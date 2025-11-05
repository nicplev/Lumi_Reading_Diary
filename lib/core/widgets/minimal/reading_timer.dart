import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';
import 'rounded_card.dart';

/// Reading timer widget with start/pause/reset functionality
class ReadingTimer extends StatefulWidget {
  final Function(Duration)? onTimeUpdate;
  final Duration? initialDuration;

  const ReadingTimer({
    super.key,
    this.onTimeUpdate,
    this.initialDuration,
  });

  @override
  State<ReadingTimer> createState() => _ReadingTimerState();
}

class _ReadingTimerState extends State<ReadingTimer> {
  Timer? _timer;
  Duration _duration = Duration.zero;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDuration != null) {
      _duration = widget.initialDuration!;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    setState(() {
      _isRunning = !_isRunning;
    });

    if (_isRunning) {
      _startTimer();
    } else {
      _pauseTimer();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration = Duration(seconds: _duration.inSeconds + 1);
      });
      widget.onTimeUpdate?.call(_duration);
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
  }

  void _resetTimer() {
    setState(() {
      _timer?.cancel();
      _duration = Duration.zero;
      _isRunning = false;
    });
    widget.onTimeUpdate?.call(_duration);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return RoundedCard(
      backgroundColor: MinimalTheme.lightPurple.withValues(alpha: 0.3),
      child: Column(
        children: [
          // Timer Display
          Container(
            padding: const EdgeInsets.all(MinimalTheme.spaceL),
            decoration: BoxDecoration(
              color: MinimalTheme.white,
              borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 32,
                  color: MinimalTheme.primaryPurple,
                ),
                const SizedBox(height: MinimalTheme.spaceM),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: MinimalTheme.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Reading time',
                  style: TextStyle(
                    fontSize: 14,
                    color: MinimalTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),

          // Control Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _toggleTimer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRunning
                        ? MinimalTheme.orange
                        : MinimalTheme.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(MinimalTheme.radiusMedium),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isRunning ? Icons.pause : Icons.play_arrow),
                      const SizedBox(width: 8),
                      Text(_isRunning ? 'Pause' : 'Start'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: MinimalTheme.spaceM),
              ElevatedButton(
                onPressed: _resetTimer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MinimalTheme.white,
                  foregroundColor: MinimalTheme.textPrimary,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MinimalTheme.radiusMedium),
                  ),
                ),
                child: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
