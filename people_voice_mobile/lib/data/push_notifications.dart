import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'local_store.dart';

abstract class InAppPushGateway {
  Future<void> initialize();
  Stream<RemoteMessage> get messages;
  Future<void> subscribe();
  Future<void> unsubscribe();
}

/// Only public, data-only messages are accepted. Private account activity keeps
/// using the authenticated inbox API; it must never use public Firebase topics.
class InAppPush extends ChangeNotifier {
  InAppPush(this.store, {required this.owner, InAppPushGateway? gateway})
    : gateway = gateway ?? FirebaseInAppPushGateway();
  final LocalStore store;
  final int Function() owner;
  final InAppPushGateway gateway;
  static const preferenceKey = 'firebase-in-app-updates-v1';
  bool enabled = false, ready = false, busy = false, active = true;
  bool _disposed = false;
  String? error;
  StreamSubscription<RemoteMessage>? _subscription;
  Future<void>? _starting;
  Future<void> _delivery = Future.value();
  Timer? _retry;
  int _attempts = 0;

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      enabled = (await store.cached(preferenceKey))?['enabled'] == true;
      await gateway.initialize();
      if (_disposed) return;
      _subscription = gateway.messages.listen((message) {
        final account = owner();
        if (!active || !enabled || _disposed) return;
        _delivery = _delivery.then((_) => _receive(message, account));
      });
      ready = true;
      error = null;
      // Remove legacy registrations too when the user has not opted in.
      await synchronize();
    } catch (_) {
      error = 'Live updates could not connect. Tap Retry.';
    } finally {
      _notify();
    }
  }

  Future<void> _receive(RemoteMessage message, int account) async {
    final data = message.data;
    final kind = data['kind'];
    final id = int.tryParse('${data['content_id']}');
    final title = data['title'];
    final body = data['body'];
    if (_disposed ||
        !active ||
        !enabled ||
        owner() != account ||
        message.notification != null ||
        data['mode'] != 'in_app' ||
        (kind != 'news' && kind != 'podcasts') ||
        id == null ||
        id < 1 ||
        title is! String ||
        title.trim().isEmpty ||
        body is! String) {
      return;
    }
    try {
      await store.localNotification(account, 'firebase:$kind:$id', {
        'title': title,
        'message': body,
        'kind': kind,
        'created': (message.sentTime ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        if (kind == 'news') 'article_id': id,
        if (kind == 'podcasts') 'podcast_id': id,
      });
    } catch (_) {
      error = 'A live update could not be saved. Check device storage.';
      _notify();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (busy || !ready || _disposed) return;
    busy = true;
    _notify();
    var saved = false;
    try {
      await store.cache(preferenceKey, {'enabled': value});
      if (_disposed) return;
      enabled = value;
      _attempts = 0;
      saved = true;
    } catch (_) {
      error = 'Could not save your live update preference. Try again.';
    } finally {
      busy = false;
      _notify();
    }
    if (saved) await synchronize();
  }

  Future<void> retry() async {
    if (_disposed) return;
    _attempts = 0;
    if (!ready) {
      _starting = null;
      await start();
    } else {
      await synchronize();
    }
  }

  Future<void> synchronize() async {
    if (!ready || busy || _disposed) return;
    busy = true;
    _notify();
    try {
      if (enabled) {
        await gateway.subscribe();
      } else {
        await gateway.unsubscribe();
      }
      error = null;
      _attempts = 0;
      _retry?.cancel();
    } catch (_) {
      error = 'Live updates are waiting to connect. Tap Retry when online.';
      if (!_disposed && active && _attempts++ < 3) {
        _retry?.cancel();
        _retry = Timer(const Duration(seconds: 5), synchronize);
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class FirebaseInAppPushGateway implements InAppPushGateway {
  static const topics = [
    'people_voice_news_in_app_v1',
    'people_voice_podcasts_in_app_v1',
  ];
  FirebaseMessaging get messaging => FirebaseMessaging.instance;
  @override
  Stream<RemoteMessage> get messages => FirebaseMessaging.onMessage;
  @override
  Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
  }

  @override
  Future<void> subscribe() async {
    // Request no system presentation privileges. FCM on Apple still needs APNs
    // registration even when its payload only updates the foreground inbox.
    await messaging.requestPermission(alert: false, badge: false, sound: false);
    await messaging.setAutoInitEnabled(true);
    if ((defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        await messaging.getAPNSToken() == null) {
      throw StateError('Waiting for APNs registration');
    }
    await messaging.register();
    // Do not inherit legacy topics whose sender may include system alerts.
    for (final topic in ['people_voice_news', 'people_voice_podcasts']) {
      await messaging.unsubscribeFromTopic(topic);
    }
    for (final topic in topics) {
      await messaging.subscribeToTopic(topic);
    }
  }

  @override
  Future<void> unsubscribe() async {
    await messaging.setAutoInitEnabled(false);
    await messaging.unregister();
  }
}
