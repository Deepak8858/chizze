import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../home/models/restaurant.dart';

/// Favorites state
class FavoritesState {
  final List<Restaurant> favorites;
  final Set<String> favoriteIds;
  final bool isLoading;
  final String? error;

  const FavoritesState({
    this.favorites = const [],
    this.favoriteIds = const {},
    this.isLoading = false,
    this.error,
  });

  FavoritesState copyWith({
    List<Restaurant>? favorites,
    Set<String>? favoriteIds,
    bool? isLoading,
    String? error,
  }) {
    return FavoritesState(
      favorites: favorites ?? this.favorites,
      favoriteIds: favoriteIds ?? this.favoriteIds,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Favorites notifier — manages user's favorite restaurants
class FavoritesNotifier extends StateNotifier<FavoritesState> {
  final ApiClient _api;

  FavoritesNotifier(this._api) : super(const FavoritesState()) {
    fetchFavorites();
  }

  /// Check if a restaurant is favorited
  bool isFavorite(String restaurantId) {
    return state.favoriteIds.contains(restaurantId);
  }

  /// Toggle favorite status for a restaurant
  Future<void> toggleFavorite(String restaurantId) async {
    if (state.favoriteIds.contains(restaurantId)) {
      await removeFavorite(restaurantId);
    } else {
      await addFavorite(restaurantId);
    }
  }

  /// Fetch all favorites from API
  Future<void> fetchFavorites() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get(ApiConfig.favorites);
      if (response.success && response.data != null) {
        final list = response.data as List<dynamic>;
        final restaurants = <Restaurant>[];
        final ids = <String>{};
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final restaurantId = m['restaurant_id'] as String? ?? '';
          ids.add(restaurantId);
          // Parse restaurant data if enriched by backend
          if (m['restaurant'] != null) {
            try {
              restaurants.add(Restaurant.fromMap(
                  m['restaurant'] as Map<String, dynamic>));
            } catch (_) {}
          }
        }
        state = FavoritesState(
          favorites: restaurants,
          favoriteIds: ids,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      // Fallback to mock data on error
      state = FavoritesState(
        favorites: _mockFavorites,
        favoriteIds: _mockFavorites.map((r) => r.id).toSet(),
        isLoading: false,
      );
    }
  }

  /// Add a restaurant to favorites
  Future<void> addFavorite(String restaurantId) async {
    // Optimistic update
    final newIds = {...state.favoriteIds, restaurantId};
    state = state.copyWith(favoriteIds: newIds);

    try {
      await _api.post(ApiConfig.favorites, body: {
        'restaurant_id': restaurantId,
      });
    } catch (_) {
      // Revert on failure
      final revertIds = {...state.favoriteIds}..remove(restaurantId);
      state = state.copyWith(favoriteIds: revertIds);
    }
  }

  /// Remove a restaurant from favorites
  Future<void> removeFavorite(String restaurantId) async {
    // Optimistic update
    final newIds = {...state.favoriteIds}..remove(restaurantId);
    final newFavs =
        state.favorites.where((r) => r.id != restaurantId).toList();
    state = state.copyWith(favoriteIds: newIds, favorites: newFavs);

    try {
      await _api.delete('${ApiConfig.favorites}/$restaurantId');
    } catch (_) {
      // Revert on failure
      state = state.copyWith(
        favoriteIds: {...state.favoriteIds, restaurantId},
      );
      fetchFavorites(); // Re-fetch to restore
    }
  }
}

/// Provider
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  final api = ref.watch(apiClientProvider);
  return FavoritesNotifier(api);
});

/// Mock favorites for offline fallback
final List<Restaurant> _mockFavorites = [
  Restaurant.mockList[0],
  Restaurant.mockList[2],
];
