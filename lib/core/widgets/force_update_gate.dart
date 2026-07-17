import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/providers/remote_message_provider.dart';
import '../constants/legal_links.dart';
import '../models/remote_message.dart';
import '../services/remote_message_controller.dart';
import '../services/force_update_evaluator.dart';
import 'lumi_mascot.dart';

/// Optional App Store page for the Update button on iOS (Play can be derived
/// from the package id; the App Store's numeric id can't be). Set via
/// `--dart-define=LUMI_APPSTORE_URL=https://apps.apple.com/app/id...` in
/// `.dart_define.json`; when unset the screen shows guidance instead.
const String _appStoreUrl =
    String.fromEnvironment('LUMI_APPSTORE_URL', defaultValue: '');

/// Package info resolves once. A release with an active minimum-version policy
/// enters support mode if its installed version cannot be read.
final packageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
});

String get _platformKey {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => defaultTargetPlatform.name.toLowerCase(),
  };
}

/// Blocks the whole app behind an update screen when the status worker's
/// message carries a `minAppVersion` above this build (see
/// force_update_evaluator.dart). Release ambiguity enters support mode; debug
/// builds retain fail-open ergonomics. This is the
/// safety valve that lets rules/functions changes ship once old clients can
/// be forced forward, and it finally consumes the payload fields the worker
/// has always sent.
class ForceUpdateGate extends ConsumerWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(remoteMessageProvider).value;
    final info = ref.watch(packageInfoProvider).value;
    final configState = ref.watch(remoteMessageConfigStateProvider).value;
    final configAvailable = switch (configState) {
      RemoteMessageConfigState.available => true,
      RemoteMessageConfigState.unavailable => false,
      RemoteMessageConfigState.checking || null => null,
    };
    final decision = evaluateForceUpdate(
      requireVersionConfig: kReleaseMode,
      configConfigured: isRemoteMessageConfigured,
      configAvailable: configAvailable,
      message: message,
      currentVersion: info?.version,
      platform: _platformKey,
    );
    return switch (decision) {
      ForceUpdateDecision.allow => child,
      ForceUpdateDecision.checking => const _VersionCheckScreen(),
      ForceUpdateDecision.updateRequired => _ForceUpdateScreen(
          message: message!,
          packageName: info?.packageName,
        ),
      ForceUpdateDecision.supportRequired => _VersionSupportScreen(
          endpointUnreachable: isRemoteMessageConfigured &&
              configState == RemoteMessageConfigState.unavailable,
          onRetry: isRemoteMessageConfigured
              ? () async {
                  await ref.read(remoteMessageControllerProvider)?.retry();
                }
              : null,
        ),
    };
  }
}

class _VersionCheckScreen extends StatelessWidget {
  const _VersionCheckScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFBF7F0),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Checking this version of Lumi…',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionSupportScreen extends StatefulWidget {
  const _VersionSupportScreen({
    required this.endpointUnreachable,
    this.onRetry,
  });

  final bool endpointUnreachable;
  final Future<void> Function()? onRetry;

  @override
  State<_VersionSupportScreen> createState() => _VersionSupportScreenState();
}

class _VersionSupportScreenState extends State<_VersionSupportScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    final retry = widget.onRetry;
    if (retry == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      await retry();
    } catch (_) {
      // The support screen remains in place with retry + contact options.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LumiMascot(variant: LumiVariant.teacherWhy, size: 96),
                  const SizedBox(height: 24),
                  Text(
                    'Lumi needs a quick version check',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.endpointUnreachable
                        ? 'Lumi could not reach its independent version '
                            'service. Try again or contact support if this '
                            'continues.'
                        : 'This build cannot verify that it is safe to use. '
                            'Please contact Lumi support.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (widget.onRetry != null)
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Try version check again'),
                    ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(LegalLinks.support),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Contact Lumi support'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForceUpdateScreen extends StatelessWidget {
  const _ForceUpdateScreen({required this.message, this.packageName});

  final RemoteMessage message;
  final String? packageName;

  Uri? get _storeUri {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final id = packageName;
      if (id != null && id.isNotEmpty) {
        return Uri.parse('https://play.google.com/store/apps/details?id=$id');
      }
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        _appStoreUrl.isNotEmpty) {
      return Uri.parse(_appStoreUrl);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final storeUri = _storeUri;
    final storeName = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? 'App Store'
        : 'Play Store';

    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LumiMascot(variant: LumiVariant.teacherWhy, size: 96),
                  const SizedBox(height: 24),
                  Text(
                    'Time to update Lumi',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (message.message?.isNotEmpty ?? false)
                        ? message.message!
                        : 'This version of Lumi is no longer supported. '
                            'Please update to keep reading.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (storeUri != null)
                    FilledButton.icon(
                      onPressed: () => launchUrl(
                        storeUri,
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: Text('Update on the $storeName'),
                    )
                  else
                    Column(
                      children: [
                        Text(
                          'Open the $storeName and update Lumi to continue.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(LegalLinks.support),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text('Contact Lumi support'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
