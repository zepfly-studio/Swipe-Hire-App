/// The "I'm active" ring: companies rank candidates who have not confirmed
/// they are still looking for [kActiveWindowDays] days far lower.
const int kActiveWindowDays = 15;

class ActivityRing {
  const ActivityRing({
    required this.progress,
    required this.daysLeft,
    required this.isFull,
  });

  /// 0..1 of the window used up.
  final double progress;

  /// Whole days left (at least 1 while the ring is not full, 0 once full).
  final int daysLeft;

  /// 15 days or more since the last confirmation.
  final bool isFull;
}

ActivityRing activityRingFor(DateTime? activeAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (activeAt == null) {
    return const ActivityRing(
      progress: 0,
      daysLeft: kActiveWindowDays,
      isFull: false,
    );
  }
  final elapsedDays = current.difference(activeAt).inMinutes / (60 * 24);
  if (elapsedDays >= kActiveWindowDays) {
    return const ActivityRing(progress: 1, daysLeft: 0, isFull: true);
  }
  final clamped = elapsedDays < 0 ? 0.0 : elapsedDays;
  final left = (kActiveWindowDays - clamped).ceil().clamp(1, kActiveWindowDays);
  return ActivityRing(
    progress: clamped / kActiveWindowDays,
    daysLeft: left,
    isFull: false,
  );
}
