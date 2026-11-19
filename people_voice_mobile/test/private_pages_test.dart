import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/drafts.dart';
import 'package:people_voice/ui/home.dart';
import 'package:people_voice/ui/my_articles.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Session extends Session {
  _Session(super.api);

  void select(int? owner) {
    value = owner == null
        ? null
        : {
            'user': {'id': owner, 'username': 'reader-$owner'},
            'access_token': 'token-$owner',
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          };
    notifyListeners();
  }
}

class _DelayedDraftStore extends LocalStore {
  _DelayedDraftStore(super.db);
  final nextAccount = Completer<List<Json>>();

  @override
  Future<List<Json>> drafts(int? userId) =>
      userId == 8 ? nextAccount.future : super.drafts(userId);
}

class _DelayedLibraryStore extends LocalStore {
  _DelayedLibraryStore(super.db);
  final nextAccount = Completer<List<Json>>();

  @override
  Future<List<Json>> favoriteArticles(int owner) => owner == 8
      ? nextAccount.future
      : Future.value([
          {'id': 7, 'title': 'Favorite for account 7'},
        ]);
}

Json _post(int owner) => {
  'id': owner,
  'title': 'Private article for account $owner',
  'status': 'draft',
  'views': 0,
  'comment_count': 0,
};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

void main() {
  late LocalStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => store.db.close());

  testWidgets(
    'server pagination encodes opaque cursors and stops repeated cursors',
    (tester) async {
      const cursor = 'page+/=?&owner=99';
      var requests = 0;
      final api = Api(
        client: MockClient((request) async {
          requests++;
          if (requests == 1) {
            expect(request.url.queryParameters, isEmpty);
          } else {
            expect(request.url.queryParameters, {'cursor': cursor});
          }
          return http.Response(
            jsonEncode({'data': [], 'next_cursor': cursor}),
            200,
          );
        }),
      );
      final session = _Session(api)..select(7);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyArticlesPage(
              repository: Repository(api, store, session: session),
              session: session,
              showServer: true,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(requests, 2);
      expect(
        find.textContaining('Could not load the complete article list'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.client.close();
    },
  );

  testWidgets('server pagination stops even when every cursor is different', (
    tester,
  ) async {
    var requests = 0;
    final api = Api(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'data': [], 'next_cursor': 'page-${++requests}'}),
          200,
        ),
      ),
    );
    final session = _Session(api)..select(7);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyArticlesPage(
            repository: Repository(api, store, session: session),
            session: session,
            showServer: true,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(requests, 100);
    expect(
      find.textContaining('Could not load the complete article list'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.client.close();
  });

  testWidgets(
    'server articles disappear immediately while another account loads',
    (tester) async {
      final nextAccount = Completer<http.Response>();
      final api = Api(
        client: MockClient((request) async {
          if (request.headers['Authorization'] == 'Bearer token-8') {
            return nextAccount.future;
          }
          return http.Response(
            jsonEncode({
              'data': [_post(7)],
              'next_cursor': null,
            }),
            200,
          );
        }),
      );
      final session = _Session(api)..select(7);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyArticlesPage(
              repository: Repository(api, store, session: session),
              session: session,
              showServer: true,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Private article for account 7'), findsOneWidget);
      session.select(8);
      await tester.pump();
      expect(find.text('Private article for account 7'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      nextAccount.complete(
        http.Response(
          jsonEncode({
            'data': [_post(8)],
            'next_cursor': null,
          }),
          200,
        ),
      );
      await _settle(tester);
      expect(find.text('Private article for account 8'), findsOneWidget);
      session.select(null);
      await tester.pump();
      expect(find.text('Private article for account 8'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.client.close();
    },
  );

  testWidgets(
    'device drafts reload without retaining another account snapshot',
    (tester) async {
      await tester.runAsync(
        () => store.saveDraft({
          'local_id': 'private-7',
          'owner_id': 7,
          'title': 'Private device draft for account 7',
          'state': 'local',
        }),
      );
      final delayed = _DelayedDraftStore(store.db);
      final api = Api(
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      final session = _Session(api)..select(7);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DraftsPage(
              repository: Repository(api, delayed, session: session),
              session: session,
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Private device draft for account 7'), findsOneWidget);
      session.select(8);
      await tester.pump();
      expect(find.text('Private device draft for account 7'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      delayed.nextAccount.complete([
        {
          'local_id': 'private-8',
          'owner_id': 8,
          'title': 'Private device draft for account 8',
          'state': 'local',
        },
      ]);
      await _settle(tester);
      expect(find.text('Private device draft for account 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.client.close();
    },
  );
  testWidgets('library refresh and account changes discard stale favorites', (
    tester,
  ) async {
    final delayed = _DelayedLibraryStore(store.db);
    final api = Api(client: MockClient((_) async => http.Response('{}', 503)));
    final session = _Session(api)..select(7);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryPage(
            repository: Repository(api, delayed, session: session),
          ),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Favorites'));
    await _settle(tester);
    expect(find.text('Favorite for account 7'), findsOneWidget);
    await tester.runAsync(
      () => tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh(),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    session.select(8);
    await tester.pump();
    expect(find.text('Favorite for account 7'), findsNothing);
    delayed.nextAccount.complete([]);
    await _settle(tester);
    expect(find.text('Keep your favorites close'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.client.close();
  });
}
