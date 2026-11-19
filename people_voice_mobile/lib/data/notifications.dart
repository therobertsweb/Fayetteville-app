import 'package:flutter/foundation.dart';

import 'api.dart';
import 'editorial.dart';
import 'local_store.dart';
import 'experience.dart';
import 'promotions.dart';

/// Private, account-scoped inbox. Local read state survives offline refreshes.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox(
    this.gateway,
    this.store, {
    this.preferences,
    this.onNewStories,
    this.promotions,
  }) {
    store.notificationChanges.addListener(reload);
    gateway.session.addListener(_accountChanged);
    preferences?.addListener(reload);
    reload();
  }
  final EditorialGateway gateway;
  final LocalStore store;
  final Experience? preferences;
  final PromotionApi? promotions;
  final void Function(int count)? onNewStories;
  List<Json> items = [];
  String? error;
  bool busy = false, _disposed = false;
  int _generation = 0;
  int get owner => gateway.session.userId ?? 0;
  int get unread => items.where((item) => item['read'] != true).length;

  void _accountChanged() {
    _generation++;
    items = [];
    error = null;
    busy = false;
    notifyListeners();
    refresh();
  }

  Future<void> reload() async {
    final generation = _generation;
    final account = owner;
    try {
      final result = await store.notifications(account);
      if (_disposed || generation != _generation || account != owner) return;
      items = result.where((item) {
        final kind = item['kind'] ?? item['type'];
        if (kind == 'reply' || kind == 'comment_reply') {
          return preferences?.enabled('replies') ?? true;
        }
        return preferences?.enabled('$kind') ?? true;
      }).toList();
      notifyListeners();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'Could not open the local inbox. Try again.';
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    if (busy || _disposed) return;
    final generation = _generation;
    final account = owner;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await preferences?.checkActivity();
      if (_disposed || generation != _generation || account != owner) return;
      await reload();
      if (_disposed || generation != _generation || account != owner) return;
      if (!gateway.enabled || gateway.session.expired) return;
      final token = gateway.session.token;
      final access = await gateway.capabilities();
      if (generation != _generation || _disposed) return;
      if (access.role == 'admin') {
        try {
          await _refreshStories(account, token, generation);
        } catch (e) {
          if (!_disposed && generation == _generation) error = '$e';
        }
        if (promotions != null) {
          try {
            final paid = await promotions!.notifications(token);
            if (_disposed || generation != _generation || account != owner) {
              return;
            }
            await store.mergeNotifications(account, paid);
            await reload();
          } catch (e) {
            if (!_disposed && generation == _generation) error = '$e';
          }
        }
      }
      if (generation != _generation || _disposed) return;
      if (!access.notifications) return;
      final read = await store.pendingNotificationReads(account);
      if (_disposed || generation != _generation || account != owner) return;
      if (read.isNotEmpty) {
        await gateway.api.request(
          '/notifications/read',
          token: token,
          body: {'ids': read},
        );
        await store.acknowledgeNotificationReads(account, read);
        if (_disposed || generation != _generation || account != owner) return;
      }
      String? cursor;
      final seen = <String>{};
      for (var page = 0; page < 100; page++) {
        final response = await gateway.api.request(
          '/notifications?limit=100${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
          token: token,
        );
        if (_disposed || generation != _generation || account != owner) return;
        final rows = List<Json>.from(response['data'] as List);
        if (rows.any(
          (item) =>
              item['id'] is! String ||
              item['title'] is! String ||
              item['message'] is! String ||
              item['created'] is! String ||
              DateTime.tryParse(item['created']) == null ||
              item['read'] is! bool ||
              (item['article_id'] != null && item['article_id'] is! int),
        )) {
          throw ApiFailure(
            'The notifications received have an invalid format.',
          );
        }
        await store.mergeNotifications(account, rows);
        cursor = response['next_cursor'] as String?;
        if (cursor == null) break;
        if (!seen.add(cursor) || page == 99) {
          throw ApiFailure('Could not finish refreshing notifications.');
        }
      }
      await reload();
    } catch (e) {
      if (!_disposed && generation == _generation) error = '$e';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshStories(
    int account,
    String token,
    int generation,
  ) async {
    bool current() =>
        !_disposed && generation == _generation && account == owner;
    final existing = (await store.notifications(account))
        .map((item) => item['id'])
        .toSet();
    String? cursor;
    final cursors = <String>{};
    final stories = <Json>[];
    do {
      final response = await gateway.api.request(
        '/admin/submissions${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
        token: token,
      );
      if (!current()) return;
      stories.addAll(List<Json>.from(response['data'] as List));
      cursor = response['next_cursor'] as String?;
      if (cursor != null && (!cursors.add(cursor) || cursors.length >= 100)) {
        throw ApiFailure('Could not finish checking newsroom submissions.');
      }
    } while (cursor != null);
    var added = 0;
    for (final story in stories) {
      if (!current()) return;
      if (story['kind'] != 'news_tip' ||
          story['status'] != 'received' ||
          story['id'] is! int) {
        continue;
      }
      final id = 'local:newsroom:${story['id']}';
      if (!existing.add(id)) continue;
      await store.localNotification(account, id, {
        'kind': 'newsroom',
        'title': 'New story for the newsroom',
        'message': '${story['title']}',
        'created': DateTime.now().toUtc().toIso8601String(),
        'submission_id': story['id'],
      });
      added++;
    }
    if (!current()) return;
    await reload();
    if (current() && added > 0) onNewStories?.call(added);
  }

  Future<void> markRead(List<String> ids) async {
    try {
      await store.readNotifications(owner, ids);
      await reload();
      await refresh();
    } catch (_) {
      if (!_disposed) {
        error = 'Could not save the read status.';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    preferences?.removeListener(reload);
    _disposed = true;
    store.notificationChanges.removeListener(reload);
    gateway.session.removeListener(_accountChanged);
    super.dispose();
  }
}
