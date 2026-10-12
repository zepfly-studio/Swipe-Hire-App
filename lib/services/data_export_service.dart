import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import 'auth_service.dart';

/// Gathers every Firestore doc the signed-in account owns or appears in
/// into one plain JSON-safe map, for the "Export my data" action on the
/// recruiter and candidate profile screens.
class DataExportService {
  DataExportService._();

  static Future<Map<String, dynamic>> exportMyData() async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('No signed-in user to export data for.');
    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    final userDoc = await firestore.collection('users').doc(uid).get();
    final profile = userDoc.data() == null ? null : AppUser.fromMap(uid, userDoc.data()!);

    final export = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'account': {
        'uid': uid,
        'email': user.email,
        'emailVerified': user.emailVerified,
        'createdAt': user.metadata.creationTime?.toIso8601String(),
      },
      'profile': userDoc.data() == null ? null : _sanitize(userDoc.data()!),
    };

    if (profile?.role == UserRole.candidate) {
      final candidateDoc = await firestore.collection('candidate_profiles').doc(uid).get();
      export['candidateProfile'] = candidateDoc.data() == null ? null : _sanitize(candidateDoc.data()!);

      final asCandidate = await firestore.collection('opportunities').where('candidateUid', isEqualTo: uid).get();
      export['hiringActivity'] = asCandidate.docs.map((d) => _sanitize(d.data())).toList();
    } else {
      final asRecruiter = await firestore.collection('opportunities').where('recruiterUid', isEqualTo: uid).get();
      export['pipeline'] = asRecruiter.docs.map((d) => _sanitize(d.data())).toList();
    }

    return export;
  }

  /// Recursively turns Firestore-only types ([Timestamp], [GeoPoint], ...)
  /// into JSON-encodable values.
  static dynamic _sanitize(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _sanitize(v)));
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }
}
