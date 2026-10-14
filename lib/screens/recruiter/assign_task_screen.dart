import 'package:flutter/material.dart';
import '../../models/opportunity.dart';
import '../../services/api_client.dart';
import '../../services/error_reporter.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';
import '../../widgets/app_toast.dart';

/// Recruiter assigns a small assessment task to a shortlisted candidate.
/// The candidate gets it in their Applications tab (plus a push and a chat
/// message), submits an answer or a link, and the recruiter reviews it
/// before scheduling the interview. Pops `true` once the task is sent.
class AssignTaskScreen extends StatefulWidget {
  final Opportunity opportunity;
  const AssignTaskScreen({super.key, required this.opportunity});

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _TaskTemplate {
  final String label;
  final String title;
  final String description;
  const _TaskTemplate(this.label, this.title, this.description);
}

const _templates = [
  _TaskTemplate(
    'Mini project',
    'Build a small feature',
    'Build a small working example of the feature below and share a link to the code or a short demo video.\n\nWhat to include: a working screen, clean code, and a note on any trade-offs you made.',
  ),
  _TaskTemplate(
    'Case question',
    'Short written case',
    'Describe in 200 to 300 words how you would approach the problem below, step by step, and what you would check before shipping.',
  ),
  _TaskTemplate(
    'Portfolio review',
    'Share your best work',
    'Share one or two links to work you are proud of. For each, tell us your role and what you would do differently today.',
  ),
];

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _link = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 3));
  bool _sending = false;
  bool _saveAsTemplate = false;
  List<TaskTemplate> _saved = const [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await OpportunityService.instance.fetchTemplates();
      if (mounted) setState(() => _saved = templates);
    } catch (e, stackTrace) {
      // Saved templates are a convenience; the built-in ones still work.
      ErrorReporter.report(e, stackTrace, reason: 'AssignTaskScreen: load templates failed');
    }
  }

  void _applySaved(TaskTemplate t) {
    setState(() {
      _title.text = t.title;
      _description.text = t.description;
      _link.text = t.link;
      _saveAsTemplate = false;
    });
  }

  Future<void> _deleteSaved(TaskTemplate t) async {
    setState(() => _saved = _saved.where((x) => x.id != t.id).toList());
    try {
      await OpportunityService.instance.deleteTemplate(t.id);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'AssignTaskScreen: delete template failed');
      if (!mounted) return;
      AppToast.error('Could not delete that template');
      _loadTemplates();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  void _applyTemplate(_TaskTemplate t) {
    setState(() {
      _title.text = t.title;
      _description.text = t.description;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      // End of the chosen day, so "due Friday" really means Friday night.
      setState(() => _dueDate = DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await OpportunityService.instance.assignTask(
        widget.opportunity.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        link: _link.text.trim(),
        dueDate: _dueDate,
        saveAsTemplate: _saveAsTemplate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'AssignTaskScreen: assign failed');
      if (!mounted) return;
      _showError('Could not send the task. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String message) {
    AppToast.error(message);
  }

  String _formatDay(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
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

  @override
  Widget build(BuildContext context) {
    final o = widget.opportunity;
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
                    IconButton(onPressed: () => Navigator.of(context).pop(false), icon: const Icon(Icons.arrow_back_rounded)),
                    Expanded(
                      child: Text('Assign a task', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeInUp(
                          child: Text(
                            'For ${o.candidateName}${o.role.isEmpty ? '' : ' · ${o.role}'}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeInUp(
                          delay: const Duration(milliseconds: 30),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in _saved)
                                InputChip(
                                  label: Text(t.title),
                                  avatar: const Icon(Icons.bookmark_rounded, size: 15, color: AppColors.accent),
                                  onPressed: () => _applySaved(t),
                                  onDeleted: () => _deleteSaved(t),
                                  deleteIcon: const Icon(Icons.close_rounded, size: 15),
                                  backgroundColor: AppColors.accent.withValues(alpha: 0.10),
                                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
                                ),
                              for (final t in _templates)
                                ActionChip(
                                  label: Text(t.label),
                                  avatar: const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.accentAlt),
                                  onPressed: () => _applyTemplate(t),
                                  backgroundColor: AppColors.surface,
                                  side: const BorderSide(color: AppColors.border),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeInUp(
                          delay: const Duration(milliseconds: 60),
                          child: TextFormField(
                            controller: _title,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _decoration('Task title', Icons.assignment_outlined),
                            validator: (v) => (v == null || v.trim().length < 3) ? 'Give the task a short title' : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeInUp(
                          delay: const Duration(milliseconds: 90),
                          child: TextFormField(
                            controller: _description,
                            minLines: 4,
                            maxLines: 8,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _decoration('What should the candidate do?', Icons.notes_rounded),
                            validator: (v) => (v == null || v.trim().length < 10) ? 'Explain the task in a sentence or two' : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeInUp(
                          delay: const Duration(milliseconds: 120),
                          child: TextFormField(
                            controller: _link,
                            keyboardType: TextInputType.url,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _decoration('Reference link (optional)', Icons.link_rounded),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return null;
                              return RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(value)
                                  ? null
                                  : 'Start the link with http:// or https://';
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeInUp(
                          delay: const Duration(milliseconds: 150),
                          child: SectionCard(
                            title: 'Due date',
                            icon: Icons.event_outlined,
                            child: OutlinedButton.icon(
                              onPressed: _pickDueDate,
                              icon: const Icon(Icons.calendar_today_outlined, size: 16),
                              label: Text(_formatDay(_dueDate)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FadeInUp(
                          delay: const Duration(milliseconds: 165),
                          child: SwitchListTile(
                            value: _saveAsTemplate,
                            onChanged: (v) => setState(() => _saveAsTemplate = v),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Save as a template', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: const Text('Reuse it for other candidates', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeInUp(
                          delay: const Duration(milliseconds: 180),
                          child: FilledButton.icon(
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : const Icon(Icons.send_rounded, size: 18),
                            label: const Text('Send task to candidate'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'The candidate is notified right away. When they submit, you review it here and then schedule the interview.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
