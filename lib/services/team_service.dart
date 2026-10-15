import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// A team can hold this many people: the owner, members and pending invites.
const int kMaxTeamSize = 10;

/// One person on the team (`GET /team` -> `members[]`).
class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.isOwner,
    required this.isYou,
  });

  final String id;
  final String name;
  final String email;
  final bool isOwner;
  final bool isYou;

  factory TeamMember.fromMap(Map<String, dynamic> m) => TeamMember(
        id: '${m['id'] ?? ''}',
        name: (m['name'] as String? ?? '').trim(),
        email: (m['email'] as String? ?? '').trim(),
        isOwner: m['role'] == 'owner',
        isYou: m['you'] == true,
      );

  /// What the UI calls this person when the name is blank.
  String get displayName => name.isNotEmpty ? name : email;

  /// Up to two capital letters for the avatar tile.
  String get initials => initialsOf(displayName);
}

/// A pending invite (`GET /team` -> `invites[]`).
class TeamInvite {
  const TeamInvite({required this.id, required this.email});
  final String id;
  final String email;

  factory TeamInvite.fromMap(Map<String, dynamic> m) =>
      TeamInvite(id: '${m['id'] ?? ''}', email: (m['email'] as String? ?? '').trim());
}

/// The whole `GET /team` answer.
class TeamData {
  const TeamData({required this.isOwner, required this.members, required this.invites});
  final bool isOwner;
  final List<TeamMember> members;
  final List<TeamInvite> invites;

  factory TeamData.fromMap(Map<String, dynamic> m) => TeamData(
        isOwner: m['isOwner'] == true,
        members: [
          for (final e in (m['members'] as List? ?? const []))
            if (e is Map) TeamMember.fromMap(Map<String, dynamic>.from(e)),
        ],
        invites: [
          for (final e in (m['invites'] as List? ?? const []))
            if (e is Map) TeamInvite.fromMap(Map<String, dynamic>.from(e)),
        ],
      );

  /// People counted against the limit: members (owner included) + invites.
  int get size => members.length + invites.length;

  bool get isFull => size >= kMaxTeamSize;

  /// How many more people can still be invited.
  int get seatsLeft => (kMaxTeamSize - size).clamp(0, kMaxTeamSize);
}

/// What `POST /team/invite` answered.
class InviteResult {
  const InviteResult({this.inviteCode});

  /// Present when the server could not (or was told not to) email the
  /// invite, so the owner has to share the code by hand.
  final String? inviteCode;
}

/// Up to two capital letters from a name or email ("Asha Rao" -> "AR").
String initialsOf(String text) {
  final parts = text.trim().split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final second = parts.length > 1 ? parts[1][0] : '';
  return (first + second).toUpperCase();
}

/// Pulls the invite token out of what a person pasted: the bare code, or a
/// link carrying `?token=...`. Whitespace (a wrapped paste) is dropped.
String extractInviteToken(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return '';
  final fromQuery = RegExp(r'[?&#]token=([^&#\s]+)').firstMatch(raw);
  if (fromQuery != null) {
    try {
      return Uri.decodeQueryComponent(fromQuery.group(1)!).trim();
    } on ArgumentError {
      return fromQuery.group(1)!.trim();
    }
  }
  return raw.replaceAll(RegExp(r'\s+'), '');
}

/// The company's team (`/team`). Errors surface as [ApiException] with the
/// server's own message, which the screens show verbatim.
class TeamService {
  TeamService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final TeamService instance = TeamService._internal();

  @visibleForTesting
  factory TeamService.test(ApiClient api) => TeamService._internal(api: api);

  final ApiClient _api;

  Future<TeamData> load() async => TeamData.fromMap(await _api.get('/team'));

  Future<InviteResult> invite(String email) async {
    final res = await _api.post('/team/invite', body: {'email': email.trim()});
    final code = res['inviteCode'];
    return InviteResult(inviteCode: code is String && code.isNotEmpty ? code : null);
  }

  Future<void> removeMember(String id) async {
    await _api.delete('/team/members/${Uri.encodeComponent(id)}');
  }

  Future<void> cancelInvite(String id) async {
    await _api.delete('/team/invites/${Uri.encodeComponent(id)}');
  }
}
