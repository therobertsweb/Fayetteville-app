import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/editorial.dart';
import 'package:people_voice/data/experience.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/notifications.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/home.dart';
import 'package:people_voice/ui/iphone_news.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'editorial_test.dart' show login, response;

class SwitchingSession extends Session {
  SwitchingSession(super.api);
  void switchTo(int id) {
    value = login(id);
    notifyListeners();
  }
}

class DelayedActivity extends Experience {
  DelayedActivity(super.store);
  final pending = Completer<void>();
  int calls = 0;
  @override
  Future<void> checkActivity() async {
    if (++calls == 1) await pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('a refresh interrupted by account switching never fetches for the old owner', () async {
    final store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final preferences = DelayedActivity(store);
    var capabilityCalls = 0;
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('capabilities')) {
          capabilityCalls++;
          return response({
            'data': {
              'user_id': 5,
              'role': 'commenter',
              'permissions': ['notifications:read'],
            },
          });
        }
        return response({
          'data': [
            {
              'id': 'new',
              'title': 'Private',
              'message': 'Account five',
              'created': '2026-11-19T12:00:00Z',
              'read': false,
            },
          ],
          'next_cursor': null,
        });
      }),
    );
    final session = SwitchingSession(api)..value = login(4);
    final inbox = NotificationInbox(
      EditorialGateway(api, session),
      store,
      preferences: preferences,
    );
    final first = inbox.refresh();
    session.switchTo(5);
    preferences.pending.complete();
    await first;
    for (var i = 0; inbox.busy && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(inbox.busy, isFalse);
    expect(capabilityCalls, 1);
    expect(await store.notifications(4), isEmpty);
    expect(inbox.unread, 1);
    inbox.dispose();
    preferences.dispose();
    session.dispose();
    api.client.close();
    await store.db.close();
  });

  testWidgets(
    'iPhone refreshes on launch, each active minute and resume, with unread badge',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      var refreshes = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('capabilities')) {
            refreshes++;
            return response({
              'data': {
                'user_id': 4,
                'role': 'commenter',
                'permissions': ['notifications:read'],
              },
            });
          }
          if (request.url.path.endsWith('/notifications')) {
            return response({
              'data': [
                {
                  'id': 'one',
                  'title': 'Reply',
                  'message': 'A new reply',
                  'created': '2026-11-19T12:00:00Z',
                  'read': false,
                },
              ],
              'next_cursor': null,
            });
          }
          return response({'data': [], 'pages': 1, 'next_cursor': null});
        }),
      );
      final session = Session(api)..value = login(4);
      await tester.pumpWidget(
        MaterialApp(
          theme: iphoneTheme(Brightness.light),
          home: Home(repository: Repository(api, store), session: session),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
      }

      await settle();
      expect(refreshes, 1);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget,
      );
      await tester.pump(const Duration(minutes: 1));
      await settle();
      expect(refreshes, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      await settle();
      expect(refreshes, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle();
      expect(refreshes, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
      session.dispose();
      api.client.close();
      await tester.runAsync(() => store.db.close());
    },
  );
}
