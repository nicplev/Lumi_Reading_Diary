import '../exceptions/impersonation_exceptions.dart';
import 'impersonation_service.dart';

/// Throws [ImpersonationReadOnlyException] if a developer impersonation
/// session is active. Call at the entry of any client-side Firestore mutation
/// (repository create/update/delete) so the failure surfaces with a usable
/// message before the Firestore rule-level block rejects the write.
///
/// Also fires a fire-and-forget audit event via [ImpersonationService] so
/// blocked writes appear in the audit trail.
void assertWritable({
  required String opLabel,
  String? collection,
  String? docId,
  String? operation,
}) {
  final service = ImpersonationService.instance;
  if (!service.isActive) return;

  // Fire-and-forget; do not await so the caller's synchronous throw is fast.
  // The server-side Firestore rule is the authoritative block.
  service.reportBlockedWrite(
    collection: collection ?? opLabel,
    docId: docId,
    operation: operation,
    reason: 'client_guard',
  );

  throw ImpersonationReadOnlyException(
    opLabel: opLabel,
    collection: collection,
    docId: docId,
    operation: operation,
  );
}
