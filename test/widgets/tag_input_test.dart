import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/inputs/tag_input.dart';

void main() {
  Future<List<String> Function()> pump(WidgetTester tester, List<String> initial) async {
    var tags = [...initial];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TagInput(
            tags: tags,
            options: const ['React', 'Excel', 'Node.js'],
            hintText: 'Skills',
            onChanged: (v) => setState(() => tags = v),
          ),
        ),
      ),
    ));
    return () => tags;
  }

  testWidgets('a comma adds exactly what was typed, using the list spelling', (tester) async {
    final read = await pump(tester, []);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '​react,');
    await tester.pump();
    expect(read(), ['React']);
    expect(find.text('React'), findsOneWidget);
  });

  testWidgets('duplicates are ignored case-insensitively', (tester) async {
    final read = await pump(tester, ['React']);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '​REACT,');
    await tester.pump();
    expect(read(), ['React']);
  });

  testWidgets('Enter adds the top suggestion', (tester) async {
    final read = await pump(tester, []);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '​ex');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(read(), ['Excel']);
  });

  testWidgets('deleting from an empty input removes the last chip', (tester) async {
    final read = await pump(tester, ['React', 'Excel']);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    // The zero-width sentinel is deleted by Backspace on an empty field.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(read(), ['React']);
  });

  testWidgets('the close icon removes a chip', (tester) async {
    final read = await pump(tester, ['React', 'Excel']);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    expect(read(), ['Excel']);
  });
}
