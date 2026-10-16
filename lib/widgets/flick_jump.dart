import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';

/// Wraps a vertically scrolling [child] (driven by [controller]): a quick
/// swipe up jumps straight to [target] (e.g. the intro video at the bottom of
/// a candidate card), a quick swipe down jumps back to the top. A slow drag
/// is left to the scroll view and scrolls normally.
class FlickJump extends StatefulWidget {
  final ScrollController controller;

  /// Key of the widget inside [child] a swipe up jumps to.
  final GlobalKey target;
  final Widget child;

  /// Vertical speed (pixels per second) from which a swipe counts as quick.
  final double minVelocity;

  const FlickJump({
    super.key,
    required this.controller,
    required this.target,
    required this.child,
    this.minVelocity = 1100,
  });

  @override
  State<FlickJump> createState() => _FlickJumpState();
}

class _FlickJumpState extends State<FlickJump> {
  static const _duration = Duration(milliseconds: 420);
  VelocityTracker? _tracker;

  void _down(PointerDownEvent e) {
    _tracker = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) => _tracker?.addPosition(e.timeStamp, e.position);

  void _up(PointerUpEvent e) {
    final v = _tracker?.getVelocity().pixelsPerSecond;
    _tracker = null;
    if (v == null || v.dy.abs() < widget.minVelocity || v.dy.abs() < v.dx.abs() * 1.5) return;
    // After the scroll view has started its own fling, so ours replaces it.
    Future<void>.delayed(Duration.zero, () {
      if (!mounted || !widget.controller.hasClients) return;
      if (v.dy < 0) {
        final target = widget.target.currentContext;
        if (target == null || !target.mounted) return;
        Scrollable.ensureVisible(target, duration: _duration, curve: Curves.easeOutCubic, alignment: 0.05);
      } else {
        widget.controller.animateTo(0, duration: _duration, curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: _down, onPointerMove: _move, onPointerUp: _up, child: widget.child);
  }
}
