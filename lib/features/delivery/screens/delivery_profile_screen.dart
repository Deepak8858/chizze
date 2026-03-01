import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/delivery_provider.dart';

/// Delivery partner profile — stats, vehicle, support
class DeliveryProfileScreen extends ConsumerWidget {
  const DeliveryProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dState = ref.watch(deliveryProvider);
    final partner = dState.partner;
    final metrics = dState.metrics;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            // ─── Avatar & Name ───
            _buildProfileHeader(partner.name, partner.rating, partner.phone),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Stats ───
            _buildStatsRow(
              partner.totalDeliveries,
              partner.totalEarnings,
              metrics.hoursOnline,
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Vehicle Info ───
            _buildVehicleCard(
              context,
              ref,
              partner.vehicleType,
              partner.vehicleNumber,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ─── Menu Items ───
            _buildMenuItem(
              Icons.account_balance_wallet_rounded,
              'Bank Details',
              subtitle: 'Manage payout accounts',
              onTap: () => context.push('/delivery/bank-details'),
            ),
            _buildMenuItem(
              Icons.description_rounded,
              'Documents',
              subtitle: 'ID, License & Vehicle docs',
              onTap: () => context.push('/delivery/documents'),
            ),
            _buildMenuItem(
              Icons.schedule_rounded,
              'Availability',
              subtitle: 'Set your working hours',
              onTap: () => context.push('/delivery/availability'),
            ),
            _buildMenuItem(
              Icons.headset_mic_rounded,
              'Support',
              subtitle: 'Help & FAQs',
              onTap: () => context.push('/support'),
            ),
            _buildMenuItem(
              Icons.info_outline_rounded,
              'About Chizze',
              subtitle: 'Terms, privacy & version',
              onTap: () => launchUrl(
                Uri.parse('https://chizze.com/about'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Logout ───
            TextButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
              label: Text(
                'Logout',
                style: AppTypography.body2.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout', style: AppTypography.h3),
        content: Text(
          'Are you sure you want to logout?',
          style: AppTypography.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Logout',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(authProvider.notifier).logout();
    }
  }

  Widget _buildProfileHeader(String name, double rating, String phone) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: AppTypography.h1.copyWith(fontSize: 32),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(name, style: AppTypography.h2.copyWith(fontSize: 20)),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(phone, style: AppTypography.caption),
        ],
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 18,
              color: AppColors.ratingStar,
            ),
            const SizedBox(width: 4),
            Text(
              '$rating',
              style: AppTypography.body1.copyWith(
                color: AppColors.ratingStar,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(' rating', style: AppTypography.caption),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildStatsRow(int deliveries, double earnings, double hoursOnline) {
    return Row(
      children: [
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('📦', style: TextStyle(fontSize: 24)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$deliveries',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.primary,
                    fontSize: 20,
                  ),
                ),
                Text('Deliveries', style: AppTypography.overline),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('💰', style: TextStyle(fontSize: 24)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '₹${(earnings / 1000).toStringAsFixed(1)}K',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.success,
                    fontSize: 20,
                  ),
                ),
                Text('Earned', style: AppTypography.overline),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('⏱️', style: TextStyle(fontSize: 24)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${hoursOnline.toStringAsFixed(1)}h',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.info,
                    fontSize: 20,
                  ),
                ),
                Text('Online', style: AppTypography.overline),
              ],
            ),
          ),
        ),
      ],
    ).animate(delay: 200.ms).fadeIn();
  }

  Widget _buildVehicleCard(
    BuildContext context,
    WidgetRef ref,
    String type,
    String number,
  ) {
    final emoji = type == 'bike'
        ? '🏍️'
        : type == 'scooter'
        ? '🛵'
        : type == 'bicycle'
        ? '🚲'
        : '🚗';
    final label = type[0].toUpperCase() + type.substring(1);

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(number, style: AppTypography.caption),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showVehicleEditDialog(context, ref, type, number),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.edit_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn();
  }

  void _showVehicleEditDialog(
    BuildContext context,
    WidgetRef ref,
    String currentType,
    String currentNumber,
  ) {
    String selectedType = currentType;
    final numberCtrl = TextEditingController(text: currentNumber);
    final types = ['bike', 'scooter', 'bicycle', 'car'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Edit Vehicle',
                style: AppTypography.h3.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Vehicle Type',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: types.map((t) {
                  final isSelected = t == selectedType;
                  final emoji = t == 'bike'
                      ? '🏍️'
                      : t == 'scooter'
                      ? '🛵'
                      : t == 'bicycle'
                      ? '🚲'
                      : '🚗';
                  return ChoiceChip(
                    label: Text(
                      '$emoji ${t[0].toUpperCase()}${t.substring(1)}',
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    backgroundColor: AppColors.surfaceElevated,
                    labelStyle: AppTypography.body2.copyWith(
                      color: isSelected ? AppColors.primary : AppColors.text,
                    ),
                    onSelected: (_) {
                      setModalState(() => selectedType = t);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: numberCtrl,
                style: AppTypography.body1,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Vehicle Number',
                  hintText: 'e.g. KA01AB1234',
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final newNumber = numberCtrl.text.trim();
                    if (newNumber.isEmpty) return;
                    Navigator.of(ctx).pop();
                    final success = await ref
                        .read(deliveryProvider.notifier)
                        .updateProfile(
                          vehicleType: selectedType,
                          vehicleNumber: newNumber,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Vehicle updated'
                                : 'Failed to update vehicle',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, {String? subtitle, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListTile(
        leading: Icon(icon, size: 22, color: AppColors.textSecondary),
        title: Text(label, style: AppTypography.body2),
        subtitle: subtitle != null
            ? Text(subtitle, style: AppTypography.caption.copyWith(fontSize: 11))
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppColors.textTertiary,
        ),
        onTap: onTap,
        dense: true,
      ),
    );
  }
}
