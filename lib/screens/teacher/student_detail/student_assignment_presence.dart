import '../../../data/models/allocation_model.dart';

/// Whether [allocation] currently applies to [studentId].
///
/// Keep this eligibility check shared by the normal Assigned Books list and
/// the first-read gate so a classmate's allocation, an expired allocation, or
/// a student-specific removal cannot suppress the appropriate empty state.
bool isCurrentStudentAssignment(
  AllocationModel allocation,
  String studentId, {
  DateTime? now,
}) {
  final instant = now ?? DateTime.now();
  final isWithinWindow = !allocation.startDate.isAfter(instant) &&
      !allocation.endDate.isBefore(instant);
  return allocation.isActive &&
      isWithinWindow &&
      (allocation.isForWholeClass || allocation.studentIds.contains(studentId));
}

/// Whether a current allocation produces an Assigned Books card for a student.
///
/// Title allocations only count when they still have an effective item for the
/// student. Level and free-choice allocations are intentionally treated as an
/// assignment because the normal section renders them as an actionable card.
bool hasCurrentStudentBookAssignment(
  Iterable<AllocationModel> allocations,
  String studentId, {
  DateTime? now,
}) {
  return allocations.any((allocation) {
    if (!isCurrentStudentAssignment(allocation, studentId, now: now)) {
      return false;
    }
    return allocation.type != AllocationType.byTitle ||
        allocation.effectiveAssignmentItemsForStudent(studentId).isNotEmpty;
  });
}
