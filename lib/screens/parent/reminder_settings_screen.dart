import 'package:flutter/material.dart';
import 'package:lumi_reading_tracker/services/notification_service.dart';
import 'package:lumi_reading_tracker/core/theme/app_colors.dart';
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
    {'time': const TimeOfDay(hour: 7, minute: 0), 'label': '🌅 Morning', 'emoji': '☕'},
    {'time': const TimeOfDay(hour: 15, minute: 0), 'label': '📚 After School', 'emoji': '🎒'},
    {'time': const TimeOfDay(hour: 18, minute: 0), 'label': '🌆 Evening', 'emoji': '🍽️'},
    {'time': const TimeOfDay(hour': 20, minute: 0), 'label': '🌙 Bedtime', 'emoji': '🛏️'},
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
            const SnackBar(
              content: Text('Notification permissions required for reminders'),
              backgroundColor: Colors.red,
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
            backgroundColor: Colors.green,
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
              backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
              hourMinuteTextColor: Colors.white,
              dayPeriodTextColor: Colors.white,
              dialHandColor: AppColors.secondaryOrange,
              dialBackgroundColor: AppColors.primaryBlue.withOpacity(0.2),
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
              backgroundColor: Colors.green,
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryBlue.withOpacity(0.1),
              AppColors.secondaryOrange.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '🔔 Reminders',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Enable/Disable toggle
                      _buildToggleCard(),
                      const SizedBox(height: 24),

                      if (_remindersEnabled) ...[
                        // Time picker
                        _buildTimePickerCard(),
                        const SizedBox(height: 24),

                        // Smart suggestions
                        _buildSuggestionsCard(),
                        const SizedBox(height: 24),

                        // Info card
                        _buildInfoCard(),
                        const SizedBox(height: 16),

                        // Test notification button
                        _buildTestButton(),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildToggleCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.2),
            Colors.white.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.secondaryOrange.withOpacity(0.3),
                  AppColors.secondaryOrange.withOpacity(0.1),
                ],
              ),
            ),
            child: const Center(
              child: Text('🔔', style: TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Reminders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Get reminded to log reading',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _remindersEnabled,
            onChanged: _toggleReminders,
            activeColor: AppColors.secondaryOrange,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildTimePickerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.2),
            Colors.white.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reminder Time',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primaryBlue.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _formatTime(_reminderTime),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap to change time',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.6),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildSuggestionsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Quick Set',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _suggestions.map((suggestion) {
            final time = suggestion['time'] as TimeOfDay;
            final isSelected = time.hour == _reminderTime.hour &&
                time.minute == _reminderTime.minute;

            return GestureDetector(
              onTap: () => _setSuggestionTime(time),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            AppColors.secondaryOrange.withOpacity(0.3),
                            AppColors.secondaryOrange.withOpacity(0.2),
                          ],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.2),
                            Colors.white.withOpacity(0.1),
                          ],
                        ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.secondaryOrange.withOpacity(0.5)
                        : Colors.white.withOpacity(0.3),
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
                    const SizedBox(width: 8),
                    Text(
                      suggestion['label'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Reminders help build consistent reading habits. You\'ll get a friendly notification at ${_formatTime(_reminderTime)} every day.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 300.ms);
  }

  Widget _buildTestButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _testNotification,
        icon: const Icon(Icons.notification_add),
        label: const Text('Test Notification'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 400.ms);
  }
}
