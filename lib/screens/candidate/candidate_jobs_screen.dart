import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/job_posting.dart';
import '../../services/job_posting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in_up.dart';
import 'job_detail_screen.dart';

/// The candidate's "Browse Jobs" tab: every open [JobPosting] across all
/// recruiters, newest first, with a simple text search over title/company/
/// location/skills.
class CandidateJobsScreen extends StatefulWidget {
  final AppUser user;
  const CandidateJobsScreen({super.key, required this.user});

  @override
  State<CandidateJobsScreen> createState() => _CandidateJobsScreenState();
}

class _CandidateJobsScreenState extends State<CandidateJobsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<JobPosting> _filter(List<JobPosting> postings) {
    if (_query.trim().isEmpty) return postings;
    final q = _query.toLowerCase();
    return postings.where((p) {
      return p.title.toLowerCase().contains(q) ||
          p.companyName.toLowerCase().contains(q) ||
          p.location.toLowerCase().contains(q) ||
          p.skills.any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Browse Jobs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search title, company, skills...',
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
              prefixIcon: const Icon(Icons.search, color: AppColors.accentAlt),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<JobPosting>>(
            stream: JobPostingService.instance.streamOpenPostings(),
            builder: (context, snapshot) {
              final all = snapshot.data ?? const <JobPosting>[];
              final filtered = _filter(all);
              if (filtered.isEmpty) {
                return Center(
                  child: FadeInUp(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        all.isEmpty ? 'No open roles right now.\nCheck back soon.' : 'No matching roles.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final posting = filtered[index];
                  return FadeInUp(
                    delay: Duration(milliseconds: 35 * index),
                    child: _JobTile(
                      posting: posting,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => JobDetailScreen(user: widget.user, posting: posting)),
                      ),
                    ),
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

class _JobTile extends StatelessWidget {
  final JobPosting posting;
  final VoidCallback onTap;
  const _JobTile({required this.posting, required this.onTap});

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(posting.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(posting.companyName, style: const TextStyle(color: AppColors.accentAlt, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(posting.location, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                  const SizedBox(width: 12),
                  const Icon(Icons.schedule_outlined, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(posting.employmentType, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                ],
              ),
              if (posting.salaryMinLpa > 0 || posting.salaryMaxLpa > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '₹${posting.salaryMinLpa.toStringAsFixed(1)}-${posting.salaryMaxLpa.toStringAsFixed(1)} LPA',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
