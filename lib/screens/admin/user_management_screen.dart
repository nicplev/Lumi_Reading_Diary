import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
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
        title: const Text(
          'User Management',
          style: TextStyle(color: AppColors.darkGray),
        ),
        iconTheme: const IconThemeData(color: AppColors.darkGray),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: AppColors.gray,
          indicatorColor: AppColors.primaryBlue,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Teachers'),
            Tab(text: 'Parents'),
            Tab(text: 'Students'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'user_management_fab',
        onPressed: () {
          if (_tabController.index == 3) {
            _showAddStudentDialog();
          } else {
            _showAddUserDialog();
          }
        },
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 3 ? 'Add Student' : 'Add User'),
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
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading users...',
                  style: TextStyle(color: AppColors.gray),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
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
          padding: const EdgeInsets.all(16),
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
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Loading users...',
                  style: TextStyle(color: AppColors.gray),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
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
          padding: const EdgeInsets.all(16),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.2),
          child: Icon(roleIcon, color: roleColor),
        ),
        title: Text(
          user.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    roleString.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: roleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!user.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'INACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
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
                  SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                  Text(user.isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'reset_password',
              child: Row(
                children: [
                  Icon(Icons.lock_reset, size: 20),
                  SizedBox(width: 8),
                  Text('Reset Password'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryBlue.withOpacity(0.2),
          child: Text(
            firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '$firstName $lastName',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student ID: ${data['studentId'] ?? studentId}'),
            const SizedBox(height: 4),
            Row(
              children: [
                if (yearLevel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      yearLevel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryPurple,
                      ),
                    ),
                  ),
                if (className.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      className,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.teacherColor,
                      ),
                    ),
                  ),
                ],
                if (!isActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'INACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
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
                  SizedBox(width: 8),
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
                  const SizedBox(width: 8),
                  Text(isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'teacher':
        return AppColors.teacherColor;
      case 'parent':
        return AppColors.primaryBlue;
      case 'schoolAdmin':
        return AppColors.adminColor;
      default:
        return AppColors.gray;
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
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
                  const SizedBox(height: 16),
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
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              child: const Text('Add User'),
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
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to login screen
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                ),
                child: const Text('Go to Login'),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Add Student'),
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
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              child: const Text('Update User'),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Update Student'),
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