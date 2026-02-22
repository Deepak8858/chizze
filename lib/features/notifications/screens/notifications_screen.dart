import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/notifications_provider.dart';

/// Selected notification filter
final _notifFilterProvider = StateProvider<NotificationType?>((ref) => null);

/// Notifications center — grouped list with read/unread + tab filters
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allNotifications = ref.watch(notificationsProvider);
    final notifier = ref.read(notificationsProvider.notifier);
    final unread = notifier.unreadCount;
    final activeFilter = ref.watch(_notifFilterProvider);

    // Apply filter
    final notifications = activeFilter == null
        ? allNotifications
        : allNotifications.where((n) => n.type == activeFilter).toList();

    // Group by today / earlier
    final today = <AppNotification>[];
    final earlier = <AppNotification>[];
    final now = DateTime.now();
    for (final n in notifications) {
      if (now.difference(n.createdAt).inHours < 24) {
        today.add(n);
      } else {
        earlier.add(n);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => notifier.markAllRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ─── Filter Chips ───
          _buildFilterChips(ref, activeFilter),
          const SizedBox(height: AppSpacing.sm),
          // ─── Notification List ───
          Expanded(
            child: notifications.isEmpty
                ? _buildEmpty()
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    children: [
                      if (today.isNotEmpty) ...[
                        Text(
                          'Today',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...today.asMap().entries.map(
                          (e) => _buildNotificationCard(
                            context,
                            ref,
                            e.value,
                            e.key,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (earlier.isNotEmpty) ...[
                        Text(
                          'Earlier',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...earlier.asMap().entries.map(
                          (e) => _buildNotificationCard(
                            context,
                            ref,
                            e.value,
                            e.key + today.length,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(WidgetRef ref, NotificationType? active) {
    final filters = <(String, NotificationType?)>[
      ('All', null),
      ('📦 Orders', NotificationType.order),
      ('🎁 Offers', NotificationType.promo),
      ('⚙️ Updates', NotificationType.system),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final (label, type) = filters[index];
          final isActive = active == type;
          return GestureDetector(
            onTap: () => ref.read(_notifFilterProvider.notifier).state = type,
            child: AnimatedContainer(
              duration: 200.ms,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔔', style: TextStyle(fontSize: 48)),
          const SizedBox(height: AppSpacing.xl),
          Text('No notifications yet', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'We\'ll notify you about orders & offers',
            style: AppTypography.body2,
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GestureDetector(
        onTap: () {
          ref.read(notificationsProvider.notifier).markRead(n.id);
          if (n.actionRoute != null) context.push(n.actionRoute!);
        },
        child: GlassCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: n.isRead
                      ? AppColors.surfaceElevated
                      : AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    n.type.emoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: AppTypography.body2.copyWith(
                              fontWeight: n.isRead
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n.body,
                      style: AppTypography.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(n.createdAt),
                      style: AppTypography.overline.copyWith(
                        fontSize: 9,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (index * 50).ms).fadeIn().slideX(begin: 0.02);
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
