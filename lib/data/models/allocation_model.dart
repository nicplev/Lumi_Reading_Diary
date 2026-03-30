import 'package:cloud_firestore/cloud_firestore.dart';

enum AllocationCadence {
  daily,
  weekly,
  fortnightly,
  custom,
}

enum AllocationType {
  byLevel, // Level band allocation
  byTitle, // Specific book titles
  freeChoice, // Student chooses within level
}

/// Stable book-assignment item inside an allocation.
///
/// This enables per-book CRUD without relying on brittle title matching.
class AllocationBookItem {
  const AllocationBookItem({
    required this.id,
    required this.title,
    this.bookId,
    this.isbn,
    this.isDeleted = false,
    this.addedAt,
    this.addedBy,
    this.metadata,
  });

  final String id;
  final String title;
  final String? bookId;
  final String? isbn;
  final bool isDeleted;
  final DateTime? addedAt;
  final String? addedBy;
  final Map<String, dynamic>? metadata;

  String? get resolvedIsbn {
    final rawIsbn = isbn?.trim();
    if (rawIsbn != null && rawIsbn.isNotEmpty) return rawIsbn;
    final rawBookId = bookId?.trim();
    if (rawBookId != null && rawBookId.startsWith('isbn_')) {
      final parsed = rawBookId.substring(5).trim();
      return parsed.isEmpty ? null : parsed;
    }
    return null;
  }

  String get dedupeKey {
    final keyIsbn = resolvedIsbn;
    if (keyIsbn != null && keyIsbn.isNotEmpty) {
      return 'isbn:${keyIsbn.toLowerCase()}';
    }
    final keyBookId = bookId?.trim();
    if (keyBookId != null && keyBookId.isNotEmpty) {
      return 'book:$keyBookId';
    }
    final normalizedTitle = _normalizeTitle(title);
    if (normalizedTitle.isNotEmpty) return 'title:$normalizedTitle';
    return 'item:$id';
  }

  factory AllocationBookItem.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final itemId = (map['id'] as String?)?.trim();
    final rawTitle = (map['title'] as String?)?.trim() ?? '';

    return AllocationBookItem(
      id: (itemId != null && itemId.isNotEmpty)
          ? itemId
          : (fallbackId ?? 'item_${rawTitle.hashCode.abs()}'),
      title: rawTitle,
      bookId: (map['bookId'] as String?)?.trim(),
      isbn: ((map['isbnNormalized'] ?? map['isbn']) as String?)?.trim(),
      isDeleted: map['isDeleted'] == true,
      addedAt: _coerceDateTime(map['addedAt']),
      addedBy: (map['addedBy'] as String?)?.trim(),
      metadata: _coerceMap(map['metadata']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'bookId': bookId,
      'isbn': isbn,
      'isbnNormalized': isbn,
      'isDeleted': isDeleted,
      'addedAt': addedAt != null ? Timestamp.fromDate(addedAt!) : null,
      'addedBy': addedBy,
      'metadata': metadata,
    };
  }

  AllocationBookItem copyWith({
    String? id,
    String? title,
    String? bookId,
    String? isbn,
    bool? isDeleted,
    DateTime? addedAt,
    String? addedBy,
    Map<String, dynamic>? metadata,
  }) {
    return AllocationBookItem(
      id: id ?? this.id,
      title: title ?? this.title,
      bookId: bookId ?? this.bookId,
      isbn: isbn ?? this.isbn,
      isDeleted: isDeleted ?? this.isDeleted,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
      metadata: metadata ?? this.metadata,
    );
  }

  static String _normalizeTitle(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}

/// Per-student delta against a class/global allocation.
class StudentAllocationOverride {
  const StudentAllocationOverride({
    required this.studentId,
    this.removedItemIds = const <String>[],
    this.addedItems = const <AllocationBookItem>[],
    this.updatedAt,
    this.updatedBy,
    this.metadata,
  });

  final String studentId;
  final List<String> removedItemIds;
  final List<AllocationBookItem> addedItems;
  final DateTime? updatedAt;
  final String? updatedBy;
  final Map<String, dynamic>? metadata;

  List<AllocationBookItem> get activeAddedItems {
    return addedItems
        .where((item) => !item.isDeleted && item.title.trim().isNotEmpty)
        .toList();
  }

  factory StudentAllocationOverride.fromMap(
    Map<String, dynamic> map, {
    required String studentId,
  }) {
    final rawAdded = map['addedItems'];
    final parsedAdded = <AllocationBookItem>[];
    if (rawAdded is List) {
      for (var i = 0; i < rawAdded.length; i++) {
        final entry = rawAdded[i];
        if (entry is! Map) continue;
        parsedAdded.add(
          AllocationBookItem.fromMap(
            Map<String, dynamic>.from(entry),
            fallbackId: 'override_${studentId}_$i',
          ),
        );
      }
    }

    return StudentAllocationOverride(
      studentId: studentId,
      removedItemIds: ((map['removedItemIds'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(),
      addedItems: parsedAdded,
      updatedAt: _coerceDateTime(map['updatedAt']),
      updatedBy: (map['updatedBy'] as String?)?.trim(),
      metadata: _coerceMap(map['metadata']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'removedItemIds': removedItemIds,
      'addedItems': addedItems.map((item) => item.toMap()).toList(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'updatedBy': updatedBy,
      'metadata': metadata,
    };
  }

  StudentAllocationOverride copyWith({
    List<String>? removedItemIds,
    List<AllocationBookItem>? addedItems,
    DateTime? updatedAt,
    String? updatedBy,
    Map<String, dynamic>? metadata,
  }) {
    return StudentAllocationOverride(
      studentId: studentId,
      removedItemIds: removedItemIds ?? this.removedItemIds,
      addedItems: addedItems ?? this.addedItems,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      metadata: metadata ?? this.metadata,
    );
  }
}

class AllocationModel {
  const AllocationModel({
    required this.id,
    required this.schoolId,
    required this.classId,
    required this.teacherId,
    required this.studentIds,
    required this.type,
    required this.cadence,
    required this.targetMinutes,
    required this.startDate,
    required this.endDate,
    this.levelStart,
    this.levelEnd,
    this.bookIds,
    this.bookTitles,
    this.assignmentItems,
    this.studentOverrides,
    this.schemaVersion = 1,
    this.isRecurring = false,
    this.templateName,
    this.isActive = true,
    required this.createdAt,
    required this.createdBy,
    this.metadata,
  });

  final String id;
  final String schoolId;
  final String classId;
  final String teacherId;
  final List<String> studentIds; // Can be whole class or specific students
  final AllocationType type;
  final AllocationCadence cadence;
  final int targetMinutes;
  final DateTime startDate;
  final DateTime endDate;

  // For level-based allocation
  final String? levelStart;
  final String? levelEnd;

  // Legacy title-based fields (kept for compatibility)
  final List<String>? bookIds;
  final List<String>? bookTitles;

  // New normalized assignment structure for per-book CRUD.
  final List<AllocationBookItem>? assignmentItems;
  final Map<String, StudentAllocationOverride>? studentOverrides;
  final int schemaVersion;

  final bool isRecurring;
  final String? templateName; // For saving as template
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, dynamic>? metadata;

  bool get isForWholeClass => studentIds.isEmpty;

  List<AllocationBookItem> get activeAssignmentItems {
    final items = parseAssignmentItems(
      assignmentItems?.map((item) => item.toMap()).toList(),
      legacyBookTitles: bookTitles,
      legacyBookIds: bookIds,
    );
    return items
        .where((item) => !item.isDeleted && item.title.trim().isNotEmpty)
        .toList();
  }

  List<AllocationBookItem> effectiveAssignmentItemsForStudent(
      String studentId) {
    final baseItems = activeAssignmentItems;
    final overrides = studentOverrides;
    if (overrides == null || !overrides.containsKey(studentId)) {
      return baseItems;
    }

    final override = overrides[studentId]!;
    final removed = override.removedItemIds.toSet();
    final merged = baseItems
        .where((item) => !removed.contains(item.id))
        .toList(growable: true);

    final dedupeKeys = merged.map((item) => item.dedupeKey).toSet();
    for (final item in override.activeAddedItems) {
      if (removed.contains(item.id)) continue;
      if (dedupeKeys.add(item.dedupeKey)) {
        merged.add(item);
      }
    }
    return merged;
  }

  List<String>? get derivedBookTitles {
    final titles = activeAssignmentItems
        .map((item) => item.title.trim())
        .where((title) => title.isNotEmpty)
        .toList();
    return titles.isEmpty ? null : titles;
  }

  List<String>? get derivedBookIds {
    final ids = activeAssignmentItems
        .map((item) => item.bookId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    return ids.isEmpty ? null : ids;
  }

  AllocationModel syncLegacyBookFields() {
    return copyWith(
      bookTitles: derivedBookTitles,
      bookIds: derivedBookIds,
      schemaVersion: schemaVersion < 2 ? 2 : schemaVersion,
    );
  }

  factory AllocationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final parsedAssignmentItems = parseAssignmentItems(
      data['assignmentItems'],
      legacyBookTitles: data['bookTitles'] != null
          ? List<String>.from(data['bookTitles'])
          : null,
      legacyBookIds:
          data['bookIds'] != null ? List<String>.from(data['bookIds']) : null,
    );

    return AllocationModel(
      id: doc.id,
      schoolId: data['schoolId'] ?? '',
      classId: data['classId'] ?? '',
      teacherId: data['teacherId'] ?? '',
      studentIds: List<String>.from(data['studentIds'] ?? []),
      type: AllocationType.values.firstWhere(
        (e) => e.toString() == 'AllocationType.${data['type']}',
        orElse: () => AllocationType.byLevel,
      ),
      cadence: AllocationCadence.values.firstWhere(
        (e) => e.toString() == 'AllocationCadence.${data['cadence']}',
        orElse: () => AllocationCadence.weekly,
      ),
      targetMinutes: data['targetMinutes'] ?? 20,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      levelStart: data['levelStart'],
      levelEnd: data['levelEnd'],
      bookIds:
          data['bookIds'] != null ? List<String>.from(data['bookIds']) : null,
      bookTitles: data['bookTitles'] != null
          ? List<String>.from(data['bookTitles'])
          : null,
      assignmentItems: parsedAssignmentItems,
      studentOverrides: _parseStudentOverrides(data['studentOverrides']),
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ??
          (parsedAssignmentItems.isNotEmpty ? 2 : 1),
      isRecurring: data['isRecurring'] ?? false,
      templateName: data['templateName'],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      metadata: _coerceMap(data['metadata']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'schoolId': schoolId,
      'classId': classId,
      'teacherId': teacherId,
      'studentIds': studentIds,
      'type': type.toString().split('.').last,
      'cadence': cadence.toString().split('.').last,
      'targetMinutes': targetMinutes,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'levelStart': levelStart,
      'levelEnd': levelEnd,
      'bookIds': bookIds,
      'bookTitles': bookTitles,
      'assignmentItems': assignmentItems?.map((item) => item.toMap()).toList(),
      'studentOverrides': studentOverrides?.map(
        (studentId, override) => MapEntry(studentId, override.toMap()),
      ),
      'schemaVersion': schemaVersion,
      'isRecurring': isRecurring,
      'templateName': templateName,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'metadata': metadata,
    };
  }

  AllocationModel copyWith({
    String? id,
    String? schoolId,
    String? classId,
    String? teacherId,
    List<String>? studentIds,
    AllocationType? type,
    AllocationCadence? cadence,
    int? targetMinutes,
    DateTime? startDate,
    DateTime? endDate,
    String? levelStart,
    String? levelEnd,
    List<String>? bookIds,
    List<String>? bookTitles,
    List<AllocationBookItem>? assignmentItems,
    Map<String, StudentAllocationOverride>? studentOverrides,
    int? schemaVersion,
    bool? isRecurring,
    String? templateName,
    bool? isActive,
    DateTime? createdAt,
    String? createdBy,
    Map<String, dynamic>? metadata,
  }) {
    return AllocationModel(
      id: id ?? this.id,
      schoolId: schoolId ?? this.schoolId,
      classId: classId ?? this.classId,
      teacherId: teacherId ?? this.teacherId,
      studentIds: studentIds ?? this.studentIds,
      type: type ?? this.type,
      cadence: cadence ?? this.cadence,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      levelStart: levelStart ?? this.levelStart,
      levelEnd: levelEnd ?? this.levelEnd,
      bookIds: bookIds ?? this.bookIds,
      bookTitles: bookTitles ?? this.bookTitles,
      assignmentItems: assignmentItems ?? this.assignmentItems,
      studentOverrides: studentOverrides ?? this.studentOverrides,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      isRecurring: isRecurring ?? this.isRecurring,
      templateName: templateName ?? this.templateName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      metadata: metadata ?? this.metadata,
    );
  }

  static List<AllocationBookItem> parseAssignmentItems(
    dynamic raw, {
    List<String>? legacyBookTitles,
    List<String>? legacyBookIds,
  }) {
    final parsed = <AllocationBookItem>[];

    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final entry = raw[i];
        if (entry is! Map) continue;
        parsed.add(
          AllocationBookItem.fromMap(
            Map<String, dynamic>.from(entry),
            fallbackId: 'item_$i',
          ),
        );
      }
    }

    if (parsed.isNotEmpty) return parsed;
    return _legacyAssignmentItems(
      legacyBookTitles: legacyBookTitles,
      legacyBookIds: legacyBookIds,
    );
  }

  static Map<String, StudentAllocationOverride>? _parseStudentOverrides(
    dynamic raw,
  ) {
    if (raw is! Map) return null;
    final parsed = <String, StudentAllocationOverride>{};
    raw.forEach((key, value) {
      final studentId = key.toString().trim();
      if (studentId.isEmpty || value is! Map) return;
      parsed[studentId] = StudentAllocationOverride.fromMap(
        Map<String, dynamic>.from(value),
        studentId: studentId,
      );
    });
    return parsed.isEmpty ? null : parsed;
  }

  static List<AllocationBookItem> _legacyAssignmentItems({
    List<String>? legacyBookTitles,
    List<String>? legacyBookIds,
  }) {
    final titles = legacyBookTitles ?? const <String>[];
    final ids = legacyBookIds ?? const <String>[];
    final parsed = <AllocationBookItem>[];

    for (var i = 0; i < titles.length; i++) {
      final rawTitle = titles[i].trim();
      if (rawTitle.isEmpty) continue;

      final rawBookId =
          i < ids.length ? ids[i].trim() : null; // legacy positional pairing
      final resolvedBookId =
          (rawBookId == null || rawBookId.isEmpty) ? null : rawBookId;
      final resolvedIsbn = _isbnFromBookId(resolvedBookId);
      parsed.add(
        AllocationBookItem(
          id: _legacyItemId(
            index: i,
            title: rawTitle,
            bookId: resolvedBookId,
          ),
          title: rawTitle,
          bookId: resolvedBookId,
          isbn: resolvedIsbn,
        ),
      );
    }

    for (var i = titles.length; i < ids.length; i++) {
      final rawBookId = ids[i].trim();
      if (rawBookId.isEmpty) continue;
      final resolvedIsbn = _isbnFromBookId(rawBookId);
      parsed.add(
        AllocationBookItem(
          id: _legacyItemId(
            index: i,
            title: 'Unknown Book',
            bookId: rawBookId,
          ),
          title: resolvedIsbn != null
              ? 'Unknown Book (ISBN $resolvedIsbn)'
              : 'Unknown Book',
          bookId: rawBookId,
          isbn: resolvedIsbn,
        ),
      );
    }

    return parsed;
  }

  static String _legacyItemId({
    required int index,
    required String title,
    String? bookId,
  }) {
    final slug = _slugify(title);
    final idPart = (bookId != null && bookId.isNotEmpty) ? bookId : slug;
    return 'legacy_${index}_$idPart';
  }

  static String _slugify(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return normalized.isEmpty ? 'book' : normalized;
  }

  static String? _isbnFromBookId(String? bookId) {
    if (bookId == null || bookId.isEmpty) return null;
    final trimmed = bookId.trim();
    if (!trimmed.startsWith('isbn_')) return null;
    final isbn = trimmed.substring(5).trim();
    return isbn.isEmpty ? null : isbn;
  }
}

DateTime? _coerceDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic>? _coerceMap(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}
