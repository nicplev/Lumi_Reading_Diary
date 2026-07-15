import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/auth/sign_out_flow.dart';
import '../../data/models/student_model.dart';
import '../../data/models/user_model.dart';
import '../../services/account_deletion_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.user,
    this.deletionService,
    this.firestore,
  });

  final UserModel user;
  final AccountDeletionService? deletionService;
  final FirebaseFirestore? firestore;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountDeletionService _deletionService;
  late final FirebaseFirestore _firestore;
  DeletionJobStatus? _accountStatus;
  bool _loadingStatus = true;
  bool _deletingAccount = false;
  bool _loadingStudents = false;
  String? _error;

  bool get _canDeleteStudents =>
      widget.user.role == UserRole.teacher ||
      widget.user.role == UserRole.schoolAdmin;

  @override
  void initState() {
    super.initState();
    _deletionService = widget.deletionService ?? AccountDeletionService();
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _refreshAccountStatus();
  }

  Future<void> _refreshAccountStatus() async {
    try {
      final status = await _deletionService.loadAccountStatus();
      if (mounted) setState(() => _accountStatus = status);
    } catch (_) {
      // Status is helpful context, but a transient load failure must not hide
      // the deletion control itself.
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await _showAccountConfirmation();
    if (!confirmed || !mounted) return;

    setState(() {
      _deletingAccount = true;
      _error = null;
    });
    try {
      final status = await _deletionService.requestAccountDeletion();
      if (!mounted) return;
      setState(() => _accountStatus = status);
      if (status.state == DeletionState.completed) {
        await signOutAndNavigateToLogin(context);
      }
    } on AccountDeletionException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
      await _refreshAccountStatus();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The request could not be confirmed. Check your connection and try again.');
      }
      await _refreshAccountStatus();
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  String _messageFor(AccountDeletionException error) {
    if (error.requiresRecentLogin) {
      return 'For your security, sign out and sign back in before deleting data.';
    }
    if (error.code == 'permission-denied') {
      return 'You do not have permission to delete this data.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'The request may still be processing. Reopen this screen in a moment to check.';
    }
    return error.message;
  }

  Future<bool> _showAccountConfirmation() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Permanently delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_accountDeletionExplanation),
              const SizedBox(height: LumiTokens.space4),
              const Text('Type DELETE to continue.'),
              const SizedBox(height: LumiTokens.space2),
              TextField(
                key: const Key('account-delete-confirmation'),
                controller: controller,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Confirmation'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-account-deletion'),
              onPressed: controller.text == 'DELETE'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: LumiTokens.red),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result == true;
  }

  String get _accountDeletionExplanation {
    if (widget.user.role == UserRole.parent) {
      return 'This removes your Lumi login, profile, preferences and content you created. '
          'A school must retain and manage its student records, so deleting your account '
          'does not delete your child\'s school record. Contact the school to request that.';
    }
    return 'This removes your Lumi login, staff profile, preferences and content you created. '
        'It does not delete student records or other staff accounts.';
  }

  Future<void> _chooseStudentToDelete() async {
    if (_loadingStudents) return;
    setState(() {
      _loadingStudents = true;
      _error = null;
    });
    try {
      final students = await _loadDeletableStudents();
      if (!mounted) return;
      if (students.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students available to delete.')),
        );
        return;
      }
      final student = await showDialog<StudentModel>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Choose a student'),
          children: students
              .map((student) => SimpleDialogOption(
                    key: Key('delete-student-${student.id}'),
                    onPressed: () => Navigator.pop(dialogContext, student),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(student.fullName),
                    ),
                  ))
              .toList(),
        ),
      );
      if (student != null && mounted) await _confirmStudentDeletion(student);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Students could not be loaded. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  Future<List<StudentModel>> _loadDeletableStudents() async {
    final schoolId = widget.user.schoolId;
    if (schoolId == null || schoolId.isEmpty) return const [];
    final school = _firestore.collection('schools').doc(schoolId);

    if (widget.user.role == UserRole.schoolAdmin) {
      final snapshot = await school.collection('students').get();
      final students = snapshot.docs
          .map(StudentModel.fromFirestore)
          .where((student) => student.isActive)
          .toList();
      students.sort((a, b) => a.fullName.compareTo(b.fullName));
      return students;
    }

    final classes = school.collection('classes');
    final classResults = await Future.wait([
      classes.where('teacherId', isEqualTo: widget.user.id).get(),
      classes.where('teacherIds', arrayContains: widget.user.id).get(),
    ]);
    final classIds = <String>{
      for (final result in classResults)
        for (final doc in result.docs) doc.id,
    };
    if (classIds.isEmpty) return const [];

    final results = await Future.wait(classIds.map(
      (classId) => school
          .collection('students')
          .where('classId', isEqualTo: classId)
          .get(),
    ));
    final students = <String, StudentModel>{};
    for (final result in results) {
      for (final doc in result.docs) {
        final student = StudentModel.fromFirestore(doc);
        if (student.isActive) students[student.id] = student;
      }
    }
    final sorted = students.values.toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return sorted;
  }

  Future<void> _confirmStudentDeletion(StudentModel student) async {
    final nameController = TextEditingController();
    final deleteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid = nameController.text.trim().toLowerCase() ==
                  student.fullName.trim().toLowerCase() &&
              deleteController.text == 'DELETE';
          return AlertDialog(
            title: Text('Delete ${student.fullName}?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently removes the student profile, reading logs, '
                    'comments, audio, allocations, links and notifications. Guardian '
                    'accounts are not deleted. This cannot be undone.',
                  ),
                  const SizedBox(height: LumiTokens.space4),
                  Text('Type the full name: ${student.fullName}'),
                  TextField(
                    key: const Key('student-name-confirmation'),
                    controller: nameController,
                    autocorrect: false,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: LumiTokens.space3),
                  const Text('Then type DELETE'),
                  TextField(
                    key: const Key('student-delete-confirmation'),
                    controller: deleteController,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-student-deletion'),
                onPressed:
                    valid ? () => Navigator.pop(dialogContext, true) : null,
                style: FilledButton.styleFrom(backgroundColor: LumiTokens.red),
                child: const Text('Delete student data'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    deleteController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _loadingStudents = true);
    try {
      final status = await _deletionService.requestStudentDeletion(
        schoolId: student.schoolId,
        studentId: student.id,
        studentName: student.fullName,
      );
      if (!mounted) return;
      final message = status.state == DeletionState.completed
          ? '${student.fullName}\'s data has been permanently deleted.'
          : 'Deletion is processing and will retry automatically if needed.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on AccountDeletionException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The deletion request could not be confirmed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: LumiTokens.cream,
        title: const Text('Account'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(LumiTokens.space4),
        children: [
          _AccountCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.user.fullName, style: LumiType.subhead),
                const SizedBox(height: LumiTokens.space1),
                Text(widget.user.contactIdentifier, style: LumiType.caption),
                const SizedBox(height: LumiTokens.space2),
                Text(
                  widget.user.role == UserRole.parent
                      ? 'Parent / guardian account'
                      : 'School staff account',
                  style: LumiType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: LumiTokens.space5),
          Text('Data deletion', style: LumiType.subhead),
          const SizedBox(height: LumiTokens.space2),
          Text(
            'Deletion is permanent. Lumi checks your permissions again on the server '
            'and records only a minimal completion receipt.',
            style: LumiType.caption,
          ),
          const SizedBox(height: LumiTokens.space4),
          if (_loadingStatus) const LinearProgressIndicator(),
          if (_accountStatus != null &&
              _accountStatus!.state != DeletionState.completed)
            _StatusBanner(status: _accountStatus!),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(LumiTokens.space3),
              decoration: BoxDecoration(
                color: LumiTokens.tintRed.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              ),
              child: Text(_error!, key: const Key('deletion-error')),
            ),
            const SizedBox(height: LumiTokens.space3),
          ],
          _DangerCard(
            icon: Icons.person_remove_outlined,
            title: 'Delete my account',
            body: _accountDeletionExplanation,
            buttonKey: const Key('delete-account-button'),
            buttonLabel: _deletingAccount ? 'Deleting…' : 'Delete my account',
            onPressed: _deletingAccount ? null : _requestAccountDeletion,
          ),
          if (_canDeleteStudents) ...[
            const SizedBox(height: LumiTokens.space4),
            _DangerCard(
              icon: Icons.school_outlined,
              title: 'Delete student data',
              body: 'Available only for students in your assigned classes. '
                  'Guardian accounts are kept intact.',
              buttonKey: const Key('delete-student-button'),
              buttonLabel:
                  _loadingStudents ? 'Please wait…' : 'Choose a student',
              onPressed: _loadingStudents ? null : _chooseStudentToDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(LumiTokens.space4),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          boxShadow: LumiTokens.shadowCard,
        ),
        child: child,
      );
}

class _DangerCard extends StatelessWidget {
  const _DangerCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _AccountCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: LumiTokens.red),
                const SizedBox(width: LumiTokens.space2),
                Expanded(
                  child: Text(title,
                      style:
                          LumiType.body.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: LumiTokens.space2),
            Text(body, style: LumiType.caption),
            const SizedBox(height: LumiTokens.space4),
            OutlinedButton(
              key: buttonKey,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(foregroundColor: LumiTokens.red),
              child: Text(buttonLabel),
            ),
          ],
        ),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final DeletionJobStatus status;

  @override
  Widget build(BuildContext context) {
    final text = switch (status.state) {
      DeletionState.failed when status.retrying =>
        'Deletion is waiting to retry automatically.',
      DeletionState.failed =>
        'Deletion needs support. No further automatic retries are scheduled.',
      DeletionState.processing => 'Deletion is currently processing.',
      _ => 'Deletion is queued for processing.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: LumiTokens.space3),
      child: Container(
        padding: const EdgeInsets.all(LumiTokens.space3),
        decoration: BoxDecoration(
          color: LumiTokens.tintYellow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: LumiTokens.space3),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
