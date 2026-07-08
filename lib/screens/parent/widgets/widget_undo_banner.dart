import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_borders.dart';
import '../../../core/theme/lumi_spacing.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../services/widget_data_service.dart';

/// Legacy in-app "you can still undo" banner for older widget builds.
///
/// Current widget taps deep-link into the normal logging flow and do not create
/// commits directly. This remains so any recently-created records from a
/// previous build can still be undone, dismissed, or expired cleanly.
///
/// Renders nothing while no recent widget commit is in window — safe to drop
/// into the parent layout unconditionally.
class WidgetUndoBanner extends ConsumerStatefulWidget {
  const WidgetUndoBanner({super.key});

  @override
  ConsumerState<WidgetUndoBanner> createState() => _WidgetUndoBannerState();
}

class _WidgetUndoBannerState extends ConsumerState<WidgetUndoBanner> {
  List<WidgetCommitRecord> _commits = const [];
  StreamSubscription<void>? _sub;
  Timer? _expiryTicker;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = WidgetDataService.instance.recentCommitsChanges.listen((_) {
      _refresh();
    });
    // Re-check expiry periodically so the banner self-dismisses when the
    // 5-minute window closes without any user input.
    _expiryTicker =
        Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _expiryTicker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final commits = await WidgetDataService.instance.recentCommits();
    if (!mounted) return;
    setState(() => _commits = commits);
  }

  Future<void> _onUndo(WidgetCommitRecord commit) async {
    try {
      await WidgetDataService.instance.undoCommit(commit);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Undone — ${commit.firstName}'s log removed."),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't undo — please try again."),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _onDismiss(WidgetCommitRecord commit) async {
    await WidgetDataService.instance.dismissCommit(commit);
  }

  @override
  Widget build(BuildContext context) {
    if (_commits.isEmpty) return const SizedBox.shrink();
    // Surface only the most recent commit — multi-child households logging
    // two kids in quick succession will still see them one at a time.
    final commit = _commits.first;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiSpacing.s,
        vertical: LumiSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LumiSpacing.m,
          LumiSpacing.s,
          LumiSpacing.s,
          LumiSpacing.s,
        ),
        decoration: BoxDecoration(
          color: AppColors.offWhite,
          borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
          border: Border.all(
            color: AppColors.charcoal.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.charcoal.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 20,
              color: AppColors.rosePink,
            ),
            const SizedBox(width: LumiSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Logged reading for ${commit.firstName}",
                    style: LumiTextStyles.bodyMedium().copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _agoLabel(commit.committedAt),
                    style: LumiTextStyles.caption(
                      color: AppColors.charcoal.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _onUndo(commit),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.rosePink,
                padding: const EdgeInsets.symmetric(
                  horizontal: LumiSpacing.s,
                  vertical: LumiSpacing.xxs,
                ),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                "Undo",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () => _onDismiss(commit),
              icon: Icon(
                Icons.close,
                size: 18,
                color: AppColors.charcoal.withValues(alpha: 0.45),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              tooltip: "Dismiss",
            ),
          ],
        ),
      ),
    );
  }

  String _agoLabel(DateTime committedAt) {
    final diff = DateTime.now().difference(committedAt);
    if (diff.inSeconds < 30) return "Just now";
    if (diff.inMinutes < 1) return "Less than a minute ago";
    if (diff.inMinutes == 1) return "1 minute ago";
    return "${diff.inMinutes} minutes ago";
  }
}
