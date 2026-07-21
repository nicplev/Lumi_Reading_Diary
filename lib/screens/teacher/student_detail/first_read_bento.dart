import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/allocation_model.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'student_assignment_presence.dart';

/// Replaces the normal detail sections only for a student who has genuinely
/// not started a reading journey. It deliberately keeps the normal content
/// visible while either source is loading or errors, so the bento cannot flash
/// before Firestore confirms the empty state.
class StudentDetailFirstReadGate extends ConsumerWidget {
  final StudentDetailLookup lookup;
  final String studentName;
  final VoidCallback onAssignBooks;
  final VoidCallback onScanIsbn;
  final VoidCallback onLogReading;
  final Widget child;

  const StudentDetailFirstReadGate({
    super.key,
    required this.lookup,
    required this.studentName,
    required this.onAssignBooks,
    required this.onScanIsbn,
    required this.onLogReading,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allocationsAsync = ref.watch(studentAllocationsProvider(lookup));
    final recentLogsAsync = ref.watch(studentRecentLogsProvider(lookup));

    // An error belongs to the section that owns it; rendering [child] lets its
    // existing, retryable error UI remain visible rather than recasting it as
    // an empty-state invitation.
    if (!allocationsAsync.hasValue || !recentLogsAsync.hasValue) {
      return child;
    }

    final allocations = allocationsAsync.value!.docs
        .map(AllocationModel.fromFirestore)
        .toList(growable: false);
    final hasAssignedBook =
        hasCurrentStudentBookAssignment(allocations, lookup.studentId);
    final hasReadingHistory = recentLogsAsync.value!.docs.isNotEmpty;

    if (hasAssignedBook || hasReadingHistory) return child;

    return StudentDetailFirstReadBento(
      studentName: studentName,
      onAssignBooks: onAssignBooks,
      onScanIsbn: onScanIsbn,
      onLogReading: onLogReading,
    );
  }
}

/// Calm, task-led first-read empty state for the teacher student-detail page.
/// It is intentionally a collection of flat, bordered compartments so it
/// belongs with Lumi's newer bento surfaces rather than older empty cards.
class StudentDetailFirstReadBento extends StatelessWidget {
  final String studentName;
  final VoidCallback onAssignBooks;
  final VoidCallback onScanIsbn;
  final VoidCallback onLogReading;

  const StudentDetailFirstReadBento({
    super.key,
    required this.studentName,
    required this.onAssignBooks,
    required this.onScanIsbn,
    required this.onLogReading,
  });

  @override
  Widget build(BuildContext context) {
    final displayName =
        studentName.trim().isEmpty ? 'this student' : studentName;
    final possessiveName = _possessive(displayName);

    return Semantics(
      container: true,
      label: "Set up $displayName's first read",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroTile(possessiveName: possessiveName),
          const SizedBox(height: 12),
          StudentDetailBentoActionTile(
            icon: Icons.menu_book_rounded,
            title: 'Assign a book',
            description: 'Choose from class, library or take-home books.',
            onTap: onAssignBooks,
            primary: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StudentDetailBentoActionTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Scan a book',
                  description: 'Use an ISBN.',
                  onTap: onScanIsbn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StudentDetailBentoActionTile(
                  icon: Icons.edit_note_rounded,
                  title: 'Log a read',
                  description: 'Start without a book.',
                  onTap: onLogReading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _JourneyTile(),
        ],
      ),
    );
  }

  String _possessive(String name) {
    return name.toLowerCase().endsWith('s') ? '$name\u2019' : '$name\u2019s';
  }
}

class _HeroTile extends StatelessWidget {
  final String possessiveName;

  const _HeroTile({required this.possessiveName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _bentoDecoration(color: LumiTokens.paper),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: LumiTokens.tintBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: LumiTokens.ink,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FIRST READ',
                  style: LumiType.sectionLabel.copyWith(
                    color: LumiTokens.blue,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ready for $possessiveName first read?',
                  style: LumiType.subhead.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a starting point and Lumi will help track the journey.',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable action compartment shared by the first-read and next-read states.
class StudentDetailBentoActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool primary;

  const StudentDetailBentoActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? LumiTokens.paper : LumiTokens.ink;
    final secondary =
        primary ? LumiTokens.paper.withValues(alpha: 0.84) : LumiTokens.muted;

    return Semantics(
      button: true,
      label: '$title. $description',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          child: Ink(
            decoration: _bentoDecoration(
              color: primary ? LumiTokens.green : LumiTokens.paper,
              borderColor: primary ? LumiTokens.green : LumiTokens.rule,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 88),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: primary
                            ? LumiTokens.paper.withValues(alpha: 0.18)
                            : LumiTokens.cream,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                      ),
                      child: Icon(icon, size: 19, color: foreground),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: LumiType.body.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: LumiType.caption.copyWith(
                              color: secondary,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: foreground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Next-step bento for students who have a reading history but no current
/// allocation. It deliberately keeps the history below visible; this is an
/// invitation to continue their journey, not a reset to onboarding.
class StudentDetailNextReadBento extends StatelessWidget {
  final VoidCallback onAssignBooks;
  final VoidCallback onScanIsbn;
  final VoidCallback onLogReading;

  const StudentDetailNextReadBento({
    super.key,
    required this.onAssignBooks,
    required this.onScanIsbn,
    required this.onLogReading,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Choose the next read',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _bentoDecoration(color: LumiTokens.paper),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: LumiTokens.tintYellow,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 21,
                    color: LumiTokens.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT READ',
                        style: LumiType.sectionLabel.copyWith(
                          color: LumiTokens.orange,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Choose the next read',
                        style: LumiType.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Keep the reading journey moving.',
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          StudentDetailBentoActionTile(
            icon: Icons.menu_book_rounded,
            title: 'Assign a book',
            description: 'Choose from class, library or take-home books.',
            onTap: onAssignBooks,
            primary: true,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StudentDetailBentoActionTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Scan a book',
                  description: 'Use an ISBN.',
                  onTap: onScanIsbn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StudentDetailBentoActionTile(
                  icon: Icons.edit_note_rounded,
                  title: 'Log a read',
                  description: 'Start without a book.',
                  onTap: onLogReading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JourneyTile extends StatelessWidget {
  const _JourneyTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _bentoDecoration(color: LumiTokens.cream),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHAT GROWS NEXT',
              style: LumiType.sectionLabel.copyWith(fontSize: 11)),
          const SizedBox(height: 5),
          Text(
            'After the first read, Lumi can follow more than minutes.',
            style: LumiType.caption.copyWith(color: LumiTokens.muted),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _JourneyHint(
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  label: 'Feelings'),
              _JourneyHint(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Home comments'),
              _JourneyHint(
                  icon: Icons.emoji_events_outlined, label: 'Achievements'),
            ],
          ),
        ],
      ),
    );
  }
}

class _JourneyHint extends StatelessWidget {
  final IconData icon;
  final String label;

  const _JourneyHint({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: LumiTokens.muted),
          const SizedBox(width: 5),
          Text(label,
              style: LumiType.caption.copyWith(color: LumiTokens.muted)),
        ],
      ),
    );
  }
}

BoxDecoration _bentoDecoration({
  required Color color,
  Color borderColor = LumiTokens.rule,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
    border: Border.all(color: borderColor),
  );
}
