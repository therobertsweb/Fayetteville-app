import 'dart:math';

import 'api.dart';
import 'local_store.dart';
import 'repository.dart';

String operationId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

const roleNames = {
  'admin': 'Administrators',
  'editor': 'Editors',
  'author': 'Authors',
  'moderator': 'Moderators',
  'advertiser': 'Advertisers',
  'commenter': 'Readers',
};
String roleName(String role) => roleNames[role] ?? 'Other role';

class Capabilities {
  const Capabilities({
    this.role,
    this.ai = false,
    this.review = false,
    this.analytics = false,
    this.rankings = false,
    this.saves = false,
    this.notifications = false,
    this.promotionReview = false,
    this.bufferManage = false,
    this.openaiConfigured = false,
    this.bufferConfigured = false,
  });
  final String? role;
  final bool ai, review, analytics, rankings, saves, notifications;
  final bool promotionReview;
  final bool bufferManage, openaiConfigured, bufferConfigured;
}

/// Server-derived editorial capabilities. Administrative rights always come
/// from the authenticated API response, never from the legacy publish flag.
class EditorialGateway {
  EditorialGateway(
    this.api,
    this.session, {
    this.enabled = const bool.fromEnvironment(
      'EDITORIAL_API_ENABLED',
      defaultValue: true,
    ),
  });
  final Api api;
  final Session session;
  final bool enabled;

  Future<Capabilities> capabilities() async {
    if (!enabled || session.expired) return const Capabilities();
    final owner = session.userId;
    final response = await api.request(
      '/mobile/capabilities',
      token: session.token,
    );
    final data = response['data'] as Json;
    if (data['user_id'] != owner || session.userId != owner) {
      throw ApiFailure('Could not verify your account.');
    }
    final permissions = List<String>.from(data['permissions'] as List);
    final role = data['role'] as String;
    final services = data['services'] is Json
        ? data['services'] as Json
        : <String, dynamic>{};
    return Capabilities(
      role: role,
      ai: permissions.contains('ai:write'),
      review: role == 'admin' && permissions.contains('drafts:manage'),
      analytics: role == 'admin' && permissions.contains('analytics:read'),
      rankings: permissions.contains('rankings:read'),
      saves: permissions.contains('saves:write'),
      notifications: permissions.contains('notifications:read'),
      promotionReview:
          role == 'admin' && permissions.contains('promotions:review'),
      bufferManage: role == 'admin' && permissions.contains('social:manage'),
      openaiConfigured: services['openai'] == true,
      bufferConfigured: services['social_media'] == true,
    );
  }

  void requireEnabled() {
    if (!enabled) {
      throw ApiFailure(
        'This feature is not available yet. Your content is still saved.',
      );
    }
  }

  Future<Json> improve({
    required String title,
    required String content,
    required String instruction,
  }) async {
    requireEnabled();
    if (!(await capabilities()).ai) {
      throw ApiFailure(
        'AI writing assistance is not available for this account.',
      );
    }
    final response = await api.request(
      '/ai/writing-assist',
      token: session.token,
      body: {
        'title': title,
        'content': content,
        'instruction': instruction,
        'format': 'plain_text',
      },
    );
    final data = response['data'];
    if (data is! Json ||
        data['title'] is! String ||
        data['content'] is! String ||
        (data['title'] as String).length > 100 ||
        (data['content'] as String).length > 100000) {
      throw ApiFailure('The writing suggestion has an invalid format.');
    }
    return data;
  }

  Future<List<Json>> rankings(String metric, int days) async {
    requireEnabled();
    if (!['comments', 'saves'].contains(metric)) {
      throw ArgumentError.value(metric);
    }
    if (![7, 30, 90].contains(days)) throw ArgumentError.value(days);
    final response = await api.request('/rankings?metric=$metric&days=$days');
    final rows = List<Json>.from(response['data'] as List);
    if (rows.any(
      (row) =>
          row['count'] is! int ||
          (row['count'] as int) < 0 ||
          row['article'] is! Json ||
          row['article']['id'] is! int ||
          row['article']['title'] is! String,
    )) {
      throw ApiFailure('The statistics received are not valid.');
    }
    return rows;
  }

  Future<List<Json>> drafts() async {
    requireEnabled();
    if (!(await capabilities()).review) {
      throw ApiFailure('Only authorized administrators can review drafts.');
    }
    final result = <Json>[];
    String? cursor;
    final cursors = <String>{};
    for (int page = 0; page < 100; page++) {
      final query = cursor == null
          ? ''
          : '&cursor=${Uri.encodeQueryComponent(cursor)}';
      final response = await api.request(
        '/admin/drafts?limit=100$query',
        token: session.token,
      );
      result.addAll(List<Json>.from(response['data'] as List));
      cursor = response['next_cursor'] as String?;
      if (cursor == null) {
        final ids = result.map((d) => d['id']).toSet();
        if (ids.length != result.length) {
          throw ApiFailure(
            'The list changed while loading. Refresh before making changes.',
          );
        }
        return result;
      }
      if (!cursors.add(cursor)) break;
    }
    throw ApiFailure(
      'Could not load the complete list. Actions on all items are unavailable.',
    );
  }

  Future<Json> statistics(int days) async {
    requireEnabled();
    if (!(await capabilities()).analytics) {
      throw ApiFailure('You do not have access to admin statistics.');
    }
    final response = await api.request(
      '/admin/statistics?days=$days',
      token: session.token,
    );
    return response['data'] as Json;
  }

  Future<Json> bulk(String operation, String action, List<Json> drafts) async {
    requireEnabled();
    final owner = session.userId;
    final token = session.token;
    if (!(await capabilities()).review || session.userId != owner) {
      throw ApiFailure('You do not have permission to manage these articles.');
    }
    if (!['publish', 'delete'].contains(action)) {
      throw ArgumentError.value(action);
    }
    return api.request(
      '/admin/drafts/bulk',
      token: token,
      body: {
        'operation_id': operation,
        'action': action,
        'items': drafts
            .map((d) => {'id': d['id'], 'version': d['version']})
            .toList(),
      },
    );
  }

  Future<void> syncFavorites(LocalStore store) async {
    if (!enabled || session.expired) return;
    if (!(await capabilities()).saves) return;
    final owner = session.userId!;
    for (final item in await store.pendingFavorites(owner)) {
      if (session.userId != owner) return;
      await api.request(
        '/posts/${item['id']}/saved',
        token: session.token,
        body: {'saved': item['saved'] == 1, 'mutation_id': item['revision']},
      );
      await store.acknowledgeFavorite(
        owner,
        item['id'] as int,
        item['revision'] as String,
      );
    }
  }

  Future<List<Json>> managementList(String resource) async {
    requireEnabled();
    if (!['users', 'posts', 'roles', 'contacts'].contains(resource)) {
      throw ArgumentError.value(resource);
    }
    final owner = session.userId;
    final token = session.token;
    final access = await capabilities();
    if (access.role != 'admin' || owner != session.userId) {
      throw ApiFailure('Administrator access is required.');
    }
    final items = <Json>[];
    String? cursor;
    final seen = <String>{};
    do {
      final response = await api.request(
        '/admin/$resource?limit=100${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
        token: token,
      );
      if (owner != session.userId) {
        throw ApiFailure('The account changed. Refresh the list.');
      }
      items.addAll(List<Json>.from(response['data'] as List));
      cursor = response['next_cursor'] as String?;
      if (cursor != null && (!seen.add(cursor) || seen.length >= 100)) {
        throw ApiFailure('Could not load the complete list.');
      }
    } while (cursor != null);
    return items;
  }

  /// The server returns only Stripe-confirmed payments awaiting editorial review.
  Future<List<Json>> pendingPromotions() async {
    requireEnabled();
    final owner = session.userId;
    final token = session.token;
    if (!(await capabilities()).promotionReview || owner != session.userId) {
      throw ApiFailure('Administrator access is required.');
    }
    final items = <Json>[];
    String? cursor;
    final seen = <String>{};
    do {
      final response = await api.request(
        '/admin/promotions?status=pending&limit=100${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
        token: token,
      );
      if (owner != session.userId) {
        throw ApiFailure('The account changed. Refresh the list.');
      }
      final page = List<Json>.from(response['data'] as List);
      if (page.any(
        (item) =>
            item['id'] is! int ||
            item['version'] is! int ||
            item['status'] != 'pending' ||
            item['payment_status'] != 'paid' ||
            item['article'] is! Json ||
            item['article']['id'] is! int ||
            item['article']['title'] is! String ||
            item['user'] is! Json ||
            item['user']['id'] is! int ||
            item['user']['username'] is! String,
      )) {
        throw ApiFailure('The promotion review list has an invalid format.');
      }
      items.addAll(page);
      cursor = response['next_cursor'] as String?;
      if (cursor != null && (!seen.add(cursor) || seen.length >= 100)) {
        throw ApiFailure('Could not load the complete promotion review list.');
      }
    } while (cursor != null);
    if (items.map((item) => item['id']).toSet().length != items.length) {
      throw ApiFailure('The promotion list changed. Refresh before deciding.');
    }
    return items;
  }

  Future<Json> decidePromotion(
    Json promotion, {
    required String decision,
    String? reason,
  }) async {
    requireEnabled();
    if (!['approve', 'reject'].contains(decision)) {
      throw ArgumentError.value(decision);
    }
    if (decision == 'reject' && (reason == null || reason.trim().isEmpty)) {
      throw ArgumentError.value(reason);
    }
    final owner = session.userId;
    final token = session.token;
    if (!(await capabilities()).promotionReview || owner != session.userId) {
      throw ApiFailure('Administrator access is required.');
    }
    if (promotion['status'] != 'pending' ||
        promotion['payment_status'] != 'paid' ||
        promotion['id'] is! int ||
        promotion['version'] is! int) {
      throw ApiFailure(
        'Only confirmed payments awaiting review can be decided.',
      );
    }
    return api.request(
      '/admin/promotions/${promotion['id']}/decision',
      token: token,
      body: {
        'decision': decision,
        'version': promotion['version'],
        'operation_id': operationId(),
        if (reason != null) 'reason': reason.trim(),
      },
    );
  }

  Future<Json> operation(String id) {
    requireEnabled();
    return api.request(
      '/admin/operations/${Uri.encodeComponent(id)}',
      token: session.token,
    );
  }

  Future<Json> integrations() async {
    requireEnabled();
    if ((await capabilities()).role != 'admin') {
      throw ApiFailure('Administrator access is required.');
    }
    final response = await api.request(
      '/admin/integrations',
      token: session.token,
    );
    return response['data'] as Json;
  }

  Future<List<Json>> bufferChannels() async {
    requireEnabled();
    if (!(await capabilities()).bufferManage) {
      throw ApiFailure('Social media administration is unavailable.');
    }
    final response = await api.request(
      '/admin/social/channels',
      token: session.token,
    );
    return List<Json>.from(response['data'] as List);
  }

  Future<Json> shareWithBuffer(Json post, {bool retryFailed = false}) {
    requireEnabled();
    return api.request(
      '/admin/social/posts/${post['id']}/share',
      token: session.token,
      body: {
        'operation_id': operationId(),
        'version': post['version'],
        'retry_failed': retryFailed,
      },
    );
  }
}

/// Persist the operation ID before a bulk write. A lost response is reconciled
/// using its receipt, never by automatically issuing another destructive batch.
class AdminOperations {
  AdminOperations(this.gateway, this.store);
  final EditorialGateway gateway;
  final LocalStore store;
  bool busy = false;
  String get key => 'admin_operation_${gateway.session.userId}';
  Future<Json?> pending() async {
    final result = await store.cached(key);
    return result?['status'] == 'pending' ? result : null;
  }

  Future<Json> run(String action, List<Json> items) async {
    if (busy) throw ApiFailure('An operation is already in progress.');
    if (items.isEmpty) throw ApiFailure('Select at least one article.');
    busy = true;
    final operationKey = key;
    try {
      if (await pending() != null) {
        throw ApiFailure('Check the previous operation before continuing.');
      }
      final id = operationId();
      if (operationKey != key) {
        throw ApiFailure('The account changed. Review the drafts again.');
      }
      await store.cache(operationKey, {
        'operation_id': id,
        'status': 'pending',
        'action': action,
        'count': items.length,
        'ids': items.map((d) => d['id']).toList(),
      });
      try {
        final result = await gateway.bulk(id, action, items);
        await _record(result, id, operationKey);
        return result;
      } on ApiFailure catch (e) {
        if (!e.uncertain && e.status != 409) {
          await store.cache(operationKey, {
            'operation_id': id,
            'status': 'rejected',
          });
        }
        rethrow;
      }
    } finally {
      busy = false;
    }
  }

  Future<Json> reconcile() async {
    final operationKey = key;
    final saved = await pending();
    if (saved == null) throw ApiFailure('There is no pending operation.');
    final id = saved['operation_id'] as String;
    if (key != operationKey) {
      throw ApiFailure('The account changed. Refresh the list.');
    }
    final result = await gateway.operation(id);
    await _record(result, id, operationKey);
    return result;
  }

  Future<void> _record(Json result, String id, String operationKey) async {
    final saved = await store.cached(operationKey);
    final expected = (saved?['ids'] as List?)?.toSet();
    final results = result['results'];
    final validItems =
        results is List &&
        results.every(
          (r) => r is Json && r['id'] is int && r['success'] is bool,
        );
    final received = validItems
        ? results.map((r) => r['id']).toSet()
        : <dynamic>{};
    if (result['operation_id'] != id ||
        result['status'] != 'completed' ||
        !validItems ||
        (expected != null &&
            (received.length != results.length ||
                received.length != expected.length ||
                !received.containsAll(expected)))) {
      throw ApiFailure(
        'This operation is still unconfirmed. Check its result before trying again.',
        uncertain: true,
      );
    }
    await store.cache(operationKey, {...result, 'status': 'completed'});
  }
}

/// A durable receipt prevents repeating account changes and contact replies.
class ManagementOperations {
  ManagementOperations(this.gateway, this.store);
  final EditorialGateway gateway;
  final LocalStore store;
  String get key => 'management_operation_${gateway.session.userId}';
  Future<Json?> pending() async {
    final saved = await store.cached(key);
    return saved?['status'] == 'pending' ? saved : null;
  }

  Future<void> run(String resource, int id, Json changes) async {
    final operationKey = key;
    final token = gateway.session.token;
    if (await pending() != null) {
      throw ApiFailure(
        'Check the previous operation before making more changes.',
      );
    }
    final access = await gateway.capabilities();
    if (access.role != 'admin' || key != operationKey) {
      throw ApiFailure('Administrator access is required.');
    }
    final receipt = operationId();
    await store.cache(operationKey, {
      'status': 'pending',
      'operation_id': receipt,
    });
    try {
      final result = await gateway.api.request(
        '/admin/$resource/$id',
        token: token,
        body: {...changes, 'operation_id': receipt},
      );
      if (result['operation_id'] != receipt ||
          result['status'] != 'completed') {
        throw ApiFailure(
          'The server did not confirm this change. Check its result before trying again.',
          uncertain: true,
        );
      }
      await store.cache(operationKey, {'status': 'completed'});
    } on ApiFailure catch (e) {
      if (!e.uncertain && e.status != 409) {
        await store.cache(operationKey, {'status': 'rejected'});
      }
      rethrow;
    }
  }

  Future<void> reconcile() async {
    final operationKey = key;
    final saved = await pending();
    if (saved == null) return;
    try {
      final result = await gateway.operation(saved['operation_id'] as String);
      if (result['operation_id'] != saved['operation_id'] ||
          result['status'] != 'completed') {
        throw ApiFailure(
          'The server has not confirmed this operation yet. Do not repeat it.',
          uncertain: true,
        );
      }
      await store.cache(operationKey, {'status': 'completed'});
    } on ApiFailure catch (e) {
      if (e.status == 404) {
        // A missing receipt is not proof that a timed-out write will never commit.
        throw ApiFailure(
          'No receipt is available yet. Check with the server administrator before repeating this operation.',
        );
      }
      rethrow;
    }
  }
}
