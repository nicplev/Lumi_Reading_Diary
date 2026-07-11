import 'package:flutter/material.dart';

import '../../../data/models/student_model.dart';
import '../../../services/reading_level_service.dart';

/// Displays a student's reading level formatted through their school's level
/// schema ("PM 12", "Level J", a named colour, ...) instead of interpolating
/// the raw stored value, which only reads correctly for A-Z schools.
///
/// Shows the raw value immediately and swaps in the schema label once the
/// school's level options resolve (cached per school after the first load).
class StudentReadingLevelLabel extends StatefulWidget {
  const StudentReadingLevelLabel({
    super.key,
    required this.student,
    this.prefix = 'Level: ',
    this.unsetLabel = 'Not set',
    this.style,
    this.maxLines,
    this.overflow,
  });

  final StudentModel student;
  final String prefix;
  final String unsetLabel;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<StudentReadingLevelLabel> createState() =>
      _StudentReadingLevelLabelState();
}

class _StudentReadingLevelLabelState extends State<StudentReadingLevelLabel> {
  // Shared across all instances so sibling rows reuse the per-school cache
  // instead of each re-reading the school document.
  static final ReadingLevelService _service = ReadingLevelService();

  String? _label;

  @override
  void initState() {
    super.initState();
    _label = widget.student.currentReadingLevel?.trim();
    _load();
  }

  @override
  void didUpdateWidget(StudentReadingLevelLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.student.currentReadingLevel !=
            widget.student.currentReadingLevel ||
        oldWidget.student.schoolId != widget.student.schoolId) {
      _label = widget.student.currentReadingLevel?.trim();
      _load();
    }
  }

  Future<void> _load() async {
    // Compact label ("J", "PM 12") — the display label would double up the
    // "Level" prefix ("Level: Level J").
    final formatted = await _service.formatStoredLevelForSchool(
      widget.student.schoolId,
      widget.student.currentReadingLevel,
      compact: true,
    );
    if (!mounted) return;
    setState(() => _label = formatted);
  }

  @override
  Widget build(BuildContext context) {
    final label = (_label == null || _label!.isEmpty)
        ? widget.unsetLabel
        : _label!;
    return Text(
      '${widget.prefix}$label',
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
