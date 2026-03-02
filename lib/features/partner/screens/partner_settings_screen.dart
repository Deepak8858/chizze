import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/partner_provider.dart';

/// Partner restaurant settings — photo, online/offline, support, logout
class PartnerSettingsScreen extends ConsumerStatefulWidget {
  const PartnerSettingsScreen({super.key});

  @override
  ConsumerState<PartnerSettingsScreen> createState() =>
      _PartnerSettingsScreenState();
}

class _PartnerSettingsScreenState extends ConsumerState<PartnerSettingsScreen> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final file = await ImageUploadService.pickImage();
    if (file == null) return;

    setState(() => _isUploading = true);

    try {
      final uploadService = ref.read(imageUploadServiceProvider);
      final imageUrl = await uploadService.uploadRestaurantImage(file);

      if (imageUrl != null && mounted) {
        final success = await ref
            .read(partnerProvider.notifier)
            .updateRestaurantImage(imageUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Restaurant photo updated'
                    : 'Failed to update photo',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload image')),
        );
      }
    } catch (e) {
      debugPrint('[PartnerSettings] _pickAndUploadImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error uploading image. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pState = ref.watch(partnerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Restaurant Photo ───
            _buildPhotoSection(pState),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Online / Offline Toggle ───
            _buildOnlineToggle(pState),
            const SizedBox(height: AppSpacing.xl),

            // ─── Menu Items ───
            _buildSettingsItem(
              Icons.support_agent_rounded,
              'Help & Support',
              subtitle: 'Contact us for assistance',
              onTap: () => context.push('/support'),
            ),
            _buildSettingsItem(
              Icons.description_rounded,
              'Terms & Conditions',
              subtitle: 'View legal information',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon')),
                );
              },
            ),
            _buildSettingsItem(
              Icons.privacy_tip_rounded,
              'Privacy Policy',
              subtitle: 'How we handle your data',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon')),
                );
              },
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Logout ───
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text(
                        'Are you sure you want to logout?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    await ref.read(authProvider.notifier).logout();
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                label: Text(
                  'Logout',
                  style: AppTypography.body1.copyWith(color: AppColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.error, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection(PartnerState pState) {
    final imageUrl = pState.restaurantImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return GlassCard(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Container(
                  width: double.infinity,
                  height: 180,
                  color: AppColors.surfaceElevated,
                  child: hasImage
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Material(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _isUploading ? null : _pickAndUploadImage,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            pState.restaurantName ?? 'Your Restaurant',
            style: AppTypography.h3.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          if (hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tap the camera icon to change photo',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Add a photo to attract more customers',
                style: AppTypography.caption.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.restaurant_rounded,
            size: 48,
            color: AppColors.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No photo yet',
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineToggle(PartnerState pState) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: pState.isOnline
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              pState.isOnline
                  ? Icons.storefront_rounded
                  : Icons.storefront_outlined,
              color: pState.isOnline ? AppColors.primary : AppColors.error,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Restaurant Status',
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  pState.isOnline
                      ? 'Accepting orders'
                      : 'Not accepting orders',
                  style: AppTypography.caption.copyWith(
                    color: pState.isOnline
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: pState.isOnline,
            activeColor: AppColors.primary,
            onChanged: (_) =>
                ref.read(partnerProvider.notifier).toggleOnline(),
          ),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn();
  }

  Widget _buildSettingsItem(
    IconData icon,
    String label, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
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
            ? Text(
                subtitle,
                style: AppTypography.caption.copyWith(fontSize: 11),
              )
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
