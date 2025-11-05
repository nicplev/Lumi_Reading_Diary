import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
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
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
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
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.teacherColor,
                    child: Text(
                      widget.user.fullName.isNotEmpty
                          ? widget.user.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 36,
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.user.fullName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user.email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Teacher',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.teacherColor,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

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
                          leading: const Icon(Icons.info_outline, color: AppColors.gray),
                          title: Text(
                            'No classes assigned',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.gray,
                                ),
                          ),
                        )
                      : Column(
                          children: _classes.map((classModel) {
                            final isMainTeacher = classModel.teacherId == widget.user.id;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.teacherColor.withOpacity(0.1),
                                child: const Icon(
                                  Icons.groups,
                                  color: AppColors.teacherColor,
                                ),
                              ),
                              title: Text(classModel.name),
                              subtitle: Text(
                                '${classModel.studentIds.length} students • ${classModel.yearLevel != null ? 'Year ${classModel.yearLevel}' : ''}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.gray,
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
                                        color: AppColors.info.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Assistant',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: AppColors.info,
                                            ),
                                      ),
                                    ),
                            );
                          }).toList(),
                        ),
            ),

            const SizedBox(height: 16),

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
                        leading: const Icon(Icons.school, color: AppColors.primaryBlue),
                        title: Text(schoolName),
                        subtitle: widget.user.schoolId != null
                            ? Text(
                                'School ID: ${widget.user.schoolId!.substring(0, 8)}...',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.gray,
                                    ),
                              )
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // Settings
            _buildSectionTitle(context, 'Settings', Icons.settings_outlined),
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notification Settings'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to notification settings
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Help & Support'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to help
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to privacy policy
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Actions
            Container(
              color: AppColors.white,
              child: ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: Text(
                  'Sign Out',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: _handleSignOut,
              ),
            ),

            const SizedBox(height: 32),

            // Version info
            Text(
              'Version 1.0.0',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray,
                  ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.gray),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGray,
                ),
          ),
        ],
      ),
    );
  }
}