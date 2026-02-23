import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/realtime_service.dart';
import '../models/delivery_partner.dart';

/// Delivery partner state
class DeliveryState {
  final DeliveryPartner partner;
  final DeliveryMetrics metrics;
  final DeliveryRequest? incomingRequest;
  final ActiveDelivery? activeDelivery;
  final bool isLoading;
  final String? errorMessage;

  const DeliveryState({
    required this.partner,
    this.metrics = const DeliveryMetrics(),
    this.incomingRequest,
    this.activeDelivery,
    this.isLoading = false,
    this.errorMessage,
  });

  DeliveryState copyWith({
    DeliveryPartner? partner,
    DeliveryMetrics? metrics,
    DeliveryRequest? incomingRequest,
    ActiveDelivery? activeDelivery,
    bool? isLoading,
    String? errorMessage,
    bool clearRequest = false,
    bool clearDelivery = false,
    bool clearError = false,
  }) {
    return DeliveryState(
      partner: partner ?? this.partner,
      metrics: metrics ?? this.metrics,
      incomingRequest: clearRequest
          ? null
          : (incomingRequest ?? this.incomingRequest),
      activeDelivery: clearDelivery
          ? null
          : (activeDelivery ?? this.activeDelivery),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get hasActiveDelivery => activeDelivery != null;
  bool get hasIncomingRequest =>
      incomingRequest != null && !incomingRequest!.hasExpired;
}

/// Delivery notifier — API-backed with Realtime + location tracking
class DeliveryNotifier extends StateNotifier<DeliveryState> {
  final ApiClient _api;
  final RealtimeService _realtime;
  final LocationService _location;
  StreamSubscription? _realtimeSub;
  StreamSubscription? _locationStreamSub;
  Timer? _locationTimer;
  bool _isLoadingGuard = false;

  DeliveryNotifier(this._api, this._realtime, this._location)
    : super(DeliveryState(partner: DeliveryPartner.empty)) {
    _loadData();
    _subscribeToRealtime();
  }

  /// Listen for new delivery request assignments in real-time
  void _subscribeToRealtime() {
    try {
      final channel = RealtimeChannels.deliveryRequestsChannel();
      _realtimeSub = _realtime.subscribe(channel).listen((event) {
        if (event.type == RealtimeEventType.create) {
          try {
            final request = DeliveryRequest.fromMap(event.data);
            state = state.copyWith(incomingRequest: request);
          } catch (_) {
            // Malformed event data — ignore
          }
        }
      });
    } catch (_) {} // Realtime not available
  }

  /// Start real GPS location tracking when online
  void _startLocationTracking() {
    _locationTimer?.cancel();
    _locationStreamSub?.cancel();

    // Use continuous position stream from geolocator (10m distance filter)
    _locationStreamSub = _location.getPositionStream().listen((loc) {
      // Update local state
      state = state.copyWith(
        partner: state.partner.copyWith(
          currentLatitude: loc.latitude,
          currentLongitude: loc.longitude,
        ),
      );
    });

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
    // Use real GPS coordinates from state (updated by position stream)
    if (state.partner.currentLatitude == 0) {
      // Try to get a one-shot position if stream hasn't delivered yet
      try {
        final loc = await _location.getCurrentPosition();
        state = state.copyWith(
          partner: state.partner.copyWith(
            currentLatitude: loc.latitude,
            currentLongitude: loc.longitude,
          ),
        );
      } catch (_) {
        return;
      }
    }
    _api
        .put(
          ApiConfig.deliveryLocation,
          body: {
            'latitude': state.partner.currentLatitude,
            'longitude': state.partner.currentLongitude,
            'heading': 0.0,
            'speed': 0.0,
          },
        )
        .then((r) {
      if (!r.success) debugPrint('[Delivery] location update failed: ${r.error}');
    }).catchError((e) {
      debugPrint('[Delivery] location update error: $e');
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _locationTimer?.cancel();
    _locationStreamSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isLoadingGuard) return;
    _isLoadingGuard = true;
    state = state.copyWith(isLoading: true);

    try {
      final response = await _api.get(ApiConfig.deliveryDashboard);
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final partner = DeliveryPartner.fromDashboard(data);
        final metrics = DeliveryMetrics.fromDashboard(data);

        state = state.copyWith(
          partner: partner,
          metrics: metrics,
          isLoading: false,
          clearError: true,
        );

        if (partner.isOnline) _startLocationTracking();
        _isLoadingGuard = false;
        return;
      }
    } catch (_) {}

    // No mock fallback — show empty state
    state = state.copyWith(
      metrics: const DeliveryMetrics(),
      isLoading: false,
    );
    _isLoadingGuard = false;
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
      state = state.copyWith(clearRequest: true);
      _stopLocationTracking();
    } else {
      _startLocationTracking();
    }

    // Push to API with rollback on failure
    try {
      final response = await _api.put(
        ApiConfig.deliveryStatus,
        body: {'is_online': newOnline},
      );
      if (!response.success) {
        // Rollback
        state = state.copyWith(
          partner: state.partner.copyWith(isOnline: !newOnline),
        );
      }
    } catch (_) {
      state = state.copyWith(
        partner: state.partner.copyWith(isOnline: !newOnline),
      );
    }
  }

  /// Accept a delivery request
  Future<void> acceptRequest() async {
    if (state.incomingRequest == null) return;

    final orderId = state.incomingRequest!.order.id;
    final delivery = ActiveDelivery(
      request: state.incomingRequest!,
      acceptedAt: DateTime.now(),
    );

    state = state.copyWith(
      activeDelivery: delivery,
      partner: state.partner.copyWith(isOnDelivery: true),
      clearRequest: true,
    );

    // Push to API
    try {
      await _api.put('${ApiConfig.deliveryOrders}/$orderId/accept');
    } catch (_) {
      // Accept already optimistic — don't rollback UI
    }
  }

  /// Reject/skip a delivery request
  void rejectRequest() {
    state = state.copyWith(clearRequest: true);
  }

  /// Move to next delivery step
  Future<void> advanceStep() async {
    if (state.activeDelivery == null) return;
    final next = state.activeDelivery!.nextStep;
    if (next != null) {
      state = state.copyWith(
        activeDelivery: state.activeDelivery!.copyWith(currentStep: next),
      );

      // Map step to order status and push to API
      final orderId = state.activeDelivery!.request.order.id;
      String? apiStatus;
      switch (next) {
        case DeliveryStep.pickUp:
          apiStatus = 'picked_up';
        case DeliveryStep.goToCustomer:
          apiStatus = 'out_for_delivery';
        default:
          break;
      }
      if (apiStatus != null) {
        _api
            .put(
              '${ApiConfig.deliveryOrders}/$orderId/status',
              body: {'status': apiStatus},
            )
            .then((r) {
          if (!r.success) debugPrint('[Delivery] advanceStep failed: ${r.error}');
        }).catchError((e) {
          debugPrint('[Delivery] advanceStep error: $e');
        });
      }
    }
  }

  /// Complete delivery
  Future<void> completeDelivery() async {
    final orderId = state.activeDelivery?.request.order.id;
    final earning = state.activeDelivery?.request.estimatedEarning ?? 0;
    final distance = state.activeDelivery?.request.distanceKm ?? 0;

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

    // Push delivered status to API
    if (orderId != null) {
      _api
          .put(
            '${ApiConfig.deliveryOrders}/$orderId/status',
            body: {'status': 'delivered'},
          )
          .then((r) {
        if (!r.success) debugPrint('[Delivery] complete failed: ${r.error}');
      }).catchError((e) {
        debugPrint('[Delivery] complete error: $e');
      });
    }
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
      if (!r.success) debugPrint('[Delivery] reportIssue failed: ${r.error}');
    }).catchError((e) {
      debugPrint('[Delivery] reportIssue error: $e');
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

  /// Simulate a new delivery request (debug / demo only)
  void simulateNewRequest() {
    final mock = DeliveryRequest.mock();
    state = state.copyWith(incomingRequest: mock);
  }

  /// Update delivery partner profile (vehicle, bank details)
  Future<bool> updateProfile({
    String? vehicleType,
    String? vehicleNumber,
    String? bankAccountId,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (vehicleType != null) body['vehicle_type'] = vehicleType;
      if (vehicleNumber != null) body['vehicle_number'] = vehicleNumber;
      if (bankAccountId != null) body['bank_account_id'] = bankAccountId;

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
    } catch (_) {}
    return false;
  }

  /// Fetch performance metrics
  Future<Map<String, dynamic>?> fetchPerformance() async {
    try {
      final response = await _api.get(ApiConfig.deliveryPerformance);
      if (response.success && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}

/// Delivery provider
final deliveryProvider = StateNotifierProvider<DeliveryNotifier, DeliveryState>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    final realtime = ref.watch(realtimeServiceProvider);
    final location = ref.watch(locationServiceProvider);
    return DeliveryNotifier(api, realtime, location);
  },
);
