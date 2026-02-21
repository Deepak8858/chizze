import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/realtime_service.dart';
import '../models/delivery_partner.dart';

/// Delivery partner state
class DeliveryState {
  final DeliveryPartner partner;
  final DeliveryMetrics metrics;
  final DeliveryRequest? incomingRequest;
  final ActiveDelivery? activeDelivery;
  final bool isLoading;

  const DeliveryState({
    required this.partner,
    this.metrics = const DeliveryMetrics(),
    this.incomingRequest,
    this.activeDelivery,
    this.isLoading = false,
  });

  DeliveryState copyWith({
    DeliveryPartner? partner,
    DeliveryMetrics? metrics,
    DeliveryRequest? incomingRequest,
    ActiveDelivery? activeDelivery,
    bool? isLoading,
    bool clearRequest = false,
    bool clearDelivery = false,
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
    );
  }

  bool get hasActiveDelivery => activeDelivery != null;
  bool get hasIncomingRequest =>
      incomingRequest != null && !incomingRequest!.hasExpired;
}

/// Delivery notifier — API-backed with mock fallback + Realtime
class DeliveryNotifier extends StateNotifier<DeliveryState> {
  final ApiClient _api;
  final RealtimeService _realtime;
  StreamSubscription? _realtimeSub;

  DeliveryNotifier(this._api, this._realtime)
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
          // Parse real delivery request from event data
          // TODO: implement DeliveryRequest.fromMap(event.data)
        }
      });
    } catch (_) {} // Realtime not available
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Fetch dashboard data (partner profile + today metrics + weekly progress)
      final response = await _api.get(ApiConfig.deliveryDashboard);
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final partner = DeliveryPartner.fromDashboard(data);
        final metrics = DeliveryMetrics.fromDashboard(data);

        state = state.copyWith(
          partner: partner,
          metrics: metrics,
        );
        return;
      }
    } catch (_) {}

    // No mock fallback — show empty state
    state = state.copyWith(
      metrics: const DeliveryMetrics(),
    );
  }

  /// Toggle online/offline
  void toggleOnline() {
    state = state.copyWith(
      partner: state.partner.copyWith(isOnline: !state.partner.isOnline),
    );
    // When going offline, clear incoming request
    if (!state.partner.isOnline) {
      state = state.copyWith(clearRequest: true);
    }

    // Push to API
    _api
        .put(
          ApiConfig.deliveryStatus,
          body: {'is_online': state.partner.isOnline},
        )
        .ignore();
  }

  /// Accept a delivery request
  void acceptRequest() {
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
    _api.put('${ApiConfig.deliveryOrders}/$orderId/accept').ignore();
  }

  /// Reject/skip a delivery request
  void rejectRequest() {
    state = state.copyWith(clearRequest: true);
  }

  /// Move to next delivery step
  void advanceStep() {
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
            .ignore();
      }
    }
  }

  /// Complete delivery
  void completeDelivery() {
    final orderId = state.activeDelivery?.request.order.id;
    state = state.copyWith(
      clearDelivery: true,
      partner: state.partner.copyWith(isOnDelivery: false),
      metrics: DeliveryMetrics(
        todayEarnings:
            state.metrics.todayEarnings +
            (state.activeDelivery?.request.estimatedEarning ?? 0),
        todayDeliveries: state.metrics.todayDeliveries + 1,
        todayDistanceKm:
            state.metrics.todayDistanceKm +
            (state.activeDelivery?.request.distanceKm ?? 0),
        weeklyGoal: state.metrics.weeklyGoal,
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
          .ignore();
    }
  }

  /// Simulate a new incoming request (removed — no mock data)
  void simulateNewRequest() {
    // No-op: removed mock simulation
  }
}

/// Delivery provider
final deliveryProvider = StateNotifierProvider<DeliveryNotifier, DeliveryState>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    final realtime = ref.watch(realtimeServiceProvider);
    return DeliveryNotifier(api, realtime);
  },
);
