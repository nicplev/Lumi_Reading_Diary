import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../services/comprehension_audio_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../lumi/lumi_toast.dart';

/// Compact inline player for a child's comprehension recording, shown on the
/// teacher's per-log row. Resolves the Storage download URL only after an
/// explicit play gesture; signed URLs are deliberately not cached between
/// widget instances or account sessions.
///
/// Designed to be lightweight: a play/pause button, a progress bar, and a
/// duration label. The existing comment thread under each log handles any
/// reply the teacher wants to leave about the recording.
class ComprehensionAudioPlayer extends StatefulWidget {
  static const double reviewThreshold = 0.8;

  @visibleForTesting
  static bool hasReachedReviewThreshold({
    required Duration position,
    required Duration total,
  }) {
    return total > Duration.zero &&
        position.inMilliseconds >= total.inMilliseconds * reviewThreshold;
  }

  /// Firebase Storage object path, e.g.
  /// `schools/{schoolId}/comprehension_audio/{logId}.m4a`. Used only as the
  /// per-log cache key — the object is not client-readable (see [schoolId]).
  final String storagePath;

  /// Duration recorded on the log doc. Used as a fallback while the audio
  /// metadata is loading so the UI doesn't show 0:00 momentarily.
  final int? durationSec;

  /// School + log ids. Required: the recording is a child's voice — PII at rest
  /// — so the Storage object is not client-readable. Playback goes through the
  /// `getComprehensionAudioUrl` callable, which authorizes the caller against
  /// the log's school and returns a short-lived signed URL. The same ids drive
  /// the trash button (`deleteComprehensionAudio`); `onDeleted` lets the host
  /// screen refresh once the server confirms.
  final String schoolId;
  final String logId;
  final VoidCallback? onDeleted;

  /// Called once when at least 80% of the recording has played (or playback
  /// completes). The recording inbox uses this to mark the current generation
  /// reviewed for all co-teachers.
  final VoidCallback? onMostlyPlayed;

  /// Injectable boundary for focused widget tests.
  @visibleForTesting
  final ComprehensionAudioService? audioService;

  /// Avoids creating a native audio player in focused widget tests.
  @visibleForTesting
  final bool debugSkipPlayerInitialization;

  const ComprehensionAudioPlayer({
    super.key,
    required this.storagePath,
    required this.schoolId,
    required this.logId,
    this.durationSec,
    this.onDeleted,
    this.onMostlyPlayed,
    this.audioService,
    this.debugSkipPlayerInitialization = false,
  });

  @override
  State<ComprehensionAudioPlayer> createState() =>
      _ComprehensionAudioPlayerState();
}

class _ComprehensionAudioPlayerState extends State<ComprehensionAudioPlayer>
    with WidgetsBindingObserver {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  bool _loading = false;
  bool _failed = false;
  bool _isPlaying = false;
  bool _deleting = false;
  bool _deleted = false;
  bool _mostlyPlayedNotified = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _duration = Duration(seconds: widget.durationSec ?? 0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_player?.pause());
    }
  }

  Future<void> _initPlayer({bool playWhenReady = false}) async {
    AudioPlayer? candidate;
    try {
      final url = await _resolveUrl();

      final player = AudioPlayer();
      candidate = player;
      final dur = await player.setUrl(url);
      if (!mounted) {
        await player.dispose();
        return;
      }
      _player = player;
      if (dur != null && dur > Duration.zero) _duration = dur;
      _stateSub = player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() {
          _isPlaying =
              s.playing && s.processingState != ProcessingState.completed;
          if (s.processingState == ProcessingState.completed) {
            _notifyMostlyPlayed();
            _position = Duration.zero;
            player.pause();
            player.seek(Duration.zero);
          }
        });
      });
      _positionSub = player.positionStream.listen((pos) {
        if (!mounted) return;
        _maybeNotifyMostlyPlayed(pos);
        setState(() => _position = pos);
      });
      setState(() => _loading = false);
      if (playWhenReady) await player.play();
    } catch (_) {
      await candidate?.dispose();
      if (identical(_player, candidate)) {
        _player = null;
        await _stateSub?.cancel();
        await _positionSub?.cancel();
        _stateSub = null;
        _positionSub = null;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Returns a freshly authorized, short-lived signed URL. Keeping it only in
  /// this widget's player instance avoids one account reusing another
  /// account's in-process cache after sign-out/sign-in.
  Future<String> _resolveUrl() async {
    final result =
        await (widget.audioService ?? ComprehensionAudioService()).getAudioUrl(
      schoolId: widget.schoolId,
      logId: widget.logId,
    );
    return result.url;
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p == null) {
      if (widget.debugSkipPlayerInitialization) return;
      setState(() {
        _loading = true;
        _failed = false;
      });
      await _initPlayer(playWhenReady: true);
      return;
    }
    if (_isPlaying) {
      await p.pause();
    } else {
      await p.play();
    }
  }

  void _maybeNotifyMostlyPlayed(Duration position) {
    final total = _duration > Duration.zero
        ? _duration
        : Duration(seconds: widget.durationSec ?? 0);
    if (total <= Duration.zero) return;
    if (ComprehensionAudioPlayer.hasReachedReviewThreshold(
      position: position,
      total: total,
    )) {
      _notifyMostlyPlayed();
    }
  }

  void _notifyMostlyPlayed() {
    if (_mostlyPlayedNotified) return;
    _mostlyPlayedNotified = true;
    widget.onMostlyPlayed?.call();
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _player?.dispose();
    _stateSub = null;
    _positionSub = null;
    _player = null;
    await _initPlayer(playWhenReady: true);
  }

  bool get _canDelete => !_deleting;

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: const Text(
          'The audio file will be permanently removed. The reading log itself '
          'is kept. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.warmOrange),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await _player?.pause();
      await (widget.audioService ?? ComprehensionAudioService()).deleteAudio(
        schoolId: widget.schoolId,
        logId: widget.logId,
      );
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deleted = true;
      });
      widget.onDeleted?.call();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showLumiToast(
        message: e.message ?? 'Failed to delete recording',
        type: LumiToastType.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showLumiToast(
        message: 'Failed to delete recording',
        type: LumiToastType.error,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Row(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading recording…',
            style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
          ),
        ],
      );
    }
    if (_failed) {
      return Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.warmOrange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Audio unavailable',
              style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
            ),
          ),
          IconButton(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.charcoal, size: 20),
            tooltip: 'Try again',
          ),
        ],
      );
    }
    final total = _duration.inSeconds == 0
        ? (widget.durationSec ?? 0)
        : _duration.inSeconds;
    final pos = _position.inSeconds.clamp(0, total);
    return Row(
      children: [
        InkWell(
          onTap: _toggle,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 32,
              color: AppColors.rosePinkAccessible,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: total > 0 ? pos / total : 0,
                backgroundColor: AppColors.charcoal.withValues(alpha: 0.08),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.rosePinkAccessible),
                minHeight: 4,
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final time = '${_format(pos)} / ${_format(total)}';
                  final style =
                      LumiTextStyles.bodySmall(color: AppColors.charcoal);
                  if (constraints.maxWidth < 180) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(time, style: style),
                      ),
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Comprehension recap',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(time, style: style),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        _deleting
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                onPressed: _canDelete ? _confirmAndDelete : null,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.charcoal, size: 20),
                tooltip: 'Delete recording',
              ),
      ],
    );
  }

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
