import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';

class UserManagementScreen extends StatefulWidget {
  final UserModel adminUser;

  const UserManagementScreen({
    super.key,
    required this.adminUser,
  });

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService.instance;
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _getUsersStream(String role) {
    // Using nested structure - no need for schoolId filter!
    CollectionReference usersRef = _firebaseService.firestore
        .collection('schools')
        .doc(widget.adminUser.schoolId)
        .collection('users');

    if (role != 'all') {
      return usersRef.where('role', isEqualTo: role).snapshots();
    }

    return usersRef.snapshots();
  }

  Stream<QuerySnapshot> _getStudentsStream() {
    // Using nested structure - no need for schoolId filter!
    return _firebaseService.firestore
        .collection('schools')
        .doc(widget.adminUser.schoolId)
        .collection('students')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          'User Management',
          style: LumiTextStyles.h3(color: AppColors.charcoal),
        ),
        iconTheme: const IconThemeData(color: AppColors.charcoal),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.rosePink,
          unselectedLabelColor: AppColors.charcoal.withValues(alpha: 0.7),
          indicatorColor: AppColors.rosePink,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Teachers'),
            Tab(text: 'Parents'),
            Tab(text: 'Students'),
          ],
        ),
      ),
      floatingActionButton: LumiFab(
        onPressed: () {
          if (_tabController.index == 3) {
            _showAddStudentDialog();
          } else {
            _showAddUserDialog();
          }
        },
        isExtended: true,
        icon: Icons.add,
        label: _tabController.index == 3 ? 'Add Student' : 'Add User',
      ),
      body: Column(
        children: [
          // Search Bar
          CommonWidgets.buildSearchBar(
            hintText: 'Search users...',
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
          ),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList('all'),
                _buildUserList('teacher'),
                _buildUserList('parent'),
                _buildStudentList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList(String role) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getUsersStream(role),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // More graceful error handling - show loading instead of hard error
          // This handles temporary permission issues after user creation
          debugPrint('Stream error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: AppColors.rosePink,
                ),
                LumiGap.s,
                Text(
                  'Loading users...',
                  style: LumiTextStyles.body(color: AppColors.charcoal.withValues(alpha: 0.7)),
                ),
                LumiGap.xs,
                LumiTextButton(
                  onPressed: () => setState(() {}),
                  text: 'Retry',
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return CommonWidgets.buildLoadingIndicator();
        }

        final docs = snapshot.data!.docs;
        final filteredDocs = docs.where((doc) {
          final user = UserModel.fromFirestore(doc);
          final searchLower = _searchQuery.toLowerCase();
          return user.fullName.toLowerCase().contains(searchLower) ||
              user.email.toLowerCase().contains(searchLower);
        }).toList();

        if (filteredDocs.isEmpty) {
          return CommonWidgets.buildEmptyState(
            icon: Icons.people_outline,
            title: 'No users found',
            subtitle: 'Try adjusting your search or add a new user',
          );
        }

        return ListView.builder(
          padding: LumiPadding.allS,
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final user = UserModel.fromFirestore(filteredDocs[index]);
            return _buildUserCard(user);
          },
        );
      },
    );
  }

  Widget _buildStudentList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getStudentsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // More graceful error handling - show loading instead of hard error
          // This handles temporary permission issues after user creation
          debugPrint('Stream error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: AppColors.rosePink,
                ),
                LumiGap.s,
                Text(
                  'Loading users...',
                  style: LumiTextStyles.body(color: AppColors.charcoal.withValues(alpha: 0.7)),
                ),
                LumiGap.xs,
                LumiTextButton(
                  onPressed: () => setState(() {}),
                  text: 'Retry',
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return CommonWidgets.buildLoadingIndicator();
        }

        final docs = snapshot.data!.docs;
        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final searchLower = _searchQuery.toLowerCase();
          final firstName = (data['firstName'] ?? '').toLowerCase();
          final lastName = (data['lastName'] ?? '').toLowerCase();
          final studentId = (data['studentId'] ?? '').toLowerCase();
          return firstName.contains(searchLower) ||
              lastName.contains(searchLower) ||
              studentId.contains(searchLower);
        }).toList();

        if (filteredDocs.isEmpty) {
          return CommonWidgets.buildEmptyState(
            icon: Icons.school_outlined,
            title: 'No students found',
            subtitle: 'Try adjusting your search or add a new student',
          );
        }

        return ListView.builder(
          padding: LumiPadding.allS,
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final doc = filteredDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildStudentCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildUserCard(UserModel user) {
    final roleString = user.role.toString().split('.').last;
    final roleColor = _getRoleColor(roleString);
    final roleIcon = _getRoleIcon(roleString);

    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.listItemSpacing),
      child: LumiCard(
        padding: EdgeInsets.zero,
        child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withValues(alpha: 0.2),
          child: Icon(roleIcon, color: roleColor),
        ),
        title: Text(
          user.fullName,
          style: LumiTextStyles.bodyLarge().copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            LumiGap.xxs,
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: LumiSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.medium,
                  ),
                  child: Text(
                    roleString.toUpperCase(),
                    style: LumiTextStyles.caption(color: roleColor).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                LumiGap.horizontalXS,
                if (!user.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.medium,
                    ),
                    child: Text(
                      'INACTIVE',
                      style: LumiTextStyles.caption(color: AppColors.error).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleUserAction(value, user),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  LumiGap.horizontalXS,
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: user.isActive ? 'deactivate' : 'activate',
              child: Row(
                children: [
                  Icon(
                    user.isActive ? Icons.block : Icons.check_circle,
                    size: 20,
                  ),
                  LumiGap.horizontalXS,
                  Text(user.isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'reset_password',
              child: Row(
                children: [
                  Icon(Icons.lock_reset, size: 20),
                  LumiGap.horizontalXS,
                  Text('Reset Password'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: AppColors.error),
                  LumiGap.horizontalXS,
                  Text('Delete', style: LumiTextStyles.body(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(String studentId, Map<String, dynamic> data) {
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final yearLevel = data['yearLevel'] ?? '';
    final className = data['className'] ?? '';
    final isActive = data['isActive'] ?? true;

    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.listItemSpacing),
      child: LumiCard(
        padding: EdgeInsets.zero,
        child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.rosePink.withValues(alpha: 0.2),
          child: Text(
            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
            style: LumiTextStyles.body(color: AppColors.rosePink).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '$firstName $lastName',
          style: LumiTextStyles.bodyLarge().copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student ID: ${data['studentId'] ?? studentId}'),
            LumiGap.xxs,
            Row(
              children: [
                if (yearLevel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryPurple.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.medium,
                    ),
                    child: Text(
                      yearLevel,
                      style: LumiTextStyles.caption(color: AppColors.secondaryPurple).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (className.isNotEmpty) ...[
                  LumiGap.horizontalXS,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherColor.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.medium,
                    ),
                    child: Text(
                      className,
                      style: LumiTextStyles.caption(color: AppColors.teacherColor).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (!isActive) ...[
                  LumiGap.horizontalXS,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: LumiBorders.medium,
                    ),
                    child: Text(
                      'INACTIVE',
                      style: LumiTextStyles.caption(color: AppColors.error).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleStudentAction(value, studentId, data),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  LumiGap.horizontalXS,
                  Text('Edit'),
                ],
              ),
            ),
            PopupMenuItem(
              value: isActive ? 'deactivate' : 'activate',
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.block : Icons.check_circle,
                    size: 20,
                  ),
                  LumiGap.horizontalXS,
                  Text(isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: AppColors.error),
                  LumiGap.horizontalXS,
                  Text('Delete', style: LumiTextStyles.body(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'teacher':
        return AppColors.teacherColor;
      case 'parent':
        return AppColors.rosePink;
      case 'schoolAdmin':
        return AppColors.adminColor;
      default:
        return AppColors.charcoal.withValues(alpha: 0.7);
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'teacher':
        return Icons.school;
      case 'parent':
        return Icons.family_restroom;
      case 'schoolAdmin':
        return Icons.admin_panel_settings;
      default:
        return Icons.person;
    }
  }

  Future<void> _handleUserAction(String action, UserModel user) async {
    switch (action) {
      case 'edit':
        await _showEditUserDialog(user);
        break;
      case 'activate':
      case 'deactivate':
        await _toggleUserStatus(user);
        break;
      case 'reset_password':
        await _resetUserPassword(user);
        break;
      case 'delete':
        await _deleteUser(user);
        break;
    }
  }

  Future<void> _handleStudentAction(
    String action,
    String studentId,
    Map<String, dynamic> data,
  ) async {
    switch (action) {
      case 'edit':
        await _showEditStudentDialog(studentId, data);
        break;
      case 'activate':
      case 'deactivate':
        await _toggleStudentStatus(studentId, data['isActive'] ?? true);
        break;
      case 'delete':
        await _deleteStudent(studentId);
        break;
    }
  }

  Future<void> _toggleUserStatus(UserModel user) async {
    try {
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('users')
          .doc(user.id)
          .update({
        'isActive': !user.isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        CommonWidgets.showSuccessSnackbar(
          context,
          user.isActive
              ? 'User deactivated successfully'
              : 'User activated successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        CommonWidgets.showErrorSnackbar(context, 'Error updating user: $e');
      }
    }
  }

  Future<void> _toggleStudentStatus(String studentId, bool currentStatus) async {
    try {
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .doc(studentId)
          .update({
        'isActive': !currentStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        CommonWidgets.showSuccessSnackbar(
          context,
          currentStatus
              ? 'Student deactivated successfully'
              : 'Student activated successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        CommonWidgets.showErrorSnackbar(context, 'Error updating student: $e');
      }
    }
  }

  Future<void> _resetUserPassword(UserModel user) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email);

      if (mounted) {
        CommonWidgets.showSuccessSnackbar(
          context,
          'Password reset email sent to ${user.email}',
        );
      }
    } catch (e) {
      if (mounted) {
        CommonWidgets.showErrorSnackbar(context, 'Error sending reset email: $e');
      }
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete ${user.fullName}? This action cannot be undone.'),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: LumiBorders.small,
              ),
            ),
            child: Text('Delete', style: LumiTextStyles.button(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('users')
            .doc(user.id)
            .delete();

        if (mounted) {
          CommonWidgets.showSuccessSnackbar(context, 'User deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          CommonWidgets.showErrorSnackbar(context, 'Error deleting user: $e');
        }
      }
    }
  }

  Future<void> _deleteStudent(String studentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Student'),
        content: const Text('Are you sure you want to delete this student? This action cannot be undone.'),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: LumiBorders.small,
              ),
            ),
            child: Text('Delete', style: LumiTextStyles.button(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.adminUser.schoolId)
            .collection('students')
            .doc(studentId)
            .delete();

        if (mounted) {
          CommonWidgets.showSuccessSnackbar(context, 'Student deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          CommonWidgets.showErrorSnackbar(context, 'Error deleting student: $e');
        }
      }
    }
  }

  Future<void> _showAddUserDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    String selectedRole = 'teacher';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New User'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Role Selection
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'teacher',
                        child: Text('Teacher'),
                      ),
                      DropdownMenuItem(
                        value: 'parent',
                        child: Text('Parent'),
                      ),
                      DropdownMenuItem(
                        value: 'schoolAdmin',
                        child: Text('School Admin'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedRole = value!;
                      });
                    },
                  ),
                  LumiGap.s,
                  // First Name
                  TextFormField(
                    controller: firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter first name';
                      }
                      return null;
                    },
                  ),
                  LumiGap.s,
                  // Last Name
                  TextFormField(
                    controller: lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter last name';
                      }
                      return null;
                    },
                  ),
                  LumiGap.s,
                  // Email
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  LumiGap.s,
                  // Password
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      helperText: 'Min 6 characters',
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            LumiTextButton(
              onPressed: () => Navigator.pop(context, false),
              text: 'Cancel',
            ),
            LumiPrimaryButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              text: 'Add User',
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _createUser(
        email: emailController.text.trim(),
        password: passwordController.text,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        role: selectedRole,
      );
    }
  }

  Future<void> _createUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String role,
  }) async {
    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      // Store current admin credentials to re-authenticate later
      final currentUser = FirebaseAuth.instance.currentUser;
      final adminEmail = currentUser?.email;

      if (adminEmail == null) {
        throw Exception('Admin user not authenticated');
      }

      // Create user in Firebase Auth
      // Note: This will temporarily sign in as the new user
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userId = userCredential.user!.uid;

      // Create user document in Firestore while still authenticated as new user
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('users')
          .doc(userId)
          .set({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'fullName': '$firstName $lastName',
        'role': role,
        'schoolId': widget.adminUser.schoolId,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Sign out the newly created user
      await FirebaseAuth.instance.signOut();

      // Navigate back to login to re-authenticate as admin
      // This is the cleanest approach without needing admin password
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        // Show success message and navigate to login
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('User Created Successfully'),
            content: Text(
              'User $firstName $lastName has been created.\n\nPlease sign in again to continue.',
            ),
            actions: [
              LumiPrimaryButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to login screen
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (route) => false,
                  );
                },
                text: 'Go to Login',
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        CommonWidgets.showErrorSnackbar(context, 'Error creating user: $e');
      }
    }
  }

  Future<void> _showAddStudentDialog() async {
    final formKey = GlobalKey<FormState>();
    final studentIdController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final yearLevelController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Student'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Student ID
                TextFormField(
                  controller: studentIdController,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter student ID';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // First Name
                TextFormField(
                  controller: firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter first name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Last Name
                TextFormField(
                  controller: lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter last name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Year Level
                TextFormField(
                  controller: yearLevelController,
                  decoration: const InputDecoration(
                    labelText: 'Year Level',
                    hintText: 'e.g., Year 3',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter year level';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiPrimaryButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            text: 'Add Student',
          ),
        ],
      ),
    );

    if (result == true) {
      await _createStudent(
        studentId: studentIdController.text.trim(),
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        yearLevel: yearLevelController.text.trim(),
      );
    }
  }

  Future<void> _createStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String yearLevel,
  }) async {
    try {
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .add({
        'studentId': studentId,
        'firstName': firstName,
        'lastName': lastName,
        'yearLevel': yearLevel,
        'schoolId': widget.adminUser.schoolId,
        'isActive': true,
        'parentIds': [],
        'classIds': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        CommonWidgets.showSuccessSnackbar(
          context,
          'Student $firstName $lastName added successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        CommonWidgets.showErrorSnackbar(context, 'Error adding student: $e');
      }
    }
  }

  Future<void> _showEditUserDialog(UserModel user) async {
    final formKey = GlobalKey<FormState>();
    // Split fullName into first and last name for editing
    final nameParts = user.fullName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final firstNameController = TextEditingController(text: firstName);
    final lastNameController = TextEditingController(text: lastName);
    final emailController = TextEditingController(text: user.email);
    String selectedRole = user.role.toString().split('.').last;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit User'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Role Selection
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'teacher',
                        child: Text('Teacher'),
                      ),
                      DropdownMenuItem(
                        value: 'parent',
                        child: Text('Parent'),
                      ),
                      DropdownMenuItem(
                        value: 'schoolAdmin',
                        child: Text('School Admin'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedRole = value!;
                      });
                    },
                  ),
                  LumiGap.s,
                  // First Name
                  TextFormField(
                    controller: firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter first name';
                      }
                      return null;
                    },
                  ),
                  LumiGap.s,
                  // Last Name
                  TextFormField(
                    controller: lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter last name';
                      }
                      return null;
                    },
                  ),
                  LumiGap.s,
                  // Email (read-only)
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      enabled: false,
                    ),
                    readOnly: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            LumiTextButton(
              onPressed: () => Navigator.pop(context, false),
              text: 'Cancel',
            ),
            LumiPrimaryButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              text: 'Update User',
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _updateUser(
        user: user,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        role: selectedRole,
      );
    }
  }

  Future<void> _updateUser({
    required UserModel user,
    required String firstName,
    required String lastName,
    required String role,
  }) async {
    try {
      final fullName = '$firstName $lastName';
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('users')
          .doc(user.id)
          .update({
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        CommonWidgets.showSuccessSnackbar(
          context,
          'User $fullName updated successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        CommonWidgets.showErrorSnackbar(context, 'Error updating user: $e');
      }
    }
  }

  Future<void> _showEditStudentDialog(String studentId, Map<String, dynamic> data) async {
    final formKey = GlobalKey<FormState>();
    final studentIdController = TextEditingController(text: data['studentId'] ?? studentId);
    final firstNameController = TextEditingController(text: data['firstName'] ?? '');
    final lastNameController = TextEditingController(text: data['lastName'] ?? '');
    final yearLevelController = TextEditingController(text: data['yearLevel'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Student'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Student ID
                TextFormField(
                  controller: studentIdController,
                  decoration: const InputDecoration(
                    labelText: 'Student ID',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter student ID';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // First Name
                TextFormField(
                  controller: firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter first name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Last Name
                TextFormField(
                  controller: lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter last name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Year Level
                TextFormField(
                  controller: yearLevelController,
                  decoration: const InputDecoration(
                    labelText: 'Year Level',
                    hintText: 'e.g., Year 3',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter year level';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiPrimaryButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            text: 'Update Student',
          ),
        ],
      ),
    );

    if (result == true) {
      await _updateStudent(
        studentId: studentId,
        newStudentId: studentIdController.text.trim(),
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        yearLevel: yearLevelController.text.trim(),
      );
    }
  }

  Future<void> _updateStudent({
    required String studentId,
    required String newStudentId,
    required String firstName,
    required String lastName,
    required String yearLevel,
  }) async {
    try {
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.adminUser.schoolId)
          .collection('students')
          .doc(studentId)
          .update({
        'studentId': newStudentId,
        'firstName': firstName,
        'lastName': lastName,
        'yearLevel': yearLevel,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        CommonWidgets.showSuccessSnackbar(
          context,
          'Student $firstName $lastName updated successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        CommonWidgets.showErrorSnackbar(context, 'Error updating student: $e');
      }
    }
  }
}