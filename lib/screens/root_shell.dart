import 'dart:async';

import 'package:flutter/material.dart';

import '../models/hiring_company.dart';
import '../services/account_flags.dart';
import '../services/hiring_service.dart';
import '../services/polling.dart';
import '../services/recruiter_profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_nav.dart';
import '../widgets/notification_bell.dart';
import 'account/account_security_screen.dart';
import 'admin/admin_screen.dart';
import 'interviews/interviews_screen.dart';
import 'messages/messages_screen.dart';
import 'profile_screen.dart';
import 'recruiter/company_profile_screen.dart';
import 'recruiter/jobs/jobs_screen.dart';
import 'recruiter/onboarding/company_onboarding_screen.dart';
import 'recruiter/plans/plans_screen.dart';
import 'recruiter/shortlisted_screen.dart';
import 'recruiter/swipe/swipe_screen.dart';
import 'recruiter/team/team_screen.dart';
import 'recruiter/verify/verify_company_screen.dart';
import 'recruiter/wishlist_screen.dart';
import 'tasks/tasks_screen.dart';

/// The company's shell: header (title, swipe counter, bell, avatar menu) and
/// five bottom tabs -- Swipe, Jobs, Shortlisted, Messages, Interviews.
/// Tabs are built on first visit and then kept alive (IndexedStack).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  static const Duration _unreadEvery = Duration(seconds: 15);

  int _index = 0;
  final Set<int> _visited = {0};
  int _unread = 0;
  bool _foreground = true;
  Timer? _unreadTimer;
  bool _onboardingShown = false;

  /// Job the Shortlisted tab should filter by (Jobs screen "Shortlisted").
  String? _shortlistJobId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNav.recruiterTab.addListener(_onTabRequest);
    HiringService.pendingShortlistedJobId.addListener(_onShortlistJob);
    _unreadTimer = Timer.periodic(_unreadEvery, (_) => _pollUnread());
    _pollUnread();
    _loadCompany();
    AccountFlagsService.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNav.recruiterTab.removeListener(_onTabRequest);
    HiringService.pendingShortlistedJobId.removeListener(_onShortlistJob);
    _unreadTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _pollUnread();
  }

  void _onTabRequest() {
    final i = AppNav.recruiterTab.value;
    if (i == null) return;
    AppNav.recruiterTab.value = null;
    if (i >= 0 && i < 5) _goTo(i);
  }

  void _onShortlistJob() {
    final id = HiringService.pendingShortlistedJobId.value;
    if (id == null) return;
    HiringService.pendingShortlistedJobId.value = null;
    setState(() => _shortlistJobId = id);
  }

  void _goTo(int i) {
    setState(() {
      _index = i;
      _visited.add(i);
    });
    if (i == AppNav.recruiterMessages) _pollUnread();
  }

  Future<void> _pollUnread() async {
    if (!_foreground || !mounted) return;
    try {
      final n = await HiringService.instance.unreadMessageCount();
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {
      // A flaky connection must never surface as an error.
    }
  }

  /// Loads the company (swipe balance for the header pill). A recruiter whose
  /// account is complete but who has no company yet is sent through onboarding.
  Future<void> _loadCompany() async {
    try {
      final res = await HiringService.instance.fetchCompany();
      if (!mounted || res.company != null || _onboardingShown) return;
      _onboardingShown = true;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (routeContext) => CompanyOnboardingScreen(
            userName: RecruiterProfileService.instance.name,
            onFinished: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
      _onboardingShown = false;
      if (mounted) {
        await HiringService.instance.fetchCompany();
        // Open lists (jobs, swipe stack) re-read the new company's data.
        DataRefresh.instance.bump();
      }
    } catch (_) {
      // Offline: the pill stays empty and the swipe tab shows its own error.
    }
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) {
        void go(Widget page) {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
        }

        return SafeArea(
          child: ValueListenableBuilder<AccountFlags?>(
            valueListenable: AccountFlagsService.current,
            builder: (context, _, _) => ValueListenableBuilder<HiringCompany?>(
              valueListenable: HiringService.company,
              builder: (context, company, _) {
              final name = RecruiterProfileService.instance.name;
              final isAdmin = AccountFlagsService.forCurrentUser()?.isAdmin == true;
              return SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text(
                        (name.isEmpty ? (company?.name ?? 'R') : name).substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(name.isEmpty ? 'Recruiter' : name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(company?.name ?? ''),
                    trailing: company?.verified == true
                        ? const Icon(Icons.verified_rounded, color: AppColors.info)
                        : null,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.favorite_border_rounded),
                    title: const Text('Wishlist'),
                    onTap: () => go(const WishlistScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.task_alt_rounded),
                    title: const Text('Tasks'),
                    onTap: () => go(const TasksScreen(isCompany: true)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bolt_rounded),
                    title: const Text('Plans & swipes'),
                    onTap: () => go(const PlansScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.apartment_rounded),
                    title: const Text('Company profile'),
                    onTap: () => go(const CompanyProfileScreen()),
                  ),
                  ListTile(
                    leading: Icon(
                      company?.verified == true ? Icons.verified_rounded : Icons.shield_outlined,
                      color: company?.verified == true ? AppColors.info : null,
                    ),
                    title: Text(company?.verified == true ? 'Verified company' : 'Get verified badge'),
                    onTap: () => go(const VerifyCompanyScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('Team'),
                    onTap: () => go(const TeamScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('Account'),
                    onTap: () => go(
                      Scaffold(
                        appBar: AppBar(title: const Text('Account')),
                        body: const ProfileScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: const Text('Account security'),
                    onTap: () => go(const AccountSecurityScreen()),
                  ),
                  if (isAdmin)
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Admin'),
                      onTap: () => go(const AdminScreen()),
                    ),
                ],
                ),
              );
            },
            ),
          ),
        );
      },
    );
  }

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => const SwipeScreen(),
      1 => const JobsScreen(),
      2 => ShortlistedScreen(initialJobId: _shortlistJobId),
      3 => const MessagesScreen(isCompany: true),
      _ => const InterviewsScreen(isCompany: true),
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgTop,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Swipe and Jobs have no header of their own; the pair screens
              // draw their own title + bell, so they only get a slim strip.
              _Header(onMenu: _openMenu, showBell: _index <= 1),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [for (var i = 0; i < 5; i++) _tab(i)],
                ),
              ),
            ],
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
              return IconThemeData(color: selected ? AppColors.accentAlt : AppColors.textSecondary);
            }),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _goTo,
            height: 64,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.layers_outlined),
                selectedIcon: Icon(Icons.layers_rounded),
                label: 'Swipe',
              ),
              const NavigationDestination(
                icon: Icon(Icons.work_outline_rounded),
                selectedIcon: Icon(Icons.work_rounded),
                label: 'Jobs',
              ),
              const NavigationDestination(
                icon: Icon(Icons.verified_outlined),
                selectedIcon: Icon(Icons.verified_rounded),
                label: 'Shortlisted',
              ),
              NavigationDestination(
                icon: _badge(const Icon(Icons.chat_bubble_outline_rounded)),
                selectedIcon: _badge(const Icon(Icons.chat_bubble_rounded)),
                label: 'Messages',
              ),
              const NavigationDestination(
                icon: Icon(Icons.event_outlined),
                selectedIcon: Icon(Icons.event_rounded),
                label: 'Interviews',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(Widget icon) => Badge(
        isLabelVisible: _unread > 0,
        label: Text(_unread > 9 ? '9+' : '$_unread'),
        backgroundColor: AppColors.like,
        child: icon,
      );
}

class _Header extends StatelessWidget {
  final VoidCallback onMenu;
  final bool showBell;
  const _Header({required this.onMenu, required this.showBell});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: showBell ? 56 : 48,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'GlideRecruit',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary),
          ),
          const Spacer(),
          const _SwipeCounter(),
          if (showBell) const NotificationBell(),
          IconButton(
            tooltip: 'Menu',
            onPressed: onMenu,
            icon: const Icon(Icons.account_circle_outlined, size: 28),
          ),
        ],
      ),
    );
  }
}

class _SwipeCounter extends StatelessWidget {
  const _SwipeCounter();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HiringService.swipesLeft,
      builder: (context, n, _) {
        final empty = n == 0;
        final color = empty ? AppColors.reject : AppColors.primary;
        return Semantics(
          button: true,
          label: 'Swipes left',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen())),
            child: Tooltip(
              message: 'Swipes left',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 18, color: color),
                    const SizedBox(width: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        n < 0 ? '–' : '$n',
                        key: ValueKey(n),
                        style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
