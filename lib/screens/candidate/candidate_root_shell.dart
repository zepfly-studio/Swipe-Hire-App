import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate_profile.dart';
import '../../services/auth_service.dart';
import '../../services/candidate_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../../utils/app_nav.dart';
import '../interviews/interviews_screen.dart';
import '../messages/messages_screen.dart';
import '../tasks/tasks_screen.dart';
import 'candidate_home_screen.dart';
import 'candidate_profile_screen.dart';
import 'onboarding/candidate_onboarding_screen.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/notification_bell.dart';

/// Bottom-nav shell for a candidate account (tab order is [AppNav]'s
/// candidate tabs): Home, Messages (unread badge), Tasks, Interviews and
/// Profile. An IndexedStack keeps each tab's state alive while switching;
/// the pair screens poll only while their tab is the visible one.
class CandidateRootShell extends StatefulWidget {
  final AppUser user;
  const CandidateRootShell({super.key, required this.user});

  @override
  State<CandidateRootShell> createState() => _CandidateRootShellState();
}

class _CandidateRootShellState extends State<CandidateRootShell> {
  int _index = AppNav.candidateHome;
  late Future<CandidateProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = CandidateProfileService.instance.fetch(widget.user.uid);
    AppNav.candidateTab.addListener(_onTabRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTabRequest());
  }

  @override
  void dispose() {
    AppNav.candidateTab.removeListener(_onTabRequest);
    super.dispose();
  }

  /// A notification tap / "Message" button asked for a tab: show it, then
  /// reset the request.
  void _onTabRequest() {
    final requested = AppNav.candidateTab.value;
    if (requested == null || !mounted) return;
    AppNav.candidateTab.value = null;
    if (requested >= AppNav.candidateHome && requested <= AppNav.candidateProfile) {
      setState(() => _index = requested);
    }
  }

  void _goTo(int index) => setState(() => _index = index);

  /// A profile change made on the Home tab (preferences, "I'm active").
  void _onProfileChanged(CandidateProfile updated) {
    setState(() => _profileFuture = Future.value(updated));
  }

  /// A profile saved through the edit flow.
  void _onProfileUpdated(CandidateProfile updated) {
    setState(() => _profileFuture = Future.value(updated));
    AppToast.success(
      'Profile updated',
      description: 'Companies see your latest details on their swipe deck.',
    );
  }

  Future<void> _editProfile(CandidateProfile current) async {
    final updated = await Navigator.of(context).push<CandidateProfile>(
      MaterialPageRoute(
        builder: (_) => CandidateOnboardingScreen(
          user: widget.user,
          existingProfile: current,
        ),
      ),
    );
    if (updated != null) _onProfileUpdated(updated);
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
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accentAlt),
                );
              }
              final profile = snapshot.data;
              if (profile == null) {
                return _MissingProfileState(user: widget.user);
              }
              return IndexedStack(
                index: _index,
                children: [
                  CandidateHomeScreen(
                    user: widget.user,
                    profile: profile,
                    onProfileChanged: _onProfileChanged,
                    onEditProfile: () => _editProfile(profile),
                  ),
                  const MessagesScreen(isCompany: false),
                  const TasksScreen(isCompany: false),
                  const InterviewsScreen(isCompany: false),
                  CandidateProfileScreen(
                    user: widget.user,
                    profile: profile,
                    onProfileUpdated: _onProfileUpdated,
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.accentAlt : AppColors.textSecondary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? AppColors.accentAlt : AppColors.textSecondary,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          height: 64,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: UnreadChatIcon(icon: Icons.chat_bubble_outline_rounded),
              selectedIcon: UnreadChatIcon(icon: Icons.chat_bubble_rounded),
              label: 'Messages',
            ),
            NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment_rounded),
              label: 'Tasks',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event_rounded),
              label: 'Interviews',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Defensive fallback: a signed-in candidate whose profile doc is missing
/// (e.g. deleted directly in the database) instead of a blank/broken screen.
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
              const Icon(
                Icons.person_off_outlined,
                size: 56,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              const Text(
                'We could not find your profile',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
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
