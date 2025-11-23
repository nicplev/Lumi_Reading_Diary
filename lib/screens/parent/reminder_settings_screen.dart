import 'package:flutter/material.dart';
import 'package:lumi_reading_tracker/services/notification_service.dart';
import 'package:lumi_reading_tracker/core/theme/app_colors.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_text_styles.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_spacing.dart';
import 'package:lumi_reading_tracker/core/theme/lumi_borders.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_buttons.dart';
import 'package:lumi_reading_tracker/core/widgets/lumi/lumi_card.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Reminder settings screen for configuring daily reading reminders
class ReminderSettingsScreen extends StatefulWidget {
  final String studentName;

  const ReminderSettingsScreen({
    super.key,
    required this.studentName,
  });

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  final NotificationService _notificationService = NotificationService.instance;

  bool _remindersEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 18, minute: 0);
  bool _loading = true;

  // Smart reminder suggestions
  final List<Map<String, dynamic>> _suggestions = [
    {
      'time': const TimeOfDay(hour: 7, minute: 0),
      'label': '🌅 Morning',
      'emoji': '☕'
    },
    {
      'time': const TimeOfDay(hour: 15, minute: 0),
      'label': '📚 After School',
      'emoji': '🎒'
    },
    {
      'time': const TimeOfDay(hour: 18, minute: 0),
      'label': '🌆 Evening',
      'emoji': '🍽️'
    },
    {
      'time': const TimeOfDay(hour: 20, minute: 0),
      'label': '🌙 Bedtime',
      'emoji': '🛏️'
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    final enabled = await _notificationService.areRemindersEnabled();
    final time = await _notificationService.getReminderTime();

    setState(() {
      _remindersEnabled = enabled;
      if (time != null) {
        _reminderTime = TimeOfDay(hour: time['hour']!, minute: time['minute']!);
      }
      _loading = false;
    });
  }

  Future<void> _toggleReminders(bool enabled) async {
    if (enabled) {
      // Request permissions first
      final hasPermission = await _notificationService.requestPermissions();

      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Notification permissions required for reminders'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Schedule reminder
      await _notificationService.scheduleDailyReminder(
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        studentName: widget.studentName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Daily reminder set for ${_formatTime(_reminderTime)} 🔔',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      // Cancel reminder
      await _notificationService.cancelDailyReminder();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daily reminders disabled'),
          ),
        );
      }
    }

    setState(() => _remindersEnabled = enabled);
  }

  Future<void> _pickTime() async {
    final newTime = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AppColors.white,
              hourMinuteTextColor: AppColors.rosePink,
              dayPeriodTextColor: AppColors.rosePink,
              dialHandColor: AppColors.rosePink,
              dialBackgroundColor: AppColors.skyBlue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (newTime != null && newTime != _reminderTime) {
      setState(() => _reminderTime = newTime);

      // If reminders are enabled, reschedule with new time
      if (_remindersEnabled) {
        await _notificationService.scheduleDailyReminder(
          hour: _reminderTime.hour,
          minute: _reminderTime.minute,
          studentName: widget.studentName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Reminder time updated to ${_formatTime(_reminderTime)} 🔔',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    }
  }

  void _setSuggestionTime(TimeOfDay time) {
    setState(() => _reminderTime = time);

    if (_remindersEnabled) {
      _notificationService.scheduleDailyReminder(
        hour: time.hour,
        minute: time.minute,
        studentName: widget.studentName,
      );
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _testNotification() async {
    await _notificationService.testNotification();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test notification sent! Check your notifications.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: AppColors.rosePink,
                ),
              )
            : SingleChildScrollView(
                padding: LumiPadding.allS,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        LumiIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                        LumiGap.horizontalXS,
                        Text(
                          '🔔 Reminders',
                          style: LumiTextStyles.h2(),
                        ),
                      ],
                    ),
                    LumiGap.m,

                    // Enable/Disable toggle
                    _buildToggleCard(),
                    LumiGap.m,

                    if (_remindersEnabled) ...[
                      // Time picker
                      _buildTimePickerCard(),
                      LumiGap.m,

                      // Smart suggestions
                      _buildSuggestionsCard(),
                      LumiGap.m,

                      // Info card
                      _buildInfoCard(),
                      LumiGap.s,

                      // Test notification button
                      _buildTestButton(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildToggleCard() {
    return LumiCard(
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.warmOrange.withValues(alpha: 0.2),
            ),
            child: const Center(
              child: Text('🔔', style: TextStyle(fontSize: 32)),
            ),
          ),
          LumiGap.horizontalS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Reminders',
                  style: LumiTextStyles.h3(),
                ),
                LumiGap.xxs,
                Text(
                  'Get reminded to log reading',
                  style: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _remindersEnabled,
            onChanged: _toggleReminders,
            activeTrackColor: AppColors.warmOrange.withValues(alpha: 0.5),
            activeThumbColor: AppColors.warmOrange,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildTimePickerCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reminder Time',
            style: LumiTextStyles.h3(),
          ),
          LumiGap.s,
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: LumiSpacing.m,
                horizontal: LumiSpacing.m,
              ),
              decoration: BoxDecoration(
                color: AppColors.rosePink.withValues(alpha: 0.1),
                borderRadius: LumiBorders.large,
                border: Border.all(
                  color: AppColors.rosePink,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.access_time,
                    color: AppColors.rosePink,
                    size: 32,
                  ),
                  LumiGap.horizontalS,
                  Text(
                    _formatTime(_reminderTime),
                    style: LumiTextStyles.display(
                      color: AppColors.rosePink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          LumiGap.xs,
          Text(
            'Tap to change time',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ).copyWith(fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: 100.ms)
        .slideY(begin: 0.2, end: 0);
  }

  Widget _buildSuggestionsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: LumiSpacing.xxs),
          child: Text(
            'Quick Set',
            style: LumiTextStyles.h3(),
          ),
        ),
        LumiGap.xs,
        Wrap(
          spacing: LumiSpacing.listItemSpacing,
          runSpacing: LumiSpacing.listItemSpacing,
          children: _suggestions.map((suggestion) {
            final time = suggestion['time'] as TimeOfDay;
            final isSelected = time.hour == _reminderTime.hour &&
                time.minute == _reminderTime.minute;

            return GestureDetector(
              onTap: () => _setSuggestionTime(time),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: LumiSpacing.s,
                  vertical: LumiSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.skyBlue
                      : AppColors.white,
                  borderRadius: LumiBorders.medium,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.rosePink
                        : AppColors.charcoal.withValues(alpha: 0.3),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      suggestion['emoji'],
                      style: const TextStyle(fontSize: 20),
                    ),
                    LumiGap.horizontalXS,
                    Text(
                      suggestion['label'],
                      style: LumiTextStyles.body(
                        color: isSelected
                            ? AppColors.rosePink
                            : AppColors.charcoal,
                      ).copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: 200.ms)
        .slideY(begin: 0.2, end: 0);
  }

  Widget _buildInfoCard() {
    return Container(
      padding: LumiPadding.allS,
      decoration: BoxDecoration(
        color: AppColors.skyBlue,
        borderRadius: LumiBorders.large,
        border: Border.all(
          color: AppColors.rosePink.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: AppColors.rosePink,
            size: 24,
          ),
          LumiGap.horizontalXS,
          Expanded(
            child: Text(
              'Reminders help build consistent reading habits. You\'ll get a friendly notification at ${_formatTime(_reminderTime)} every day.',
              style: LumiTextStyles.body(
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 300.ms);
  }

  Widget _buildTestButton() {
    return Center(
      child: LumiSecondaryButton(
        onPressed: _testNotification,
        text: 'Test Notification',
        icon: Icons.notification_add,
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
  }
}
