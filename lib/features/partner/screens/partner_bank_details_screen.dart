import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/partner_bank_provider.dart';

/// Bank details & payouts management screen for restaurant partners.
class PartnerBankDetailsScreen extends ConsumerStatefulWidget {
  const PartnerBankDetailsScreen({super.key});

  @override
  ConsumerState<PartnerBankDetailsScreen> createState() =>
      _PartnerBankDetailsScreenState();
}

class _PartnerBankDetailsScreenState
    extends ConsumerState<PartnerBankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _holderCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _isEditing = false;
  String _payoutMethod = 'upi';
  bool _prefilled = false;

  @override
  void dispose() {
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
    _upiCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _prefillOnce(PartnerBankState bank) {
    // Wait until the first real (non-loading) data arrives before locking in.
    if (_prefilled || bank.isLoading) return;
    _prefilled = true;
    final d = bank.details;
    _holderCtrl.text = d.bankAccountHolder;
    _accountCtrl.text = d.bankAccountId;
    _ifscCtrl.text = d.ifsc;
    _upiCtrl.text = d.upiId;
    if (!d.hasUpi && d.hasBankAccount) {
      _payoutMethod = 'bank_transfer';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(partnerBankProvider);
    _prefillOnce(bank);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bank Details'),
        actions: [
          TextButton.icon(
            onPressed: bank.isSaving
                ? null
                : () => setState(() => _isEditing = !_isEditing),
            icon: Icon(
              _isEditing ? Icons.close_rounded : Icons.edit_rounded,
              size: 18,
            ),
            label: Text(_isEditing ? 'Cancel' : 'Edit'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(partnerBankProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBalanceCard(bank.details.totalEarnings),
              const SizedBox(height: AppSpacing.xxl),

              Text('Bank Account',
                  style: AppTypography.h3.copyWith(fontSize: 16)),
              const SizedBox(height: AppSpacing.md),
              _buildBankForm(bank),
              const SizedBox(height: AppSpacing.xxl),

              Text('UPI ID', style: AppTypography.h3.copyWith(fontSize: 16)),
              const SizedBox(height: AppSpacing.md),
              _buildUpiField(bank),
              const SizedBox(height: AppSpacing.xxl),

              Text('Request Payout',
                  style: AppTypography.h3.copyWith(fontSize: 16)),
              const SizedBox(height: AppSpacing.md),
              _buildPayoutRequestCard(bank),
              const SizedBox(height: AppSpacing.xxl),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Payouts',
                      style: AppTypography.h3.copyWith(fontSize: 16)),
                  if (bank.payouts.isNotEmpty)
                    Text('${bank.payouts.length} total',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (bank.isLoading && bank.payouts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (bank.payouts.isEmpty)
                _buildEmptyPayouts()
              else
                ...bank.payouts
                    .take(20)
                    .toList()
                    .asMap()
                    .entries
                    .map((e) => _buildPayoutTile(e.value, e.key)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(double totalEarnings) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Available Balance', style: AppTypography.caption),
                const SizedBox(height: 2),
                Text(
                  '₹${totalEarnings.toStringAsFixed(0)}',
                  style: AppTypography.h2
                      .copyWith(color: AppColors.success, fontSize: 24),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildBankForm(PartnerBankState bank) {
    return Form(
      key: _formKey,
      child: GlassCard(
        child: Column(
          children: [
            _field(
              label: 'Account Holder Name',
              controller: _holderCtrl,
              icon: Icons.person_outline_rounded,
              enabled: _isEditing,
              hint: 'As per bank records',
              validator: (v) {
                if (!_isEditing) return null;
                if (v == null || v.trim().isEmpty) {
                  return 'Account holder name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _field(
              label: 'Account Number',
              controller: _accountCtrl,
              icon: Icons.numbers_rounded,
              enabled: _isEditing,
              hint: 'Enter account number',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                if (!_isEditing) return null;
                if (v == null || v.trim().isEmpty) {
                  return 'Account number is required';
                }
                if (v.trim().length < 9) {
                  return 'Account number must be at least 9 digits';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _field(
              label: 'IFSC Code',
              controller: _ifscCtrl,
              icon: Icons.business_rounded,
              enabled: _isEditing,
              hint: 'e.g. SBIN0001234',
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                if (!_isEditing) return null;
                if (v == null || v.trim().isEmpty) {
                  return 'IFSC code is required';
                }
                if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$')
                    .hasMatch(v.trim().toUpperCase())) {
                  return 'Enter a valid IFSC code (e.g. SBIN0001234)';
                }
                return null;
              },
            ),
            if (_isEditing) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: bank.isSaving ? null : _saveBank,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  child: bank.isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Bank Details'),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate(delay: 200.ms).fadeIn();
  }

  Widget _buildUpiField(PartnerBankState bank) {
    return GlassCard(
      child: Column(
        children: [
          _field(
            label: 'UPI ID',
            controller: _upiCtrl,
            icon: Icons.qr_code_rounded,
            enabled: _isEditing,
            hint: 'e.g. name@upi',
          ),
          if (_isEditing) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: bank.isSaving ? null : _saveUpi,
                child: const Text('Save UPI'),
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildPayoutRequestCard(PartnerBankState bank) {
    final canRequest = bank.details.totalEarnings >= 100 &&
        (bank.details.hasBankAccount || bank.details.hasUpi);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Minimum ₹100. One request at a time.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: 'Amount',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  value: 'upi',
                  groupValue: _payoutMethod,
                  onChanged: bank.details.hasUpi
                      ? (v) => setState(() => _payoutMethod = v!)
                      : null,
                  title: const Text('UPI'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  value: 'bank_transfer',
                  groupValue: _payoutMethod,
                  onChanged: bank.details.hasBankAccount
                      ? (v) => setState(() => _payoutMethod = v!)
                      : null,
                  title: const Text('Bank'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (!canRequest)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                !bank.details.hasBankAccount && !bank.details.hasUpi
                    ? 'Add bank or UPI details before requesting payout.'
                    : 'You need at least ₹100 balance.',
                style: AppTypography.caption.copyWith(color: AppColors.warning),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  bank.isRequestingPayout || !canRequest ? null : _requestPayout,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
              child: bank.isRequestingPayout
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Request Payout'),
            ),
          ),
        ],
      ),
    ).animate(delay: 350.ms).fadeIn();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool enabled = true,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          validator: validator,
          style: AppTypography.body2,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.caption,
            prefixIcon:
                Icon(icon, size: 20, color: AppColors.textTertiary),
            filled: true,
            fillColor:
                enabled ? AppColors.background : AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              borderSide: BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPayouts() {
    return GlassCard(
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: AppColors.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No payouts yet',
            style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your payout history will appear here',
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate(delay: 400.ms).fadeIn();
  }

  Widget _buildPayoutTile(PartnerPayout p, int index) {
    Color statusColor;
    IconData statusIcon;
    switch (p.status) {
      case 'completed':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'processing':
        statusColor = AppColors.info;
        statusIcon = Icons.hourglass_top_rounded;
        break;
      case 'failed':
        statusColor = AppColors.error;
        statusIcon = Icons.error_rounded;
        break;
      default:
        statusColor = AppColors.warning;
        statusIcon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          '₹${p.amount.toStringAsFixed(0)}',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${p.method == 'upi' ? 'UPI' : 'Bank Transfer'} · ${_formatDate(p.createdAt)}',
          style: AppTypography.caption.copyWith(fontSize: 11),
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            p.status.isNotEmpty
                ? p.status[0].toUpperCase() + p.status.substring(1)
                : 'Unknown',
            style: AppTypography.overline
                .copyWith(color: statusColor, fontSize: 10),
          ),
        ),
        dense: true,
      ),
    ).animate(delay: (400 + index * 60).ms).fadeIn().slideX(begin: 0.03);
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';

  Future<void> _saveBank() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(partnerBankProvider.notifier).updateBankDetails(
          bankAccountHolder: _holderCtrl.text.trim(),
          bankAccountId: _accountCtrl.text.trim(),
          ifsc: _ifscCtrl.text.trim().toUpperCase(),
        );
    if (!mounted) return;
    final err = ref.read(partnerBankProvider).errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Bank details saved' : (err ?? 'Failed to save')),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
    if (ok) setState(() => _isEditing = false);
  }

  Future<void> _saveUpi() async {
    final upi = _upiCtrl.text.trim();
    if (upi.isEmpty) return;
    final ok = await ref
        .read(partnerBankProvider.notifier)
        .updateBankDetails(upiId: upi);
    if (!mounted) return;
    final err = ref.read(partnerBankProvider).errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'UPI saved' : (err ?? 'Failed to save')),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
    if (ok) setState(() => _isEditing = false);
  }

  Future<void> _requestPayout() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Minimum payout amount is ₹100')),
      );
      return;
    }
    final bank = ref.read(partnerBankProvider);
    if (amount > bank.details.totalEarnings) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance')),
      );
      return;
    }
    final err = await ref
        .read(partnerBankProvider.notifier)
        .requestPayout(amount: amount, method: _payoutMethod);
    if (!mounted) return;
    if (err == null) {
      _amountCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payout requested successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      if (kDebugMode) debugPrint('[PartnerBank] requestPayout: $err');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }
}
