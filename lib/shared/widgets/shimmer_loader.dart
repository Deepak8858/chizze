import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/theme.dart';

/// Skeleton loading shimmer for cards and list items
class ShimmerLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = AppSpacing.radiusMd,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Skeleton loader for a restaurant card
class RestaurantCardSkeleton extends StatelessWidget {
  const RestaurantCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerLoader(height: 180, borderRadius: AppSpacing.radiusLg),
          const SizedBox(height: AppSpacing.md),
          const ShimmerLoader(height: 18, width: 200),
          const SizedBox(height: AppSpacing.sm),
          const ShimmerLoader(height: 14, width: 140),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: const [
              ShimmerLoader(height: 14, width: 60),
              SizedBox(width: AppSpacing.sm),
              ShimmerLoader(height: 14, width: 80),
              SizedBox(width: AppSpacing.sm),
              ShimmerLoader(height: 14, width: 50),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen skeleton for a list
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const ListSkeleton({
    super.key,
    this.itemCount = 5,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// Skeleton for a simple card row (icon + two text lines)
class CardRowSkeleton extends StatelessWidget {
  const CardRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const ShimmerLoader(height: 48, width: 48, borderRadius: AppSpacing.radiusMd),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerLoader(height: 16, width: 160),
                SizedBox(height: AppSpacing.xs),
                ShimmerLoader(height: 12, width: 100),
              ],
            ),
          ),
          const ShimmerLoader(height: 14, width: 50),
        ],
      ),
    );
  }
}

/// Skeleton for an order card (image + title + status chips)
class OrderCardSkeleton extends StatelessWidget {
  const OrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              ShimmerLoader(height: 56, width: 56, borderRadius: AppSpacing.radiusMd),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerLoader(height: 16, width: 180),
                    SizedBox(height: AppSpacing.xs),
                    ShimmerLoader(height: 12, width: 120),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: const [
              ShimmerLoader(height: 24, width: 70, borderRadius: 12),
              SizedBox(width: AppSpacing.sm),
              ShimmerLoader(height: 24, width: 90, borderRadius: 12),
            ],
          ),
          const Divider(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// Skeleton for earnings dashboard (stat cards + chart)
class EarningsSkeleton extends StatelessWidget {
  const EarningsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          // Stat cards row
          Row(
            children: const [
              Expanded(child: ShimmerLoader(height: 90, borderRadius: AppSpacing.radiusLg)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: ShimmerLoader(height: 90, borderRadius: AppSpacing.radiusLg)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: const [
              Expanded(child: ShimmerLoader(height: 90, borderRadius: AppSpacing.radiusLg)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: ShimmerLoader(height: 90, borderRadius: AppSpacing.radiusLg)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          // Chart placeholder
          const ShimmerLoader(height: 200, borderRadius: AppSpacing.radiusLg),
          const SizedBox(height: AppSpacing.xl),
          // List items
          ...List.generate(3, (_) => const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: ShimmerLoader(height: 60, borderRadius: AppSpacing.radiusMd),
          )),
        ],
      ),
    );
  }
}
