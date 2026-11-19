import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/experience.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Json _session(int id) => {
  'user': {'id': id, 'username': 'reader-$id'},
  'access_token': 'token-$id',
  'expires_in': 3600,
  'expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
};

class _Storage extends FlutterSecureStorage {
  String? saved;
  Completer<String?>? readResponse;
  Completer<void>? writeResponse;
  final writeStarted = Completer<void>();
  final readStarted = Completer<void>();
  bool failDelete = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!readStarted.isCompleted) readStarted.complete();
    return readResponse == null ? saved : await readResponse!.future;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeResponse?.future;
    saved = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failDelete) throw StateError('Secure storage unavailable');
    saved = null;
  }
}

Future<void> _until(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not complete');
    await Future<void>.delayed(const Duration(milliseconds: 1));
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
  tearDown(() async => store.db.close());

  test(
    'remembered credentials renew an expired session and logout removes them',
    () async {
      final storage = _Storage();
      var logins = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            logins++;
            return http.Response(jsonEncode(_session(7)), 200);
          }
          return http.Response('{}', 200);
        }),
      );
      final first = Session(api, storage: storage);
      await first.login('reader@example.org', 'secret', remember: true);
      expect(
        jsonDecode(storage.saved!)['_remember']['email'],
        'reader@example.org',
      );
      final saved = jsonDecode(storage.saved!) as Json;
      saved['expires_at'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      storage.saved = jsonEncode(saved);
      first.dispose();

      final restored = Session(api, storage: storage);
      await restored.restore();
      expect(restored.expired, isTrue);
      expect(restored.remembersLogin, isTrue);
      expect(await restored.renewIfNeeded(), isTrue);
      expect(logins, 2);
      expect(restored.username, 'reader-7');
      await restored.logout();
      expect(storage.saved, isNull);
      expect(restored.remembersLogin, isFalse);
      restored.dispose();
      api.client.close();
    },
  );

  test('login without keep signed in never stores the password', () async {
    final storage = _Storage();
    final api = Api(
      client: MockClient(
        (_) async => http.Response(jsonEncode(_session(7)), 200),
      ),
    );
    final session = Session(api, storage: storage);
    await session.login('reader@example.org', 'secret');
    expect(storage.saved, isNot(contains('secret')));
    expect(session.remembersLogin, isFalse);
    session.dispose();
    api.client.close();
  });

  test('invalid remembered credentials stop automatic retries', () async {
    final storage = _Storage();
    var logins = 0;
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          logins++;
          return logins == 1
              ? http.Response(jsonEncode(_session(7)), 200)
              : http.Response('{}', 401);
        }
        return http.Response('{}', 200);
      }),
    );
    final session = Session(api, storage: storage);
    await session.login('reader@example.org', 'old-password', remember: true);
    session.value!['expires_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 1))
        .toIso8601String();
    expect(await session.renewIfNeeded(), isFalse);
    expect(session.remembersLogin, isFalse);
    expect(storage.saved, isNot(contains('old-password')));
    expect(await session.renewIfNeeded(), isFalse);
    expect(logins, 2);
    session.dispose();
    api.client.close();
  });

  test(
    'logout disables access before slow server revocation finishes',
    () async {
      final response = Completer<http.Response>();
      final storage = _Storage()..saved = jsonEncode(_session(7));
      final api = Api(client: MockClient((_) => response.future));
      final session = Session(api, storage: storage)..value = _session(7);
      final logout = session.logout();
      expect(session.userId, isNull);
      expect(() => session.token, throwsA(isA<ApiFailure>()));
      await _until(() => storage.saved == null);
      response.complete(http.Response('{}', 200));
      expect(await logout, isTrue);
    },
  );

  test('a late login response cannot restore a signed-out session', () async {
    final response = Completer<http.Response>();
    final storage = _Storage();
    final api = Api(client: MockClient((_) => response.future));
    final session = Session(api, storage: storage);
    final login = session.login('reader@example.org', 'password');
    await session.logout();
    response.complete(http.Response(jsonEncode(_session(7)), 200));
    await login;
    expect(session.userId, isNull);
    expect(storage.saved, isNull);
  });

  test('logout removes a login write already in progress', () async {
    final storage = _Storage()..writeResponse = Completer<void>();
    final api = Api(
      client: MockClient(
        (_) async => http.Response(jsonEncode(_session(7)), 200),
      ),
    );
    final session = Session(api, storage: storage);
    final login = session.login('reader@example.org', 'password');
    await storage.writeStarted.future;
    final logout = session.logout();
    storage.writeResponse!.complete();
    await Future.wait([login, logout]);
    expect(session.userId, isNull);
    expect(storage.saved, isNull);
  });

  test('a late restore cannot replace a newly authenticated account', () async {
    final storage = _Storage()..readResponse = Completer<String?>();
    final api = Api(
      client: MockClient(
        (_) async => http.Response(jsonEncode(_session(8)), 200),
      ),
    );
    final session = Session(api, storage: storage);
    final restoring = session.restore();
    await storage.readStarted.future;
    await session.login('other@example.org', 'password');
    storage.readResponse!.complete(jsonEncode(_session(7)));
    await restoring;
    expect(session.userId, 8);
    expect(jsonDecode(storage.saved!)['user']['id'], 8);
  });

  test('secure storage deletion failure still ends access in memory', () async {
    final storage = _Storage()..failDelete = true;
    final api = Api(
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    final session = Session(api, storage: storage)..value = _session(7);
    await expectLater(session.logout(), throwsA(isA<ApiFailure>()));
    expect(session.userId, isNull);
    expect(session.expired, isTrue);
  });

  test('invalid login payloads never become persistent sessions', () async {
    final storage = _Storage();
    final api = Api(
      client: MockClient(
        (_) async =>
            http.Response('{"expires_in":"3600","access_token":""}', 200),
      ),
    );
    final session = Session(api, storage: storage);
    await expectLater(
      session.login('reader@example.org', 'password'),
      throwsA(isA<ApiFailure>()),
    );
    expect(session.userId, isNull);
    expect(storage.saved, isNull);
  });

  test(
    'new account preferences sync after an older account request finishes',
    () async {
      final oldResponse = Completer<http.Response>();
      final requested = Completer<void>();
      final calls = <String?>[];
      await store.cache('experience:8', {'theme': 'light'});
      final api = Api(
        client: MockClient((request) async {
          calls.add(request.headers['Authorization']);
          if (request.headers['Authorization'] == 'Bearer token-7') {
            requested.complete();
            return oldResponse.future;
          }
          return http.Response('{"data":{"theme":"dark"}}', 200);
        }),
      );
      final preferences = Experience(
        store,
        api: api,
        tokenFor: (owner) => 'token-$owner',
      );
      final first = preferences.load(7);
      await requested.future;
      final second = preferences.load(8);
      await _until(() => preferences.value['theme'] == 'light');
      oldResponse.complete(http.Response('{"data":{"authors":["99"]}}', 200));
      await Future.wait([first, second]);
      expect(calls, ['Bearer token-7', 'Bearer token-8']);
      expect(preferences.value['theme'], 'dark');
      expect(preferences.strings('authors'), isEmpty);
    },
  );

  test(
    'edits during a preferences refresh are sent before sync completes',
    () async {
      final refreshing = Completer<void>();
      final oldResponse = Completer<http.Response>();
      var reads = 0;
      final server = <String, dynamic>{'theme': 'light'};
      final api = Api(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body);
            server[body['key']] = body['value'];
          } else if (++reads == 2) {
            refreshing.complete();
            return oldResponse.future;
          }
          return http.Response(jsonEncode({'data': server}), 200);
        }),
      );
      final preferences = Experience(store, api: api, tokenFor: (_) => 'token');
      await preferences.load(7);
      final sync = preferences.sync();
      await refreshing.future;
      final change = preferences.set('theme', 'dark');
      await _until(
        () async =>
            (await store.cached('experience-pending:7'))?['theme'] == 'dark',
      );
      oldResponse.complete(http.Response('{"data":{"theme":"light"}}', 200));
      await Future.wait([sync, change]);
      expect(server['theme'], 'dark');
      expect(preferences.value['theme'], 'dark');
      expect(await store.cached('experience-pending:7'), isEmpty);
      expect((await store.cached('experience:7'))!['theme'], 'dark');
    },
  );

  test(
    'updated article summaries replace completed in-memory previews',
    () async {
      final api = Api(
        client: MockClient(
          (_) async => throw StateError('No request expected'),
        ),
      );
      final repository = Repository(api, store);
      final first = {'id': 1, 'title': 'Original title', 'photo_link': null};
      final changed = {...first, 'title': 'Corrected title'};
      expect((await repository.preview(first))['title'], 'Original title');
      expect((await repository.preview(changed))['title'], 'Corrected title');
      expect((await store.summary(1))!['title'], 'Corrected title');
    },
  );

  test(
    'saving an event during startup preserves previously saved events',
    () async {
      await store.cache('experience:7', {
        'events': [
          {'id': 1, 'title': 'Previously saved'},
        ],
      });
      final preferences = Experience(store);
      final loading = preferences.load(7);
      final saving = preferences.saveEvent({'id': 2, 'title': 'New event'});
      await Future.wait([loading, saving]);
      expect(preferences.savedEvents.map((event) => event['id']), [1, 2]);
      expect((await store.cached('experience:7'))!['events'], hasLength(2));
    },
  );

  test('malformed feeds preserve the usable offline copy', () async {
    await store.cache('/posts?page=1', {
      'data': [
        {'id': 1, 'title': 'Saved article'},
      ],
      'page': 1,
      'pages': 1,
    });
    final api = Api(
      client: MockClient(
        (_) async => http.Response('{"data":[{"id":"invalid"}]}', 200),
      ),
    );
    final result = await Repository(api, store).feed('/posts?page=1');
    expect(result.warning, isNotNull);
    expect(result.body['data'].single['title'], 'Saved article');
    expect((await store.cached('/posts?page=1'))!['data'].single['id'], 1);
  });

  test(
    'failed image downloads finish, retry, and then reuse stored bytes',
    () async {
      var requests = 0;
      final api = Api(
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('', 404)
              : MockClient.pngResponse();
        }),
      );
      final repository = Repository(api, store);
      const url = 'https://example.org/cover.png';
      expect(await repository.image(url), isNull);
      final downloaded = await repository.image(url);
      expect(downloaded, isNotEmpty);
      expect(await repository.image(url), downloaded);
      expect(requests, 2);
    },
  );

  test(
    'relative article covers resolve against the site and share the cache',
    () async {
      final requests = <http.Request>[];
      final api = Api(
        client: MockClient((request) async {
          requests.add(request);
          return MockClient.pngResponse();
        }),
      );
      final repository = Repository(api, store);
      const path = '/static/media/posts/editor/cover.webp';
      final absolute = Api.site.resolve(path).toString();
      final bytes = await repository.image(path);
      expect(bytes, isNotEmpty);
      expect(requests.single.url.toString(), absolute);
      expect(requests.single.headers.containsKey('authorization'), isFalse);
      expect(await repository.image(absolute), bytes);
      expect(await store.image(absolute), bytes);
      expect(requests.length, 1);
      expect(await repository.image('javascript:alert(1)'), isNull);
      expect(requests.length, 1);
    },
  );

  test('refresh retries article previews that first loaded offline', () async {
    var online = false;
    var detailRequests = 0;
    final summary = {'id': 1, 'title': 'A local story'};
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/posts/1') {
          detailRequests++;
          if (!online) throw const SocketException('offline');
          return http.Response(
            jsonEncode({
              'data': {
                ...summary,
                'content': '<p>Full story</p>',
                'photo_link': '/static/cover.jpg',
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/posts') {
          return http.Response(
            jsonEncode({
              'data': [summary],
            }),
            200,
          );
        }
        return MockClient.pngResponse();
      }),
    );
    final repository = Repository(api, store);
    expect((await repository.preview(summary))['photo_link'], isNull);
    online = true;
    await repository.feed('/posts?page=1');
    await repository.coverDownloads;
    expect(
      (await repository.preview(summary))['photo_link'],
      '/static/cover.jpg',
    );
    expect(detailRequests, 2);
  });
}
