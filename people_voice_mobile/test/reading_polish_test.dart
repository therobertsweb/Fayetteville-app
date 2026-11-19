import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/brand.dart';
import 'package:people_voice/ui/article_body.dart';
import 'package:people_voice/ui/for_you.dart';
import 'package:people_voice/ui/home.dart' show PromotionalFeatured;
import 'package:people_voice/ui/preferences.dart';
import 'package:people_voice/ui/reader.dart';
import 'package:people_voice/ui/search.dart';

class _MemoryStore extends Fake implements LocalStore {
  final values = <String, Json>{};
  final downloaded = <Json>[];
  final favorites = <int>{};

  @override
  Future<Json?> cached(String key) async => values[key];
  @override
  Future<void> cache(String key, Json body) async => values[key] = body;
  @override
  Future<List<Json>> searchableArticles() async => downloaded;
  @override
  Future<bool> favorite(int owner, int id) async => favorites.contains(id);
  @override
  Future<void> setFavorite(
    int owner,
    int id,
    bool saved,
    String revision,
  ) async {
    saved ? favorites.add(id) : favorites.remove(id);
  }
}

class _ReadingRepository extends Repository {
  _ReadingRepository(super.api, super.store);
  Future<FeedResult> Function(String, int)? searchResult;
  Json? detail;
  List<Json> promoted = [];
  List<Json> related = [];
  Uint8List? imageBytes;
  int imageRequests = 0;

  @override
  Future<FeedResult> search(String query, {int page = 1}) async =>
      searchResult?.call(query, page) ??
      FeedResult({'data': <Json>[], 'page': 1, 'pages': 1});
  @override
  Future<Json> preview(Json post) async => post;
  @override
  Future<FeedResult> categoryArticles(String category, {int page = 1}) async =>
      FeedResult({'data': related});
  @override
  Future<FeedResult> feed(String path) async =>
      FeedResult({'data': path == '/posts/featured' ? promoted : <Json>[]});
  @override
  Future<Json> article(int id, {bool refresh = false}) async => detail!;
  @override
  Future<Uint8List?> image(String url) async {
    imageRequests++;
    return imageBytes;
  }
}

Json _story(int id, String title) => {
  'id': id,
  'title': title,
  'categories': 'Business',
  'created': '2026-10-01T12:00:00',
  'author': {'id': 7, 'username': 'Local Writer'},
  'content': '<p>A local story worth reading.</p>',
};

void main() {
  late _MemoryStore store;
  late _ReadingRepository repository;
  setUp(() async {
    store = _MemoryStore();
    repository = _ReadingRepository(
      Api(client: MockClient((_) async => http.Response('{}', 200))),
      store,
    );
    await repository.experience.load(0);
  });
  tearDown(() => repository.api.client.close());

  Widget app(Widget child, {bool dark = false, double scale = 1}) =>
      MaterialApp(
        theme: Brand.theme(
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      );

  testWidgets(
    'reader repeats promoted stories after the article on all platforms',
    (tester) async {
      repository.detail = _story(1, 'Main story');
      repository.promoted = [
        _story(1, 'Main story'),
        _story(2, 'Approved promoted story'),
      ];
      await tester.pumpWidget(
        app(ReaderPage(repository: repository, id: 1, title: 'Main story')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Approved promoted story'), findsOneWidget);
      expect(find.text('Main story'), findsOneWidget);
      final article = tester.getBottomLeft(find.byType(ArticleBody));
      final promoted = tester.getTopLeft(find.text('Approved promoted story'));
      expect(promoted.dy, greaterThan(article.dy));
    },
  );

  testWidgets('desktop shows every paid placement when more than three exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final posts = List.generate(4, (i) => _story(i + 1, 'Paid story ${i + 1}'));
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: PromotionalFeatured(
              repository: repository,
              data: Future.value(FeedResult({'data': posts})),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i <= 3; i++) {
      expect(find.text('Paid story $i'), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Paid story 4'), findsOneWidget);
    expect(find.text('2 / 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause promotions'));
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous promotions'));
    await tester.pumpAndSettle();
    expect(find.text('Paid story 1'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('Paid story 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reader shows promotion images then relevant nonduplicate stories',
    (tester) async {
      repository.detail = _story(1, 'Main story');
      repository.imageBytes = MockClient.pngResponse().bodyBytes;
      repository.promoted = [
        {..._story(2, 'Paid story'), 'photo_link': '/static/paid.png'},
      ];
      repository.related = [
        _story(1, 'Main story'),
        _story(2, 'Paid story'),
        {
          ..._story(3, 'Related business story'),
          'photo_link': '/static/related.png',
        },
        _story(3, 'Related business story'),
        {..._story(4, 'Unrelated story'), 'categories': 'Sports'},
      ];
      await tester.pumpWidget(
        app(ReaderPage(repository: repository, id: 1, title: 'Main story')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paid story'), findsOneWidget);
      expect(find.text('Related business story'), findsOneWidget);
      expect(find.text('Unrelated story'), findsNothing);
      expect(find.byType(Image), findsNWidgets(2));
      expect(repository.imageRequests, greaterThanOrEqualTo(2));
      expect(
        tester.getTopLeft(find.text('Related articles')).dy,
        greaterThan(tester.getBottomLeft(find.text('Paid story')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('macOS can scroll up from the end over either window margin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.detail = {
      ..._story(1, 'Long article'),
      'content': List.generate(
        80,
        (i) => '<p>Paragraph $i of the story.</p>',
      ).join(),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: Brand.theme().copyWith(platform: TargetPlatform.macOS),
        home: ReaderPage(repository: repository, id: 1, title: 'Long article'),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (final x in [40.0, 720.0, 1400.0]) {
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      final bottom = scroll.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: Offset(x, 700),
          scrollDelta: const Offset(0, -300),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.pixels, lessThan(bottom), reason: 'Scroll up at x=$x');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS trackpad reverses at the article end without overshoot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.detail = {
      ..._story(1, 'Long article'),
      'content': List.generate(
        80,
        (i) => '<p>Paragraph $i of the story.</p>',
      ).join(),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: Brand.theme().copyWith(platform: TargetPlatform.macOS),
        home: ReaderPage(repository: repository, id: 1, title: 'Long article'),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scroll.jumpTo(scroll.maxScrollExtent - 50);
    await tester.pumpAndSettle();
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomStart(const Offset(720, 700));
    var pan = Offset.zero;
    for (var i = 0; i < 10; i++) {
      pan += const Offset(0, -30);
      await trackpad.panZoomUpdate(const Offset(720, 700), pan: pan);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final atEnd = scroll.pixels;
    // Reverse without lifting the fingers or waiting for a spring to settle.
    pan += const Offset(0, 30);
    await trackpad.panZoomUpdate(const Offset(720, 700), pan: pan);
    await tester.pump(const Duration(milliseconds: 16));
    final afterReversal = scroll.pixels;
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(
      atEnd,
      lessThanOrEqualTo(scroll.maxScrollExtent),
      reason: 'The article must not travel past its end and spring back.',
    );
    expect(
      afterReversal,
      lessThan(scroll.maxScrollExtent),
      reason: 'Reversing the trackpad must immediately reveal earlier content.',
    );
    expect(afterReversal, lessThan(atEnd));
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning up a long article keeps its cover mounted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.detail = {
      ..._story(1, 'Long article'),
      'photo_link': 'https://example.com/cover.png',
      'content': List.generate(
        80,
        (i) =>
            '<p>Paragraph $i. A community story with enough text to scroll through.</p>',
      ).join(),
    };
    await tester.pumpWidget(
      app(ReaderPage(repository: repository, id: 1, title: 'Long article')),
    );
    await tester.pumpAndSettle();
    expect(repository.imageRequests, 1);
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (var i = 0; i < 2; i++) {
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      final previous = scroll.pixels;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(scroll.pixels, lessThan(previous));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
    }
    expect(
      repository.imageRequests,
      1,
      reason: 'Returning to the cover must not restart its loading and change the article height.',
    );
    expect(scroll.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clearing search removes pagination and ignores an old response',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<FeedResult>();
      repository.searchResult = (query, page) async => query == 'delayed'
          ? pending.future
          : FeedResult({
              'data': [_story(1, 'A saved story')],
              'page': 1,
              'pages': 3,
            });
      await tester.pumpWidget(
        app(SearchPage(repository: repository), scale: 1.8),
      );
      await tester.pumpAndSettle();
      expect(find.text('Load more results'), findsNothing);
      await tester.enterText(find.byType(TextField), 'business');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('A saved story'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('A saved story'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Load more results'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Load more results'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byTooltip('Clear search'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Load more results'), findsNothing);
      await tester.enterText(find.byType(TextField), 'delayed');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      pending.complete(
        FeedResult({
          'data': [_story(2, 'Stale story')],
          'page': 1,
          'pages': 5,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stale story'), findsNothing);
      expect(find.text('Load more results'), findsNothing);
      expect(find.text('A whole community to discover'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a cached search page keeps previous results and removes duplicates',
    (tester) async {
      repository.searchResult = (_, page) async => FeedResult({
        'data': [
          _story(1, 'First story'),
          if (page > 1) _story(2, 'Second story'),
        ],
        'page': page,
        'pages': 2,
      }, warning: page > 1 ? 'Showing saved results.' : null);
      await tester.pumpWidget(
        app(SearchPage(repository: repository), scale: 1.8),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'business');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Load more results'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more results'));
      await tester.pumpAndSettle();
      expect(find.text('First story'), findsOneWidget);
      expect(find.text('Second story'), findsOneWidget);
      expect(find.text('Load more results'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('For you reacts to following changes without a manual refresh', (
    tester,
  ) async {
    store.downloaded.add(_story(9, 'A story for your interests'));
    await tester.pumpWidget(
      app(Scaffold(body: ForYouPage(repository: repository))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Make the news your own'), findsOneWidget);
    await tester.runAsync(() async {
      await repository.experience.toggle('categories', 'business');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('A story for your interests'), findsOneWidget);
    await tester.runAsync(() async {
      await repository.experience.toggle('categories', 'business');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('A story for your interests'), findsNothing);
    expect(find.text('Make the news your own'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preferences remain usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(PreferencesPage(repository: repository), dark: true, scale: 1.8),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dark'));
    await tester.pumpAndSettle();
    expect(repository.experience.theme, ThemeMode.dark);
    await tester.ensureVisible(find.byType(Slider));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(26);
    await tester.pump();
    expect(repository.experience.fontSize, 18);
    slider.onChangeEnd!(26);
    await tester.pumpAndSettle();
    expect(repository.experience.fontSize, 26);
    await tester.scrollUntilVisible(
      find.text('Your community controls'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reader supports offline favorites and unavailable image in dark mode',
    (tester) async {
      repository.detail = {
        ..._story(3, 'Community stories bring us together'),
        'photo_link': '/missing.jpg',
      };
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          ReaderPage(repository: repository, id: 3, title: 'Loading'),
          dark: true,
          scale: 1.8,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Copy article link',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Save favorite'));
      await tester.pumpAndSettle();
      expect(store.favorites, contains(3));
      expect(find.byTooltip('Remove favorite'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Image unavailable'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Image unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Reading options'));
      await tester.pumpAndSettle();
      expect(find.text('Text size & appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
