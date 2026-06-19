import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../theme/section_theme.dart';
import '../../../core/theme/lumi_spacing.dart';
import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../data/models/student_model.dart';
import '../../../data/providers/active_child_provider.dart';

/// A persistent, horizontally-scrolling row of the parent's children.
///
/// Tapping a child makes it the app-wide active child (see
/// [activeChildProvider]) — every screen watching that provider re-scopes to
/// the new child. Renders nothing when the parent has zero or one child (there
/// is nothing to switch between), so it is safe to drop into the header of
/// every parent tab unconditionally.
class ParentChildSwitcher extends ConsumerWidget {
  /// Padding around the switcher row.
  final EdgeInsetsGeometry padding;

  const ParentChildSwitcher({
    super.key,
    this.padding = const EdgeInsets.symmetric(
      horizontal: LumiSpacing.s,
      vertical: LumiSpacing.xs,
    ),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(parentChildrenProvider).value ?? const [];
    if (children.length < 2) return const SizedBox.shrink();

    // Highlight the resolved active child so the row stays consistent even
    // when the stored id is stale (activeChildProvider falls back to first).
    final activeId = ref.watch(activeChildProvider).value?.id;

    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: LumiSpacing.xs),
              _ChildPill(
                student: children[i],
                isActive: children[i].id == activeId,
                onTap: () => ref
                    .read(activeChildIdProvider.notifier)
                    .select(children[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChildPill extends StatelessWidget {
  final StudentModel student;
  final bool isActive;
  final VoidCallback onTap;

  const _ChildPill({
    required this.student,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.sectionTheme.accent;
    return Semantics(
      button: true,
      selected: isActive,
      label: 'View ${student.firstName}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.12)
                : LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            border: Border.all(
              color: isActive
                  ? accent
                  : LumiTokens.ink.withValues(alpha: 0.12),
              width: isActive ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudentAvatar.fromStudent(student, size: 30),
              const SizedBox(width: 8),
              Text(
                student.firstName,
                style: LumiType.body.copyWith(
                  color: isActive ? accent : LumiTokens.muted,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
