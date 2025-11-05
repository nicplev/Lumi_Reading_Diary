import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../data/models/student_model.dart';
import '../data/models/class_model.dart';
import 'firebase_service.dart';

class CSVImportResult {
  final int successCount;
  final int errorCount;
  final List<String> errors;
  final List<StudentModel> createdStudents;

  CSVImportResult({
    required this.successCount,
    required this.errorCount,
    required this.errors,
    required this.createdStudents,
  });
}

class CSVRow {
  final int rowNumber;
  final String studentId;
  final String firstName;
  final String lastName;
  final String? dateOfBirth;
  final String className;
  final String? parentEmail;
  final String? readingLevel;

  CSVRow({
    required this.rowNumber,
    required this.studentId,
    required this.firstName,
    required this.lastName,
    this.dateOfBirth,
    required this.className,
    this.parentEmail,
    this.readingLevel,
  });

  List<String> validate() {
    final errors = <String>[];

    if (studentId.trim().isEmpty) {
      errors.add('Row $rowNumber: Student ID is required');
    }
    if (firstName.trim().isEmpty) {
      errors.add('Row $rowNumber: First name is required');
    }
    if (lastName.trim().isEmpty) {
      errors.add('Row $rowNumber: Last name is required');
    }
    if (className.trim().isEmpty) {
      errors.add('Row $rowNumber: Class name is required');
    }

    // Validate date of birth format if provided
    if (dateOfBirth != null && dateOfBirth!.isNotEmpty) {
      try {
        DateFormat('yyyy-MM-dd').parseStrict(dateOfBirth!);
      } catch (e) {
        errors.add('Row $rowNumber: Invalid date format (use YYYY-MM-DD)');
      }
    }

    // Validate email format if provided
    if (parentEmail != null && parentEmail!.isNotEmpty) {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (!emailRegex.hasMatch(parentEmail!)) {
        errors.add('Row $rowNumber: Invalid parent email format');
      }
    }

    return errors;
  }
}

class CSVImportService {
  final FirebaseService _firebaseService = FirebaseService.instance;

  /// Parse CSV content into rows
  Future<List<CSVRow>> parseCSV(String csvContent) async {
    // Auto-detect delimiter (tab or comma)
    final firstLine = csvContent.split('\n').first;
    final delimiter = firstLine.contains('\t') ? '\t' : ',';

    final List<List<dynamic>> rows = const CsvToListConverter().convert(
      csvContent,
      eol: '\n',
      fieldDelimiter: delimiter,
    );

    if (rows.isEmpty) {
      throw Exception('CSV file is empty');
    }

    // Check header row
    final headers = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();

    // Find column indices
    final studentIdIndex = headers.indexWhere((h) =>
      h.contains('studentid') || h.contains('student id') || h.replaceAll(' ', '').contains('studentid'));
    final firstNameIndex = headers.indexWhere((h) =>
      h.contains('firstname') || h.contains('first name') || h.replaceAll(' ', '').contains('firstname'));
    final lastNameIndex = headers.indexWhere((h) =>
      h.contains('lastname') || h.contains('last name') || h.replaceAll(' ', '').contains('lastname'));
    final dobIndex = headers.indexWhere((h) =>
      h.contains('dateofbirth') || h.contains('date of birth') || h == 'dob');
    final classNameIndex = headers.indexWhere((h) =>
      h.contains('classname') || h.contains('class name') || h == 'class' || h.replaceAll(' ', '').contains('classname'));
    final parentEmailIndex = headers.indexWhere((h) =>
      h.contains('parentemail') || h.contains('parent email') || h.contains('email'));
    final readingLevelIndex = headers.indexWhere((h) =>
      h.contains('readinglevel') || h.contains('reading level') || h == 'level');

    // Validate required columns are present
    if (studentIdIndex == -1) {
      throw Exception('Missing required column: Student ID');
    }
    if (firstNameIndex == -1) {
      throw Exception('Missing required column: First Name');
    }
    if (lastNameIndex == -1) {
      throw Exception('Missing required column: Last Name');
    }
    if (classNameIndex == -1) {
      throw Exception('Missing required column: Class Name');
    }

    // Parse data rows
    final csvRows = <CSVRow>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];

      // Skip empty rows
      if (row.every((cell) => cell.toString().trim().isEmpty)) {
        continue;
      }

      csvRows.add(CSVRow(
        rowNumber: i + 1,
        studentId: row[studentIdIndex].toString().trim(),
        firstName: row[firstNameIndex].toString().trim(),
        lastName: row[lastNameIndex].toString().trim(),
        dateOfBirth: dobIndex >= 0 && dobIndex < row.length ? row[dobIndex].toString().trim() : null,
        className: row[classNameIndex].toString().trim(),
        parentEmail: parentEmailIndex >= 0 && parentEmailIndex < row.length ? row[parentEmailIndex].toString().trim() : null,
        readingLevel: readingLevelIndex >= 0 && readingLevelIndex < row.length ? row[readingLevelIndex].toString().trim() : null,
      ));
    }

    return csvRows;
  }

  /// Validate all CSV rows
  List<String> validateRows(List<CSVRow> rows) {
    final errors = <String>[];
    final seenStudentIds = <String>{};

    for (final row in rows) {
      // Validate individual row
      errors.addAll(row.validate());

      // Check for duplicate student IDs
      if (seenStudentIds.contains(row.studentId)) {
        errors.add('Row ${row.rowNumber}: Duplicate student ID: ${row.studentId}');
      }
      seenStudentIds.add(row.studentId);
    }

    return errors;
  }

  /// Import students from CSV rows
  Future<CSVImportResult> importStudents({
    required List<CSVRow> rows,
    required String schoolId,
  }) async {
    final errors = <String>[];
    final createdStudents = <StudentModel>[];
    int successCount = 0;
    int errorCount = 0;

    try {
      // Get or create classes
      final classMap = await _getOrCreateClasses(schoolId, rows);

      // Check for existing student IDs
      final existingStudentIds = await _getExistingStudentIds(schoolId, rows);

      // Process students in batches (Firestore limit is 500 operations per batch)
      final batchSize = 400; // Leave some room for class updates
      for (int i = 0; i < rows.length; i += batchSize) {
        final batchRows = rows.skip(i).take(batchSize).toList();
        final batch = _firebaseService.firestore.batch();

        for (final row in batchRows) {
          try {
            // Skip if student ID already exists
            if (existingStudentIds.contains(row.studentId)) {
              errors.add('Row ${row.rowNumber}: Student ID already exists: ${row.studentId}');
              errorCount++;
              continue;
            }

            // Get class ID
            final classId = classMap[row.className];
            if (classId == null) {
              errors.add('Row ${row.rowNumber}: Failed to find/create class: ${row.className}');
              errorCount++;
              continue;
            }

            // Create student document reference
            final studentRef = _firebaseService.firestore
                .collection('schools')
                .doc(schoolId)
                .collection('students')
                .doc();

            // Parse date of birth
            DateTime? dob;
            if (row.dateOfBirth != null && row.dateOfBirth!.isNotEmpty) {
              try {
                dob = DateFormat('yyyy-MM-dd').parseStrict(row.dateOfBirth!);
              } catch (e) {
                // Already validated, but handle gracefully
                dob = null;
              }
            }

            // Create student data
            final studentData = {
              'studentId': row.studentId,
              'firstName': row.firstName,
              'lastName': row.lastName,
              'schoolId': schoolId,
              'classId': classId,
              'dateOfBirth': dob != null ? Timestamp.fromDate(dob) : null,
              'currentReadingLevel': row.readingLevel ?? '',
              'parentIds': <String>[],
              'isActive': true,
              'createdAt': FieldValue.serverTimestamp(),
              'enrolledAt': FieldValue.serverTimestamp(),
              'profileImageUrl': null,
              'additionalInfo': row.parentEmail != null && row.parentEmail!.isNotEmpty
                  ? {'pendingParentEmail': row.parentEmail}
                  : {},
              'levelHistory': [],
              'stats': {
                'totalMinutesRead': 0,
                'totalBooksRead': 0,
                'currentStreak': 0,
                'longestStreak': 0,
                'lastReadingDate': null,
              },
            };

            batch.set(studentRef, studentData);

            // Update class studentIds array
            final classRef = _firebaseService.firestore
                .collection('schools')
                .doc(schoolId)
                .collection('classes')
                .doc(classId);

            batch.update(classRef, {
              'studentIds': FieldValue.arrayUnion([studentRef.id]),
            });

            // Create student model for result
            final student = StudentModel(
              id: studentRef.id,
              studentId: row.studentId,
              firstName: row.firstName,
              lastName: row.lastName,
              schoolId: schoolId,
              classId: classId,
              dateOfBirth: dob,
              currentReadingLevel: row.readingLevel ?? '',
              parentIds: [],
              isActive: true,
              createdAt: DateTime.now(),
              enrolledAt: DateTime.now(),
              profileImageUrl: null,
              additionalInfo: studentData['additionalInfo'] as Map<String, dynamic>,
              levelHistory: [],
              stats: StudentStats(
                totalMinutesRead: 0,
                totalBooksRead: 0,
                currentStreak: 0,
                longestStreak: 0,
                lastReadingDate: null,
              ),
            );

            createdStudents.add(student);
            successCount++;
          } catch (e) {
            errors.add('Row ${row.rowNumber}: Error creating student - $e');
            errorCount++;
          }
        }

        // Commit batch
        await batch.commit();
      }

      return CSVImportResult(
        successCount: successCount,
        errorCount: errorCount,
        errors: errors,
        createdStudents: createdStudents,
      );
    } catch (e) {
      throw Exception('Import failed: $e');
    }
  }

  /// Get existing classes or create new ones
  Future<Map<String, String>> _getOrCreateClasses(
    String schoolId,
    List<CSVRow> rows,
  ) async {
    final classNames = rows.map((r) => r.className).toSet();
    final classMap = <String, String>{};

    // Get existing classes
    final classesSnapshot = await _firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('isActive', isEqualTo: true)
        .get();

    for (final doc in classesSnapshot.docs) {
      final classModel = ClassModel.fromFirestore(doc);
      if (classNames.contains(classModel.name)) {
        classMap[classModel.name] = classModel.id;
      }
    }

    // Create missing classes
    for (final className in classNames) {
      if (!classMap.containsKey(className)) {
        final classRef = await _firebaseService.firestore
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .add({
          'name': className,
          'schoolId': schoolId,
          'teacherId': '',
          'teacherIds': <String>[],
          'studentIds': <String>[],
          'yearLevel': _extractYearLevel(className),
          'room': null,
          'defaultMinutesTarget': 20,
          'description': 'Created during CSV import',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': 'system',
          'settings': {},
        });

        classMap[className] = classRef.id;
      }
    }

    return classMap;
  }

  /// Extract year level from class name (e.g., "Year 3" -> "Year 3", "3A" -> "Year 3")
  String? _extractYearLevel(String className) {
    final yearMatch = RegExp(r'Year\s*(\d+)', caseSensitive: false).firstMatch(className);
    if (yearMatch != null) {
      return 'Year ${yearMatch.group(1)}';
    }

    final numberMatch = RegExp(r'^\d+').firstMatch(className);
    if (numberMatch != null) {
      return 'Year ${numberMatch.group(0)}';
    }

    if (className.toLowerCase().contains('prep') || className.toLowerCase().contains('foundation')) {
      return 'Prep';
    }

    return null;
  }

  /// Get existing student IDs to avoid duplicates
  Future<Set<String>> _getExistingStudentIds(
    String schoolId,
    List<CSVRow> rows,
  ) async {
    final studentIds = rows.map((r) => r.studentId).toList();
    final existingIds = <String>{};

    // Query in batches (Firestore 'in' query limit is 30)
    for (int i = 0; i < studentIds.length; i += 30) {
      final batchIds = studentIds.skip(i).take(30).toList();

      final snapshot = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('students')
          .where('studentId', whereIn: batchIds)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['studentId'] != null) {
          existingIds.add(data['studentId'] as String);
        }
      }
    }

    return existingIds;
  }

  /// Generate CSV template
  String generateTemplate() {
    return 'Student ID,First Name,Last Name,Date of Birth,Class Name,Parent Email,Reading Level\n'
        'S12345,Emma,Wilson,2015-06-15,3A,emma.parent@example.com,Level B\n'
        'S12346,Liam,Chen,2015-03-22,3A,lchen@example.com,Level C\n'
        'S12347,Sophia,Martinez,2015-08-10,3B,sophia.parent@gmail.com,Level A';
  }
}
