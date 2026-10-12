import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local persistence for the recruiter's own (editable) profile -- name,
/// designation, company, email, phone. Stored with Hive so it survives app
/// restarts without needing a backend.
class RecruiterProfileService {
  RecruiterProfileService._internal();
  static final RecruiterProfileService instance = RecruiterProfileService._internal();

  static const String _boxName = 'recruiter_profile';
  late Box<String> _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  String get name => _box.get('name') ?? '';
  String get designation => _box.get('designation') ?? '';
  String get company => _box.get('company') ?? '';
  String get email => _box.get('email') ?? '';
  String get phone => _box.get('phone') ?? '';

  bool get hasProfile => name.isNotEmpty;

  Future<void> save({
    required String name,
    required String designation,
    required String company,
    required String email,
    required String phone,
  }) async {
    await _box.putAll({
      'name': name,
      'designation': designation,
      'company': company,
      'email': email,
      'phone': phone,
    });
  }

  ValueListenable<Box<String>> listenable() => _box.listenable();
}
