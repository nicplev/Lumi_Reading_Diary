import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_scanner_card.dart';
import '../../core/widgets/lumi/teacher_student_list_item.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';

/// Teacher Classroom Screen (Tab 2)
///
/// Shows the selected class with scanner card and student list.
/// Per spec: class header, ISBN scanner, sort dropdown, student list.
class TeacherClassroomScreen extends StatefulWidget {
  final UserModel teacher;
  final ClassModel? selectedClass;
  final List<ClassModel> classes;
  final ValueChanged<ClassModel>? onClassChanged;

  const TeacherClassroomScreen({
    super.key,
    required this.teacher,
    this.selectedClass,
    this.classes = const [],
    this.onClassChanged,
  });

  @override
  State<TeacherClassroomScreen> createState() => _TeacherClassroomScreenState();
}

class _TeacherClassroomScreenState extends State<TeacherClassroomScreen> {
  String _sortBy = 'name';

  List<StudentModel> _sortStudents(List<StudentModel> students) {
    final sorted = List<StudentModel>.from(students);
    switch (_sortBy) {
      case 'name':
        sorted.sort((a, b) => a.firstName.compareTo(b.firstName));
        break;
      case 'level':
        sorted.sort((a, b) =>
            (a.currentReadingLevel ?? '').compareTo(b.currentReadingLevel ?? ''));
        break;
      case 'streak':
        sorted.sort((a, b) =>
            (b.stats?.currentStreak ?? 0).compareTo(a.stats?.currentStreak ?? 0));
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final selectedClass = widget.selectedClass;

    if (selectedClass == null) {
      return const Center(
        child: Text('No class selected', style: TeacherTypography.bodyLarge),
      );
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Class selector if multiple classes
                  if (widget.classes.length > 1) ...[
                    Material(
                      color: AppColors.teacherPrimaryLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                        onTap: () => _showClassSelectorBottomSheet(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(selectedClass.name, style: TeacherTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: AppColors.teacherPrimary)),
                              const Icon(Icons.keyboard_arrow_down, color: AppColors.teacherPrimary),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(selectedClass.name, style: TeacherTypography.h1),
                  const SizedBox(height: 4),
                  Text(
                    '${selectedClass.studentIds.length} Students',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Scanner card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TeacherScannerCard(
                title: 'Scan ISBN to Assign Books',
                description: 'Quickly assign books to students by scanning the ISBN barcode',
                buttonText: 'Open Scanner',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ISBN Scanner coming soon')),
                  );
                },
              ),
            ),
          ),

          // Students header + sort
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('Students', style: TeacherTypography.h3),
                  const Spacer(),
                  Text('Sort by: ', style: TeacherTypography.bodySmall),
                  DropdownButton<String>(
                    value: _sortBy,
                    items: const [
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'level', child: Text('Level')),
                      DropdownMenuItem(value: 'streak', child: Text('Streak')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _sortBy = value);
                    },
                    underline: const SizedBox(),
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.teacherPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.teacherPrimary,
                    ),
                    isDense: true,
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Student list
          _buildStudentList(selectedClass),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildStudentList(ClassModel classModel) {
    if (classModel.studentIds.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No students in this class yet',
                style: TeacherTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add student functionality coming soon')),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Add Student', style: TeacherTypography.buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('students')
          .where(FieldPath.documentId, whereIn: classModel.studentIds.take(10).toList())
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: AppColors.teacherPrimary),
              ),
            ),
          );
        }

        final students = snapshot.data!.docs
            .map((doc) => StudentModel.fromFirestore(doc))
            .toList();
        final sorted = _sortStudents(students);

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final student = sorted[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TeacherStudentListItem(
                    name: '${student.firstName} ${student.lastName}',
                    initial: student.firstName[0].toUpperCase(),
                    avatarColor: TeacherStudentListItem.colorForName(
                        '${student.firstName} ${student.lastName}'),
                    subtitle: student.currentReadingLevel != null
                        ? 'Level ${student.currentReadingLevel}'
                        : 'No level assigned',
                    streak: student.stats?.currentStreak,
                    onTap: () {
                      context.push(
                        '/teacher/student-detail/${student.id}',
                        extra: {
                          'teacher': widget.teacher,
                          'student': student,
                        },
                      );
                    },
                  ),
                );
              },
              childCount: sorted.length,
            ),
          ),
        );
      },
    );
  }

  void _showClassSelectorBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Class', style: TeacherTypography.h3),
            const SizedBox(height: 16),
            ...widget.classes.map((c) => ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: widget.selectedClass?.id == c.id ? AppColors.teacherPrimaryLight.withValues(alpha: 0.3) : null,
                  title: Text(
                    c.name,
                    style: TeacherTypography.bodyLarge.copyWith(
                      fontWeight: widget.selectedClass?.id == c.id ? FontWeight.w700 : FontWeight.w500,
                      color: widget.selectedClass?.id == c.id ? AppColors.teacherPrimary : AppColors.charcoal,
                    ),
                  ),
                  trailing: widget.selectedClass?.id == c.id ? const Icon(Icons.check_circle, color: AppColors.teacherPrimary) : null,
                  onTap: () {
                    if (widget.onClassChanged != null) {
                      widget.onClassChanged!(c);
                    }
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }
}
