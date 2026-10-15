import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import 'auth/auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.elasticOut,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, animation, _) => FadeTransition(
            opacity: animation,
            child: const AuthGate(),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo_mark.png', width: 148, filterQuality: FilterQuality.high),
                  const SizedBox(height: 14),
                  const Text(
                    'Swipe Hire',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Swipe. Shortlist. Hire.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
