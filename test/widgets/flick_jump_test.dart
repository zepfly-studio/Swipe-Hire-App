import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/widgets/flick_jump.dart';

void main() {
  final scroll = ScrollController();
  final video = GlobalKey();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlickJump(
            controller: scroll,
            target: video,
            child: SingleChildScrollView(
              key: const Key('scroll'),
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1500),
                  SizedBox(key: video, height: 300, child: const Text('video')),
                  const SizedBox(height: 1500),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double videoOffset(WidgetTester tester) {
    // Distance from the top of the scroll content to the video.
    return 1500;
  }

  testWidgets('a quick swipe up jumps to the video', (tester) async {
    await pump(tester);
    await tester.fling(find.byKey(const Key('scroll')), const Offset(0, -300), 3000);
    await tester.pumpAndSettle();
    // The video sits near the top of the viewport (alignment 0.05), not wherever the fling would end.
    final top = tester.getTopLeft(find.text('video')).dy;
    expect(top, lessThan(120), reason: 'video scrolled into view, top=$top, offset=${scroll.offset}');
    expect(scroll.offset, closeTo(videoOffset(tester) - 30, 60));
  });

  testWidgets('a slow drag just scrolls', (tester) async {
    await pump(tester);
    await tester.drag(find.byKey(const Key('scroll')), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(200, 1));
  });

  testWidgets('a quick swipe down jumps back to the top', (tester) async {
    await pump(tester);
    scroll.jumpTo(1450);
    await tester.pump();
    await tester.fling(find.byKey(const Key('scroll')), const Offset(0, 300), 3000);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });
}
