import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/delivery_provider.dart';

enum _DocStatus { verified, review, rejected, pending }

/// Documents screen — shows verification status for ID, license, vehicle docs.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(deliveryProvider).partner;
    // Infer verification from available fields
    final hasVehicle = partner.vehicleNumber.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Documents')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Verification Status Banner ───
            _StatusBanner(isVerified: hasVehicle),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Document List ───
            Text(
              'Required Documents',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            _DocumentCard(
              icon: Icons.badge_rounded,
              title: 'Government ID',
              subtitle: 'Aadhaar Card or PAN Card',
              status: _DocStatus.pending,
              index: 0,
            ),
            _DocumentCard(
              icon: Icons.directions_car_rounded,
              title: 'Driving License',
              subtitle: 'Upload your driving license',
              status: _DocStatus.pending,
              index: 1,
            ),
            _DocumentCard(
              icon: Icons.two_wheeler_rounded,
              title: 'Vehicle Registration (RC)',
              subtitle: hasVehicle
                  ? 'Vehicle: ${partner.vehicleNumber}'
                  : 'Upload your vehicle RC',
              status: hasVehicle ? _DocStatus.review : _DocStatus.pending,
              index: 2,
            ),
            _DocumentCard(
              icon: Icons.health_and_safety_rounded,
              title: 'Vehicle Insurance',
              subtitle: 'Valid insurance certificate',
              status: _DocStatus.pending,
              index: 3,
            ),
            _DocumentCard(
              icon: Icons.photo_camera_front_rounded,
              title: 'Profile Photo',
              subtitle: 'Clear photo for verification',
              status: partner.avatarUrl.isNotEmpty
                  ? _DocStatus.review
                  : _DocStatus.pending,
              index: 4,
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Help Text ───
            GlassCard(
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Documents are verified within 24-48 hours of submission. '
                      'Contact support if verification is delayed.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate(delay: 600.ms).fadeIn(),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ───────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.isVerified});
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: isVerified
            ? const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)])
            : const LinearGradient(
                colors: [Color(0xFFFFA726), Color(0xFFFFB74D)]),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isVerified ? Icons.verified_rounded : Icons.pending_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVerified ? 'Verified' : 'Verification Pending',
                  style: AppTypography.h3
                      .copyWith(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  isVerified
                      ? 'All your documents are approved'
                      : 'Upload & verify documents to start delivering',
                  style: AppTypography.caption
                      .copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05);
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.index,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _DocStatus status;
  final int index;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData statusIcon, String label) = switch (status) {
      _DocStatus.verified => (
          AppColors.success,
          Icons.check_circle_rounded,
          'Verified',
        ),
      _DocStatus.review => (
          AppColors.info,
          Icons.hourglass_top_rounded,
          'In Review',
        ),
      _DocStatus.rejected => (
          AppColors.error,
          Icons.cancel_rounded,
          'Rejected',
        ),
      _DocStatus.pending => (
          AppColors.warning,
          Icons.upload_file_rounded,
          'Upload',
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: status == _DocStatus.rejected
              ? AppColors.error.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: AppTypography.body2),
        subtitle: Text(
          subtitle,
          style: AppTypography.caption.copyWith(fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTypography.overline
                    .copyWith(color: color, fontSize: 10),
              ),
            ],
          ),
        ),
        onTap:
            status == _DocStatus.pending || status == _DocStatus.rejected
                ? () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Document upload will be available in the next update',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                : null,
        dense: true,
      ),
    ).animate(delay: (200 + index * 80).ms).fadeIn().slideX(begin: 0.03);
  }
}
