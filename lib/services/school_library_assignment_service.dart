import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/allocation_model.dart';
import '../data/models/book_model.dart';
import '../data/models/student_model.dart';
import 'book_lookup_service.dart';

/// Staff-only derived assignment visibility for the school library.
///
/// This service intentionally keeps "currently assigned" state out of the
/// shared book documents so parent-safe book metadata stays separate from
/// staff-only assignment visibility.
class SchoolLibraryAssignmentService {
  SchoolLibraryAssignmentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _allocationsRef(String schoolId) =>
      _firestore.collection('schools').doc(schoolId).collection('allocations');

  CollectionReference<Map<String, dynamic>> _studentsRef(String schoolId) =>
      _firestore.collection('schools').doc(schoolId).collection('students');

  Stream<LibraryAssignmentSnapshot> summaryStream(String schoolId) {
    final scopedSchoolId = schoolId.trim();
    if (scopedSchoolId.isEmpty) {
      return Stream.value(const LibraryAssignmentSnapshot());
    }

    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        allocationsSubscription;
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
        studentsSubscription;

    final controller = StreamController<LibraryAssignmentSnapshot>();
    QuerySnapshot<Map<String, dynamic>>? latestAllocations;
    QuerySnapshot<Map<String, dynamic>>? latestStudents;
    var allocationsSettled = false;
    var studentsSettled = false;

    void emitIfReady() {
      if (!allocationsSettled ||
          !studentsSettled ||
          latestAllocations == null ||
          latestStudents == null ||
          controller.isClosed) {
        return;
      }

      controller.add(
        _buildSnapshot(
          allocationsSnapshot: latestAllocations!,
          studentsSnapshot: latestStudents!,
        ),
      );
    }

    controller.onListen = () {
      allocationsSubscription = _allocationsRef(scopedSchoolId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen(
        (snapshot) {
          latestAllocations = snapshot;
          allocationsSettled = true;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          allocationsSettled = true;
          latestAllocations = null;
          debugPrint(
            'SchoolLibraryAssignmentService: allocations stream failed for '
            '$scopedSchoolId: $error',
          );
          if (!controller.isClosed) {
            controller.add(const LibraryAssignmentSnapshot());
          }
        },
      );

      studentsSubscription = _studentsRef(scopedSchoolId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen(
        (snapshot) {
          latestStudents = snapshot;
          studentsSettled = true;
          emitIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          studentsSettled = true;
          latestStudents = null;
          debugPrint(
            'SchoolLibraryAssignmentService: students stream failed for '
            '$scopedSchoolId: $error',
          );
          if (!controller.isClosed) {
            controller.add(const LibraryAssignmentSnapshot());
          }
        },
      );
    };

    controller.onCancel = () async {
      await allocationsSubscription.cancel();
      await studentsSubscription.cancel();
    };

    return controller.stream;
  }

  LibraryAssignmentSnapshot _buildSnapshot({
    required QuerySnapshot<Map<String, dynamic>> allocationsSnapshot,
    required QuerySnapshot<Map<String, dynamic>> studentsSnapshot,
  }) {
    final now = DateTime.now();
    final activeStudentIds = <String>{};
    final studentIdsByClassId = <String, Set<String>>{};

    for (final doc in studentsSnapshot.docs) {
      try {
        final student = StudentModel.fromFirestore(doc);
        if (!student.isActive) continue;
        activeStudentIds.add(student.id);
        studentIdsByClassId
            .putIfAbsent(student.classId, () => <String>{})
            .add(student.id);
      } catch (error) {
        debugPrint(
          'SchoolLibraryAssignmentService: skipping malformed student '
          '${doc.id}: $error',
        );
      }
    }

    final studentIdsByBookId = <String, Set<String>>{};
    final studentIdsByIsbn = <String, Set<String>>{};
    final studentIdsByNormalizedTitle = <String, Set<String>>{};

    for (final doc in allocationsSnapshot.docs) {
      try {
        final allocation = AllocationModel.fromFirestore(doc);
        if (!allocation.isActive) continue;

        final withinWindow = !allocation.startDate.isAfter(now) &&
            !allocation.endDate.isBefore(now);
        if (!withinWindow || allocation.type != AllocationType.byTitle) {
          continue;
        }

        final applicableStudentIds = allocation.isForWholeClass
            ? (studentIdsByClassId[allocation.classId] ?? const <String>{})
            : allocation.studentIds
                .where((studentId) => activeStudentIds.contains(studentId))
                .toSet();

        for (final studentId in applicableStudentIds) {
          final items =
              allocation.effectiveAssignmentItemsForStudent(studentId);
          for (final item in items) {
            final bookId = item.bookId?.trim();
            if (bookId != null && bookId.isNotEmpty) {
              studentIdsByBookId
                  .putIfAbsent(bookId, () => <String>{})
                  .add(studentId);
            }

            final isbn = item.resolvedIsbn?.trim();
            if (isbn != null && isbn.isNotEmpty) {
              studentIdsByIsbn
                  .putIfAbsent(isbn, () => <String>{})
                  .add(studentId);
            }

            final title = item.title.trim();
            if (title.isNotEmpty) {
              final normalizedTitle = BookLookupService.normalizeTitle(title);
              if (normalizedTitle.isNotEmpty) {
                studentIdsByNormalizedTitle
                    .putIfAbsent(normalizedTitle, () => <String>{})
                    .add(studentId);
              }
            }
          }
        }
      } catch (error) {
        debugPrint(
          'SchoolLibraryAssignmentService: skipping malformed allocation '
          '${doc.id}: $error',
        );
      }
    }

    return LibraryAssignmentSnapshot(
      studentIdsByBookId: studentIdsByBookId,
      studentIdsByIsbn: studentIdsByIsbn,
      studentIdsByNormalizedTitle: studentIdsByNormalizedTitle,
    );
  }
}

class LibraryAssignmentSnapshot {
  const LibraryAssignmentSnapshot({
    this.studentIdsByBookId = const <String, Set<String>>{},
    this.studentIdsByIsbn = const <String, Set<String>>{},
    this.studentIdsByNormalizedTitle = const <String, Set<String>>{},
  });

  final Map<String, Set<String>> studentIdsByBookId;
  final Map<String, Set<String>> studentIdsByIsbn;
  final Map<String, Set<String>> studentIdsByNormalizedTitle;

  int currentAssignedCountForBook(BookModel book) {
    final studentIds = <String>{};

    final bookId = book.id.trim();
    if (bookId.isNotEmpty) {
      studentIds.addAll(studentIdsByBookId[bookId] ?? const <String>{});
    }

    final isbn = book.isbn?.trim();
    if (isbn != null && isbn.isNotEmpty) {
      studentIds.addAll(studentIdsByIsbn[isbn] ?? const <String>{});
      studentIds.addAll(
        studentIdsByBookId['isbn_$isbn'] ?? const <String>{},
      );
    }

    final normalizedTitle = BookLookupService.normalizeTitle(book.title);
    if (normalizedTitle.isNotEmpty) {
      studentIds.addAll(
        studentIdsByNormalizedTitle[normalizedTitle] ?? const <String>{},
      );
    }

    return studentIds.length;
  }
}
