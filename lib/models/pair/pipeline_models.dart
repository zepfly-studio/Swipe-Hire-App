import '../candidate.dart';
import 'pair_person.dart';

/// A job as the shortlisted job-filter needs it (`GET /jobs/mine`).
class PipelineJob {
  final String id;
  final String title;

  /// open | paused | closed
  final String status;
  const PipelineJob({required this.id, required this.title, this.status = 'open'});

  factory PipelineJob.fromMap(Map<String, dynamic> m) {
    var status = pairStr(m['status']);
    if (status.isEmpty) status = m['isOpen'] == false ? 'closed' : 'open';
    return PipelineJob(id: pairStr(m['id']), title: pairStr(m['title'], 'Untitled job'), status: status);
  }

  /// "Flutter Developer", "Flutter Developer (paused)", "... (closed)".
  String get filterLabel => switch (status) {
        'paused' => '$title (paused)',
        'closed' => '$title (closed)',
        _ => title,
      };
}

/// One row of the stage-filtered list, de-duplicated by person: a candidate
/// shortlisted for two jobs appears twice in the list (one row per job) but is
/// one recipient in a group message.
List<Candidate> dedupeByPerson(Iterable<Candidate> rows) {
  final seen = <String>{};
  final out = <Candidate>[];
  for (final c in rows) {
    if (seen.add(c.id)) out.add(c);
  }
  return out;
}

/// The multi-select state of the shortlisted screen. Selection is by PERSON
/// id, so ticking one of a person's rows ticks all of them.
class PipelineSelection {
  final Set<String> _ids = <String>{};

  Set<String> get ids => Set.unmodifiable(_ids);
  int get count => _ids.length;
  bool get isEmpty => _ids.isEmpty;
  bool contains(String personId) => _ids.contains(personId);

  void toggle(String personId) {
    if (!_ids.remove(personId)) _ids.add(personId);
  }

  void clear() => _ids.clear();

  /// Selects every distinct person in [visible].
  void selectAll(Iterable<Candidate> visible) {
    for (final c in visible) {
      _ids.add(c.id);
    }
  }

  /// Forget people who are no longer in the list.
  void retainOnly(Iterable<Candidate> rows) {
    final keep = rows.map((c) => c.id).toSet();
    _ids.removeWhere((id) => !keep.contains(id));
  }

  /// The people a group message goes to: the selected ones among [visible],
  /// or all of [visible] when nothing is selected (de-duplicated, in order).
  List<Candidate> recipients(Iterable<Candidate> visible) {
    final people = dedupeByPerson(visible);
    if (_ids.isEmpty) return people;
    return people.where((c) => _ids.contains(c.id)).toList();
  }

  /// "Select all" / "N selected".
  String headerLabel(int visiblePeople) => _ids.isEmpty ? 'Select all' : '${_ids.length} selected';

  /// "Message N selected" / "Message all (N)".
  String buttonLabel(int visiblePeople) =>
      _ids.isEmpty ? 'Message all ($visiblePeople)' : 'Message ${_ids.length} selected';
}

/// Rows of [rows] whose stage equals [stage] (`'all'` keeps everything).
List<Candidate> rowsInStage(List<Candidate> rows, String stage) {
  if (stage == 'all') return rows;
  return rows.where((c) => (c.stage.isEmpty ? 'shortlisted' : c.stage) == stage).toList();
}
