/// Thrown by [assertWritable] when a write is attempted during an active
/// developer impersonation session. Firestore security rules would also
/// reject the write server-side — this client-side throw just gives the
/// caller a clean, localised failure path and surfaces a usable message
/// in the UI.
class ImpersonationReadOnlyException implements Exception {
  ImpersonationReadOnlyException({
    required this.opLabel,
    this.collection,
    this.docId,
    this.operation,
  });

  final String opLabel;
  final String? collection;
  final String? docId;
  final String? operation;

  @override
  String toString() =>
      "ImpersonationReadOnlyException: writes are blocked during "
      "impersonation (op=$opLabel, collection=$collection, docId=$docId, "
      "operation=$operation)";
}

/// Raised when the impersonation Cloud Function rejects a request
/// (rate-limit, validation, target-not-found, etc.). Wraps the raw
/// FirebaseFunctionsException so the UI can show a concise message.
class ImpersonationStartException implements Exception {
  ImpersonationStartException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => "ImpersonationStartException($code): $message";
}
