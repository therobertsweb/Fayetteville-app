import 'package:flutter/material.dart';

import 'local_store.dart';
import 'api.dart';

/// Device preferences are scoped to the signed-in account (0 for guests).
class Experience extends ChangeNotifier {
  Experience(this.store, {this.api, this.tokenFor});
  final LocalStore store;
  final Api? api;
  final String? Function(int)? tokenFor;
  String? syncWarning;
  Json _pending = {};
  Future<void>? _synchronization;
  int? _syncGeneration;
  bool _loaded = false;
  int owner = 0;
  Json value = {};
  int _generation = 0;
  Future<void> _writes = Future.value();
  Future<void>? _loading;
  Future<void> load(int account) {
    final future = _load(account);
    _loading = future;
    return future;
  }

  Future<void> _load(int account) async {
    final generation = ++_generation;
    owner = account;
    _loaded = false;
    _pending = {};
    syncWarning = null;
    value = {};
    notifyListeners();
    await _writes;
    final saved = await store.cached('experience:$account');
    final pending = await store.cached('experience-pending:$account');
    if (generation != _generation) return;
    value = saved ?? {};
    _pending = pending ?? {};
    _loaded = true;
    notifyListeners();
    await sync();
  }

  bool remoteKey(String key) =>
      const [
        'categories',
        'authors',
        'blocked',
        'events',
        'theme',
        'fontSize',
      ].contains(key) ||
      key.startsWith('notify:') ||
      key.startsWith('authorName:') ||
      key.startsWith('followedAt:');
  Future<void> sync() async {
    if (!_loaded || api == null || owner == 0) return;
    final account = owner, generation = _generation;
    final token = tokenFor?.call(account);
    if (token == null) return;
    final current = _synchronization;
    if (current != null) {
      final syncingGeneration = _syncGeneration;
      await current;
      // A newly selected account needs its own sync after the previous one
      // finishes. Calls for the same account share the current operation.
      if (generation == _generation && syncingGeneration != generation) {
        await sync();
      }
      return;
    }
    _syncGeneration = generation;
    final operation = _sync(account, generation, token);
    _synchronization = operation;
    try {
      await operation;
    } finally {
      if (identical(_synchronization, operation)) {
        _synchronization = null;
        _syncGeneration = null;
      }
    }
  }

  Future<void> _sync(int account, int generation, String token) async {
    try {
      do {
        // Persist changes before sending them. A restart or failed request
        // must leave an accurate queue that can safely be retried.
        await _writes;
        if (generation != _generation) return;
        while (_pending.isNotEmpty && generation == _generation) {
          final item = _pending.entries.first;
          await api!.request(
            '/me/preferences',
            body: {'key': item.key, 'value': item.value},
            token: token,
          );
          if (generation != _generation) return;
          if (identical(_pending[item.key], item.value) ||
              _pending[item.key] == item.value) {
            _pending.remove(item.key);
          }
          await _persist(account);
        }
        if (generation != _generation) return;
        final response = await api!.request('/me/preferences', token: token);
        if (generation != _generation) return;
        if (response['data'] is! Json) {
          throw ApiFailure('The server returned invalid preferences.');
        }
        value = {...value, ...response['data'] as Json, ..._pending};
        await _persist(account);
        // Edits made while a GET was in flight also need to be uploaded.
      } while (generation == _generation && _pending.isNotEmpty);
      if (generation != _generation) return;
      syncWarning = null;
    } catch (_) {
      if (generation == _generation) syncWarning = 'Saved on this device. Server sync is pending; reconnect and retry.';
    } finally {
      if (generation == _generation) notifyListeners();
    }
  }

  Future<void> set(String key, dynamic next) async {
    if (!_loaded) {
      final generation = _generation;
      await _loading;
      if (!_loaded || generation != _generation) return;
    }
    value = {...value, key: next};
    final account = owner;
    if (remoteKey(key) && account != 0) _pending[key] = next;
    notifyListeners();
    await _persist(account);
    if (account != owner) return;
    notifyListeners();
    await sync();
  }

  Future<void> _persist(int account) {
    final snapshot = Map<String, dynamic>.from(value);
    final pending = Map<String, dynamic>.from(_pending);
    // Serialize writes so a slow previous edit cannot overwrite newer settings.
    final operation = _writes.then((_) async {
      await store.cache('experience:$account', snapshot);
      await store.cache('experience-pending:$account', pending);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  List<String> strings(String key) =>
      List<String>.from(value[key] as List? ?? []);
  Future<void> toggle(String key, String id) async {
    if (!_loaded) {
      final generation = _generation;
      await _loading;
      if (!_loaded || generation != _generation) return;
    }
    final items = strings(key).toSet();
    if (!items.add(id)) items.remove(id);
    return set(key, items.toList());
  }

  bool followsCategory(String category) =>
      strings('categories').contains(category.toLowerCase());
  bool followsAuthor(int id) => strings('authors').contains('$id');
  bool blocked(int? id) => id != null && strings('blocked').contains('$id');
  bool enabled(String kind) => value['notify:$kind'] != false;
  ThemeMode get theme => switch (value['theme']) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  double get fontSize =>
      ((value['fontSize'] as num?)?.toDouble() ?? 18).clamp(14, 28);
  List<Json> get savedEvents => List<Json>.from(value['events'] as List? ?? []);
  Future<void> saveEvent(Json event) async {
    if (!_loaded) {
      final generation = _generation;
      await _loading;
      if (!_loaded || generation != _generation) return;
    }
    final items = [...savedEvents];
    final exists = items.any((e) => e['id'] == event['id']);
    items.removeWhere((e) => e['id'] == event['id']);
    if (!exists) items.add(event);
    return set('events', items);
  }

  Future<void> checkActivity() async {
    if (owner != 0 && api != null) {
      await sync();
      return;
    }
    final account = owner;
    final generation = _generation;
    final now = DateTime.now().toUtc();
    if (enabled('events')) {
      for (final event in savedEvents) {
        final start = DateTime.tryParse('${event['starts_at']}');
        if (start == null ||
            !start.isAfter(now) ||
            start.difference(now) > const Duration(days: 1)) {
          continue;
        }
        await store.localNotification(
          account,
          'event:${event['id']}:${event['starts_at']}',
          {
            'title': 'Upcoming saved event',
            'message': '${event['title']} · ${event['starts_at']}',
            'created': now.toIso8601String(),
            'kind': 'events',
          },
        );
      }
    }
    if (enabled('authors')) {
      for (final post in await store.searchableArticles()) {
        if (generation != _generation) return;
        final author = post['author']?['id'] as int?;
        if (author == null || !followsAuthor(author) || blocked(author)) {
          continue;
        }
        final since = DateTime.tryParse('${value['followedAt:$author']}');
        final created = DateTime.tryParse('${post['created']}');
        if (since == null || created == null || !created.isAfter(since)) {
          continue;
        }
        await store.localNotification(account, 'author:${post['id']}', {
          'title': 'New from ${post['author']['username']}',
          'message': post['title'],
          'article_id': post['id'],
          'created': now.toIso8601String(),
          'kind': 'authors',
        });
      }
    }
  }
}
