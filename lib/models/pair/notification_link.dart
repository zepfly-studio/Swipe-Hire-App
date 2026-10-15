/// Where a notification's `link` (a website route) leads in the app.
enum NotificationTargetKind {
  /// `/messages?with=<id>` (or `/messages`)
  messages,

  /// `/interviews`
  interviews,

  /// `/tasks`
  tasks,

  /// `/candidate` -- the candidate home tab
  candidateHome,

  /// `/company/shortlisted`
  shortlisted,

  /// `/company/swipe?search=<id>`
  swipe,

  /// `/company/verify` -- the "Get verified" screen
  verify,

  /// `/company/team` -- the team screen
  team,
  unknown,
}

class NotificationTarget {
  final NotificationTargetKind kind;

  /// `with` for messages, `search` for swipe, `job` for shortlisted.
  final String? param;
  const NotificationTarget(this.kind, [this.param]);

  @override
  bool operator ==(Object other) => other is NotificationTarget && other.kind == kind && other.param == param;

  @override
  int get hashCode => Object.hash(kind, param);

  @override
  String toString() => 'NotificationTarget($kind, $param)';
}

/// Parses a notification link such as `/messages?with=abc`.
NotificationTarget parseNotificationLink(String? link) {
  final text = (link ?? '').trim();
  if (text.isEmpty) return const NotificationTarget(NotificationTargetKind.unknown);
  final uri = Uri.tryParse(text);
  if (uri == null) return const NotificationTarget(NotificationTargetKind.unknown);
  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
  String? q(String name) {
    final v = uri.queryParameters[name];
    return v == null || v.isEmpty ? null : v;
  }

  return switch (path) {
    '/messages' => NotificationTarget(NotificationTargetKind.messages, q('with')),
    '/interviews' => const NotificationTarget(NotificationTargetKind.interviews),
    '/tasks' => const NotificationTarget(NotificationTargetKind.tasks),
    '/candidate' => const NotificationTarget(NotificationTargetKind.candidateHome),
    '/company/shortlisted' => NotificationTarget(NotificationTargetKind.shortlisted, q('job') ?? q('jobId')),
    '/company/swipe' => NotificationTarget(NotificationTargetKind.swipe, q('search')),
    '/company/verify' => const NotificationTarget(NotificationTargetKind.verify),
    '/company/team' => const NotificationTarget(NotificationTargetKind.team),
    _ => const NotificationTarget(NotificationTargetKind.unknown),
  };
}
