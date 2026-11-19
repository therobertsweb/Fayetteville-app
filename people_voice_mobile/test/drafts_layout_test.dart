import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/brand.dart';
import 'package:people_voice/ui/drafts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('draft route has readable Material styling in $brightness', (
      tester,
    ) async {
      sqfliteFfiInit();
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      final api = Api(
        client: MockClient((_) async => throw StateError('offline')),
      );
      final session = Session(api);
      await tester.pumpWidget(
        MaterialApp(
          theme: Brand.theme(brightness: brightness),
          home: DraftsPage(
            repository: Repository(api, store),
            session: session,
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final notice = find.text(
        'Write offline. Your drafts stay here until you choose to submit them online.',
      );
      final context = tester.element(notice);
      final style = DefaultTextStyle.of(context).style;
      expect(style.fontSize, lessThan(20));
      expect(style.decoration, isNot(TextDecoration.underline));
      expect(
        find.ancestor(of: notice, matching: find.byType(Material)),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await tester.runAsync(() => store.db.close());
    });
  }
}
