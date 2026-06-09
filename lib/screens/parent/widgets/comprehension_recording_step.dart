import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi_mascot.dart';

/// The result of a confirmed comprehension recording — handed to the parent
/// wizard, which carries it into the reading log payload + offline queue.
class ComprehensionRecordingResult {
  final String localPath;
  final int durationSec;

  const ComprehensionRecordingResult({
    required this.localPath,
    required this.durationSec,
  });
}

enum _RecordingState {
  idle,
  countdown,
  recording,
  preview,
  confirmed,
  permissionDenied,
  permissionPermanentlyDenied,
}

/// Optional final step in the parent's reading-log wizard. Lets the child
/// record a short (≤60s) recap of what they read. Encoded as AAC-LC m4a so
/// 60s ≈ 480KB — well under the 2MB Storage ceiling.
///
/// The widget owns its recorder/player lifecycle and emits the confirmed
/// result via [onRecordingChanged]. State (path + duration) is hoisted up
/// so the parent screen's draft system can persist it through a backgrounded
/// app.
class ComprehensionRecordingStep extends StatefulWidget {
  /// The per-class question (set by the teacher, or the class default).
  final String question;

  /// Pre-generated log id, reused as the storage filename so the path is
  /// stable across the wizard, the upload, and the teacher player.
  final String logId;

  /// When restoring a draft, the local file path captured before the app
  /// was backgrounded. If the file still exists the widget enters preview
  /// mode; if it's been cleared (e.g. cache wipe), it falls back to idle.
  final String? initialLocalPath;
  final int? initialDurationSec;

  /// Called when the recording is confirmed (`result != null`) or cleared
  /// via re-record (`result == null`).
  final ValueChanged<ComprehensionRecordingResult?> onRecordingChanged;

  const ComprehensionRecordingStep({
    super.key,
    required this.question,
    required this.logId,
    required this.onRecordingChanged,
    this.initialLocalPath,
    this.initialDurationSec,
  });

  @override
  State<ComprehensionRecordingStep> createState() =>
      _ComprehensionRecordingStepState();
}

class _ComprehensionRecordingStepState extends State<ComprehensionRecordingStep>
    with TickerProviderStateMixin {
  static const int _maxDurationSec = 60;
  static const int _warningAtSec = 55;

  late final AudioRecorder _recorder = AudioRecorder();
  AudioPlayer? _player;

  _RecordingState _state = _RecordingState.idle;

  // Recording state
  String? _localPath;
  int _elapsedSec = 0;
  int _countdown = 3;
  Timer? _elapsedTimer;
  Timer? _countdownTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _amplitudeSamples = [];
  static const int _maxSamples = 60;

  // Preview state
  Duration _playerDuration = Duration.zero;
  Duration _playerPosition = Duration.zero;
  bool _playerIsPlaying = false;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _playerPositionSub;

  @override
  void initState() {
    super.initState();
    _tryRestoreDraft();
  }

  Future<void> _tryRestoreDraft() async {
    final draftPath = widget.initialLocalPath;
    if (draftPath == null) return;
    final file = File(draftPath);
    if (!file.existsSync()) return;
    _localPath = draftPath;
    _elapsedSec = widget.initialDurationSec ?? 0;
    await _preparePlayer(draftPath);
    if (!mounted) return;
    setState(() => _state = _RecordingState.confirmed);
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _countdownTimer?.cancel();
    _amplitudeSub?.cancel();
    _playerStateSub?.cancel();
    _playerPositionSub?.cancel();
    // If the user backed out mid-recording, stop and discard the temp file.
    if (_state == _RecordingState.recording) {
      _recorder.stop().then((path) async {
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      });
    }
    _recorder.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _onRecordPressed() async {
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      setState(() => _state = _RecordingState.permissionPermanentlyDenied);
      return;
    }
    if (!status.isGranted) {
      setState(() => _state = _RecordingState.permissionDenied);
      return;
    }
    _startCountdown();
  }

  void _startCountdown() {
    setState(() {
      _state = _RecordingState.countdown;
      _countdown = 3;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown <= 1) {
        t.cancel();
        _beginRecording();
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _beginRecording() async {
    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/comprehension_${widget.logId}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: path,
    );

    if (!mounted) return;
    _localPath = path;
    _elapsedSec = 0;
    _amplitudeSamples.clear();
    setState(() => _state = _RecordingState.recording);

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      if (!mounted) return;
      // Amplitude.current is in dBFS (typically -160..0); map to 0..1.
      final db = amp.current;
      final normalized = ((db + 45) / 45).clamp(0.0, 1.0);
      setState(() {
        _amplitudeSamples.add(normalized);
        if (_amplitudeSamples.length > _maxSamples) {
          _amplitudeSamples.removeAt(0);
        }
      });
    });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _elapsedSec += 1);
      if (_elapsedSec >= _maxDurationSec) {
        _stopRecording(autoStopped: true);
      }
    });
  }

  Future<void> _stopRecording({bool autoStopped = false}) async {
    _elapsedTimer?.cancel();
    _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    if (path == null || !File(path).existsSync()) {
      setState(() => _state = _RecordingState.idle);
      return;
    }
    _localPath = path;
    await _preparePlayer(path);
    if (!mounted) return;
    setState(() => _state = _RecordingState.preview);
    if (autoStopped) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Got it — 60 seconds is plenty."),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _preparePlayer(String path) async {
    _player ??= AudioPlayer();
    try {
      final dur = await _player!.setFilePath(path);
      _playerDuration = dur ?? Duration(seconds: _elapsedSec);
    } catch (_) {
      _playerDuration = Duration(seconds: _elapsedSec);
    }
    _playerStateSub?.cancel();
    _playerStateSub = _player!.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _playerIsPlaying = s.playing && s.processingState != ProcessingState.completed;
        if (s.processingState == ProcessingState.completed) {
          _playerPosition = Duration.zero;
          _player!.pause();
          _player!.seek(Duration.zero);
        }
      });
    });
    _playerPositionSub?.cancel();
    _playerPositionSub = _player!.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _playerPosition = pos);
    });
  }

  void _togglePlayback() {
    final p = _player;
    if (p == null) return;
    if (_playerIsPlaying) {
      p.pause();
    } else {
      p.play();
    }
  }

  Future<void> _reRecord() async {
    await _player?.stop();
    final path = _localPath;
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    _localPath = null;
    _elapsedSec = 0;
    _amplitudeSamples.clear();
    widget.onRecordingChanged(null);
    if (!mounted) return;
    setState(() => _state = _RecordingState.idle);
  }

  void _confirmRecording() {
    final path = _localPath;
    if (path == null) return;
    widget.onRecordingChanged(ComprehensionRecordingResult(
      localPath: path,
      durationSec: _elapsedSec > 0
          ? _elapsedSec
          : (_playerDuration.inSeconds == 0 ? 1 : _playerDuration.inSeconds),
    ));
    setState(() => _state = _RecordingState.confirmed);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: LumiMascot(
              variant: LumiVariant.parent,
              size: 110,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.question,
            textAlign: TextAlign.center,
            style: LumiTextStyles.h2(color: AppColors.charcoal),
          ),
          const SizedBox(height: 24),
          _buildStateBody(),
        ],
      ),
    );
  }

  Widget _buildStateBody() {
    switch (_state) {
      case _RecordingState.idle:
        return _buildIdle();
      case _RecordingState.countdown:
        return _buildCountdown();
      case _RecordingState.recording:
        return _buildRecording();
      case _RecordingState.preview:
        return _buildPreview();
      case _RecordingState.confirmed:
        return _buildConfirmed();
      case _RecordingState.permissionDenied:
        return _buildPermissionDenied(permanent: false);
      case _RecordingState.permissionPermanentlyDenied:
        return _buildPermissionDenied(permanent: true);
    }
  }

  Widget _buildIdle() {
    return Column(
      children: [
        LumiPrimaryButton(
          onPressed: _onRecordPressed,
          text: 'Record',
          icon: Icons.mic_rounded,
          isFullWidth: true,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => widget.onRecordingChanged(null),
          child: Text(
            'Skip this step',
            style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdown() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          '$_countdown',
          style: LumiTextStyles.h1(color: AppColors.rosePinkAccessible)
              .copyWith(fontSize: 64),
        ),
        const SizedBox(height: 12),
        Text(
          'Get ready…',
          style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
        ),
      ],
    );
  }

  Widget _buildRecording() {
    final remaining = _maxDurationSec - _elapsedSec;
    final warning = _elapsedSec >= _warningAtSec;
    return Column(
      children: [
        SizedBox(
          height: 72,
          child: CustomPaint(
            painter: _WaveformPainter(
              samples: _amplitudeSamples,
              color: AppColors.rosePinkAccessible,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _formatDuration(_elapsedSec),
          style: LumiTextStyles.h3(
            color: warning ? AppColors.warmOrange : AppColors.charcoal,
          ),
        ),
        if (warning)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$remaining seconds left',
              style: LumiTextStyles.bodySmall(color: AppColors.warmOrange),
            ),
          ),
        const SizedBox(height: 20),
        LumiPrimaryButton(
          onPressed: () => _stopRecording(),
          text: 'Stop',
          icon: Icons.stop_rounded,
          isFullWidth: true,
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        _buildPlayerRow(),
        const SizedBox(height: 20),
        LumiPrimaryButton(
          onPressed: _confirmRecording,
          text: 'Use this recording',
          icon: Icons.check_rounded,
          isFullWidth: true,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _reRecord,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.charcoal),
          label: Text(
            'Re-record',
            style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmed() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.skyBlue.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.rosePinkAccessible),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Recording saved (${_formatDuration(_elapsedSec)})',
                  style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildPlayerRow(),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _reRecord,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.charcoal),
          label: Text(
            'Re-record',
            style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerRow() {
    final total = _playerDuration.inSeconds == 0
        ? _elapsedSec
        : _playerDuration.inSeconds;
    final pos = _playerPosition.inSeconds.clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.charcoal.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlayback,
            icon: Icon(
              _playerIsPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 32,
              color: AppColors.rosePinkAccessible,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: total > 0 ? pos / total : 0,
                  backgroundColor: AppColors.charcoal.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(
                      AppColors.rosePinkAccessible),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(pos)} / ${_formatDuration(total)}',
                  style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied({required bool permanent}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warmOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.mic_off_rounded,
              color: AppColors.warmOrange, size: 32),
          const SizedBox(height: 8),
          Text(
            permanent
                ? 'Microphone access is turned off. Open Settings to enable it.'
                : 'Lumi needs the microphone to record. Try again?',
            textAlign: TextAlign.center,
            style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
          ),
          const SizedBox(height: 12),
          LumiPrimaryButton(
            onPressed: permanent ? () => openAppSettings() : _onRecordPressed,
            text: permanent ? 'Open Settings' : 'Try again',
            isFullWidth: true,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => widget.onRecordingChanged(null),
            child: Text(
              'Skip this step',
              style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  const _WaveformPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      // Idle baseline
      final paint = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }
    final barWidth = size.width / _ComprehensionRecordingStepState._maxSamples;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, barWidth * 0.6);

    for (var i = 0; i < samples.length; i++) {
      final amp = samples[i];
      final barHeight = math.max(2.0, amp * size.height);
      final x = i * barWidth + barWidth / 2;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples;
}
