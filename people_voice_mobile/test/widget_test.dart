import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:people_voice/main.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('offline user can create a draft and reopen it from the list', (
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
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await tester.pumpWidget(
      PeopleVoiceApp(repository: Repository(api, store), session: Session(api)),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('My articles'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'Historia sin internet',
    );
    await tester.scrollUntilVisible(
      find.byType(quill.QuillEditor),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final editor = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller;
    editor.replaceText(
      0,
      0,
      'Mi draft persiste.',
      const TextSelection.collapsed(offset: 18),
    );
    editor.formatText(0, 2, quill.Attribute.bold);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('Historia sin internet'), findsOneWidget);
    await tester.tap(find.text('Historia sin internet'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(quill.QuillEditor),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final restored = tester
        .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
        .controller
        .document;
    expect(restored.toPlainText(), contains('Mi draft persiste.'));
    expect(restored.toDelta().toJson().first['attributes'], {'bold': true});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => store.db.close());
  });
}
