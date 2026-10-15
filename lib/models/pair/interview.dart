import 'pair_person.dart';

/// Interview modes the backend accepts.
const List<String> kInterviewModes = ['video', 'phone', 'in-person'];
const List<int> kInterviewDurations = [15, 30, 45, 60];

String interviewModeLabel(String mode) => switch (mode) {
      'video' => 'Video call',
      'phone' => 'Phone call',
      'in-person' || 'inperson' || 'in_person' => 'In person',
      _ => mode,
    };

/// An interview invite and (once confirmed) the chosen time.
class Interview {
  final String id;
  final PairPerson person;
  final String jobTitle;
  final List<DateTime> slots;
  final DateTime? chosenSlot;
  final int durationMins;
  final String mode;
  final String meetingLink;
  final String location;
  final String note;

  /// proposed | confirmed | cancelled
  final String status;
  final DateTime? createdAt;

  const Interview({
    required this.id,
    required this.person,
    this.jobTitle = '',
    this.slots = const [],
    this.chosenSlot,
    this.durationMins = 30,
    this.mode = 'video',
    this.meetingLink = '',
    this.location = '',
    this.note = '',
    this.status = 'proposed',
    this.createdAt,
  });

  factory Interview.fromMap(Map<String, dynamic> m) {
    final slots = <DateTime>[
      for (final s in (m['slots'] as List? ?? const []))
        if (pairDate(s) != null) pairDate(s)!,
    ]..sort();
    return Interview(
      id: pairStr(m['id']),
      person: PairPerson.fromMap(m['with']),
      jobTitle: pairStr(m['jobTitle']),
      slots: slots,
      chosenSlot: pairDate(m['chosenSlot']),
      durationMins: pairInt(m['durationMins'], 30),
      mode: pairStr(m['mode'], 'video'),
      meetingLink: pairStr(m['meetingLink']),
      location: pairStr(m['location']),
      note: pairStr(m['note']),
      status: pairStr(m['status'], 'proposed'),
      createdAt: pairDate(m['createdAt']),
    );
  }

  bool get isProposed => status == 'proposed';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled' || status == 'canceled';

  /// When the confirmed interview ends.
  DateTime? get endsAt => chosenSlot?.add(Duration(minutes: durationMins));

  /// Confirmed and over.
  bool isDone(DateTime now) => isConfirmed && endsAt != null && !endsAt!.isAfter(now);

  /// Not cancelled and not over -- the "can still be cancelled / joined" state.
  bool isActive(DateTime now) {
    if (isCancelled) return false;
    if (isConfirmed) return endsAt == null || endsAt!.isAfter(now);
    return true;
  }
}

/// The three groups of the interviews screen.
class InterviewGroups {
  /// `proposed`: "Needs your reply" (candidate) / "Waiting for the candidate".
  final List<Interview> pending;

  /// Confirmed and still ahead, soonest first.
  final List<Interview> upcoming;

  /// Done and cancelled, newest first.
  final List<Interview> past;
  const InterviewGroups({this.pending = const [], this.upcoming = const [], this.past = const []});

  bool get isEmpty => pending.isEmpty && upcoming.isEmpty && past.isEmpty;
}

InterviewGroups groupInterviews(List<Interview> all, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final pending = <Interview>[];
  final upcoming = <Interview>[];
  final past = <Interview>[];
  for (final i in all) {
    if (i.isCancelled) {
      past.add(i);
    } else if (i.isProposed) {
      pending.add(i);
    } else if (i.isConfirmed && !i.isDone(current)) {
      upcoming.add(i);
    } else {
      past.add(i);
    }
  }
  DateTime key(Interview i) => i.chosenSlot ?? i.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  upcoming.sort((a, b) => key(a).compareTo(key(b)));
  past.sort((a, b) => key(b).compareTo(key(a)));
  pending.sort((a, b) {
    final x = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final y = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return y.compareTo(x);
  });
  return InterviewGroups(pending: pending, upcoming: upcoming, past: past);
}

/// Status pill text: companies see "Waiting for reply", candidates "Pick a
/// time"; confirmed becomes "Done" once over.
String interviewStatusLabel(Interview i, {required bool isCompany, DateTime? now}) {
  if (i.isCancelled) return 'Cancelled';
  if (i.isProposed) return isCompany ? 'Waiting for reply' : 'Pick a time';
  if (i.isConfirmed) return i.isDone(now ?? DateTime.now()) ? 'Done' : 'Confirmed';
  return i.status;
}

// -- Scheduling helpers (ScheduleInterviewModal) --------------------------

/// Server minimum lead time for an interview slot.
const Duration kMinSlotLead = Duration(minutes: 15);

/// Tomorrow and the day after, both at 11:00 (the modal's defaults).
List<DateTime> defaultInterviewSlots(DateTime now) => [
      DateTime(now.year, now.month, now.day + 1, 11),
      DateTime(now.year, now.month, now.day + 2, 11),
    ];

bool isSlotInFuture(DateTime slot, DateTime now) => !slot.isBefore(now.add(kMinSlotLead));

/// The client-side validation of the schedule form; returns the message to
/// show, or null when the form can be sent. [slots] may contain nulls for
/// empty pickers.
String? validateInterviewForm({
  required List<DateTime?> slots,
  required String mode,
  required String location,
  required DateTime now,
}) {
  final chosen = slots.whereType<DateTime>().toList();
  if (chosen.isEmpty) return 'Add at least one time slot';
  if (chosen.any((s) => !isSlotInFuture(s, now))) return 'Time slots must be in the future';
  if (mode == 'in-person' && location.trim().isEmpty) return 'Please add the interview address';
  return null;
}

/// Distinct, sorted ISO strings (UTC) to send as `slots`.
List<String> slotsToIso(Iterable<DateTime?> slots) {
  final unique = <int, DateTime>{};
  for (final s in slots.whereType<DateTime>()) {
    unique[s.millisecondsSinceEpoch] = s;
  }
  final sorted = unique.values.toList()..sort();
  return [for (final s in sorted) s.toUtc().toIso8601String()];
}

/// Error text for the server's well-known interview rejections; otherwise the
/// server message is shown as-is.
String interviewErrorText(String serverMessage) {
  final m = serverMessage.toLowerCase();
  if (m.contains('already') && m.contains('interview')) {
    return 'An interview with this candidate is already scheduled';
  }
  return serverMessage;
}

/// "Add to calendar" link (Google Calendar template).
Uri interviewCalendarUri(Interview i, {required String title}) {
  final start = (i.chosenSlot ?? DateTime.now()).toUtc();
  final end = start.add(Duration(minutes: i.durationMins));
  String stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}${two(d.second)}Z';
  }

  final details = [
    if (i.note.isNotEmpty) i.note,
    if (i.meetingLink.isNotEmpty) 'Join: ${i.meetingLink}',
  ].join('\n');
  final where = i.location.isNotEmpty ? i.location : i.meetingLink;
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${stamp(start)}/${stamp(end)}',
    if (details.isNotEmpty) 'details': details,
    if (where.isNotEmpty) 'location': where,
  });
}
