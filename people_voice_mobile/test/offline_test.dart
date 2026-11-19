import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/publisher.dart';
import 'package:people_voice/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Json draft() => {
  'local_id': 'test-draft',
  'url': 'mobile-test-draft',
  'state': 'local',
  'title': 'Mi ciudad',
  'title_2': 'Una historia que cambia nuestra ciudad',
  'title_3': 'Mi ciudad',
  'subtitle': 'Una historia local para nuestra comunidad.',
  'subtitle_2': 'Vecinos explican cómo este cambio afecta a la comunidad.',
  'tag_1': 'Fayetteville',
  'tag_2': 'Local news',
  'info': 'Community',
  'content': '<p>Una historia local</p>',
  'plain_text': 'Una historia local',
  'photo_link': 'https://example.org/photo.jpg',
  'categories': 'Community',
  'owner_id': 7,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late LocalStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('people-voice-test-');
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/app.db',
    );
  });
  tearDown(() async {
    await store.db.close();
    await temp.delete(recursive: true);
  });

  test('generic binary images are validated and cached for offline use', () async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    var requests = 0;
    final api = Api(client: MockClient((request) async {
      requests++;
      return http.Response.bytes(bytes, 200, headers: {
        'content-type': 'application/octet-stream',
      });
    }));
    addTearDown(api.client.close);
    final repository = Repository(api, store);
    const url = 'https://example.org/static/photo.png';
    expect(await repository.image(url), bytes);
    expect(await repository.image(url), bytes);
    expect(requests, 1);
  });

  test('invalid generic binary responses are not cached and can retry', () async {
    var requests = 0;
    final api = Api(client: MockClient((request) async {
      requests++;
      return http.Response('<html>Missing image</html>', 200, headers: {
        'content-type': 'application/octet-stream',
      });
    }));
    addTearDown(api.client.close);
    final repository = Repository(api, store);
    const url = 'https://example.org/static/photo.webp';
    expect(await repository.image(url), isNull);
    expect(await store.image(url), isNull);
    expect(await repository.image(url), isNull);
    expect(requests, 2);
  });

  test(
    'category results exclude keyword-only matches and preserve pagination',
    () async {
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.startsWith('/api/v1/categories/')) {
            return http.Response('{}', 404);
          }
          expect(request.url.path, '/api/v1/search');
          expect(request.url.queryParameters['q'], 'Business');
          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 1,
                  'title': 'Local shop',
                  'categories': 'business',
                  'photo_link': null,
                },
                {
                  'id': 2,
                  'title': 'Business mentioned in politics',
                  'categories': 'Politics',
                  'photo_link': null,
                },
              ],
              'page': 2,
              'pages': 3,
            }),
            200,
          );
        }),
      );
      final repository = Repository(api, store);
      final result = await repository.categoryArticles('Business', page: 2);
      expect((result.body['data'] as List).map((row) => row['id']), [1]);
      expect(result.body['pages'], 3);
      await repository.coverDownloads;
      api.client.close();
    },
  );

  test(
    'article content and drafts survive closing and reopening SQLite offline',
    () async {
      final api = Api(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': {
                'id': 366,
                'title': 'News',
                'content': '<p>Full article</p>',
              },
            }),
            200,
          ),
        ),
      );
      await Repository(api, store).article(366);
      await store.saveDraft(draft());
      await store.db.close();
      store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: '${temp.path}/app.db',
      );
      final offline = Api(
        client: MockClient((_) async => throw const SocketException('Offline')),
      );
      expect(
        (await Repository(offline, store).article(366))['content'],
        '<p>Full article</p>',
      );
      expect(
        (await store.draft('test-draft'))!['plain_text'],
        'Una historia local',
      );
      expect(await store.drafts(8), isEmpty);
      expect(await store.drafts(7), hasLength(1));
    },
  );

  test(
    'submit for review creates a remote draft without publishing it',
    () async {
      await store.saveDraft(draft());
      final paths = <String>[];
      final api = Api(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('{"data":{"id":42}}', 201);
        }),
      );
      final publisher = Publisher(api, store);
      await publisher.publish(
        'test-draft',
        userId: 7,
        token: 'x',
        publishNow: false,
      );
      expect(paths, ['/api/v1/posts']);
      expect((await store.draft('test-draft'))!['state'], 'remote');
      await publisher.publish('test-draft', userId: 7, token: 'x');
      expect(paths, ['/api/v1/posts', '/api/v1/posts/42/publish']);
      expect((await store.draft('test-draft'))!['state'], 'published');
    },
  );

  test(
    'publication sends every field used by the web article template',
    () async {
      await store.saveDraft(draft());
      Json? sent;
      final api = Api(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Json;
          return http.Response('{"data":{"id":42}}', 201);
        }),
      );
      await Publisher(
        api,
        store,
      ).publish('test-draft', userId: 7, token: 'x', publishNow: false);
      expect(sent, containsPair('info', 'Community'));
      expect(sent, containsPair('tag_1', 'Fayetteville'));
      expect(sent, containsPair('tag_2', 'Local news'));
      expect(
        sent,
        containsPair('title_2', 'Una historia que cambia nuestra ciudad'),
      );
      expect(sent, containsPair('title_3', 'Mi ciudad'));
      expect(
        sent,
        containsPair('subtitle', 'Una historia local para nuestra comunidad.'),
      );
      expect(
        sent,
        containsPair(
          'subtitle_2',
          'Vecinos explican cómo este cambio afecta a la comunidad.',
        ),
      );
    },
  );

  test('offline cached text does not wait for any image request', () async {
    await store.saveArticle({
      'id': 5,
      'content': '<p>Read offline</p>',
      'photo_link': 'https://example.org/large.jpg',
    });
    final api = Api(
      client: MockClient(
        (_) async => throw StateError('No network request allowed'),
      ),
    );
    expect(
      (await Repository(api, store).article(5))['content'],
      '<p>Read offline</p>',
    );
  });

  test('favorites persist per account and a stale acknowledgment cannot clear a newer change', () async {
    await store.saveArticle({
      'id': 5,
      'title': 'News',
      'content': '<p>Article</p>',
    });
    await store.setFavorite(7, 5, true, 'revision-one');
    expect(await store.favoriteArticles(7), hasLength(1));
    expect(await store.favoriteArticles(8), isEmpty);
    await store.setFavorite(7, 5, false, 'revision-two');
    await store.acknowledgeFavorite(7, 5, 'revision-one');
    expect(await store.favoriteArticles(7), isEmpty);
    expect(
      (await store.pendingFavorites(7)).single['revision'],
      'revision-two',
    );
    await store.db.close();
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/app.db',
    );
    expect((await store.pendingFavorites(7)).single['saved'], 0);
  });

  test('feed refresh cannot replace the full offline article', () async {
    await store.saveArticle({'id': 1, 'content': '<p>Keep me</p>'});
    final api = Api(
      client: MockClient(
        (_) async => http.Response(
          '{"data":[{"id":1,"title":"Summary"}],"page":1,"pages":1}',
          200,
        ),
      ),
    );
    await Repository(api, store).feed('/posts?page=1');
    expect((await store.article(1))!['content'], '<p>Keep me</p>');
    final offline = Api(
      client: MockClient((_) async => throw const SocketException('Offline')),
    );
    final cached = await Repository(offline, store).feed('/posts?page=1');
    expect(cached.body['data'], hasLength(1));
    expect(cached.warning, isNotNull);
  });

  test('HTTP 500 detail never becomes a fake downloaded article', () async {
    final api = Api(client: MockClient((_) async => http.Response('{}', 500)));
    await expectLater(
      Repository(api, store).article(366),
      throwsA(isA<ApiFailure>()),
    );
    expect(await store.articles(), isEmpty);
  });

  test(
    'publication failure retains remote ID; retry does not create twice',
    () async {
      await store.saveDraft(draft());
      int creates = 0, publishes = 0;
      final api = Api(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          if (request.url.path == '/api/v1/posts') {
            creates++;
            return http.Response('{"data":{"id":42}}', 201);
          }
          expect(request.url.path, '/api/v1/posts/42/publish');
          publishes++;
          return http.Response('{}', publishes == 1 ? 503 : 200);
        }),
      );
      final publisher = Publisher(api, store);
      await expectLater(
        publisher.publish('test-draft', userId: 7, token: 'test-token'),
        throwsA(isA<ApiFailure>()),
      );
      expect((await store.draft('test-draft'))!['remote_id'], 42);
      expect((await store.draft('test-draft'))!['state'], 'remote');
      await publisher.publish('test-draft', userId: 7, token: 'test-token');
      expect(creates, 1);
      expect(publishes, 2);
      expect((await store.draft('test-draft'))!['state'], 'published');
    },
  );

  test('ambiguous creation survives restart and blocks blind retry', () async {
    await store.saveDraft(draft());
    int requests = 0;
    final api = Api(
      client: MockClient((_) async {
        requests++;
        throw const SocketException('Lost response');
      }),
    );
    await expectLater(
      Publisher(api, store).publish('test-draft', userId: 7, token: 'x'),
      throwsA(isA<ApiFailure>()),
    );
    expect((await store.draft('test-draft'))!['state'], 'uncertain');
    await store.db.close();
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/app.db',
    );
    await expectLater(
      Publisher(api, store).publish('test-draft', userId: 7, token: 'x'),
      throwsA(isA<ApiFailure>()),
    );
    expect(requests, 1);
  });

  test(
    'known rejection preserves editable draft; wrong account sends nothing',
    () async {
      await store.saveDraft(draft());
      int calls = 0;
      final api = Api(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 401);
        }),
      );
      final publisher = Publisher(api, store);
      await expectLater(
        publisher.publish('test-draft', userId: 8, token: 'x'),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 0);
      await expectLater(
        publisher.publish('test-draft', userId: 7, token: 'x'),
        throwsA(isA<ApiFailure>()),
      );
      expect((await store.draft('test-draft'))!['state'], 'local');
      expect(
        (await store.draft('test-draft'))!['content'],
        '<p>Una historia local</p>',
      );
    },
  );

  test(
    'recovery validates ownership and slug before associating server ID',
    () async {
      await store.saveDraft({...draft(), 'state': 'uncertain'});
      final wrong = Api(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'id': 42,
                'url': 'mobile-test-draft',
                'title': 'Mi ciudad',
                'author': {'id': 8},
              },
            }),
            200,
          ),
        ),
      );
      await expectLater(
        Publisher(
          wrong,
          store,
        ).recover('test-draft', 42, userId: 7, token: 'x'),
        throwsA(isA<ApiFailure>()),
      );
      expect((await store.draft('test-draft'))!['remote_id'], isNull);
      final right = Api(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'id': 42,
                'url': 'mobile-test-draft',
                'title': 'Mi ciudad',
                'author': {'id': 7},
                'published': false,
              },
            }),
            200,
          ),
        ),
      );
      await Publisher(
        right,
        store,
      ).recover('test-draft', 42, userId: 7, token: 'x');
      expect((await store.draft('test-draft'))!['state'], 'remote');
      expect((await store.draft('test-draft'))!['remote_id'], 42);
    },
  );
}
