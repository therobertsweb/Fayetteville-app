import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/ui/contact.dart';

void main() {
  testWidgets('email fallback includes story and does not claim delivery', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    Uri? launched;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launched = Uri.parse(call.arguments['url'] as String);
        return true;
      }
      return false;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final api = Api();
    addTearDown(api.client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ContactPage(
          api: api,
          enabled: false,
          story: true,
          initialSubject: 'Story & neighborhood',
          initialMessage: 'Información + photos\nSecond line',
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Open email draft'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Open email draft'));
    await tester.pumpAndSettle();
    expect(launched?.scheme, 'mailto');
    expect(launched?.path, 'reporter@fayettevillethepeoplevoice.com');
    expect(launched?.queryParameters['subject'], 'Story & neighborhood');
    expect(
      launched?.queryParameters['body'],
      contains('Información + photos\nSecond line'),
    );
    expect(find.textContaining('Your message has been received'), findsNothing);
    expect(
      find.textContaining('Finish sending in your email app'),
      findsOneWidget,
    );
  });
}
