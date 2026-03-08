import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_profile_card.dart';
import '../../core/widgets/lumi/teacher_settings_section.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../services/firebase_service.dart';
import '../../core/widgets/lumi/feedback_widget.dart';

class TeacherProfileScreen extends StatefulWidget {
  final UserModel user;

  const TeacherProfileScreen({
    super.key,
    required this.user,
  });

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  List<ClassModel> _classes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final List<ClassModel> classes = [];

      // Load classes where user is teacher - using nested structure
      final classQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .where('teacherId', isEqualTo: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in classQuery.docs) {
        classes.add(ClassModel.fromFirestore(doc));
      }

      // Also load classes where user is assistant teacher
      final assistantQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .where('assistantTeacherId', isEqualTo: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in assistantQuery.docs) {
        final classModel = ClassModel.fromFirestore(doc);
        if (!classes.any((c) => c.id == classModel.id)) {
          classes.add(classModel);
        }
      }

      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading classes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  int get _totalStudents {
    int total = 0;
    for (final c in _classes) {
      total += c.studentIds.length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Profile card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TeacherProfileCard(
                initials: widget.user.fullName.isNotEmpty
                    ? widget.user.fullName[0].toUpperCase()
                    : '?',
                fullName: widget.user.fullName,
                subtitle: 'Teacher',
                stats: _isLoading
                    ? []
                    : [
                        ProfileStat(
                            value: '${_classes.length}', label: 'Classes'),
                        ProfileStat(
                            value: '$_totalStudents', label: 'Students'),
                        ProfileStat(value: '0', label: 'Reports'),
                      ],
              ),
            ),

            const SizedBox(height: 20),

            // School Info
            StreamBuilder<DocumentSnapshot>(
              stream: _firebaseService.firestore
                  .collection('schools')
                  .doc(widget.user.schoolId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const SizedBox();
                }

                final schoolData =
                    snapshot.data!.data() as Map<String, dynamic>;
                final schoolName = schoolData['name'] ?? 'School';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusL),
                      boxShadow: TeacherDimensions.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.teacherPrimaryLight,
                            borderRadius: BorderRadius.circular(
                                TeacherDimensions.radiusS),
                          ),
                          child: Icon(Icons.school,
                              color: AppColors.teacherPrimary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(schoolName,
                                  style: TeacherTypography.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                widget.user.email,
                                style: TeacherTypography.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // My Classes
            if (!_isLoading && _classes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    boxShadow: TeacherDimensions.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child:
                            Text('My Classes', style: TeacherTypography.h3),
                      ),
                      ..._classes.map((classModel) {
                        final isMainTeacher =
                            classModel.teacherId == widget.user.id;
                        return ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.teacherPrimaryLight,
                              borderRadius: BorderRadius.circular(
                                  TeacherDimensions.radiusS),
                            ),
                            child: Icon(Icons.groups,
                                color: AppColors.teacherPrimary, size: 18),
                          ),
                          title: Text(classModel.name,
                              style: TeacherTypography.bodyMedium
                                  .copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${classModel.studentIds.length} students${classModel.yearLevel != null ? ' · Year ${classModel.yearLevel}' : ''}',
                            style: TeacherTypography.bodySmall,
                          ),
                          trailing: isMainTeacher
                              ? null
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.teacherPrimaryLight,
                                    borderRadius: BorderRadius.circular(
                                        TeacherDimensions.radiusRound),
                                  ),
                                  child: Text(
                                    'Assistant',
                                    style:
                                        TeacherTypography.caption.copyWith(
                                      color: AppColors.teacherPrimary,
                                    ),
                                  ),
                                ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TeacherSettingsSection(
                title: 'ACTIONS',
                items: [
                  TeacherSettingsItem(
                    icon: Icons.edit_outlined,
                    iconBgColor: AppColors.teacherPrimaryLight,
                    label: 'Edit Profile',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Edit Profile coming soon')),
                      );
                    },
                  ),
                  TeacherSettingsItem(
                    icon: Icons.feedback_outlined,
                    iconBgColor:
                        AppColors.teacherAccent.withValues(alpha: 0.2),
                    label: 'Send Feedback',
                    onTap: () {
                      showFeedbackSheet(
                        context,
                        userId: widget.user.id,
                        userRole: widget.user.role.name,
                      );
                    },
                  ),
                  TeacherSettingsItem(
                    icon: Icons.download_outlined,
                    iconBgColor: AppColors.mintGreen.withValues(alpha: 0.2),
                    label: 'Export Reports',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Export Reports coming soon')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Version info
            Text(
              'Version 1.0.0',
              style: TeacherTypography.bodySmall,
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
