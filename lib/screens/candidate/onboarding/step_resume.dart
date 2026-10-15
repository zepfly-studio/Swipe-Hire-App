import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'onboarding_media.dart';

/// Step 2 -- "Upload your resume". The PDF is only uploaded when the
/// candidate continues; this widget just picks and previews.
class StepResume extends StatelessWidget {
  /// A URL already stored for this candidate (or uploaded by the auto-fill).
  final String existingUrl;

  /// A newly chosen file that has not been uploaded yet.
  final PickedFile? picked;
  final String? error;
  final bool uploading;
  final double progress;
  final VoidCallback onPick;
  final VoidCallback onKeepCurrent;

  const StepResume({
    super.key,
    required this.existingUrl,
    required this.picked,
    required this.error,
    required this.uploading,
    required this.progress,
    required this.onPick,
    required this.onKeepCurrent,
  });

  bool get _hasExisting => existingUrl.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final file = picked;
    final hasSomething = file != null || _hasExisting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: uploading ? null : onPick,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: error != null ? AppColors.reject : AppColors.border,
                width: error != null ? 1.5 : 1.2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  size: 34,
                  color: error != null ? AppColors.reject : AppColors.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  hasSomething
                      ? 'Choose a different PDF'
                      : 'Choose your resume',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap to browse · 1 PDF only · max 5 MB',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: const TextStyle(color: AppColors.reject, fontSize: 12.5),
          ),
        ],
        if (hasSomething) ...[
          const SizedBox(height: 14),
          _FileCard(
            name: file?.name ?? 'Current resume',
            subtitle: file != null
                ? '${file.sizeLabel} · ready to upload'
                : 'Already uploaded',
            onView: uploading
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => file != null
                          ? PdfPreviewScreen(path: file.path, title: file.name)
                          : PdfPreviewScreen(url: existingUrl),
                    ),
                  ),
          ),
          if (file != null && _hasExisting && !uploading)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onKeepCurrent,
                child: const Text('Keep current resume'),
              ),
            ),
        ],
        if (uploading) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: progress.clamp(0.02, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: AppColors.surfaceAlt,
          ),
          const SizedBox(height: 6),
          Text(
            'Uploading… ${(progress * 100).round()}%',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _FileCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final VoidCallback? onView;
  const _FileCard({
    required this.name,
    required this.subtitle,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('View'),
          ),
        ],
      ),
    );
  }
}
