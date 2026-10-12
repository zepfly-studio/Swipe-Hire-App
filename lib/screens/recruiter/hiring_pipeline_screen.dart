import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/opportunity.dart';
import '../../services/auth_service.dart';
import '../../services/opportunity_service.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/candidate_card_face.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';

/// The recruiter's hiring pipeline: look up a real candidate account by
/// email, then record/update where things stand with them -- shortlisted,
/// an interview schedule, or an offer. Every change shows up live on that
/// candidate's own "Hiring Activity" dashboard.
class HiringPipelineScreen extends StatefulWidget {
  const HiringPipelineScreen({super.key});

  @override
  State<HiringPipelineScreen> createState() => _HiringPipelineScreenState();
}

class _HiringPipelineScreenState extends State<HiringPipelineScreen> {
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
                      child: Text('Pipeline', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
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
              Expanded(
                child: StreamBuilder<List<Opportunity>>(
                  stream: OpportunityService.instance.streamForRecruiter(
                    AuthService.instance.currentUser!.uid,
                  ),
                  builder: (context, snapshot) {
                    final opportunities = snapshot.data ?? const [];
                    if (opportunities.isEmpty) {
                      return FadeInUp(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No candidates in your pipeline yet.\nTap "New" and search a candidate by email to get started.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: opportunities.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final opportunity = opportunities[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 40 * index),
                          child: _PipelineTile(
                            opportunity: opportunity,
                            onTap: () => _openEditor(context, existing: opportunity),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final candidate = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => const _CandidateSearchScreen()),
    );
    if (candidate == null || !context.mounted) return;
    _openEditor(context, candidate: candidate);
  }

  void _openEditor(BuildContext context, {AppUser? candidate, Opportunity? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _OpportunityEditorScreen(candidate: candidate, existing: existing),
      ),
    );
  }
}

class _PipelineTile extends StatelessWidget {
  final Opportunity opportunity;
  final VoidCallback onTap;
  const _PipelineTile({required this.opportunity, required this.onTap});

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
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: ClipOval(child: InitialsAvatar(name: opportunity.candidateName)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opportunity.candidateName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(opportunity.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              StatusBadge(status: opportunity.status),
            ],
          ),
        ),
      ),
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
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
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

/// Create (candidate != null) or edit (existing != null) an [Opportunity]:
/// status, interview schedule, offer details.
class _OpportunityEditorScreen extends StatefulWidget {
  final AppUser? candidate;
  final Opportunity? existing;
  const _OpportunityEditorScreen({this.candidate, this.existing});

  @override
  State<_OpportunityEditorScreen> createState() => _OpportunityEditorScreenState();
}

class _OpportunityEditorScreenState extends State<_OpportunityEditorScreen> {
  final _role = TextEditingController();
  final _interviewDetails = TextEditingController();
  final _interviewMode = TextEditingController();
  final _offerSalary = TextEditingController();
  final _offerNotes = TextEditingController();

  OpportunityStatus _status = OpportunityStatus.shortlisted;
  DateTime? _interviewDate;
  DateTime? _offerJoiningDate;
  bool _saving = false;

  Opportunity? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    if (existing != null) {
      _role.text = existing.role;
      _status = existing.status;
      _interviewDate = existing.interviewDate;
      _interviewMode.text = existing.interviewMode;
      _interviewDetails.text = existing.interviewDetails;
      _offerSalary.text = existing.offerSalaryLpa?.toString() ?? '';
      _offerJoiningDate = existing.offerJoiningDate;
      _offerNotes.text = existing.offerNotes;
    }
  }

  @override
  void dispose() {
    _role.dispose();
    _interviewDetails.dispose();
    _interviewMode.dispose();
    _offerSalary.dispose();
    _offerNotes.dispose();
    super.dispose();
  }

  Future<void> _pickInterviewDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _interviewDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_interviewDate ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() => _interviewDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickJoiningDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _offerJoiningDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    setState(() => _offerJoiningDate = date);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final recruiter = RecruiterProfileService.instance;
    final existing = _existing;
    final candidate = widget.candidate;

    final opportunity = Opportunity(
      id: existing?.id ?? '',
      candidateUid: existing?.candidateUid ?? candidate!.uid,
      candidateName: existing?.candidateName ?? candidate!.name,
      recruiterUid: AuthService.instance.currentUser!.uid,
      companyName: recruiter.company.isEmpty ? 'Hiring company' : recruiter.company,
      recruiterName: recruiter.name,
      role: _role.text.trim(),
      status: _status,
      interviewDate: _status == OpportunityStatus.interviewScheduled ? _interviewDate : null,
      interviewMode: _status == OpportunityStatus.interviewScheduled ? _interviewMode.text.trim() : '',
      interviewDetails: _status == OpportunityStatus.interviewScheduled ? _interviewDetails.text.trim() : '',
      offerSalaryLpa: (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired)
          ? double.tryParse(_offerSalary.text.trim())
          : null,
      offerJoiningDate: (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired) ? _offerJoiningDate : null,
      offerNotes: (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired) ? _offerNotes.text.trim() : '',
    );

    try {
      await OpportunityService.instance.save(opportunity);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.'), backgroundColor: AppColors.reject),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _existing?.candidateName ?? widget.candidate?.name ?? '';
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    Expanded(
                      child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeInUp(
                        child: TextField(
                          controller: _role,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _decoration('Role', Icons.work_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeInUp(delay: const Duration(milliseconds: 40), child: _buildStatusPicker()),
                      const SizedBox(height: 18),
                      if (_status == OpportunityStatus.interviewScheduled)
                        FadeInUp(delay: const Duration(milliseconds: 80), child: _buildInterviewFields()),
                      if (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired)
                        FadeInUp(delay: const Duration(milliseconds: 80), child: _buildOfferFields()),
                      const SizedBox(height: 26),
                      FadeInUp(
                        delay: const Duration(milliseconds: 160),
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _saving
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPicker() {
    return SectionCard(
      title: 'Status',
      icon: Icons.flag_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: OpportunityStatus.values.map((status) {
          final selected = status == _status;
          return ChoiceChip(
            label: Text(status.label),
            selected: selected,
            onSelected: (_) => setState(() => _status = status),
            selectedColor: AppColors.accent.withValues(alpha: 0.35),
            backgroundColor: AppColors.surfaceAlt,
            labelStyle: TextStyle(color: selected ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: FontWeight.w600),
            side: const BorderSide(color: AppColors.border),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInterviewFields() {
    return SectionCard(
      title: 'Interview schedule',
      icon: Icons.event_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _pickInterviewDateTime,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_interviewDate == null ? 'Pick date & time' : _formatDateTime(_interviewDate!)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interviewMode,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Mode (e.g. Online / In-person)', Icons.videocam_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interviewDetails,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Link or address', Icons.link_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferFields() {
    return SectionCard(
      title: 'Offer details',
      icon: Icons.card_giftcard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _offerSalary,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Offered CTC (LPA)', Icons.payments_outlined),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickJoiningDate,
            icon: const Icon(Icons.event_available_outlined, size: 16),
            label: Text(_offerJoiningDate == null ? 'Pick joining date' : '${_offerJoiningDate!.day}/${_offerJoiningDate!.month}/${_offerJoiningDate!.year}'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _offerNotes,
            maxLines: 2,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Notes', Icons.notes_rounded),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year}, $hour:$minute $period';
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.accentAlt, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }
}
