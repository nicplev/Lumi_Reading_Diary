import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Pagination affordance for the parent's bookshelf.
///
/// It belongs after the book grid so loading older sessions feels like
/// continuing the shelf rather than configuring it.
class BookshelfHistoryFooter extends StatelessWidget {
  const BookshelfHistoryFooter({
    super.key,
    required this.loadedSessionCount,
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onLoadMore,
    required this.bottomClearance,
  });

  final int loadedSessionCount;
  final bool hasMore;
  final bool loading;
  final Object? error;
  final VoidCallback onLoadMore;
  final double bottomClearance;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        LumiTokens.space4,
        LumiTokens.space5,
        LumiTokens.space4,
        bottomClearance,
      ),
      child: hasMore || hasError
          ? Container(
              padding: const EdgeInsets.all(LumiTokens.space4),
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                border: Border.all(color: LumiTokens.rule),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: LumiTokens.tintYellow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasError
                              ? Icons.refresh_rounded
                              : Icons.history_rounded,
                          size: 20,
                          color: LumiTokens.ink,
                        ),
                      ),
                      const SizedBox(width: LumiTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasError
                                  ? "Older history didn't load"
                                  : 'More books may be waiting',
                              style: LumiType.body.copyWith(
                                color: LumiTokens.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: LumiTokens.space1),
                            Text(
                              hasError
                                  ? 'Your current bookshelf is still here.'
                                  : _loadedSessionsLabel,
                              style: LumiType.caption.copyWith(
                                color: LumiTokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: LumiTokens.space3),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: loading ? null : onLoadMore,
                      style: FilledButton.styleFrom(
                        backgroundColor: LumiTokens.yellow,
                        foregroundColor: LumiTokens.ink,
                        disabledBackgroundColor: LumiTokens.tintYellow,
                        disabledForegroundColor: LumiTokens.muted,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                        ),
                      ),
                      icon: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: LumiTokens.ink,
                              ),
                            )
                          : Icon(
                              hasError
                                  ? Icons.refresh_rounded
                                  : Icons.expand_more_rounded,
                            ),
                      label: Text(
                        loading
                            ? 'Loading earlier sessions…'
                            : hasError
                                ? 'Try again'
                                : 'Load older history',
                        style: LumiType.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: LumiTokens.green,
                ),
                const SizedBox(width: LumiTokens.space2),
                Text(
                  _allSessionsLabel,
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
              ],
            ),
    );
  }

  String get _loadedSessionsLabel => loadedSessionCount == 1
      ? 'This shelf uses the most recent reading session.'
      : 'This shelf uses the $loadedSessionCount most recent reading sessions.';

  String get _allSessionsLabel => loadedSessionCount == 1
      ? 'The full reading history is included'
      : 'All $loadedSessionCount reading sessions are included';
}
