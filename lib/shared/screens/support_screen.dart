import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/theme.dart';
import '../widgets/glass_card.dart';

/// Support / Help screen — shared between customer and delivery partner.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _supportPhone = '+918008008000';
  static const _supportEmail = 'support@chizze.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Help & Support')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Quick Contact ───
            _QuickContact(phone: _supportPhone, email: _supportEmail),
            const SizedBox(height: AppSpacing.xxl),

            // ─── FAQ Sections ───
            Text(
              'Frequently Asked Questions',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            ..._faqItems.asMap().entries.map((e) {
              final i = e.key;
              final faq = e.value;
              return _FaqTile(
                question: faq.$1,
                answer: faq.$2,
                index: i,
              );
            }),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Report Issue ───
            Text(
              'Report an Issue',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            _ReportIssueCard(email: _supportEmail),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Legal Links ───
            Text(
              'Legal',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            _LegalLink(
              icon: Icons.description_rounded,
              title: 'Terms of Service',
              url: 'https://chizze.com/terms',
              index: 0,
            ),
            _LegalLink(
              icon: Icons.privacy_tip_rounded,
              title: 'Privacy Policy',
              url: 'https://chizze.com/privacy',
              index: 1,
            ),
            _LegalLink(
              icon: Icons.cookie_rounded,
              title: 'Refund Policy',
              url: 'https://chizze.com/refund',
              index: 2,
            ),
          ],
        ),
      ),
    );
  }

  static const _faqItems = [
    (
      'How do I track my order?',
      'After placing an order, go to the Orders tab and tap on your '
          'active order to see live tracking with real-time rider location.',
    ),
    (
      'How do I cancel an order?',
      'You can cancel an order before the restaurant starts preparing it. '
          'Go to your active order → tap Cancel Order. Once preparation '
          'begins, cancellation is not available.',
    ),
    (
      'I received a wrong/damaged order',
      'Sorry about that! Please use the Report Issue form below or contact '
          'our support team directly. We\'ll resolve it within 24 hours and '
          'issue a refund or replacement.',
    ),
    (
      'How do payouts work for delivery partners?',
      'Payouts are processed weekly to your registered bank account. You '
          'can also request an instant payout from the Bank Details section. '
          'Minimum withdrawal amount is ₹100.',
    ),
    (
      'How long does delivery take?',
      'Typical delivery time is 25-45 minutes depending on distance and '
          'restaurant preparation time. You\'ll see an estimated arrival '
          'time on the tracking screen.',
    ),
    (
      'How to become a delivery partner?',
      'Download the app, sign up and choose "Delivery Partner" role. '
          'Upload your documents (ID, license, vehicle registration) and '
          'once verified you can start accepting deliveries.',
    ),
  ];
}

// ─── Widgets ──────────────────────────────────────────────────────

class _QuickContact extends StatelessWidget {
  const _QuickContact({required this.phone, required this.email});
  final String phone;
  final String email;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need help?',
            style: AppTypography.h3.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            'Our support team is available 24/7',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _ContactButton(
                  icon: Icons.phone_rounded,
                  label: 'Call us',
                  color: AppColors.success,
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _ContactButton(
                  icon: Icons.email_rounded,
                  label: 'Email us',
                  color: AppColors.info,
                  onTap: () => launchUrl(Uri(
                    scheme: 'mailto',
                    path: email,
                    query: 'subject=Chizze Support Request',
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.05);
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTypography.body2.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({
    required this.question,
    required this.answer,
    required this.index,
  });
  final String question;
  final String answer;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.question_mark_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          title: Text(
            question,
            style: AppTypography.body2.copyWith(fontSize: 13),
          ),
          children: [
            Text(
              answer,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (200 + index * 60).ms).fadeIn().slideX(begin: 0.03);
  }
}

class _ReportIssueCard extends StatelessWidget {
  const _ReportIssueCard({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.report_problem_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Something went wrong?',
                      style: AppTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Describe your issue and we\'ll help you out',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error.withValues(alpha: 0.12),
                foregroundColor: AppColors.error,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => launchUrl(Uri(
                scheme: 'mailto',
                path: email,
                query: 'subject=Issue Report — Chizze App',
              )),
              icon: const Icon(Icons.email_rounded, size: 18),
              label: const Text('Report via Email'),
            ),
          ),
        ],
      ),
    ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.05);
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.icon,
    required this.title,
    required this.url,
    required this.index,
  });
  final IconData icon;
  final String title;
  final String url;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListTile(
        leading: Icon(icon, size: 20, color: AppColors.textSecondary),
        title: Text(title, style: AppTypography.body2),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppColors.textTertiary,
        ),
        onTap: () => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        dense: true,
      ),
    ).animate(delay: (600 + index * 60).ms).fadeIn().slideX(begin: 0.03);
  }
}
