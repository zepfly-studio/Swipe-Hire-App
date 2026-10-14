import 'package:flutter/material.dart';
import '../../models/job_posting.dart';
import '../../services/candidate_service.dart';
import '../../services/error_reporter.dart';
import '../../services/job_posting_service.dart';
import '../../theme/app_theme.dart';

/// Bottom sheet for narrowing the swipe deck. Resolves with the new filters
/// (or null if dismissed). The search text in [current] is passed through.
Future<CandidateFilters?> showDeckFiltersSheet(BuildContext context, {required CandidateFilters current}) {
  return showModalBottomSheet<CandidateFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _DeckFiltersSheet(current: current),
  );
}

const _maxExperience = 20.0;
const _maxCtc = 60.0;
const _noticeChoices = <(String, int?)>[
  ('Any', null),
  ('Immediate', 0),
  ('15 days', 15),
  ('30 days', 30),
  ('60 days', 60),
  ('90 days', 90),
];

class _DeckFiltersSheet extends StatefulWidget {
  final CandidateFilters current;
  const _DeckFiltersSheet({required this.current});

  @override
  State<_DeckFiltersSheet> createState() => _DeckFiltersSheetState();
}

class _DeckFiltersSheetState extends State<_DeckFiltersSheet> {
  late final TextEditingController _skills = TextEditingController(text: widget.current.skills.join(', '));
  late final TextEditingController _location = TextEditingController(text: widget.current.location);
  late RangeValues _experience = RangeValues(widget.current.expMin ?? 0, widget.current.expMax ?? _maxExperience);
  late RangeValues _ctc = RangeValues(widget.current.ctcMin ?? 0, widget.current.ctcMax ?? _maxCtc);
  late int? _notice = widget.current.noticeMaxDays;
  late String _jobId = widget.current.jobId;
  late bool _byMatch = widget.current.sortByMatch;
  List<JobPosting> _postings = const [];

  @override
  void initState() {
    super.initState();
    _loadPostings();
  }

  @override
  void dispose() {
    _skills.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _loadPostings() async {
    try {
      final all = await JobPostingService.instance.fetchMyPostings();
      if (mounted) setState(() => _postings = all.where((p) => p.isOpen).toList());
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'DeckFiltersSheet: load postings failed');
    }
  }

  void _apply() {
    final skills = _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final experienceOn = _experience.start > 0 || _experience.end < _maxExperience;
    final ctcOn = _ctc.start > 0 || _ctc.end < _maxCtc;
    Navigator.of(context).pop(CandidateFilters(
      query: widget.current.query,
      skills: skills,
      location: _location.text.trim(),
      expMin: experienceOn && _experience.start > 0 ? _experience.start : null,
      expMax: experienceOn && _experience.end < _maxExperience ? _experience.end : null,
      ctcMin: ctcOn && _ctc.start > 0 ? _ctc.start : null,
      ctcMax: ctcOn && _ctc.end < _maxCtc ? _ctc.end : null,
      noticeMaxDays: _notice,
      jobId: _jobId,
      sortByMatch: _byMatch,
    ));
  }

  void _reset() => Navigator.of(context).pop(CandidateFilters(query: widget.current.query));

  String _range(RangeValues v, double max, String unit) {
    final lo = v.start.round();
    final hi = v.end.round();
    if (lo == 0 && v.end >= max) return 'Any';
    return '$lo-${v.end >= max ? '$hi+' : hi} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + inset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Filter candidates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _skills,
                decoration: const InputDecoration(
                  labelText: 'Skills (comma separated)',
                  helperText: 'Candidates with any of these',
                  prefixIcon: Icon(Icons.auto_awesome_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Location', prefixIcon: Icon(Icons.location_on_outlined)),
              ),
              const SizedBox(height: 16),
              _label('Experience', _range(_experience, _maxExperience, 'yrs')),
              RangeSlider(
                values: _experience,
                min: 0,
                max: _maxExperience,
                divisions: 20,
                onChanged: (v) => setState(() => _experience = v),
              ),
              _label('Expected CTC', _range(_ctc, _maxCtc, 'LPA')),
              RangeSlider(
                values: _ctc,
                min: 0,
                max: _maxCtc,
                divisions: 60,
                onChanged: (v) => setState(() => _ctc = v),
              ),
              const SizedBox(height: 4),
              const Text('Notice period up to', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, days) in _noticeChoices)
                    ChoiceChip(
                      label: Text(label),
                      selected: _notice == days,
                      onSelected: (_) => setState(() => _notice = days),
                    ),
                ],
              ),
              if (_postings.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Match against', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _postings.any((p) => p.id == _jobId) ? _jobId : '',
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.work_outline_rounded)),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Best of all my open roles')),
                    for (final p in _postings) DropdownMenuItem(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _jobId = v ?? ''),
                ),
                SwitchListTile(
                  value: _byMatch,
                  onChanged: (v) => setState(() => _byMatch = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Best match first', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Show candidates'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String title, String value) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
      ],
    );
  }
}
