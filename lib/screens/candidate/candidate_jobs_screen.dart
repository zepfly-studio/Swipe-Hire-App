import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/job_posting.dart';
import '../../services/error_reporter.dart';
import '../../services/job_posting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/job_card.dart';
import 'job_detail_screen.dart';
import 'job_filters_sheet.dart';

/// The candidate's "Browse Jobs" tab: every open [JobPosting] across all
/// recruiters, narrowed by search and filters on the server, with a
/// "Recommended for you" row on top when nothing is filtered. Each card
/// shows how well the role fits the candidate's profile.
class CandidateJobsScreen extends StatefulWidget {
  final AppUser user;

  /// The candidate's own years of experience, offered as a filter ("roles I
  /// qualify for").
  final double? myExperienceYears;
  const CandidateJobsScreen({super.key, required this.user, this.myExperienceYears});

  @override
  State<CandidateJobsScreen> createState() => _CandidateJobsScreenState();
}

class _CandidateJobsScreenState extends State<CandidateJobsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  JobFilters _filters = const JobFilters();
  late Stream<List<JobPosting>> _stream = _open();
  List<JobPosting> _recommended = const [];

  Stream<List<JobPosting>> _open() => JobPostingService.instance.streamOpenPostings(filters: _filters);

  @override
  void initState() {
    super.initState();
    _loadRecommended();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRecommended() async {
    try {
      final jobs = await JobPostingService.instance.fetchRecommended();
      if (mounted) setState(() => _recommended = jobs);
    } catch (e, stackTrace) {
      // The row is a bonus; the main list still works without it.
      ErrorReporter.report(e, stackTrace, reason: 'CandidateJobsScreen: recommended failed');
    }
  }

  void _setFilters(JobFilters next) {
    setState(() {
      _filters = next;
      _stream = _open();
    });
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _setFilters(_filters.copyWith(query: text));
    });
  }

  Future<void> _openFilters() async {
    final result = await showJobFiltersSheet(
      context,
      current: _filters,
      myExperienceYears: widget.myExperienceYears,
    );
    if (result != null && mounted) _setFilters(result.copyWith(query: _filters.query));
  }

  void _openPosting(JobPosting posting) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailScreen(user: widget.user, posting: posting)));
  }

  @override
  Widget build(BuildContext context) {
    final filtering = _filters.query.trim().isNotEmpty || _filters.activeCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('Browse Jobs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search title, company, skills...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search, color: AppColors.accentAlt),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              _setFilters(_filters.copyWith(query: ''));
                            },
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Badge(
                isLabelVisible: _filters.activeCount > 0,
                label: Text('${_filters.activeCount}'),
                backgroundColor: AppColors.accentAlt,
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openFilters,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(Icons.tune_rounded, color: AppColors.accentAlt),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<JobPosting>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
              }
              final jobs = snapshot.data ?? const <JobPosting>[];
              final showRecommended = !filtering && _recommended.isNotEmpty;

              if (jobs.isEmpty && !showRecommended) {
                return Center(
                  child: FadeInUp(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            filtering ? 'No roles match.\nTry fewer filters.' : 'No open roles right now.\nCheck back soon.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                          if (filtering) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () {
                                _search.clear();
                                _setFilters(const JobFilters());
                              },
                              child: const Text('Clear search and filters'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  _setFilters(_filters);
                  await _loadRecommended();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    if (showRecommended) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accent),
                            SizedBox(width: 6),
                            Text('Recommended for you', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 168,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recommended.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) => SizedBox(
                            width: 270,
                            child: JobCard(posting: _recommended[index], compact: true, onTap: () => _openPosting(_recommended[index])),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 18, bottom: 8),
                        child: Text('All roles', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    if (filtering && jobs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${jobs.length} role${jobs.length == 1 ? '' : 's'} found',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      ),
                    for (var i = 0; i < jobs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FadeInUp(
                          delay: Duration(milliseconds: 30 * (i < 8 ? i : 8)),
                          child: JobCard(posting: jobs[i], onTap: () => _openPosting(jobs[i])),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
