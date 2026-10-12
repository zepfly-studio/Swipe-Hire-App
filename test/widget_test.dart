import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiring_app/theme/app_theme.dart';

void main() {
  testWidgets('App theme renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: Center(child: Text('TalentSwipe'))),
    ));

    expect(find.text('TalentSwipe'), findsOneWidget);
  });
}
