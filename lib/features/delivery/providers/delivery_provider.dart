import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../orders/models/order.dart';
import '../models/delivery_partner.dart';

/// Delivery partner state
class DeliveryState {
  final DeliveryPartner partner;
  final DeliveryMetrics metrics;
  final List<DeliveryRequest> incomingRequests;
  final ActiveDelivery? activeDelivery;
  final bool isLoading;
  final bool
  isStepBusy; // true while advanceStep / completeDelivery is in-flight
  final String? errorMessage;

  const DeliveryState({
    required this.partner,
    this.metrics = const DeliveryMetrics(),
    this.incomingRequests = const [],
    this.activeDelivery,
    this.isLoading = false,
    this.isStepBusy = false,
    this.errorMessage,
  });

  DeliveryState copyWith({
    DeliveryPartner? partner,
    DeliveryMetrics? metrics,
    List<DeliveryRequest>? incomingRequests,
    ActiveDelivery? activeDelivery,
    bool? isLoading,
    bool? isStepBusy,
    String? errorMessage,
    bool clearDelivery = false,
    bool clearError = false,
  }) {
    return DeliveryState(
      partner: partner ?? this.partner,
      metrics: metrics ?? this.metrics,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      activeDelivery: clearDelivery
          ? null
          : (activeDelivery ?? this.activeDelivery),
      isLoading: isLoading ?? this.isLoading,
      isStepBusy: isStepBusy ?? this.isStepBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get hasActiveDelivery => activeDelivery != null;
  bool get hasIncomingRequest => incomingRequests.isNotEmpty;
}

/// Delivery notifier — API-backed with WebSocket + location tracking
class DeliveryNotifier extends StateNotifier<DeliveryState> {
  final ApiClient _api;
  final WebSocketService _ws;
  final LocationService _location;
  StreamSubscription? _wsSub;
  StreamSubscription? _orderUpdatesSub;
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
  final AudioPlayer _audioPlayer = AudioPlayer();

  DeliveryNotifier(this._api, this._ws, this._location)
    : super(DeliveryState(partner: DeliveryPartner.empty)) {
    _loadData();
    _subscribeToWebSocket();
    _subscribeToOrderUpdates();
    _startExpiryTimer();
  }

  /// Listen for new delivery request assignments via WebSocket (Go backend hub)
  void _subscribeToWebSocket() {
    try {
      _wsSub = _ws.deliveryRequests.listen((event) {
        try {
          // Ignore incoming delivery requests if rider already has an active delivery.
          if (state.hasActiveDelivery) {
            if (kDebugMode) {
              debugPrint(
              '[Delivery] Ignoring delivery_request — already on active delivery',
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

          // Play mkb.mp3 sound for incoming delivery request
          try {
            _audioPlayer.stop();
            _audioPlayer.play(AssetSource('mkb.mp3'));
          } catch (e) {
            if (kDebugMode) debugPrint('[Delivery] sound error: $e');
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
  /// disconnected. Checks every 10 seconds for available orders.
  void _startDeliveryRequestPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || !state.partner.isOnline || state.hasActiveDelivery) return;
      try {
        final response = await _api.get(
          '${ApiConfig.deliveryOrders}?mode=available&per_page=5',
        );
        if (response.success && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          final orders = (data['data'] as List<dynamic>?) ?? [];
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
                customerAddress: orderData['delivery_address'] as String? ?? '',
                customerLatitude: (orderData['delivery_latitude'] as num?)?.toDouble() ?? 0,
                customerLongitude: (orderData['delivery_longitude'] as num?)?.toDouble() ?? 0,
                distanceKm: (orderData['distance_km'] as num?)?.toDouble() ?? 0,
                estimatedEarning: (orderData['delivery_fee'] as num?)?.toDouble() ?? 0,
                specialInstructions: orderData['special_instructions'] as String? ?? '',
                expiresAt: DateTime.now().add(const Duration(seconds: 30)),
              );
              // Play mkb.mp3 for polling-discovered orders too
              try {
                _audioPlayer.stop();
                _audioPlayer.play(AssetSource('mkb.mp3'));
              } catch (_) {}
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

        // Only care about updates to our active delivery order
        if (state.activeDelivery == null ||
            state.activeDelivery!.request.order.id != orderId) {
          return;
        }

        final newStatus = OrderStatus.tryFromString(statusStr);
        if (newStatus == null) return;

        // If the order was cancelled or delivered externally, clear active delivery
        if (newStatus == OrderStatus.cancelled ||
            newStatus == OrderStatus.delivered) {
          state = state.copyWith(
            clearDelivery: true,
            partner: state.partner.copyWith(isOnDelivery: false),
          );
          _loadData(); // refresh dashboard
          return;
        }

        // Otherwise update the order status inside active delivery
        final updatedOrder =
            state.activeDelivery!.request.order.copyWith(status: newStatus);
        final updatedRequest = DeliveryRequest(
          id: state.activeDelivery!.request.id,
          order: updatedOrder,
          restaurantName: state.activeDelivery!.request.restaurantName,
          restaurantCuisine: state.activeDelivery!.request.restaurantCuisine,
          restaurantAddress: state.activeDelivery!.request.restaurantAddress,
          restaurantPhone: state.activeDelivery!.request.restaurantPhone,
          restaurantLatitude: state.activeDelivery!.request.restaurantLatitude,
          restaurantLongitude: state.activeDelivery!.request.restaurantLongitude,
          customerName: state.activeDelivery!.request.customerName,
          customerPhone: state.activeDelivery!.request.customerPhone,
          customerAddress: state.activeDelivery!.request.customerAddress,
          customerLatitude: state.activeDelivery!.request.customerLatitude,
          customerLongitude: state.activeDelivery!.request.customerLongitude,
          pickupDistanceKm: state.activeDelivery!.request.pickupDistanceKm,
          deliveryDistanceKm: state.activeDelivery!.request.deliveryDistanceKm,
          distanceKm: state.activeDelivery!.request.distanceKm,
          estimatedEarning: state.activeDelivery!.request.estimatedEarning,
          specialInstructions: state.activeDelivery!.request.specialInstructions,
          expiresAt: state.activeDelivery!.request.expiresAt,
        );
        state = state.copyWith(
          activeDelivery: ActiveDelivery(
            request: updatedRequest,
            currentStep: state.activeDelivery!.currentStep,
            acceptedAt: state.activeDelivery!.acceptedAt,
          ),
        );
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
    _locationTimer?.cancel();
    _locationStreamSub?.cancel();
    _expiryTimer?.cancel();
    _pollTimer?.cancel();
    _audioPlayer.dispose();
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

        // Restore active delivery from the dashboard's active_order field.
        // This covers app restarts / cold starts where in-memory state is lost.
        ActiveDelivery? restoredDelivery = state.activeDelivery;
        if (restoredDelivery == null && data['active_order'] != null) {
          restoredDelivery = _activeDeliveryFromOrder(
            data['active_order'] as Map<String, dynamic>,
          );
        }

        state = state.copyWith(
          partner: partner,
          metrics: metrics,
          activeDelivery: restoredDelivery,
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
        // Rollback
        state = state.copyWith(
          partner: state.partner.copyWith(isOnline: !newOnline),
        );
        if (newOnline) _stopDeliveryRequestPolling();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] toggleOnline error: $e');
      state = state.copyWith(
        partner: state.partner.copyWith(isOnline: !newOnline),
      );
      if (newOnline) _stopDeliveryRequestPolling();
    }
  }

  /// Accept a specific delivery request by order ID
  Future<void> acceptRequest(String orderId) async {
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

    final delivery = ActiveDelivery(
      request: request,
      acceptedAt: DateTime.now(),
    );

    state = state.copyWith(
      activeDelivery: delivery,
      partner: state.partner.copyWith(isOnDelivery: true),
      // Remove the accepted request; keep any other queued requests
      incomingRequests: state.incomingRequests
          .where((r) => r.order.id != orderId)
          .toList(),
    );

    // Push to API — MUST rollback if this fails to prevent ghost active deliveries
    // where local state shows active delivery but backend has no delivery_partner_id set,
    // causing all status updates (pickedUp/delivered) to fail with 403 and the order
    // to be reassigned to another rider (Bug: "order lost mid-way").
    try {
      final r = await _api.put('${ApiConfig.deliveryOrders}/$orderId/accept');
      if (!r.success) {
        if (kDebugMode) debugPrint('[Delivery] acceptRequest API failed: ${r.error} — rolling back');
        // Rollback: restore the request to incoming queue so rider can retry
        state = state.copyWith(
          clearDelivery: true,
          partner: state.partner.copyWith(isOnDelivery: false),
          incomingRequests: [request, ...state.incomingRequests],
        );
        return;
      }
      // Reload dashboard to sync server state (e.g. active_order, accepted_at)
      _loadData();
    } catch (e) {
      if (kDebugMode) debugPrint('[Delivery] acceptRequest error: $e — rolling back');
      // Rollback on network error too
      state = state.copyWith(
        clearDelivery: true,
        partner: state.partner.copyWith(isOnDelivery: false),
        incomingRequests: [request, ...state.incomingRequests],
      );
    }
  }

  /// Reject/skip a specific delivery request — order re-enters the queue
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

  /// Move to next delivery step
  Future<void> advanceStep() async {
    if (state.activeDelivery == null || _isStepBusy) return;
    final next = state.activeDelivery!.nextStep;
    if (next != null) {
      final previousStep = state.activeDelivery!.currentStep;
      _isStepBusy = true;
      state = state.copyWith(isStepBusy: true);

      // Optimistic update — advance immediately for snappy UX
      state = state.copyWith(
        activeDelivery: state.activeDelivery!.copyWith(currentStep: next),
      );

      // Map step to order status and push to API
      final orderId = state.activeDelivery!.request.order.id;
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
            // Revert step on API failure to keep state consistent
            if (state.activeDelivery != null) {
              state = state.copyWith(
                activeDelivery: state.activeDelivery!.copyWith(
                  currentStep: previousStep,
                ),
              );
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Delivery] advanceStep error: $e');
          // Revert step on error to keep state consistent
          if (state.activeDelivery != null) {
            state = state.copyWith(
              activeDelivery: state.activeDelivery!.copyWith(
                currentStep: previousStep,
              ),
            );
          }
        }
      }
      _isStepBusy = false;
      state = state.copyWith(isStepBusy: false);
    }
  }

  /// Complete delivery
  Future<void> completeDelivery() async {
    if (_isStepBusy) return;
    _isStepBusy = true;
    state = state.copyWith(isStepBusy: true);

    final activeDelivery = state.activeDelivery;
    final orderId = activeDelivery?.request.order.id;
    final earning = activeDelivery?.request.estimatedEarning ?? 0;
    final distance = activeDelivery?.request.distanceKm ?? 0;
    final previousPartner = state.partner;
    final previousMetrics = state.metrics;

    // Optimistic update — clear delivery and bump metrics immediately
    state = state.copyWith(
      clearDelivery: true,
      partner: state.partner.copyWith(isOnDelivery: false),
      metrics: state.metrics.copyWith(
        todayEarnings: state.metrics.todayEarnings + earning,
        todayDeliveries: state.metrics.todayDeliveries + 1,
        todayDistanceKm: state.metrics.todayDistanceKm + distance,
        weeklyEarningsCurrent: state.metrics.weeklyEarningsCurrent + earning,
        weeklyCompleted: state.metrics.weeklyCompleted + 1,
      ),
    );

    // Push delivered status to API — await so we can rollback on failure
    if (orderId != null) {
      try {
        final r = await _api.put(
          '${ApiConfig.deliveryOrders}/$orderId/status',
          body: {'status': 'delivered'},
        );
        if (!r.success) {
          if (kDebugMode) debugPrint('[Delivery] complete failed: ${r.error}');
          // Rollback — restore the active delivery and metrics
          state = state.copyWith(
            activeDelivery: activeDelivery,
            partner: previousPartner,
            metrics: previousMetrics,
            isStepBusy: false,
          );
          _isStepBusy = false;
          return;
        }
        // Reload dashboard to sync metrics and clear active_order
        _loadData();
      } catch (e) {
        if (kDebugMode) debugPrint('[Delivery] complete error: $e');
        // Rollback — restore the active delivery and metrics
        state = state.copyWith(
          activeDelivery: activeDelivery,
          partner: previousPartner,
          metrics: previousMetrics,
          isStepBusy: false,
        );
        _isStepBusy = false;
        return;
      }
    }
    _isStepBusy = false;
    state = state.copyWith(isStepBusy: false);
  }

  /// Report an issue with current delivery
  Future<void> reportIssue(String reason, String details) async {
    if (state.activeDelivery == null) return;
    final orderId = state.activeDelivery!.request.order.id;
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
    return DeliveryNotifier(api, ws, location);
  },
);
