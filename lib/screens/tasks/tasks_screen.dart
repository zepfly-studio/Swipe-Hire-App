import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/pair/hiring_task.dart';
import '../../services/api_client.dart';
import '../../services/hiring_task_service.dart';
import '../../services/pair_session.dart';
import '../../services/visible_poller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../messages/pair_nav.dart';
import '../messages/pair_widgets.dart';
import 'task_card.dart';

/// Take-home tasks for BOTH roles (submit for candidates, change deadline /
/// cancel for companies). Polled every 30 s while visible.
class TasksScreen extends StatefulWidget {
  /// Whether the signed-in account is a company; when null it is looked up.
  final bool? isCompany;
  const TasksScreen({super.key, this.isCompany});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final VisiblePoller _poller;
  bool? _isCompany;
  List<HiringTask>? _tasks;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _isCompany = widget.isCompany;
    _poller = VisiblePoller(interval: const Duration(seconds: 30), onTick: _load)..start();
    if (_isCompany == null) _resolveRole();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setVisible(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _resolveRole() async {
    try {
      final user = await PairSession.instance.user();
      if (!mounted) return;
      setState(() => _isCompany = user != null && user.role == UserRole.recruiter);
    } catch (_) {
      if (mounted) setState(() => _isCompany = false);
    }
  }

  Future<void> _load() async {
    try {
      final list = await HiringTaskService.instance.list();
      if (!mounted) return;
      setState(() {
        _tasks = list;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_tasks == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _tasks == null) setState(() => _error = 'Could not load your tasks.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompany = _isCompany;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PairHeader(
                title: 'Tasks',
                subtitle: isCompany == true
                    ? 'Assignments you sent to shortlisted candidates. Send one from the Shortlisted page.'
                    : 'Assignments from companies. Submit your live link and GitHub repo before the deadline.',
              ),
              Expanded(child: isCompany == null ? const Center(child: CircularProgressIndicator(color: AppColors.accentAlt)) : _body(isCompany)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool isCompany) {
    final tasks = _tasks;
    if (tasks == null) {
      if (_error != null) {
        return PairErrorState(
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _load();
          },
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    }
    if (tasks.isEmpty) {
      return PairEmptyState(
        icon: Icons.assignment_outlined,
        title: isCompany ? 'No tasks sent yet.' : 'No tasks yet.',
        message: isCompany ? null : 'When a company sends you one, it shows up here.',
        actionLabel: isCompany ? 'Open shortlisted' : null,
        onAction: isCompany ? () => PairNav.openShortlisted(context) : null,
      );
    }
    final now = DateTime.now();
    // Candidates never see cancelled tasks; the company does (in All).
    final visible = isCompany ? tasks : tasks.where((t) => !t.isCancelled).toList();
    final counts = taskFilterCounts(visible, now: now);
    final shown = filterTasks(visible, _filter, now: now);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in kTaskFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${taskFilterLabel(f)} ${counts[f] ?? 0}'),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _filter == f ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nothing here.', style: TextStyle(color: AppColors.textSecondary))),
            )
          else
            for (final t in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TaskCard(key: ValueKey(t.id), task: t, isCompany: isCompany, onChanged: _load),
              ),
        ],
      ),
    );
  }
}
