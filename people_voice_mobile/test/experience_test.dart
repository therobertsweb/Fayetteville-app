import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/community_tools.dart';
import 'package:people_voice/data/experience.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/data/promotions.dart';
import 'package:people_voice/ui/my_articles.dart';
import 'package:people_voice/ui/news_tips.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() async {
    await store.db.close();
  });

  test(
    'preferences survive offline, sync on retry, and stay account scoped',
    () async {
      bool online = false;
      final server = <String, dynamic>{};
      final api = Api(
        client: MockClient((request) async {
          if (!online) throw const SocketException('offline');
          expect(request.headers['Authorization'], 'Bearer token-7');
          if (request.method == 'POST') {
            final data = jsonDecode(request.body);
            server[data['key']] = data['value'];
          }
          return http.Response(jsonEncode({'data': server}), 200);
        }),
      );
      final prefs = Experience(
        store,
        api: api,
        tokenFor: (owner) => owner == 7 ? 'token-7' : null,
      );
      await prefs.load(7);
      await prefs.toggle('categories', 'business');
      await prefs.set('theme', 'dark');
      expect(prefs.theme, ThemeMode.dark);
      expect(prefs.syncWarning, isNotNull);
      await prefs.load(9);
      expect(prefs.strings('categories'), isEmpty);
      await prefs.load(7);
      expect(prefs.strings('categories'), ['business']);
      online = true;
      await prefs.sync();
      expect(server['categories'], ['business']);
      expect(server['theme'], 'dark');
      expect(prefs.syncWarning, isNull);
      expect(await store.cached('experience-pending:7'), isEmpty);
      api.client.close();
    },
  );

  test(
    'slow response from a previous account cannot overwrite the new account',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final api = Api(
        client: MockClient((request) {
          requested.complete();
          return response.future;
        }),
      );
      final prefs = Experience(
        store,
        api: api,
        tokenFor: (owner) => owner == 7 ? 'token' : null,
      );
      final loading = prefs.load(7);
      await requested.future;
      await prefs.load(8);
      response.complete(http.Response('{"data":{"authors":["99"]}}', 200));
      await loading;
      expect(prefs.owner, 8);
      expect(prefs.strings('authors'), isEmpty);
      api.client.close();
    },
  );

  test(
    'checkout passes stable operation ID and rejects lookalike domains',
    () async {
      final api = Api(
        client: MockClient((request) async {
          expect(
            jsonDecode(request.body)['operation_id'],
            'fixed-checkout-operation',
          );
          return http.Response(
            '{"data":{"checkout_url":"https://checkout.stripe.com.evil.example/pay"}}',
            201,
          );
        }),
      );
      await expectLater(
        api.featuredCheckout(
          postId: 1,
          token: 'token',
          operationId: 'fixed-checkout-operation',
        ),
        throwsA(isA<ApiFailure>()),
      );
      api.client.close();
    },
  );

  test(
    'app promotion checkout binds the article, token, and operation ID',
    () async {
      final promotionApi = PromotionApi(
        client: MockClient((request) async {
          expect(request.url.path, '/promotions/checkout');
          expect(request.headers['Authorization'], 'Bearer author-token');
          expect(jsonDecode(request.body), {
            'article_id': 42,
            'operation_id': 'a' * 32,
          });
          return http.Response(
            '{"data":{"checkout_url":"https://checkout.stripe.com/c/pay/cs_test_example"}}',
            201,
          );
        }),
      );
      expect(
        await promotionApi.checkout(
          articleId: 42,
          token: 'author-token',
          operationId: 'a' * 32,
        ),
        startsWith('https://checkout.stripe.com/'),
      );
      promotionApi.client.close();
    },
  );

  test(
    'calendar escapes untrusted text, folds UTF8, and preserves event offset',
    () {
      final event = {
        'id': 1,
        'title': 'A, B; C\n${'ñ' * 120}',
        'location': 'Town square',
        'starts_at': '2026-10-01T18:00:00-04:00',
        'ends_at': '2026-10-01T19:00:00-04:00',
      };
      final calendar = calendarEvent(event);
      expect(calendar, contains('DTSTART:20261001T220000Z'));
      expect(calendar, contains('DTEND:20261001T230000Z'));
      expect(calendar, contains(r'A\, B\; C\n'));
      expect(
        calendar.split('\r\n').every((line) => utf8.encode(line).length <= 75),
        isTrue,
      );
      expect(
        eventMatches(event, period: 'all', free: true, family: false),
        isFalse,
      );
      expect(
        eventMatches(
          {...event, 'is_free': true},
          period: 'all',
          free: true,
          family: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'category catalog understands server records and excludes test content',
    () async {
      final api = Api(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {'name': 'Business', 'slug': 'business'},
                {'name': 'Local Test Content', 'slug': 'test'},
              ],
            }),
            200,
          ),
        ),
      );
      final result = await Repository(api, store).categories();
      expect(result.body['data'], ['Business']);
      api.client.close();
    },
  );

  Session signedIn(Api api) => Session(api)
    ..value = {
      'user': {'id': 7, 'username': 'Writer', 'can_publish': true},
      'access_token': 'test-token',
      'expires_at': DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    };
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'My articles loads own server records and opens promotion pricing without charging',
    (tester) async {
      final requests = <String>[];
      final promotionRequests = <String>[];
      final promotionApi = PromotionApi(
        client: MockClient((request) async {
          promotionRequests.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/pricing')) {
            return http.Response(
              '{"data":{"amount_cents":500,"currency":"usd","days":7,"available":true}}',
              200,
            );
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      final api = Api(
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 1,
                  'title': 'My server story',
                  'content': '<p>Hello</p>',
                  'author': {'id': 7},
                  'status': 'published',
                  'published': true,
                  'can_edit': true,
                  'views': 12,
                  'comment_count': 2,
                },
              ],
              'next_cursor': null,
            }),
            200,
          );
        }),
      );
      final session = signedIn(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyArticlesPage(
              repository: Repository(
                api,
                store,
                session: session,
                promotions: promotionApi,
              ),
              session: session,
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('My server articles'));
      await settle(tester);
      expect(find.text('My server story'), findsOneWidget);
      expect(find.textContaining('Reads: 12'), findsOneWidget);
      await tester.tap(find.text('Promote article'));
      await settle(tester);
      expect(find.text('USD 5.00 · 7 days'), findsOneWidget);
      expect(find.text('Continue to Stripe'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to Stripe'),
            )
            .onPressed,
        isNull,
        reason: 'A server without paid review must not start another charge.',
      );
      expect(requests.where((r) => r.startsWith('POST')), isEmpty);
      expect(promotionRequests, contains('GET /promotions/pricing'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.client.close();
      promotionApi.client.close();
    },
  );

  testWidgets('configured app promotion service enables each author checkout', (
    tester,
  ) async {
    final api = Api(client: MockClient((_) async => http.Response('{}', 200)));
    final promotionApi = PromotionApi(
      client: MockClient((request) async {
        expect(request.url.path, '/promotions/pricing');
        return http.Response(
          '{"data":{"amount_cents":500,"currency":"usd","days":7,"available":true,"review_enabled":true}}',
          200,
        );
      }),
    );
    final repository = Repository(
      api,
      store,
      session: signedIn(api),
      promotions: promotionApi,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PromotionPage(
          repository: repository,
          post: {'id': 42, 'title': 'Published article'},
        ),
      ),
    );
    await settle(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue to Stripe'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.client.close();
    promotionApi.client.close();
  });

  testWidgets('story returns to newsroom and retries the same receipt', (
    tester,
  ) async {
    final writes = <Json>[];
    final api = Api(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/me/submissions');
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.method == 'POST') {
          writes.add(jsonDecode(request.body) as Json);
          if (writes.length == 1) return http.Response('{}', 503);
          return http.Response('{"data":{"id":1,"status":"received"}}', 200);
        }
        return http.Response('{"data":[],"next_cursor":null}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NewsTipsPage(
          repository: Repository(api, store, session: signedIn(api)),
        ),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'Neighborhood story');
    await tester.enterText(
      find.byType(TextField).at(1),
      'Details for the newsroom',
    );
    await tester.enterText(find.byType(TextField).at(2), 'Fayetteville');
    expect(find.text('Attach photo'), findsOneWidget);
    await tester.ensureVisible(find.text('Send to newsroom'));
    await tester.tap(find.text('Send to newsroom'));
    await settle(tester);
    expect(find.text('Retry same submission'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry same submission'));
    await tester.tap(find.text('Retry same submission'));
    await settle(tester);
    expect(writes.length, 2);
    expect(writes[0], writes[1]);
    expect(writes.first['kind'], 'news_tip');
    expect(writes.first['title'], 'Neighborhood story');
    expect(writes.first['body'], 'Details for the newsroom');
    expect(writes.first['location'], 'Fayetteville');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.client.close();
  });
}
