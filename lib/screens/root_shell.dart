import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/wishlist_service.dart';
import '../theme/app_theme.dart';
import 'home_swipe_screen.dart';
import 'profile_screen.dart';
import 'recruiter/hiring_pipeline_screen.dart';
import 'shortlist_screen.dart';
import 'wishlist_screen.dart';

/// Bottom-nav shell with five tabs: Discover (the full-screen swipe deck),
/// Wishlist, Shortlist, Pipeline (real candidates: interviews/offers) and
/// Profile. An IndexedStack keeps every tab's state alive (so the swipe
/// deck isn't lost) while switching between them.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  void _goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeSwipeScreen(onViewWishlist: () => _goTo(1)),
          const WishlistScreen(),
          const ShortlistScreen(),
          const HiringPipelineScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accent.withValues(alpha: 0.25),
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
              icon: Icon(Icons.style_outlined),
              selectedIcon: Icon(Icons.style_rounded),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: _CountBadge(listenable: WishlistService.instance.listenableShortlist(), icon: Icons.favorite_border_rounded, count: () => WishlistService.instance.shortlistCount),
              selectedIcon: _CountBadge(listenable: WishlistService.instance.listenableShortlist(), icon: Icons.favorite_rounded, count: () => WishlistService.instance.shortlistCount),
              label: 'Wishlist',
            ),
            NavigationDestination(
              icon: _CountBadge(listenable: WishlistService.instance.listenableFinalShortlist(), icon: Icons.playlist_add_check_outlined, count: () => WishlistService.instance.finalShortlistCount),
              selectedIcon: _CountBadge(listenable: WishlistService.instance.listenableFinalShortlist(), icon: Icons.playlist_add_check_rounded, count: () => WishlistService.instance.finalShortlistCount),
              label: 'Shortlist',
            ),
            const NavigationDestination(
              icon: Icon(Icons.business_center_outlined),
              selectedIcon: Icon(Icons.business_center_rounded),
              label: 'Pipeline',
            ),
            const NavigationDestination(
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

class _CountBadge extends StatelessWidget {
  final ValueListenable<Box<Map>> listenable;
  final IconData icon;
  final int Function() count;

  const _CountBadge({required this.listenable, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: listenable,
      builder: (context, _, _) {
        final n = count();
        return Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          backgroundColor: AppColors.like,
          child: Icon(icon),
        );
      },
    );
  }
}
