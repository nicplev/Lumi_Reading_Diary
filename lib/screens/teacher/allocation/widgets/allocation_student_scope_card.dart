import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../../core/widgets/lumi/lumi_input.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/reading_group_model.dart';
import 'allocation_form_common.dart';

/// "Students" card: choose the allocation scope (Whole Class / Select Students /
/// By Group) and pick the individual students or groups.
class AllocationStudentScopeCard extends StatelessWidget {
  const AllocationStudentScopeCard({
    super.key,
    required this.students,
    required this.readingGroups,
    required this.selectAllStudents,
    required this.selectByGroup,
    required this.selectedStudentIds,
    required this.selectedGroupIds,
    required this.studentSearchQuery,
    required this.studentError,
    required this.levelsEnabled,
    required this.formatLevelLabel,
    required this.onScopeChanged,
    required this.onGroupToggled,
    required this.onStudentToggled,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onSearchChanged,
  });

  final List<StudentModel> students;
  final List<ReadingGroupModel> readingGroups;
  final bool selectAllStudents;
  final bool selectByGroup;
  final List<String> selectedStudentIds;
  final List<String> selectedGroupIds;
  final String studentSearchQuery;
  final String? studentError;
  final bool levelsEnabled;
  final String Function(String?) formatLevelLabel;
  final void Function(bool allStudents, bool byGroup) onScopeChanged;
  final void Function(String groupId, bool selected) onGroupToggled;
  final ValueChanged<String> onStudentToggled;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final ValueChanged<String> onSearchChanged;

  bool get _isWholeClass => selectAllStudents && !selectByGroup;
  bool get _isSelectStudents => !selectAllStudents && !selectByGroup;

  @override
  Widget build(BuildContext context) {
    final filteredStudents = studentSearchQuery.isEmpty
        ? students
        : students
            .where((s) => s.fullName
                .toLowerCase()
                .contains(studentSearchQuery.toLowerCase()))
            .toList();

    return AllocationFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AllocationSectionHeader(step: 3, title: 'Students'),
          const SizedBox(height: 16),

          // Scope chooser — descriptive option rows
          AllocationOptionList(
            cards: [
              AllocationOptionCard(
                icon: Icons.groups_rounded,
                iconColor: LumiTokens.blue,
                title: 'Whole class',
                description: 'All ${students.length} '
                    '${students.length == 1 ? 'student' : 'students'}.',
                isSelected: _isWholeClass,
                onTap: () => onScopeChanged(true, false),
                trailing: students.isEmpty ? null : _AvatarStrip(students),
              ),
              AllocationOptionCard(
                icon: Icons.person_outline_rounded,
                iconColor: LumiTokens.muted,
                title: 'Select students',
                description: 'Pick individual students.',
                isSelected: _isSelectStudents,
                onTap: () => onScopeChanged(false, false),
              ),
              if (readingGroups.isNotEmpty)
                AllocationOptionCard(
                  icon: Icons.workspaces_rounded,
                  iconColor: LumiTokens.yellow,
                  title: 'By group',
                  description: '${readingGroups.length} reading '
                      '${readingGroups.length == 1 ? 'group' : 'groups'}.',
                  isSelected: selectByGroup,
                  onTap: () => onScopeChanged(false, true),
                ),
            ],
          ),

          if (studentError != null && !selectAllStudents) ...[
            const SizedBox(height: 8),
            Text(
              studentError!,
              style: LumiType.caption.copyWith(color: LumiTokens.red),
            ),
          ],

          // Group selection UI
          if (selectByGroup) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: readingGroups.isEmpty
                  ? Text(
                      'No groups found. Create groups in Settings > Reading Groups.',
                      style: LumiType.caption,
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: readingGroups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final group = readingGroups[index];
                        final isSelected =
                            selectedGroupIds.contains(group.id);
                        final groupColor = group.color != null
                            ? Color(int.parse(
                                group.color!.replaceFirst('#', '0xFF')))
                            : LumiTokens.green;
                        return _SelectableRow(
                          isSelected: isSelected,
                          onTap: () =>
                              onGroupToggled(group.id, !isSelected),
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: groupColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: group.name,
                          subtitle: '${group.studentIds.length} students',
                        );
                      },
                    ),
            ),
            if (selectedGroupIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${selectedStudentIds.length} students selected from ${selectedGroupIds.length} group${selectedGroupIds.length == 1 ? '' : 's'}',
                style: LumiType.caption.copyWith(color: LumiTokens.green),
              ),
            ],
          ],

          // Individual student selection UI
          if (_isSelectStudents) ...[
            const SizedBox(height: 12),
            LumiSearchInput(
              hintText: 'Search students...',
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                LumiTextButton(
                  onPressed: onSelectAll,
                  text: 'Select All',
                  color: LumiTokens.green,
                ),
                const SizedBox(width: 4),
                LumiTextButton(
                  onPressed: onDeselectAll,
                  text: 'Deselect All',
                  color: LumiTokens.muted,
                ),
                const Spacer(),
                Text(
                  '${selectedStudentIds.length} selected',
                  style: LumiType.caption,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filteredStudents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final student = filteredStudents[index];
                  final isSelected =
                      selectedStudentIds.contains(student.id);
                  return _SelectableRow(
                    isSelected: isSelected,
                    onTap: () => onStudentToggled(student.id),
                    leading: _InitialsAvatar(
                      initials: _initials(student.fullName),
                      isSelected: isSelected,
                    ),
                    title: student.fullName,
                    subtitle: levelsEnabled &&
                            student.currentReadingLevel != null
                        ? 'Level: ${formatLevelLabel(student.currentReadingLevel)}'
                        : null,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
}

/// An overlapping strip of mini initials avatars plus a friendly names line —
/// shown under "Whole class" so the teacher can see who they're assigning to.
class _AvatarStrip extends StatelessWidget {
  const _AvatarStrip(this.students);

  final List<StudentModel> students;

  static const int _maxAvatars = 6;

  String get _namesLine {
    final names = students.map((s) => s.firstName).toList();
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    if (names.length == 3) return '${names[0]}, ${names[1]} & ${names[2]}';
    return '${names[0]}, ${names[1]} +${names.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = students.take(_maxAvatars).toList();
    final overflow = students.length - shown.length;

    return Row(
      children: [
        SizedBox(
          width: shown.length * 20.0 + 8,
          height: 28,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 20.0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: LumiTokens.paper,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: _InitialsAvatar(
                      initials: _initials(shown[i].fullName),
                      isSelected: false,
                      size: 25,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('+$overflow', style: LumiType.caption),
          ),
        Expanded(
          child: Text(
            _namesLine,
            style: LumiType.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A tappable list row with a leading widget, title/subtitle and a check icon.
class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.isSelected,
    required this.onTap,
    required this.leading,
    required this.title,
    this.subtitle,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? LumiTokens.green.withValues(alpha: 0.08)
              : LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          border: Border.all(
            color: isSelected
                ? LumiTokens.green.withValues(alpha: 0.4)
                : LumiTokens.rule,
          ),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LumiType.body.copyWith(
                      color: LumiTokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: LumiType.caption),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? LumiTokens.green : LumiTokens.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.initials,
    required this.isSelected,
    this.size = 32,
  });

  final String initials;
  final bool isSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected
            ? LumiTokens.green
            : LumiTokens.green.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: LumiType.caption.copyWith(
            color: isSelected ? LumiTokens.paper : LumiTokens.green,
            fontWeight: FontWeight.w700,
            fontSize: size < 28 ? 10 : 11,
          ),
        ),
      ),
    );
  }
}
