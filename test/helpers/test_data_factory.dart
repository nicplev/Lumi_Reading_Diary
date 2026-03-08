import 'package:lumi_reading_tracker/data/models/user_model.dart';
import 'package:lumi_reading_tracker/data/models/student_model.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';
import 'package:lumi_reading_tracker/data/models/book_model.dart';

/// Factory methods for creating test instances of all data models.
/// Use these in tests to avoid boilerplate constructor calls.
class TestDataFactory {
  static final DateTime _now = DateTime(2026, 2, 22, 10, 0, 0);

  // ─── Users ───────────────────────────────────────────────

  static UserModel parentUser({
    String id = 'parent-1',
    String email = 'parent@test.com',
    String fullName = 'Test Parent',
    String? schoolId = 'school-1',
    List<String> linkedChildren = const ['student-1'],
  }) {
    return UserModel(
      id: id,
      email: email,
      fullName: fullName,
      role: UserRole.parent,
      schoolId: schoolId,
      linkedChildren: linkedChildren,
      createdAt: _now,
    );
  }

  static UserModel teacherUser({
    String id = 'teacher-1',
    String email = 'teacher@test.com',
    String fullName = 'Test Teacher',
    String? schoolId = 'school-1',
    List<String> classIds = const ['class-1'],
  }) {
    return UserModel(
      id: id,
      email: email,
      fullName: fullName,
      role: UserRole.teacher,
      schoolId: schoolId,
      classIds: classIds,
      createdAt: _now,
    );
  }

  static UserModel adminUser({
    String id = 'admin-1',
    String email = 'admin@test.com',
    String fullName = 'Test Admin',
    String? schoolId = 'school-1',
  }) {
    return UserModel(
      id: id,
      email: email,
      fullName: fullName,
      role: UserRole.schoolAdmin,
      schoolId: schoolId,
      createdAt: _now,
    );
  }

  // ─── Students ────────────────────────────────────────────

  static StudentModel student({
    String id = 'student-1',
    String firstName = 'Test',
    String lastName = 'Student',
    String schoolId = 'school-1',
    String classId = 'class-1',
    List<String> parentIds = const ['parent-1'],
    String? currentReadingLevel = 'C',
    StudentStats? stats,
  }) {
    return StudentModel(
      id: id,
      firstName: firstName,
      lastName: lastName,
      schoolId: schoolId,
      classId: classId,
      parentIds: parentIds,
      currentReadingLevel: currentReadingLevel,
      createdAt: _now,
      stats: stats ?? studentStats(),
    );
  }

  static StudentStats studentStats({
    int totalMinutesRead = 600,
    int totalBooksRead = 12,
    int currentStreak = 5,
    int longestStreak = 14,
    int totalReadingDays = 48,
    double averageMinutesPerDay = 20.0,
    DateTime? lastReadingDate,
  }) {
    return StudentStats(
      totalMinutesRead: totalMinutesRead,
      totalBooksRead: totalBooksRead,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalReadingDays: totalReadingDays,
      averageMinutesPerDay: averageMinutesPerDay,
      lastReadingDate: lastReadingDate ?? _now.subtract(const Duration(days: 1)),
    );
  }

  // ─── Reading Logs ───────────────────────────────────────

  static ReadingLogModel readingLog({
    String id = 'log-1',
    String studentId = 'student-1',
    String parentId = 'parent-1',
    String schoolId = 'school-1',
    String classId = 'class-1',
    DateTime? date,
    int minutesRead = 20,
    int targetMinutes = 20,
    LogStatus status = LogStatus.completed,
    List<String> bookTitles = const ['The Cat in the Hat'],
    String? notes,
    bool isOfflineCreated = false,
    DateTime? createdAt,
  }) {
    return ReadingLogModel(
      id: id,
      studentId: studentId,
      parentId: parentId,
      schoolId: schoolId,
      classId: classId,
      date: date ?? _now,
      minutesRead: minutesRead,
      targetMinutes: targetMinutes,
      status: status,
      bookTitles: bookTitles,
      notes: notes,
      isOfflineCreated: isOfflineCreated,
      createdAt: createdAt ?? _now,
    );
  }

  // ─── Books ──────────────────────────────────────────────

  static BookModel book({
    String id = 'book-1',
    String title = 'The Cat in the Hat',
    String? author = 'Dr. Seuss',
    String? readingLevel = 'C',
    List<String> genres = const ['Fiction'],
    DateTime? createdAt,
  }) {
    return BookModel(
      id: id,
      title: title,
      author: author,
      readingLevel: readingLevel,
      genres: genres,
      createdAt: createdAt ?? _now,
    );
  }
}
