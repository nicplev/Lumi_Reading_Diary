import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/teacher_device_book_cache_service.dart';

/// Singleton provider for the teacher device book cache service.
final teacherDeviceBookCacheServiceProvider =
    Provider<TeacherDeviceBookCacheService>((ref) {
  return TeacherDeviceBookCacheService.instance;
});
