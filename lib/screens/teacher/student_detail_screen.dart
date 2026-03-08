import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_stat_card.dart';
import '../../core/widgets/lumi/teacher_book_assignment_card.dart';
import '../../core/widgets/lumi/teacher_student_list_item.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/providers/teacher_stub_data.dart';

/// Student Detail Screen
///
/// Shows student profile, stats, assigned books, and latest parent comment.
/// Per spec: avatar header, 2-col stats, assigned books list, parent comment.
class StudentDetailScreen extends StatelessWidget {
  final UserModel teacher;
  final StudentModel student;

  const StudentDetailScreen({
    super.key,
    required this.teacher,
    required this.student,
  });

  @override
  Widget build(BuildContext context) {
    final stubBooks = TeacherStubData.getStubAssignedBooks(student.id);
    final stubComment = TeacherStubData.getStubLatestComment(student.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Student Detail',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student header
            _buildStudentHeader(),
            const SizedBox(height: 20),

            // Stats cards (2-column)
            _buildStatsRow(),
            const SizedBox(height: 24),

            // Assigned Books section
            _buildAssignedBooksSection(stubBooks),
            const SizedBox(height: 24),

            // Latest Parent Comment
            _buildParentCommentSection(stubComment),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentHeader() {
    final fullName = '${student.firstName} ${student.lastName}';

    return Row(
      children: [
        CircleAvatar(
          radius: TeacherDimensions.avatarM / 2,
          backgroundColor: TeacherStudentListItem.colorForName(fullName),
          child: Text(
            student.firstName[0].toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullName, style: TeacherTypography.h2),
              const SizedBox(height: 4),
              if (student.currentReadingLevel != null)
                Text(
                  'Level ${student.currentReadingLevel}',
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: TeacherStatCard(
            icon: Icons.local_fire_department,
            iconColor: AppColors.warmOrange,
            iconBgColor: AppColors.warmOrange.withValues(alpha: 0.15),
            value: '${student.stats?.currentStreak ?? 0}',
            label: 'Day Streak',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TeacherStatCard(
            icon: Icons.nights_stay,
            iconColor: AppColors.teacherPrimary,
            iconBgColor: AppColors.teacherPrimaryLight,
            value: '${student.stats?.totalReadingDays ?? 0}',
            label: 'Total Nights',
          ),
        ),
      ],
    );
  }

  Widget _buildAssignedBooksSection(List<Map<String, dynamic>> books) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Assigned Books', style: TeacherTypography.h3),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                // Stub: assign book flow
              },
              icon: Icon(Icons.add, size: 18, color: AppColors.teacherPrimary),
              label: Text(
                'Assign',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...books.map((book) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TeacherBookAssignmentCard(
              title: book['title'] as String,
              subtitle: book['subtitle'] as String,
              coverGradient: (book['coverGradient'] as List<Color>),
              bookType: book['type'] as String,
              status: book['status'] as String,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildParentCommentSection(Map<String, dynamic> comment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Latest Parent Comment', style: TeacherTypography.h3),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
            border: Border(
              left: BorderSide(
                color: AppColors.teacherPrimary,
                width: 4,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${comment['comment']}"',
                style: TeacherTypography.bodyMedium.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '— ${comment['author']} \u2022 ${comment['date']}',
                style: TeacherTypography.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
