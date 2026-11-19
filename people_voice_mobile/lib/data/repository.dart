import 'push_notifications.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImmutableBuffer, ImageDescriptor;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'api.dart';
import 'local_store.dart';
import 'article_media.dart';
import 'experience.dart';
import 'promotions.dart';

class Session extends ChangeNotifier {
  Session(this.api, {FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final Api api;
  final FlutterSecureStorage storage;
  Json? value;
  String? restoreError;
  ({String email, String password})? _rememberedCredentials;
  Future<bool>? _renewal;
  Timer? _renewalTimer;
  bool renewing = false;
  bool get remembersLogin => _rememberedCredentials != null;
  int _generation = 0;
  Future<void> _storageWrites = Future.value();
  int? get userId => value?['user']['id'] as int?;
  String get username => value?['user']['username'] as String? ?? 'Guest';
  bool get canPublish => value?['user']['can_publish'] == true;
  bool get expired {
    final expiry = DateTime.tryParse('${value?['expires_at']}');
    return expiry == null || !expiry.isAfter(DateTime.now().toUtc());
  }

  String get token {
    if (expired) {
      throw ApiFailure('Your session expired. Please sign in again.');
    }
    return value!['access_token'] as String;
  }

  Future<void> restore() async {
    final generation = ++_generation;
    try {
      await _storageWrites;
      final saved = await storage.read(key: 'session');
      if (generation != _generation) return;
      restoreError = null;
      value = null;
      _rememberedCredentials = null;
      _renewalTimer?.cancel();
      if (saved != null) {
        final decoded = jsonDecode(saved);
        if (!_validSession(decoded) ||
            decoded['expires_at'] is! String ||
            DateTime.tryParse(decoded['expires_at']) == null) {
          throw const FormatException('Invalid saved session');
        }
        final remembered = decoded['_remember'];
        if (remembered is Json &&
            remembered['email'] is String &&
            remembered['password'] is String &&
            (remembered['password'] as String).isNotEmpty) {
          _rememberedCredentials = (
            email: remembered['email'] as String,
            password: remembered['password'] as String,
          );
        }
        value = Json.from(decoded)..remove('_remember');
        _scheduleRenewal();
      }
    } catch (_) {
      if (generation != _generation) return;
      // A keychain problem must not lock users out of downloaded public content.
      value = null;
      restoreError = 'Could not restore your session. You can keep reading offline and sign in again when needed.';
    }
    notifyListeners();
  }

  Future<void> login(
    String email,
    String password, {
    bool remember = false,
  }) async {
    final generation = ++_generation;
    final result = await api.request(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    if (generation != _generation) return;
    if (!_validSession(result) ||
        result['expires_in'] is! int ||
        (result['expires_in'] as int) <= 0) {
      throw ApiFailure(
        'The server returned an invalid session. Please try signing in again.',
      );
    }
    result['expires_at'] = DateTime.now()
        .toUtc()
        .add(Duration(seconds: result['expires_in'] as int))
        .toIso8601String();
    try {
      await _writeStorage(() async {
        if (generation == _generation) {
          await storage.write(
            key: 'session',
            value: jsonEncode({
              ...result,
              if (remember)
                '_remember': {'email': email.trim(), 'password': password},
            }),
          );
        }
      });
    } catch (_) {
      throw ApiFailure(
        'Could not securely save your session. Please try signing in again.',
      );
    }
    if (generation != _generation) return;
    value = result;
    _rememberedCredentials = remember
        ? (email: email.trim(), password: password)
        : null;
    restoreError = null;
    _scheduleRenewal();
    notifyListeners();
  }

  /// Reauthenticate only when the short-lived server token is about to expire.
  /// Concurrent resume/timer requests share the same login operation.
  Future<bool> renewIfNeeded() {
    if (!expired &&
        DateTime.parse(value!['expires_at'] as String)
                .difference(DateTime.now().toUtc()) >
            const Duration(minutes: 5)) {
      return Future.value(true);
    }
    if (_rememberedCredentials == null) return Future.value(false);
    return _renewal ??= _renew().whenComplete(() => _renewal = null);
  }

  Future<bool> _renew() async {
    final credentials = _rememberedCredentials!;
    renewing = true;
    notifyListeners();
    try {
      await login(credentials.email, credentials.password, remember: true);
      return !expired;
    } on ApiFailure catch (error) {
      if (error.status == 401 || error.status == 403) {
        _rememberedCredentials = null;
        _renewalTimer?.cancel();
        try {
          await _writeStorage(
            () => storage.write(key: 'session', value: jsonEncode(value)),
          );
        } catch (_) {
          restoreError =
              'Could not remove the saved sign-in. Sign out on this device.';
        }
      } else {
        _scheduleRenewal(retry: true);
      }
      return false;
    } finally {
      renewing = false;
      notifyListeners();
    }
  }

  void _scheduleRenewal({bool retry = false}) {
    _renewalTimer?.cancel();
    if (_rememberedCredentials == null || value == null) return;
    final expiry = DateTime.tryParse('${value!['expires_at']}');
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now().toUtc());
    final delay = retry
        ? const Duration(minutes: 1)
        : remaining > const Duration(minutes: 6)
        ? remaining - const Duration(minutes: 5)
        : const Duration(minutes: 1);
    _renewalTimer = Timer(delay, () => unawaited(renewIfNeeded()));
  }

  Future<bool> logout() async {
    final previousToken = expired ? null : token;
    ++_generation;
    _renewalTimer?.cancel();
    _rememberedCredentials = null;
    value = null;
    restoreError = null;
    notifyListeners();
    // Clear access immediately, and serialize deletion behind any in-flight
    // login write so it cannot restore the session after the user signs out.
    var storageFailed = false;
    try {
      await _writeStorage(() => storage.delete(key: 'session'));
    } catch (_) {
      storageFailed = true;
    }
    bool revoked = false;
    try {
      if (previousToken != null) {
        await api.request('/auth/logout', body: {}, token: previousToken);
        revoked = true;
      }
    } on ApiFailure {
      /* Local logout is still possible offline. */
    }
    if (storageFailed) {
      throw ApiFailure(
        'Signed out of the app. Secure storage is unavailable, so removal of the saved session could not be confirmed.',
      );
    }
    return revoked;
  }

  static bool _validSession(dynamic session) =>
      session is Json &&
      session['user'] is Json &&
      session['user']['id'] is int &&
      session['user']['id'] > 0 &&
      session['user']['username'] is String &&
      session['access_token'] is String &&
      (session['access_token'] as String).trim().isNotEmpty;

  Future<void> _writeStorage(Future<void> Function() action) {
    final operation = _storageWrites.then((_) => action());
    _storageWrites = operation.catchError((Object _) {});
    return operation;
  }

  @override
  void dispose() {
    _renewalTimer?.cancel();
    super.dispose();
  }
}

class FeedResult {
  FeedResult(this.body, {this.warning});
  final Json body;
  final String? warning;
}

class Repository {
  Repository(this.api, this.store, {this.session, this.promotions, this.push});
  final InAppPush? push;
  final Session? session;
  final PromotionApi? promotions;
  final Api api;
  final LocalStore store;
  late final experience = Experience(
    store,
    api: api,
    tokenFor: (owner) =>
        session != null && !session!.expired && session!.userId == owner
        ? session!.token
        : null,
  );
  final _previews = <int, Future<Json>>{};
  final _authorNames = <int, String>{};
  final _adminUserNames = <int, String>{};
  Future<void>? _adminUserLoad;
  int? _adminUserOwner;

  void rememberAuthor(Json post) {
    final author = post['author'];
    if (author is! Map) return;
    final id = author['id'];
    final name = author['username'];
    if (id is int && name is String && name.trim().isNotEmpty) {
      _authorNames[id] = name.trim();
    }
  }

  String? authorName(int? id) {
    if (id == null) return null;
    if (id == session?.userId) return session!.username;
    return _authorNames[id] ??
        (_adminUserOwner == session?.userId ? _adminUserNames[id] : null);
  }

  /// Administrators can match comment IDs against the existing account list.
  /// Keep this private data in memory and never request it for ordinary readers.
  Future<void> loadAdminUserNames() {
    final owner = session?.userId;
    if (owner == null || session!.expired) return Future.value();
    if (_adminUserOwner != owner) {
      _adminUserNames.clear();
      _adminUserLoad = null;
      _adminUserOwner = owner;
    }
    return _adminUserLoad ??= _fetchAdminUserNames(owner)
        .catchError((Object _) {
          _adminUserLoad = null;
        });
  }

  Future<void> _fetchAdminUserNames(int owner) async {
    final token = session!.token;
    final access = await api.request('/mobile/capabilities', token: token);
    if (access['data']?['user_id'] != owner ||
        access['data']?['role'] != 'admin' ||
        session!.userId != owner) {
      return;
    }
    final names = <int, String>{};
    String? cursor;
    final seen = <String>{};
    do {
      final response = await api.request(
        '/admin/users?limit=100${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
        token: token,
      );
      for (final item in response['data'] as List) {
        if (item is Json &&
            item['id'] is int &&
            item['username'] is String &&
            (item['username'] as String).trim().isNotEmpty) {
          names[item['id'] as int] = (item['username'] as String).trim();
        }
      }
      cursor = response['next_cursor'] as String?;
      if (cursor != null && (!seen.add(cursor) || seen.length >= 100)) return;
    } while (cursor != null);
    if (session!.userId == owner && !session!.expired) {
      _adminUserNames
        ..clear()
        ..addAll(names);
    }
  }

  final _previewInputs = <int, String>{};
  final _coverQueue = <Json>[];
  bool _prefetching = false;
  Future<void>? coverDownloads;

  /// Public feed covers are attempted automatically, including off-screen cards.
  void prefetchCovers(List<Json> posts) {
    _coverQueue.addAll(posts);
    if (!_prefetching) coverDownloads = _drainCovers();
  }

  Future<void> _drainCovers() async {
    _prefetching = true;
    try {
      while (_coverQueue.isNotEmpty) {
        final batch = _coverQueue.take(3).toList();
        _coverQueue.removeRange(0, batch.length);
        await Future.wait(batch.map(preview));
      }
    } catch (_) {
      // A failed cover never prevents reading the feed; refresh retries it.
    } finally {
      _prefetching = false;
    }
  }

  Future<Json> preview(Json post) {
    final id = post['id'] as int;
    final input = jsonEncode(post);
    if (_previewInputs[id] != input) {
      _previews.remove(id);
      _previewInputs[id] = input;
    }
    return _previews.putIfAbsent(
      id,
      // Keep completed previews in memory. Window resizing can rebuild the feed;
      // retaining them prevents a second network request for every article.
      () => _loadPreview(post),
    );
  }

  Future<Json> _loadPreview(Json post) async {
    final id = post['id'] as int;
    try {
      final cached = await store.article(id) ?? await store.summary(id);
      var result = {...?cached, ...post};
      if (!result.containsKey('photo_link')) {
        try {
          result = {...result, ...await article(id)};
        } catch (_) {}
      }
      await store.saveSummary(result);
      final cover = imageUrl(result['photo_link'] as String?);
      if (cover != null) await image(cover);
      return result;
    } catch (_) {
      return post;
    }
  }

  Future<FeedResult> search(String query, {int page = 1}) async {
    final term = query.trim();
    if (term.isEmpty) {
      return FeedResult({'data': <Json>[], 'pages': 1, 'page': 1});
    }
    try {
      if (!const bool.fromEnvironment(
        'EDITORIAL_API_ENABLED',
        defaultValue: true,
      )) {
        throw ApiFailure('Online search is not enabled.');
      }
      final result = await feed(
        '/search?q=${Uri.encodeQueryComponent(term)}&page=$page',
      );
      return result;
    } on ApiFailure {
      final words = term.toLowerCase().split(RegExp(r'\s+'));
      final matches = (await store.searchableArticles()).where((post) {
        final text =
            html
                .parse(
                  '${post['title'] ?? ''} ${post['info'] ?? ''} ${post['content'] ?? ''} ${post['author']?['username'] ?? ''} ${post['categories'] ?? ''}',
                )
                .body
                ?.text
                .toLowerCase() ??
            '';
        return words.every(text.contains);
      }).toList();
      prefetchCovers(matches);
      return FeedResult(
        {'data': matches, 'pages': 1, 'page': 1},
        warning: 'Online search is unavailable. Showing matches from articles saved on this device.',
      );
    }
  }

  static bool _validCategory(String value) =>
      value.trim().isNotEmpty &&
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') !=
          'local test content';

  static Iterable<String> articleCategories(Json post) {
    // Legacy info can be descriptive text, not necessarily a category.
    const primaryCategories = {
      'local news',
      'community',
      'business',
      'technology',
      'opinion',
      'events',
    };
    final primary = (post['info'] as String? ?? '').trim();
    final seen = <String>{};
    return [
          ...(post['categories'] as String? ?? '').split(','),
          if (primaryCategories.contains(primary.toLowerCase())) primary,
        ]
        .map((value) => value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where(_validCategory)
        .where((value) => seen.add(value.toLowerCase()))
        .toList();
  }

  Future<FeedResult> categories() async {
    try {
      final result = await feed('/categories');
      final values = (result.body['data'] as List)
          .map((v) => v is Map ? v['name'] : v)
          .whereType<String>()
          .map((value) => value.trim())
          .where(_validCategory)
          .toSet()
          .toList();
      return FeedResult({
        ...result.body,
        'data': values,
      }, warning: result.warning);
    } on ApiFailure {
      final articles = await store.searchableArticles();
      final values = articles.expand(articleCategories).toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return FeedResult(
        {'data': values},
        warning: 'Online categories are unavailable. Showing categories saved on this device.',
      );
    }
  }

  Future<FeedResult> categoryArticles(String category, {int page = 1}) async {
    try {
      return await feed(
        '/categories/${Uri.encodeComponent(category)}/posts?page=$page',
      );
    } on ApiFailure catch (e) {
      if (e.status != 404) rethrow;
    }
    // Compatibility with older servers while the updated API is deployed.
    final result = await search(category, page: page);
    final matches = List<Json>.from(result.body['data'] as List)
        .where(
          (post) => articleCategories(post).any(
            (value) => value.toLowerCase() == category.trim().toLowerCase(),
          ),
        )
        .toList();
    return FeedResult({
      ...result.body,
      'data': matches,
    }, warning: result.warning);
  }

  Future<FeedResult> feed(String path) async {
    try {
      var result = await api.request(path);
      String? promotionWarning;
      if (path == '/posts/featured' && promotions != null) {
        try {
          final appPosts = await promotions!.featured();
          final seen = <int>{};
          final merged = <Json>[];
          for (final post in [
            ...List<Json>.from(result['data'] as List),
            ...appPosts,
          ]) {
            if (seen.add(post['id'] as int)) merged.add(post);
          }
          result = {...result, 'data': merged};
        } catch (_) {
          promotionWarning =
              'App promotions could not be refreshed. Pull down to try again.';
        }
      }
      if (result['data'] is! List) {
        throw ApiFailure(
          'The server returned an invalid list. Please try again.',
        );
      }
      final isArticleList =
          path.startsWith('/posts?') ||
          path == '/posts/featured' ||
          path.startsWith('/search?') ||
          (path.startsWith('/categories/') && path.contains('/posts'));
      if (isArticleList &&
          (result['data'] as List).any(
            (post) =>
                post is! Json || post['id'] is! int || post['title'] is! String,
          )) {
        throw ApiFailure(
          'The server returned an invalid article list. Please try again.',
        );
      }
      await store.cache(path, result);
      if (isArticleList) {
        final posts = List<Json>.from(result['data'] as List);
        for (final post in posts) {
          rememberAuthor(post);
          // Refresh retries previews that were incomplete while offline.
          _previews.remove(post['id']);
          await store.saveSummary(post);
        }
        prefetchCovers(posts);
      }
      return FeedResult(result, warning: promotionWarning);
    } on ApiFailure catch (e) {
      final cached = await store.cached(path);
      if (cached == null) rethrow;
      if (cached['data'] is List) {
        for (final item in cached['data'] as List) {
          if (item is Json) rememberAuthor(item);
        }
      }
      return FeedResult(
        cached,
        warning: '${e.message} Showing the last saved copy.',
      );
    }
  }

  Future<Json> article(int id, {bool refresh = false}) async {
    final cached = await store.article(id);
    if (cached != null && !refresh) {
      rememberAuthor(cached);
      return cached;
    }
    // Public requests only: never cache an author's private draft as a public article.
    final response = await api.request('/posts/$id');
    final detail = response['data'];
    if (detail is! Json || detail['content'] is! String || detail['id'] != id) {
      throw ApiFailure(
        'The server did not return the complete article. It has not been marked as downloaded.',
      );
    }
    await store.saveArticle(detail);
    rememberAuthor(detail);
    return detail;
  }

  String? imageUrl(String? source) {
    if (source == null || source.isEmpty) return null;
    if (source.startsWith(localImagePrefix)) return source;
    try {
      final uri = Api.site.resolve(source);
      return (uri.scheme == 'https' ||
                  (uri.scheme == 'http' && uri.origin == Api.site.origin)) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? uri.toString()
          : null;
    } on FormatException {
      return null;
    }
  }

  final Map<String, Future<Uint8List?>> _imagesInFlight = {};
  Future<Uint8List?> image(String url) async {
    // Feed covers use site-relative paths; readers may already pass full URLs.
    // Resolve both to the same download and offline-cache key.
    final resolved = imageUrl(url.trim());
    if (resolved == null) return null;
    url = resolved;
    final cached = await store.image(url);
    if (cached != null) return cached;
    return _imagesInFlight.putIfAbsent(
      url,
      () => _downloadImage(url).whenComplete(() {
        _imagesInFlight.remove(url);
      }),
    );
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      // Never send API credentials to image hosts.
      final response = await api.client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 10));
      final contentType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      final genericBinary = contentType == 'application/octet-stream';
      if (response.statusCode != 200 ||
          (!contentType.startsWith('image/') && !genericBinary) ||
          (response.contentLength ?? 0) > 5 * 1024 * 1024) {
        await response.stream.listen((_) {}).cancel();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 5 * 1024 * 1024) {
          throw const FormatException('Image too large');
        }
      }
      final data = Uint8List.fromList(bytes);
      // Some Docker static servers serve WebP with a generic MIME type.
      // Verify those bytes before persisting them as an offline image.
      if (genericBinary) {
        final buffer = await ImmutableBuffer.fromUint8List(data);
        ImageDescriptor? descriptor;
        try {
          descriptor = await ImageDescriptor.encoded(buffer);
          if (descriptor.width * descriptor.height > 20000000) return null;
        } finally {
          descriptor?.dispose();
          buffer.dispose();
        }
      }
      await store.saveImage(url, data);
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Missing media never prevents reading the downloaded article text.
  Future<int> downloadImages(Json article) async {
    final document = html.parse(article['content'] as String? ?? '');
    final urls = <String>{
      if (imageUrl(article['photo_link'] as String?) case final String url) url,
      ...document
          .querySelectorAll('img')
          .map((e) => imageUrl(e.attributes['src']))
          .whereType<String>(),
    };
    int missing = urls.length > 20 ? urls.length - 20 : 0;
    for (final url in urls.take(20)) {
      if (await image(url) == null) missing++;
    }
    return missing;
  }
}
