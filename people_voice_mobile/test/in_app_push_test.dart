import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/push_notifications.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeGateway implements InAppPushGateway {
  final stream = StreamController<RemoteMessage>.broadcast(sync: true);
  int subscriptions = 0, removals = 0;
  bool fail = false;
  @override
  Stream<RemoteMessage> get messages => stream.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> subscribe() async {
    if (fail) throw StateError('offline');
    subscriptions++;
  }

  @override
  Future<void> unsubscribe() async => removals++;
}

RemoteMessage update({
  String kind = 'news',
  String mode = 'in_app',
  bool alert = false,
}) => RemoteMessage(
  data: {
    'mode': mode,
    'kind': kind,
    'content_id': '42',
    'title': 'Community update',
    'body': 'New public story',
  },
  notification: alert
      ? const RemoteNotification(title: 'Legacy system alert')
      : null,
  sentTime: DateTime.utc(2026, 11, 19),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalStore store;
  late FakeGateway gateway;
  late InAppPush push;
  var owner = 4;
  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    gateway = FakeGateway();
    owner = 4;
    push = InAppPush(store, owner: () => owner, gateway: gateway);
    await push.start();
  });
  tearDown(() async {
    push.dispose();
    await gateway.stream.close();
    await store.db.close();
  });
  Future<void> deliver(RemoteMessage message) async {
    gateway.stream.add(message);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test(
    'opt-in persists and disabled devices remove legacy registration',
    () async {
      expect(push.enabled, isFalse);
      expect(gateway.removals, 1);
      await deliver(update());
      expect(await store.notifications(4), isEmpty);
      await push.setEnabled(true);
      expect(gateway.subscriptions, 1);
      expect((await store.cached(InAppPush.preferenceKey))?['enabled'], isTrue);
      await push.setEnabled(false);
      expect(gateway.removals, 2);
      await deliver(update());
      expect(await store.notifications(4), isEmpty);
    },
  );

  test('foreground updates persist once and never reset read status', () async {
    await push.setEnabled(true);
    await deliver(update());
    final items = await store.notifications(4);
    expect(items, hasLength(1));
    expect(items.single['article_id'], 42);
    await store.readNotifications(4, [items.single['id'] as String]);
    await deliver(update());
    expect((await store.notifications(4)).single['read'], isTrue);
    expect(await store.notifications(5), isEmpty);
    expect(await store.pendingNotificationReads(4), isEmpty);
  });

  test(
    'background, system-alert and private payloads are not added to the inbox',
    () async {
      await push.setEnabled(true);
      push.active = false;
      await deliver(update());
      push.active = true;
      await deliver(update(alert: true));
      await deliver(update(kind: 'private_reply'));
      await deliver(update(mode: 'system'));
      expect(await store.notifications(4), isEmpty);
      await deliver(update(kind: 'podcasts'));
      expect((await store.notifications(4)).single['podcast_id'], 42);
    },
  );

  test('queued deliveries are discarded after account switching', () async {
    await push.setEnabled(true);
    gateway.stream.add(update());
    owner = 5;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await store.notifications(4), isEmpty);
    expect(await store.notifications(5), isEmpty);
  });

  test('offline subscriptions preserve intent and recover on retry', () async {
    gateway.fail = true;
    await push.setEnabled(true);
    expect(push.error, isNotNull);
    expect(push.enabled, isTrue);
    gateway.fail = false;
    await push.retry();
    expect(push.error, isNull);
    expect(gateway.subscriptions, 1);
  });
}
