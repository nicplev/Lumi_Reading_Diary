import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../services/firebase_service.dart';
import '../auth/login_screen.dart';

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

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: LumiBorders.shapeLarge,
        title: Text('Sign Out', style: LumiTextStyles.h2()),
        content: Text(
          'Are you sure you want to sign out?',
          style: LumiTextStyles.body(),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiTextButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'Sign Out',
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firebaseService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Profile', style: LumiTextStyles.h2()),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header
            Container(
              color: AppColors.white,
              padding: LumiPadding.allM,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.teacherColor,
                    child: Text(
                      widget.user.fullName.isNotEmpty
                          ? widget.user.fullName[0].toUpperCase()
                          : '?',
                      style: LumiTextStyles.display(color: AppColors.white),
                    ),
                  ),
                  LumiGap.s,
                  Text(
                    widget.user.fullName,
                    style: LumiTextStyles.h1(),
                  ),
                  LumiGap.xxs,
                  Text(
                    widget.user.email,
                    style: LumiTextStyles.bodyMedium(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  LumiGap.xs,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherColor.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.circular,
                    ),
                    child: Text(
                      'Teacher',
                      style: LumiTextStyles.label(color: AppColors.teacherColor),
                    ),
                  ),
                ],
              ),
            ),

            LumiGap.s,

            // Classes Section
            _buildSectionTitle(context, 'My Classes', Icons.groups),
            Container(
              color: AppColors.white,
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _classes.isEmpty
                      ? ListTile(
                          leading: Icon(
                            Icons.info_outline,
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                          title: Text(
                            'No classes assigned',
                            style: LumiTextStyles.bodyMedium(
                              color: AppColors.charcoal.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                      : Column(
                          children: _classes.map((classModel) {
                            final isMainTeacher = classModel.teacherId == widget.user.id;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.teacherColor.withValues(alpha: 0.1),
                                child: const Icon(
                                  Icons.groups,
                                  color: AppColors.teacherColor,
                                ),
                              ),
                              title: Text(
                                classModel.name,
                                style: LumiTextStyles.bodyMedium(),
                              ),
                              subtitle: Text(
                                '${classModel.studentIds.length} students • ${classModel.yearLevel != null ? 'Year ${classModel.yearLevel}' : ''}',
                                style: LumiTextStyles.bodySmall(
                                  color: AppColors.charcoal.withValues(alpha: 0.7),
                                ),
                              ),
                              trailing: isMainTeacher
                                  ? null
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.info.withValues(alpha: 0.1),
                                        borderRadius: LumiBorders.medium,
                                      ),
                                      child: Text(
                                        'Assistant',
                                        style: LumiTextStyles.label(color: AppColors.info),
                                      ),
                                    ),
                            );
                          }).toList(),
                        ),
            ),

            LumiGap.s,

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

                final schoolData = snapshot.data!.data() as Map<String, dynamic>;
                final schoolName = schoolData['name'] ?? 'School';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(context, 'School', Icons.school),
                    Container(
                      color: AppColors.white,
                      child: ListTile(
                        leading: const Icon(Icons.school, color: AppColors.rosePink),
                        title: Text(schoolName, style: LumiTextStyles.bodyMedium()),
                        subtitle: widget.user.schoolId != null
                            ? Text(
                                'School ID: ${widget.user.schoolId!.substring(0, 8)}...',
                                style: LumiTextStyles.bodySmall(
                                  color: AppColors.charcoal.withValues(alpha: 0.7),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),

            LumiGap.s,

            // Settings
            _buildSectionTitle(context, 'Settings', Icons.settings_outlined),
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(
                      'Notification Settings',
                      style: LumiTextStyles.bodyMedium(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to notification settings
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(
                      'Help & Support',
                      style: LumiTextStyles.bodyMedium(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to help
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(
                      'Privacy Policy',
                      style: LumiTextStyles.bodyMedium(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to privacy policy
                    },
                  ),
                ],
              ),
            ),

            LumiGap.s,

            // Actions
            Container(
              color: AppColors.white,
              child: ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: Text(
                  'Sign Out',
                  style: LumiTextStyles.bodyMedium(color: AppColors.error),
                ),
                onTap: _handleSignOut,
              ),
            ),

            LumiGap.l,

            // Version info
            Text(
              'Version 1.0.0',
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),

            LumiGap.s,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumiSpacing.s,
        LumiSpacing.s,
        LumiSpacing.s,
        LumiSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          LumiGap.xs,
          Text(
            title,
            style: LumiTextStyles.h3(color: AppColors.charcoal),
          ),
        ],
      ),
    );
  }
}