import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/reader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'administrators can match comment IDs with verified account names',
    () async {
      sqfliteFfiInit();
      final store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final requests = <String>[];
      final api = Api(
        client: MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path.endsWith('/mobile/capabilities')) {
            return http.Response(
              '{"data":{"user_id":2,"role":"admin","permissions":[]}}',
              200,
            );
          }
          return http.Response(
            '{"data":[{"id":32,"username":"Morgan"}],"next_cursor":null}',
            200,
          );
        }),
      );
      final session = Session(api)
        ..value = {
          'user': {'id': 2, 'username': 'Admin'},
          'access_token': 'test-token',
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        };
      final repository = Repository(api, store, session: session);
      await repository.loadAdminUserNames();
      expect(repository.authorName(32), 'Morgan');
      expect(requests, ['/api/v1/mobile/capabilities', '/api/v1/admin/users']);
      session.value = {
        ...session.value!,
        'user': {'id': 3, 'username': 'Reader'},
      };
      await repository.loadAdminUserNames();
      expect(repository.authorName(32), isNull);
      expect(requests.last, '/api/v1/mobile/capabilities');
      await store.db.close();
      api.client.close();
    },
  );

  for (final retry in [false, true]) {
    testWidgets('reply publishes its own draft (retry: $retry)', (
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
      final writes = <http.Request>[];
      final api = Api(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes.add(request);
            if (retry && writes.length == 2) return http.Response('{}', 503);
            return http.Response('{"data":{"id":99}}', 200);
          }
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 10,
                  'author_id': 1,
                  'author': {'username': 'Avery'},
                  'content': 'Original comment',
                  'parent_id': null,
                },
              ],
              'pages': 1,
            }),
            200,
          );
        }),
      );
      final session = Session(api)
        ..value = {
          'user': {'id': 2, 'username': 'Reader'},
          'access_token': 'test-token',
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        };
      Future<void> settle() async {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: CommentsPage(
            repository: Repository(api, store, session: session),
            postId: 1,
          ),
        ),
      );
      await settle();
      expect(find.text('Avery'), findsOneWidget);
      expect(find.textContaining('User 1'), findsNothing);
      await tester.tap(find.text('Reply'));
      await settle();
      await tester.enterText(find.byType(TextField), 'My reply');
      await tester.tap(find.text('Publish'));
      await settle();
      if (retry) {
        expect(find.text('My reply'), findsOneWidget);
        await tester.tap(find.text('Retry publishing'));
        await settle();
      }
      expect(tester.takeException(), isNull);
      expect(writes, hasLength(retry ? 3 : 2));
      expect(jsonDecode(writes.first.body)['parent_id'], 10);
      expect(writes.last.url.path, '/api/v1/comments/99/publish');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => store.db.close());
      api.client.close();
    });
  }
}
