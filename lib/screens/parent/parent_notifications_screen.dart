import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../data/models/parent_notification_model.dart';
import '../../data/models/user_model.dart';
import '../../services/staff_notification_service.dart';

class ParentNotificationsScreen extends StatelessWidget {
  const ParentNotificationsScreen({
    super.key,
    required this.user,
  });

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final service = StaffNotificationService.instance;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Notifications',
          style: LumiTextStyles.h2(color: AppColors.charcoal),
        ),
      ),
      body: StreamBuilder<List<ParentNotificationModel>>(
        stream: service.watchParentNotifications(user),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications =
              snapshot.data ?? const <ParentNotificationModel>[];
          if (notifications.isEmpty) {
            return Center(
              child: Text(
                'No notifications yet.',
                style: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: LumiPadding.allM,
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _NotificationCard(
                notification: notification,
                onTap: () async {
                  if (!notification.isRead) {
                    await service.markParentNotificationRead(
                      user: user,
                      notificationId: notification.id,
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  final ParentNotificationModel notification;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final deliveredLabel = notification.deliveredAt == null
        ? 'Just now'
        : DateFormat('EEE, d MMM • h:mm a').format(notification.deliveredAt!);

    return Material(
      color: AppColors.white,
      borderRadius: LumiBorders.large,
      child: InkWell(
        onTap: () {
          onTap();
        },
        borderRadius: LumiBorders.large,
        child: Container(
          padding: LumiPadding.allM,
          decoration: BoxDecoration(
            borderRadius: LumiBorders.large,
            border: Border.all(
              color: notification.isRead
                  ? AppColors.divider
                  : AppColors.rosePink.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      notification.title,
                      style: LumiTextStyles.body(
                        color: AppColors.charcoal,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!notification.isRead)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.rosePink,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                notification.body,
                style: LumiTextStyles.body(
                  color: AppColors.charcoal.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Tag(label: notification.messageType.replaceAll('_', ' ')),
                  _Tag(label: 'From ${notification.senderName}'),
                  _Tag(label: deliveredLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.rosePink.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: LumiTextStyles.caption(color: AppColors.rosePink)
            .copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
