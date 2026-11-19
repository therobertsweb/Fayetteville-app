import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

typedef Json = Map<String, dynamic>;

/// Durable, transactional storage. Article details are separate from summaries:
/// refreshing a feed must never replace a downloaded article with a title only.
class LocalStore {
  LocalStore(this.db);
  final Database db;
  static const _summariesSchema =
      'CREATE TABLE summaries (id INTEGER PRIMARY KEY, body TEXT NOT NULL)';
  Future<void> saveSummary(Json post) => db.insert('summaries', {
    'id': post['id'],
    'body': jsonEncode(post),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<Json?> summary(int id) async {
    final rows = await db.query('summaries', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['body'] as String) as Json;
  }

  Future<List<Json>> searchableArticles() async {
    final result = <int, Json>{};
    for (final row in await db.query('summaries')) {
      final post = jsonDecode(row['body'] as String) as Json;
      result[post['id'] as int] = post;
    }
    for (final post in await articles()) {
      result[post['id'] as int] = post;
    }
    return result.values.toList();
  }

  final notificationChanges = ValueNotifier<int>(0);
  Future<void> localNotification(int owner, String id, Json body) async {
    await db.insert('notifications', {
      'owner': owner,
      'id': id,
      'body': jsonEncode(body),
      'created': body['created'],
      'is_read': 0,
      'pending_read': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    notificationChanges.value++;
  }

  static const _notificationsSchema =
      'CREATE TABLE notifications (owner INTEGER NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, created TEXT NOT NULL, is_read INTEGER NOT NULL DEFAULT 0, pending_read INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(owner, id))';

  Future<List<Json>> notifications(int owner) async =>
      (await db.query(
            'notifications',
            where: 'owner = ?',
            whereArgs: [owner],
            orderBy: 'created DESC, id DESC',
          ))
          .map(
            (row) => {
              ...jsonDecode(row['body'] as String) as Json,
              'id': row['id'],
              'read': row['is_read'] == 1,
            },
          )
          .toList();

  Future<void> mergeNotifications(int owner, List<Json> items) async {
    await db.transaction((txn) async {
      for (final item in items) {
        final id = 'remote:${item['id']}';
        final existing = await txn.query(
          'notifications',
          where: 'owner = ? AND id = ?',
          whereArgs: [owner, id],
        );
        await txn.insert('notifications', {
          'owner': owner,
          'id': id,
          'body': jsonEncode(item),
          'created': item['created'],
          'is_read':
              item['read'] == true ||
                  (existing.isNotEmpty && existing.first['is_read'] == 1)
              ? 1
              : 0,
          'pending_read': item['read'] == true
              ? 0
              : (existing.isEmpty ? 0 : existing.first['pending_read']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    notificationChanges.value++;
  }

  Future<void> readNotifications(int owner, List<String> ids) async {
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notifications',
          {
            'is_read': 1,
            'pending_read':
                id.startsWith('remote:') && !id.startsWith('remote:promotion:')
                ? 1
                : 0,
          },
          where: 'owner = ? AND id = ?',
          whereArgs: [owner, id],
        );
      }
    });
    notificationChanges.value++;
  }

  Future<List<String>> pendingNotificationReads(int owner) async =>
      (await db.query(
        'notifications',
        columns: ['id'],
        where: 'owner = ? AND pending_read = 1',
        whereArgs: [owner],
      )).map((row) => (row['id'] as String).substring(7)).toList();

  Future<void> acknowledgeNotificationReads(int owner, List<String> ids) async {
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notifications',
          {'pending_read': 0},
          where: 'owner = ? AND id = ?',
          whereArgs: [owner, 'remote:$id'],
        );
      }
    });
  }

  static const _favoritesSchema =
      'CREATE TABLE favorites (owner INTEGER NOT NULL, id INTEGER NOT NULL, saved INTEGER NOT NULL, revision TEXT NOT NULL, synced INTEGER NOT NULL, PRIMARY KEY(owner, id))';

  Future<bool> favorite(int owner, int id) async {
    final rows = await db.query(
      'favorites',
      where: 'owner = ? AND id = ?',
      whereArgs: [owner, id],
    );
    return rows.isNotEmpty && rows.first['saved'] == 1;
  }

  Future<void> setFavorite(int owner, int id, bool saved, String revision) =>
      db.insert('favorites', {
        'owner': owner,
        'id': id,
        'saved': saved ? 1 : 0,
        'revision': revision,
        'synced': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Json>> favoriteArticles(int owner) async {
    final rows = await db.rawQuery(
      'SELECT a.body FROM articles a JOIN favorites f ON a.id = f.id WHERE f.owner = ? AND f.saved = 1 ORDER BY a.saved_at DESC',
      [owner],
    );
    return rows.map((r) => jsonDecode(r['body'] as String) as Json).toList();
  }

  Future<List<Map<String, Object?>>> pendingFavorites(int owner) => db.query(
    'favorites',
    where: 'owner = ? AND synced = 0',
    whereArgs: [owner],
  );
  Future<void> acknowledgeFavorite(int owner, int id, String revision) =>
      db.update(
        'favorites',
        {'synced': 1},
        where: 'owner = ? AND id = ? AND revision = ?',
        whereArgs: [owner, id, revision],
      );

  static Future<LocalStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final engine = factory ?? databaseFactory;
    final location =
        path ?? '${await engine.getDatabasesPath()}/people_voice.db';
    final db = await engine.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 4,
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await db.execute(_favoritesSchema);
          if (oldVersion < 3) await db.execute(_notificationsSchema);
          if (oldVersion < 4) await db.execute(_summariesSchema);
        },
        onCreate: (db, _) async {
          await db.execute(_notificationsSchema);
          await db.execute(_favoritesSchema);
          await db.execute(_summariesSchema);
          await db.execute(
            'CREATE TABLE cache (key TEXT PRIMARY KEY, body TEXT NOT NULL, saved_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE articles (id INTEGER PRIMARY KEY, body TEXT NOT NULL, saved_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE images (url TEXT PRIMARY KEY, bytes BLOB NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE drafts (id TEXT PRIMARY KEY, body TEXT NOT NULL, updated_at TEXT NOT NULL)',
          );
        },
      ),
    );
    return LocalStore(db);
  }

  Future<void> cache(String key, Json body) => db.insert('cache', {
    'key': key,
    'body': jsonEncode(body),
    'saved_at': DateTime.now().toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Json?> cached(String key) async {
    final rows = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['body'] as String) as Json;
  }

  Future<void> saveArticle(Json article) => db.insert('articles', {
    'id': article['id'],
    'body': jsonEncode(article),
    'saved_at': DateTime.now().toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Json?> article(int id) async {
    final rows = await db.query('articles', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['body'] as String) as Json;
  }

  Future<List<Json>> articles() async => (await db.query(
    'articles',
    orderBy: 'saved_at DESC',
  )).map((r) => jsonDecode(r['body'] as String) as Json).toList();

  Future<void> saveImage(String url, Uint8List bytes) => db.insert('images', {
    'url': url,
    'bytes': bytes,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Uint8List?> image(String url) async {
    final rows = await db.query('images', where: 'url = ?', whereArgs: [url]);
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  Future<void> saveDraft(Json draft) async {
    var changed = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'drafts',
        where: 'id = ?',
        whereArgs: [draft['local_id']],
      );
      final previous = rows.isEmpty
          ? null
          : jsonDecode(rows.first['body'] as String) as Json;
      await txn.insert('drafts', {
        'id': draft['local_id'],
        'body': jsonEncode(draft),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final state = draft['state'];
      if (state != previous?['state'] &&
          ['remote', 'published', 'uncertain'].contains(state)) {
        final title = switch (state) {
          'published' => 'Article published',
          'remote' => 'Draft received by the server',
          _ => 'Review your submission',
        };
        final detail = state == 'uncertain'
            ? 'Could not confirm the submission of «${draft['title']}». Check its status in Drafts before submitting again.'
            : '«${draft['title']}» ${state == 'published' ? 'has been published.' : 'is saved on the server and has not been published yet.'}';
        final now = DateTime.now().toUtc().toIso8601String();
        await txn.insert('notifications', {
          'owner': draft['owner_id'] ?? 0,
          'id': 'draft:${draft['local_id']}:$state',
          'created': now,
          'body': jsonEncode({
            'title': title,
            'message': detail,
            'created': now,
            if (state == 'published') 'article_id': draft['remote_id'],
          }),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        changed = true;
      }
    });
    if (changed) notificationChanges.value++;
  }

  Future<Json?> draft(String id) async {
    final rows = await db.query('drafts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['body'] as String) as Json;
  }

  Future<List<Json>> drafts(int? userId) async {
    final rows = await db.query('drafts', orderBy: 'updated_at DESC');
    return rows
        .map((r) => jsonDecode(r['body'] as String) as Json)
        .where((d) => d['owner_id'] == null || d['owner_id'] == userId)
        .toList();
  }
}
