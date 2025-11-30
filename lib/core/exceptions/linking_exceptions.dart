/// Custom exceptions for the parent-student linking process
/// These provide user-friendly error messages for better UX
library;

abstract class LinkingException implements Exception {
  final String message;
  final String userMessage;

  LinkingException(this.message, this.userMessage);

  @override
  String toString() => 'LinkingException: $message';
}

/// Thrown when a link code is not found or is invalid
class InvalidCodeException extends LinkingException {
  InvalidCodeException()
      : super(
          'Code not found or invalid',
          'This code is invalid or has expired. Please check with your child\'s teacher for a new code.',
        );
}

/// Thrown when a link code has already been used by another parent
class CodeAlreadyUsedException extends LinkingException {
  CodeAlreadyUsedException()
      : super(
          'Code has already been used',
          'This code has already been used by another parent. Each code can only be used once. Please request a new code from your child\'s teacher.',
        );
}

/// Thrown when a parent is already linked to the student
class AlreadyLinkedException extends LinkingException {
  AlreadyLinkedException()
      : super(
          'Parent already linked to student',
          'You are already linked to this student. You can log in and start tracking reading!',
        );
}

/// Thrown when the student associated with a code cannot be found
class StudentNotFoundException extends LinkingException {
  StudentNotFoundException()
      : super(
          'Student not found',
          'The student associated with this code could not be found. Please contact your school administrator.',
        );
}

/// Thrown when the parent document cannot be found during linking
class ParentDocumentNotFoundException extends LinkingException {
  ParentDocumentNotFoundException()
      : super(
          'Parent document not found',
          'There was an error setting up your account. Please try registering again or contact support.',
        );
}

/// Thrown when the Firestore transaction fails
class TransactionFailedException extends LinkingException {
  final String details;

  TransactionFailedException(this.details)
      : super(
          'Transaction failed: $details',
          'There was an error completing your registration. Please try again. If the problem persists, contact support.',
        );
}

/// Thrown when a code has been revoked by an administrator
class CodeRevokedException extends LinkingException {
  final String? reason;

  CodeRevokedException({this.reason})
      : super(
          'Code has been revoked${reason != null ? ": $reason" : ""}',
          reason != null
              ? 'This code has been revoked: $reason. Please contact your school for a new code.'
              : 'This code has been revoked. Please contact your school for a new code.',
        );
}

/// Thrown when a code has expired
class CodeExpiredException extends LinkingException {
  CodeExpiredException()
      : super(
          'Code has expired',
          'This code has expired. Please request a new code from your child\'s teacher.',
        );
}
