import 'package:flutter/material.dart';
import '../../models/opportunity.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// One recruiter interaction, shown as a status-colour-coded card --
/// reused by the Dashboard's "Recent Activity" preview and the full
/// Applications list.
class CandidateApplicationTile extends StatelessWidget {
  final Opportunity opportunity;
  const CandidateApplicationTile({super.key, required this.opportunity});

  Color get _statusColor => switch (opportunity.status) {
        OpportunityStatus.applied => AppColors.textSecondary,
        OpportunityStatus.shortlisted => AppColors.accentAlt,
        OpportunityStatus.interviewScheduled => const Color(0xFFFFB84D),
        OpportunityStatus.offered => AppColors.like,
        OpportunityStatus.hired => AppColors.like,
        OpportunityStatus.rejected => AppColors.reject,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opportunity.companyName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(opportunity.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        StatusBadge(status: opportunity.status),
                      ],
                    ),
                    if (opportunity.status == OpportunityStatus.interviewScheduled && opportunity.interviewDate != null) ...[
                      const Divider(height: 20, color: AppColors.border),
                      _DetailRow(icon: Icons.event_outlined, label: 'Interview', value: _formatDateTime(opportunity.interviewDate!)),
                      if (opportunity.interviewMode.isNotEmpty)
                        _DetailRow(icon: Icons.videocam_outlined, label: 'Mode', value: opportunity.interviewMode),
                      if (opportunity.interviewDetails.isNotEmpty)
                        _DetailRow(icon: Icons.link_rounded, label: 'Details', value: opportunity.interviewDetails),
                    ],
                    if (opportunity.status == OpportunityStatus.offered || opportunity.status == OpportunityStatus.hired) ...[
                      const Divider(height: 20, color: AppColors.border),
                      if (opportunity.offerSalaryLpa != null)
                        _DetailRow(
                          icon: Icons.payments_outlined,
                          label: 'Offered CTC',
                          value: '₹${opportunity.offerSalaryLpa!.toStringAsFixed(1)} LPA',
                        ),
                      if (opportunity.offerJoiningDate != null)
                        _DetailRow(icon: Icons.event_available_outlined, label: 'Joining date', value: _formatDate(opportunity.offerJoiningDate!)),
                      if (opportunity.offerNotes.isNotEmpty)
                        _DetailRow(icon: Icons.notes_rounded, label: 'Notes', value: opportunity.offerNotes),
                    ],
                    if (opportunity.recruiterName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Contact: ${opportunity.recruiterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _formatDateTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${_formatDate(d)}, $hour:$minute $period';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.accentAlt),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
