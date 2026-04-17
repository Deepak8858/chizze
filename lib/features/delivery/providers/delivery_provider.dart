import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../orders/models/order.dart';
import '../models/delivery_partner.dart';

/// Delivery partner state — supports up to 5 simultaneous active deliveries
class DeliveryState {
  final DeliveryPartner partner;
  final DeliveryMetrics metrics;
  final List<DeliveryRequest> incomingRequests;
  final List<ActiveDelivery> activeDeliveries;
  final bool isLoading;
  final bool isStepBusy; // true while advanceStep / completeDelivery is in-flight
  final String? errorMessage;

  const DeliveryState({
    required this.partner,
    this.metrics = const DeliveryMetrics(),
    this.incomingRequests = const [],
    this.activeDeliveries = const [],
    this.isLoading = false,
    this.isStepBusy = false,
    this.errorMessage,
  });

  DeliveryState copyWith({
    DeliveryPartner? partner,
    DeliveryMetrics? metrics,
    List<DeliveryRequest>? incomingRequests,
    List<ActiveDelivery>? activeDeliveries,
    bool? isLoading,
    bool? isStepBusy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DeliveryState(
      partner: partner ?? this.partner,
      metrics: metrics ?? this.metrics,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      activeDeliveries: activeDeliveries ?? this.activeDeliveries,
      isLoading: isLoading ?? this.isLoading,
      isStepBusy: isStepBusy ?? this.isStepBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get hasActiveDelivery => activeDeliveries.isNotEmpty;
  bool get hasIncomingRequest => incomingRequests.isNotEmpty;
  int get activeDeliveryCount => activeDeliveries.length;
  /// True when rider can still accept more orders (max 5)
  bool get canAcceptMoreOrders => activeDeliveries.length < 5;
  /// Returns the first active delivery (backward compat)
  ActiveDelivery? get activeDelivery =>
      activeDeliveries.isNotEmpty ? activeDeliveries.first : null;
}

/// Delivery notifier — API-backed with WebSocket + Appwrite Realtime + location tracking
class DeliveryNotifier extends StateNotifier<DeliveryState> {
  final ApiClient _api;
  final WebSocketService _ws;
  final LocationService _location;
  final RealtimeService _realtime;
  StreamSubscription? _wsSub;
  StreamSubscription? _orderUpdatesSub;
  StreamSubscription? _realtimeSub; // Appwrite Realtime fallback for delivery_requests
  StreamSubscription? _locationStreamSub;
  Timer? _locationTimer;
  Timer? _expiryTimer; // auto-rejects expired delivery requests
  Timer? _pollTimer;   // polling fallback for delivery requests
  bool _isLoadingGuard = false;
  bool _pendingReload = false;
  bool _isStepBusy =
      false; // guards advanceStep / completeDelivery from double-taps
  double _lastHeading = 0.0;
  double _lastSpeed = 0.0;
  String? _currentUserId; // cached for Realtime filtering

  DeliveryNotifier(this._api, this._ws, this._location, this._realtime)
    : super(DeliveryState(partner: DeliveryPartner.empty)) {
    _loadData();
    _subscribeToWebSocket();
    _subscribeToOrderUpdates();
    _subscribeToRealtimeDeliveryRequests();
    _startExpiryTimer();
  }

  /// Subscribe to Appwrite Realtime for delivery_requests collection.
  /// This is the most reliable channel — works even when WS is disconnected.
  /// When a delivery_requests document is created with rider_id == this rider,
  /// it triggers the same flow as a WS delivery_request event.
  void _subscribeToRealtimeDeliveryRequests() {
    try {
      final channel = RealtimeChannels.deliveryRequestsChannel();
      _realtimeSub = _realtime.subscribe(channel).listen((event) {
        if (!mounted || event.type != RealtimeEventType.create) return;
        final data = event.data;

        // Filter: only process requests for this rider
        final riderId = data['rider_id'] as String? ?? '';
        if (_currentUserId == null || riderId != _currentUserId) return;

        // Ignore if already at max capacity (5 orders)
        if (!state.canAcceptMoreOrders) return;

        final orderId = data['order_id'] as String? ?? '';
        if (orderId.isEmpty) return;
        if (state.incomingRequests.any((r) => r.order.id == orderId)) return;

        if (kDebugMode) debugPrint('[Delivery] Realtime delivery_request for order $orderId');

        // Build a minimal DeliveryRequest from the Appwrite document data.
        // The WS payload has full order details, the Realtime doc has less,
        // so we trigger a full dashboard reload which will populate active_order.

        // Reload dashboard — this will pick up the pending delivery request
        // and populate state.incomingRequests via polling
        _loadData();

        // Also force-start polling if not running
        _startDeliveryRequestPolling();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] Realtime subscribe error: $e');
    }
  }

  /// Listen for new delivery request assignments via WebSocket (Go backend hub)
  void _subscribeToWebSocket() {
    try {
      _wsSub = _ws.deliveryRequests.listen((event) {
        try {
          // Ignore incoming delivery requests if rider is already at max capacity (5 orders).
          if (!state.canAcceptMoreOrders) {
            if (kDebugMode) {
              debugPrint(
              '[Delivery] Ignoring delivery_request — at max capacity (${state.activeDeliveryCount}/5)',
            );
            }
            return;
          }

          final request = DeliveryRequest.fromMap(event.payload);

          // Skip if an identical request is already queued (same order)
          if (state.incomingRequests.any(
            (r) => r.order.id == request.order.id,
          )) {
            if (kDebugMode) {
              debugPrint(
              '[Delivery] Ignoring duplicate delivery_request for same order',
            );
            }
            return;
          }

          // Append to the queue so multiple orders are visible at once
          state = state.copyWith(
            incomingRequests: [...state.incomingRequests, request],
          );
        } catch (e) {
          if (kDebugMode) debugPrint('[Delivery] WS delivery_request parse error: $e');
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] WS subscribe error: $e');
    }
  }

  /// Periodically check for expired delivery requests and auto-reject them.
  /// This is CRITICAL: without this, when a rider ignores a request and the
  /// 30-second countdown expires, the backend Redis locks are never cleared,
  /// blocking the order from being reassigned for up to 2 minutes.
  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final expired = state.incomingRequests.where((r) => r.hasExpired).toList();
      for (final req in expired) {
        if (kDebugMode) {
          debugPrint('[Delivery] Auto-rejecting expired request for order ${req.order.id}');
        }
        // Tell backend to clear Redis locks so order can be reassigned
        _rejectOrderSilently(req.order.id);
      }
      if (expired.isNotEmpty) {
        state = state.copyWith(
          incomingRequests: state.incomingRequests
              .where((r) => !r.hasExpired)
              .toList(),
        );
      }
    });
  }

  /// Silently reject an order without throwing errors. Used by the expiry timer.
  Future<void> _rejectOrderSilently(String orderId) async {
    try {
      await _api.put('${ApiConfig.deliveryOrders}/$orderId/reject');
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] Auto-reject error: $e');
    }
  }

  /// Poll for pending delivery requests as a fallback when WebSocket is
  /// disconnected. 5s interval keeps rider-side order discovery snappy
  /// enough that WS disconnects during a commute don't leave them idle
  /// for 10+ seconds while orders pile up at the matcher. Slower than the
  /// 8s matcher tick so we don't hammer the backend when WS is healthy;
  /// the matcher clears pending_delivery the moment it broadcasts, so
  /// faster polling doesn't produce duplicate displays.
  void _startDeliveryRequestPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || !state.partner.isOnline || state.hasActiveDelivery) return;
      try {
        final response = await _api.get(
          '${ApiConfig.deliveryOrders}?mode=available&per_page=5',
        );
        if (response.success && response.data != null) {
          // Paginated backend responses unwrap to a List (not a Map). Earlier
          // versions cast to Map and swallowed a TypeError, so riders never
          // saw orders when WebSocket was down — matcher looped forever.
          final raw = response.data;
          final orders = raw is List
              ? raw
              : raw is Map<String, dynamic>
                  ? ((raw['data'] as List<dynamic>?) ?? const [])
                  : const [];
          // Don't show orders that are already in the incoming requests queue
          final existingIds = state.incomingRequests.map((r) => r.order.id).toSet();
          for (final orderData in orders) {
            final orderId = orderData['\$id'] as String? ?? '';
            if (orderId.isEmpty || existingIds.contains(orderId)) continue;
            // Only add if not already shown
            try {
              final order = Order.fromMap(orderData as Map<String, dynamic>);
              final request = DeliveryRequest(
                id: orderId,
                order: order,
                restaurantName: orderData['restaurant_name'] as String? ?? '',
                restaurantAddress: orderData['restaurant_address'] as String? ?? '',
                restaurantLatitude: (orderData['restaurant_latitude'] as num?)?.toDouble() ?? 0,
                restaurantLongitude: (orderData['restaurant_longitude'] as num?)?.toDouble() ?? 0,
                customerName: orderData['customer_name'] as String? ?? 'Customer',
                customerPhone: orderData['customer_phone'] as String? ?? '',
                customerAddress: orderData['delivery_address'] as String? ?? '',
                customerLatitude: (orderData['delivery_latitude'] as num?)?.toDouble() ?? 0,
                customerLongitude: (orderData['delivery_longitude'] as num?)?.toDouble() ?? 0,
                distanceKm: (orderData['distance_km'] as num?)?.toDouble() ?? 0,
                estimatedEarning: (orderData['delivery_fee'] as num?)?.toDouble() ?? 0,
                specialInstructions: orderData['special_instructions'] as String? ?? '',
                expiresAt: DateTime.now().add(const Duration(seconds: 30)),
              );
              state = state.copyWith(
                incomingRequests: [...state.incomingRequests, request],
              );
              existingIds.add(orderId);
            } catch (e) {
              if (kDebugMode) debugPrint('[Delivery] poll parse error: $e');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Delivery] poll error: $e');
      }
    });
  }

  void _stopDeliveryRequestPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Listen for order_update events via WebSocket so the delivery partner UI
  /// stays in sync when the restaurant or system changes order status (e.g.
  /// cancelled). This also clears the active delivery when the order is
  /// delivered/cancelled by another source.
  void _subscribeToOrderUpdates() {
    try {
      _orderUpdatesSub = _ws.orderUpdates.listen((event) {
        final orderId = event.orderId;
        final statusStr = event.status;
        if (orderId == null || statusStr == null) return;

        // Find the matching active delivery by order ID
        final idx = state.activeDeliveries.indexWhere(
          (d) => d.request.order.id == orderId,
        );
        if (idx == -1) return;

        final delivery = state.activeDeliveries[idx];
        final newStatus = OrderStatus.tryFromString(statusStr);
        if (newStatus == null) return;

        // If cancelled or delivered externally, remove from active deliveries
        if (newStatus == OrderStatus.cancelled ||
            newStatus == OrderStatus.delivered) {
          final updated = state.activeDeliveries
              .where((d) => d.request.order.id != orderId)
              .toList();
          state = state.copyWith(
            activeDeliveries: updated,
            partner: state.partner.copyWith(isOnDelivery: updated.isNotEmpty),
          );
          _loadData(); // refresh dashboard metrics
          return;
        }

        // Otherwise update the order status inside this specific active delivery
        final updatedOrder =
            delivery.request.order.copyWith(status: newStatus);
        final updatedRequest = DeliveryRequest(
          id: delivery.request.id,
          order: updatedOrder,
          restaurantName: delivery.request.restaurantName,
          restaurantCuisine: delivery.request.restaurantCuisine,
          restaurantAddress: delivery.request.restaurantAddress,
          restaurantPhone: delivery.request.restaurantPhone,
          restaurantLatitude: delivery.request.restaurantLatitude,
          restaurantLongitude: delivery.request.restaurantLongitude,
          customerName: delivery.request.customerName,
          customerPhone: delivery.request.customerPhone,
          customerAddress: delivery.request.customerAddress,
          customerLatitude: delivery.request.customerLatitude,
          customerLongitude: delivery.request.customerLongitude,
          pickupDistanceKm: delivery.request.pickupDistanceKm,
          deliveryDistanceKm: delivery.request.deliveryDistanceKm,
          distanceKm: delivery.request.distanceKm,
          estimatedEarning: delivery.request.estimatedEarning,
          specialInstructions: delivery.request.specialInstructions,
          expiresAt: delivery.request.expiresAt,
        );
        final updatedDeliveries = List<ActiveDelivery>.from(state.activeDeliveries);
        updatedDeliveries[idx] = ActiveDelivery(
          request: updatedRequest,
          currentStep: delivery.currentStep,
          acceptedAt: delivery.acceptedAt,
        );
        state = state.copyWith(activeDeliveries: updatedDeliveries);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] WS order updates subscribe error: $e');
    }
  }

  /// Start real GPS location tracking when online
  Future<void> _startLocationTracking() async {
    _locationTimer?.cancel();
    _locationStreamSub?.cancel();

    // Pre-check permissions before subscribing (Fixes FLUTTER-1)
    try {
      final hasPermission = await _location.checkPermissions();
      if (!hasPermission || !mounted) {
        if (kDebugMode) debugPrint('[Delivery] Location permission not granted — skipping tracking');
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] Permission check failed: $e');
      return;
    }

    // Use continuous position stream from geolocator (10m distance filter)
    _locationStreamSub = _location.getPositionStream().listen(
      (loc) {
        if (!mounted) return;
        // Update local state
        _lastHeading = loc.heading;
        _lastSpeed = loc.speed;
        state = state.copyWith(
          partner: state.partner.copyWith(
            currentLatitude: loc.latitude,
            currentLongitude: loc.longitude,
          ),
        );
      },
      onError: (error) {
        // Gracefully handle location permission denied / GPS errors (Fixes FLUTTER-1)
        if (kDebugMode) debugPrint('[Delivery] Location stream error: $error');
        _stopLocationTracking();
      },
    );

    // Push to backend every 15 seconds
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pushLocationUpdate();
    });
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _locationStreamSub?.cancel();
    _locationStreamSub = null;
  }

  Future<void> _pushLocationUpdate() async {
    if (!mounted) return; // Guard against disposed state

    // Validate both coordinates before pushing (Fixes FLUTTER-2/3)
    if (state.partner.currentLatitude == 0 && state.partner.currentLongitude == 0) {
      // Try to get a one-shot position if stream hasn't delivered yet
      try {
        final loc = await _location.getCurrentPosition();
        if (!mounted) return;
        state = state.copyWith(
          partner: state.partner.copyWith(
            currentLatitude: loc.latitude,
            currentLongitude: loc.longitude,
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Delivery] one-shot location error: $e');
        return;
      }
    }

    // Skip if we still don't have valid coordinates
    if (state.partner.currentLatitude == 0 && state.partner.currentLongitude == 0) return;

    try {
      final r = await _api.put(
        ApiConfig.deliveryLocation,
        body: {
          'latitude': state.partner.currentLatitude,
          'longitude': state.partner.currentLongitude,
          'heading': _lastHeading,
          'speed': _lastSpeed,
        },
      );
      if (!r.success) {
        if (kDebugMode) debugPrint('[Delivery] location update failed: ${r.error}');
      }
    } catch (e) {
      // Don't rethrow — the timer will retry in 15s anyway
      if (kDebugMode) debugPrint('[Delivery] location update error: $e');
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _orderUpdatesSub?.cancel();
    _realtimeSub?.cancel();
    _locationTimer?.cancel();
    _locationStreamSub?.cancel();
    _expiryTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isLoadingGuard) {
      _pendingReload = true;
      return;
    }
    _isLoadingGuard = true;
    _pendingReload = false;
    state = state.copyWith(isLoading: true);

    try {
      final response = await _api.get(ApiConfig.deliveryDashboard);
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final partner = DeliveryPartner.fromDashboard(data);
        final metrics = DeliveryMetrics.fromDashboard(data);

        // Cache the user ID for Realtime filtering
        if (_currentUserId == null && data['user_id'] != null) {
          _currentUserId = data['user_id'] as String?;
        }

        // Restore active deliveries from the dashboard.
        // Priority: active_orders (multi-order array) > active_order (compat) > keep in-memory state.
        // This covers app restarts / cold starts where in-memory state is lost.
        List<ActiveDelivery> restoredDeliveries = state.activeDeliveries;
        if (restoredDeliveries.isEmpty) {
          if (data['active_orders'] is List) {
            final orders = data['active_orders'] as List<dynamic>;
            restoredDeliveries = orders
                .map((o) => _activeDeliveryFromOrder(o as Map<String, dynamic>))
                .whereType<ActiveDelivery>()
                .toList();
          } else if (data['active_order'] != null) {
            // Backward compat: single active_order from older backend
            final d = _activeDeliveryFromOrder(
              data['active_order'] as Map<String, dynamic>,
            );
            if (d != null) restoredDeliveries = [d];
          }
        }

        state = state.copyWith(
          partner: partner,
          metrics: metrics,
          activeDeliveries: restoredDeliveries,
          isLoading: false,
          clearError: true,
        );

        if (partner.isOnline) {
          _startLocationTracking();
          _startDeliveryRequestPolling();
        }
        _isLoadingGuard = false;

        // If another load was requested while we were fetching, run it now
        if (_pendingReload) {
          _pendingReload = false;
          _loadData();
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] _loadData error: $e');
    }

    // API failed — show empty state
    state = state.copyWith(
      metrics: const DeliveryMetrics(),
      isLoading: false,
    );
    _isLoadingGuard = false;

    if (_pendingReload) {
      _pendingReload = false;
      _loadData();
    }
  }

  /// Build an [ActiveDelivery] from the raw order document returned by the
  /// dashboard's `active_order` field so that the rider UI is restored on
  /// app restart.
  ActiveDelivery? _activeDeliveryFromOrder(Map<String, dynamic> orderData) {
    try {
      final order = Order.fromMap(orderData);
      final status = orderData['status'] as String? ?? '';

      // Determine delivery step from current order status
      DeliveryStep step;
      switch (status) {
        case 'pickedUp':
          step = DeliveryStep.goToCustomer;
        case 'outForDelivery':
          step = DeliveryStep.deliver;
        default:
          // "ready" or anything before pickup
          step = DeliveryStep.goToRestaurant;
      }

      final request = DeliveryRequest(
        id: order.id,
        order: order,
        restaurantName:
            orderData['restaurant_name'] as String? ?? order.restaurantName,
        restaurantAddress: orderData['restaurant_address'] as String? ?? '',
        restaurantPhone: orderData['restaurant_phone'] as String? ?? '',
        restaurantLatitude:
            (orderData['restaurant_latitude'] as num?)?.toDouble() ?? 0,
        restaurantLongitude:
            (orderData['restaurant_longitude'] as num?)?.toDouble() ?? 0,
        customerName: orderData['customer_name'] as String? ?? 'Customer',
        customerPhone: orderData['customer_phone'] as String? ?? '',
        customerAddress: orderData['customer_address'] as String? ?? '',
        customerLatitude:
            (orderData['customer_latitude'] as num?)?.toDouble() ?? 0,
        customerLongitude:
            (orderData['customer_longitude'] as num?)?.toDouble() ?? 0,
        distanceKm: (orderData['distance_km'] as num?)?.toDouble() ?? 0,
        estimatedEarning: (orderData['delivery_fee'] as num?)?.toDouble() ?? 0,
        specialInstructions: orderData['special_instructions'] as String? ?? '',
        expiresAt: DateTime.now().add(const Duration(minutes: 60)),
      );

      final acceptedAtStr = orderData['accepted_at'] as String?;
      final acceptedAt =
          DateTime.tryParse(acceptedAtStr ?? '') ?? DateTime.now();

      return ActiveDelivery(
        request: request,
        currentStep: step,
        acceptedAt: acceptedAt,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] Failed to restore active delivery: $e');
      return null;
    }
  }

  /// Refresh dashboard data
  Future<void> refresh() => _loadData();

  /// Toggle online/offline
  Future<void> toggleOnline() async {
    final newOnline = !state.partner.isOnline;
    state = state.copyWith(
      partner: state.partner.copyWith(isOnline: newOnline),
    );

    if (!newOnline) {
      state = state.copyWith(incomingRequests: []);
      _stopLocationTracking();
      _stopDeliveryRequestPolling();
    } else {
      _startLocationTracking();
      // Push location immediately so rider appears in Redis geo set right away
      // instead of waiting up to 15 seconds for the periodic timer.
      _pushLocationUpdate();
      // Start polling as a fallback in case WebSocket is disconnected
      _startDeliveryRequestPolling();
    }

    // Push to API with rollback on failure
    try {
      // Include the rider's current GPS so the backend can immediately add
      // them to the Redis geo set (no 15-second wait for UpdateLocation).
      final body = <String, dynamic>{'is_online': newOnline};
      if (newOnline) {
        final pos = _location.lastPosition;
        if (pos != null && pos.latitude != 0 && pos.longitude != 0) {
          body['latitude'] = pos.latitude;
          body['longitude'] = pos.longitude;
        }
      }
      final response = await _api.put(
        ApiConfig.deliveryStatus,
        body: body,
      );
      if (!response.success) {
        // Rollback: also tear down location tracking started optimistically above.
        // Without this, the rider's phone keeps streaming GPS while the backend
        // thinks they're offline — battery drain + zombie geo entries.
        state = state.copyWith(
          partner: state.partner.copyWith(isOnline: !newOnline),
        );
        if (newOnline) {
          _stopLocationTracking();
          _stopDeliveryRequestPolling();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] toggleOnline error: $e');
      state = state.copyWith(
        partner: state.partner.copyWith(isOnline: !newOnline),
      );
      if (newOnline) {
        _stopLocationTracking();
        _stopDeliveryRequestPolling();
      }
    }
  }

  /// Accept a specific delivery request by order ID.
  /// Appends to the activeDeliveries list (supports up to 5 simultaneous orders).
  Future<void> acceptRequest(String orderId) async {
    if (!state.canAcceptMoreOrders) {
      if (kDebugMode) debugPrint('[Delivery] acceptRequest: at max capacity (5 orders)');
      return;
    }
    final index = state.incomingRequests.indexWhere(
      (r) => r.order.id == orderId,
    );
    if (index == -1) {
      if (kDebugMode) {
        debugPrint('[Delivery] acceptRequest: orderId $orderId not found in queue');
      }
      return;
    }
    final request = state.incomingRequests[index];
    final delivery = ActiveDelivery(request: request, acceptedAt: DateTime.now());

    // Optimistic update: append to active deliveries, remove from incoming
    state = state.copyWith(
      activeDeliveries: [...state.activeDeliveries, delivery],
      partner: state.partner.copyWith(isOnDelivery: true),
      incomingRequests: state.incomingRequests
          .where((r) => r.order.id != orderId)
          .toList(),
    );

    // Push to API — MUST rollback if this fails to prevent ghost active deliveries.
    try {
      final r = await _api.put('${ApiConfig.deliveryOrders}/$orderId/accept');
      if (!r.success) {
        if (kDebugMode) debugPrint('[Delivery] acceptRequest API failed: ${r.error} — rolling back');
        // Rollback: remove from active, re-add to incoming queue
        state = state.copyWith(
          activeDeliveries: state.activeDeliveries
              .where((d) => d.request.order.id != orderId)
              .toList(),
          partner: state.partner.copyWith(
            isOnDelivery: state.activeDeliveries
                .where((d) => d.request.order.id != orderId)
                .isNotEmpty,
          ),
          incomingRequests: [request, ...state.incomingRequests],
        );
        return;
      }
      // Reload dashboard to sync server state (accepted_at, etc.)
      _loadData();
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] acceptRequest error: $e — rolling back');
      state = state.copyWith(
        activeDeliveries: state.activeDeliveries
            .where((d) => d.request.order.id != orderId)
            .toList(),
        partner: state.partner.copyWith(
          isOnDelivery: state.activeDeliveries
              .where((d) => d.request.order.id != orderId)
              .isNotEmpty,
        ),
        incomingRequests: [request, ...state.incomingRequests],
      );
    }
  }

  /// Reject/skip a specific delivery request — order re-enters the matcher queue
  Future<void> rejectRequest(String orderId) async {
    final previousRequests = state.incomingRequests;
    state = state.copyWith(
      incomingRequests: state.incomingRequests
          .where((r) => r.order.id != orderId)
          .toList(),
    );

    try {
      await _api.put('${ApiConfig.deliveryOrders}/$orderId/reject');
    } catch (e) {
      // Rollback — re-insert the removed request so client/server stay consistent
      state = state.copyWith(incomingRequests: previousRequests);
      if (kDebugMode) debugPrint('[Delivery] rejectRequest error: $e');
    }
  }

  /// Move to next delivery step for a specific order.
  Future<void> advanceStep(String orderId) async {
    final idx = state.activeDeliveries.indexWhere(
      (d) => d.request.order.id == orderId,
    );
    if (idx == -1 || _isStepBusy) return;

    final delivery = state.activeDeliveries[idx];
    final next = delivery.nextStep;
    if (next == null) return;

    final previousStep = delivery.currentStep;
    _isStepBusy = true;
    state = state.copyWith(isStepBusy: true);

    // Optimistic update — advance immediately for snappy UX
    final optimisticDeliveries = List<ActiveDelivery>.from(state.activeDeliveries);
    optimisticDeliveries[idx] = delivery.copyWith(currentStep: next);
    state = state.copyWith(activeDeliveries: optimisticDeliveries);

    // Map step to API status
    String? apiStatus;
    switch (next) {
      case DeliveryStep.pickUp:
        apiStatus = 'pickedUp';
      case DeliveryStep.goToCustomer:
        apiStatus = 'outForDelivery';
      default:
        break;
    }
    if (apiStatus != null) {
      try {
        final r = await _api.put(
          '${ApiConfig.deliveryOrders}/$orderId/status',
          body: {'status': apiStatus},
        );
        if (!r.success) {
          if (kDebugMode) debugPrint('[Delivery] advanceStep failed: ${r.error}');
          // Revert this specific delivery's step
          final revertIdx = state.activeDeliveries.indexWhere(
            (d) => d.request.order.id == orderId,
          );
          if (mounted && revertIdx != -1) {
            final reverted = List<ActiveDelivery>.from(state.activeDeliveries);
            reverted[revertIdx] = reverted[revertIdx].copyWith(currentStep: previousStep);
            state = state.copyWith(activeDeliveries: reverted);
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Delivery] advanceStep error: $e');
        final revertIdx = state.activeDeliveries.indexWhere(
          (d) => d.request.order.id == orderId,
        );
        if (mounted && revertIdx != -1) {
          final reverted = List<ActiveDelivery>.from(state.activeDeliveries);
          reverted[revertIdx] = reverted[revertIdx].copyWith(currentStep: previousStep);
          state = state.copyWith(activeDeliveries: reverted);
        }
      }
    }
    _isStepBusy = false;
    state = state.copyWith(isStepBusy: false);
  }

  /// Complete a specific delivery by order ID.
  Future<void> completeDelivery(String orderId) async {
    if (_isStepBusy) return;
    _isStepBusy = true;
    state = state.copyWith(isStepBusy: true);

    final idx = state.activeDeliveries.indexWhere(
      (d) => d.request.order.id == orderId,
    );
    if (idx == -1) {
      _isStepBusy = false;
      state = state.copyWith(isStepBusy: false);
      return;
    }

    final delivery = state.activeDeliveries[idx];
    final earning = delivery.request.estimatedEarning;
    final distance = delivery.request.distanceKm;
    final previousDeliveries = List<ActiveDelivery>.from(state.activeDeliveries);
    final previousPartner = state.partner;
    final previousMetrics = state.metrics;

    // Optimistic: remove this delivery and bump metrics
    final updatedDeliveries = state.activeDeliveries
        .where((d) => d.request.order.id != orderId)
        .toList();
    state = state.copyWith(
      activeDeliveries: updatedDeliveries,
      partner: state.partner.copyWith(isOnDelivery: updatedDeliveries.isNotEmpty),
      metrics: state.metrics.copyWith(
        todayEarnings: state.metrics.todayEarnings + earning,
        todayDeliveries: state.metrics.todayDeliveries + 1,
        todayDistanceKm: state.metrics.todayDistanceKm + distance,
        weeklyEarningsCurrent: state.metrics.weeklyEarningsCurrent + earning,
        weeklyCompleted: state.metrics.weeklyCompleted + 1,
      ),
    );

    // Push delivered status to API
    try {
      final r = await _api.put(
        '${ApiConfig.deliveryOrders}/$orderId/status',
        body: {'status': 'delivered'},
      );
      if (!r.success) {
        if (kDebugMode) debugPrint('[Delivery] completeDelivery failed: ${r.error}');
        // Rollback
        state = state.copyWith(
          activeDeliveries: previousDeliveries,
          partner: previousPartner,
          metrics: previousMetrics,
          isStepBusy: false,
        );
        _isStepBusy = false;
        return;
      }
      // Reload dashboard to sync metrics
      _loadData();
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] completeDelivery error: $e');
      state = state.copyWith(
        activeDeliveries: previousDeliveries,
        partner: previousPartner,
        metrics: previousMetrics,
        isStepBusy: false,
      );
      _isStepBusy = false;
      return;
    }
    _isStepBusy = false;
    state = state.copyWith(isStepBusy: false);
  }

  /// Report an issue with a specific delivery order
  Future<void> reportIssue(String orderId, String reason, String details) async {
    _api
        .post(
          '${ApiConfig.deliveryOrders}/$orderId/report',
          body: {'reason': reason, 'details': details},
        )
        .then((r) {
      if (!r.success) if (kDebugMode) debugPrint('[Delivery] reportIssue failed: ${r.error}');
    }).catchError((e) {
      if (kDebugMode) debugPrint('[Delivery] reportIssue error: $e');
    });
  }

  /// Update partner location (called externally e.g., from GPS)
  void updateLocation(double lat, double lng) {
    state = state.copyWith(
      partner: state.partner.copyWith(
        currentLatitude: lat,
        currentLongitude: lng,
      ),
    );
  }

  /// Update delivery partner profile (vehicle, bank details)
  Future<bool> updateProfile({
    String? vehicleType,
    String? vehicleNumber,
    String? bankAccountId,
    String? bankAccountHolder,
    String? ifsc,
    String? upiId,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (vehicleType != null) body['vehicle_type'] = vehicleType;
      if (vehicleNumber != null) body['vehicle_number'] = vehicleNumber;
      if (bankAccountId != null) body['bank_account_id'] = bankAccountId;
      if (bankAccountHolder != null) {
        body['bank_account_holder'] = bankAccountHolder;
      }
      if (ifsc != null) body['ifsc'] = ifsc;
      if (upiId != null) body['upi_id'] = upiId;

      if (body.isEmpty) return false;

      final response = await _api.put(ApiConfig.deliveryProfile, body: body);
      if (response.success) {
        // Update local state
        state = state.copyWith(
          partner: state.partner.copyWith(
            vehicleType: vehicleType ?? state.partner.vehicleType,
            vehicleNumber: vehicleNumber ?? state.partner.vehicleNumber,
          ),
        );
        return true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] updateProfile error: $e');
    }
    return false;
  }

  /// Fetch performance metrics
  Future<Map<String, dynamic>?> fetchPerformance() async {
    try {
      final response = await _api.get(ApiConfig.deliveryPerformance);
      if (response.success && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] fetchPerformance error: $e');
    }
    return null;
  }
}

/// Delivery provider
final deliveryProvider = StateNotifierProvider<DeliveryNotifier, DeliveryState>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    final ws = ref.watch(webSocketServiceProvider);
    final location = ref.watch(locationServiceProvider);
    final realtime = ref.watch(realtimeServiceProvider);
    return DeliveryNotifier(api, ws, location, realtime);
  },
);
