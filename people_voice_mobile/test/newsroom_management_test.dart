import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/editorial.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/notifications.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/ui/admin_management.dart';
import 'package:people_voice/ui/brand.dart';
import 'package:people_voice/ui/iphone_news.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Session sessionFor(Api api) => Session(api)
  ..value = {
    'user': {'id': 7, 'username': 'Admin'},
    'access_token': 'test-token',
    'expires_at': DateTime.now()
        .add(const Duration(hours: 1))
        .toIso8601String(),
  };

void main() {
  late LocalStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => store.db.close());

  for (final resource in ['users', 'posts', 'roles', 'contacts']) {
    testWidgets(
      'macOS $resource renders records, search and forms without errors',
      (tester) async {
        tester.view.physicalSize = const Size(1180, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final row = <String, dynamic>{
          'id': 1,
          'version': 1,
          'username': 'Reader',
          'email': 'reader@example.com',
          'role': 'commenter',
          'posts_count': 1,
          'email_verified': true,
          'title': 'Community story',
          'content': '<p>Story details.</p>',
          'author': {'username': 'Reader', 'role': 'commenter'},
          'published': false,
          'name': 'Reader',
          'subject': 'Question',
          'message': 'A message for the newsroom.',
          'count': 1,
          'can_publish': false,
        };
        final api = Api(
          client: MockClient((request) async {
            expect(request.method, 'GET');
            return http.Response(
              jsonEncode({
                'data': request.url.path.endsWith('/mobile/capabilities')
                    ? {'user_id': 7, 'role': 'admin', 'permissions': <String>[]}
                    : [row],
              }),
              200,
            );
          }),
        );
        final gateway = EditorialGateway(api, sessionFor(api));
        await tester.pumpWidget(
          MaterialApp(
            theme: Brand.theme(brightness: Brightness.dark)
                .copyWith(platform: TargetPlatform.macOS),
            localizationsDelegates: const [FlutterQuillLocalizations.delegate],
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AdminManagement(
                        gateway: gateway,
                        store: store,
                        resource: resource,
                      ),
                    ),
                  ),
                  child: const Text('Management'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Management'));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        final search = find.byType(TextField).first;
        expect(
          find.ancestor(of: search, matching: find.byType(Material)),
          findsWidgets,
        );
        await tester.enterText(search, 'no matching record');
        await tester.pumpAndSettle();
        expect(find.text('No matching records.'), findsOneWidget);
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        if (resource != 'roles') {
          final edit = find.text(
            resource == 'contacts' ? 'Reply by email' : 'Edit',
          );
          await tester.ensureVisible(edit);
          await tester.tap(edit);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byType(ErrorWidget), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Management'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        api.client.close();
      },
    );
  }

  test(
    'new stories notify once, preserve read state, and stay private',
    () async {
      var role = 'admin';
      var storyId = 1;
      var submissionReads = 0;
      final notices = <int>[];
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/mobile/capabilities')) {
            return http.Response(
              jsonEncode({
                'data': {'user_id': 7, 'role': role, 'permissions': <String>[]},
              }),
              200,
            );
          }
          expect(request.url.path, '/api/v1/admin/submissions');
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], 'Bearer test-token');
          submissionReads++;
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': storyId,
                  'kind': 'news_tip',
                  'status': 'received',
                  'title': 'Story $storyId',
                },
                {
                  'id': 99,
                  'kind': 'news_tip',
                  'status': 'resolved',
                  'title': 'Old story',
                },
                {
                  'id': 100,
                  'kind': 'comment_report',
                  'status': 'received',
                  'title': 'Report',
                },
              ],
              'next_cursor': null,
            }),
            200,
          );
        }),
      );
      final inbox = NotificationInbox(
        EditorialGateway(api, sessionFor(api)),
        store,
        onNewStories: notices.add,
      );
      await inbox.refresh();
      expect(inbox.unread, 1);
      expect(inbox.items.single['submission_id'], 1);
      expect(notices, [1]);
      await inbox.markRead(['local:newsroom:1']);
      await inbox.refresh();
      expect(inbox.unread, 0);
      expect(notices, [1]);
      storyId = 2;
      await inbox.refresh();
      expect(inbox.unread, 1);
      expect(notices, [1, 1]);
      expect(await store.pendingNotificationReads(7), isEmpty);
      expect(await store.notifications(8), isEmpty);
      role = 'commenter';
      final before = submissionReads;
      await inbox.refresh();
      expect(submissionReads, before);
      inbox.dispose();
      api.client.close();
    },
  );

  for (final resource in ['users', 'posts', 'roles', 'contacts']) {
    for (final brightness in [null, Brightness.light, Brightness.dark]) {
      testWidgets(
        '$resource returns to Management on ${brightness == null ? 'desktop' : 'iPhone $brightness'}',
        (tester) async {
          final phone = brightness != null;
          if (phone) {
            tester.view.physicalSize = const Size(320, 568);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
          }
          final api = Api(
            client: MockClient((request) async {
              return http.Response(
                jsonEncode({
                  'data': request.url.path.endsWith('/mobile/capabilities')
                      ? {
                          'user_id': 7,
                          'role': 'admin',
                          'permissions': <String>[],
                        }
                      : <Json>[],
                }),
                200,
              );
            }),
          );
          final gateway = EditorialGateway(api, sessionFor(api));
          await tester.pumpWidget(
            MaterialApp(
              theme: phone ? iphoneTheme(brightness) : Brand.theme(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Management'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AdminManagement(
                          gateway: gateway,
                          store: store,
                          resource: resource,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Management'));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          expect(find.byType(AppBar), findsOneWidget);
          expect(find.byType(BackButton), findsOneWidget);
          final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
          final context = tester.element(find.byType(AdminManagement));
          expect(
            scaffold.backgroundColor ??
                Theme.of(context).scaffoldBackgroundColor,
            phone
                ? (brightness == Brightness.dark
                      ? Colors.black
                      : const Color(0xfff2f2f7))
                : const Color(0xfff8fafc),
          );
          if (!phone) {
            expect(find.text('No matching records.'), findsOneWidget);
          }
          expect(
            tester.getRect(find.byType(BackButton)).left,
            greaterThanOrEqualTo(0),
          );
          if (phone) {
            expect(
              find.text('Back to Management').hitTestable(),
              findsOneWidget,
            );
          }
          // Exercise both the explicit toolbar button and the phone fallback.
          await tester.tap(
            phone && brightness == Brightness.dark
                ? find.text('Back to Management')
                : find.byType(BackButton),
          );
          await tester.pumpAndSettle();
          expect(find.text('Management'), findsOneWidget);
          expect(find.byType(AdminManagement), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          api.client.close();
        },
      );
    }
  }
}
