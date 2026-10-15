import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../services/error_reporter.dart';
import '../../../theme/app_theme.dart';
import 'onboarding_media.dart';

enum _RecState { idle, starting, ready, countdown, recording, finishing }

/// In-app intro-video recorder: front camera with audio, a 3-2-1 countdown,
/// a progress ring that fills over 15 s, a stop button that stays disabled
/// until 5 s, and auto-stop at 15 s. The finished clip is handed to
/// [onRecorded]; the parent then swaps in a preview, which also releases the
/// camera.
class VideoRecorder extends StatefulWidget {
  final ValueChanged<PickedFile> onRecorded;

  /// "upload a video instead" after a permission/camera problem.
  final VoidCallback onUseUpload;

  /// True while a countdown or recording is running (parent disables
  /// navigation meanwhile).
  final ValueChanged<bool> onBusyChanged;

  /// Open the camera straight away (used by Retake).
  final bool autoStart;

  const VideoRecorder({
    super.key,
    required this.onRecorded,
    required this.onUseUpload,
    required this.onBusyChanged,
    this.autoStart = false,
  });

  @override
  State<VideoRecorder> createState() => _VideoRecorderState();
}

class _VideoRecorderState extends State<VideoRecorder>
    with WidgetsBindingObserver {
  static const double _max = 15;
  static const double _min = 5;

  CameraController? _camera;
  _RecState _state = _RecState.idle;
  String? _error;
  bool _cameraProblem = false;
  int _countdown = 0;
  double _elapsed = 0;
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _watch.stop();
    // Leaving the step while recording discards the clip.
    final c = _camera;
    _camera = null;
    c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_camera != null) _releaseCamera();
    }
  }

  void _setBusy(bool busy) => widget.onBusyChanged(busy);

  Future<void> _releaseCamera() async {
    _ticker?.cancel();
    _watch
      ..stop()
      ..reset();
    final c = _camera;
    _camera = null;
    _setBusy(false);
    if (mounted) setState(() => _state = _RecState.idle);
    await c?.dispose();
  }

  Future<void> _openCamera() async {
    if (_state == _RecState.starting) return;
    setState(() {
      _state = _RecState.starting;
      _error = null;
      _cameraProblem = false;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('noCamera', 'No camera found');
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _state = _RecState.ready;
      });
    } on CameraException catch (e, st) {
      ErrorReporter.report(
        e,
        st,
        reason: 'VideoRecorder: camera open failed (${e.code})',
      );
      _fail(
        'We could not access your camera or microphone. Please allow access, or upload a video instead.',
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VideoRecorder: camera open failed');
      _fail(
        'We could not access your camera or microphone. Please allow access, or upload a video instead.',
      );
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _state = _RecState.idle;
      _error = message;
      _cameraProblem = true;
    });
  }

  Future<void> _begin() async {
    final camera = _camera;
    if (camera == null || _state != _RecState.ready) return;
    _setBusy(true);
    setState(() {
      _state = _RecState.countdown;
      _countdown = 3;
      _error = null;
    });
    for (var n = 3; n >= 1; n--) {
      if (!mounted || _state != _RecState.countdown) return;
      setState(() => _countdown = n);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    if (!mounted || _state != _RecState.countdown) return;
    try {
      await camera.startVideoRecording();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VideoRecorder: start failed');
      _setBusy(false);
      if (mounted) {
        setState(() {
          _state = _RecState.ready;
          _error =
              'Could not start recording. Please try again, or upload a video instead.';
        });
      }
      return;
    }
    _watch
      ..reset()
      ..start();
    setState(() {
      _state = _RecState.recording;
      _elapsed = 0;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final s = _watch.elapsedMilliseconds / 1000;
      if (s >= _max) {
        _finish();
      } else {
        setState(() => _elapsed = s);
      }
    });
  }

  Future<void> _finish() async {
    final camera = _camera;
    if (camera == null || _state != _RecState.recording) return;
    _ticker?.cancel();
    _watch.stop();
    final seconds = math.min(_max, _watch.elapsedMilliseconds / 1000);
    setState(() {
      _state = _RecState.finishing;
      _elapsed = seconds;
    });
    try {
      final file = await camera.stopVideoRecording();
      final size = await File(file.path).length();
      if (!mounted) return;
      if (seconds < 4.5) {
        _setBusy(false);
        setState(() {
          _state = _RecState.ready;
          _error = 'Please record at least 5 seconds.';
        });
        return;
      }
      _setBusy(false);
      final name = file.name.isEmpty || !file.name.contains('.')
          ? 'intro.mp4'
          : file.name;
      widget.onRecorded(
        PickedFile(path: file.path, name: name, size: size, seconds: seconds),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'VideoRecorder: stop failed');
      _setBusy(false);
      if (mounted) {
        setState(() {
          _state = _RecState.ready;
          _error =
              'Something went wrong while saving the clip. Please try again, or upload a video instead.';
        });
      }
    }
  }

  // -- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              color: AppColors.mediaBg,
              child: _cameraBox(),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              color: AppColors.reject,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (_cameraProblem)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.onUseUpload,
                child: const Text('Upload a video instead'),
              ),
            ),
        ],
        const SizedBox(height: 16),
        _controls(),
      ],
    );
  }

  Widget _cameraBox() {
    final camera = _camera;
    final live =
        camera != null &&
        camera.value.isInitialized &&
        (_state == _RecState.ready ||
            _state == _RecState.countdown ||
            _state == _RecState.recording ||
            _state == _RecState.finishing);
    if (!live) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _state == _RecState.starting
              ? const CircularProgressIndicator(color: AppColors.onPrimary)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_outlined,
                      size: 44,
                      color: AppColors.onPrimaryMuted,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Say your name, your role and why a company should hire you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 14.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _openCamera,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.onPrimary,
                        foregroundColor: AppColors.primary,
                      ),
                      icon: const Icon(Icons.videocam_rounded, size: 18),
                      label: const Text('Turn on camera'),
                    ),
                  ],
                ),
        ),
      );
    }

    final preview = camera.value.previewSize ?? const Size(1280, 720);
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            // previewSize is landscape; the portrait box swaps the sides.
            width: math.min(preview.width, preview.height),
            height: math.max(preview.width, preview.height),
            child: CameraPreview(camera),
          ),
        ),
        if (_state == _RecState.recording || _state == _RecState.finishing)
          Positioned(left: 12, right: 12, top: 12, child: _topBar()),
        if (_state == _RecState.countdown)
          Container(
            color: AppColors.scrimLight,
            alignment: Alignment.center,
            child: Text(
              '$_countdown',
              style: const TextStyle(
                color: AppColors.onPrimary,
                fontSize: 96,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _topBar() {
    final secs = _elapsed.floor().clamp(0, 15);
    return Column(
      children: [
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_elapsed / _max).clamp(0, 1),
                minHeight: 5,
                backgroundColor: AppColors.onPrimarySubtle,
                valueColor: const AlwaysStoppedAnimation(AppColors.onPrimary),
              ),
            ),
            // The 5 s marker.
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _min / _max,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(width: 2, height: 9, color: AppColors.onPrimary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.scrimStrong,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BlinkingDot(active: _state == _RecState.recording),
              const SizedBox(width: 6),
              Text(
                '$secs / 15 sec',
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    final recording = _state == _RecState.recording;
    final canStop = recording && _elapsed >= _min;
    final waiting = recording && !canStop;
    final remaining = math.max(1, (_min - _elapsed).ceil());

    String caption;
    if (_state == _RecState.countdown) {
      caption = 'Get ready…';
    } else if (waiting) {
      caption = 'Keep talking… $remaining sec more';
    } else if (canStop) {
      caption = 'Tap to stop · stops by itself at 15 sec';
    } else if (_state == _RecState.ready) {
      caption = 'Tap to start · 5–15 seconds';
    } else if (_state == _RecState.finishing) {
      caption = 'Saving…';
    } else {
      caption = 'Turn on the camera to begin';
    }

    final enabled = _state == _RecState.ready || canStop;
    return Column(
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: recording ? 'Stop recording' : 'Start recording',
          child: GestureDetector(
            onTap: !enabled ? null : (recording ? _finish : _begin),
            child: _RecordButton(
              progress: recording || _state == _RecState.finishing
                  ? (_elapsed / _max).clamp(0, 1)
                  : 0,
              recording: recording || _state == _RecState.finishing,
              dimmed: !enabled,
              pulsing: waiting,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: waiting ? AppColors.warning : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  final bool active;
  const _BlinkingDot({required this.active});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: AppColors.recording,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _RecordButton extends StatefulWidget {
  final double progress;
  final bool recording;
  final bool dimmed;
  final bool pulsing;
  const _RecordButton({
    required this.progress,
    required this.recording,
    required this.dimmed,
    required this.pulsing,
  });

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final scale = widget.pulsing ? 0.94 + 0.06 * _pulse.value : 1.0;
        return Opacity(
          opacity: widget.dimmed && !widget.pulsing ? 0.45 : 1,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 84,
              height: 84,
              child: CustomPaint(
                painter: _RingPainter(widget.progress),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: widget.recording ? 30 : 58,
                    height: widget.recording ? 30 : 58,
                    decoration: BoxDecoration(
                      color: widget.pulsing
                          ? AppColors.recording.withValues(alpha: 0.5)
                          : AppColors.recording,
                      borderRadius: BorderRadius.circular(
                        widget.recording ? 8 : 29,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = AppColors.border;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.recording;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}
