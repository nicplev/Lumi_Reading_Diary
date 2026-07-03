import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/app_icon_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';

/// Home Screen icon picker (the Lumi icon pack). iOS-only; reachable from the
/// Settings/Profile tabs. Currently dev-access gated while the pack is tested
/// in the live app — un-gate the entry points + route to release it publicly.
class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  final AppIconService _service = AppIconService();

  /// Active icon; null while the initial lookup is in flight.
  LumiAppIcon? _current;

  /// Icon id currently being applied, if any (disables further taps).
  String? _applyingId;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final icon = await _service.currentIcon();
      if (mounted) setState(() => _current = icon);
    } catch (_) {
      // Channel unavailable (non-iOS build or missing native side): show the
      // catalog anyway with the default marked active.
      if (mounted) setState(() => _current = kLumiAppIcons.first);
    }
  }

  Future<void> _select(LumiAppIcon icon) async {
    if (_applyingId != null || _current == null) return;
    if (icon.iosIconName == _current!.iosIconName) return;

    setState(() => _applyingId = icon.id);
    try {
      await _service.setIcon(icon);
      // iOS shows its own "You have changed the icon" alert on success.
      if (mounted) setState(() => _current = icon);
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Could not change the app icon: ${e.message ?? e.code}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        title: const Text('App icon'),
        backgroundColor: LumiTokens.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: LumiTokens.ink,
      ),
      body: !AppIconService.isSupportedPlatform
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(LumiTokens.space5),
                child: Text(
                  'Changing the app icon is only available on iOS.',
                  style: LumiType.body,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('DEV PREVIEW', style: LumiType.sectionLabel),
                const SizedBox(height: LumiTokens.space2),
                Text(
                  'Pick the icon Lumi wears on your Home Screen.',
                  style: LumiType.body,
                ),
                const SizedBox(height: LumiTokens.space1),
                Text(
                  'iOS shows a confirmation message when the icon changes.',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
                const SizedBox(height: LumiTokens.space4),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                  children: [
                    for (final icon in kLumiAppIcons)
                      _IconTile(
                        icon: icon,
                        selected: icon.iosIconName == _current?.iosIconName,
                        applying: icon.id == _applyingId,
                        enabled: _current != null && _applyingId == null,
                        onTap: () => _select(icon),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final LumiAppIcon icon;
  final bool selected;
  final bool applying;
  final bool enabled;
  final VoidCallback onTap;

  const _IconTile({
    required this.icon,
    required this.selected,
    required this.applying,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusLarge + 3),
                    border: Border.all(
                      color:
                          selected ? LumiTokens.green : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusLarge - 3),
                    child: Image.asset(icon.previewAsset, fit: BoxFit.cover),
                  ),
                ),
                if (icon.isDefault)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: LumiTokens.paper.withValues(alpha: 0.9),
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                      ),
                      child: Text(
                        'Default',
                        style: LumiType.caption.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: LumiTokens.ink,
                        ),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: LumiTokens.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 16, color: Colors.white),
                    ),
                  ),
                if (applying)
                  Container(
                    decoration: BoxDecoration(
                      color: LumiTokens.ink.withValues(alpha: 0.25),
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusLarge + 3),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            icon.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LumiType.caption.copyWith(
              color: selected ? LumiTokens.ink : LumiTokens.muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
