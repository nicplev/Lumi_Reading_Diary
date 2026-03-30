import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../data/models/class_model.dart';
import '../../data/models/notification_campaign_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/staff_notification_service.dart';

class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({
    super.key,
    required this.user,
  });

  final UserModel user;

  @override
  State<StaffNotificationsScreen> createState() =>
      _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen>
    with SingleTickerProviderStateMixin {
  final StaffNotificationService _service = StaffNotificationService.instance;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  late final TabController _tabController;
  List<ClassModel> _classes = const [];
  List<StudentModel> _students = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _audienceType = 'classes';
  String _messageType = 'reading_reminder';
  DateTime? _scheduledFor;
  final Set<String> _selectedClassIds = <String>{};
  final Set<String> _selectedStudentIds = <String>{};

  bool get _canTargetWholeSchool => widget.user.role == UserRole.schoolAdmin;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAudienceData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadAudienceData() async {
    setState(() => _isLoading = true);
    try {
      final classes = await _service.loadAvailableClasses(widget.user);
      final students = await _service.loadAvailableStudents(widget.user);
      if (!mounted) return;
      setState(() {
        _classes = [...classes]..sort((a, b) => a.name.compareTo(b.name));
        _students = [...students]
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load notification audience: $error')),
      );
    }
  }

  Future<void> _refreshStudents() async {
    final students = await _service.loadAvailableStudents(
      widget.user,
      classIds: _selectedClassIds.toList(),
    );
    if (!mounted) return;
    setState(() {
      _students = [...students]
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
      _selectedStudentIds.removeWhere(
        (studentId) => !_students.any((student) => student.id == studentId),
      );
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledFor ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _scheduledFor ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _scheduledFor = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _pickClasses() async {
    final selected = Set<String>.from(_selectedClassIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Choose Classes'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _classes.map((classModel) {
                    return CheckboxListTile(
                      value: selected.contains(classModel.id),
                      title: Text(classModel.name),
                      subtitle: Text(
                        '${classModel.studentIds.length} students',
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          if (value == true) {
                            selected.add(classModel.id);
                          } else {
                            selected.remove(classModel.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    setState(() {
      _selectedClassIds
        ..clear()
        ..addAll(result);
      if (_audienceType != 'students') {
        _selectedStudentIds.clear();
      }
    });
    await _refreshStudents();
  }

  Future<void> _pickStudents() async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No students available for this audience.')),
      );
      return;
    }

    final selected = Set<String>.from(_selectedStudentIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Choose Students'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _students.map((student) {
                    final classNames = _classes
                        .where((classModel) => classModel.id == student.classId)
                        .map((classModel) => classModel.name)
                        .toList();
                    return CheckboxListTile(
                      value: selected.contains(student.id),
                      title: Text(student.fullName),
                      subtitle: Text(
                        classNames.isNotEmpty
                            ? classNames.first
                            : 'Class ${student.classId}',
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          if (value == true) {
                            selected.add(student.id);
                          } else {
                            selected.remove(student.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    setState(() {
      _selectedStudentIds
        ..clear()
        ..addAll(result);
    });
  }

  Future<void> _submitCampaign() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final wasScheduled = _scheduledFor != null;

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a title and message before sending.')),
      );
      return;
    }

    if (_audienceType == 'classes' && _selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one class.')),
      );
      return;
    }

    if (_audienceType == 'students' && _selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one student.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _service.createCampaign(
        user: widget.user,
        title: title,
        body: body,
        messageType: _messageType,
        audienceType: _audienceType,
        classIds: _selectedClassIds.toList(),
        studentIds: _selectedStudentIds.toList(),
        scheduledFor: _scheduledFor,
      );
      if (!mounted) return;
      _titleController.clear();
      _bodyController.clear();
      setState(() {
        _selectedClassIds.clear();
        _selectedStudentIds.clear();
        _scheduledFor = null;
        _audienceType = 'classes';
        _messageType = 'reading_reminder';
      });
      await _refreshStudents();
      if (!mounted) return;
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasScheduled
                ? 'Scheduled notification saved.'
                : 'Notification queued for delivery.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _audienceSummary() {
    switch (_audienceType) {
      case 'students':
        return '${_selectedStudentIds.length} student${_selectedStudentIds.length == 1 ? '' : 's'} selected';
      case 'school':
        return 'Whole school parent audience';
      case 'classes':
      default:
        return '${_selectedClassIds.length} class${_selectedClassIds.length == 1 ? '' : 'es'} selected';
    }
  }

  String _campaignSubtitle(NotificationCampaignModel campaign) {
    final format = DateFormat('EEE d MMM, h:mm a');
    if (campaign.status == 'scheduled' && campaign.scheduledFor != null) {
      return 'Scheduled for ${format.format(campaign.scheduledFor!)}';
    }
    if (campaign.sentAt != null) {
      return 'Sent ${format.format(campaign.sentAt!)}';
    }
    if (campaign.createdAt != null) {
      return 'Created ${format.format(campaign.createdAt!)}';
    }
    return campaign.status;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'sent':
        return AppColors.mintGreen;
      case 'partial':
        return AppColors.warmOrange;
      case 'failed':
        return AppColors.error;
      case 'scheduled':
        return AppColors.skyBlue;
      default:
        return AppColors.teacherPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.teacherBackground,
      appBar: AppBar(
        backgroundColor: AppColors.teacherBackground,
        elevation: 0,
        title: const Text('Notifications'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.teacherPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.teacherPrimary,
          tabs: const [
            Tab(text: 'Compose'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildComposeTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildComposeTab() {
    final audienceOptions = <Map<String, String>>[
      {'value': 'classes', 'label': 'Classes'},
      {'value': 'students', 'label': 'Students'},
      if (_canTargetWholeSchool) {'value': 'school', 'label': 'Whole School'},
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            border: Border.all(color: AppColors.teacherBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send a reminder', style: TeacherTypography.h3),
              const SizedBox(height: 8),
              Text(
                'Parents receive this as a push notification and as an inbox item.',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _messageType,
                decoration: const InputDecoration(labelText: 'Message type'),
                items: const [
                  DropdownMenuItem(
                    value: 'reading_reminder',
                    child: Text('Reading reminder'),
                  ),
                  DropdownMenuItem(
                    value: 'announcement',
                    child: Text('Announcement'),
                  ),
                  DropdownMenuItem(
                    value: 'general',
                    child: Text('General'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _messageType = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Books come back tomorrow',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bodyController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText:
                      'Please send readers back tomorrow so we can swap books for the weekend.',
                ),
              ),
              const SizedBox(height: 20),
              Text('Audience', style: TeacherTypography.sectionHeader),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: audienceOptions.map((option) {
                  return ChoiceChip(
                    label: Text(option['label']!),
                    selected: _audienceType == option['value'],
                    onSelected: (_) async {
                      setState(() {
                        _audienceType = option['value']!;
                        if (_audienceType == 'school') {
                          _selectedClassIds.clear();
                          _selectedStudentIds.clear();
                        }
                      });
                      if (_audienceType == 'students') {
                        await _refreshStudents();
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (_audienceType == 'classes') ...[
                OutlinedButton.icon(
                  onPressed: _pickClasses,
                  icon: const Icon(Icons.class_outlined),
                  label: const Text('Choose classes'),
                ),
                const SizedBox(height: 8),
              ],
              if (_audienceType == 'students') ...[
                OutlinedButton.icon(
                  onPressed: _pickClasses,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: Text(
                    _selectedClassIds.isEmpty
                        ? 'Filter by classes (optional)'
                        : 'Update class filter',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickStudents,
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Choose students'),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _audienceSummary(),
                style: TeacherTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schedule for later'),
                value: _scheduledFor != null,
                onChanged: (value) async {
                  if (!value) {
                    setState(() => _scheduledFor = null);
                    return;
                  }
                  await _pickDateTime();
                },
              ),
              if (_scheduledFor != null) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    DateFormat('EEEE, d MMMM • h:mm a').format(_scheduledFor!),
                  ),
                  subtitle: const Text('Tap to change'),
                  trailing: const Icon(Icons.schedule),
                  onTap: _pickDateTime,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitCampaign,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _scheduledFor == null ? Icons.send : Icons.schedule,
                        ),
                  label: Text(
                    _scheduledFor == null
                        ? 'Send Notification'
                        : 'Schedule Notification',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<List<NotificationCampaignModel>>(
      stream: _service.watchCampaigns(widget.user),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final campaigns = snapshot.data ?? const <NotificationCampaignModel>[];
        if (campaigns.isEmpty) {
          return Center(
            child: Text(
              'No notification campaigns yet.',
              style: TeacherTypography.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          itemCount: campaigns.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final campaign = campaigns[index];
            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
                border: Border.all(color: AppColors.teacherBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          campaign.title,
                          style: TeacherTypography.h3,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(campaign.status)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          campaign.status.toUpperCase(),
                          style: TeacherTypography.caption.copyWith(
                            color: _statusColor(campaign.status),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    campaign.body,
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _campaignSubtitle(campaign),
                    style: TeacherTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        icon: Icons.people_alt_outlined,
                        label: '${campaign.recipientParentCount} parents',
                      ),
                      _StatChip(
                        icon: Icons.child_care_outlined,
                        label: '${campaign.recipientStudentCount} students',
                      ),
                      _StatChip(
                        icon: Icons.notifications_active_outlined,
                        label:
                            '${campaign.pushSentCount} sent / ${campaign.pushFailedCount} failed',
                      ),
                    ],
                  ),
                  if ((campaign.errorSummary ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      campaign.errorSummary!,
                      style: TeacherTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.teacherSurfaceTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.teacherPrimary),
          const SizedBox(width: 6),
          Text(label, style: TeacherTypography.bodySmall),
        ],
      ),
    );
  }
}
