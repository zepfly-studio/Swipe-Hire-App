import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';

import '../../../theme/app_theme.dart';

const int kMaxResumeBytes = 5 * 1024 * 1024;
const int kMaxVideoBytes = 40 * 1024 * 1024;
const double kMinVideoSeconds = 5;
const double kMaxVideoSeconds = 15;
const double kMinVideoSecondsLenient = 4.5;
const double kMaxVideoSecondsLenient = 15.5;

/// A file the candidate picked (or the recorder wrote) that is not uploaded
/// yet.
class PickedFile {
  final String path;
  final String name;
  final int size;

  /// Video length in seconds when it could be read.
  final double? seconds;

  const PickedFile({
    required this.path,
    required this.name,
    required this.size,
    this.seconds,
  });

  String get sizeLabel => formatFileSize(size);
}

String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Client-side resume checks; null = fine.
String? validateResumeFile(String name, int size) {
  if (_ext(name) != 'pdf') return 'Please choose a PDF file';
  if (size > kMaxResumeBytes) return 'Your PDF must be under 5 MB';
  return null;
}

/// Client-side video checks (type and size); null = fine.
String? validateVideoFile(String name, int size) {
  if (!{'mp4', 'mov', 'webm', 'm4v'}.contains(_ext(name))) {
    return 'Please choose an MP4, WebM or MOV video';
  }
  if (size > kMaxVideoBytes) return 'Video must be under 40 MB';
  return null;
}

/// Duration check for an uploaded clip: 4.5-15.5 s, or accepted when the
/// length could not be read ([seconds] null).
String? validateVideoDuration(double? seconds) {
  if (seconds == null) return null;
  if (seconds < kMinVideoSecondsLenient || seconds > kMaxVideoSecondsLenient) {
    return 'Your video is ${seconds.round()} seconds. Please upload a 5–15 second video.';
  }
  return null;
}

/// Reads a local video's length; null when the platform cannot tell.
Future<double?> readVideoSeconds(String path) async {
  final c = VideoPlayerController.file(File(path));
  try {
    await c.initialize();
    final ms = c.value.duration.inMilliseconds;
    return ms > 0 ? ms / 1000 : null;
  } catch (_) {
    return null;
  } finally {
    await c.dispose();
  }
}

/// A plain full-screen PDF viewer for a local file or a URL.
class PdfPreviewScreen extends StatelessWidget {
  final String? path;
  final String? url;
  final String title;
  const PdfPreviewScreen({
    super.key,
    this.path,
    this.url,
    this.title = 'Resume',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false),
      body: path != null
          ? SfPdfViewer.file(File(path!))
          : SfPdfViewer.network(url ?? ''),
    );
  }
}

/// A looping, tap-to-pause video box for a URL or a local file.
class VideoPreviewBox extends StatefulWidget {
  final String? url;
  final String? path;
  final double aspectRatio;
  const VideoPreviewBox({
    super.key,
    this.url,
    this.path,
    this.aspectRatio = 3 / 4,
  });

  @override
  State<VideoPreviewBox> createState() => _VideoPreviewBoxState();
}

class _VideoPreviewBoxState extends State<VideoPreviewBox> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = widget.path != null
          ? VideoPlayerController.file(File(widget.path!))
          : VideoPlayerController.networkUrl(Uri.parse(widget.url ?? ''));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Container(
          color: Colors.black,
          child: _failed
              ? const Center(
                  child: Text(
                    'Could not load the video',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : c == null
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : GestureDetector(
                  onTap: () =>
                      setState(() => c.value.isPlaying ? c.pause() : c.play()),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      ),
                      if (!c.value.isPlaying)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// The soft green box used for notes ("Resume uploaded · N fields filled").
class NoteBox extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const NoteBox({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.like,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
