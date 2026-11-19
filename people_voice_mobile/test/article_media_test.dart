import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/article_media.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/publisher.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/article_editor.dart';
import 'package:people_voice/ui/article_body.dart';
import 'package:people_voice/ui/reader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_test.dart' show draft;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets('typing keeps keyboard focus across editor rebuilds', (tester) async {
    late LocalStore store;
    await tester.runAsync(() async {
      store = await LocalStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    });
    final content = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [quill.FlutterQuillLocalizations.delegate],
      home: Scaffold(body: ListView(children: [ArticleEditor(
        controller: content,
        repository: Repository(Api(), store),
      )])),
    ));
    final editorFinder = find.byType(quill.QuillEditor);
    await tester.tapAt(tester.getTopLeft(editorFinder) + const Offset(15, 15));
    await tester.pump();
    expect(tester.widget<quill.QuillEditor>(editorFinder).focusNode.hasFocus, isTrue);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'Hello\n', selection: TextSelection.collapsed(offset: 5),
    ));
    await tester.pump();
    expect(tester.widget<quill.QuillEditor>(editorFinder).focusNode.hasFocus, isTrue);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'Hello world\n', selection: TextSelection.collapsed(offset: 11),
    ));
    await tester.pump();
    expect(content.text, contains('Hello world'));
    await tester.pumpWidget(const SizedBox.shrink());
    content.dispose();
    await tester.runAsync(() => store.db.close());
  });

  test('empty and legacy drafts open as editable blank documents', () {
    for (final content in ['', '<p></p>', '<p><br></p>']) {
      expect(articleDocument(content: content).toPlainText().trim(), isEmpty);
    }
    expect(
      articleDocument(delta: [], plainText: 'Legacy draft').toPlainText(),
      contains('Legacy draft'),
    );
  });

  test('formatting and mixed media survive HTML and Delta round trips', () {
    final document = articleDocument(
      content: '<h2>Community</h2><p><strong>Bold</strong> <em>italic</em> <u>underline</u> <a href="https://example.com">source</a></p><ul><li>One</li><li>Two</li></ul><blockquote>Quote</blockquote><p><img src="/local-images/photo.png"></p><iframe src="https://www.tiktok.com/player/v1/12345"></iframe><video controls src="https://example.com/video.mp4"></video>',
    );
    final restored = articleDocument(
      delta: jsonDecode(jsonEncode(document.toDelta().toJson())) as List,
    );
    final output = articleHtml(restored);
    final parsed = html.parseFragment(output);
    expect(parsed.querySelector('h2')?.text, 'Community');
    expect(parsed.querySelector('strong')?.text, 'Bold');
    expect(parsed.querySelector('em')?.text, 'italic');
    expect(parsed.querySelector('u')?.text, 'underline');
    expect(parsed.querySelectorAll('li'), hasLength(2));
    expect(
      parsed.querySelector('a')?.attributes['href'],
      'https://example.com',
    );
    expect(
      parsed.querySelector('img')?.attributes['src'],
      '/local-images/photo.png',
    );
    expect(
      parsed.querySelector('iframe')?.attributes['src'],
      'https://www.tiktok.com/player/v1/12345',
    );
    expect(
      parsed.querySelector('video')?.attributes['src'],
      'https://example.com/video.mp4',
    );
    expect(
      articleHtml(articleDocument(content: output)),
      contains('https://example.com/video.mp4'),
    );
  });

  test('provider URLs normalize and unsafe schemes are rejected', () {
    expect(
      videoSource('https://youtu.be/abc-123'),
      'https://www.youtube-nocookie.com/embed/abc-123',
    );
    expect(
      videoSource('https://youtube.com/shorts/abc_123'),
      'https://www.youtube-nocookie.com/embed/abc_123',
    );
    expect(
      videoSource('https://vimeo.com/123/secret'),
      'https://player.vimeo.com/video/123?h=secret',
    );
    expect(
      videoSource('https://www.tiktok.com/@author/video/12345'),
      'https://www.tiktok.com/player/v1/12345',
    );
    expect(
      videoSource('https://www.facebook.com/author/videos/12345'),
      startsWith('https://www.facebook.com/plugins/video.php?href='),
    );
    expect(
      videoSource('https://example.com/stream?token=abc'),
      'https://example.com/stream?token=abc',
    );
    for (final value in [
      'javascript:alert(1)',
      'file:///tmp/a.mp4',
      'http://example.com/a.mp4',
      'https://user:pass@example.com/a',
      'https://tiktok.com/@author',
      'https://vm.tiktok.com/short',
    ]) {
      expect(videoSource(value), isNull, reason: value);
    }
  });

  testWidgets('article image loading keeps the scroll extent stable', (tester) async {
    tester.view.physicalSize = const Size(700, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late LocalStore store;
    await tester.runAsync(() async {
      store = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });
    final imageResponse = Completer<http.Response>();
    final repository = Repository(
      Api(client: MockClient((_) => imageResponse.future)),
      store,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(children: [
            const SizedBox(height: 900),
            ArticleBody(
              content: '<img src="https://fayettevillethepeoplevoice.com/static/test.png">',
              repository: repository,
            ),
            const SizedBox(height: 900),
          ]),
        ),
      ),
    ));
    await tester.pump();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final extentBefore = scroll.position.maxScrollExtent;
    final offsetBefore = scroll.offset;

    imageResponse.complete(http.Response.bytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
      200,
      headers: {'content-type': 'image/png'},
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(scroll.position.maxScrollExtent, closeTo(extentBefore, 0.1));
    expect(scroll.offset, closeTo(offsetBefore, 0.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    await tester.runAsync(store.db.close);
  });

  test('uploads deduplicate cover and body, persist retries and never send local image paths', () async {
    final store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(store.db.close);
    const local = '/local-images/photo.png';
    const second = '/local-images/second.png';
    await store.saveImage(local, Uint8List.fromList([1, 2, 3]));
    await store.saveImage(second, Uint8List.fromList([4, 5, 6]));
    await store.saveDraft({
      ...draft(),
      'photo_link': local,
      'content': '<p>Article</p><img src="$local"><img src="$second">',
    });
    var uploadCount = 0, createCount = 0, failSecond = true;
    final api = Api(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/media/images')) {
          uploadCount++;
          expect(request.headers['Authorization'], 'Bearer token');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data'),
          );
          if (failSecond && uploadCount == 2) return http.Response('{}', 503);
          return http.Response(
            jsonEncode({
              'data': {'url': '/static/media/posts/editor/$uploadCount.webp'},
            }),
            201,
          );
        }
        createCount++;
        final body = jsonDecode(request.body) as Json;
        expect(body['photo_link'], '/static/media/posts/editor/1.webp');
        expect(body['content'], isNot(contains(localImagePrefix)));
        expect(body['content'], contains('/static/media/posts/editor/3.webp'));
        return http.Response('{"data":{"id":42}}', 201);
      }),
    );
    await expectLater(
      Publisher(
        api,
        store,
      ).publish('test-draft', userId: 7, token: 'token', publishNow: false),
      throwsA(isA<ApiFailure>()),
    );
    expect(createCount, 0);
    expect((await store.draft('test-draft'))!['state'], 'local');
    failSecond = false;
    await Publisher(
      api,
      store,
    ).publish('test-draft', userId: 7, token: 'token', publishNow: false);
    expect(uploadCount, 3);
    expect(createCount, 1);
    expect((await store.draft('test-draft'))!['content'], contains(local));
  });

  testWidgets(
    'editor toolbar formats selection and preview fits a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late LocalStore store;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await store.saveImage(
          '/local-images/test.png',
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
      });
      final controller = TextEditingController(
        text: '<p>Local story</p><img src="/local-images/test.png"><iframe src="https://www.youtube-nocookie.com/embed/abc123"></iframe>',
      );
      final repo = Repository(
        Api(client: MockClient((_) async => http.Response('', 503))),
        store,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            quill.FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArticleEditor(controller: controller, repository: repo),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(OfflineImage), findsOneWidget);
      expect(find.byType(ArticleVideo), findsOneWidget);
      final editor = tester
          .widget<quill.QuillEditor>(find.byType(quill.QuillEditor))
          .controller;
      editor.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        quill.ChangeSource.local,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pumpAndSettle();
      expect(controller.text, contains('<strong>Local</strong>'));
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.byType(quill.QuillEditor), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(store.db.close);
    },
  );
}
