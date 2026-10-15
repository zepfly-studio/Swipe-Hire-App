import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/candidate.dart';
import '../../models/candidate_profile.dart';
import '../../models/candidate_stats.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/candidate_profile_service.dart';
import '../../services/error_reporter.dart';
import '../../services/opportunity_service.dart';
import '../../services/taxonomy_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/activity_ring.dart';
import '../../utils/profile_strength.dart';
import '../../utils/salary.dart';
import '../../utils/search_rank.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/candidate_card_face.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/inputs/form_blocks.dart';
import '../../widgets/inputs/tag_input.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/trust_widgets.dart';
import '../chat_screen.dart';
import '../resume_screen.dart';
import 'company_page_screen.dart';
import 'onboarding/onboarding_form.dart';
import 'onboarding/onboarding_media.dart';

/// The candidate's Home tab (website B7): live/hidden status, three stat
/// cards, the 15-day "I'm active" ring, profile strength, the companies that
/// shortlisted you, the open-to-work switch, job preferences and a card with
/// your own profile.
class CandidateHomeScreen extends StatefulWidget {
  final AppUser user;
  final CandidateProfile profile;
  final ValueChanged<CandidateProfile> onProfileChanged;
  final VoidCallback onEditProfile;

  const CandidateHomeScreen({
    super.key,
    required this.user,
    required this.profile,
    required this.onProfileChanged,
    required this.onEditProfile,
  });

  @override
  State<CandidateHomeScreen> createState() => _CandidateHomeScreenState();
}

class _CandidateHomeScreenState extends State<CandidateHomeScreen>
    with WidgetsBindingObserver {
  CandidateStats? _stats;
  Timer? _poll;
  bool _marking = false;
  bool _savingPrefs = false;
  bool _togglingOpen = false;
  final GlobalKey _prefsKey = GlobalKey();

  late List<String> _workModes = [...widget.profile.workModes];
  late List<String> _jobTypes = [...widget.profile.jobTypes];
  late List<String> _cities = [...widget.profile.preferredLocations];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TaxonomyService.instance.ensureLoaded();
    _loadStats();
    // A gentle refresh while the app is open; also on resume and pull-down.
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _loadStats());
  }

  @override
  void didUpdateWidget(covariant CandidateHomeScreen old) {
    super.didUpdateWidget(old);
    if (!_prefsDirty(old.profile)) {
      _workModes = [...widget.profile.workModes];
      _jobTypes = [...widget.profile.jobTypes];
      _cities = [...widget.profile.preferredLocations];
    }
  }

  /// Whether the local preference edits differ from [reference].
  bool _prefsDirty(CandidateProfile reference) =>
      !_sameSet(_workModes, reference.workModes) ||
      !_sameSet(_jobTypes, reference.jobTypes) ||
      !_sameList(_cities, reference.preferredLocations);

  static bool _sameSet(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);
  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await CandidateProfileService.instance.fetchStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {
      // Keep the last numbers; an older backend just shows "-".
      if (mounted && _stats == null) {
        setState(() => _stats = const CandidateStats());
      }
    }
  }

  Future<void> _refresh() async {
    await _loadStats();
    try {
      final p = await CandidateProfileService.instance.fetch(widget.user.uid);
      if (p != null && mounted) widget.onProfileChanged(p);
    } catch (_) {}
  }

  // -- actions -----------------------------------------------------------------

  Future<void> _imActive() async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      final p = await CandidateProfileService.instance.markActive();
      if (!mounted) return;
      widget.onProfileChanged(
        p.activeAt == null ? p.copyWith(activeAt: DateTime.now()) : p,
      );
      AppToast.success("You're back at the top of company feeds!");
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not update', description: e.message);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _toggleOpen(bool value) async {
    if (_togglingOpen) return;
    setState(() => _togglingOpen = true);
    try {
      final p = widget.profile;
      final saved = await CandidateProfileService.instance.savePreferences(
        openToWork: value,
        workModes: p.workModes,
        jobTypes: p.jobTypes,
        preferredLocations: p.preferredLocations,
      );
      if (!mounted) return;
      widget.onProfileChanged(saved.copyWith(openToWork: value));
      AppToast.success('Preferences saved');
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not save', description: e.message);
    } finally {
      if (mounted) setState(() => _togglingOpen = false);
    }
  }

  Future<void> _savePrefs() async {
    if (_savingPrefs) return;
    setState(() => _savingPrefs = true);
    try {
      final saved = await CandidateProfileService.instance.savePreferences(
        openToWork: widget.profile.openToWork,
        workModes: _workModes,
        jobTypes: _jobTypes,
        preferredLocations: _cities,
      );
      if (!mounted) return;
      widget.onProfileChanged(
        saved.copyWith(
          openToWork: widget.profile.openToWork,
          workModes: _workModes,
          jobTypes: _jobTypes,
          preferredLocations: _cities,
        ),
      );
      AppToast.success('Preferences saved');
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not save', description: e.message);
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  void _openStrengthItem(StrengthItem item) {
    if (item.target == StrengthTarget.preferences) {
      final ctx = _prefsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    } else {
      widget.onEditProfile();
    }
  }

  void _openCompany(ShortlistedBy row) {
    if (row.companyId.isEmpty) {
      AppToast.info("This company hasn't added a page yet");
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CompanyPageScreen(user: widget.user, companyId: row.companyId),
      ),
    );
  }

  Future<void> _openChat(ShortlistedBy row) async {
    try {
      final all = await OpportunityService.instance.fetchMine();
      final match = all.where((o) => o.id == row.id).toList();
      if (!mounted) return;
      if (match.isEmpty) {
        AppToast.info('Chat is not available yet');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            opportunity: match.first,
            currentUid: AuthService.instance.currentUid,
            currentName: widget.user.name,
          ),
        ),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'CandidateHome: open chat failed');
      if (mounted) AppToast.error('Could not open the chat');
    }
  }

  Candidate get _asCandidate {
    final p = widget.profile;
    return Candidate(
      id: widget.user.uid,
      name: widget.user.name,
      age: p.age,
      qualification: p.qualification,
      experience: p.experience,
      role: p.desiredRole,
      location: p.location,
      currentCompany: p.currentCompany,
      currentSalaryLpa: p.currentSalaryLpa,
      expectedSalaryLpa: p.expectedSalaryLpa,
      skills: p.skills,
      photoUrl: p.photoUrl,
      resumeUrl: p.resumeUrl,
      introVideoUrl: p.introVideoUrl,
      about: p.about,
      noticePeriod: p.noticePeriod,
    );
  }

  // -- build ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final first = widget.user.name.trim().split(RegExp(r'\s+')).first;
    final strength = computeProfileStrength(p);
    final stats = _stats;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          FadeInUp(child: _greeting(first, p.openToWork)),
          const SizedBox(height: 18),
          FadeInUp(
            delay: const Duration(milliseconds: 40),
            child: _statCards(stats),
          ),
          if (p.openToWork) ...[
            const SizedBox(height: 16),
            FadeInUp(
              delay: const Duration(milliseconds: 80),
              child: _ActivityCard(
                ring: activityRingFor(p.activeAt),
                busy: _marking,
                onActive: _imActive,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FadeInUp(
            delay: const Duration(milliseconds: 120),
            child: _StrengthCard(strength: strength, onItem: _openStrengthItem),
          ),
          const SizedBox(height: 16),
          FadeInUp(
            delay: const Duration(milliseconds: 160),
            child: _ShortlistedCard(
              stats: stats,
              onCompany: _openCompany,
              onChat: _openChat,
            ),
          ),
          const SizedBox(height: 16),
          FadeInUp(
            delay: const Duration(milliseconds: 200),
            child: _openToWorkCard(p.openToWork),
          ),
          const SizedBox(height: 16),
          FadeInUp(
            delay: const Duration(milliseconds: 240),
            child: _preferencesCard(),
          ),
          const SizedBox(height: 16),
          FadeInUp(
            delay: const Duration(milliseconds: 280),
            child: _profileCard(p),
          ),
        ],
      ),
    );
  }

  Widget _greeting(String first, bool live) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PulseDot(
                    color: live ? AppColors.like : AppColors.textTertiary,
                    pulsing: live,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    live ? 'Your profile is live' : 'Your profile is hidden',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: live
                          ? AppColors.likeText
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Hi $first',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                live
                    ? 'Companies are swiping through profiles like yours right now.'
                    : 'Turn on "Open to work" when you are ready for new offers.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const NotificationBell(),
      ],
    );
  }

  Widget _statCards(CandidateStats? s) {
    String v(int? n) => n == null ? '–' : '$n';
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.visibility_outlined,
            value: v(s?.viewedCount),
            label: 'Profile views',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.favorite_border_rounded,
            value: v(s?.wishlistedCount),
            label: 'Wishlisted',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.bookmark_border_rounded,
            value: v(s?.shortlistedCount),
            label: 'Shortlisted',
          ),
        ),
      ],
    );
  }

  Widget _openToWorkCard(bool open) {
    return _Panel(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (open ? AppColors.like : AppColors.textTertiary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              open ? Icons.work_outline_rounded : Icons.work_off_outlined,
              color: open ? AppColors.like : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  open ? 'Open to work' : 'Not looking right now',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  open
                      ? 'Companies can discover your profile.'
                      : 'Your profile is hidden from companies.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: open, onChanged: _togglingOpen ? null : _toggleOpen),
        ],
      ),
    );
  }

  Widget _preferencesCard() {
    final dirty = _prefsDirty(widget.profile);
    return Container(
      key: _prefsKey,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.tune_rounded,
              title: 'Job preferences',
            ),
            const SizedBox(height: 14),
            FormFieldBlock(
              label: 'Work mode',
              child: MultiChipSelect(
                options: kWorkModes,
                labels: kWorkModeLabels,
                values: _workModes,
                onChanged: (v) => setState(() => _workModes = v),
              ),
            ),
            const SizedBox(height: 14),
            FormFieldBlock(
              label: 'Job type',
              child: MultiChipSelect(
                options: kJobTypes,
                labels: kJobTypeLabels,
                values: _jobTypes,
                onChanged: (v) => setState(() => _jobTypes = v),
              ),
            ),
            const SizedBox(height: 14),
            FormFieldBlock(
              label: "Cities you'd work in",
              hint: 'Up to 10 cities',
              child: ValueListenableBuilder<Taxonomy>(
                valueListenable: TaxonomyService.instance.notifier,
                builder: (context, t, _) => TagInput(
                  tags: _cities,
                  max: 10,
                  options: t.locations,
                  hintText: 'Jaipur, Pune…',
                  suggestionIcon: Icons.place_outlined,
                  suggest: (q, exclude) =>
                      rankLocations(q, t.cities, t.states, exclude: exclude),
                  onChanged: (v) => setState(() => _cities = v),
                ),
              ),
            ),
            if (dirty) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _savingPrefs ? null : _savePrefs,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: _savingPrefs
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save preferences'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profileCard(CandidateProfile p) {
    final details = <(String, String)>[
      (
        'Experience',
        p.experience.trim().isEmpty
            ? ''
            : (p.experienceYears == 0
                  ? 'Fresher'
                  : experienceTextFor(p.experienceYears)),
      ),
      (
        'Expected salary',
        salaryRangeLabel(
          p.expectedSalaryLpa,
          p.expectedSalaryMaxLpa,
          negotiable: p.salaryNegotiable,
        ),
      ),
      (
        'Current salary',
        p.currentSalaryLpa > 0
            ? '₹${p.currentSalaryLpa.toStringAsFixed(p.currentSalaryLpa == p.currentSalaryLpa.roundToDouble() ? 0 : 1)} LPA'
            : '',
      ),
      ('Notice period', p.noticePeriod),
      ('Current / last company', p.currentCompany),
      ('Current / last role', p.currentPost),
      ('Qualification', p.qualification),
      ('Degree', p.degree),
      ('College', p.college),
      ('Graduation year', p.graduationYear > 0 ? '${p.graduationYear}' : ''),
      ('Age', p.age > 0 ? '${p.age}' : ''),
      ('Gender', p.gender),
      ('Location', p.location),
      ('Open to cities', p.preferredLocations.join(', ')),
      ('Work mode', p.workModes.map((m) => kWorkModeLabels[m] ?? m).join(', ')),
      ('Job type', p.jobTypes.map((m) => kJobTypeLabels[m] ?? m).join(', ')),
    ].where((d) => d.$2.trim().isNotEmpty).toList();

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: ClipOval(
                  child: p.photoUrl.isEmpty
                      ? InitialsAvatar(name: widget.user.name)
                      : CachedNetworkImage(
                          imageUrl: p.photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              InitialsAvatar(name: widget.user.name),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (p.desiredRole.isNotEmpty)
                      Text(
                        p.desiredRole,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: widget.onEditProfile,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Edit profile'),
              ),
            ],
          ),
          if (p.introVideoUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: VideoPreviewBox(url: p.introVideoUrl),
              ),
            ),
          ],
          if (p.resumeUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResumeScreen(candidate: _asCandidate),
                ),
              ),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('View my resume'),
            ),
          ],
          if (p.skills.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _Eyebrow('Skills'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in p.skills)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _Eyebrow('Details'),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final d in details)
                      SizedBox(
                        width: w,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.bgTop,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.$1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                d.$2,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (p.about.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const _Eyebrow('About'),
            const SizedBox(height: 6),
            Text(p.about, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ],
        ],
      ),
    );
  }
}

// -- pieces ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _PanelTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
          ),
        ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.textSecondary,
    ),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _PulseDot({required this.color, required this.pulsing});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: widget.pulsing
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.4 * (1 - _c.value)),
                    blurRadius: 2 + 8 * _c.value,
                    spreadRadius: 3 * _c.value,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// The 15-day "I'm active" ring.
class _ActivityCard extends StatelessWidget {
  final ActivityRing ring;
  final bool busy;
  final VoidCallback onActive;
  const _ActivityCard({
    required this.ring,
    required this.busy,
    required this.onActive,
  });

  @override
  Widget build(BuildContext context) {
    final full = ring.isFull;
    final color = full ? AppColors.warning : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: full
            ? AppColors.warning.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: full
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(92, 92),
                  painter: _RingPainter(ring.progress, color),
                ),
                if (full)
                  InkWell(
                    onTap: busy ? null : onActive,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  color: AppColors.warning,
                                  size: 22,
                                ),
                                Text(
                                  "I'm active",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${ring.daysLeft}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        ring.daysLeft == 1 ? 'day left' : 'days left',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  full
                      ? 'Your profile has moved down'
                      : "You're at the top of company feeds",
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  full
                      ? "You haven't confirmed you're still looking for 15+ days, so companies now see you much lower. Tap I'm active to go back to the top."
                      : "This ring fills up over 15 days. When it's full, it becomes an I'm active button: tap it to stay on top. If you don't, companies will see your profile much lower.",
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (full) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: busy ? null : onActive,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      minimumSize: const Size(0, 40),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text("I'm active"),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = AppColors.surfaceAlt;
    canvas.drawCircle(center, radius, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

class _StrengthCard extends StatelessWidget {
  final ProfileStrength strength;
  final ValueChanged<StrengthItem> onItem;
  const _StrengthCard({required this.strength, required this.onItem});

  @override
  Widget build(BuildContext context) {
    final missing = strength.topMissing;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(64, 64),
                      painter: _RingPainter(
                        strength.score / 100,
                        strength.color,
                      ),
                    ),
                    Text(
                      '${strength.score}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Eyebrow('Profile strength'),
                    const SizedBox(height: 3),
                    Text(
                      strength.level,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: strength.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      missing.isEmpty
                          ? 'Your profile has everything companies look for.'
                          : 'Complete profiles get shortlisted more often.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (missing.isEmpty)
            const Text(
              '✓ Nothing left to add.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.likeText,
              ),
            )
          else
            for (final item in missing)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onItem(item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        '+${item.points}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ShortlistedCard extends StatelessWidget {
  final CandidateStats? stats;
  final void Function(ShortlistedBy) onCompany;
  final void Function(ShortlistedBy) onChat;
  const _ShortlistedCard({
    required this.stats,
    required this.onCompany,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final hidden = s?.hiddenCount ?? 0;
    final rows = s?.shortlistedBy ?? const <ShortlistedBy>[];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.business_center_outlined,
            title: 'Companies that shortlisted you',
          ),
          const SizedBox(height: 12),
          if (hidden > 0)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.visibility_off_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hidden == 1
                              ? '1 company shortlisted you'
                              : '$hidden companies shortlisted you',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "You'll see who they are as soon as they message you or send a task or interview invite.",
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (rows.isEmpty && hidden == 0 && s != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No shortlists yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'A great intro video and a complete skill list help you get noticed faster.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          for (final r in rows)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onCompany(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: r.logoUrl.isEmpty
                            ? InitialsAvatar(name: r.companyName)
                            : CachedNetworkImage(
                                imageUrl: r.logoUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    InitialsAvatar(name: r.companyName),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CompanyName(
                            name: r.companyName,
                            verified: r.verified,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          if (r.subtitle.isNotEmpty)
                            Text(
                              r.subtitle,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              StatePill(
                                label: r.stageLabel,
                                color: r.stage == 'hired'
                                    ? AppColors.like
                                    : AppColors.primary,
                              ),
                              if (r.date != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  _dayLabel(r.date!),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (r.id.isNotEmpty)
                      IconButton(
                        tooltip: 'Message',
                        onPressed: () => onChat(r),
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'These companies can see your email and phone number and may contact you directly.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}
