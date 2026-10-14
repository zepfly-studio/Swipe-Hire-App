import 'package:flutter/material.dart';
import '../../services/job_posting_service.dart';
import '../../theme/app_theme.dart';

const _employmentTypes = ['Full-time', 'Part-time', 'Contract', 'Internship'];

/// Bottom sheet for narrowing the job list. Resolves with the new filters
/// (or null if dismissed). [current]'s search text is passed through
/// untouched.
Future<JobFilters?> showJobFiltersSheet(
  BuildContext context, {
  required JobFilters current,
  double? myExperienceYears,
}) {
  return showModalBottomSheet<JobFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _JobFiltersSheet(current: current, myExperienceYears: myExperienceYears),
  );
}

class _JobFiltersSheet extends StatefulWidget {
  final JobFilters current;
  final double? myExperienceYears;
  const _JobFiltersSheet({required this.current, required this.myExperienceYears});

  @override
  State<_JobFiltersSheet> createState() => _JobFiltersSheetState();
}

class _JobFiltersSheetState extends State<_JobFiltersSheet> {
  late String _type = widget.current.employmentType;
  late bool _remote = widget.current.remoteOnly;
  late bool _byExperience = widget.current.myExperienceYears != null;
  late bool _bestMatch = widget.current.sortByMatch;
  late double _salaryMin = widget.current.salaryMin ?? 0;
  late final TextEditingController _location = TextEditingController(text: widget.current.location);
  late final TextEditingController _skills = TextEditingController(text: widget.current.skills.join(', '));

  @override
  void dispose() {
    _location.dispose();
    _skills.dispose();
    super.dispose();
  }

  void _apply() {
    final skills = _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    Navigator.of(context).pop(JobFilters(
      query: widget.current.query,
      location: _location.text.trim(),
      employmentType: _type,
      salaryMin: _salaryMin > 0 ? _salaryMin : null,
      skills: skills,
      remoteOnly: _remote,
      myExperienceYears: _byExperience ? widget.myExperienceYears : null,
      sortByMatch: _bestMatch,
    ));
  }

  void _reset() {
    Navigator.of(context).pop(JobFilters(query: widget.current.query));
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
                  const Expanded(child: Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Job type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _employmentTypes)
                    ChoiceChip(
                      label: Text(t),
                      selected: _type.toLowerCase() == t.toLowerCase(),
                      onSelected: (on) => setState(() => _type = on ? t : ''),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Location', prefixIcon: Icon(Icons.location_on_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _skills,
                decoration: const InputDecoration(
                  labelText: 'Skills (comma separated)',
                  helperText: 'Roles that ask for any of these',
                  prefixIcon: Icon(Icons.auto_awesome_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Text('Minimum pay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Text(_salaryMin <= 0 ? 'Any' : '₹${_salaryMin.toStringAsFixed(0)} LPA+',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
                ],
              ),
              Slider(
                value: _salaryMin,
                min: 0,
                max: 50,
                divisions: 50,
                onChanged: (v) => setState(() => _salaryMin = v),
              ),
              SwitchListTile(
                value: _remote,
                onChanged: (v) => setState(() => _remote = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('Remote only', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (widget.myExperienceYears != null)
                SwitchListTile(
                  value: _byExperience,
                  onChanged: (v) => setState(() => _byExperience = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Roles I qualify for', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Hide roles asking for more than ${widget.myExperienceYears!.toStringAsFixed(widget.myExperienceYears! % 1 == 0 ? 0 : 1)} years'),
                ),
              SwitchListTile(
                value: _bestMatch,
                onChanged: (v) => setState(() => _bestMatch = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('Best match first', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Show roles'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
