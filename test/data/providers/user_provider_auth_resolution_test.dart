import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/providers/user_provider.dart';

void main() {
  group('resolveUserProviderUid', () {
    test('uses the current Firebase UID while the auth stream starts', () {
      expect(
        resolveUserProviderUid(
          const AsyncLoading<String?>(),
          'current-user',
        ),
        'current-user',
      );
    });

    test('an emitted signed-out state overrides a stale synchronous user', () {
      expect(
        resolveUserProviderUid(
          const AsyncData<String?>(null),
          'stale-user',
        ),
        isNull,
      );
    });

    test('uses the UID emitted by the auth stream once available', () {
      expect(
        resolveUserProviderUid(
          const AsyncData<String?>('stream-user'),
          'current-user',
        ),
        'stream-user',
      );
    });

    test('keeps a verified current user during a transient stream error', () {
      expect(
        resolveUserProviderUid(
          AsyncError<String?>(StateError('transient'), StackTrace.empty),
          'current-user',
        ),
        'current-user',
      );
    });
  });
}
