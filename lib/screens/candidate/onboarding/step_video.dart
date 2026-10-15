import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'onboarding_media.dart';
import 'video_recorder.dart';

/// Step 3 -- "Record a quick intro": record in the app or upload a clip.
/// Nothing is sent from here; the chosen clip is handed up via [onPicked]
/// and uploaded when the candidate taps the main button.
class StepVideo extends StatefulWidget {
  final String existingUrl;
  final PickedFile? picked;
  final String? error;
  final bool uploading;
  final double progress;
  final ValueChanged<PickedFile?> onPicked;

  /// True while the recorder is counting down or recording.
  final ValueChanged<bool> onRecordingChanged;

  const StepVideo({
    super.key,
    required this.existingUrl,
    required this.picked,
    required this.error,
    required this.uploading,
    required this.progress,
    required this.onPicked,
    required this.onRecordingChanged,
  });

  @override
  State<StepVideo> createState() => _StepVideoState();
}

class _StepVideoState extends State<StepVideo> {
  bool _recordMode = true;
  bool _recording = false;
  bool _autoStart = false;
  String? _pickError;
  bool _reading = false;

  void _setRecording(bool v) {
    if (_recording == v) return;
    setState(() => _recording = v);
    widget.onRecordingChanged(v);
  }

  Future<void> _pickVideo() async {
    setState(() => _pickError = null);
    final file = await FilePicker.pickFile(type: FileType.video);
    if (file == null || !mounted) return;
    final path = file.path;
    if (path == null) {
      setState(() => _pickError = 'Please choose a video file');
      return;
    }
    final size = file.lengthSync() ?? await file.length() ?? 0;
    final typeError = validateVideoFile(file.name, size);
    if (typeError != null) {
      setState(() => _pickError = typeError);
      return;
    }
    setState(() => _reading = true);
    final seconds = await readVideoSeconds(path);
    if (!mounted) return;
    setState(() => _reading = false);
    final durationError = validateVideoDuration(seconds);
    if (durationError != null) {
      setState(() => _pickError = durationError);
      return;
    }
    widget.onPicked(
      PickedFile(path: path, name: file.name, size: size, seconds: seconds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picked = widget.picked;
    final error = _pickError ?? widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_recording && picked == null && !widget.uploading) ...[
          _ModeSwitch(
            recordMode: _recordMode,
            onChanged: (v) => setState(() {
              _recordMode = v;
              _pickError = null;
              _autoStart = false;
            }),
          ),
          const SizedBox(height: 16),
        ],
        if (picked != null) ...[
          VideoPreviewBox(key: ValueKey(picked.path), path: picked.path),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  picked.seconds != null
                      ? '${picked.seconds!.toStringAsFixed(1)} seconds'
                      : picked.sizeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.uploading
                    ? null
                    : () {
                        setState(() {
                          _autoStart = _recordMode;
                          _pickError = null;
                        });
                        widget.onPicked(null);
                      },
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retake'),
              ),
            ],
          ),
        ] else if (_recordMode)
          VideoRecorder(
            key: ValueKey('rec-$_autoStart'),
            autoStart: _autoStart,
            onBusyChanged: _setRecording,
            onUseUpload: () => setState(() => _recordMode = false),
            onRecorded: (f) {
              setState(() => _pickError = null);
              widget.onPicked(f);
            },
          )
        else
          _UploadBox(
            reading: _reading,
            hasError: error != null,
            onTap: _pickVideo,
          ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: const TextStyle(
              color: AppColors.reject,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        if (widget.uploading) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: widget.progress.clamp(0.02, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: AppColors.surfaceAlt,
          ),
          const SizedBox(height: 6),
          Text(
            'Uploading… ${(widget.progress * 100).round()}%',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
        if (widget.existingUrl.isNotEmpty && picked == null && !_recording) ...[
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text(
                  'Your current intro video',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  SizedBox(
                    height: 280,
                    child: Center(
                      child: VideoPreviewBox(url: widget.existingUrl),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final bool recordMode;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.recordMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap,
    ) => Expanded(
      child: Material(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppColors.onPrimary : AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: selected ? AppColors.onPrimary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          tab(
            'Record now',
            Icons.videocam_outlined,
            recordMode,
            () => onChanged(true),
          ),
          tab(
            'Upload video',
            Icons.upload_file_rounded,
            !recordMode,
            () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _UploadBox extends StatelessWidget {
  final bool reading;
  final bool hasError;
  final VoidCallback onTap;
  const _UploadBox({
    required this.reading,
    required this.hasError,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: reading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasError ? AppColors.reject : AppColors.border,
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            reading
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  )
                : Icon(
                    Icons.video_file_outlined,
                    size: 36,
                    color: hasError ? AppColors.reject : AppColors.primary,
                  ),
            const SizedBox(height: 10),
            const Text(
              'Choose a video',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            const Text(
              '5–15 seconds · MP4 / WebM / MOV · max 40 MB',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
