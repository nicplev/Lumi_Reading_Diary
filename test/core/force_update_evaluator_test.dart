import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/models/remote_message.dart';
import 'package:lumi_reading_tracker/core/services/force_update_evaluator.dart';

RemoteMessage msg({String? minAppVersion, List<String>? platforms}) {
  return RemoteMessage(
    version: 1,
    id: 'update',
    message: 'Please update Lumi.',
    severity: RemoteMessageSeverity.critical,
    dismissible: false,
    fetchedAt: DateTime(2026, 7, 8),
    minAppVersion: minAppVersion,
    platforms: platforms,
  );
}

void main() {
  group('isVersionBelow', () {
    test('numeric segment comparison, not lexicographic', () {
      expect(isVersionBelow('1.2.3', '1.2.10'), isTrue); // 3 < 10
      expect(isVersionBelow('1.2.10', '1.2.3'), isFalse);
      expect(isVersionBelow('1.9.0', '1.10.0'), isTrue);
    });

    test('missing segments count as zero', () {
      expect(isVersionBelow('1.2', '1.2.0'), isFalse); // equal
      expect(isVersionBelow('1.2', '1.2.1'), isTrue);
      expect(isVersionBelow('2', '1.9.9'), isFalse);
    });

    test('build metadata and prerelease suffixes are ignored', () {
      expect(isVersionBelow('1.2.3+45', '1.3.0'), isTrue);
      expect(isVersionBelow('1.3.0-beta', '1.3.0'), isFalse); // equal core
    });

    test('garbage fails open (never blocks)', () {
      expect(isVersionBelow('abc', '1.0.0'), isFalse);
      expect(isVersionBelow('1.0.0', 'not-a-version'), isFalse);
      expect(isVersionBelow('', '1.0.0'), isFalse);
    });
  });

  group('shouldForceUpdate', () {
    test('blocks an older build', () {
      expect(
        shouldForceUpdate(
            message: msg(minAppVersion: '2.0.0'),
            currentVersion: '1.9.0',
            platform: 'ios'),
        isTrue,
      );
    });

    test('never blocks an up-to-date or newer build', () {
      expect(
        shouldForceUpdate(
            message: msg(minAppVersion: '2.0.0'),
            currentVersion: '2.0.0',
            platform: 'ios'),
        isFalse,
      );
      expect(
        shouldForceUpdate(
            message: msg(minAppVersion: '2.0.0'),
            currentVersion: '2.1.0',
            platform: 'android'),
        isFalse,
      );
    });

    test('no minAppVersion → never blocks (plain banner messages)', () {
      expect(
        shouldForceUpdate(
            message: msg(), currentVersion: '0.0.1', platform: 'ios'),
        isFalse,
      );
    });

    test('platform scoping: only listed platforms block', () {
      final m = msg(minAppVersion: '2.0.0', platforms: ['ios']);
      expect(
        shouldForceUpdate(message: m, currentVersion: '1.0.0', platform: 'ios'),
        isTrue,
      );
      expect(
        shouldForceUpdate(
            message: m, currentVersion: '1.0.0', platform: 'android'),
        isFalse,
      );
      // Case-insensitive matching.
      final upper = msg(minAppVersion: '2.0.0', platforms: ['iOS']);
      expect(
        shouldForceUpdate(
            message: upper, currentVersion: '1.0.0', platform: 'ios'),
        isTrue,
      );
    });

    test('empty platforms list applies everywhere', () {
      final m = msg(minAppVersion: '2.0.0', platforms: []);
      expect(
        shouldForceUpdate(
            message: m, currentVersion: '1.0.0', platform: 'android'),
        isTrue,
      );
    });

    test('unknown current version fails open', () {
      expect(
        shouldForceUpdate(
            message: msg(minAppVersion: '2.0.0'),
            currentVersion: null,
            platform: 'ios'),
        isFalse,
      );
    });

    test('null message fails open', () {
      expect(
        shouldForceUpdate(
            message: null, currentVersion: '1.0.0', platform: 'ios'),
        isFalse,
      );
    });
  });

  group('evaluateForceUpdate', () {
    ForceUpdateDecision decide({
      bool required = true,
      bool configured = true,
      bool? available = true,
      RemoteMessage? message,
      String? version = '1.0.0',
      String platform = 'ios',
    }) {
      return evaluateForceUpdate(
        requireVersionConfig: required,
        configConfigured: configured,
        configAvailable: available,
        message: message,
        currentVersion: version,
        platform: platform,
      );
    }

    test('release enters support mode when version config is missing', () {
      expect(
        decide(configured: false),
        ForceUpdateDecision.supportRequired,
      );
      expect(
        decide(available: false),
        ForceUpdateDecision.supportRequired,
      );
    });

    test('release continues during a confirmed transient transport failure',
        () {
      expect(
        evaluateForceUpdate(
          requireVersionConfig: true,
          configConfigured: true,
          configAvailable: false,
          transientConfigFailure: true,
          message: null,
          currentVersion: '1.0.0',
          platform: 'ios',
        ),
        ForceUpdateDecision.allow,
      );
    });

    test('invalid configuration remains blocked', () {
      expect(
        evaluateForceUpdate(
          requireVersionConfig: true,
          configConfigured: true,
          configAvailable: false,
          message: null,
          currentVersion: '1.0.0',
          platform: 'ios',
        ),
        ForceUpdateDecision.supportRequired,
      );
    });

    test('release waits while the first version check is pending', () {
      expect(decide(available: null), ForceUpdateDecision.checking);
    });

    test('valid empty policy permits the app', () {
      expect(decide(message: msg()), ForceUpdateDecision.allow);
    });

    test('older build requires update', () {
      expect(
        decide(message: msg(minAppVersion: '2.0.0')),
        ForceUpdateDecision.updateRequired,
      );
    });

    test('malformed policy or unknown installed version enters support mode',
        () {
      expect(
        decide(message: msg(minAppVersion: 'broken')),
        ForceUpdateDecision.supportRequired,
      );
      expect(
        decide(message: msg(minAppVersion: '2.0.0'), version: null),
        ForceUpdateDecision.supportRequired,
      );
    });

    test('a policy for another platform permits the app', () {
      expect(
        decide(
          message: msg(minAppVersion: '2.0.0', platforms: ['android']),
        ),
        ForceUpdateDecision.allow,
      );
    });

    test('non-release ambiguity retains fail-open developer behaviour', () {
      expect(
        decide(
          required: false,
          configured: false,
          available: false,
          message: null,
        ),
        ForceUpdateDecision.allow,
      );
    });
  });
}
