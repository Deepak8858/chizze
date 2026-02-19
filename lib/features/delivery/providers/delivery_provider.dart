import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Delivery notifier
class DeliveryNotifier extends StateNotifier<DeliveryState> {
  DeliveryNotifier() : super(DeliveryState(partner: DeliveryPartner.mock)) {
    _loadMockData();
  }

  void _loadMockData() {
    state = state.copyWith(
      metrics: DeliveryMetrics.mock,
      incomingRequest: DeliveryRequest.mock(),
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
  }

  /// Accept a delivery request
  void acceptRequest() {
    if (state.incomingRequest == null) return;

    final delivery = ActiveDelivery(
      request: state.incomingRequest!,
      acceptedAt: DateTime.now(),
    );

    state = state.copyWith(
      activeDelivery: delivery,
      partner: state.partner.copyWith(isOnDelivery: true),
      clearRequest: true,
    );
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
    }
  }

  /// Complete delivery
  void completeDelivery() {
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
  }

  /// Simulate a new incoming request
  void simulateNewRequest() {
    state = state.copyWith(incomingRequest: DeliveryRequest.mock());
  }
}

/// Delivery provider
final deliveryProvider = StateNotifierProvider<DeliveryNotifier, DeliveryState>(
  (ref) {
    return DeliveryNotifier();
  },
);
