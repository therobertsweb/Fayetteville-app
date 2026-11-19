import 'api.dart';
import 'local_store.dart';
import 'article_media.dart';

import 'package:html/parser.dart' as html;

/// Persist each stage before/after network writes. Publication can be retried
/// with its known server ID; ambiguous creation cannot safely be repeated.
class Publisher {
  Publisher(this.api, this.store);
  final Api api;
  final LocalStore store;
  final Set<String> _busy = {};

  Future<void> publish(
    String localId, {
    required int userId,
    required String token,
    bool publishNow = true,
  }) async {
    if (!_busy.add(localId)) {
      throw ApiFailure('This draft is already being sent.');
    }
    try {
      final draft = await store.draft(localId);
      if (draft == null) throw ApiFailure('Draft not found.');
      if (draft['owner_id'] != null && draft['owner_id'] != userId) {
        throw ApiFailure('This draft belongs to another account.');
      }
      if (draft['state'] == 'published') return;
      if (draft['state'] == 'creating' || draft['state'] == 'uncertain') {
        throw ApiFailure(
          'The previous submission could not be confirmed. Link the server draft ID before continuing.',
        );
      }
      validate(draft);
      draft['owner_id'] = userId;
      if (draft['remote_id'] == null) {
        final publication = await prepareMedia(draft, token);
        validate(publication);
        draft['state'] = 'creating';
        await store.saveDraft(draft);
        Json result;
        try {
          result = await api.request(
            '/posts',
            token: token,
            body: {
              for (final key in [
                'url',
                'title',
                'content',
                'info',
                'tag_1',
                'tag_2',
                'title_2',
                'title_3',
                'subtitle',
                'subtitle_2',
                'photo_link',
                'categories',
              ])
                key: publication[key],
            },
          );
        } on ApiFailure catch (e) {
          draft['state'] = e.uncertain || e.status == 409
              ? 'uncertain'
              : 'local';
          draft['error'] = e.message;
          await store.saveDraft(draft);
          rethrow;
        }
        final id = result['data']?['id'];
        if (id is! int) {
          draft['state'] = 'uncertain';
          await store.saveDraft(draft);
          throw ApiFailure(
            'The server did not confirm the ID. Your local draft is still saved.',
          );
        }
        draft['remote_id'] = id;
        draft['state'] = 'remote';
        await store.saveDraft(draft);
      }
      if (!publishNow) return;
      // API publishes idempotently; keep the same remote ID after a lost response.
      await api.request(
        '/posts/${draft['remote_id']}/publish',
        body: {},
        token: token,
      );
      draft['state'] = 'published';
      draft.remove('error');
      await store.saveDraft(draft);
    } finally {
      _busy.remove(localId);
    }
  }

  /// Upload only referenced local images, recording successes for safe retries.
  Future<Json> prepareMedia(
    Json draft,
    String token, {
    bool persist = true,
  }) async {
    final document = html.parseFragment(draft['content'] as String);
    final cover = draft['photo_link'] as String;
    final sources = <String>{
      cover,
      ...document.querySelectorAll('img').map((e) => e.attributes['src'] ?? ''),
    }.where((s) => s.startsWith(localImagePrefix));
    final uploaded = Map<String, dynamic>.from(
      draft['uploaded_images'] as Map? ?? {},
    );
    for (final source in sources) {
      if (uploaded[source] != null) continue;
      final bytes = await store.image(source);
      if (bytes == null) {
        throw ApiFailure(
          'A local image is missing. Select it again before publishing.',
        );
      }
      uploaded[source] = await api.uploadImage(
        bytes,
        source.split('/').last,
        token,
      );
      draft['uploaded_images'] = uploaded;
      if (persist) await store.saveDraft(draft);
    }
    for (final image in document.querySelectorAll('img')) {
      final remote = uploaded[image.attributes['src']];
      if (remote is String) image.attributes['src'] = remote;
    }
    return {
      ...draft,
      'content': document.outerHtml,
      'photo_link': uploaded[cover] ?? cover,
    };
  }

  Future<void> recover(
    String localId,
    int remoteId, {
    required int userId,
    required String token,
  }) async {
    final draft = await store.draft(localId);
    if (draft == null ||
        draft['owner_id'] != userId ||
        !['creating', 'uncertain'].contains(draft['state'])) {
      throw ApiFailure('This draft cannot be linked.');
    }
    final result = await api.request('/posts/$remoteId', token: token);
    final remote = result['data'];
    if (remote is! Json ||
        remote['author']?['id'] != userId ||
        remote['url'] != draft['url'] ||
        remote['title'] != draft['title']) {
      throw ApiFailure('The article does not match this draft and account.');
    }
    draft['remote_id'] = remoteId;
    draft['state'] = remote['published'] == true ? 'published' : 'remote';
    await store.saveDraft(draft);
  }

  static void validate(Json draft) {
    for (final key in [
      'url',
      'title',
      'content',
      'photo_link',
      'info',
      'tag_2',
      'title_2',
      'title_3',
      'subtitle_2',
    ]) {
      if ((draft[key] as String? ?? '').trim().isEmpty) {
        throw ApiFailure(
          'Complete every required template field before publishing.',
        );
      }
    }
    const limits = {
      'url': 100,
      'title': 100,
      'content': 100000,
      'info': 2000,
      'tag_1': 200,
      'tag_2': 200,
      'title_2': 1000,
      'title_3': 1000,
      'subtitle': 2000,
      'subtitle_2': 2000,
      'photo_link': 2000,
      'categories': 500,
    };
    for (final entry in limits.entries) {
      if ((draft[entry.key] as String? ?? '').length > entry.value) {
        throw ApiFailure('A field exceeds the size allowed by the server.');
      }
    }
    final slug = draft['url'] as String;
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
      throw ApiFailure(
        'Use lowercase letters, numbers and hyphens for the article URL.',
      );
    }
    final photo = draft['photo_link'] as String;
    final uri = Uri.tryParse(photo);
    final valid =
        uri != null &&
        ((uri.scheme == 'https' &&
                uri.host.isNotEmpty &&
                uri.userInfo.isEmpty) ||
            ((photo.startsWith('/static/') ||
                    photo.startsWith(localImagePrefix)) &&
                !uri.hasAuthority));
    if (!valid || RegExp(r'[\\<>\r\n\t]').hasMatch(photo)) {
      throw ApiFailure(
        'Use an HTTPS image URL or a /static/ path on the website.',
      );
    }
  }
}
