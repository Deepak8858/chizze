import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../models/promo_banner.dart';

class PromoBannerState {
  final List<PromoBanner> banners;
  final bool isLoading;
  final String? error;

  const PromoBannerState({
    this.banners = const [],
    this.isLoading = false,
    this.error,
  });

  PromoBanner? get primaryBanner => banners.isNotEmpty ? banners.first : null;

  PromoBannerState copyWith({
    List<PromoBanner>? banners,
    bool? isLoading,
    String? error,
  }) {
    return PromoBannerState(
      banners: banners ?? this.banners,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PromoBannerNotifier extends StateNotifier<PromoBannerState> {
  final ApiClient _api;

  PromoBannerNotifier(this._api) : super(const PromoBannerState()) {
    fetchBanners();
  }

  Future<void> fetchBanners() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get(ApiConfig.contentBanners);
      if (response.success && response.data != null) {
        final data = response.data;
        final docs = data is List
            ? data
            : (data is Map<String, dynamic>
                  ? (data['data'] as List<dynamic>?) ?? <dynamic>[]
                  : <dynamic>[]);

        final banners = docs
            .whereType<Map<String, dynamic>>()
            .map(PromoBanner.fromMap)
            .toList();

        state = state.copyWith(banners: banners, isLoading: false);
      } else {
        state = state.copyWith(
          banners: const [],
          isLoading: false,
          error: response.error,
        );
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[Home] Promo banners ApiException: ${e.message}');
      }
      state = state.copyWith(
        banners: const [],
        isLoading: false,
        error: e.message,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Home] Promo banners error: $e');
      }
      state = state.copyWith(
        banners: const [],
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

final promoBannerProvider =
    StateNotifierProvider<PromoBannerNotifier, PromoBannerState>((ref) {
  final api = ref.watch(apiClientProvider);
  return PromoBannerNotifier(api);
});
