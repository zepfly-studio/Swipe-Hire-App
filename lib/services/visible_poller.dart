import 'dart:async';
import 'package:flutter/widgets.dart';

/// Runs [onTick] immediately and then every [interval], but only while the
/// owning screen is visible and the app is in the foreground (spec B0:
/// "Polling: only while the screen is visible; runs again when it becomes
/// visible").
///
/// Usage from a State: create it in initState and call [start]; call
/// [setVisible] from didChangeDependencies with `TickerMode.of(context)` (an
/// IndexedStack tab that is not shown, or a route covered by another, has
/// tickers disabled); call [dispose] in dispose.
class VisiblePoller with WidgetsBindingObserver {
  VisiblePoller({required this.interval, required this.onTick});

  final Duration interval;
  final Future<void> Function() onTick;

  Timer? _timer;
  bool _visible = true;
  bool _foreground = true;
  bool _started = false;
  bool _running = false;
  bool _disposed = false;

  bool get isActive => _timer != null;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _sync();
  }

  /// Fetch now (e.g. after the user acted), outside the timer rhythm.
  Future<void> pokeNow() => _tick();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (_disposed || !_started) return;
    final shouldRun = _visible && _foreground;
    if (shouldRun && _timer == null) {
      unawaited(_tick());
      _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    } else if (!shouldRun && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _tick() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      await onTick();
    } catch (_) {
      // A flaky connection must never surface from a background refresh;
      // onTick implementations do their own error handling.
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}
