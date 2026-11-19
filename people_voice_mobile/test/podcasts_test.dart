import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/podcasts.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/podcasts.dart';
import 'package:people_voice/ui/reader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final origin = Uri.parse('https://podcasts.example.test');
  final articleCover = 'https://fayettevillethepeoplevoice.com/static/main.jpg';
  final episode = {
    'id': 9,
    'title': 'Article discussion',
    'author': 'Reporter',
    'author_id': 21,
    'audio_url': '/media/episode.mp3',
    'cover_url': articleCover,
    'created_at': '2026-10-20T10:00:00+00:00',
    'likes': 3,
    'dislikes': 1,
    'comment_count': 2,
    'article': {'id': 42, 'title': 'Article headline'},
  };

  testWidgets('related article opens without disposing the podcast page', (
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
    final podcastApi = PodcastApi(
      baseUrl: origin,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {...episode, 'author': 'Community member'},
            ],
            'next_page': null,
          }),
          200,
        ),
      ),
    );
    final articleApi = Api(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'id': 42,
              'title': 'Article headline',
              'content': '<p>Story text</p>',
              'author': {'id': 21, 'username': 'Reporter'},
            },
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PodcastsPage(
          api: podcastApi,
          repository: Repository(articleApi, store),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('By Reporter'), findsOneWidget);
    expect(find.text('By Community member'), findsNothing);
    final podcastState = tester.state(find.byType(PodcastsPage));
    expect(find.text('Delete podcast'), findsNothing);
    await tester.tap(find.text('Read the related article'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(
      identical(
        podcastState,
        tester.state(find.byType(PodcastsPage, skipOffstage: false)),
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => store.db.close());
    articleApi.client.close();
    podcastApi.client.close();
  });

  test(
    'deleting a podcast requires a bearer token and admin approval',
    () async {
      var permitted = false;
      final api = PodcastApi(
        baseUrl: origin,
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/episodes/9');
          expect(request.headers['authorization'], 'Bearer admin-token');
          return http.Response('', permitted ? 204 : 403);
        }),
      );
      await expectLater(
        api.deleteEpisode(9, 'admin-token'),
        throwsA(isA<PodcastFailure>()),
      );
      permitted = true;
      await api.deleteEpisode(9, 'admin-token');
      api.client.close();
    },
  );

  testWidgets('administrator can delete a podcast from its card', (
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
    var deleted = false;
    final podcastApi = PodcastApi(
      baseUrl: origin,
      client: MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted = true;
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/reaction')) {
          return http.Response(
            '{"data":{"likes":3,"dislikes":1,"my_reaction":null}}',
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': [episode],
            'next_page': null,
          }),
          200,
        );
      }),
    );
    final articleApi = Api(
      client: MockClient(
        (_) async => http.Response(
          '{"data":{"user_id":7,"role":"admin","permissions":[]}}',
          200,
        ),
      ),
    );
    final session = Session(articleApi)
      ..value = {
        'user': {'id': 7, 'username': 'Admin'},
        'access_token': 'admin-token',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      };
    await tester.pumpWidget(
      MaterialApp(
        home: PodcastsPage(
          api: podcastApi,
          repository: Repository(articleApi, store, session: session),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Delete podcast'));
    await tester.tap(find.text('Delete podcast'));
    await tester.pump();
    await tester.tap(find.text('Delete').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(deleted, isTrue);
    expect(find.text('Article discussion'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => store.db.close());
    articleApi.client.close();
    podcastApi.client.close();
  });

  test('public feed accepts article cover and related article', () async {
    final api = PodcastApi(
      baseUrl: origin,
      client: MockClient((request) async {
        expect(request.url.path, '/episodes');
        expect(request.url.queryParameters['page'], '1');
        expect(request.headers.containsKey('authorization'), false);
        return http.Response(
          jsonEncode({
            'data': [episode],
            'next_page': null,
          }),
          200,
        );
      }),
    );
    final page = await api.list();
    expect(page.episodes.single.articleId, 42);
    expect(page.episodes.single.authorId, 21);
    expect(page.episodes.single.coverUrl.toString(), articleCover);
    expect(page.nextPage, isNull);
  });

  test(
    'publishing an MP3 requires a token and can reuse article cover',
    () async {
      final directory = await Directory.systemTemp.createTemp('podcast-test-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/voice.mp3');
      await file.writeAsBytes([73, 68, 51, 0]);
      final audio = XFile(file.path);
      final api = PodcastApi(
        baseUrl: origin,
        client: MockClient((request) async {
          expect(request.url.path, '/episodes');
          expect(request.headers['authorization'], 'Bearer signed-in-token');
          expect(request.body, contains('name="article_id"'));
          expect(request.body, contains('42'));
          expect(request.body, contains('name="audio"'));
          expect(request.body, isNot(contains('name="cover"')));
          return http.Response(jsonEncode({'data': episode}), 201);
        }),
      );
      final created = await api.upload(
        title: 'Article discussion',
        audio: audio,
        token: 'signed-in-token',
        articleId: 42,
      );
      expect(created.articleTitle, 'Article headline');
    },
  );

  test('direct MP3 links work and YouTube is rejected', () async {
    final api = PodcastApi(
      baseUrl: origin,
      client: MockClient((request) async {
        expect(request.url.path, '/episodes/links');
        expect(request.body, contains('media.example.test'));
        return http.Response(jsonEncode({'data': episode}), 201);
      }),
    );
    final created = await api.createLink(
      title: 'Article discussion',
      audioUrl: 'https://media.example.test/audio.mp3',
      token: 'signed-in-token',
      articleId: 42,
    );
    expect(created.id, 9);
    expect(
      () => api.createLink(
        title: 'YouTube',
        audioUrl: 'https://youtube.com/watch?v=123',
        token: 'signed-in-token',
        articleId: 42,
      ),
      throwsA(isA<PodcastFailure>()),
    );
  });

  test('votes and comments use the signed-in account', () async {
    final api = PodcastApi(
      baseUrl: origin,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/reaction')) {
          expect(request.headers['authorization'], 'Bearer signed-in-token');
          if (request.method == 'PUT') {
            expect(jsonDecode(request.body), {'value': 'like'});
          }
          return http.Response(
            jsonEncode({
              'data': {'likes': 4, 'dislikes': 1, 'my_reaction': 'like'},
            }),
            200,
          );
        }
        if (request.method == 'POST') {
          expect(request.headers['authorization'], 'Bearer signed-in-token');
          expect(jsonDecode(request.body), {'body': 'Good discussion'});
          return http.Response(
            jsonEncode({
              'data': {
                'id': 5,
                'author_id': 22,
                'author': 'Listener',
                'body': 'Good discussion',
                'created_at': '2026-10-20T10:00:00+00:00',
              },
            }),
            201,
          );
        }
        expect(request.url.path, '/episodes/9/comments');
        expect(request.headers.containsKey('authorization'), false);
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 5,
                'author_id': 22,
                'author': 'Listener',
                'body': 'Good discussion',
                'created_at': '2026-10-20T10:00:00+00:00',
              },
            ],
            'next_page': null,
          }),
          200,
        );
      }),
    );
    expect((await api.reaction(9, 'signed-in-token')).mine, 'like');
    expect((await api.setReaction(9, 'signed-in-token', 'like')).likes, 4);
    expect((await api.comments(9)).comments.single.body, 'Good discussion');
    expect((await api.comments(9)).comments.single.authorId, 22);
    expect(
      (await api.addComment(9, 'signed-in-token', ' Good discussion ')).id,
      5,
    );
  });
}
