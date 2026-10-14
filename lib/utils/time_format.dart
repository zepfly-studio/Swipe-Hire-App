const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "19 Oct 2026"
String formatDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Mon, 19 Oct"
String formatShortDay(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// "3:00 PM"
String formatClock(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$hour:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// "19 Oct 2026, 3:00 PM"
String formatDateTime(DateTime d) => '${formatDay(d)}, ${formatClock(d)}';

/// "just now", "5 min ago", "3 h ago", "Yesterday", "19 Oct".
String timeAgo(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${time.day} ${_months[time.month - 1]}';
}

/// How long until [due]: "Due today", "Due tomorrow", "Due in 3 days",
/// "Overdue by 2 days".
String dueLabel(DateTime due, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final days = dueDay.difference(today).inDays;
  if (due.isBefore(current)) {
    final late = today.difference(dueDay).inDays;
    return late <= 0 ? 'Overdue' : 'Overdue by $late day${late == 1 ? '' : 's'}';
  }
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}

/// A "Add to Google Calendar" link for an interview. Works in a browser and
/// on phones without needing a file download.
Uri googleCalendarUri({
  required String title,
  required DateTime start,
  int durationMinutes = 60,
  String details = '',
  String location = '',
}) {
  String stamp(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  final end = start.add(Duration(minutes: durationMinutes));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${stamp(start)}/${stamp(end)}',
    if (details.isNotEmpty) 'details': details,
    if (location.isNotEmpty) 'location': location,
  });
}
