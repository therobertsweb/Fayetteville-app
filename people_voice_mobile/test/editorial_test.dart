import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/editorial.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/notifications.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/admin.dart';
import 'package:people_voice/ui/ai_assistant.dart';
import 'package:people_voice/ui/brand.dart';
import 'package:people_voice/ui/charts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Json login(int id) => {
  'user': {'id': id, 'username': 'Admin'},
  'access_token': 'test',
  'expires_at': '2099-01-01T00:00:00Z',
};
http.Response response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);
Json access(int id, List<String> permissions) => {
  'data': {'user_id': id, 'role': 'admin', 'permissions': permissions},
};
Json draft(int id, String name, String role) => {
  'id': id,
  'title': 'Historia $id',
  'version': 'v$id',
  'author': {'id': id, 'username': name, 'role': role},
  'content': 'Texto',
};

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'unavailable editorial services stay disabled without network calls',
    () async {
      var requests = 0;
      final api = Api(
        client: MockClient((request) async {
          requests++;
          return response(access(4, ['ai:write', 'drafts:manage']));
        }),
      );
      final session = Session(api)..value = login(4);
      final gateway = EditorialGateway(api, session, enabled: false);
      expect((await gateway.capabilities()).review, isFalse);
      await expectLater(
        gateway.improve(
          title: 'Title',
          content: 'Draft',
          instruction: 'Improve',
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'notifications persist, deduplicate and remain account scoped',
    () async {
      final store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(store.db.close);
      final local = {
        'local_id': 'one',
        'owner_id': 4,
        'title': 'Mi noticia',
        'state': 'local',
      };
      await store.saveDraft(local);
      expect(await store.notifications(4), isEmpty);
      local['state'] = 'published';
      await store.saveDraft(local);
      await store.saveDraft(local);
      expect(await store.notifications(4), hasLength(1));
      expect(await store.notifications(5), isEmpty);
      final remote = {
        'id': 'n1',
        'title': 'Comment',
        'message': 'Nueva respuesta',
        'created': '2026-09-28T10:00:00Z',
        'read': false,
      };
      await store.mergeNotifications(4, [remote]);
      await store.readNotifications(4, ['remote:n1']);
      await store.mergeNotifications(4, [remote]);
      expect(
        (await store.notifications(4))
            .singleWhere((n) => n['id'] == 'remote:n1')['read'],
        isTrue,
      );
      expect(await store.pendingNotificationReads(4), ['n1']);
      await store.acknowledgeNotificationReads(4, ['n1']);
      expect(await store.pendingNotificationReads(4), isEmpty);
      await store.mergeNotifications(4, [
        {...remote, 'id': 'promotion:51', 'title': 'Paid article'},
      ]);
      await store.readNotifications(4, ['remote:promotion:51']);
      expect(
        await store.pendingNotificationReads(4),
        isEmpty,
        reason: 'App-only promotion alerts must not be sent to the news API.',
      );
    },
  );

  test('version 2 database migrates without losing drafts', () async {
    final dir = await Directory.systemTemp.createTemp('voice-notifications-');
    final path = '${dir.path}/migration.db';
    var db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE drafts (id TEXT PRIMARY KEY, body TEXT NOT NULL, updated_at TEXT NOT NULL)',
          );
          await db.insert('drafts', {
            'id': 'kept',
            'body': '{"title":"Conservar"}',
            'updated_at': '2026-01-01',
          });
        },
      ),
    );
    await db.close();
    final store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect((await store.draft('kept'))?['title'], 'Conservar');
    expect(await store.notifications(1), isEmpty);
    await store.db.close();
    await dir.delete(recursive: true);
  });

  test('inbox synchronizes read state and retains offline messages', () async {
    final store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(store.db.close);
    bool offline = false;
    final reads = <Object?>[];
    final api = Api(
      client: MockClient((request) async {
        if (offline) throw const SocketException('offline');
        if (request.url.path.endsWith('capabilities')) {
          return response(access(4, ['notifications:read']));
        }
        if (request.url.path.endsWith('/read')) {
          reads.add(jsonDecode(request.body)['ids']);
          return response({});
        }
        return response({
          'data': [
            {
              'id': 'n1',
              'title': 'Comment',
              'message': 'Hola',
              'created': '2026-09-28T10:00:00Z',
              'read': false,
            },
          ],
          'next_cursor': null,
        });
      }),
    );
    final session = Session(api)..value = login(4);
    final inbox = NotificationInbox(
      EditorialGateway(api, session, enabled: true),
      store,
    );
    addTearDown(inbox.dispose);
    await inbox.refresh();
    expect(inbox.unread, 1);
    offline = true;
    await inbox.markRead(['remote:n1']);
    expect(inbox.unread, 0);
    expect(inbox.items, hasLength(1));
    expect(inbox.error, isNotNull);
    offline = false;
    await inbox.refresh();
    expect(reads, [
      ['n1'],
    ]);
    expect(inbox.unread, 0);
  });

  test(
    'uncertain bulk operation cannot be resent and reconciles by receipt',
    () async {
      final store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(store.db.close);
      String? operation;
      var writes = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('capabilities')) {
            return response(access(4, ['drafts:manage']));
          }
          if (request.url.path.endsWith('/bulk')) {
            writes++;
            operation = jsonDecode(request.body)['operation_id'] as String;
            throw const SocketException('response lost');
          }
          return response({
            'operation_id': operation,
            'status': 'completed',
            'results': [
              {'id': 1, 'success': true},
              {'id': 2, 'success': false, 'message': 'Version changed'},
            ],
          });
        }),
      );
      final session = Session(api)..value = login(4);
      final operations = AdminOperations(
        EditorialGateway(api, session, enabled: true),
        store,
      );
      final drafts = [draft(1, 'Ana', 'author'), draft(2, 'Luis', 'editor')];
      await expectLater(
        operations.run('publish', drafts),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        operations.run('delete', drafts),
        throwsA(isA<ApiFailure>()),
      );
      expect(writes, 1);
      await operations.reconcile();
      expect(await operations.pending(), isNull);
    },
  );

  test('bulk writes require admin permissions and complete receipts', () async {
    final store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(store.db.close);
    var allowed = false;
    var writes = 0;
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('capabilities')) {
          return response(access(4, allowed ? ['drafts:manage'] : []));
        }
        writes++;
        final body = jsonDecode(request.body);
        return response({
          'operation_id': body['operation_id'],
          'status': 'completed',
          'results': [],
        });
      }),
    );
    final session = Session(api)..value = login(4);
    final operations = AdminOperations(
      EditorialGateway(api, session, enabled: true),
      store,
    );
    final items = [draft(1, 'Ana', 'author')];
    await expectLater(
      operations.run('delete', items),
      throwsA(isA<ApiFailure>()),
    );
    expect(writes, 0);
    allowed = true;
    await expectLater(
      operations.run('publish', items),
      throwsA(isA<ApiFailure>()),
    );
    expect(writes, 1);
    expect(await operations.pending(), isNotNull);
  });

  testWidgets('AI generates from an idea and only applies after review', (
    tester,
  ) async {
    Json? sent;
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('capabilities')) {
          return response(access(4, ['ai:write']));
        }
        sent = jsonDecode(request.body) as Json;
        return response({
          'data': {
            'title': 'Nuevo título',
            'content': 'Propuesta para revisar',
          },
        });
      }),
    );
    final session = Session(api)..value = login(4);
    await tester.pumpWidget(
      MaterialApp(
        theme: Brand.theme(),
        home: AiAssistant(
          gateway: EditorialGateway(api, session, enabled: true),
          title: '',
          content: '',
        ),
      ),
    );
    await tester.tap(find.text('Create a draft'));
    await tester.enterText(
      find.byType(TextField),
      'Una feria comunitaria el sábado',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Get suggestion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get suggestion'));
    await tester.pumpAndSettle();
    expect(sent?['instruction'], contains('Una feria comunitaria'));
    await tester.scrollUntilVisible(
      find.text('Apply suggestion to draft'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == 'Propuesta para revisar',
      ),
      findsOneWidget,
    );
    expect(find.text('Apply suggestion to draft'), findsOneWidget);
  });

  testWidgets('article charts handle long titles, zeros and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: ListView(
              children: [
                ArticleRankingChart(
                  metric: 'saves',
                  items: [
                    {
                      'article': {
                        'id': 1,
                        'title': 'Un título largo que debe adaptarse al ancho de un teléfono pequeño',
                      },
                      'count': 0,
                    },
                    {
                      'article': {'id': 2, 'title': 'Otra historia'},
                      'count': 150,
                    },
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('150 favorites'), findsOneWidget);
  });

  testWidgets(
    'admin selects a user group and cancels deletion without a write',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      var writes = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.method == 'POST') writes++;
          if (request.url.path.endsWith('capabilities')) {
            return response(access(4, ['drafts:manage']));
          }
          return response({
            'data': [
              draft(1, 'Ana', 'author'),
              draft(2, 'Ana', 'author'),
              draft(3, 'Luis', 'editor'),
            ],
            'next_cursor': null,
          });
        }),
      );
      final session = Session(api)..value = login(4);
      await tester.pumpWidget(
        MaterialApp(
          theme: Brand.theme(),
          home: AdminPage(
            gateway: EditorialGateway(api, session, enabled: true),
            store: store,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      expect(find.text('3 drafts · 2 selected'), findsOneWidget);
      await tester.tap(find.text('Delete selected'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 drafts'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(store.db.close);
    },
  );

  testWidgets('admin checks social services without exposing provider names', (
    tester,
  ) async {
    late LocalStore store;
    await tester.runAsync(() async {
      store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/mobile/capabilities')) {
          return response({
            'data': {
              'user_id': 4,
              'role': 'admin',
              'permissions': [
                'drafts:manage',
                'analytics:read',
                'social:manage',
              ],
              'services': {'openai': true, 'social_media': true},
            },
          });
        }
        if (request.url.path.endsWith('/admin/drafts')) {
          return response({'data': <Json>[], 'next_cursor': null});
        }
        if (request.url.path.endsWith('/admin/statistics')) {
          return response({
            'data': {
              'published': 0,
              'drafts': 0,
              'active_authors': 0,
              'by_author': <Json>[],
              'most_saved': <Json>[],
              'most_commented': <Json>[],
            },
          });
        }
        if (request.url.path.endsWith('/admin/integrations')) {
          return response({
            'data': {
              'openai': {'configured': true, 'model': 'writer-model'},
              'social_media': {'configured': true, 'mode': 'queue'},
            },
          });
        }
        if (request.url.path.endsWith('/admin/social/channels')) {
          return response({
            'data': [
              {'id': 'one', 'name': 'Community page', 'service': 'facebook'},
            ],
          });
        }
        throw StateError('Unexpected request ${request.url.path}');
      }),
    );
    final session = Session(api)..value = login(4);
    await tester.pumpWidget(
      MaterialApp(
        theme: Brand.theme(),
        home: AdminPage(
          gateway: EditorialGateway(api, session, enabled: true),
          store: store,
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    expect(find.text('Social media publishing'), findsOneWidget);
    expect(find.textContaining('Buffer'), findsNothing);
    await tester.tap(find.text('Check connected social channels'));
    await settle(tester);
    expect(find.text('Community page'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.db.close);
  });
}
