import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/feelings/feelings_tracker_card.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../theme/lumi_tokens.dart';

/// Feelings tracker on the teacher student-detail screen.
///
/// Prefers the server-maintained `feelingsByDay` aggregate on the student doc
/// (one doc read, C7) and synthesizes the tracker's log input from it. Falls
/// back to the former 400-log live query while the aggregate hasn't been
/// backfilled for this student. Remove the fallback one release after the
/// backfill has run in production.
class FeelingsSection extends ConsumerWidget {
  final StudentDetailLookup lookup;

  const FeelingsSection({super.key, required this.lookup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(studentDocProvider(lookup)).value;
    final aggregate = student?.feelingsByDay;
    if (aggregate != null) {
      return FeelingsTrackerCard(
        logs: _logsFromAggregate(aggregate),
        accentColor: LumiTokens.ink,
      );
    }

    final snapshot = ref.watch(studentFeelingLogsProvider(lookup));
    // While loading (or on error), render an empty tracker rather than a
    // spinner so the section never janks the scroll position.
    final docs = snapshot.value?.docs ?? const [];
    final logs = docs
        .map((d) => ReadingLogModel.fromFirestore(d))
        .toList(growable: false);
    return FeelingsTrackerCard(logs: logs, accentColor: LumiTokens.ink);
  }

  /// Expands the per-day feeling counts into stub logs. The tracker's
  /// aggregator reads only `date` and `childFeeling`, so N stubs per
  /// (day, feeling) reproduce its per-day averages exactly.
  List<ReadingLogModel> _logsFromAggregate(
    Map<String, Map<String, int>> byDay,
  ) {
    final logs = <ReadingLogModel>[];
    byDay.forEach((dayKey, bucket) {
      final date = DateTime.tryParse(dayKey);
      if (date == null) return;
      bucket.forEach((feelingName, count) {
        final feeling = ReadingFeeling.values
            .where((f) => f.name == feelingName)
            .firstOrNull;
        if (feeling == null) return;
        for (var i = 0; i < count; i++) {
          logs.add(ReadingLogModel(
            id: 'agg_${dayKey}_${feelingName}_$i',
            studentId: lookup.studentId,
            parentId: '',
            schoolId: lookup.schoolId,
            classId: lookup.classId,
            date: date,
            minutesRead: 0,
            targetMinutes: 0,
            status: LogStatus.completed,
            bookTitles: const [],
            createdAt: date,
            childFeeling: feeling,
          ));
        }
      });
    });
    return logs;
  }
}
