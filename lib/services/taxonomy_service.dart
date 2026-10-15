import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'api_client.dart';

/// The suggestion lists behind every autocomplete (`GET /taxonomy`).
class Taxonomy {
  final List<String> roles;
  final List<String> skills;
  final List<String> degrees;
  final List<String> cities;
  final List<String> states;
  final List<String> locations;

  const Taxonomy({
    required this.roles,
    required this.skills,
    required this.degrees,
    required this.cities,
    required this.states,
    required this.locations,
  });

  static List<String> _list(dynamic v, List<String> fallback) {
    if (v is! List) return fallback;
    final out = [
      for (final e in v)
        if (e != null && e.toString().trim().isNotEmpty) e.toString(),
    ];
    return out.isEmpty ? fallback : out;
  }

  /// Missing lists fall back to the built-in ones, so a partial answer from
  /// the server never leaves a field without suggestions.
  factory Taxonomy.fromMap(Map<String, dynamic> m, {Taxonomy? fallback}) {
    final f = fallback ?? Taxonomy.builtIn;
    final cities = _list(m['cities'], f.cities);
    final states = _list(m['states'], f.states);
    return Taxonomy(
      roles: _list(m['roles'], f.roles),
      skills: _list(m['skills'], f.skills),
      degrees: _list(m['degrees'], f.degrees),
      cities: cities,
      states: states,
      locations: _list(m['locations'], [...cities, ...states, 'Remote']),
    );
  }

  Map<String, dynamic> toMap() => {
    'roles': roles,
    'skills': skills,
    'degrees': degrees,
    'cities': cities,
    'states': states,
    'locations': locations,
  };

  /// Small offline fallback so autocomplete works before (or without) the
  /// network. Most popular first.
  static const Taxonomy builtIn = Taxonomy(
    roles: [
      'Software Engineer',
      'Web Developer',
      'Frontend Developer',
      'Backend Developer',
      'Full Stack Developer',
      'Mobile App Developer',
      'Data Analyst',
      'Data Scientist',
      'DevOps Engineer',
      'QA Engineer',
      'UI/UX Designer',
      'Graphic Designer',
      'Product Manager',
      'Project Manager',
      'Business Analyst',
      'Digital Marketing Executive',
      'Content Writer',
      'SEO Specialist',
      'Sales Executive',
      'Business Development Executive',
      'Customer Support Executive',
      'HR Executive',
      'Recruiter',
      'Accountant',
      'Operations Executive',
      'Teacher',
      'Nurse',
      'Mechanical Engineer',
      'Civil Engineer',
      'Electrical Engineer',
    ],
    skills: [
      'JavaScript',
      'Python',
      'Java',
      'React',
      'Node.js',
      'SQL',
      'HTML',
      'CSS',
      'TypeScript',
      'Flutter',
      'Dart',
      'Angular',
      'Vue.js',
      'PHP',
      'C++',
      'C#',
      'Go',
      'Kotlin',
      'Swift',
      'Android',
      'MongoDB',
      'PostgreSQL',
      'MySQL',
      'AWS',
      'Docker',
      'Git',
      'REST APIs',
      'Django',
      'Spring Boot',
      'Figma',
      'Excel',
      'Power BI',
      'Tableau',
      'Communication',
      'Leadership',
      'Sales',
      'Customer Service',
      'Marketing',
      'SEO',
      'Content Writing',
      'Photoshop',
      'Accounting',
      'Tally',
      'Data Analysis',
      'Machine Learning',
      'Problem Solving',
      'Teamwork',
      'Project Management',
      'Recruitment',
      'Typing',
    ],
    degrees: [
      'B.Tech (CSE)',
      'B.Tech (IT)',
      'B.Tech (ECE)',
      'B.Tech (Mechanical)',
      'B.Tech (Civil)',
      'B.E.',
      'BCA',
      'B.Sc',
      'B.Com',
      'BBA',
      'BA',
      'M.Tech',
      'MCA',
      'M.Sc',
      'M.Com',
      'MBA',
      'MA',
      'Diploma (Engineering)',
      'Diploma',
      'ITI',
      '12th (Science)',
      '12th (Commerce)',
      '12th (Arts)',
      '10th',
      'PhD',
    ],
    cities: [
      'Delhi',
      'Mumbai',
      'Bengaluru',
      'Hyderabad',
      'Chennai',
      'Kolkata',
      'Pune',
      'Ahmedabad',
      'Jaipur',
      'Surat',
      'Lucknow',
      'Kanpur',
      'Nagpur',
      'Indore',
      'Bhopal',
      'Visakhapatnam',
      'Patna',
      'Vadodara',
      'Ghaziabad',
      'Ludhiana',
      'Agra',
      'Nashik',
      'Faridabad',
      'Meerut',
      'Rajkot',
      'Varanasi',
      'Srinagar',
      'Aurangabad',
      'Dhanbad',
      'Amritsar',
      'Navi Mumbai',
      'Allahabad',
      'Ranchi',
      'Howrah',
      'Coimbatore',
      'Jabalpur',
      'Gwalior',
      'Vijayawada',
      'Jodhpur',
      'Madurai',
      'Raipur',
      'Kota',
      'Chandigarh',
      'Guwahati',
      'Mysuru',
      'Gurugram',
      'Noida',
      'Thiruvananthapuram',
      'Kochi',
      'Dehradun',
      'Udaipur',
      'Bhubaneswar',
      'Jamshedpur',
      'Jalandhar',
      'Ajmer',
      'Bikaner',
      'Mangaluru',
      'Goa',
    ],
    states: [
      'Rajasthan',
      'Maharashtra',
      'Karnataka',
      'Tamil Nadu',
      'Telangana',
      'Uttar Pradesh',
      'Gujarat',
      'West Bengal',
      'Delhi',
      'Kerala',
      'Madhya Pradesh',
      'Punjab',
      'Haryana',
      'Bihar',
      'Odisha',
      'Andhra Pradesh',
      'Assam',
      'Jharkhand',
      'Chhattisgarh',
      'Uttarakhand',
      'Himachal Pradesh',
      'Jammu and Kashmir',
      'Goa',
      'Chandigarh',
    ],
    locations: [],
  );
}

/// Fetches `GET /taxonomy` once per app session and keeps it in memory (and
/// in Hive, best effort). Until the first answer arrives, [current] is the
/// built-in fallback (or last session's cached copy), so autocomplete always
/// has something to suggest. Widgets listen to [notifier].
class TaxonomyService {
  TaxonomyService._internal({ApiClient? api})
    : _api = api ?? ApiClient.instance;
  static final TaxonomyService instance = TaxonomyService._internal();

  /// A service wired to an injected (fake) API -- tests only.
  @visibleForTesting
  factory TaxonomyService.test(ApiClient api) =>
      TaxonomyService._internal(api: api);

  final ApiClient _api;
  static const _boxName = 'taxonomy_cache';
  static const _cacheKey = 'taxonomy';

  final ValueNotifier<Taxonomy> notifier = ValueNotifier(
    _withLocations(Taxonomy.builtIn),
  );
  Future<void>? _loading;
  bool _loaded = false;

  Taxonomy get current => notifier.value;
  bool get isLoaded => _loaded;

  static Taxonomy _withLocations(Taxonomy t) => t.locations.isNotEmpty
      ? t
      : Taxonomy(
          roles: t.roles,
          skills: t.skills,
          degrees: t.degrees,
          cities: t.cities,
          states: t.states,
          locations: [...t.cities, ...t.states, 'Remote'],
        );

  /// Safe to call repeatedly: only the first call hits the network. A failed
  /// attempt can be retried by calling again.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    await _readCache();
    try {
      final res = await _api.get('/taxonomy');
      notifier.value = _withLocations(Taxonomy.fromMap(res));
      _loaded = true;
      await _writeCache(notifier.value);
    } catch (_) {
      // Offline or an older backend: keep the fallback / cached lists.
    }
  }

  Future<void> _readCache() async {
    if (_loaded) return;
    try {
      final box = await Hive.openBox(_boxName);
      final raw = box.get(_cacheKey) as String?;
      if (raw == null) return;
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        notifier.value = _withLocations(Taxonomy.fromMap(map));
      }
    } catch (_) {
      // Hive not initialised (tests) or a corrupt entry: ignore.
    }
  }

  Future<void> _writeCache(Taxonomy t) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_cacheKey, jsonEncode(t.toMap()));
    } catch (_) {}
  }
}
