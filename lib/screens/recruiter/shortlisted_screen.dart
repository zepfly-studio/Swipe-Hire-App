import 'package:flutter/material.dart';
import '../../models/candidate.dart';
import '../../models/pair/pipeline_models.dart';
import '../../models/pair/pipeline_stage.dart';
import '../../services/api_client.dart';
import '../../services/pipeline_service.dart';
import '../../services/visible_poller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../messages/pair_nav.dart';
import '../messages/pair_widgets.dart';
import 'shortlisted/candidate_sheet.dart';
import 'shortlisted/group_message_sheet.dart';
import 'shortlisted/pipeline_card.dart';

/// The company's shortlisted pipeline: job filter, stage tabs, multi-select
/// group message, and a candidate modal with pipeline controls.
class ShortlistedScreen extends StatefulWidget {
  /// Pre-select a job in the job filter.
  final String? initialJobId;
  const ShortlistedScreen({super.key, this.initialJobId});

  @override
  State<ShortlistedScreen> createState() => _ShortlistedScreenState();
}

class _ShortlistedScreenState extends State<ShortlistedScreen> {
  late final VisiblePoller _poller;
  List<Candidate>? _rows;
  List<PipelineJob> _jobs = const [];
  String? _jobId;
  String _stage = 'all';
  String? _error;
  final PipelineSelection _selection = PipelineSelection();

  @override
  void initState() {
    super.initState();
    _jobId = (widget.initialJobId == null || widget.initialJobId!.isEmpty) ? null : widget.initialJobId;
    _poller = VisiblePoller(interval: const Duration(seconds: 30), onTick: _loadRows)..start();
    _loadJobs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setVisible(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant ShortlistedScreen old) {
    super.didUpdateWidget(old);
    if (old.initialJobId != widget.initialJobId) {
      _jobId = (widget.initialJobId == null || widget.initialJobId!.isEmpty) ? null : widget.initialJobId;
      _poller.pokeNow();
    }
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await PipelineService.instance.myJobs();
      if (!mounted) return;
      setState(() => _jobs = jobs);
    } catch (_) {
      // The filter just stays hidden.
    }
  }

  Future<void> _loadRows() async {
    final jobId = _jobId;
    try {
      final rows = await PipelineService.instance.shortlisted(jobId: jobId);
      if (!mounted || jobId != _jobId) return;
      setState(() {
        _rows = rows;
        _error = null;
        _selection.retainOnly(rows);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_rows == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _rows == null) setState(() => _error = 'Could not load your shortlist.');
    }
  }

  void _setJob(String? id) {
    if (id == _jobId) return;
    setState(() {
      _jobId = id;
      _rows = null;
      _error = null;
      _selection.clear();
    });
    _loadRows();
  }

  void _patchRow(bool Function(Candidate) match, Candidate Function(Candidate) change) {
    final rows = _rows;
    if (rows == null) return;
    setState(() => _rows = [for (final r in rows) match(r) ? change(r) : r]);
  }

  void _onStage(String swipeId, String personId, String stage) {
    if (!mounted) return;
    _patchRow((r) => r.swipeId == swipeId, (r) => r.copyWith(stage: stage));
  }

  void _onNotes(String swipeId, String notes) {
    if (!mounted) return;
    _patchRow((r) => r.swipeId == swipeId, (r) => r.copyWith(notes: notes));
  }

  Future<void> _messageGroup(List<Candidate> visible) async {
    final recipients = _selection.recipients(visible);
    if (recipients.isEmpty) return;
    final result = await showGroupMessageSheet(context, recipients);
    if (result == null || !mounted) return;
    // Rows still in Shortlisted move to Contacted on screen.
    _patchRow(
      (r) => result.sentIds.contains(r.id) && (r.stage.isEmpty || r.stage == 'shortlisted'),
      (r) => r.copyWith(stage: 'contacted'),
    );
    setState(_selection.clear);
    _loadRows();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PairHeader(
                title: 'Shortlisted',
                badge: rows == null ? null : CountPill(count: rows.length),
                subtitle:
                    'Everyone you shortlisted. Tap a candidate for full details, message them, send a task or schedule an interview.',
              ),
              if (_jobs.length > 1) _jobFilter(),
              Expanded(child: _body(rows)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobFilter() {
    String labelFor(String? id) {
      if (id == null) return 'All jobs';
      for (final j in _jobs) {
        if (j.id == id) return j.filterLabel;
      }
      return 'All jobs';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<String>(
          tooltip: 'Filter by job',
          onSelected: (v) => _setJob(v.isEmpty ? null : v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: '', child: Text('All jobs')),
            for (final j in _jobs) PopupMenuItem(value: j.id, child: Text(j.filterLabel)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.work_outline_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    labelFor(_jobId),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<Candidate>? rows) {
    if (rows == null) {
      if (_error != null) {
        return PairErrorState(
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _loadRows();
          },
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    }
    if (rows.isEmpty) {
      return PairEmptyState(
        icon: Icons.groups_2_outlined,
        title: 'No one shortlisted yet',
        message: 'Swipe right on a candidate to shortlist them and unlock their contact details.',
        actionLabel: 'Start swiping',
        onAction: () => PairNav.openSwipe(context),
      );
    }
    final counts = stageCounts(rows.map((r) => r.stage));
    final inStage = rowsInStage(rows, _stage);
    final people = dedupeByPerson(inStage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stageTabs(counts),
        if (inStage.isNotEmpty) _selectionBar(people.length, inStage),
        Expanded(
          child: inStage.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('Nobody in this stage yet.', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRows,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: inStage.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final c = inStage[i];
                      return PipelineCard(
                        key: ValueKey('${c.swipeId}-${c.id}-${c.jobId}'),
                        candidate: c,
                        selected: _selection.contains(c.id),
                        onToggleSelected: () => setState(() => _selection.toggle(c.id)),
                        onOpen: () => showCandidateSheet(
                          context,
                          c,
                          onStageChanged: _onStage,
                          onNotesChanged: _onNotes,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _stageTabs(Map<String, int> counts) {
    final tabs = ['all', ...kPipelineStages];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = tabs[i];
          final selected = _stage == key;
          final label = key == 'all' ? 'All' : stageLabel(key);
          return ChoiceChip(
            label: Text('$label ${counts[key] ?? 0}'),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => setState(() => _stage = key),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          );
        },
      ),
    );
  }

  Widget _selectionBar(int visiblePeople, List<Candidate> inStage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() {
              if (_selection.isEmpty) {
                _selection.selectAll(inStage);
              } else {
                _selection.clear();
              }
            }),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    _selection.isEmpty
                        ? Icons.check_box_outline_blank_rounded
                        : (_selection.count >= visiblePeople
                            ? Icons.check_box_rounded
                            : Icons.indeterminate_check_box_rounded),
                    color: _selection.isEmpty ? AppColors.textSecondary : AppColors.primary,
                  ),
                ),
                Text(
                  _selection.headerLabel(visiblePeople),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ],
            ),
          ),
          if (!_selection.isEmpty)
            TextButton(onPressed: () => setState(_selection.clear), child: const Text('Clear')),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _messageGroup(inStage),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text(_selection.buttonLabel(visiblePeople)),
          ),
        ],
      ),
    );
  }
}
