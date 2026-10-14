import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local persistence for the recruiter's own (editable) profile -- name,
/// designation, company, email, phone. Stored with Hive so it survives app
/// restarts without needing a backend.
class RecruiterProfileService {
  RecruiterProfileService._internal();
  static final RecruiterProfileService instance = RecruiterProfileService._internal();

  static const String _boxName = 'recruiter_profile';
  Box<String>? _box;

  // Used instead of the Hive box in widget tests, where Hive's real file IO
  // would never complete under the test's fake clock.
  Map<String, String>? _memory;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Keeps everything in memory from now on -- tests only.
  @visibleForTesting
  void useInMemoryStorage() {
    _box = null;
    _memory = {};
  }

  String _get(String key) => (_memory != null ? _memory![key] : _box?.get(key)) ?? '';

  String get name => _get('name');
  String get designation => _get('designation');
  String get company => _get('company');
  String get email => _get('email');
  String get phone => _get('phone');

  Future<void> save({
    required String name,
    required String designation,
    required String company,
    required String email,
    required String phone,
  }) async {
    final values = {
      'name': name,
      'designation': designation,
      'company': company,
      'email': email,
      'phone': phone,
    };
    final memory = _memory;
    if (memory != null) {
      memory.addAll(values);
      return;
    }
    await _box!.putAll(values);
  }

  ValueListenable<Box<String>> listenable() => _box!.listenable();
}
