import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_voice/ui/keyboard_dismiss.dart';

void main() {
  testWidgets('hide keyboard removes focus and preserves multiline text', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismiss(child: child!),
        home: Scaffold(
          body: TextField(
            controller: controller,
            focusNode: focus,
            maxLines: 5,
          ),
        ),
      ),
    );
    expect(find.text('Hide keyboard'), findsNothing);
    await tester.enterText(find.byType(TextField), 'My story\nMore details');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('Hide keyboard'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(controller.text, 'My story\nMore details');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
  });
}
