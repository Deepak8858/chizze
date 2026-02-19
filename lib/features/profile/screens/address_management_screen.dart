import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/address_provider.dart';

/// Address management screen — list, add, edit, delete
class AddressManagementScreen extends ConsumerWidget {
  const AddressManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Saved Addresses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddressSheet(context, ref),
            tooltip: 'Add Address',
          ),
        ],
      ),
      body: addresses.isEmpty
          ? _buildEmpty(context, ref)
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.xl),
              itemCount: addresses.length,
              itemBuilder: (context, index) {
                final addr = addresses[index];
                return _buildAddressCard(context, ref, addr, index);
              },
            ),
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: AppSpacing.xl),
          Text('No saved addresses', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.sm),
          Text('Add your first delivery address', style: AppTypography.body2),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: () => _showAddressSheet(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Address'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(
    BuildContext context,
    WidgetRef ref,
    SavedAddress addr,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      addr.iconLabel.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            addr.label,
                            style: AppTypography.body1.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (addr.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Default',
                                style: AppTypography.overline.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        addr.fullAddress,
                        style: AppTypography.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (addr.landmark.isNotEmpty)
                        Text(
                          '📌 ${addr.landmark}',
                          style: AppTypography.overline.copyWith(fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: AppColors.divider, height: AppSpacing.xl),
            Row(
              children: [
                if (!addr.isDefault)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => ref
                          .read(addressProvider.notifier)
                          .setDefault(addr.id),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text(
                        'Set Default',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        _showAddressSheet(context, ref, existing: addr),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => ref
                        .read(addressProvider.notifier)
                        .removeAddress(addr.id),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    label: Text(
                      'Delete',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 60).ms).fadeIn().slideY(begin: 0.02);
  }

  void _showAddressSheet(
    BuildContext context,
    WidgetRef ref, {
    SavedAddress? existing,
  }) {
    final isEdit = existing != null;
    final addrCtrl = TextEditingController(text: existing?.fullAddress ?? '');
    final landCtrl = TextEditingController(text: existing?.landmark ?? '');
    String selectedLabel = existing?.label ?? 'Home';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
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
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                isEdit ? 'Edit Address' : 'Add Address',
                style: AppTypography.h3,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Label selector
              Row(
                children: IconLabel.values.map((il) {
                  final selected = selectedLabel == il.label;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text('${il.emoji} ${il.label}'),
                      selected: selected,
                      onSelected: (_) =>
                          setSheetState(() => selectedLabel = il.label),
                      selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Address',
                  hintText: 'House no, street, area, city',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: landCtrl,
                decoration: const InputDecoration(
                  labelText: 'Landmark (optional)',
                  hintText: 'Near...',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Map placeholder
              Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🗺️', style: TextStyle(fontSize: 28)),
                    SizedBox(height: 4),
                    Text(
                      'Pick on Map (coming soon)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (addrCtrl.text.isEmpty) return;
                    if (isEdit) {
                      ref
                          .read(addressProvider.notifier)
                          .updateAddress(
                            existing.copyWith(
                              label: selectedLabel,
                              fullAddress: addrCtrl.text,
                              landmark: landCtrl.text,
                            ),
                          );
                    } else {
                      ref
                          .read(addressProvider.notifier)
                          .addAddress(
                            SavedAddress(
                              id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
                              label: selectedLabel,
                              fullAddress: addrCtrl.text,
                              landmark: landCtrl.text,
                            ),
                          );
                    }
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(isEdit ? 'Update Address' : 'Save Address'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
