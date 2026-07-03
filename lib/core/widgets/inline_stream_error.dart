import 'package:flutter/material.dart';
import '../../theme/lumi_tokens.dart';

/// Inline "couldn't load" placeholder for a [StreamBuilder] whose snapshot hit
/// an error. Replaces the anti-patterns of an infinite spinner or a
/// confident-but-false empty state (0 read / no comments) when a query fails.
/// Matches the muted inline style used in the comment thread. Optional [onRetry]
/// (typically a `setState` that re-subscribes the stream).
class InlineStreamError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const InlineStreamError({
    super.key,
    this.message = "Couldn't load. Please try again shortly.",
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LumiTokens.muted, fontSize: 13),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
