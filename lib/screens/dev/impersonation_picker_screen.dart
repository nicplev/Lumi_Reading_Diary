import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/exceptions/impersonation_exceptions.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/impersonation_service.dart';

class ImpersonationPickerScreen extends ConsumerStatefulWidget {
  const ImpersonationPickerScreen({super.key});

  @override
  ConsumerState<ImpersonationPickerScreen> createState() =>
      _ImpersonationPickerScreenState();
}

class _ImpersonationPickerScreenState
    extends ConsumerState<ImpersonationPickerScreen> {
  final _service = ImpersonationService.instance;
  final _reasonController = TextEditingController();

  List<ImpersonationSchoolSummary> _schools = const [];
  List<ImpersonationUserSummary> _users = const [];

  ImpersonationSchoolSummary? _selectedSchool;
  String _selectedRole = 'teacher';
  ImpersonationUserSummary? _selectedUser;

  bool _loadingSchools = true;
  bool _loadingUsers = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _fetchSchools() async {
    try {
      final schools = await _service.listSchools();
      if (!mounted) return;
      setState(() {
        _schools = schools;
        _loadingSchools = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load schools: $e';
        _loadingSchools = false;
      });
    }
  }

  Future<void> _fetchUsersForSelection() async {
    final school = _selectedSchool;
    if (school == null) return;
    setState(() {
      _loadingUsers = true;
      _users = const [];
      _selectedUser = null;
    });
    try {
      final users = await _service.listUsers(
        schoolId: school.schoolId,
        role: _selectedRole,
      );
      if (!mounted) return;
      setState(() {
        _users = users;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load users: $e';
        _loadingUsers = false;
      });
    }
  }

  bool get _canStart =>
      _selectedSchool != null &&
      _selectedUser != null &&
      _reasonController.text.trim().length >= 20 &&
      !_starting;

  Future<void> _start() async {
    final school = _selectedSchool;
    final user = _selectedUser;
    if (school == null || user == null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _service.start(
        schoolId: school.schoolId,
        schoolName: school.name,
        userId: user.userId,
        userLabel: user.fullName.isEmpty ? user.email : user.fullName,
        role: _selectedRole,
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      final route = AppRouter.getHomeRouteForRoleName(_selectedRole);
      context.go(route);
    } on ImpersonationStartException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Start failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impersonate a school'),
        backgroundColor: const Color(0xFFB91C1C),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _loadingSchools
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _PrivacyNotice(),
                    const SizedBox(height: 16),
                    _buildSchoolDropdown(),
                    const SizedBox(height: 12),
                    _buildRoleSelector(),
                    const SizedBox(height: 12),
                    _buildUserDropdown(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reasonController,
                      maxLines: 3,
                      maxLength: 500,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Reason (min 20 chars)',
                        hintText:
                            'e.g. Reproducing reading log bug reported in ticket #123',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: TextStyle(color: Colors.red.shade700)),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _canStart ? _start : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB91C1C),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Start read-only session (30 min)'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSchoolDropdown() {
    return DropdownButtonFormField<ImpersonationSchoolSummary>(
      initialValue: _selectedSchool,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'School',
        border: OutlineInputBorder(),
      ),
      items: _schools
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(
                '${s.name} (${s.teacherCount} teachers)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (s) {
        setState(() {
          _selectedSchool = s;
          _users = const [];
          _selectedUser = null;
        });
        _fetchUsersForSelection();
      },
    );
  }

  Widget _buildRoleSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'teacher', label: Text('Teacher')),
        ButtonSegment(value: 'schoolAdmin', label: Text('School admin')),
      ],
      selected: {_selectedRole},
      onSelectionChanged: (s) {
        setState(() {
          _selectedRole = s.first;
        });
        _fetchUsersForSelection();
      },
    );
  }

  Widget _buildUserDropdown() {
    if (_loadingUsers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_selectedSchool == null) {
      return const SizedBox.shrink();
    }
    if (_users.isEmpty) {
      return Text(
        'No ${_selectedRole == "teacher" ? "teachers" : "school admins"} found in this school.',
        style: TextStyle(color: Colors.grey.shade600),
      );
    }
    return DropdownButtonFormField<ImpersonationUserSummary>(
      initialValue: _selectedUser,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'User',
        border: OutlineInputBorder(),
      ),
      items: _users
          .map(
            (u) => DropdownMenuItem(
              value: u,
              child: Text(
                u.fullName.isEmpty
                    ? u.email
                    : '${u.fullName} <${u.email}>',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (u) => setState(() => _selectedUser = u),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, color: Color(0xFFB91C1C)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are about to view real school data in READ-ONLY mode. '
              'Every session and action is logged to the super-admin audit '
              'trail and can be reviewed by the school at any time. '
              'Writes are blocked in three layers.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
