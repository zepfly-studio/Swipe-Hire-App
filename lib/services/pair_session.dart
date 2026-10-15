import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import 'api_client.dart';

/// Who is signed in, for the pair screens that serve both roles
/// ([MessagesScreen], [InterviewsScreen], [TasksScreen]). Resolved from
/// `GET /users/me` and cached per session token; shells that already know the
/// role pass it to the screens directly and skip this.
class PairSession {
  PairSession._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final PairSession instance = PairSession._internal();

  @visibleForTesting
  factory PairSession.test(ApiClient api) => PairSession._internal(api: api);

  final ApiClient _api;
  AppUser? _user;
  String? _token;
  Future<AppUser?>? _loading;

  Future<AppUser?> user() async {
    final token = await _api.token;
    if (_user != null && _token == token) return _user;
    return _loading ??= _load(token).whenComplete(() => _loading = null);
  }

  Future<AppUser?> _load(String? token) async {
    final map = await _api.fetchMe();
    if (map == null) return null;
    final uid = (map['uid'] ?? map['id'] ?? '').toString();
    _user = AppUser.fromMap(uid, map);
    _token = token;
    return _user;
  }

  Future<bool?> isCompany() async {
    final u = await user();
    return u == null ? null : u.role == UserRole.recruiter;
  }
}
