import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/main.dart';
import 'package:people_voice/ui/macos_home.dart';
import 'package:people_voice/ui/brand.dart';
import 'package:people_voice/ui/search.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _UnusedStore extends Fake implements LocalStore {}

void main() {
  testWidgets(
    'News preserves editorial section order and distinct card layouts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = Repository(Api(), _UnusedStore());
      final posts = List<Json>.generate(
        13,
        (i) => {
          'id': i + 1,
          'title': 'Community story ${i + 1}',
          'categories': 'Community',
          'subtitle': 'News and events from Fayetteville.',
          'author': {'username': 'Reporter'},
          'created': '2026-11-19T12:00:00Z',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: Brand.theme(brightness: Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MacosNewsSections(posts: posts, repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<MacosEditorialCard>(find.byType(MacosEditorialCard))
          .toList();
      expect(cards.length, 13);
      expect(
        cards.take(2).every((c) => c.style == MacosCardStyle.large),
        isTrue,
      );
      expect(
        cards.skip(2).take(3).every((c) => c.style == MacosCardStyle.compact),
        isTrue,
      );
      expect(cards[5].style, MacosCardStyle.focus);
      final headings = [
        'Latest stories',
        'More to explore',
        'In focus',
        'More news',
      ];
      for (var i = 1; i < headings.length; i++) {
        expect(
          tester.getTopLeft(find.text(headings[i])).dy,
          greaterThan(tester.getTopLeft(find.text(headings[i - 1])).dy),
        );
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('mac-story-13'))).width,
        1200,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(500, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      repository.api.client.close();
    },
  );

  testWidgets(
    'macOS navigation, search, promotions and resizing preserve news',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1180, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          requests.add(request.url.toString());
          final path = request.url.path;
          if (path.endsWith('/categories')) {
            return http.Response('{"data":[{"name":"Business"}]}', 200);
          }
          if (path.endsWith('/posts/featured')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 8, 'title': 'Promoted community event'},
                ],
              }),
              200,
            );
          }
          if (path.endsWith('/posts') || path.endsWith('/search')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'title': 'A story for Fayetteville',
                    'subtitle': 'The community comes together.',
                    'categories': 'Local News',
                    'author': {'id': 2, 'username': 'Reporter'},
                    'created': '2026-11-19T15:20:00Z',
                  },
                ],
                'page': 1,
                'pages': 1,
              }),
              200,
            );
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      final session = Session(api);
      final repository = Repository(api, store, session: session);
      await tester.pumpWidget(
        PeopleVoiceApp(repository: repository, session: session),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      expect(find.byType(MacosHeroStory), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(MacosHome))).brightness,
        Brightness.dark,
      );
      for (final label in [
        'Promote',
        'Preferences',
        'Trends',
        'Notifications',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('mac-nav-Search')));
      await settle();
      expect(find.byType(SearchPage), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Fayetteville');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle();
      expect(requests.any((url) => url.contains('Fayetteville')), isTrue);
      await tester.tap(find.byTooltip('Promote'));
      await settle();
      expect(find.text('Sign in to advertise'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mac-nav-News')));
      await settle();
      expect(find.byType(MacosHeroStory), findsOneWidget);
      expect(
        requests.where((url) => Uri.parse(url).path == '/api/v1/posts').length,
        1,
      );
      tester.view.physicalSize = const Size(500, 900);
      await settle();
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await settle();
      await tester.tap(find.byKey(const ValueKey('mac-nav-Search')));
      await settle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
