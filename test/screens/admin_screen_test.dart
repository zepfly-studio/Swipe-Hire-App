import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/screens/admin/admin_screen.dart';
import 'package:hiring_app/services/admin_service.dart';
import 'package:hiring_app/services/api_client.dart';

class _StubApi extends ApiClient {
  _StubApi() : super.forTest();

  final List<String> calls = [];
  final List<Map<String, dynamic>?> bodies = [];
  final List<Map<String, String>?> queries = [];
  final List<Map<String, dynamic>> companies = [
    {
      'id': 'c1',
      'companyName': 'No Papers Pvt',
      'website': 'https://nopapers.example',
      'location': 'Pune',
      'status': 'unverified',
      'verified': false,
      'method': '',
      'gstin': '',
      'contact': {'name': 'Asha', 'email': 'asha@gmail.com'},
    },
    {
      'id': 'c2',
      'companyName': 'Badge Holder',
      'status': 'verified',
      'verified': true,
      'method': 'admin',
      'gstin': '',
      'contact': {'name': 'Ravi', 'email': 'ravi@gmail.com'},
    },
    {
      'id': 'c3',
      'companyName': 'With Gstin',
      'status': 'pending',
      'verified': false,
      'method': 'gst',
      'gstin': '22AAAAA0000A1Z5',
      'contact': {'name': 'Mira', 'email': 'mira@gmail.com'},
    },
  ];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    calls.add('GET $path');
    bodies.add(null);
    queries.add(query);
    final status = query?['status'];
    final list = status == null ? companies : companies.where((c) => c['status'] == status).toList();
    return {'companies': list};
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) async {
    calls.add('POST $path');
    bodies.add(body);
    queries.add(null);
    if (path.endsWith('/verify')) {
      final id = path.split('/')[3];
      final row = companies.firstWhere((c) => c['id'] == id);
      final on = body?['verified'] == true;
      row['verified'] = on;
      row['status'] = on ? 'verified' : 'unverified';
      row['method'] = on ? 'admin' : '';
    }
    return {'ok': true};
  }
}

void main() {
  Future<_StubApi> pumpScreen(WidgetTester tester) async {
    final api = _StubApi();
    await tester.pumpWidget(MaterialApp(home: AdminScreen(service: AdminService.test(api))));
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('lists companies; a GSTIN is shown only when one was submitted', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No Papers Pvt'), findsOneWidget);
    expect(find.text('Badge Holder'), findsOneWidget);
    expect(find.text('Verify any company yourself. A GSTIN is not required.'), findsOneWidget);

    // No GSTIN submitted: no GSTIN row, but Verify is there.
    expect(find.byKey(const Key('gstin-c1')), findsNothing);
    expect(find.byKey(const Key('verify-c1')), findsOneWidget);
    // Already verified: Remove badge instead.
    expect(find.byKey(const Key('unverify-c2')), findsOneWidget);
    expect(find.byKey(const Key('verify-c2')), findsNothing);
    // A company that did submit a GSTIN shows it and can still be rejected.
    expect(find.byKey(const Key('gstin-c3')), findsOneWidget);
    expect(find.byKey(const Key('reject-c3')), findsOneWidget);
    expect(find.text('Verified by admin'), findsOneWidget);
    expect(find.text('Needs review'), findsWidgets);
  });

  testWidgets('Verify works without a GSTIN and refreshes the list', (tester) async {
    final api = await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('verify-c1')));
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /admin/companies/c1/verify'));
    expect(api.bodies[api.calls.indexOf('POST /admin/companies/c1/verify')], {'verified': true});
    // The list was reloaded: c1 now has Remove badge.
    expect(find.byKey(const Key('unverify-c1')), findsOneWidget);
    expect(find.byKey(const Key('verify-c1')), findsNothing);
  });

  testWidgets('Remove badge asks first, then un-verifies', (tester) async {
    final api = await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('unverify-c2')));
    await tester.pumpAndSettle();
    expect(find.text('Remove the verified badge from Badge Holder?'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('POST')), isEmpty, reason: 'nothing is sent before confirming');

    await tester.tap(find.text('Remove badge').last);
    await tester.pumpAndSettle();
    expect(api.calls, contains('POST /admin/companies/c2/verify'));
    expect(api.bodies[api.calls.indexOf('POST /admin/companies/c2/verify')], {'verified': false});
    expect(find.byKey(const Key('verify-c2')), findsOneWidget);
  });

  testWidgets('the filter chips ask the server for that status', (tester) async {
    final api = await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('admin-filter-pending')));
    await tester.pumpAndSettle();

    expect(api.queries.last, {'status': 'pending'});
    expect(find.text('With Gstin'), findsOneWidget);
    expect(find.text('No Papers Pvt'), findsNothing);
  });
}
