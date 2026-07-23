import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../services/class_daily_reading_service.dart';
import 'dashboard_student_nav.dart';

/// Bottom sheet breaking a single calendar day into who read and who didn't.
/// All data comes from the [summary] already streamed by the calendar card plus
/// the current [roster] — no extra Firestore reads.
void showCalendarDayDetailSheet(
  BuildContext context, {
  required DateTime day,
  required ClassDailyReadingSummary? summary,
  required List<StudentModel> roster,
  required UserModel teacher,
  required ClassModel classModel,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CalendarDayDetailSheet(
      day: day,
      summary: summary,
      roster: roster,
      teacher: teacher,
      classModel: classModel,
    ),
  );
}

class _CalendarDayDetailSheet extends StatelessWidget {
  final DateTime day;
  final ClassDailyReadingSummary? summary;
  final List<StudentModel> roster;
  final UserModel teacher;
  final ClassModel classModel;

  const _CalendarDayDetailSheet({
    required this.day,
    required this.summary,
    required this.roster,
    required this.teacher,
    required this.classModel,
  });

  bool get _isWeekend =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in roster) s.id: s};
    final readerIds = summary?.students.keys.toSet() ?? <String>{};

    // Readers, sorted by minutes desc. A reader id not in the current roster is
    // a student who has since left the class — shown, but flagged, so the
    // "n read" count and the list length always agree.
    final readers = readerIds.toList()
      ..sort((a, b) {
        final ma = summary?.students[a]?.minutes ?? 0;
        final mb = summary?.students[b]?.minutes ?? 0;
        return mb.compareTo(ma);
      });

    // Non-readers are drawn only from the CURRENT roster (a departed student
    // can't meaningfully be "still to read").
    final nonReaders = roster.where((s) => !readerIds.contains(s.id)).toList()
      ..sort((a, b) => a.firstName.compareTo(b.firstName));

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(LumiTokens.radiusXL),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('EEEE, d MMMM').format(day),
                              style: LumiType.subhead),
                          const SizedBox(height: 2),
                          Text(
                            '${readers.length} read · ${nonReaders.length} still to read',
                            style: LumiType.caption
                                .copyWith(color: LumiTokens.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isWeekend)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Weekend reading is optional at most schools.',
                    style: LumiType.caption
                        .copyWith(color: LumiTokens.muted, fontSize: 11),
                  ),
                ),
              const Divider(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (readers.isNotEmpty) ...[
                      _sectionHeader('Read (${readers.length})'),
                      for (final id in readers)
                        _readerRow(context, id, byId[id]),
                      const SizedBox(height: 12),
                    ],
                    _sectionHeader('Didn\'t read (${nonReaders.length})'),
                    if (nonReaders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Everyone read — nice.',
                            style: LumiType.caption
                                .copyWith(color: LumiTokens.muted)),
                      ),
                    for (final s in nonReaders) _nonReaderRow(context, s),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4, left: 4),
        child: Text(
          text,
          style: LumiType.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: LumiTokens.muted,
          ),
        ),
      );

  Widget _readerRow(BuildContext context, String id, StudentModel? student) {
    final metrics = summary?.students[id];
    final minutes = metrics?.minutes ?? 0;
    final teacherLogged = (metrics?.teacherLogs ?? 0) > 0;
    final name = student?.firstNameWithLastInitial ??
        'Former student'; // departed from the roster

    return InkWell(
      onTap: student == null
          ? null
          : () {
              Navigator.of(context).pop();
              pushStudentDetail(context,
                  teacher: teacher, student: student, classModel: classModel);
            },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            student != null
                ? StudentAvatar.fromStudent(student, size: 32)
                : StudentAvatar(
                    characterId: null,
                    initial: '–',
                    avatarColor: LumiTokens.tintBlue,
                    size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                  style: LumiType.body.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            if (teacherLogged) ...[
              Icon(Icons.school_outlined,
                  size: 14, color: LumiTokens.muted),
              const SizedBox(width: 4),
            ],
            Text('$minutes min',
                style: LumiType.caption.copyWith(
                    fontWeight: FontWeight.w700, color: LumiTokens.ink)),
            if (student != null) ...[
              const SizedBox(width: 6),
              const DashboardRowChevron(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nonReaderRow(BuildContext context, StudentModel student) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        pushStudentDetail(context,
            teacher: teacher, student: student, classModel: classModel);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            StudentAvatar.fromStudent(student, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(student.firstNameWithLastInitial,
                  style: LumiType.body.copyWith(fontSize: 14)),
            ),
            const DashboardRowChevron(),
          ],
        ),
      ),
    );
  }
}
