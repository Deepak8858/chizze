import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../widgets/glass_card.dart';

/// In-app Terms and Conditions page for all app roles.
class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  static const _lastUpdated = 'April 14, 2026';
  static const _supportEmail = 'supportchizze@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Terms & Conditions')),
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
            const _Section(
              title: '1. Acceptance of Terms',
              body:
                  'By creating an account or using the Chizze platform (app, partner portal, or delivery app), you agree to these Terms. If you do not agree, do not use Chizze.',
            ),
            const _Section(
              title: '2. Eligibility',
              body:
                  'You must be at least 18 years old to use Chizze. Restaurant partners and delivery partners must provide accurate business and identity information and comply with applicable local laws and licensing requirements.',
            ),
            const _Section(
              title: '3. User Accounts',
              body:
                  'You are responsible for maintaining the confidentiality of your account credentials. You agree to notify us immediately of any unauthorized use of your account. We may suspend or terminate accounts that violate these Terms.',
            ),
            const _Section(
              title: '4. Orders and Payments',
              body:
                  'Orders placed through Chizze are binding. Prices are set by restaurant partners. Chizze facilitates payment processing and is not responsible for the quality of food or delivery. Refunds and cancellations are subject to Chizze\'s cancellation policy.',
            ),
            const _Section(
              title: '5. Restaurant Partner Obligations',
              body:
                  'Restaurant partners must maintain accurate menus, prices, and availability. Partners are responsible for food safety, hygiene, and compliance with FSSAI and other applicable regulations. Chizze reserves the right to remove partners who violate food safety or platform policies.',
            ),
            const _Section(
              title: '6. Delivery Partner Obligations',
              body:
                  'Delivery partners must maintain a valid driving license, vehicle insurance, and comply with traffic laws. Partners are independent contractors, not employees of Chizze. Earnings and payouts are subject to the payout policy; minimum ₹100 per withdrawal.',
            ),
            const _Section(
              title: '7. Prohibited Conduct',
              body:
                  'You may not: impersonate others, manipulate ratings or reviews, place fraudulent orders, interfere with platform operations, or use Chizze for any unlawful purpose.',
            ),
            const _Section(
              title: '8. Intellectual Property',
              body:
                  'All Chizze branding, software, and content are owned by Chizze or its licensors. You may not copy, modify, or distribute any part of the platform without prior written permission.',
            ),
            const _Section(
              title: '9. Limitation of Liability',
              body:
                  'Chizze is not liable for indirect, incidental, or consequential damages arising from use of the platform. Our total liability for any claim is limited to the amount you paid for the relevant transaction.',
            ),
            const _Section(
              title: '10. Dispute Resolution',
              body:
                  'Disputes shall first be resolved through our support team. If unresolved, disputes are subject to arbitration under Indian Arbitration and Conciliation Act, 1996, in Bangalore, Karnataka.',
            ),
            const _Section(
              title: '11. Changes to Terms',
              body:
                  'We may update these Terms at any time. Continued use of Chizze after changes constitutes acceptance. We will notify active users of material changes via in-app notice or email.',
            ),
            _Section(
              title: '12. Contact',
              body:
                  'For questions about these Terms, contact us at $_supportEmail.',
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

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
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w700),
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
