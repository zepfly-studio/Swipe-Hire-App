import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/job_posting.dart';
import '../../services/job_posting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in_up.dart';
import 'job_detail_screen.dart';

/// The candidate's "Saved" tab: job postings they bookmarked from Browse
/// Jobs or a job's detail page.
class CandidateSavedJobsScreen extends StatelessWidget {
  final AppUser user;
  const CandidateSavedJobsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Saved Jobs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: JobPostingService.instance.streamSavedJobIds(user.uid),
            builder: (context, savedSnapshot) {
              final savedIds = savedSnapshot.data ?? const <String>{};
              if (savedIds.isEmpty) {
                return FadeInUp(
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No saved jobs yet.\nTap the bookmark icon on a listing to save it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                );
              }
              return FutureBuilder<List<JobPosting?>>(
                future: Future.wait(savedIds.map(JobPostingService.instance.fetchById)),
                builder: (context, postingsSnapshot) {
                  if (!postingsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
                  }
                  final postings = postingsSnapshot.data!.whereType<JobPosting>().toList();
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: postings.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final posting = postings[index];
                      return FadeInUp(
                        delay: Duration(milliseconds: 35 * index),
                        child: _SavedJobTile(
                          posting: posting,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => JobDetailScreen(user: user, posting: posting)),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SavedJobTile extends StatelessWidget {
  final JobPosting posting;
  final VoidCallback onTap;
  const _SavedJobTile({required this.posting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow(),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(posting.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${posting.companyName} · ${posting.location}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!posting.isOpen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.reject.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Closed', style: TextStyle(color: AppColors.reject, fontSize: 10.5, fontWeight: FontWeight.w700)),
                )
              else
                const Icon(Icons.bookmark_rounded, color: AppColors.accentAlt, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
