import 'package:hiring_app/services/api_client.dart';

/// Stands in for the Node backend in service tests: a tiny in-memory
/// router over the handful of `/auth`, `/users`, `/jobs` and
/// `/opportunities` routes the services under test call, keyed by the
/// same paths and JSON shapes `backend/src/routes/*.js` use.
class FakeApi extends ApiClient {
  FakeApi() : super.forTest();

  /// The single signed-in account (null = signed out / deleted).
  Map<String, dynamic>? account;
  bool deleted = false;

  final Map<String, Map<String, dynamic>> jobs = {};
  final List<Map<String, dynamic>> opportunities = [];
  final Set<String> savedJobIds = {};

  int _ids = 0;
  String _nextId(String prefix) => '$prefix-${++_ids}';

  ApiSession _sessionFor(Map<String, dynamic> user) => ApiSession(firebaseToken: 'custom-token', user: user);

  // -- auth -----------------------------------------------------------------

  @override
  Future<ApiSession> signUp({
    required String name,
    required String email,
    required String password,
    required String role,
    String company = '',
  }) async {
    account = {
      'uid': 'pg-${email.hashCode}',
      'email': email,
      'name': name,
      'role': role,
      'company': company,
      'designation': '',
      'phone': '',
      'profileComplete': false,
      'emailVerified': true,
    };
    return _sessionFor(account!);
  }

  @override
  Future<ApiSession> signIn({required String email, required String password}) async {
    if (account == null || account!['email'] != email) {
      throw ApiException(401, 'Incorrect email or password.');
    }
    return _sessionFor(account!);
  }

  /// The id token and role the last Google sign-in sent.
  String? googleIdToken;
  String? googleRole;

  /// What a first-time Google account is: it needs a role before it exists.
  @override
  Future<ApiSession> googleSignIn({required String idToken, String? role}) async {
    googleIdToken = idToken;
    googleRole = role;
    if (role == null) {
      throw ApiException(409, 'Choose how you will use GlideRecruit.', body: {'needsRole': true});
    }
    account = {
      'uid': 'pg-google',
      'email': 'google.user@example.com',
      'name': 'Google User',
      'role': role,
      'company': '',
      'designation': '',
      'phone': '',
      'profileComplete': false,
      'emailVerified': true,
    };
    return _sessionFor(account!);
  }

  @override
  Future<Map<String, dynamic>?> fetchMe() async => account;

  /// When set, [updateMe] throws it (e.g. the backend's 400 for a bad phone).
  Object? updateMeError;
  int updateMeCalls = 0;

  @override
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> fields) async {
    updateMeCalls++;
    if (updateMeError != null) throw updateMeError!;
    account = {...?account, ...fields};
    return account!;
  }

  @override
  Future<void> deleteMe() async {
    deleted = true;
    account = null;
  }

  @override
  Future<void> signOut() async {}

  // -- generic data routes --------------------------------------------------

  String get _uid => account?['uid'] as String? ?? 'anon';

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    if (path == '/jobs') {
      return {'jobs': jobs.values.where((j) => j['isOpen'] == true).toList()};
    }
    if (path == '/jobs/mine') {
      return {'jobs': jobs.values.where((j) => j['recruiterUid'] == _uid).toList()};
    }
    if (path == '/jobs/saved') return {'ids': savedJobIds.toList(), 'jobs': savedJobIds.map((id) => jobs[id]).whereType<Map<String, dynamic>>().toList()};
    final application = RegExp(r'^/jobs/([^/]+)/application$').firstMatch(path);
    if (application != null) {
      final jobId = application.group(1);
      return {'applied': opportunities.any((o) => o['candidateUid'] == _uid && o['jobPostingId'] == jobId)};
    }
    final job = RegExp(r'^/jobs/([^/]+)$').firstMatch(path);
    if (job != null) {
      final found = jobs[job.group(1)];
      if (found == null) throw ApiException(404, 'Job posting not found.');
      return found;
    }
    if (path == '/opportunities') {
      return {
        'opportunities': opportunities.where((o) => o['candidateUid'] == _uid || o['recruiterUid'] == _uid).toList(),
      };
    }
    throw ApiException(404, 'FakeApi: unhandled GET $path');
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    if (path == '/jobs') {
      final id = _nextId('job');
      jobs[id] = {...?body, 'id': id, 'recruiterUid': _uid};
      return jobs[id]!;
    }
    final apply = RegExp(r'^/jobs/([^/]+)/apply$').firstMatch(path);
    if (apply != null) {
      final posting = jobs[apply.group(1)];
      if (posting == null) throw ApiException(404, 'Job posting not found.');
      if (opportunities.any((o) => o['candidateUid'] == _uid && o['jobPostingId'] == posting['id'])) {
        throw ApiException(409, 'You have already applied to this role.');
      }
      final row = {
        'id': _nextId('opp'),
        'candidateUid': _uid,
        'candidateName': account?['name'] ?? '',
        'recruiterUid': posting['recruiterUid'],
        'recruiterName': posting['recruiterName'] ?? '',
        'companyName': posting['companyName'] ?? '',
        'role': posting['title'],
        'jobPostingId': posting['id'],
        'status': 'applied',
      };
      opportunities.add(row);
      return row;
    }
    throw ApiException(404, 'FakeApi: unhandled POST $path');
  }

  @override
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) async {
    final saved = RegExp(r'^/jobs/saved/([^/]+)$').firstMatch(path);
    if (saved != null) {
      savedJobIds.add(saved.group(1)!);
      return {'saved': true};
    }
    final job = RegExp(r'^/jobs/([^/]+)$').firstMatch(path);
    if (job != null) {
      final id = job.group(1)!;
      jobs[id] = {...?body, 'id': id, 'recruiterUid': _uid};
      return jobs[id]!;
    }
    throw ApiException(404, 'FakeApi: unhandled PUT $path');
  }

  @override
  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) async {
    final job = RegExp(r'^/jobs/([^/]+)$').firstMatch(path);
    if (job != null) {
      final id = job.group(1)!;
      jobs[id] = {...jobs[id]!, 'isOpen': body?['isOpen'] ?? true};
      return jobs[id]!;
    }
    throw ApiException(404, 'FakeApi: unhandled PATCH $path');
  }

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    final saved = RegExp(r'^/jobs/saved/([^/]+)$').firstMatch(path);
    if (saved != null) {
      savedJobIds.remove(saved.group(1));
      return {'saved': false};
    }
    throw ApiException(404, 'FakeApi: unhandled DELETE $path');
  }
}
