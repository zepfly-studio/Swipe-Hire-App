import 'pair_person.dart';

class TaskSubmission {
  final String liveUrl;
  final String repoUrl;
  final String note;
  final DateTime? at;
  const TaskSubmission({this.liveUrl = '', this.repoUrl = '', this.note = '', this.at});

  factory TaskSubmission.fromMap(Object? raw) {
    final m = pairMap(raw);
    return TaskSubmission(
      liveUrl: pairStr(m['liveUrl']),
      repoUrl: pairStr(m['repoUrl']),
      note: pairStr(m['note']),
      at: pairDate(m['at']),
    );
  }
}

/// A take-home task a company sent to a shortlisted candidate.
class HiringTask {
  final String id;
  final PairPerson person;
  final String jobTitle;
  final String title;
  final String description;
  final String briefUrl;
  final DateTime? dueAt;

  /// assigned | submitted | overdue | cancelled
  final String status;
  final TaskSubmission? submission;
  final DateTime? createdAt;

  const HiringTask({
    required this.id,
    required this.person,
    this.jobTitle = '',
    this.title = '',
    this.description = '',
    this.briefUrl = '',
    this.dueAt,
    this.status = 'assigned',
    this.submission,
    this.createdAt,
  });

  factory HiringTask.fromMap(Map<String, dynamic> m) {
    final sub = m['submission'];
    return HiringTask(
      id: pairStr(m['id']),
      person: PairPerson.fromMap(m['with']),
      jobTitle: pairStr(m['jobTitle']),
      title: pairStr(m['title']),
      description: pairStr(m['description']),
      briefUrl: pairStr(m['briefUrl']),
      dueAt: pairDate(m['dueAt']),
      status: pairStr(m['status'], 'assigned'),
      submission: sub is Map ? TaskSubmission.fromMap(sub) : null,
      createdAt: pairDate(m['createdAt']),
    );
  }

  /// `overdue` is not stored: an assigned task past its deadline.
  String effectiveStatus(DateTime now) {
    if (status == 'assigned' && dueAt != null && dueAt!.isBefore(now)) return 'overdue';
    return status;
  }

  bool get isCancelled => status == 'cancelled';

  /// Candidate can still (re)submit: assigned or submitted, before the deadline.
  bool canSubmit(DateTime now) {
    if (status != 'assigned' && status != 'submitted') return false;
    return dueAt == null || dueAt!.isAfter(now);
  }
}

String taskStatusLabel(String effectiveStatus) => switch (effectiveStatus) {
      'assigned' => 'Waiting',
      'submitted' => 'Submitted',
      'overdue' => 'Deadline passed',
      'cancelled' => 'Cancelled',
      _ => effectiveStatus,
    };

/// Filter chips of the tasks screen.
const List<String> kTaskFilters = ['all', 'assigned', 'submitted', 'overdue'];

String taskFilterLabel(String filter) => switch (filter) {
      'all' => 'All',
      _ => taskStatusLabel(filter),
    };

Map<String, int> taskFilterCounts(Iterable<HiringTask> tasks, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final counts = <String, int>{for (final f in kTaskFilters) f: 0};
  for (final t in tasks) {
    counts['all'] = counts['all']! + 1;
    final s = t.effectiveStatus(current);
    if (counts.containsKey(s)) counts[s] = counts[s]! + 1;
  }
  return counts;
}

List<HiringTask> filterTasks(List<HiringTask> tasks, String filter, {DateTime? now}) {
  if (filter == 'all') return tasks;
  final current = now ?? DateTime.now();
  return tasks.where((t) => t.effectiveStatus(current) == filter).toList();
}

// -- Validation helpers ------------------------------------------------------

/// A normalised link, or an error message.
class LinkCheck {
  final String? url;
  final String? error;
  const LinkCheck.ok(this.url) : error = null;
  const LinkCheck.error(this.error) : url = null;
  bool get isOk => error == null;
}

/// Normalises a user-typed link the way the server does: empty is allowed
/// (url == ''), `https://` is added when no scheme is given, only http(s) is
/// accepted, at most 300 characters, and [githubOnly] requires github.com.
LinkCheck checkTaskLink(String raw, {bool githubOnly = false, required String invalidMessage}) {
  var text = raw.trim();
  if (text.isEmpty) return const LinkCheck.ok('');
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(text)) {
    // "mailto:x" / "javascript:x" style schemes are not http(s).
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:(?!\d)').hasMatch(text)) return LinkCheck.error(invalidMessage);
    text = 'https://$text';
  }
  if (text.length > 300) return LinkCheck.error(invalidMessage);
  final uri = Uri.tryParse(text);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return LinkCheck.error(invalidMessage);
  final host = uri.host.toLowerCase();
  if (host.isEmpty || !host.contains('.') || host.endsWith('.')) return LinkCheck.error(invalidMessage);
  if (githubOnly && host != 'github.com' && host != 'www.github.com') {
    return const LinkCheck.error('The repo link must be a github.com link');
  }
  return LinkCheck.ok(text);
}

/// Result of validating the candidate's submit form.
class SubmissionCheck {
  final String liveUrl;
  final String repoUrl;
  final String? liveError;
  final String? repoError;
  final String? formError;
  const SubmissionCheck({this.liveUrl = '', this.repoUrl = '', this.liveError, this.repoError, this.formError});
  bool get isValid => liveError == null && repoError == null && formError == null;
}

SubmissionCheck validateSubmission({required String live, required String repo}) {
  if (live.trim().isEmpty && repo.trim().isEmpty) {
    return const SubmissionCheck(formError: 'Add your live link or GitHub repo link');
  }
  final l = checkTaskLink(live, invalidMessage: 'Please enter a valid live link');
  final r = checkTaskLink(repo, githubOnly: true, invalidMessage: 'Please enter a valid GitHub repo link');
  return SubmissionCheck(
    liveUrl: l.url ?? '',
    repoUrl: r.url ?? '',
    liveError: l.error,
    repoError: r.error,
  );
}

/// Validates a task deadline for sending / changing. Returns an error text or
/// null. The server window is now+1h .. now+30d.
String? validateTaskDeadline(DateTime? due, {DateTime? now}) {
  if (due == null) return 'Pick a deadline at least 1 hour from now';
  final current = now ?? DateTime.now();
  if (due.isBefore(current.add(const Duration(hours: 1)))) return 'Pick a deadline at least 1 hour from now';
  if (due.isAfter(current.add(const Duration(days: 30)))) return 'The deadline can be at most 30 days away';
  return null;
}

/// Preset deadline: [days] from today at 23:59 local time.
DateTime deadlinePreset(int days, {DateTime? now}) {
  final c = now ?? DateTime.now();
  return DateTime(c.year, c.month, c.day + days, 23, 59);
}
