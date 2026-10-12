import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate_profile.dart';
import '../../services/auth_service.dart';
import '../../services/candidate_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import 'candidate_applications_screen.dart';
import 'candidate_dashboard_screen.dart';
import 'candidate_jobs_screen.dart';
import 'candidate_profile_screen.dart';
import 'candidate_saved_jobs_screen.dart';

/// Bottom-nav shell for a candidate account: Dashboard, Browse Jobs, My
/// Applications, Saved and Profile. Mirrors the recruiter's [RootShell]
/// pattern -- an IndexedStack keeps each tab's scroll position alive while
/// switching.
class CandidateRootShell extends StatefulWidget {
  final AppUser user;
  const CandidateRootShell({super.key, required this.user});

  @override
  State<CandidateRootShell> createState() => _CandidateRootShellState();
}

class _CandidateRootShellState extends State<CandidateRootShell> {
  int _index = 0;
  late Future<CandidateProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = CandidateProfileService.instance.fetch(widget.user.uid);
  }

  void _goTo(int index) => setState(() => _index = index);

  void _onProfileUpdated(CandidateProfile updated) {
    setState(() => _profileFuture = Future.value(updated));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Profile updated'),
        backgroundColor: AppColors.surfaceAlt,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: FutureBuilder<CandidateProfile?>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
              }
              final profile = snapshot.data;
              if (profile == null) {
                return _MissingProfileState(user: widget.user);
              }
              return IndexedStack(
                index: _index,
                children: [
                  CandidateDashboardScreen(user: widget.user, profile: profile, onViewAllApplications: () => _goTo(2)),
                  CandidateJobsScreen(user: widget.user),
                  CandidateApplicationsScreen(user: widget.user),
                  CandidateSavedJobsScreen(user: widget.user),
                  CandidateProfileScreen(user: widget.user, profile: profile, onProfileUpdated: _onProfileUpdated),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accent.withValues(alpha: 0.25),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? AppColors.accentAlt : AppColors.textSecondary);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(color: selected ? AppColors.accentAlt : AppColors.textSecondary);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.work_outline_rounded), selectedIcon: Icon(Icons.work_rounded), label: 'Jobs'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: 'Applications'),
            NavigationDestination(icon: Icon(Icons.bookmark_border_rounded), selectedIcon: Icon(Icons.bookmark_rounded), label: 'Saved'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

/// Defensive fallback: a signed-in candidate whose profile doc is missing
/// (e.g. deleted directly in Firestore) instead of a blank/broken screen.
class _MissingProfileState extends StatelessWidget {
  final AppUser user;
  const _MissingProfileState({required this.user});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: FadeInUp(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text('We could not find your profile', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => AuthService.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
