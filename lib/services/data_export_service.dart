import 'api_client.dart';
import 'auth_service.dart';

/// Fetches everything the signed-in account owns or appears in from the
/// backend (`GET /users/me/export`) as one plain JSON map, for the "Export
/// my data" action on the recruiter and candidate profile screens.
class DataExportService {
  DataExportService._();

  static Future<Map<String, dynamic>> exportMyData() async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('No signed-in user to export data for.');
    return ApiClient.instance.get('/users/me/export');
  }
}
