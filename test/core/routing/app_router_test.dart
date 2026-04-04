import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/routing/app_router.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';

void main() {
  group('AppRouter helper methods', () {
    final teacher = UserModel(
      id: 'teacher_1',
      email: 'teacher@example.com',
      fullName: 'Test Teacher',
      role: UserRole.teacher,
      schoolId: 'school_1',
      createdAt: DateTime(2026, 1, 1),
    );

    test('getHomeRouteForRole returns correct routes', () {
      expect(AppRouter.getHomeRouteForRole(UserRole.parent), '/parent/home');
      expect(AppRouter.getHomeRouteForRole(UserRole.teacher), '/teacher/home');
      expect(
        AppRouter.getHomeRouteForRole(UserRole.schoolAdmin),
        '/admin/home',
      );
    });

    test('checkParentWebAccess allows non-parent roles', () {
      expect(AppRouter.checkParentWebAccess(UserRole.teacher), isNull);
      expect(AppRouter.checkParentWebAccess(UserRole.schoolAdmin), isNull);
    });

    test('resolveUserFromRoute prefers route extra over fallback user', () {
      final resolved = AppRouter.resolveUserFromRoute(
        extra: teacher,
        fallback: null,
      );

      expect(resolved, same(teacher));
    });

    test('resolveUserFromRoute falls back when extra is missing or invalid',
        () {
      final resolved = AppRouter.resolveUserFromRoute(
        extra: const {'unexpected': true},
        fallback: teacher,
      );

      expect(resolved, same(teacher));
    });
  });
}
