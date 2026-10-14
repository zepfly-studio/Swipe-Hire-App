import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/candidate.dart';
import '../models/opportunity.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/opportunity_service.dart';
import '../services/recruiter_profile_service.dart';
import '../services/wishlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/page_transitions.dart';
import 'recruiter/assign_task_screen.dart';
import 'resume_screen.dart';
import 'video_intro_screen.dart';
import '../widgets/app_toast.dart';

/// Shortlist tab: candidates promoted from the Wishlist for final hiring
/// consideration (stored on the backend, so it's the same on every
/// device). Swiping a tile away (or tapping the undo icon) sends the
/// candidate back to the Wishlist rather than discarding them. Tapping
/// "Assign a task" puts the candidate in Hiring > Pipeline (or reuses the
/// entry they already have from a job application) and sends them a task
/// to complete; once they submit it, the recruiter reviews it there and
/// then schedules the interview. "Send to Pipeline" does the first half
/// only, with no task.
class ShortlistScreen extends StatelessWidget {
  const ShortlistScreen({super.key});

  /// Makes sure this candidate has a pipeline entry with the signed-in
  /// recruiter and returns it (with its id). An existing entry is reused as
  /// is: an applicant moves from "Applied" to "Shortlisted", and anyone
  /// further along keeps the stage they are already at.
  Future<Opportunity> _ensurePipelineEntry(Candidate candidate) async {
    final recruiterUid = AuthService.instance.currentUid;
    final recruiter = RecruiterProfileService.instance;

    final existing = await OpportunityService.instance.findExistingBetween(recruiterUid, candidate.id);
    if (existing != null) {
      if (existing.status != OpportunityStatus.applied) return existing;
      final moved = existing.copyWithStatus(OpportunityStatus.shortlisted);
      await OpportunityService.instance.save(moved);
      return moved;
    }

    final created = Opportunity(
      candidateUid: candidate.id,
      candidateName: candidate.name,
      recruiterUid: recruiterUid,
      companyName: recruiter.company.isEmpty ? 'Hiring company' : recruiter.company,
      recruiterName: recruiter.name,
      role: candidate.role,
      status: OpportunityStatus.shortlisted,
    );
    final id = await OpportunityService.instance.save(created);
    return Opportunity(
      id: id,
      candidateUid: created.candidateUid,
      candidateName: created.candidateName,
      recruiterUid: created.recruiterUid,
      companyName: created.companyName,
      recruiterName: created.recruiterName,
      role: created.role,
      status: OpportunityStatus.shortlisted,
    );
  }

  void _snack(BuildContext context, String message, {bool error = false}) {
    error ? AppToast.error(message) : AppToast.success(message);
  }

  Future<void> _sendToPipeline(BuildContext context, Candidate candidate) async {
    try {
      await _ensurePipelineEntry(candidate);
      await WishlistService.instance.removeFromShortlist(candidate.id);
      if (!context.mounted) return;
      AppToast.success('Sent to Pipeline', description: '${candidate.name} is in Hiring > Pipeline. Assign a task or schedule an interview there.');
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'ShortlistScreen: send to pipeline failed');
      if (!context.mounted) return;
      _snack(context, 'Could not send to Pipeline. Please try again.', error: true);
    }
  }

  /// Shortlist -> task: puts the candidate in the pipeline (if needed),
  /// then opens the task form. The candidate leaves the shortlist only once
  /// the task has actually been sent.
  Future<void> _assignTask(BuildContext context, Candidate candidate) async {
    try {
      final opportunity = await _ensurePipelineEntry(candidate);
      if (!context.mounted) return;
      final past = opportunity.status == OpportunityStatus.interviewScheduled ||
          opportunity.status == OpportunityStatus.offered ||
          opportunity.status == OpportunityStatus.hired ||
          opportunity.status == OpportunityStatus.rejected;
      if (past) {
        AppToast.warning('Cannot assign a task', description: '${candidate.name} is already at "${opportunity.status.label}".');
        return;
      }
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AssignTaskScreen(opportunity: opportunity)),
      );
      if (sent != true) return;
      await WishlistService.instance.removeFromShortlist(candidate.id);
      if (!context.mounted) return;
      AppToast.success('Task sent', description: '${candidate.name} has been notified. Their submission will show up in Hiring > Pipeline.');
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'ShortlistScreen: assign task failed');
      if (!context.mounted) return;
      _snack(context, 'Could not assign the task. Please try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  'Shortlist',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: WishlistService.instance.listenableFinalShortlist(),
                  builder: (context, _, _) {
                    final shortlisted = WishlistService.instance.getFinalShortlist();
                    if (shortlisted.isEmpty) {
                      return FadeInUp(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No one shortlisted yet.\nMove a candidate here from your Wishlist when you\'re ready to move forward with them.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: shortlisted.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final candidate = shortlisted[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 50 * index),
                          child: _ShortlistTile(
                            candidate: candidate,
                            onDemote: () => WishlistService.instance.demoteToWishlist(candidate),
                            onSendToPipeline: () => _sendToPipeline(context, candidate),
                            onAssignTask: () => _assignTask(context, candidate),
                            onResume: () => pushSmooth(context, ResumeScreen(candidate: candidate)),
                            onVideo: () => pushSmooth(context, VideoIntroScreen(candidate: candidate)),
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

class _ShortlistTile extends StatelessWidget {
  final Candidate candidate;
  final VoidCallback onDemote;
  final VoidCallback onSendToPipeline;
  final VoidCallback onAssignTask;
  final VoidCallback onResume;
  final VoidCallback onVideo;

  const _ShortlistTile({
    required this.candidate,
    required this.onDemote,
    required this.onSendToPipeline,
    required this.onAssignTask,
    required this.onResume,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(candidate.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDemote(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.undo_rounded, color: Colors.white),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.like.withValues(alpha: 0.4)),
          boxShadow: AppColors.cardShadow(),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 60,
                height: 60,
                child: Hero(
                  tag: candidatePhotoHeroTag(candidate.id),
                  child: candidate.photoUrl.isEmpty
                      ? InitialsAvatar(name: candidate.name)
                      : CachedNetworkImage(
                          imageUrl: candidate.photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => InitialsAvatar(name: candidate.name),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 14, color: AppColors.like),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(candidate.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${candidate.role} · ${candidate.experience}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(onPressed: onResume, icon: const Icon(Icons.description_outlined), tooltip: 'Resume', iconSize: 20),
            IconButton(onPressed: onVideo, icon: const Icon(Icons.play_circle_outline), tooltip: 'Intro video', iconSize: 20),
            IconButton(
              onPressed: onDemote,
              icon: const Icon(Icons.undo_rounded, color: AppColors.accentAlt),
              tooltip: 'Move back to Wishlist',
              iconSize: 20,
            ),
            IconButton(
              onPressed: onSendToPipeline,
              icon: const Icon(Icons.send_rounded, color: AppColors.textSecondary),
              tooltip: 'Send to Pipeline without a task',
              iconSize: 20,
            ),
            IconButton(
              onPressed: onAssignTask,
              icon: const Icon(Icons.assignment_add, color: AppColors.like),
              tooltip: 'Assign a task',
              iconSize: 22,
            ),
          ],
        ),
      ),
    );
  }
}
