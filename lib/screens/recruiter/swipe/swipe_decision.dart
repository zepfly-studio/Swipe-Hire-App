import 'dart:math' as math;

enum SwipeDir { left, right }

extension SwipeDirX on SwipeDir {
  /// What POST /company/swipe takes.
  String get action => this == SwipeDir.right ? 'right' : 'left';
}

/// Drag distance (px) past which a release always commits.
const double kSwipeCommitDistance = 100;

/// A fling faster than this (px/s) commits once it also passed
/// [kSwipeFlingMinDistance].
const double kSwipeFlingVelocity = 500;
const double kSwipeFlingMinDistance = 40;

/// Rotation reaches this many degrees at +/- [kSwipeRotationDistance].
const double kSwipeMaxRotationDegrees = 9;
const double kSwipeRotationDistance = 320;

/// What a drag release means: right = shortlist, left = pass, null = spring
/// back. Commit when |dx| > 100, or velocity > 500 with |dx| > 40.
SwipeDir? swipeDecision({required double dx, required double velocityX}) {
  final distance = dx.abs();
  final fast = velocityX.abs() > kSwipeFlingVelocity && distance > kSwipeFlingMinDistance;
  if (distance <= kSwipeCommitDistance && !fast) return null;
  return dx > 0 ? SwipeDir.right : SwipeDir.left;
}

/// Card rotation (radians) for a horizontal offset.
double swipeRotation(double dx) {
  final t = (dx / kSwipeRotationDistance).clamp(-1.0, 1.0);
  return t * kSwipeMaxRotationDegrees * math.pi / 180;
}

/// Opacity (0..1) of the SHORTLIST / PASS stamp.
double swipeStampOpacity(double dx) => (dx.abs() / kSwipeCommitDistance).clamp(0.0, 1.0);

/// Opacity (0..0.22) of the green/red tint over the dragged card.
double swipeTintOpacity(double dx) => ((dx.abs() / kSwipeRotationDistance) * 0.22).clamp(0.0, 0.22);
