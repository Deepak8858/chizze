import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../models/restaurant.dart';

/// Restaurant list state
class RestaurantListState {
  final List<Restaurant> restaurants;
  final bool isLoading;
  final String? error;

  const RestaurantListState({
    this.restaurants = const [],
    this.isLoading = false,
    this.error,
  });

  RestaurantListState copyWith({
    List<Restaurant>? restaurants,
    bool? isLoading,
    String? error,
  }) {
    return RestaurantListState(
      restaurants: restaurants ?? this.restaurants,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Fetches restaurants from Go backend API with mock fallback in dev
class RestaurantNotifier extends StateNotifier<RestaurantListState> {
  final ApiClient _api;

  RestaurantNotifier(this._api) : super(const RestaurantListState()) {
    fetchRestaurants();
  }

  Future<void> fetchRestaurants() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get(ApiConfig.restaurants);
      if (response.success && response.data != null) {
        final data = response.data;
        List<dynamic> docs;
        if (data is Map<String, dynamic>) {
          // Paginated response: { data: [...], page: ..., total: ... }
          docs = (data['data'] as List<dynamic>?) ?? [];
        } else if (data is List) {
          docs = data;
        } else {
          docs = [];
        }
        final restaurants =
            docs.map((d) => Restaurant.fromMap(d as Map<String, dynamic>)).toList();
        state = state.copyWith(restaurants: restaurants, isLoading: false);
      } else {
        // API returned error — fall back to mock in dev
        debugPrint('[Restaurants] API error: ${response.error}');
        state = state.copyWith(
          restaurants: Restaurant.mockList,
          isLoading: false,
          error: response.error,
        );
      }
    } on ApiException catch (e) {
      debugPrint('[Restaurants] ApiException: ${e.message}');
      state = state.copyWith(
        restaurants: Restaurant.mockList,
        isLoading: false,
        error: e.message,
      );
    } catch (e) {
      debugPrint('[Restaurants] Unexpected error: $e');
      state = state.copyWith(
        restaurants: Restaurant.mockList,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() => fetchRestaurants();
}

/// Global restaurant list provider
final restaurantProvider =
    StateNotifierProvider<RestaurantNotifier, RestaurantListState>((ref) {
  final api = ref.watch(apiClientProvider);
  return RestaurantNotifier(api);
});
