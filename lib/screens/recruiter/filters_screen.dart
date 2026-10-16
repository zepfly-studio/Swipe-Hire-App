import 'package:flutter/material.dart';

import '../../models/swipe_filters.dart';
import '../../services/api_client.dart';
import '../../services/hiring_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_nav.dart';
import '../../widgets/app_toast.dart';
import 'swipe/filters_sheet.dart';

/// The recruiter's saved filters. Every filter applied on the Swipe tab is
/// saved here. "Swipe" applies one (it becomes the active filter), "Clear"
/// switches the active filter off, "Edit" changes one, the bin deletes it.
class FiltersScreen extends StatefulWidget {
  final HiringService? service;
  const FiltersScreen({super.key, this.service});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  List<SavedSearch> _items = [];
  SwipeFilters _active = const SwipeFilters();
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  HiringService get _service => widget.service ?? HiringService.instance;

  @override
  void initState() {
    super.initState();
    _load();
    HiringService.savedFiltersChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    HiringService.savedFiltersChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted && !_loading) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final items = await _service.fetchSearches();
      final companyId = HiringService.company.value?.id ?? '';
      final active = companyId.isEmpty ? const SwipeFilters() : await _service.loadFilters(companyId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _active = active;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    }
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _create() async {
    final next = await showFiltersSheet(context, initial: const SwipeFilters(), applyLabel: 'Save filter');
    if (next == null || next.isEmpty || !mounted) return;
    await _run('new', () async {
      await _service.createSearch(name: next.label, filters: next, alerts: false);
      AppToast.success('Filter saved');
      HiringService.savedFiltersChanged.value++;
    });
  }

  /// The backend keeps a saved search's filters fixed, so editing saves the
  /// changed filter under the same name and removes the old one.
  Future<void> _edit(SavedSearch s) async {
    final next = await showFiltersSheet(context, initial: s.filters, applyLabel: 'Save changes');
    if (next == null || next.isEmpty || next == s.filters || !mounted) return;
    await _run(s.id, () async {
      await _service.createSearch(name: s.name, filters: next, alerts: s.alerts);
      await _service.deleteSearch(s.id);
      AppToast.success('Filter updated');
      HiringService.savedFiltersChanged.value++;
    });
  }

  Future<void> _toggleAlerts(SavedSearch s) => _run(s.id, () async {
        await _service.setSearchAlerts(s.id, !s.alerts);
        AppToast.success(s.alerts ? 'Alerts off' : "Alerts on. We'll notify you about new matches");
        HiringService.savedFiltersChanged.value++;
      });

  Future<void> _delete(SavedSearch s) => _run(s.id, () async {
        await _service.deleteSearch(s.id);
        HiringService.savedFiltersChanged.value++;
      });

  /// Switches the active filter off: the Swipe tab shows no candidates again.
  Future<void> _clearActive() async {
    final companyId = HiringService.company.value?.id ?? '';
    if (companyId.isEmpty) return;
    await _service.saveFilters(companyId, const SwipeFilters());
    AppToast.success('Filter cleared. Add a filter to see candidates');
    HiringService.savedFiltersChanged.value++;
  }

  void _swipe(SavedSearch s) {
    AppNav.swipeSearchId.value = s.id;
    AppNav.recruiterTab.value = AppNav.recruiterSwipe;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Filters', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(
                      _loading ? 'Filters you set while swiping are saved here.' : '${_items.length} saved',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New filter'),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No filters yet. Apply a filter on the Swipe tab (or tap New filter) and it is saved here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = _items[i];
          return FilterCard(
            search: s,
            busy: _busy.contains(s.id),
            active: !_active.isEmpty && s.filters == _active,
            onClear: _clearActive,
            onSwipe: () => _swipe(s),
            onEdit: () => _edit(s),
            onToggleAlerts: () => _toggleAlerts(s),
            onDelete: () => _delete(s),
          );
        },
      ),
    );
  }
}

class FilterCard extends StatelessWidget {
  final SavedSearch search;
  final bool busy;

  /// This is the filter the Swipe tab is using right now.
  final bool active;
  final VoidCallback onClear;
  final VoidCallback onSwipe;
  final VoidCallback onEdit;
  final VoidCallback onToggleAlerts;
  final VoidCallback onDelete;

  const FilterCard({
    super.key,
    required this.search,
    required this.busy,
    required this.active,
    required this.onClear,
    required this.onSwipe,
    required this.onEdit,
    required this.onToggleAlerts,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final parts = search.filters.summaryParts;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? AppColors.like : AppColors.border, width: active ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.tune_rounded, color: AppColors.onPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  search.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (active)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.like.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(color: AppColors.likeText, fontWeight: FontWeight.w800, fontSize: 11.5),
                  ),
                ),
              IconButton(
                tooltip: search.alerts ? 'Alerts on: we notify you about new matches' : 'Alerts off',
                onPressed: busy ? null : onToggleAlerts,
                icon: Icon(
                  search.alerts ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                  color: search.alerts ? AppColors.warning : AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ],
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in parts)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                    child: Text(p, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: busy ? null : onSwipe,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 18)),
                child: const Text('Swipe'),
              ),
              if (active) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : onClear,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  child: const Text('Clear'),
                ),
              ],
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: busy ? null : onEdit,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: const Text('Edit'),
              ),
              const Spacer(),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.reject),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
