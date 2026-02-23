import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/referral_provider.dart';

/// Referral screen — share code, apply code, view history
class ReferralScreen extends ConsumerStatefulWidget {
  /// Optional referral code from deep link (chizze://referral?code=XYZ)
  final String? referralCode;

  const ReferralScreen({super.key, this.referralCode});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-fill referral code from deep link
    if (widget.referralCode != null && widget.referralCode!.isNotEmpty) {
      _codeController.text = widget.referralCode!;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referralProvider);

    // Listen for success/error messages
    ref.listen<ReferralState>(referralProvider, (prev, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: AppColors.success,
          ),
        );
        _codeController.clear();
      }
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Refer & Earn')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          // ─── Hero Banner ───
          _buildHeroBanner(state).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),
          const SizedBox(height: AppSpacing.xxl),

          // ─── Your Code Section ───
          _buildYourCode(state).animate(delay: 200.ms).fadeIn().slideY(begin: 0.05),
          const SizedBox(height: AppSpacing.xxl),

          // ─── Apply Code Section ───
          _buildApplyCode(state).animate(delay: 300.ms).fadeIn().slideY(begin: 0.05),
          const SizedBox(height: AppSpacing.xxl),

          // ─── How It Works ───
          _buildHowItWorks().animate(delay: 400.ms).fadeIn().slideY(begin: 0.05),
          const SizedBox(height: AppSpacing.xxl),

          // ─── Referral History ───
          _buildHistory(state),
          const SizedBox(height: AppSpacing.massive),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(ReferralState state) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Column(
        children: [
          const Text('🎁', style: TextStyle(fontSize: 48)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Refer Friends, Earn ₹100',
            style: AppTypography.h2.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Share your code with friends. When they order,\nyou both get ₹100 off!',
            style: AppTypography.body2.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total earned: ',
                  style: AppTypography.body2.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '₹${state.totalEarned.toInt()}',
                  style: AppTypography.h3.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYourCode(ReferralState state) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Referral Code', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.base,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  state.referralCode ?? '...',
                  style: AppTypography.h2.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                IconButton(
                  onPressed: () {
                    if (state.referralCode != null) {
                      Clipboard.setData(
                        ClipboardData(text: state.referralCode!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Share.share(
                  'Use my referral code ${state.referralCode ?? ''} on Chizze and get ₹100 off your first order! 🍕',
                  subject: 'Join Chizze!',
                );
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Share with Friends'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyCode(ReferralState state) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Have a Referral Code?', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    hintText: 'Enter code',
                    hintStyle: AppTypography.body2.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMd,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  style: AppTypography.body1.copyWith(letterSpacing: 2),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              ElevatedButton(
                onPressed: state.isLoading
                    ? null
                    : () {
                        final code = _codeController.text.trim();
                        if (code.isNotEmpty) {
                          ref
                              .read(referralProvider.notifier)
                              .applyCode(code);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                child: state.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    final steps = [
      ('📤', 'Share Code', 'Send your code to friends'),
      ('📱', 'Friend Signs Up', 'They use your code on Chizze'),
      ('🍕', 'Friend Orders', 'They place their first order'),
      ('💰', 'You Both Earn', '₹100 credit for both of you!'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How It Works', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.md),
        ...steps.asMap().entries.map((e) {
          final (emoji, title, desc) = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.body1),
                      Text(desc, style: AppTypography.caption),
                    ],
                  ),
                ),
              ],
            ),
          ).animate(delay: (500 + e.key * 100).ms).fadeIn().slideX(begin: 0.05);
        }),
      ],
    );
  }

  Widget _buildHistory(ReferralState state) {
    if (state.referrals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Referral History', style: AppTypography.h3),
        const SizedBox(height: AppSpacing.md),
        ...state.referrals.asMap().entries.map((e) {
          final referral = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        referral.referredUserName.isNotEmpty
                            ? referral.referredUserName[0]
                            : '?',
                        style: AppTypography.h3.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          referral.referredUserName,
                          style: AppTypography.body2,
                        ),
                        Text(
                          _timeAgo(referral.createdAt),
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '+₹${referral.rewardAmount.toInt()}',
                    style: AppTypography.body1.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ).animate(delay: (600 + e.key * 80).ms).fadeIn().slideX(begin: 0.03);
        }),
      ],
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
