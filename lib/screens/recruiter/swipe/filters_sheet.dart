import 'package:flutter/material.dart';

import '../../../models/swipe_filters.dart';
import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/salary.dart';
import '../../../widgets/inputs/autocomplete_field.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../../widgets/inputs/location_field.dart';
import '../../../widgets/inputs/tag_input.dart';
import '../../../models/job_choices.dart';
import 'swipe_controller.dart';

/// Opens the "Filter candidates" bottom sheet. Resolves with the filters the
/// recruiter applied, or null when it was dismissed.
///
/// With a [controller] the sheet also lists and saves searches (swipe
/// screen); without one it is just the filter form (Filters screen).
/// [allowEmpty] false keeps the apply button off until a filter is set.
Future<SwipeFilters?> showFiltersSheet(
  BuildContext context, {
  required SwipeFilters initial,
  SwipeController? controller,
  String applyLabel = 'Show candidates',
  bool allowEmpty = false,
}) {
  return showModalBottomSheet<SwipeFilters>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bgTop,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => FiltersSheet(
      initial: initial,
      controller: controller,
      applyLabel: applyLabel,
      allowEmpty: allowEmpty,
    ),
  );
}

/// Number text -> value; null for empty/invalid.
double? parseFilterNumber(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll(',', '.'));
}

/// The salary text the budget field shows for a value (LPA).
String _numText(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.round().toString() : v.toString();
}

class FiltersSheet extends StatefulWidget {
  final SwipeFilters initial;
  final SwipeController? controller;
  final String applyLabel;
  final bool allowEmpty;
  const FiltersSheet({
    super.key,
    required this.initial,
    this.controller,
    this.applyLabel = 'Show candidates',
    this.allowEmpty = false,
  });

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late final TextEditingController _city;
  late final TextEditingController _minExp;
  late final TextEditingController _maxExp;
  late final TextEditingController _minSalary;
  late final TextEditingController _maxSalary;
  late final TextEditingController _role;
  late final TextEditingController _name;
  late List<int> _notice;
  late List<String> _skills;
  late List<String> _workModes;
  String? _saveError;
  bool _saving = false;

  SwipeController? get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _city = TextEditingController(text: f.location);
    _minExp = TextEditingController(text: _numText(f.minExp));
    _maxExp = TextEditingController(text: _numText(f.maxExp));
    _minSalary = TextEditingController(text: _numText(f.minSalary));
    _maxSalary = TextEditingController(text: _numText(f.maxSalary));
    _role = TextEditingController(text: f.role);
    _name = TextEditingController();
    _notice = [...f.notice];
    _skills = [...f.skills];
    _workModes = [...f.workModes];
    TaxonomyService.instance.ensureLoaded();
    _c?.addListener(_onController);
  }

  @override
  void dispose() {
    _c?.removeListener(_onController);
    for (final t in [_role, _city, _minExp, _maxExp, _minSalary, _maxSalary, _name]) {
      t.dispose();
    }
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  SwipeFilters _current() {
    return SwipeFilters(
      role: _role.text.trim(),
      location: _city.text.trim(),
      minExp: parseFilterNumber(_minExp.text),
      maxExp: parseFilterNumber(_maxExp.text),
      minSalary: parseLpa(_minSalary.text).value,
      maxSalary: parseLpa(_maxSalary.text).value,
      notice: ([..._notice]..sort()),
      skills: _skills.take(SwipeFilters.maxSkills).toList(),
      workModes: [..._workModes],
    );
  }

  void _fill(SwipeFilters f) {
    setState(() {
      _city.text = f.location;
      _minExp.text = _numText(f.minExp);
      _maxExp.text = _numText(f.maxExp);
      _minSalary.text = _numText(f.minSalary);
      _maxSalary.text = _numText(f.maxSalary);
      _role.text = f.role;
      _notice = [...f.notice];
      _skills = [...f.skills];
      _workModes = [...f.workModes];
      _saveError = null;
    });
  }

  void _clear() => _fill(const SwipeFilters());

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final err = await _c!.saveSearch(_name.text, _current());
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = err;
      if (err == null) _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final filters = _current();
    final minParsed = parseLpa(_minSalary.text);
    final maxParsed = parseLpa(_maxSalary.text);
    final searches = _c?.searches ?? const <SavedSearch>[];
    final canApply = widget.allowEmpty || !filters.isEmpty;
    final canSave = !filters.isEmpty && _name.text.trim().isNotEmpty && !_saving;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Filter candidates', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text(
                        'Only matching candidates will appear in your stack',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              children: [
                if (searches.isNotEmpty) ...[
                  const _SectionLabel('Saved searches'),
                  for (final s in searches)
                    _SavedSearchRow(
                      search: s,
                      onApply: () => _fill(s.filters),
                      onToggleAlerts: () => _c!.toggleSearchAlerts(s),
                      onDelete: () => _c!.deleteSearch(s),
                    ),
                  const SizedBox(height: 14),
                ],
                FormFieldBlock(
                  label: 'Role / job title',
                  child: ValueListenableBuilder<Taxonomy>(
                    valueListenable: TaxonomyService.instance.notifier,
                    builder: (context, tax, _) => AutocompleteField(
                      controller: _role,
                      options: tax.roles,
                      hintText: 'e.g. Web Developer',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'City',
                  hint: 'e.g. Jaipur (also matches preferred cities)',
                  child: LocationField(
                    controller: _city,
                    hintText: 'e.g. Jaipur',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FormFieldBlock(
                        label: 'Min experience (yrs)',
                        child: TextField(
                          controller: _minExp,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: fieldDecoration(hintText: 'Any'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FormFieldBlock(
                        label: 'Max experience (yrs)',
                        child: TextField(
                          controller: _maxExp,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: fieldDecoration(hintText: 'Any'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FormFieldBlock(
                        label: 'Min salary (LPA)',
                        hint: _minSalary.text.trim().isEmpty ? null : minParsed.hint,
                        child: TextField(
                          controller: _minSalary,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: fieldDecoration(hintText: 'Any'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FormFieldBlock(
                        label: 'Max salary (LPA)',
                        hint: _maxSalary.text.trim().isEmpty ? 'Includes candidates open to negotiate' : maxParsed.hint,
                        child: TextField(
                          controller: _maxSalary,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: fieldDecoration(hintText: 'Any'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Work mode',
                  child: MultiChipSelect(
                    options: kJobWorkModes,
                    values: _workModes,
                    labels: kJobWorkModeLabels,
                    onChanged: (v) => setState(() => _workModes = v),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Notice period',
                  child: MultiChipSelect(
                    options: [for (final d in kNoticeBuckets.values) '$d'],
                    values: [for (final d in _notice) '$d'],
                    labels: {for (final e in kNoticeBuckets.entries) '${e.value}': e.key},
                    onChanged: (v) => setState(() => _notice = [for (final s in v) int.parse(s)]),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Must have any of these skills',
                  child: ValueListenableBuilder<Taxonomy>(
                    valueListenable: TaxonomyService.instance.notifier,
                    builder: (context, tax, _) => TagInput(
                      tags: _skills,
                      options: tax.skills,
                      max: SwipeFilters.maxSkills,
                      hintText: 'React, Excel…',
                      onChanged: (v) => setState(() => _skills = v),
                    ),
                  ),
                ),
                if (_c != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text('Save this search & get alerts', style: TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "We'll notify you when a new candidate matching these filters joins.",
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _name,
                                maxLength: 60,
                                decoration: fieldDecoration(hintText: 'e.g. React devs in Jaipur'),
                                onChanged: (_) => setState(() => _saveError = null),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: canSave ? _save : null,
                              style: FilledButton.styleFrom(minimumSize: const Size(72, 46)),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                                    )
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                        if (_saveError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_saveError!, style: const TextStyle(color: AppColors.reject, fontSize: 12.5)),
                          )
                        else if (filters.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Set at least one filter first.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(100, 48)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Clear'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canApply ? () => Navigator.of(context).pop(_current()) : null,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(canApply ? widget.applyLabel : 'Set a filter to continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

class _SavedSearchRow extends StatelessWidget {
  final SavedSearch search;
  final VoidCallback onApply;
  final VoidCallback onToggleAlerts;
  final VoidCallback onDelete;

  const _SavedSearchRow({
    required this.search,
    required this.onApply,
    required this.onToggleAlerts,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onApply,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark_border_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        search.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: search.alerts ? 'Alerts on: we notify you about new matches' : 'Alerts off',
            onPressed: onToggleAlerts,
            icon: Icon(
              search.alerts ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
              color: search.alerts ? AppColors.warning : AppColors.textSecondary,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Delete search',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
