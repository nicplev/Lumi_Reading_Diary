import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../theme/section_theme.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../data/models/parent_notification_model.dart';
import '../../data/models/user_model.dart';
import '../../services/staff_notification_service.dart';
import '../../core/widgets/lumi/lumi_toast.dart';

class ParentNotificationsScreen extends StatefulWidget {
  const ParentNotificationsScreen({
    super.key,
    required this.user,
  });

  final UserModel user;

  @override
  State<ParentNotificationsScreen> createState() =>
      _ParentNotificationsScreenState();
}

class _ParentNotificationsScreenState
    extends State<ParentNotificationsScreen> {
  final _service = StaffNotificationService.instance;
  late final StreamSubscription<List<ParentNotificationModel>> _sub;
  List<ParentNotificationModel> _notifications = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = _service.watchParentNotifications(widget.user).listen((data) {
      if (mounted) {
        setState(() {
          _notifications = data;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        ),
        title: Text('Clear all notifications?', style: LumiType.subhead),
        content: Text("This can't be undone.", style: LumiType.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: LumiType.button.copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Clear all',
                style: LumiType.button.copyWith(color: LumiTokens.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await _service.clearAllParentNotifications(widget.user);
      } catch (_) {
        // The stream re-emits the server state, so the list restores itself —
        // just tell the user why.
        if (mounted) {
          showLumiToast(
            message: "Couldn't clear notifications. Please try again.",
            type: LumiToastType.error,
          );
        }
      }
    }
  }

  Future<void> _dismissNotification(String notificationId) async {
    try {
      await _service.deleteParentNotification(
        user: widget.user,
        notificationId: notificationId,
      );
    } catch (_) {
      if (mounted) {
        showLumiToast(
          message: "Couldn't dismiss that notification.",
          type: LumiToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LumiSectionScope(
      section: LumiSectionTheme.home,
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        appBar: AppBar(
          backgroundColor: LumiTokens.cream,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: LumiTokens.ink),
          title: Text('Notifications', style: LumiType.subhead),
          actions: [
            if (_notifications.isNotEmpty)
              TextButton(
                onPressed: _confirmClearAll,
                child: Text(
                  'Clear all',
                  style: LumiType.body.copyWith(color: LumiTokens.muted),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: LumiTokens.red),
              )
            : _notifications.isEmpty
                ? Center(
                    child: Text(
                      'No notifications yet.',
                      style: LumiType.body.copyWith(color: LumiTokens.muted),
                    ),
                  )
                : ListView.separated(
                    padding: LumiPadding.allM,
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return Dismissible(
                        key: ValueKey(notification.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: LumiTokens.red.withValues(alpha: 0.1),
                            borderRadius: LumiBorders.large,
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: LumiTokens.red,
                          ),
                        ),
                        onDismissed: (_) {
                          _dismissNotification(notification.id);
                        },
                        child: _NotificationCard(
                          notification: notification,
                          onTap: () async {
                            if (!notification.isRead) {
                              await _service.markParentNotificationRead(
                                user: widget.user,
                                notificationId: notification.id,
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
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
    final accent = context.sectionTheme.accent;
    final isUnread = !notification.isRead;
    final deliveredLabel = notification.deliveredAt == null
        ? 'Just now'
        : DateFormat("EEE, d MMM 'at' h:mm a").format(notification.deliveredAt!);
    final category = notification.messageType.replaceAll('_', ' ').toUpperCase();
    final meta = 'From ${notification.senderName}  ·  $deliveredLabel';

    return Material(
      color: isUnread ? accent.withValues(alpha: 0.04) : LumiTokens.paper,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: InkWell(
        onTap: () {
          onTap();
        },
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(LumiTokens.space5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
            border: Border.all(color: LumiTokens.rule),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category,
                      style: LumiType.sectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isUnread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: LumiTokens.space2),
              Text(
                notification.title,
                style: LumiType.subhead,
              ),
              const SizedBox(height: LumiTokens.space1),
              Text(
                notification.body,
                style: LumiType.body.copyWith(color: LumiTokens.muted),
              ),
              const SizedBox(height: LumiTokens.space3),
              Text(
                meta,
                style: LumiType.caption.copyWith(color: LumiTokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
