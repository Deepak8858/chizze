import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// Referral history item
class Referral {
  final String id;
  final String referredUserId;
  final String referredUserName;
  final double rewardAmount;
  final String status; // pending, completed
  final DateTime createdAt;

  const Referral({
    required this.id,
    required this.referredUserId,
    required this.referredUserName,
    required this.rewardAmount,
    required this.status,
    required this.createdAt,
  });
}

/// Referral state
class ReferralState {
  final String? referralCode;
  final List<Referral> referrals;
  final double totalEarned;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const ReferralState({
    this.referralCode,
    this.referrals = const [],
    this.totalEarned = 0,
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  ReferralState copyWith({
    String? referralCode,
    List<Referral>? referrals,
    double? totalEarned,
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return ReferralState(
      referralCode: referralCode ?? this.referralCode,
      referrals: referrals ?? this.referrals,
      totalEarned: totalEarned ?? this.totalEarned,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Referral notifier — manages referral code, history, and applying codes
class ReferralNotifier extends StateNotifier<ReferralState> {
  final ApiClient _api;

  ReferralNotifier(this._api) : super(const ReferralState()) {
    fetchReferralCode();
    fetchReferrals();
  }

  /// Fetch the user's referral code
  Future<void> fetchReferralCode() async {
    try {
      final response = await _api.get(ApiConfig.referralCode);
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        state = state.copyWith(referralCode: data['referral_code'] ?? '');
      }
    } on ApiException {
      // Keep current state
    } catch (e) {
      debugPrint('[Referral] fetchReferralCode error: $e');
    }
  }

  /// Fetch referral history
  Future<void> fetchReferrals() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiConfig.referrals);
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final list = (data['referrals'] as List<dynamic>?) ?? [];
        final referrals = list.map((d) {
          final m = d as Map<String, dynamic>;
          return Referral(
            id: m['\$id'] ?? '',
            referredUserId: m['referred_user_id'] ?? '',
            referredUserName: m['referred_user_name'] ?? 'User',
            rewardAmount: (m['reward_amount'] ?? 0).toDouble(),
            status: m['status'] ?? 'completed',
            createdAt:
                DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          );
        }).toList();
        final totalEarned = (data['total_earned'] ?? 0).toDouble();
        state = state.copyWith(
          referrals: referrals,
          totalEarned: totalEarned,
          isLoading: false,
        );
      }
    } on ApiException {
      state = state.copyWith(isLoading: false);
    } catch (e) {
      debugPrint('[Referral] fetchReferrals error: $e');
      state = state.copyWith(
        referrals: const [],
        isLoading: false,
      );
    }
  }

  /// Apply a referral code
  Future<void> applyCode(String code) async {
    state = state.copyWith(isLoading: true, error: null, successMessage: null);
    try {
      final response = await _api.post(
        ApiConfig.referralApply,
        body: {'referral_code': code},
      );
      if (response.success) {
        state = state.copyWith(
          isLoading: false,
          successMessage: '₹100 reward added! 🎉',
        );
        fetchReferrals(); // Refresh history
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.error ?? 'Invalid referral code',
        );
      }
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Something went wrong. Try again.',
      );
    }
  }
}

final referralProvider =
    StateNotifierProvider<ReferralNotifier, ReferralState>((ref) {
      final api = ref.watch(apiClientProvider);
      return ReferralNotifier(api);
    });
