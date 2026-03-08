import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/routing/app_router.dart';
import 'package:lumi_reading_tracker/data/models/user_model.dart';

void main() {
  group('AppRouter helper methods', () {
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
  });
}
