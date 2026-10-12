import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate.dart';
import '../../models/candidate_profile.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/candidate_card_face.dart';
import '../../widgets/fade_in_up.dart';
import '../auth/account_actions.dart';
import '../auth/complete_profile_screen.dart';
import '../resume_screen.dart';
import '../video_intro_screen.dart';

/// The candidate's "Profile" tab: avatar, a profile-completion bar, and a
/// settings-style list of detail rows -- tapping any of them (other than
/// "Log out") opens the same editable form on [CompleteProfileScreen].
class CandidateProfileScreen extends StatelessWidget {
  final AppUser user;
  final CandidateProfile profile;
  final ValueChanged<CandidateProfile> onProfileUpdated;

  const CandidateProfileScreen({
    super.key,
    required this.user,
    required this.profile,
    required this.onProfileUpdated,
  });

  Future<void> _edit(BuildContext context) async {
    final updated = await Navigator.of(context).push<CandidateProfile>(
      MaterialPageRoute(builder: (_) => CompleteProfileScreen(user: user, existingCandidateProfile: profile)),
    );
    if (updated == null) return;
    onProfileUpdated(updated);
  }

  /// The same [Candidate] shape recruiters see on the swipe deck, built
  /// from this account's own data -- lets the candidate preview their
  /// resume/intro video with the exact same viewer screens recruiters use.
  Candidate get _asCandidate {
    return Candidate(
      id: user.uid,
      name: user.name,
      age: profile.age,
      qualification: profile.qualification,
      experience: profile.experience,
      role: profile.desiredRole,
      location: profile.location,
      currentCompany: profile.currentCompany,
      currentSalaryLpa: profile.currentSalaryLpa,
      expectedSalaryLpa: profile.expectedSalaryLpa,
      skills: profile.skills,
      photoUrl: profile.photoUrl,
      resumeUrl: profile.resumeUrl,
      introVideoUrl: profile.introVideoUrl,
      about: profile.about,
      noticePeriod: profile.noticePeriod,
    );
  }

  void _viewResume(BuildContext context) {
    if (profile.resumeUrl.isEmpty) {
      _edit(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResumeScreen(candidate: _asCandidate)));
  }

  void _viewIntroVideo(BuildContext context) {
    if (profile.introVideoUrl.isEmpty) {
      _edit(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoIntroScreen(candidate: _asCandidate)));
  }

  int get _completionPercent {
    final fields = <bool>[
      profile.age > 0,
      profile.qualification.isNotEmpty,
      profile.experience.isNotEmpty,
      profile.desiredRole.isNotEmpty,
      profile.location.isNotEmpty,
      profile.skills.isNotEmpty,
      profile.expectedSalaryLpa > 0,
      profile.noticePeriod.isNotEmpty,
      profile.about.isNotEmpty,
    ];
    final filled = fields.where((f) => f).length;
    return ((filled / fields.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        FadeInUp(
          child: Row(
            children: [
              SizedBox(width: 64, height: 64, child: ClipOval(child: InitialsAvatar(name: user.name))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(user.email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.edit_outlined, color: AppColors.accentAlt),
                tooltip: 'Edit profile',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FadeInUp(delay: const Duration(milliseconds: 40), child: _buildCompletionBar()),
        const SizedBox(height: 20),
        FadeInUp(
          delay: const Duration(milliseconds: 80),
          child: _DetailTile(
            icon: Icons.badge_outlined,
            label: 'Personal Information',
            value: '${profile.age > 0 ? '${profile.age} yrs' : 'Age not set'} · ${profile.location.isEmpty ? 'Location not set' : profile.location}',
            onTap: () => _edit(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 110),
          child: _DetailTile(
            icon: Icons.work_outline_rounded,
            label: 'Professional Details',
            value: '${profile.desiredRole.isEmpty ? 'Role not set' : profile.desiredRole} · ${profile.experience.isEmpty ? '-' : profile.experience}'
                '${profile.currentCompany.isEmpty ? '' : ' · currently at ${profile.currentCompany}'}',
            onTap: () => _edit(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 140),
          child: _DetailTile(
            icon: Icons.school_outlined,
            label: 'Education',
            value: profile.qualification.isEmpty ? 'Not added' : profile.qualification,
            onTap: () => _edit(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 170),
          child: _DetailTile(
            icon: Icons.auto_awesome_outlined,
            label: 'Skills',
            value: profile.skills.isEmpty ? 'Not added' : profile.skills.join(', '),
            onTap: () => _edit(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 200),
          child: _DetailTile(
            icon: Icons.payments_outlined,
            label: 'Preferences',
            value: '${profile.expectedSalaryLpa > 0 ? '₹${profile.expectedSalaryLpa.toStringAsFixed(1)} LPA' : 'CTC not set'} · ${profile.noticePeriod.isEmpty ? 'Notice period not set' : profile.noticePeriod}',
            onTap: () => _edit(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 230),
          child: _DetailTile(
            icon: Icons.description_outlined,
            label: 'Resume',
            value: profile.resumeUrl.isEmpty ? 'Not uploaded -- tap to add' : 'Uploaded · tap to view',
            iconColor: profile.resumeUrl.isEmpty ? AppColors.accentAlt : AppColors.like,
            onTap: () => _viewResume(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 260),
          child: _DetailTile(
            icon: Icons.videocam_outlined,
            label: 'Intro Video',
            value: profile.introVideoUrl.isEmpty ? 'Not uploaded -- tap to add' : 'Uploaded · tap to watch',
            iconColor: profile.introVideoUrl.isEmpty ? AppColors.accentAlt : AppColors.like,
            onTap: () => _viewIntroVideo(context),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 290),
          child: _DetailTile(
            icon: Icons.download_outlined,
            label: 'Export my data',
            value: '',
            onTap: () => showExportDataDialog(context),
          ),
        ),
        const SizedBox(height: 8),
        FadeInUp(
          delay: const Duration(milliseconds: 320),
          child: _DetailTile(
            icon: Icons.logout_rounded,
            label: 'Log out',
            value: '',
            iconColor: AppColors.reject,
            labelColor: AppColors.reject,
            onTap: () => AuthService.instance.signOut(),
          ),
        ),
        FadeInUp(
          delay: const Duration(milliseconds: 350),
          child: _DetailTile(
            icon: Icons.delete_forever_outlined,
            label: 'Delete account',
            value: '',
            iconColor: AppColors.reject,
            labelColor: AppColors.reject,
            onTap: () => confirmAndDeleteAccount(context),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionBar() {
    final percent = _completionPercent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Profile Completion', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
              Text('$percent%', style: const TextStyle(color: AppColors.accentAlt, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: const AlwaysStoppedAnimation(AppColors.like),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                Icon(icon, size: 19, color: iconColor ?? AppColors.accentAlt),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: labelColor)),
                      if (value.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(value, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                if (labelColor == null) const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
