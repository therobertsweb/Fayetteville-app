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
import 'package:people_voice/ui/brand.dart';
import 'package:people_voice/ui/home.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settleIO(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('iPhone layout keeps web branding and community refresh works', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/posts/featured') {
          return http.Response(jsonEncode({'data': [
            {'id': 42, 'title': 'Promoted community story'},
            {'id': 43, 'title': 'Another promoted story'},
            {'id': 44, 'title': 'Local featured news'},
          ]}), 200);
        }
        if (request.url.path == '/api/v1/posts') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 366,
                  'title': 'Half-Price Homeschool Days at the Museum',
                  'created': '2026-09-27T07:38:18',
                },
                {
                  'id': 347,
                  'title': 'En Fuego Latin Dance Night!',
                  'created': '2026-09-27T05:36:56',
                },
                {
                  'id': 348,
                  'title': 'Community event at the Fayetteville library',
                  'created': '2026-09-26T16:00:00',
                },
                {
                  'id': 349,
                  'title': 'Small businesses bring neighbors together',
                  'created': '2026-09-25T16:00:00',
                },
                {
                  'id': 350,
                  'title': 'A new chapter for local artists',
                  'created': '2026-09-24T16:00:00',
                },
                {
                  'id': 351,
                  'title': 'Neighbors prepare for the weekend market',
                  'created': '2026-09-23T16:00:00',
                },
                {
                  'id': 352,
                  'title': 'Inside the Fayetteville arts scene',
                  'created': '2026-09-22T16:00:00',
                },
                {
                  'id': 353,
                  'title': 'Students share their ideas for the city',
                  'created': '2026-09-21T16:00:00',
                },
              ],
              'page': 1,
              'pages': 1,
              'total': 8,
            }),
            200,
          );
        }
        return http.Response('{"data":[]}', 200);
      }),
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: PeopleVoiceApp(
          repository: Repository(api, store),
          session: Session(api),
        ),
      ),
    );
    await settleIO(tester);
    expect(find.byType(BrandMasthead), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(BrandMasthead))).colorScheme.primary,
      Brand.red,
    );
    expect(
      find.text('Half-Price Homeschool Days at the Museum'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('top-story-card')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('FEATURED POSTS'),
      240,
      scrollable: find.descendant(
        of: find.byType(FeedPage),
        matching: find.byType(Scrollable),
      ).first,
    );
    await settleIO(tester);
    expect(find.text('FEATURED POSTS'), findsOneWidget);
    expect(find.text('Promote my article · five dollars/week'), findsOneWidget);
    expect(find.text('Shop products'), findsOneWidget);
    final feed = tester.state<ScrollableState>(find.descendant(
      of: find.byType(FeedPage),
      matching: find.byType(Scrollable),
    ).first);
    feed.position.jumpTo(0);
    await settleIO(tester);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/iphone-news.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    for (final size in [
      const Size(320, 700),
      const Size(834, 1194),
      const Size(1440, 900),
      const Size(700, 600),
    ]) {
      tester.view.physicalSize = size;
      await settleIO(tester);
      expect(
        find.byType(size.width >= 720 ? EditorialSidebar : NavigationBar),
        findsOneWidget,
      );
      expect(
        find.text('Half-Price Homeschool Days at the Museum'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'Layout at $size');
    }
    tester.view.physicalSize = const Size(1440, 900);
    await settleIO(tester);
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/previews/macos-news.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    final desktopFeed = tester.state<ScrollableState>(find.descendant(
      of: find.byType(FeedPage),
      matching: find.byType(Scrollable),
    ).first);
    desktopFeed.position.jumpTo(620);
    await settleIO(tester);
    expect(find.byType(PromotionalFeatured), findsOneWidget);
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/previews/macos-promotions.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    final firstCard = tester.getRect(find.byKey(const ValueKey('feature-347')));
    final secondCard = tester.getRect(find.byKey(const ValueKey('feature-348')));
    expect(firstCard.top, secondCard.top);
    expect(firstCard.left, lessThan(secondCard.left));
    desktopFeed.position.jumpTo(1700);
    await settleIO(tester);
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/previews/macos-news-cards.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Account'));
    await settleIO(tester);
    await tester.enterText(find.byType(TextField).first, 'resize@example.com');
    tester.view.physicalSize = const Size(390, 844);
    await settleIO(tester);
    expect(find.text('resize@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Community'));
    await settleIO(tester);
    await tester.tap(find.text('Businesses'));
    await settleIO(tester);
    await tester.tap(find.text('Refresh'));
    await settleIO(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => store.db.close());
  });
}
