import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// Saved bank/UPI details + available balance for a restaurant partner.
class PartnerBankDetails {
  final String bankAccountId;
  final String bankAccountHolder;
  final String ifsc;
  final String upiId;
  final double totalEarnings;

  const PartnerBankDetails({
    this.bankAccountId = '',
    this.bankAccountHolder = '',
    this.ifsc = '',
    this.upiId = '',
    this.totalEarnings = 0,
  });

  factory PartnerBankDetails.fromMap(Map<String, dynamic> m) {
    return PartnerBankDetails(
      bankAccountId: (m['bank_account_id'] ?? '').toString(),
      bankAccountHolder: (m['bank_account_holder'] ?? '').toString(),
      ifsc: (m['ifsc'] ?? '').toString(),
      upiId: (m['upi_id'] ?? '').toString(),
      totalEarnings: (m['total_earnings'] as num?)?.toDouble() ?? 0,
    );
  }

  bool get hasBankAccount =>
      bankAccountId.isNotEmpty && ifsc.isNotEmpty && bankAccountHolder.isNotEmpty;
  bool get hasUpi => upiId.isNotEmpty;
}

/// Partner payout history entry.
class PartnerPayout {
  final String id;
  final double amount;
  final String status;
  final String method;
  final DateTime createdAt;

  const PartnerPayout({
    required this.id,
    required this.amount,
    required this.status,
    required this.method,
    required this.createdAt,
  });

  factory PartnerPayout.fromMap(Map<String, dynamic> m) {
    return PartnerPayout(
      id: m['\$id']?.toString() ?? m['id']?.toString() ?? '',
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      status: (m['status'] ?? 'pending').toString(),
      method: (m['method'] ?? '').toString(),
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class PartnerBankState {
  final PartnerBankDetails details;
  final List<PartnerPayout> payouts;
  final bool isLoading;
  final bool isSaving;
  final bool isRequestingPayout;
  final String? errorMessage;

  const PartnerBankState({
    this.details = const PartnerBankDetails(),
    this.payouts = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.isRequestingPayout = false,
    this.errorMessage,
  });

  PartnerBankState copyWith({
    PartnerBankDetails? details,
    List<PartnerPayout>? payouts,
    bool? isLoading,
    bool? isSaving,
    bool? isRequestingPayout,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PartnerBankState(
      details: details ?? this.details,
      payouts: payouts ?? this.payouts,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isRequestingPayout: isRequestingPayout ?? this.isRequestingPayout,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PartnerBankNotifier extends StateNotifier<PartnerBankState> {
  final ApiClient _api;

  PartnerBankNotifier(this._api) : super(const PartnerBankState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _api.get(ApiConfig.partnerBankDetails),
        _api.get(ApiConfig.partnerPayouts, queryParams: {'per_page': 20}),
      ]);
      final detailsRes = results[0];
      final payoutsRes = results[1];

      PartnerBankDetails details = state.details;
      if (detailsRes.success && detailsRes.data is Map<String, dynamic>) {
        details = PartnerBankDetails.fromMap(
          Map<String, dynamic>.from(detailsRes.data as Map),
        );
      }

      List<PartnerPayout> payouts = state.payouts;
      if (payoutsRes.success && payoutsRes.data is List) {
        payouts = (payoutsRes.data as List)
            .map((e) =>
                PartnerPayout.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      state = state.copyWith(
        details: details,
        payouts: payouts,
        isLoading: false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PartnerBank] refresh error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load bank details',
      );
    }
  }

  /// Save bank/UPI details. Returns true on success.
  Future<bool> updateBankDetails({
    String? bankAccountId,
    String? bankAccountHolder,
    String? ifsc,
    String? upiId,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final body = <String, dynamic>{};
      if (bankAccountId != null && bankAccountId.isNotEmpty) {
        body['bank_account_id'] = bankAccountId;
      }
      if (bankAccountHolder != null && bankAccountHolder.isNotEmpty) {
        body['bank_account_holder'] = bankAccountHolder;
      }
      if (ifsc != null && ifsc.isNotEmpty) {
        body['ifsc'] = ifsc;
      }
      if (upiId != null && upiId.isNotEmpty) {
        body['upi_id'] = upiId;
      }

      if (body.isEmpty) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'Enter at least one field to save',
        );
        return false;
      }

      final res = await _api.put(ApiConfig.partnerBankDetails, body: body);
      if (!res.success) {
        state = state.copyWith(
          isSaving: false,
          errorMessage: res.error ?? 'Failed to save bank details',
        );
        return false;
      }

      // Optimistically update local state
      final d = state.details;
      state = state.copyWith(
        isSaving: false,
        details: PartnerBankDetails(
          bankAccountId: bankAccountId?.isNotEmpty == true
              ? bankAccountId!
              : d.bankAccountId,
          bankAccountHolder: bankAccountHolder?.isNotEmpty == true
              ? bankAccountHolder!
              : d.bankAccountHolder,
          ifsc: ifsc?.isNotEmpty == true
              ? ifsc!.toUpperCase()
              : d.ifsc,
          upiId: upiId?.isNotEmpty == true ? upiId! : d.upiId,
          totalEarnings: d.totalEarnings,
        ),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[PartnerBank] update error: $e');
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Failed to save bank details',
      );
      return false;
    }
  }

  /// Request a payout. Returns null on success, or an error message string.
  Future<String?> requestPayout({
    required double amount,
    required String method,
  }) async {
    state = state.copyWith(isRequestingPayout: true, clearError: true);
    try {
      final res = await _api.post(
        ApiConfig.partnerPayoutRequest,
        body: {'amount': amount, 'method': method},
      );
      if (!res.success) {
        final err = res.error ?? 'Failed to request payout';
        state = state.copyWith(
          isRequestingPayout: false,
          errorMessage: err,
        );
        return err;
      }
      // Refresh to pick up the new payout + reduced balance
      await refresh();
      state = state.copyWith(isRequestingPayout: false);
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[PartnerBank] requestPayout error: $e');
      const err = 'Failed to request payout';
      state = state.copyWith(isRequestingPayout: false, errorMessage: err);
      return err;
    }
  }
}

final partnerBankProvider =
    StateNotifierProvider<PartnerBankNotifier, PartnerBankState>((ref) {
  final api = ref.watch(apiClientProvider);
  return PartnerBankNotifier(api);
});
