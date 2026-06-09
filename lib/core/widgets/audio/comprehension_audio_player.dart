import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Compact inline player for a child's comprehension recording, shown on the
/// teacher's per-log row. Resolves the Storage download URL on demand and
/// caches it in-process to avoid re-fetching as the teacher scrolls.
///
/// Designed to be lightweight: a play/pause button, a progress bar, and a
/// duration label. The existing comment thread under each log handles any
/// reply the teacher wants to leave about the recording.
class ComprehensionAudioPlayer extends StatefulWidget {
  /// Firebase Storage object path, e.g.
  /// `schools/{schoolId}/comprehension_audio/{logId}.m4a`.
  final String storagePath;

  /// Duration recorded on the log doc. Used as a fallback while the audio
  /// metadata is loading so the UI doesn't show 0:00 momentarily.
  final int? durationSec;

  const ComprehensionAudioPlayer({
    super.key,
    required this.storagePath,
    this.durationSec,
  });

  @override
  State<ComprehensionAudioPlayer> createState() =>
      _ComprehensionAudioPlayerState();
}

class _ComprehensionAudioPlayerState extends State<ComprehensionAudioPlayer> {
  // Signed-URL cache. Firebase Storage URLs expire in ~1h which is more
  // than enough for a session — sharing the map across instances avoids
  // hammering Storage when the teacher scrolls a long list.
  static final Map<String, String> _urlCache = {};

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;

  bool _loading = true;
  bool _failed = false;
  bool _isPlaying = false;
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
      final url = _urlCache[widget.storagePath] ??
          await FirebaseStorage.instance
              .ref(widget.storagePath)
              .getDownloadURL();
      _urlCache[widget.storagePath] = url;

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
      ],
    );
  }

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
