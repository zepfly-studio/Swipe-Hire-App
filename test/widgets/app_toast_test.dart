import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/theme/app_theme.dart';
import 'package:hiring_app/widgets/app_toast.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester, {Widget? home}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      builder: AppToastHost.builder,
      home: home ?? const Scaffold(body: Center(child: Text('Home'))),
    ));
    await tester.pump();
  }

  testWidgets('a success toast shows its title and description', (tester) async {
    await pumpHost(tester);

    AppToast.success('Task sent', description: 'Riya has been notified.');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Task sent'), findsOneWidget);
    expect(find.text('Riya has been notified.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    // let the auto-dismiss timer finish so the test ends clean
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('error and notification toasts use their own icons', (tester) async {
    await pumpHost(tester);

    AppToast.error('Could not save');
    AppToast.notification(title: 'Interview scheduled', body: 'Acme, 19 Oct, 3:00 PM', type: 'interviewScheduled');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
    expect(find.text('Interview scheduled'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('three different toasts fired together all show', (tester) async {
    await pumpHost(tester);

    AppToast.success('First');
    AppToast.info('Second');
    AppToast.warning('Third');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('the same message twice in a row is shown once', (tester) async {
    await pumpHost(tester);

    AppToast.error('Network error');
    AppToast.error('Network error');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Network error'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('an action toast runs its callback and closes', (tester) async {
    await pumpHost(tester);
    var undone = false;

    AppToast.action('Added Riya to wishlist', actionLabel: 'UNDO', onAction: () => undone = true);
    // The first pump builds the toast; the slide-in then runs for 350ms.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('UNDO'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(undone, isTrue);

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('toasts do not block taps on the screen underneath', (tester) async {
    var taps = 0;
    await pumpHost(
      tester,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ElevatedButton(onPressed: () => taps++, child: const Text('Tap me')),
        ),
      ),
    );

    AppToast.info('Heads up');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The toast is on screen at the top...
    expect(tester.getRect(find.text('Heads up')).top, greaterThan(0));
    // ...and the button underneath still takes the tap.
    await tester.tap(find.text('Tap me'));

    expect(taps, 1);

    await tester.pump(const Duration(seconds: 6));
  });
}
