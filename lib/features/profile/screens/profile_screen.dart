import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/address_provider.dart';

/// User profile & settings screen
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final addresses = ref.watch(addressProvider);
    final defaultAddr = addresses.where((a) => a.isDefault).firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.md),

              // ─── Avatar ───
              _buildAvatar(context, ref, profile),
              const SizedBox(height: AppSpacing.xxl),

              // ─── Default Address ───
              if (defaultAddr != null)
                _buildDefaultAddress(context, defaultAddr),
              const SizedBox(height: AppSpacing.xl),

              // ─── Settings Sections ───
              _buildSection('Account', [
                _SettingsTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Edit Profile',
                  onTap: () => _showEditProfile(context, ref, profile),
                ),
                _SettingsTile(
                  icon: Icons.location_on_outlined,
                  label: 'Saved Addresses',
                  subtitle: '${addresses.length} saved',
                  onTap: () => context.push('/addresses'),
                ),
                _SettingsTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Order History',
                  onTap: () => context.go('/orders'),
                ),
              ]),
              const SizedBox(height: AppSpacing.xl),

              _buildSection('Offers', [
                _SettingsTile(
                  icon: Icons.local_offer_outlined,
                  label: 'Coupons & Offers',
                  onTap: () => context.push('/coupons'),
                ),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () => context.push('/notifications'),
                ),
              ]),
              const SizedBox(height: AppSpacing.xl),

              _buildSection('Preferences', [
                _SettingsTile(
                  icon: Icons.eco_outlined,
                  label: 'Vegetarian Mode',
                  trailing: Switch.adaptive(
                    value: profile.isVeg,
                    onChanged: (_) =>
                        ref.read(userProfileProvider.notifier).toggleVeg(),
                    activeColor: AppColors.veg,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark Mode',
                  trailing: Switch.adaptive(
                    value: profile.darkMode,
                    onChanged: (_) =>
                        ref.read(userProfileProvider.notifier).toggleDarkMode(),
                    activeColor: AppColors.primary,
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.xl),

              _buildSection('More', [
                const _SettingsTile(
                  icon: Icons.headset_mic_outlined,
                  label: 'Help & Support',
                ),
                const _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About Chizze',
                ),
                const _SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                ),
              ]),
              const SizedBox(height: AppSpacing.xxl),

              // ─── Logout ───
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Chizze v1.0.0',
                style: AppTypography.overline.copyWith(fontSize: 10),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
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
              profile.initials,
              style: AppTypography.h1.copyWith(fontSize: 30),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(profile.name, style: AppTypography.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 4),
        Text(profile.phone, style: AppTypography.caption),
        if (profile.email.isNotEmpty)
          Text(
            profile.email,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildDefaultAddress(BuildContext context, SavedAddress addr) {
    return GestureDetector(
      onTap: () => context.push('/addresses'),
      child: GlassCard(
        child: Row(
          children: [
            Text(addr.iconLabel.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        addr.label,
                        style: AppTypography.body2.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Default',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.primary,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    addr.fullAddress,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    ).animate(delay: 200.ms).fadeIn();
  }

  Widget _buildSection(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.overline.copyWith(
            color: AppColors.textTertiary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }

  void _showEditProfile(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) {
    final nameCtrl = TextEditingController(text: profile.name);
    final emailCtrl = TextEditingController(text: profile.email);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
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
            Text('Edit Profile', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ref
                      .read(userProfileProvider.notifier)
                      .updateName(nameCtrl.text);
                  ref
                      .read(userProfileProvider.notifier)
                      .updateEmail(emailCtrl.text);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22, color: AppColors.textSecondary),
      title: Text(label, style: AppTypography.body2),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTypography.caption)
          : null,
      trailing:
          trailing ??
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: AppColors.textTertiary,
          ),
      onTap: onTap,
      dense: true,
    );
  }
}
