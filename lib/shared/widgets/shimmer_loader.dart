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
