import 'dart:ui' show Offset, PointerDeviceKind, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/home.dart';
import 'package:people_voice/ui/responsive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> settleFeed(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

class FixtureFeedRepository extends Repository {
  FixtureFeedRepository(
    LocalStore store, {
    this.articleCount = 12,
    this.pageSize = 0,
  }) : super(Api(), store);

  final int articleCount;
  final int pageSize;
  final requestedPages = <int>[];

  @override
  Future<FeedResult> feed(String path) async {
    if (path == '/posts/featured') return FeedResult({'data': <Json>[]});
    final page = int.parse(Uri.parse(path).queryParameters['page'] ?? '1');
    requestedPages.add(page);
    if (pageSize > 0) {
      return FeedResult({
        'data': [
          for (
            var id = (page - 1) * pageSize + 1;
            id <= page * pageSize && id <= articleCount;
            id++
          )
            {
              'id': id,
              'title': 'Article $id from Fayetteville',
              'categories': 'Local News',
              'photo_link': '',
            },
        ],
        'page': page,
        'pages': (articleCount + pageSize - 1) ~/ pageSize,
      });
    }
    if (articleCount > 12) {
      return FeedResult({
        'data': [
          for (var id = 1; id <= articleCount; id++)
            {
              'id': id,
              'title': 'Article $id from Fayetteville',
              'categories': 'Local News',
              'photo_link': '',
            },
        ],
        'page': 1,
        'pages': 1,
      });
    }
    final first = page == 1 ? 1 : 9;
    final last = page == 1 ? 8 : 12;
    return FeedResult({
      'data': [
        for (var id = first; id <= last; id++)
          {
            'id': id,
            'title': 'Article $id from Fayetteville',
            'categories': 'Local News',
            'photo_link': '',
          },
      ],
      'page': page,
      'pages': 2,
    });
  }

  @override
  Future<Json> preview(Json post) async => post;
}

void main() {
  testWidgets('editorial rows fill narrow and wide desktop windows', (
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
    final repository = FixtureFeedRepository(store);
    tester.view.physicalSize = const Size(1072, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ContentWidth(
          maxWidth: 1240,
          child: FeedPage(repository: repository),
        ),
      ),
    );
    await settleFeed(tester);
    expect(repository.requestedPages, [1, 2]);
    await tester.drag(find.byType(ListView), const Offset(0, -1300));
    await tester.pump();
    final compact4 = tester.getRect(find.byKey(const ValueKey('compact-4')));
    final compact5 = tester.getRect(find.byKey(const ValueKey('compact-5')));
    final compact6 = tester.getRect(find.byKey(const ValueKey('compact-6')));
    expect(compact5.top, compact4.top);
    expect(compact6.top, compact4.top);
    expect(compact4.left, lessThan(compact5.left));
    expect(compact5.left, lessThan(compact6.left));

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    final narrow8 = tester.getRect(find.byKey(const ValueKey('more-8')));
    final narrow9 = tester.getRect(find.byKey(const ValueKey('more-9')));
    final narrow10 = tester.getRect(find.byKey(const ValueKey('more-10')));
    final narrow11 = tester.getRect(find.byKey(const ValueKey('more-11')));
    expect(narrow9.top, narrow8.top);
    expect(narrow10.top, greaterThan(narrow8.top));
    expect(narrow11.top, narrow10.top);

    await tester.binding.setSurfaceSize(const Size(1460, 1000));
    await tester.pump();
    final wide8 = tester.getRect(find.byKey(const ValueKey('more-8')));
    final wide9 = tester.getRect(find.byKey(const ValueKey('more-9')));
    final wide10 = tester.getRect(find.byKey(const ValueKey('more-10')));
    expect(wide9.top, wide8.top);
    expect(wide10.top, wide8.top);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'Load more news fills the last narrow row before starting another',
    (tester) async {
      sqfliteFfiInit();
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
      });
      tester.view.physicalSize = const Size(1072, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FixtureFeedRepository(
        store,
        articleCount: 40,
        pageSize: 20,
      );
      await tester.pumpWidget(
        MaterialApp(home: FeedPage(repository: repository)),
      );
      await settleFeed(tester);
      expect(repository.requestedPages, [1]);
      await tester.scrollUntilVisible(
        find.text('Load more news'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Load more news'));
      await settleFeed(tester);
      expect(repository.requestedPages, [1, 2]);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('more-20')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      final lastOld = tester.getRect(find.byKey(const ValueKey('more-20')));
      final firstNew = tester.getRect(find.byKey(const ValueKey('more-21')));
      final nextRow = tester.getRect(find.byKey(const ValueKey('more-22')));
      expect(lastOld.top, firstNew.top);
      expect(lastOld.left, lessThan(firstNew.left));
      expect(nextRow.top, greaterThan(firstNew.top));
    },
  );

  testWidgets('News builds only nearby article rows while scrolling on macOS', (
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
    tester.view.physicalSize = const Size(1072, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FixtureFeedRepository(store, articleCount: 60);
    await tester.pumpWidget(
      MaterialApp(
        home: ContentWidth(
          maxWidth: 1240,
          child: FeedPage(repository: repository),
        ),
      ),
    );
    await settleFeed(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-8')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('more-8')), findsOneWidget);
    expect(find.byType(EditorialStoryCard).evaluate().length, lessThan(20));
  });

  testWidgets(
    'News reverses trackpad scrolling immediately at its end on macOS',
    (tester) async {
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
      tester.view.physicalSize = const Size(1072, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FixtureFeedRepository(store);
      await tester.pumpWidget(
        MaterialApp(home: FeedPage(repository: repository)),
      );
      await settleFeed(tester);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent - 50);
      await tester.pumpAndSettle();
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(const Offset(500, 700));
      var pan = Offset.zero;
      for (var i = 0; i < 10; i++) {
        pan += const Offset(0, -30);
        await trackpad.panZoomUpdate(const Offset(500, 700), pan: pan);
        await tester.pump(const Duration(milliseconds: 16));
      }
      final atEnd = scroll.pixels;
      pan += const Offset(0, 30);
      await trackpad.panZoomUpdate(const Offset(500, 700), pan: pan);
      await tester.pump(const Duration(milliseconds: 16));
      await trackpad.panZoomEnd();
      expect(atEnd, lessThanOrEqualTo(scroll.maxScrollExtent));
      expect(scroll.pixels, lessThan(atEnd));
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
