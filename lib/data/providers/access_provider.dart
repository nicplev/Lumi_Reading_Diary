import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/school_model.dart';
import '../models/student_model.dart';
import 'active_child_provider.dart';

/// Access / entitlement state for the parent app.
///
/// Enforcement is materialised onto `student.access` (and `school.access`)
/// server-side; these providers simply read it. The security rules are the
/// hard backstop — these drive the UX (which gate screen to show, whether to
/// disable logging) so a lapsed family sees a clear "why" instead of an opaque
/// permission error.

/// Streams a single school document by id. Used to distinguish a whole-school
/// suspension ("contact Lumi") from a per-child lapse ("contact your school").
final schoolByIdProvider =
    StreamProvider.family<SchoolModel?, String>((ref, schoolId) {
  if (schoolId.isEmpty) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('schools')
      .doc(schoolId)
      .snapshots()
      .map((doc) => doc.exists ? SchoolModel.fromFirestore(doc) : null);
});

/// The reason a child is gated, if any.
enum AccessGateReason {
  /// Access is live — no gate.
  ok,

  /// The whole school is suspended (unpaid / off-boarded). Message: contact Lumi.
  schoolSuspended,

  /// This child's access has lapsed or was not renewed. Message: contact school.
  childLapsed,
}

/// Resolves the gate reason for a given student, factoring in school-wide
/// suspension. School suspension takes precedence so the message points the
/// family at the right party. Falls back to [AccessGateReason.childLapsed] for
/// any non-live access (the conservative, fail-closed message).
AccessGateReason gateReasonFor(StudentModel student, SchoolModel? school) {
  if (school != null && school.isSuspended) {
    return AccessGateReason.schoolSuspended;
  }
  if (student.hasActiveAccess) return AccessGateReason.ok;
  return AccessGateReason.childLapsed;
}

/// Convenience provider: the gate reason for the parent's active child.
/// Resolves to [AccessGateReason.ok] while data is still loading or when the
/// parent has no children, so it never blocks on a transient state — the route
/// guard and rules remain the authority.
final activeChildGateReasonProvider = Provider<AccessGateReason>((ref) {
  final child = ref.watch(activeChildProvider).value;
  if (child == null) return AccessGateReason.ok;
  final school = ref.watch(schoolByIdProvider(child.schoolId)).value;
  return gateReasonFor(child, school);
});
