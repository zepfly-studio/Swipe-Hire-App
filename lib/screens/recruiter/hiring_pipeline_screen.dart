import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/opportunity.dart';
import '../../services/auth_service.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import 'my_postings_tab.dart';
import 'pipeline_widgets.dart';
import '../../widgets/notification_bell.dart';

/// The recruiter's hiring side: "Pipeline" (every candidate interaction --
/// found by email search or from someone applying to a posting) and "My
/// Postings" (roles they've published for candidates to browse and apply
/// to). Every change here shows up live on the matching candidate's own
/// dashboard.
class HiringPipelineScreen extends StatefulWidget {
  const HiringPipelineScreen({super.key});

  @override
  State<HiringPipelineScreen> createState() => _HiringPipelineScreenState();
}

class _HiringPipelineScreenState extends State<HiringPipelineScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  OpportunityStatus? _filter;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Hiring', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    const NotificationBell(),
                    if (_tabController.index == 0)
                      FilledButton.icon(
                        onPressed: () => _openSearch(context),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                        label: const Text('New'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                labelColor: AppColors.accentAlt,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.accentAlt,
                tabs: const [
                  Tab(text: 'Pipeline'),
                  Tab(text: 'My Postings'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildPipelineTab(), const MyPostingsTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineTab() {
    return StreamBuilder<List<Opportunity>>(
      stream: OpportunityService.instance.streamForRecruiter(AuthService.instance.currentUid),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Opportunity>[];
        if (all.isEmpty) {
          return FadeInUp(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No candidates in your pipeline yet.\nTap "New" to search a candidate by email, or wait for someone to apply to a posting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }
        final filtered = _filter == null ? all : all.where((o) => o.status == _filter).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  _FilterChip(label: 'All (${all.length})', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                  const SizedBox(width: 8),
                  for (final status in OpportunityStatus.values) ...[
                    _FilterChip(
                      label: '${status.label} (${all.where((o) => o.status == status).length})',
                      selected: _filter == status,
                      onTap: () => setState(() => _filter = status),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? FadeInUp(
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Nothing in this category yet.', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final opportunity = filtered[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 35 * index),
                          child: PipelineTile(
                            opportunity: opportunity,
                            onTap: () => openOpportunityEditor(context, existing: opportunity),
                            onMove: (status) => moveOpportunity(context, opportunity, status),
                            onAssignTask: () => assignTaskTo(context, opportunity),
                            onReviewTask: (task) => reviewTaskOf(context, opportunity, task: task),
                            onScheduleInterview: () => openOpportunityEditor(
                              context,
                              existing: opportunity,
                              initialStatus: OpportunityStatus.interviewScheduled,
                            ),
                            onOpenChat: () => openChatWith(context, opportunity),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final candidate = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => const _CandidateSearchScreen()),
    );
    if (candidate == null || !context.mounted) return;

    // This candidate may already have a pipeline entry with this
    // recruiter -- e.g. they separately applied to a job posting, or
    // were already shortlisted via the Wishlist. Open THAT one instead
    // of starting a second, duplicate entry for the same candidate.
    final existing = await OpportunityService.instance
        .findExistingBetween(AuthService.instance.currentUid, candidate.uid);
    if (!context.mounted) return;
    if (existing != null) {
      openOpportunityEditor(context, existing: existing);
    } else {
      openOpportunityEditor(context, candidate: candidate);
    }
  }

}

/// Same filter-chip-row-plus-list pattern as
/// [CandidateApplicationsScreen] (the candidate's "My Applications" tab)
/// -- kept consistent across both sides of the app rather than
/// introducing a different layout (e.g. a horizontally-scrolling Kanban
/// board) just for this screen.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent.withValues(alpha: 0.35),
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(color: selected ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
      side: const BorderSide(color: AppColors.border),
    );
  }
}

/// Email search for a real candidate account to start a pipeline entry
/// with.
class _CandidateSearchScreen extends StatefulWidget {
  const _CandidateSearchScreen();

  @override
  State<_CandidateSearchScreen> createState() => _CandidateSearchScreenState();
}

class _CandidateSearchScreenState extends State<_CandidateSearchScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final candidate = await OpportunityService.instance.findCandidateByEmail(email);
    if (!mounted) return;
    setState(() => _loading = false);
    if (candidate == null) {
      setState(() => _error = 'No candidate account found with that email.');
      return;
    }
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    const Text('Find a candidate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _search(),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Candidate email',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.email_outlined, color: AppColors.accentAlt),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary))
                      : const Text('Search'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

