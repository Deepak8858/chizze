import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/gold_provider.dart';

/// Chizze Gold membership screen — plans, status, subscribe/cancel
class GoldScreen extends ConsumerWidget {
  const GoldScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(goldProvider);

    // Listen for success/error messages
    ref.listen<GoldState>(goldProvider, (prev, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: AppColors.success,
          ),
        );
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
      body: CustomScrollView(
        slivers: [
          // ─── Gold AppBar ───
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      const Text('👑', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Chizze Gold',
                        style: AppTypography.h1.copyWith(
                          color: Colors.white,
                          fontSize: 28,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Premium dining experience',
                        style: AppTypography.body2.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              title: const Text('Chizze Gold'),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Active Subscription ───
                  if (state.isGoldMember && state.subscription != null)
                    _buildActiveSubscription(context, ref, state.subscription!)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.05),

                  if (state.isGoldMember)
                    const SizedBox(height: AppSpacing.xxl),

                  // ─── Benefits ───
                  _buildBenefits()
                      .animate(delay: 200.ms)
                      .fadeIn()
                      .slideY(begin: 0.05),
                  const SizedBox(height: AppSpacing.xxl),

                  // ─── Plans ───
                  if (!state.isGoldMember) ...[
                    Text('Choose Your Plan', style: AppTypography.h2),
                    const SizedBox(height: AppSpacing.md),
                    ...state.plans.asMap().entries.map(
                      (e) => _buildPlanCard(context, ref, e.value, e.key, state)
                          .animate(delay: (300 + e.key * 100).ms)
                          .fadeIn()
                          .slideY(begin: 0.05),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.massive),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSubscription(
    BuildContext context,
    WidgetRef ref,
    GoldSubscription sub,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👑', style: TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gold Member',
                      style: AppTypography.h3.copyWith(color: Colors.white),
                    ),
                    Text(
                      sub.planName,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  '${sub.daysRemaining}d left',
                  style: AppTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 1 - (sub.daysRemaining / 30).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Expires ${_formatDate(sub.expiresAt)}',
                style: AppTypography.overline.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              GestureDetector(
                onTap: () => _showCancelDialog(context, ref),
                child: Text(
                  'Cancel',
                  style: AppTypography.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBenefits() {
    final benefits = [
      ('🚚', 'Free Delivery', 'On every order, no minimum'),
      ('💰', 'Extra 10% Off', 'On top of existing offers'),
      ('⚡', 'Priority Support', 'Get help faster, always'),
      ('🌟', 'Exclusive Deals', 'Gold-only restaurant offers'),
      ('🎂', 'Birthday Treats', 'Special offers on your birthday'),
      ('🔔', 'Early Access', 'New restaurants & features first'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gold Benefits', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.md),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.6,
          ),
          itemCount: benefits.length,
          itemBuilder: (context, index) {
            final (emoji, title, desc) = benefits[index];
            return GlassCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    title,
                    style: AppTypography.body2.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    desc,
                    style: AppTypography.overline.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 9,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    WidgetRef ref,
    GoldPlan plan,
    int index,
    GoldState state,
  ) {
    final isPopular = index == 1; // Quarterly = most popular

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plan.name, style: AppTypography.h3),
                          Text(
                            plan.description,
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${plan.price.toInt()}',
                          style: AppTypography.h2.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          '/${plan.durationLabel}',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ...plan.benefits.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(b, style: AppTypography.caption),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: state.isLoading
                        ? null
                        : () => ref
                              .read(goldProvider.notifier)
                              .subscribe(plan.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular
                          ? const Color(0xFFFFD700)
                          : AppColors.primary,
                      foregroundColor: isPopular ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                    ),
                    child: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            isPopular
                                ? 'Get Gold — Best Value'
                                : 'Subscribe',
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (isPopular)
            Positioned(
              top: -10,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  '⭐ Most Popular',
                  style: AppTypography.overline.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Gold?'),
        content: const Text(
          'You\'ll lose all Gold benefits including free delivery and exclusive deals. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Gold'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(goldProvider.notifier).cancel();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel Membership'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
