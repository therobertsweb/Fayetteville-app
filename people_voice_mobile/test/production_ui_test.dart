import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/main.dart';
import 'package:people_voice/ui/home.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 160)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mobile navigation, account validation and large dark layouts work',
    (tester) async {
      sqfliteFfiInit();
      late LocalStore store;
      await tester.runAsync(() async {
        for (final name in ['Montserrat', 'Roboto', 'Raleway']) {
          await (FontLoader(
            name,
          )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      var logins = 0;
      var feedLoads = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) logins++;
          if (request.url.path.endsWith('/posts')) {
            feedLoads++;
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 1,
                    'title': 'A new chapter for our community',
                    'created': '2026-10-02T12:00:00',
                    'categories': 'Local',
                    'author': {'id': 7, 'username': 'The People Voice'},
                  },
                  {
                    'id': 2,
                    'title': 'Discover what is happening in Fayetteville',
                    'categories': 'Community',
                  },
                ],
                'page': 1,
                'pages': 1,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/posts/featured')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 3,
                    'title': 'An exceptionally long promoted local community story to check accessible layouts',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/categories')) {
            return http.Response('{"data":["Local","Business"]}', 200);
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      final session = Session(api);
      final repo = Repository(api, store, session: session);
      final boundary = GlobalKey();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: PeopleVoiceApp(repository: repo, session: session),
        ),
      );
      await settle(tester);
      final initialFeedLoads = feedLoads;
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .destinations
            .length,
        5,
      );
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('My articles'), findsOneWidget);
      await tester.tap(find.text('Account'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Sign in'),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.ensureVisible(find.text('Sign in'));
      await settle(tester);
      await tester.tap(find.text('Sign in'));
      await settle(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(logins, 0);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
      await tester.tap(find.byTooltip('News'));
      await settle(tester);
      expect(
        feedLoads,
        initialFeedLoads,
        reason: 'Returning to News retains its loaded feed.',
      );
      await tester.runAsync(() => repo.experience.set('theme', 'dark'));
      await settle(tester);
      expect(
        Theme.of(tester.element(find.byType(FeedPage))).brightness,
        Brightness.dark,
      );
      for (final size in [
        const Size(320, 700),
        const Size(834, 1194),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        await settle(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Dark enlarged layout at $size',
        );
        final feed = find
            .descendant(
              of: find.byType(FeedPage),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Shop products'),
          200,
          scrollable: feed,
        );
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'Promotions at $size');
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await settle(tester);
      final feed = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(FeedPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      feed.position.jumpTo(0);
      await settle(tester);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/iphone-dark.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => store.db.close());
      api.client.close();
    },
  );
}
