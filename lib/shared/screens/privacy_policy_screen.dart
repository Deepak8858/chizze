import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../widgets/glass_card.dart';

/// In-app privacy policy page for all app roles.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _lastUpdated = 'April 2, 2026';
  static const _supportEmail = 'supportchizze@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last updated: $_lastUpdated',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _PolicySection(
              title: '1. Information We Collect',
              body:
                  'We collect account details (name, phone, email), location data for delivery and order tracking, and order/payment metadata required to provide services.',
            ),
            _PolicySection(
              title: '2. How We Use Information',
              body:
                  'We use your information to process orders, assign deliveries, provide customer support, improve reliability, and prevent abuse or fraud.',
            ),
            _PolicySection(
              title: '3. Role-Specific Data',
              body:
                  'Restaurant partners may provide restaurant profile/menu information. Delivery partners may provide vehicle, payout, and live location information while online.',
            ),
            _PolicySection(
              title: '4. Notifications',
              body:
                  'The app may send operational notifications (order updates, delivery requests, and support messages). Notification sound is disabled by default in-app for partner flows.',
            ),
            _PolicySection(
              title: '5. Data Sharing',
              body:
                  'We share only necessary data with restaurants, delivery partners, payment providers, and infrastructure vendors required to fulfill orders and run the platform.',
            ),
            _PolicySection(
              title: '6. Data Retention',
              body:
                  'We retain data for operational, legal, accounting, and safety requirements. We minimize retention where possible and delete or anonymize data when no longer needed.',
            ),
            _PolicySection(
              title: '7. Security',
              body:
                  'We use access controls, transport security, and monitoring to protect account and order data. No system is 100% secure, but we continuously improve safeguards.',
            ),
            _PolicySection(
              title: '8. Your Choices',
              body:
                  'You can update profile information, manage addresses, and control app permissions from your device settings. You may request account-related assistance from support.',
            ),
            _PolicySection(
              title: '9. Contact Us',
              body:
                  'For privacy questions or requests, contact us at $_supportEmail.',
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.body1.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
