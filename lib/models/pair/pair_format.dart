const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Mon, 5 Oct"
String formatPairDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// "3:45 pm"
String formatPairClock(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'pm' : 'am'}';
}

/// "Mon, 5 Oct, 11:00 am"
String formatPairDateTime(DateTime d) => '${formatPairDay(d)}, ${formatPairClock(d)}';

/// How long until [due], as the task cards show it: "2 days 4 h left",
/// "1 day left", "5 h left", "45 min left", or "Deadline passed".
String timeLeftLabel(DateTime due, {DateTime? now}) {
  final diff = due.difference(now ?? DateTime.now());
  if (diff.inSeconds <= 0) return 'Deadline passed';
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  if (days >= 1) {
    final d = '$days day${days == 1 ? '' : 's'}';
    return hours == 0 ? '$d left' : '$d $hours h left';
  }
  if (diff.inHours >= 1) return '${diff.inHours} h left';
  final mins = diff.inMinutes < 1 ? 1 : diff.inMinutes;
  return '$mins min left';
}

/// True when less than an hour is left (shown in bold red).
bool isTimeLeftUrgent(DateTime due, {DateTime? now}) {
  final diff = due.difference(now ?? DateTime.now());
  return diff.inSeconds > 0 && diff.inHours < 1;
}

/// "new" when there is no timestamp, else a compact relative time for the
/// conversation list ("now", "5m", "3h", "Yesterday", "5 Oct").
String conversationTime(DateTime? at, {DateTime? now}) {
  if (at == null) return 'new';
  final current = now ?? DateTime.now();
  final diff = current.difference(at);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && at.day == current.day) return '${diff.inHours}h';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[at.weekday - 1];
  return '${at.day} ${_months[at.month - 1]}';
}
