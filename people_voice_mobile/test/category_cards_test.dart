import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/home.dart';
import 'package:people_voice/ui/responsive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settleCategory(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'article categories remove duplicates across legacy and current fields',
    () {
      final categories = Repository.articleCategories({
        'categories':
            ' Community, COMMUNITY, Local   News, local news, Business ',
        'info': 'community',
      });
      expect(categories, ['Community', 'Local News', 'Business']);
      expect(categories, ['Community', 'Local News', 'Business']);
    },
  );

  testWidgets('category stories use compact responsive cards and keep paging', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    sqfliteFfiInit();
    late LocalStore store;
    await tester.runAsync(() async {
      store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });
    final requests = <int>[];
    final api = Api(
      client: MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        requests.add(page);
        return http.Response(
          jsonEncode({
            'data': [
              for (var i = 1; i <= 6; i++)
                {
                  'id': page * 100 + i,
                  'title': 'Community story $i on page $page',
                  'categories': 'Community',
                  'photo_link': '',
                  'created': '2026-10-20T08:00:00',
                },
            ],
            'page': page,
            'pages': 2,
          }),
          200,
        );
      }),
    );
    final repository = Repository(api, store);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryArticlesPage(
          repository: repository,
          category: 'Community',
        ),
      ),
    );
    await settleCategory(tester);

    final first = tester.getRect(find.byKey(const ValueKey('category-101')));
    final second = tester.getRect(find.byKey(const ValueKey('category-102')));
    final third = tester.getRect(find.byKey(const ValueKey('category-103')));
    expect(first.height, lessThan(220));
    expect(second.top, first.top);
    expect(third.top, first.top);
    expect(first.left, lessThan(second.left));
    expect(second.left, lessThan(third.left));

    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpAndSettle();
    final mobileFirst = tester.getRect(
      find.byKey(const ValueKey('category-101')),
    );
    final mobileSecond = tester.getRect(
      find.byKey(const ValueKey('category-102')),
    );
    expect(mobileFirst.left, mobileSecond.left);
    expect(mobileSecond.top, mobileFirst.bottom);
    expect(mobileFirst.width, greaterThan(340));
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Next'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await settleCategory(tester);
    expect(requests, contains(2));
    expect(find.byKey(const ValueKey('category-201')), findsOneWidget);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryArticlesPage(
          repository: repository,
          category: 'Community',
        ),
      ),
    );
    await settleCategory(tester);
    expect(find.byType(ArticleTile), findsWidgets);
    expect(find.byType(EditorialStoryCard), findsNothing);
    expect(
      tester.widget<ContentWidth>(find.byType(ContentWidth)).maxWidth,
      840,
    );
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    debugDefaultTargetPlatformOverride = null;
  });
}
