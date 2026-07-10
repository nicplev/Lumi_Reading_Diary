import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../services/comprehension_audio_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../lumi/lumi_toast.dart';

/// A cached signed URL and the moment it stops being valid.
class _CachedUrl {
  final String url;
  final DateTime expiresAt;
  const _CachedUrl(this.url, this.expiresAt);
}

/// Compact inline player for a child's comprehension recording, shown on the
/// teacher's per-log row. Resolves the Storage download URL on demand and
/// caches it in-process to avoid re-fetching as the teacher scrolls.
///
/// Designed to be lightweight: a play/pause button, a progress bar, and a
/// duration label. The existing comment thread under each log handles any
/// reply the teacher wants to leave about the recording.
class ComprehensionAudioPlayer extends StatefulWidget {
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

  const ComprehensionAudioPlayer({
    super.key,
    required this.storagePath,
    required this.schoolId,
    required this.logId,
    this.durationSec,
    this.onDeleted,
  });

  @override
  State<ComprehensionAudioPlayer> createState() =>
      _ComprehensionAudioPlayerState();
}

class _ComprehensionAudioPlayerState extends State<ComprehensionAudioPlayer> {
  // Signed-URL cache keyed by storage path, shared across instances so a
  // teacher scrolling a long list doesn't re-mint a URL on every rebuild.
  // Entries carry their expiry — signed URLs are short-lived (~15 min), so a
  // stale entry is dropped and re-fetched rather than served (which would fail
  // playback mid-session).
  static final Map<String, _CachedUrl> _urlCache = {};

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  bool _loading = true;
  bool _failed = false;
  bool _isPlaying = false;
  bool _deleting = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.durationSec ?? 0);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final url = await _resolveUrl();

      final player = AudioPlayer();
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
            _position = Duration.zero;
            player.pause();
            player.seek(Duration.zero);
          }
        });
      });
      _positionSub = player.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
      });
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Returns a playable signed URL, using the shared cache when the entry is
  /// still comfortably valid, otherwise minting a fresh one via the callable.
  Future<String> _resolveUrl() async {
    final now = DateTime.now();
    final cached = _urlCache[widget.storagePath];
    if (cached != null &&
        cached.expiresAt.isAfter(now.add(const Duration(seconds: 30)))) {
      return cached.url;
    }
    final result = await ComprehensionAudioService().getAudioUrl(
      schoolId: widget.schoolId,
      logId: widget.logId,
    );
    _urlCache[widget.storagePath] = _CachedUrl(
      result.url,
      now.add(Duration(seconds: result.expiresInSec)),
    );
    return result.url;
  }

  void _toggle() {
    final p = _player;
    if (p == null) return;
    if (_isPlaying) {
      p.pause();
    } else {
      p.play();
    }
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _urlCache.remove(widget.storagePath);
    await _initPlayer();
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
      await ComprehensionAudioService().deleteAudio(
        schoolId: widget.schoolId,
        logId: widget.logId,
      );
      _urlCache.remove(widget.storagePath);
      if (!mounted) return;
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
    _stateSub?.cancel();
    _positionSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                valueColor: const AlwaysStoppedAnimation(
                    AppColors.rosePinkAccessible),
                minHeight: 4,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Comprehension recap',
                    style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
                  ),
                  Text(
                    '${_format(pos)} / ${_format(total)}',
                    style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
                  ),
                ],
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
