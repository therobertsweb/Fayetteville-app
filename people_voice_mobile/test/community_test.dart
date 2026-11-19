import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/community.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets(
    'community opens listings and prepares suggestions without sending them',
    (tester) async {
      sqfliteFfiInit();
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      final requests = <String>[];
      final api = Api(
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('/events')
                  ? [
                      {
                        'id': 1,
                        'title': 'Neighborhood gathering',
                        'location': 'Town square',
                        'starts_at': '2026-10-01T18:00:00Z',
                      },
                    ]
                  : [],
              'pages': 1,
            }),
            200,
          );
        }),
      );
      Future<void> settle() async {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommunityHub(repository: Repository(api, store)),
          ),
        ),
      );
      await settle();
      await tester.tap(find.text('Neighborhood gathering'));
      await settle();
      expect(find.text('Event details'), findsOneWidget);
      expect(find.text('Open map'), findsOneWidget);
      await tester.pageBack();
      await settle();
      await tester.tap(find.text('Businesses'));
      await settle();
      expect(
        find.textContaining('No verified business listings yet'),
        findsOneWidget,
      );
      await tester.tap(find.text('Suggest a business'));
      await settle();
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        fields.any(
          (f) => f.controller?.text == 'Business directory submission',
        ),
        isTrue,
      );
      expect(requests.where((r) => r.startsWith('POST')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => store.db.close());
      api.client.close();
    },
  );
}
