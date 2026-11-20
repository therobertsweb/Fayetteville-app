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
import 'package:people_voice/ui/home.dart';
import 'package:people_voice/ui/iphone_news.dart';
import 'package:people_voice/ui/search.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scenario in [
    'active',
    'empty',
    'news unavailable',
    'promotions unavailable',
  ]) {
    testWidgets('Weekly promotions: $scenario', (tester) async {
      sqfliteFfiInit();
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      var advertiseTaps = 0;
      var moreTaps = 0, notificationTaps = 0;
      addTearDown(() => store.db.close());
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/posts/featured')) {
            if (scenario == 'promotions unavailable') {
              return http.Response('{}', 400);
            }
            return http.Response(
              jsonEncode({
                'data': scenario == 'empty'
                    ? []
                    : [
                        {
                          'id': 90,
                          'title': 'A promoted community story',
                          'photo_link': null,
                        },
                      ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/posts')) {
            if (scenario == 'news unavailable') return http.Response('{}', 400);
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 1, 'title': 'Lead story', 'photo_link': null},
                  {'id': 2, 'title': 'Secondary story', 'photo_link': null},
                ],
                'pages': 1,
              }),
              200,
            );
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      final repository = Repository(api, store);
      await tester.pumpWidget(
        MaterialApp(
          theme: iphoneTheme(Brightness.dark),
          home: Scaffold(
            body: IphoneFeed(
              repository: repository,
              onAdvertise: () => advertiseTaps++,
              onAccount: () {},
              onMore: () => moreTaps++,
              onNotifications: () => notificationTaps++,
            ),
          ),
        ),
      );
      await settle(tester);
      final headerPosition = tester.getTopLeft(find.text('FAYETTEVILLE'));
      await tester.scrollUntilVisible(
        find.text('Promoted this week'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Promoted this week'), findsOneWidget);
      if (scenario == 'empty') {
        expect(
          find.text(
            'No promoted stories this week. Put your published article in the spotlight.',
          ),
          findsOneWidget,
        );
      } else if (scenario == 'promotions unavailable') {
        expect(
          find.text(
            'Promoted stories could not be refreshed. Pull down to try again.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'No promoted stories this week. Put your published article in the spotlight.',
          ),
          findsNothing,
        );
      } else {
        expect(find.text('A promoted community story'), findsOneWidget);
        expect(find.text('THE PEOPLE VOICE · SPONSORED'), findsOneWidget);
      }
      await tester.ensureVisible(find.text('Promote your article'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote your article'));
      expect(advertiseTaps, 1);
      expect(tester.getTopLeft(find.text('FAYETTEVILLE')), headerPosition);
      await tester.tap(find.byTooltip('More options'));
      await tester.tap(find.byTooltip('Notifications'));
      expect(moreTaps, 1);
      expect(notificationTaps, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => store.db.close());
    });
  }

  testWidgets(
    'iOS news, navigation, advertising sign-in and accessible layouts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      sqfliteFfiInit();
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      final api = Api(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/categories')) {
            return http.Response(
              '{"data":["Local","Sports","Politics","Business"]}',
              200,
            );
          }
          if (path.endsWith('/posts')) {
            return http.Response(
              jsonEncode({
                'data': [
                  for (var i = 1; i <= 6; i++)
                    {
                      'id': i,
                      'title': [
                        'Fayetteville comes together for a new chapter downtown',
                        'Local voices shape the future of our community',
                        'A weekend of music, food and neighborhood stories',
                        'Small businesses bring fresh ideas to Main Street',
                        'Explore the latest news from across Fayetteville',
                        'Meet the people making a difference',
                      ][i - 1],
                      'photo_link': null,
                      'created': '2026-10-13T12:00:00',
                    },
                ],
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
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: PeopleVoiceApp(repository: repository, session: session),
        ),
      );
      await settle(tester);
      expect(find.byType(IphoneNavigation), findsOneWidget);
      expect(find.text('Top Stories'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(IphoneFeed)))
            .scaffoldBackgroundColor,
        Colors.black,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Advertise'));
      await settle(tester);
      expect(find.text('Put your story in the spotlight.'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign in to advertise'));
      await tester.tap(find.text('Sign in to advertise'));
      await settle(tester);
      expect(find.byType(AccountPage), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.byTooltip('Search'));
      await settle(tester);
      expect(find.byType(SearchPage), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text('Saved'));
      await settle(tester);
      expect(find.byType(LibraryPage), findsOneWidget);
      await tester.tap(find.text('Today'));
      await settle(tester);
      for (final size in [
        const Size(320, 700),
        const Size(430, 932),
        const Size(844, 390),
      ]) {
        tester.view.physicalSize = size;
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'iPhone size $size');
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'Large text');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => store.db.close());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
