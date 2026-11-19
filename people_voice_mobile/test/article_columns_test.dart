import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_voice/ui/responsive.dart';

void main() {
  testWidgets('hidden articles leave no empty columns after an async update', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hidden = ValueNotifier(false);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArticleColumns(
              children: [
                for (var i = 0; i < 6; i++)
                  ValueListenableBuilder<bool>(
                    valueListenable: hidden,
                    builder: (context, hide, _) => hide && (i == 1 || i == 3)
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: () => taps++,
                            child: Container(
                              key: ValueKey('card-$i'),
                              height: i == 0 ? 220 : 180,
                              color: Colors.white,
                              child: Text('Article $i'),
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    hidden.value = true;
    await tester.pump();
    final first = tester.getRect(find.byKey(const ValueKey('card-0')));
    final second = tester.getRect(find.byKey(const ValueKey('card-2')));
    final third = tester.getRect(find.byKey(const ValueKey('card-4')));
    final fourth = tester.getRect(find.byKey(const ValueKey('card-5')));
    expect(second.top, first.top);
    expect(second.left, closeTo(first.right + 16, .01));
    expect(third.top, first.top);
    expect(third.left, closeTo(second.right + 16, .01));
    expect(fourth.left, first.left);
    expect(fourth.top, first.bottom);
    await tester.tap(find.byKey(const ValueKey('card-4')));
    expect(taps, 1);
    // Resizing back to a phone keeps all visible cards in reading order.
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pump();
    final mobileSecond = tester.getRect(find.byKey(const ValueKey('card-2')));
    expect(mobileSecond.left, 0);
    expect(mobileSecond.top, 220);
    expect(mobileSecond.width, 390);
    hidden.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('card-1')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-2'))).dy, 400);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    hidden.dispose();
  });
}
