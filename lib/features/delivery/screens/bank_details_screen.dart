import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/delivery_provider.dart';
import '../providers/earnings_provider.dart';

/// Bank details & payouts management screen for delivery partners.
class BankDetailsScreen extends ConsumerStatefulWidget {
  const BankDetailsScreen({super.key});

  @override
  ConsumerState<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends ConsumerState<BankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountHolderCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from partner model after the first frame (ref is not usable
    // inside initState for ConsumerStatefulWidget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final partner = ref.read(deliveryProvider).partner;
      if (partner.bankAccountHolder != null &&
          partner.bankAccountHolder!.isNotEmpty) {
        _accountHolderCtrl.text = partner.bankAccountHolder!;
      }
      if (partner.ifsc != null && partner.ifsc!.isNotEmpty) {
        _ifscCtrl.text = partner.ifsc!;
      }
      if (partner.upiId != null && partner.upiId!.isNotEmpty) {
        _upiCtrl.text = partner.upiId!;
      }
    });
  }

  @override
  void dispose() {
    _accountHolderCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ifscCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final earnings = ref.watch(earningsProvider);
    final partner = ref.watch(deliveryProvider).partner;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bank Details'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _isEditing = !_isEditing),
            icon: Icon(
              _isEditing ? Icons.close_rounded : Icons.edit_rounded,
              size: 18,
            ),
            label: Text(_isEditing ? 'Cancel' : 'Edit'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Balance Overview ───
            _buildBalanceCard(partner.totalEarnings),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Bank Account Form ───
            Text(
              'Bank Account',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildBankForm(),
            const SizedBox(height: AppSpacing.xxl),

            // ─── UPI ───
            Text(
              'UPI ID',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildUpiField(),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Recent Payouts ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Payouts',
                  style: AppTypography.h3.copyWith(fontSize: 16),
                ),
                if (earnings.payouts.isNotEmpty)
                  Text(
                    '${earnings.payouts.length} total',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (earnings.payouts.isEmpty)
              _buildEmptyPayouts()
            else
              ...earnings.payouts
                  .take(10)
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => _buildPayoutTile(e.value, e.key)),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(double totalEarnings) {
    return GlassCard(
      child: Column(
        children: [
          Row(
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
                    Text('Total Earnings', style: AppTypography.caption),
                    const SizedBox(height: 2),
                    Text(
                      '₹${totalEarnings.toStringAsFixed(0)}',
                      style: AppTypography.h2.copyWith(
                        color: AppColors.success,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildBankForm() {
    return Form(
      key: _formKey,
      child: GlassCard(
        child: Column(
          children: [
            _buildField(
              label: 'Account Holder Name',
              controller: _accountHolderCtrl,
              icon: Icons.person_outline_rounded,
              enabled: _isEditing,
              hint: 'Enter account holder name',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Account holder name is required'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _buildField(
              label: 'Account Number',
              controller: _accountNumberCtrl,
              icon: Icons.numbers_rounded,
              enabled: _isEditing,
              hint: 'Enter account number',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
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
            _buildField(
              label: 'IFSC Code',
              controller: _ifscCtrl,
              icon: Icons.business_rounded,
              enabled: _isEditing,
              hint: 'e.g. SBIN0001234',
              textCapitalization: TextCapitalization.characters,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'IFSC code is required';
                }
                if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v.trim().toUpperCase())) {
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
                  onPressed: _saveBankDetails,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                  child: const Text('Save Bank Details'),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate(delay: 200.ms).fadeIn();
  }

  Widget _buildUpiField() {
    return GlassCard(
      child: _buildField(
        label: 'UPI ID',
        controller: _upiCtrl,
        icon: Icons.qr_code_rounded,
        enabled: _isEditing,
        hint: 'e.g. name@upi',
      ),
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildField({
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
            prefixIcon: Icon(icon, size: 20, color: AppColors.textTertiary),
            filled: true,
            fillColor: enabled
                ? AppColors.background
                : AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              borderSide: BorderSide(
                color: AppColors.divider,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              borderSide: BorderSide(
                color: AppColors.divider,
              ),
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
            style: AppTypography.body1.copyWith(
              fontWeight: FontWeight.w600,
            ),
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

  Widget _buildPayoutTile(PayoutRecord payout, int index) {
    final amount = payout.amount;
    final status = payout.status;
    final date = payout.periodEnd.toIso8601String();

    Color statusColor;
    IconData statusIcon;
    switch (status) {
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
          '₹${amount.toStringAsFixed(0)}',
          style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${payout.orderCount} orders · ${_formatDate(date)}',
          style: AppTypography.caption.copyWith(fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            status.isNotEmpty
                ? status[0].toUpperCase() + status.substring(1)
                : 'Unknown',
            style: AppTypography.overline.copyWith(
              color: statusColor,
              fontSize: 10,
            ),
          ),
        ),
        dense: true,
      ),
    ).animate(delay: (400 + index * 60).ms).fadeIn().slideX(begin: 0.03);
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _saveBankDetails() async {
    if (!_formKey.currentState!.validate()) return;

    final accountId = _accountNumberCtrl.text.trim();
    final holderName = _accountHolderCtrl.text.trim();
    final ifsc = _ifscCtrl.text.trim().toUpperCase();
    final upiId = _upiCtrl.text.trim();

    try {
      await ref.read(deliveryProvider.notifier).updateProfile(
        bankAccountId: accountId,
        bankAccountHolder: holderName,
        ifsc: ifsc,
        upiId: upiId.isNotEmpty ? upiId : null,
      );
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bank details saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[BankDetailsScreen] Failed to save: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save changes. Please try again.'),
          ),
        );
      }
    }
  }
}
