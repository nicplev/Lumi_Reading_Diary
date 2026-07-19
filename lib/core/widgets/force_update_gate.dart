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
import '../theme/lumi_spacing.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';

const String versionGateArtwork = 'assets/UI Lumi/lumi welcome.png';

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
/// force_update_evaluator.dart). Invalid release configuration enters support
/// mode; confirmed transient transport failures retry without blocking. Debug
/// builds retain fail-open ergonomics. This is the
/// safety valve that lets rules/functions changes ship once old clients can
/// be forced forward, and it finally consumes the payload fields the worker
/// has always sent.
class ForceUpdateGate extends ConsumerWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageState = ref.watch(remoteMessageProvider);
    final packageInfoState = ref.watch(packageInfoProvider);
    final message = messageState.value;
    final info = packageInfoState.value;
    final configState = ref.watch(remoteMessageConfigStateProvider).value;
    final transientConfigFailure =
        configState == RemoteMessageConfigState.temporarilyUnavailable;
    final configAvailable = switch (configState) {
      RemoteMessageConfigState.available => true,
      RemoteMessageConfigState.temporarilyUnavailable ||
      RemoteMessageConfigState.unavailable =>
        false,
      RemoteMessageConfigState.checking || null => null,
    };
    // Stream/Future providers emit on separate microtasks. Do not flash the
    // support screen if the policy or package metadata is simply warming up.
    final providerWarmup =
        configState == RemoteMessageConfigState.available && message == null ||
            !transientConfigFailure && packageInfoState.isLoading;
    final decision = providerWarmup
        ? ForceUpdateDecision.checking
        : evaluateForceUpdate(
            requireVersionConfig: kReleaseMode,
            configConfigured: isRemoteMessageConfigured,
            configAvailable: configAvailable,
            transientConfigFailure: transientConfigFailure,
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
    return const VersionGateLayout(
      title: 'Checking this version of Lumi…',
      message:
          'Lumi is making sure this build can safely connect to your school.',
      actions: Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            color: LumiTokens.red,
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }
}

class _VersionSupportScreen extends StatefulWidget {
  const _VersionSupportScreen({
    this.onRetry,
  });

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
    return VersionGateLayout(
      title: 'Lumi needs a quick version check',
      message:
          'This build could not verify its version settings. Try again, or contact Lumi support if this continues.',
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onRetry != null) ...[
            FilledButton.icon(
              onPressed: _retrying ? null : _retry,
              style: _primaryButtonStyle(),
              icon: _retrying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        color: LumiTokens.paper,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _retrying ? 'Checking again…' : 'Try version check again',
                style: LumiType.button,
              ),
            ),
            LumiGap.s,
          ],
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(LegalLinks.support),
              mode: LaunchMode.externalApplication,
            ),
            style: _secondaryButtonStyle(),
            icon: const Icon(Icons.support_agent_rounded),
            label: Text(
              'Contact Lumi support',
              style: LumiType.button.copyWith(color: LumiTokens.ink),
            ),
          ),
        ],
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

    return VersionGateLayout(
      title: 'Time to update Lumi',
      message: (message.message?.isNotEmpty ?? false)
          ? message.message!
          : 'This version of Lumi is no longer supported. Please update to keep reading.',
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (storeUri != null)
            FilledButton.icon(
              onPressed: () => launchUrl(
                storeUri,
                mode: LaunchMode.externalApplication,
              ),
              style: _primaryButtonStyle(),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: Text(
                'Update on the $storeName',
                style: LumiType.button,
              ),
            )
          else ...[
            Container(
              padding: LumiPadding.allS,
              decoration: BoxDecoration(
                color: LumiTokens.tintYellow.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                border: Border.all(color: LumiTokens.tintYellow),
              ),
              child: Text(
                'Open the $storeName and update Lumi to continue.',
                style: LumiType.body.copyWith(
                  color: LumiTokens.ink,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            LumiGap.s,
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(LegalLinks.support),
                mode: LaunchMode.externalApplication,
              ),
              style: _secondaryButtonStyle(),
              icon: const Icon(Icons.support_agent_rounded),
              label: Text(
                'Contact Lumi support',
                style: LumiType.button.copyWith(color: LumiTokens.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared presentation for every blocking version state. The policy decision
/// remains outside this widget so a visual change cannot weaken the gate.
@visibleForTesting
class VersionGateLayout extends StatelessWidget {
  const VersionGateLayout({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
  });

  final String title;
  final String message;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: LumiPadding.allM,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                width: double.infinity,
                padding: LumiPadding.allL,
                decoration: BoxDecoration(
                  color: LumiTokens.paper,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
                  border: Border.all(color: LumiTokens.rule),
                  boxShadow: LumiTokens.shadowCard,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      versionGateArtwork,
                      height: 190,
                      fit: BoxFit.contain,
                      semanticLabel: 'Lumi welcome illustration',
                    ),
                    LumiGap.m,
                    Text(title,
                        style: LumiType.heading, textAlign: TextAlign.center),
                    LumiGap.s,
                    Text(
                      message,
                      style: LumiType.body.copyWith(color: LumiTokens.muted),
                      textAlign: TextAlign.center,
                    ),
                    LumiGap.l,
                    SizedBox(width: double.infinity, child: actions),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      backgroundColor: LumiTokens.red,
      foregroundColor: LumiTokens.paper,
      disabledBackgroundColor: LumiTokens.tintRed,
      disabledForegroundColor: LumiTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
    );

ButtonStyle _secondaryButtonStyle() => OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      foregroundColor: LumiTokens.ink,
      side: const BorderSide(color: LumiTokens.rule, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
    );
