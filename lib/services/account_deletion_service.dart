import 'package:cloud_functions/cloud_functions.dart';

import '../core/services/functions_instance.dart';

typedef AccountDeletionInvoker = Future<Object?> Function(
  String name,
  Map<String, dynamic> arguments,
);

Future<Object?> _invokeDeletionCallable(
  String name,
  Map<String, dynamic> arguments,
) async {
  final result =
      await lumiFunctions.httpsCallable(name).call<Object?>(arguments);
  return result.data;
}

enum DeletionKind { account, student }

enum DeletionState { pending, processing, failed, completed }

class DeletionJobStatus {
  const DeletionJobStatus({
    required this.jobId,
    required this.kind,
    required this.state,
    required this.attemptCount,
    required this.retrying,
    this.requestedAt,
    this.startedAt,
    this.completedAt,
  });

  final String jobId;
  final DeletionKind kind;
  final DeletionState state;
  final int attemptCount;
  final bool retrying;
  final DateTime? requestedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory DeletionJobStatus.fromMap(Map<String, dynamic> data) {
    return DeletionJobStatus(
      jobId: data['jobId'] as String? ?? '',
      kind: data['kind'] == 'student'
          ? DeletionKind.student
          : DeletionKind.account,
      state: switch (data['status']) {
        'processing' => DeletionState.processing,
        'failed' => DeletionState.failed,
        'completed' => DeletionState.completed,
        _ => DeletionState.pending,
      },
      attemptCount: (data['attemptCount'] as num?)?.toInt() ?? 0,
      retrying: data['retrying'] == true,
      requestedAt: _parseDate(data['requestedAt']),
      startedAt: _parseDate(data['startedAt']),
      completedAt: _parseDate(data['completedAt']),
    );
  }

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.code, this.message);

  final String code;
  final String message;

  bool get requiresRecentLogin =>
      code == 'failed-precondition' && message == 'recent-login-required';

  @override
  String toString() => message;
}

class AccountDeletionService {
  AccountDeletionService({AccountDeletionInvoker? callableInvoker})
      : _invoke = callableInvoker ?? _invokeDeletionCallable;

  final AccountDeletionInvoker _invoke;

  Future<DeletionJobStatus?> loadAccountStatus() async {
    final response = await _call('getMyDeletionStatus', {
      'kind': 'account',
    });
    final job = response['job'];
    return job is Map ? _parseStatus(job) : null;
  }

  Future<DeletionJobStatus?> loadStudentStatus({
    required String schoolId,
    required String studentId,
  }) async {
    final response = await _call('getMyDeletionStatus', {
      'kind': 'student',
      'schoolId': schoolId,
      'studentId': studentId,
    });
    final job = response['job'];
    return job is Map ? _parseStatus(job) : null;
  }

  Future<DeletionJobStatus> requestAccountDeletion() async {
    return _parseStatus(await _call('requestAccountDeletion', {
      'confirmation': 'DELETE',
    }));
  }

  Future<DeletionJobStatus> requestStudentDeletion({
    required String schoolId,
    required String studentId,
    required String studentName,
  }) async {
    return _parseStatus(await _call('requestStudentDeletion', {
      'schoolId': schoolId,
      'studentId': studentId,
      'studentName': studentName,
      'confirmation': 'DELETE',
    }));
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final data = await _invoke(name, arguments);
      if (data is! Map) {
        throw const AccountDeletionException(
          'invalid-response',
          'Lumi received an invalid deletion response. Please try again.',
        );
      }
      return Map<String, dynamic>.from(data);
    } on FirebaseFunctionsException catch (error) {
      final message =
          error.message ?? 'The deletion request could not be completed.';
      throw AccountDeletionException(error.code, message);
    }
  }

  DeletionJobStatus _parseStatus(Map<dynamic, dynamic> data) =>
      DeletionJobStatus.fromMap(Map<String, dynamic>.from(data));
}
