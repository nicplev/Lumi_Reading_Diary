import 'package:flutter/material.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/allocation_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_log_service.dart';

/// Modal sheet a teacher uses to log a reading session on behalf of a student
/// whose carer cannot use the app (rural / remote families). The log is
/// attributed to the teacher and tagged as a proxy log via `loggedByRole`
/// so it doesn't conflate with parent engagement metrics.
class TeacherLogReadingSheet extends StatefulWidget {
  const TeacherLogReadingSheet({
    super.key,
    required this.teacher,
    required this.student,
  });

  final UserModel teacher;
  final StudentModel student;

  static Future<bool?> show({
    required BuildContext context,
    required UserModel teacher,
    required StudentModel student,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LumiTokens.paper,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusLarge)),
      ),
      builder: (ctx) => TeacherLogReadingSheet(teacher: teacher, student: student),
    );
  }

  @override
  State<TeacherLogReadingSheet> createState() => _TeacherLogReadingSheetState();
}

class _TeacherLogReadingSheetState extends State<TeacherLogReadingSheet> {
  static const int _maxBackdateDays = 7;

  final _firebaseService = FirebaseService.instance;
  final _customTitleController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _date = _dateOnly(DateTime.now());
  int _minutes = 15;
  final Set<String> _selectedAssignedTitles = {};
  final List<String> _customTitles = [];

  String? _selectedAllocationId;
  int? _selectedAllocationTargetMinutes;

  bool _isLoadingAllocations = true;
  bool _isSaving = false;
  List<_AssignedBook> _assignedBooks = const [];

  @override
  void initState() {
    super.initState();
    _loadAllocations();
  }

  @override
  void dispose() {
    _customTitleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadAllocations() async {
    try {
      final snapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.student.schoolId)
          .collection('allocations')
          .where('classId', isEqualTo: widget.student.classId)
          .where('isActive', isEqualTo: true)
          .get();

      final now = DateTime.now();
      final books = <_AssignedBook>[];
      for (final doc in snapshot.docs) {
        final allocation = AllocationModel.fromFirestore(doc);
        final withinWindow = !allocation.startDate.isAfter(now) &&
            !allocation.endDate.isBefore(now);
        final appliesToStudent = allocation.isForWholeClass ||
            allocation.studentIds.contains(widget.student.id);
        if (!withinWindow || !appliesToStudent) continue;

        final items =
            allocation.effectiveAssignmentItemsForStudent(widget.student.id);
        for (final item in items) {
          final title = item.title.trim();
          if (title.isEmpty) continue;
          books.add(_AssignedBook(
            title: title,
            allocationId: allocation.id,
            targetMinutes: allocation.targetMinutes,
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _assignedBooks = books;
        _isLoadingAllocations = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAllocations = false);
    }
  }

  Future<void> _pickDate() async {
    final now = _dateOnly(DateTime.now());
    final firstDate = now.subtract(const Duration(days: _maxBackdateDays));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: firstDate,
      lastDate: now,
      helpText: 'Reading date',
    );
    if (picked != null && mounted) {
      setState(() => _date = _dateOnly(picked));
    }
  }

  void _toggleAssignedTitle(_AssignedBook book, bool selected) {
    setState(() {
      if (selected) {
        _selectedAssignedTitles.add(book.title);
        _selectedAllocationId ??= book.allocationId;
        _selectedAllocationTargetMinutes ??= book.targetMinutes;
      } else {
        _selectedAssignedTitles.remove(book.title);
        if (_selectedAssignedTitles.isEmpty) {
          _selectedAllocationId = null;
          _selectedAllocationTargetMinutes = null;
        }
      }
    });
  }

  void _addCustomTitle() {
    final value = _customTitleController.text.trim();
    if (value.isEmpty || _customTitles.contains(value)) return;
    setState(() {
      _customTitles.add(value);
      _customTitleController.clear();
    });
  }

  bool get _canSave =>
      !_isSaving &&
      _minutes > 0 &&
      (_selectedAssignedTitles.isNotEmpty || _customTitles.isNotEmpty);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);

    final titles = [
      ..._selectedAssignedTitles,
      ..._customTitles,
    ];

    try {
      await ReadingLogService.instance.logReadingAsTeacher(
        teacher: widget.teacher,
        student: widget.student,
        date: _date,
        minutesRead: _minutes,
        bookTitles: titles,
        notes: _notesController.text,
        allocationId: _selectedAllocationId,
        targetMinutes: _selectedAllocationTargetMinutes ?? 20,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      showLumiToast(
        message: 'Reading logged for ${widget.student.firstName}',
        type: LumiToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showLumiToast(
        message: 'Couldn\'t log reading: $e',
        type: LumiToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDateRow(),
                      const SizedBox(height: 16),
                      _buildBookPicker(),
                      const SizedBox(height: 16),
                      _buildMinutesSelector(),
                      const SizedBox(height: 16),
                      _buildNotesField(),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: LumiTokens.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildDateRow() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: LumiTokens.cream,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          border: Border.all(color: LumiTokens.rule),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: LumiTokens.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reading date',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.muted,
                      )),
                  Text(_relativeDateLabel(_date),
                      style: LumiType.bodyL),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: LumiTokens.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildBookPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What did they read?', style: LumiType.subhead),
        const SizedBox(height: 8),
        if (_isLoadingAllocations)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_assignedBooks.isNotEmpty) ...[
          ..._assignedBooks.map((book) => CheckboxListTile(
                value: _selectedAssignedTitles.contains(book.title),
                onChanged: (v) => _toggleAssignedTitle(book, v == true),
                title: Text(book.title, style: LumiType.body),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                activeColor: LumiTokens.green,
              )),
        ],
        const SizedBox(height: 8),
        Text(
          _assignedBooks.isEmpty ? 'Add a book' : 'Or add another title',
          style: LumiType.caption.copyWith(
            color: LumiTokens.muted,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customTitleController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCustomTitle(),
                decoration: const InputDecoration(
                  hintText: 'Book title',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _addCustomTitle,
              icon: const Icon(Icons.add_circle),
              color: LumiTokens.green,
            ),
          ],
        ),
        if (_customTitles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _customTitles
                  .map((t) => Chip(
                        label: Text(t),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () =>
                            setState(() => _customTitles.remove(t)),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildMinutesSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Minutes read', style: LumiType.subhead),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _minutes > 5
                  ? () => setState(() => _minutes -= 5)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: LumiTokens.green,
              iconSize: 28,
            ),
            SizedBox(
              width: 120,
              child: Center(
                child: Text(
                  '$_minutes min',
                  style: LumiType.heading.copyWith(color: LumiTokens.ink),
                  maxLines: 1,
                ),
              ),
            ),
            IconButton(
              onPressed: _minutes < 120
                  ? () => setState(() => _minutes += 5)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              color: LumiTokens.green,
              iconSize: 28,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [10, 15, 20, 25, 30].map((m) {
              final selected = _minutes == m;
              return ChoiceChip(
                label: Text('$m'),
                selected: selected,
                onSelected: (v) {
                  if (v) setState(() => _minutes = m);
                },
                selectedColor: LumiTokens.green,
                labelStyle: TextStyle(
                  color: selected ? LumiTokens.paper : LumiTokens.ink,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Note (optional)', style: LumiType.subhead),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 3,
          maxLength: 280,
          decoration: const InputDecoration(
            hintText: "e.g. 'Mum reported 15 min reading at home'",
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        border: Border(
          top: BorderSide(color: LumiTokens.rule.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: LumiTokens.muted,
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(LumiTokens.radiusMedium),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: LumiTokens.paper,
                      ),
                    )
                  : const Text('Save log'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedBook {
  const _AssignedBook({
    required this.title,
    required this.allocationId,
    required this.targetMinutes,
  });

  final String title;
  final String allocationId;
  final int targetMinutes;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _relativeDateLabel(DateTime date) {
  final today = _dateOnly(DateTime.now());
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
}
