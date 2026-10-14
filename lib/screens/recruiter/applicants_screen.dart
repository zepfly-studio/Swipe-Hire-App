import 'package:flutter/material.dart';
import '../../models/job_posting.dart';
import '../../models/opportunity.dart';
import '../../services/job_posting_service.dart';
import '../../services/polling.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import 'pipeline_widgets.dart';

/// Everyone who applied to one posting, best match first, with the same
/// actions as the Pipeline tab (assign a task, review, schedule, chat).
class ApplicantsScreen extends StatefulWidget {
  final JobPosting posting;
  const ApplicantsScreen({super.key, required this.posting});

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  late final Stream<List<Applicant>> _stream =
      pollingStream(() => JobPostingService.instance.fetchApplicants(widget.posting.id));

  @override
  Widget build(BuildContext context) {
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Applicants', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(
                            widget.posting.title,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Applicant>>(
                  stream: _stream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError && !snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Could not load the applicants.\nCheck your connection; this will retry on its own.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
                    }
                    final applicants = snapshot.data!;
                    if (applicants.isEmpty) {
                      return FadeInUp(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No one has applied yet.\nYou will be notified as soon as someone does.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: applicants.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final a = applicants[index];
                        final o = a.opportunity;
                        return FadeInUp(
                          delay: Duration(milliseconds: 35 * (index < 8 ? index : 8)),
                          child: PipelineTile(
                            opportunity: o,
                            candidate: a.candidate,
                            onTap: () => openOpportunityEditor(context, existing: o),
                            onMove: (status) => moveOpportunity(context, o, status),
                            onAssignTask: () => assignTaskTo(context, o),
                            onReviewTask: (task) => reviewTaskOf(context, o, task: task),
                            onScheduleInterview: () =>
                                openOpportunityEditor(context, existing: o, initialStatus: OpportunityStatus.interviewScheduled),
                            onOpenChat: () => openChatWith(context, o),
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
}
