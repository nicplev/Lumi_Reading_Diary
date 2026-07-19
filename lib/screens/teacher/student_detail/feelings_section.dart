import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/feelings/feelings_tracker_card.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../theme/lumi_tokens.dart';

/// Feelings tracker on the teacher student-detail screen. Watches the shared
/// feelings-log stream provider so the Firestore subscription survives parent
/// rebuilds untouched.
class FeelingsSection extends ConsumerWidget {
  final StudentDetailLookup lookup;

  const FeelingsSection({super.key, required this.lookup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(studentFeelingLogsProvider(lookup));
    // While loading (or on error), render an empty tracker rather than a
    // spinner so the section never janks the scroll position.
    final docs = snapshot.value?.docs ?? const [];
    final logs = docs
        .map((d) => ReadingLogModel.fromFirestore(d))
        .toList(growable: false);
    return FeelingsTrackerCard(logs: logs, accentColor: LumiTokens.ink);
  }
}
