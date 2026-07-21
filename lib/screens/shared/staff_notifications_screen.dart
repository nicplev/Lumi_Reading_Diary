import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/class_model.dart';
import '../../data/models/notification_campaign_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/staff_notification_service.dart';

/// Flat, bordered "bento" card surface used across this screen.
BoxDecoration _lumiCard() => BoxDecoration(
      color: LumiTokens.paper,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      border: Border.all(color: LumiTokens.rule),
    );

class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({
    super.key,
    required this.user,
    this.preFilledTitle,
    this.preFilledBody,
    this.preSelectedStudentIds,
  });

  final UserModel user;
  final String? preFilledTitle;
  final String? preFilledBody;
  final Set<String>? preSelectedStudentIds;

  @override
  State<StaffNotificationsScreen> createState() =>
      _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxTitleLength = 120;
  static const int _maxBodyLength = 1000;

  final StaffNotificationService _service = StaffNotificationService.instance;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  late final TabController _tabController;
  List<ClassModel> _classes = const [];
  List<StudentModel> _students = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _audienceType = 'classes';
  // Message type is no longer teacher-selectable in the compose UI — the chip
  // row caused layout issues on smaller devices and the value never affected
  // delivery (it isn't used for channel selection, filtering or analytics).
  // It still rides along to createCampaign as a stable label for the History
  // view and the parent notification category, so it's kept as a constant that
  // preserves the prior parent-facing behaviour.
  static const String _messageType = 'reading_reminder';
  DateTime? _scheduledFor;
  final Set<String> _selectedClassIds = <String>{};
  final Set<String> _selectedStudentIds = <String>{};


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });

    if (widget.preFilledTitle != null) {
      _titleController.text = widget.preFilledTitle!;
    }
    if (widget.preFilledBody != null) {
      _bodyController.text = widget.preFilledBody!;
    }
    if (widget.preSelectedStudentIds != null &&
        widget.preSelectedStudentIds!.isNotEmpty) {
      _selectedStudentIds.addAll(widget.preSelectedStudentIds!);
      _audienceType = 'students';
    }

    _loadAudienceData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  // ─── Data Loading ───────────────────────────────────────────────

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
      showLumiToast(
        message: 'Failed to load notification audience: $error',
        type: LumiToastType.error,
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

  // ─── Pickers ────────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _scheduledFor ?? now.add(const Duration(hours: 1));

    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var selectedDate = DateTime(initial.year, initial.month, initial.day);
        var selectedHour = initial.hour;
        var selectedMinute = (initial.minute ~/ 5) * 5; // Round to nearest 5

        return StatefulBuilder(
          builder: (context, setModalState) {
            // Generate date options: today + next 30 days
            final dates = List.generate(31, (i) => DateTime(
              now.year, now.month, now.day,
            ).add(Duration(days: i)));

            String formatDateLabel(DateTime d) {
              final today = DateTime(now.year, now.month, now.day);
              final tomorrow = today.add(const Duration(days: 1));
              if (d == today) return 'Today';
              if (d == tomorrow) return 'Tomorrow';
              return DateFormat('EEE, d MMM').format(d);
            }

            return Container(
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(LumiTokens.radiusXL),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: LumiTokens.rule,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: LumiTokens.yellow
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusMedium),
                            ),
                            child: const Icon(Icons.schedule,
                                color: LumiTokens.yellow, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text('Schedule', style: LumiType.subhead),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Date picker — horizontal scroll
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text('DATE',
                              style: LumiType.sectionLabel),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: dates.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final d = dates[index];
                          final isActive = d == selectedDate;
                          return GestureDetector(
                            onTap: () =>
                                setModalState(() => selectedDate = d),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? LumiTokens.blue
                                    : LumiTokens.paper,
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusPill),
                                border: Border.all(
                                  color: isActive
                                      ? LumiTokens.blue
                                      : LumiTokens.rule,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  formatDateLabel(d),
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isActive
                                        ? LumiTokens.paper
                                        : LumiTokens.muted,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Time picker
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Text('TIME',
                              style: LumiType.sectionLabel),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 20),
                        decoration: BoxDecoration(
                          color: LumiTokens.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                              LumiTokens.radiusLarge),
                          border: Border.all(
                              color: LumiTokens.rule),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Hour column
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => setModalState(() =>
                                      selectedHour = (selectedHour + 1) % 24),
                                  child: Container(
                                    width: 40,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: LumiTokens.paper,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.keyboard_arrow_up,
                                        color: LumiTokens.blue, size: 22),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    // Show inline text input for hour
                                    _showTimeInputDialog(
                                      context,
                                      'Hour',
                                      selectedHour,
                                      0,
                                      23,
                                      (val) => setModalState(() => selectedHour = val),
                                    );
                                  },
                                  child: Container(
                                    width: 64,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: LumiTokens.paper,
                                      borderRadius: BorderRadius.circular(
                                          LumiTokens.radiusMedium),
                                      border: Border.all(
                                          color: LumiTokens.blue,
                                          width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        selectedHour.toString().padLeft(2, '0'),
                                        style: LumiType.heading.copyWith(
                                            color: LumiTokens.blue),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => setModalState(() =>
                                      selectedHour = (selectedHour - 1 + 24) % 24),
                                  child: Container(
                                    width: 40,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: LumiTokens.paper,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.keyboard_arrow_down,
                                        color: LumiTokens.blue, size: 22),
                                  ),
                                ),
                              ],
                            ),
                            // Colon separator
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(':',
                                  style: LumiType.heading
                                      .copyWith(color: LumiTokens.muted)),
                            ),
                            // Minute column
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => setModalState(() =>
                                      selectedMinute = (selectedMinute + 5) % 60),
                                  child: Container(
                                    width: 40,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: LumiTokens.paper,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.keyboard_arrow_up,
                                        color: LumiTokens.blue, size: 22),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    _showTimeInputDialog(
                                      context,
                                      'Minute',
                                      selectedMinute,
                                      0,
                                      59,
                                      (val) => setModalState(() => selectedMinute = val),
                                    );
                                  },
                                  child: Container(
                                    width: 64,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: LumiTokens.paper,
                                      borderRadius: BorderRadius.circular(
                                          LumiTokens.radiusMedium),
                                      border: Border.all(
                                          color: LumiTokens.blue,
                                          width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        selectedMinute.toString().padLeft(2, '0'),
                                        style: LumiType.heading.copyWith(
                                            color: LumiTokens.blue),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => setModalState(() =>
                                      selectedMinute = (selectedMinute - 5 + 60) % 60),
                                  child: Container(
                                    width: 40,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: LumiTokens.paper,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.keyboard_arrow_down,
                                        color: LumiTokens.blue, size: 22),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Footer buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    Navigator.of(context).pop(),
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        LumiTokens.radiusMedium),
                                    border: Border.all(
                                        color:
                                            LumiTokens.rule),
                                  ),
                                  child: Center(
                                    child: Text('Cancel',
                                        style: LumiType.button
                                            .copyWith(
                                                color: LumiTokens.muted)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  final scheduled = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    selectedHour,
                                    selectedMinute,
                                  );
                                  Navigator.of(context)
                                      .pop(scheduled);
                                },
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: LumiTokens.blue,
                                    borderRadius: BorderRadius.circular(
                                        LumiTokens.radiusMedium),
                                  ),
                                  child: Center(
                                    child: Text('Confirm',
                                        style: LumiType.button),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) {
      if (mounted) setState(() => _scheduledFor = null);
      return;
    }

    setState(() => _scheduledFor = result);
  }

  Future<void> _pickClasses() async {
    final selected = Set<String>.from(_selectedClassIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(LumiTokens.radiusXL),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: LumiTokens.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: LumiTokens.blue
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                                LumiTokens.radiusMedium),
                          ),
                          child: const Icon(Icons.class_outlined,
                              color: LumiTokens.blue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text('Choose Classes',
                            style: LumiType.subhead),
                        const Spacer(),
                        Text('${selected.length} selected',
                            style: LumiType.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: LumiTokens.rule),
                  // List
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _classes.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: LumiTokens.rule
                            .withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final classModel = _classes[index];
                        final isSelected =
                            selected.contains(classModel.id);
                        return InkWell(
                          onTap: () {
                            setModalState(() {
                              if (isSelected) {
                                selected.remove(classModel.id);
                              } else {
                                selected.add(classModel.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: LumiTokens.blue
                                        .withValues(alpha: 0.14),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.class_,
                                      color: LumiTokens.blue,
                                      size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(classModel.name,
                                          style: LumiType.body
                                              .copyWith(
                                                  fontWeight:
                                                      FontWeight.w600)),
                                      Text(
                                        '${classModel.studentIds.length} students',
                                        style:
                                            LumiType.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(
                                      milliseconds: 200),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? LumiTokens.blue
                                        : Colors.transparent,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? LumiTokens.blue
                                          : LumiTokens.rule,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          size: 16,
                                          color: LumiTokens.paper)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Footer
                  Divider(height: 1, color: LumiTokens.rule),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    Navigator.of(context).pop(),
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        LumiTokens.radiusMedium),
                                    border: Border.all(
                                        color: LumiTokens.rule),
                                  ),
                                  child: Center(
                                    child: Text('Cancel',
                                        style: LumiType.button
                                            .copyWith(
                                                color: LumiTokens.muted)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.of(context)
                                    .pop(selected),
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: LumiTokens.blue,
                                    borderRadius: BorderRadius.circular(
                                        LumiTokens.radiusMedium),
                                  ),
                                  child: Center(
                                    child: Text('Apply',
                                        style: LumiType.button),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
      showLumiToast(
        message: 'No students available for this audience.',
        type: LumiToastType.error,
      );
      return;
    }

    final selected = Set<String>.from(_selectedStudentIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(LumiTokens.radiusXL),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: LumiTokens.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: LumiTokens.blue
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                                LumiTokens.radiusMedium),
                          ),
                          child: const Icon(Icons.people_outline,
                              color: LumiTokens.blue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text('Choose Students',
                            style: LumiType.subhead),
                        const Spacer(),
                        Text('${selected.length} selected',
                            style: LumiType.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: LumiTokens.rule),
                  // List
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _students.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                        color: LumiTokens.rule
                            .withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final student = _students[index];
                        final isSelected =
                            selected.contains(student.id);
                        final classNames = _classes
                            .where((c) => c.id == student.classId)
                            .map((c) => c.name)
                            .toList();
                        return InkWell(
                          onTap: () {
                            setModalState(() {
                              if (isSelected) {
                                selected.remove(student.id);
                              } else {
                                selected.add(student.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                StudentAvatar.fromStudent(student, size: 40),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(student.fullName,
                                          style: LumiType.body
                                              .copyWith(
                                                  fontWeight:
                                                      FontWeight
                                                          .w600)),
                                      Text(
                                        classNames.isNotEmpty
                                            ? classNames.first
                                            : 'Unassigned',
                                        style: LumiType.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: const Duration(
                                      milliseconds: 200),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? LumiTokens.blue
                                        : Colors.transparent,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? LumiTokens.blue
                                          : LumiTokens.rule,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          size: 16,
                                          color: LumiTokens.paper)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Footer
                  Divider(height: 1, color: LumiTokens.rule),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    Navigator.of(context).pop(),
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        LumiTokens.radiusMedium),
                                    border: Border.all(
                                        color: LumiTokens.rule),
                                  ),
                                  child: Center(
                                    child: Text('Cancel',
                                        style: LumiType.button
                                            .copyWith(
                                                color: LumiTokens.muted)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.of(context)
                                    .pop(selected),
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusMedium),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: LumiTokens.blue,
                                    borderRadius: BorderRadius.circular(
                                        LumiTokens.radiusMedium),
                                  ),
                                  child: Center(
                                    child: Text('Apply',
                                        style: LumiType.button),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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

  // ─── Submit ─────────────────────────────────────────────────────

  Future<void> _submitCampaign() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final wasScheduled = _scheduledFor != null;

    if (title.isEmpty || body.isEmpty) {
      showLumiToast(
        message: 'Add a title and message before sending.',
        type: LumiToastType.error,
      );
      return;
    }

    if (title.length > _maxTitleLength) {
      showLumiToast(
        message: 'Title must be $_maxTitleLength characters or fewer.',
        type: LumiToastType.error,
      );
      return;
    }

    if (body.length > _maxBodyLength) {
      showLumiToast(
        message: 'Message must be $_maxBodyLength characters or fewer.',
        type: LumiToastType.error,
      );
      return;
    }

    if (_audienceType == 'classes' && _selectedClassIds.isEmpty) {
      showLumiToast(
        message: 'Select at least one class.',
        type: LumiToastType.error,
      );
      return;
    }

    if (_audienceType == 'students' && _selectedStudentIds.isEmpty) {
      showLumiToast(
        message: 'Select at least one student.',
        type: LumiToastType.error,
      );
      return;
    }

    final recipientDescription = _audienceType == 'school'
        ? 'all parents in the school'
        : _audienceType == 'students'
            ? '${_selectedStudentIds.length} student${_selectedStudentIds.length == 1 ? "'s" : "s'"} parent(s)'
            : '${_selectedClassIds.length} class${_selectedClassIds.length == 1 ? '' : 'es'}';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        ),
        title: Text(
          wasScheduled ? 'Schedule Notification?' : 'Send Notification?',
          style: LumiType.subhead,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wasScheduled
                  ? 'This will schedule a notification to $recipientDescription.'
                  : 'This will send a push notification to $recipientDescription.',
              style: LumiType.body,
            ),
            if (wasScheduled) ...[
              const SizedBox(height: 12),
              Text(
                'Scheduled for: ${DateFormat('EEEE, d MMMM • h:mm a').format(_scheduledFor!)}',
                style: LumiType.body
                    .copyWith(color: LumiTokens.muted),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: LumiType.button
                    .copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(wasScheduled ? 'Schedule' : 'Send',
                style: LumiType.button
                    .copyWith(color: LumiTokens.blue)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

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
      });
      await _refreshStudents();
      if (!mounted) return;
      _tabController.animateTo(1);
      showLumiToast(
        message: wasScheduled
            ? 'Notification scheduled successfully.'
            : 'Notification queued for delivery.',
        type: LumiToastType.success,
      );
    } on StaffNotificationException catch (error) {
      if (!mounted) return;
      showLumiToast(
        message: error.message,
        type: LumiToastType.error,
      );
    } catch (error) {
      if (!mounted) return;
      showLumiToast(
        message: 'Something went wrong. Please try again.',
        type: LumiToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────

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
        return LumiTokens.blue;
      case 'partial':
        return LumiTokens.yellow;
      case 'failed':
        return LumiTokens.red;
      case 'scheduled':
        return LumiTokens.blue;
      default:
        return LumiTokens.blue;
    }
  }

  InputDecoration _inputDecoration(String hint, {bool multiline = false}) {
    return InputDecoration(
      counterText: '',
      hintText: hint,
      hintStyle: LumiType.body
          .copyWith(color: LumiTokens.muted.withValues(alpha: 0.5)),
      filled: true,
      fillColor: LumiTokens.cream,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        borderSide: BorderSide(color: LumiTokens.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        borderSide: BorderSide(color: LumiTokens.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        borderSide:
            BorderSide(color: LumiTokens.blue, width: 1.5),
      ),
      contentPadding: multiline
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  void _showTimeInputDialog(
    BuildContext parentContext,
    String label,
    int currentValue,
    int min,
    int max,
    ValueChanged<int> onConfirm,
  ) {
    final controller = TextEditingController(
        text: currentValue.toString().padLeft(2, '0'));
    controller.selection = TextSelection(
        baseOffset: 0, extentOffset: controller.text.length);

    showDialog<int>(
      context: parentContext,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
          ),
          title: Text('Enter $label', style: LumiType.subhead),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: LumiType.heading
                .copyWith(color: LumiTokens.blue),
            decoration: InputDecoration(
              hintText: '$min–$max',
              hintStyle: LumiType.body
                  .copyWith(color: LumiTokens.muted.withValues(alpha: 0.4)),
              filled: true,
              fillColor: LumiTokens.cream,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(LumiTokens.radiusMedium),
                borderSide: BorderSide(color: LumiTokens.rule),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(LumiTokens.radiusMedium),
                borderSide: BorderSide(
                    color: LumiTokens.blue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
            ),
            onSubmitted: (text) {
              final parsed = int.tryParse(text);
              Navigator.of(context).pop(
                (parsed != null && parsed >= min && parsed <= max) ? parsed : null,
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: LumiType.button
                      .copyWith(color: LumiTokens.muted)),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text);
                Navigator.of(context).pop(
                  (parsed != null && parsed >= min && parsed <= max) ? parsed : null,
                );
              },
              child: Text('Set',
                  style: LumiType.button
                      .copyWith(color: LumiTokens.blue)),
            ),
          ],
        );
      },
    ).then((result) {
      if (result != null) onConfirm(result);
    });
  }

  Widget _buildBadgeChevron(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: LumiTokens.blue,
              borderRadius:
                  BorderRadius.circular(LumiTokens.radiusPill),
            ),
            child: Text(
              '$count',
              style: LumiType.caption.copyWith(
                color: LumiTokens.paper,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: LumiTokens.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.chevron_right,
            size: 18,
            color: LumiTokens.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(bool value, ValueChanged<bool> onChanged) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: LumiTokens.green.withValues(alpha: 0.4),
      activeThumbColor: LumiTokens.green,
    );
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      // Clean paper app bar — matches Reading Groups and the rest of the app
      // (no heavy grey back-square).
      appBar: AppBar(
        backgroundColor: LumiTokens.paper,
        foregroundColor: LumiTokens.ink,
        surfaceTintColor: LumiTokens.paper,
        elevation: 0,
        title: Text('Notifications', style: LumiType.subhead),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Pill tab bar. Capped and centered on tablets so it doesn't
            // stretch to half the iPad's width per segment.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTablet(context) ? 420.0 : double.infinity,
                  ),
                  child: _buildAnimatedTabPill(),
                ),
              ),
            ),

            // Tab body
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildComposeTab(),
                        _buildHistoryTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedTabPill() {
    const labels = ['Compose', 'History'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LumiTokens.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      child: AnimatedBuilder(
        animation: _tabController.animation!,
        builder: (context, child) {
          final animValue = _tabController.animation!.value;
          return Stack(
            children: [
              // Sliding pill background
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pillWidth = constraints.maxWidth / 2;
                    return Transform.translate(
                      offset: Offset(animValue * pillWidth, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: pillWidth,
                          height: constraints.maxHeight,
                          decoration: BoxDecoration(
                            color: LumiTokens.blue,
                            borderRadius: BorderRadius.circular(
                                LumiTokens.radiusPill),
                            boxShadow: [
                              BoxShadow(
                                color: LumiTokens.blue
                                    .withValues(alpha: 0.18),
                                blurRadius: 12,
                                spreadRadius: -4,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Text labels on top
              Row(
                children: List.generate(labels.length, (index) {
                  // Interpolate color: active = white, inactive = secondary
                  final activeAmount = index == 0
                      ? 1.0 - animValue
                      : animValue;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(index),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Text(
                            labels[index],
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color.lerp(
                                LumiTokens.muted,
                                LumiTokens.paper,
                                activeAmount,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Compose Tab ────────────────────────────────────────────────

  /// In-card bento header — a soft blue icon chip + normal-case title.
  Widget _cardHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: LumiTokens.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
          ),
          child: Icon(icon, size: 17, color: LumiTokens.blue),
        ),
        const SizedBox(width: 10),
        Text(title, style: LumiType.subhead.copyWith(fontSize: 16)),
      ],
    );
  }

  Widget _buildComposeTab() {
    if (_classes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: LumiTokens.blue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.class_outlined,
                    size: 28, color: LumiTokens.blue),
              ),
              const SizedBox(height: 16),
              Text('No classes assigned',
                  style: LumiType.subhead
                      .copyWith(color: LumiTokens.muted)),
              const SizedBox(height: 8),
              Text(
                'You need at least one class assigned to send notifications to parents.',
                textAlign: TextAlign.center,
                style: LumiType.body
                    .copyWith(color: LumiTokens.muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // ── Content ──
        Container(
          decoration: _lumiCard(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardHeader(Icons.edit_note_rounded, 'Content'),
              const SizedBox(height: 12),
              Text(
                'Parents receive this as a push notification and inbox item.',
                style: LumiType.caption,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                maxLength: _maxTitleLength,
                style: LumiType.body,
                decoration: _inputDecoration('Notification title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                minLines: 4,
                maxLines: 6,
                maxLength: _maxBodyLength,
                style: LumiType.body,
                decoration: _inputDecoration(
                  'Write your message...',
                  multiline: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Audience ──
        Container(
          decoration: _lumiCard(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardHeader(Icons.groups_rounded, 'Audience'),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                      child: TeacherFilterChip(
                        activeColor: LumiTokens.blue,
                        label: 'Classes',
                        isActive: _audienceType == 'classes',
                        onTap: () {
                          setState(() {
                            _audienceType = 'classes';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TeacherFilterChip(
                        activeColor: LumiTokens.blue,
                        label: 'Students',
                        isActive: _audienceType == 'students',
                        onTap: () async {
                          setState(() {
                            _audienceType = 'students';
                          });
                          await _refreshStudents();
                        },
                      ),
                    ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_audienceType != 'school') ...[
                Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: LumiTokens.rule.withValues(alpha: 0.9),
                ),
                if (_audienceType == 'classes')
                  TeacherSettingsItem(
                    icon: Icons.class_outlined,
                    iconBgColor: LumiTokens.blue,
                    label: _selectedClassIds.isEmpty
                        ? 'Choose classes'
                        : '${_selectedClassIds.length} class${_selectedClassIds.length == 1 ? '' : 'es'} chosen',
                    trailing:
                        _buildBadgeChevron(_selectedClassIds.length),
                    onTap: _pickClasses,
                  ),
                if (_audienceType == 'students') ...[
                  TeacherSettingsItem(
                    icon: Icons.filter_alt_outlined,
                    iconBgColor: LumiTokens.blue,
                    label: _selectedClassIds.isEmpty
                        ? 'Filter by class'
                        : 'Filtering ${_selectedClassIds.length} class${_selectedClassIds.length == 1 ? '' : 'es'}',
                    trailing:
                        _buildBadgeChevron(_selectedClassIds.length),
                    onTap: _pickClasses,
                  ),
                  Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color:
                        LumiTokens.rule.withValues(alpha: 0.9),
                  ),
                  TeacherSettingsItem(
                    icon: Icons.people_outline,
                    iconBgColor: LumiTokens.blue,
                    label: _selectedStudentIds.isEmpty
                        ? 'Choose students'
                        : '${_selectedStudentIds.length} student${_selectedStudentIds.length == 1 ? '' : 's'} chosen',
                    trailing:
                        _buildBadgeChevron(_selectedStudentIds.length),
                    onTap: _pickStudents,
                  ),
                ],
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  _audienceSummary(),
                  style: LumiType.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Schedule & send ──
        Container(
          decoration: _lumiCard(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: _cardHeader(Icons.send_rounded, 'Schedule & send'),
              ),
              TeacherSettingsItem(
                icon: Icons.schedule,
                iconBgColor: LumiTokens.yellow,
                label: 'Schedule for later',
                trailing: _buildSwitch(
                  _scheduledFor != null,
                  (value) async {
                    if (!value) {
                      setState(() => _scheduledFor = null);
                      return;
                    }
                    await _pickDateTime();
                  },
                ),
              ),
              if (_scheduledFor != null) ...[
                Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 20,
                  color: LumiTokens.rule.withValues(alpha: 0.9),
                ),
                TeacherSettingsItem(
                  icon: Icons.calendar_today,
                  iconBgColor: LumiTokens.blue,
                  label: DateFormat('EEE, d MMM • h:mm a')
                      .format(_scheduledFor!),
                  onTap: _pickDateTime,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Send Button ──
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isSubmitting ? null : _submitCampaign,
            borderRadius:
                BorderRadius.circular(LumiTokens.radiusMedium),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: _isSubmitting
                    ? LumiTokens.green.withValues(alpha: 0.5)
                    : LumiTokens.green,
                borderRadius:
                    BorderRadius.circular(LumiTokens.radiusMedium),
                boxShadow: _isSubmitting
                    ? null
                    : [
                        BoxShadow(
                          color: LumiTokens.green
                              .withValues(alpha: 0.25),
                          blurRadius: 16,
                          spreadRadius: -4,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: Center(
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: LumiTokens.paper,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _scheduledFor == null
                                ? Icons.send_rounded
                                : Icons.schedule,
                            color: LumiTokens.paper,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _scheduledFor == null
                                ? 'Send Notification'
                                : 'Schedule Notification',
                            style: LumiType.button,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─── History Tab ────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    return StreamBuilder<List<NotificationCampaignModel>>(
      stream: _service.watchCampaigns(widget.user),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }

        final campaigns =
            snapshot.data ?? const <NotificationCampaignModel>[];
        if (campaigns.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: LumiTokens.blue
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        size: 28, color: LumiTokens.blue),
                  ),
                  const SizedBox(height: 16),
                  Text('No notifications sent yet',
                      style: LumiType.subhead
                          .copyWith(color: LumiTokens.muted)),
                  const SizedBox(height: 8),
                  Text(
                    'Notifications you send will appear here with delivery status.',
                    textAlign: TextAlign.center,
                    style: LumiType.body
                        .copyWith(color: LumiTokens.muted),
                  ),
                ],
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
            return _CampaignCard(
              campaign: campaign,
              subtitle: _campaignSubtitle(campaign),
              statusColor: _statusColor(campaign.status),
              classes: _classes,
            );
          },
        );
      },
    );
  }
}

// ─── Campaign Card ──────────────────────────────────────────────

class _CampaignCard extends StatefulWidget {
  const _CampaignCard({
    required this.campaign,
    required this.subtitle,
    required this.statusColor,
    required this.classes,
  });

  final NotificationCampaignModel campaign;
  final String subtitle;
  final Color statusColor;
  final List<ClassModel> classes;

  @override
  State<_CampaignCard> createState() => _CampaignCardState();
}

class _CampaignCardState extends State<_CampaignCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _lumiCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(campaign.title, style: LumiType.subhead),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    campaign.status.toUpperCase(),
                    style: LumiType.caption.copyWith(
                      color: widget.statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              campaign.body,
              style: LumiType.body
                  .copyWith(color: LumiTokens.muted),
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Text(
              widget.subtitle,
              style: LumiType.caption
                  .copyWith(color: LumiTokens.muted),
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
                  label: '${campaign.pushSentCount} sent'
                      '${campaign.pushFailedCount > 0 ? ' / ${campaign.pushFailedCount} failed' : ''}'
                      '${campaign.pushSkippedCount > 0 ? ' / ${campaign.pushSkippedCount} no token' : ''}',
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Divider(
                      height: 1, color: LumiTokens.rule),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.group_outlined,
                      'Audience: ${campaign.audienceType}'),
                  if (campaign.targetClassIds.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.class_outlined,
                        'Classes: ${_resolveClassNames(campaign.targetClassIds)}'),
                  ],
                  if (campaign.messageType.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildDetailRow(Icons.label_outline,
                        'Type: ${_formatMessageType(campaign.messageType)}'),
                  ],
                ],
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
            if ((campaign.errorSummary ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                campaign.errorSummary!,
                style: LumiType.caption
                    .copyWith(color: LumiTokens.red),
              ),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color:
                        LumiTokens.muted.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: LumiTokens.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: LumiType.caption
                .copyWith(color: LumiTokens.muted),
          ),
        ),
      ],
    );
  }

  String _resolveClassNames(List<String> classIds) {
    final names = <String>[];
    for (final id in classIds) {
      final match = widget.classes.where((c) => c.id == id);
      names.add(match.isNotEmpty ? match.first.name : id);
    }
    return names.join(', ');
  }

  String _formatMessageType(String type) {
    switch (type) {
      case 'reading_reminder':
        return 'Reading Reminder';
      case 'announcement':
        return 'Announcement';
      case 'general':
        return 'General';
      default:
        return type;
    }
  }
}

// ─── Stat Chip ──────────────────────────────────────────────────

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
        color: LumiTokens.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: LumiTokens.rule.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: LumiTokens.blue),
          const SizedBox(width: 6),
          Text(label, style: LumiType.caption),
        ],
      ),
    );
  }
}
