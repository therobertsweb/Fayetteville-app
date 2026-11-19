import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;

class PodcastFailure implements Exception {
  const PodcastFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class PodcastEpisode {
  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.author,
    required this.audioUrl,
    required this.coverUrl,
    required this.createdAt,
    required this.likes,
    required this.dislikes,
    required this.commentCount,
    this.authorId,
    this.articleId,
    this.articleTitle,
  });
  final int id;
  final String title, author;
  final Uri audioUrl, coverUrl;
  final DateTime createdAt;
  final int likes, dislikes, commentCount;
  final int? authorId;
  final int? articleId;
  final String? articleTitle;

  factory PodcastEpisode.fromJson(Map<String, dynamic> data, Uri origin) {
    final article = data['article'];
    final audioPath = data['audio_url'];
    final coverPath = data['cover_url'];
    final audio = origin.resolve('$audioPath');
    final cover = origin.resolve('$coverPath');
    if (data['id'] is! int ||
        data['title'] is! String ||
        (data['title'] as String).trim().isEmpty ||
        data['author'] is! String ||
        (data['author_id'] != null && data['author_id'] is! int) ||
        data['likes'] is! int ||
        data['likes'] < 0 ||
        data['dislikes'] is! int ||
        data['dislikes'] < 0 ||
        data['comment_count'] is! int ||
        data['comment_count'] < 0 ||
        DateTime.tryParse('${data['created_at']}') == null ||
        audioPath is! String ||
        audioPath.isEmpty ||
        !_validHttpsAudio(audio) ||
        coverPath is! String ||
        coverPath.isEmpty ||
        !_validHttpsAudio(cover) ||
        (article != null &&
            (article is! Map<String, dynamic> ||
                article['id'] is! int ||
                article['title'] is! String))) {
      throw const PodcastFailure('The podcast service returned invalid data.');
    }
    return PodcastEpisode(
      id: data['id'] as int,
      title: data['title'] as String,
      author: data['author'] as String,
      authorId: data['author_id'] as int?,
      audioUrl: audio,
      coverUrl: cover,
      createdAt: DateTime.parse(data['created_at'] as String),
      likes: data['likes'] as int,
      dislikes: data['dislikes'] as int,
      commentCount: data['comment_count'] as int,
      articleId: article == null ? null : article['id'] as int,
      articleTitle: article == null ? null : article['title'] as String,
    );
  }
}

bool _validHttpsAudio(Uri value) =>
    value.scheme == 'https' && value.host.isNotEmpty && value.userInfo.isEmpty;

class PodcastPage {
  const PodcastPage(this.episodes, this.nextPage);
  final List<PodcastEpisode> episodes;
  final int? nextPage;
}

class PodcastReaction {
  const PodcastReaction(this.likes, this.dislikes, this.mine);
  final int likes, dislikes;
  final String? mine;

  factory PodcastReaction.fromJson(Map<String, dynamic> value) {
    final mine = value['my_reaction'];
    if (value['likes'] is! int ||
        value['dislikes'] is! int ||
        (mine != null && mine != 'like' && mine != 'dislike')) {
      throw const PodcastFailure('The podcast service returned invalid data.');
    }
    return PodcastReaction(
      value['likes'] as int,
      value['dislikes'] as int,
      mine as String?,
    );
  }
}

class PodcastComment {
  const PodcastComment(
    this.id,
    this.author,
    this.body,
    this.createdAt, {
    this.authorId,
  });
  final int id;
  final int? authorId;
  final String author, body;
  final DateTime createdAt;

  factory PodcastComment.fromJson(Map<String, dynamic> value) {
    if (value['id'] is! int ||
        value['author'] is! String ||
        (value['author_id'] != null && value['author_id'] is! int) ||
        value['body'] is! String ||
        DateTime.tryParse('${value['created_at']}') == null) {
      throw const PodcastFailure('The podcast service returned invalid data.');
    }
    return PodcastComment(
      value['id'] as int,
      value['author'] as String,
      value['body'] as String,
      DateTime.parse(value['created_at'] as String),
      authorId: value['author_id'] as int?,
    );
  }
}

class PodcastCommentsPage {
  const PodcastCommentsPage(this.comments, this.nextPage);
  final List<PodcastComment> comments;
  final int? nextPage;
}

/// Separate podcast service. It never writes to the news website or its API.
class PodcastApi {
  PodcastApi({Uri? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _configuredBaseUrl,
      client = client ?? http.Client();

  static final Uri? _configuredBaseUrl = Uri.tryParse(
    const String.fromEnvironment(
      'PODCAST_API_BASE_URL',
      defaultValue: 'https://podcasts.fayettevillethepeoplevoice.com',
    ),
  );
  final Uri? baseUrl;
  final http.Client client;

  bool get configured =>
      baseUrl != null &&
      baseUrl!.scheme == 'https' &&
      baseUrl!.host.isNotEmpty &&
      baseUrl!.userInfo.isEmpty;

  Uri _uri(String path) {
    if (!configured) {
      throw const PodcastFailure(
        'Podcasts are not connected to a service yet.',
      );
    }
    return baseUrl!.resolve(path);
  }

  Future<PodcastPage> list({int page = 1}) async {
    if (page < 1) throw ArgumentError.value(page);
    try {
      final response = await client
          .get(_uri('/episodes?page=$page'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const PodcastFailure('Could not load podcasts. Try again.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = body['data'];
      if (rows is! List ||
          (body['next_page'] != null && body['next_page'] is! int)) {
        throw const PodcastFailure(
          'The podcast service returned invalid data.',
        );
      }
      return PodcastPage(
        rows
            .map(
              (item) => PodcastEpisode.fromJson(
                item as Map<String, dynamic>,
                baseUrl!,
              ),
            )
            .toList(),
        body['next_page'] as int?,
      );
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not load podcasts. Try again.');
    }
  }

  Future<void> deleteEpisode(int episodeId, String token) async {
    if (episodeId < 1 || token.isEmpty) {
      throw const PodcastFailure(
        'Sign in as an administrator to delete a podcast.',
      );
    }
    try {
      final response = await client
          .delete(
            _uri('/episodes/$episodeId'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 204) return;
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const PodcastFailure('Administrator access is required.');
      }
      if (response.statusCode == 404) {
        throw const PodcastFailure('This podcast is no longer available.');
      }
      throw const PodcastFailure('Could not delete this podcast. Try again.');
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not delete this podcast. Try again.');
    }
  }

  Future<PodcastReaction> reaction(int episodeId, String token) async {
    try {
      final response = await client
          .get(
            _uri('/episodes/$episodeId/reaction'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const PodcastFailure('Could not load your reaction.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PodcastReaction.fromJson(body['data'] as Map<String, dynamic>);
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not load your reaction.');
    }
  }

  Future<PodcastReaction> setReaction(
    int episodeId,
    String token,
    String value,
  ) async {
    if (!['like', 'dislike', 'none'].contains(value)) {
      throw ArgumentError.value(value);
    }
    try {
      final response = await client
          .put(
            _uri('/episodes/$episodeId/reaction'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'value': value}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw PodcastFailure(
          _serverMessage(response.body) ?? 'Could not save your reaction.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PodcastReaction.fromJson(body['data'] as Map<String, dynamic>);
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not save your reaction.');
    }
  }

  Future<PodcastCommentsPage> comments(int episodeId, {int page = 1}) async {
    if (page < 1) throw ArgumentError.value(page);
    try {
      final response = await client
          .get(_uri('/episodes/$episodeId/comments?page=$page'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const PodcastFailure('Could not load comments.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = body['data'];
      if (rows is! List ||
          (body['next_page'] != null && body['next_page'] is! int)) {
        throw const PodcastFailure(
          'The podcast service returned invalid data.',
        );
      }
      return PodcastCommentsPage(
        rows
            .map((row) => PodcastComment.fromJson(row as Map<String, dynamic>))
            .toList(),
        body['next_page'] as int?,
      );
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not load comments.');
    }
  }

  Future<PodcastComment> addComment(
    int episodeId,
    String token,
    String comment,
  ) async {
    final clean = comment.trim();
    if (clean.isEmpty || clean.length > 1000) {
      throw const PodcastFailure('Write a comment up to 1000 characters.');
    }
    try {
      final response = await client
          .post(
            _uri('/episodes/$episodeId/comments'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'body': clean}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 201) {
        throw PodcastFailure(
          _serverMessage(response.body) ?? 'Could not publish your comment.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PodcastComment.fromJson(body['data'] as Map<String, dynamic>);
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not publish your comment.');
    }
  }

  Future<PodcastEpisode> upload({
    required String title,
    required XFile audio,
    XFile? cover,
    required String token,
    int? articleId,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw const PodcastFailure('Enter a title up to 120 characters.');
    }
    if (!audio.name.toLowerCase().endsWith('.mp3') ||
        await audio.length() == 0 ||
        await audio.length() > 85 * 1024 * 1024) {
      throw const PodcastFailure('Choose an MP3 smaller than 85 MB.');
    }
    if (cover != null &&
        (!RegExp(
              r'\.(jpg|jpeg|png|webp)$',
              caseSensitive: false,
            ).hasMatch(cover.name) ||
            await cover.length() == 0 ||
            await cover.length() > 5 * 1024 * 1024)) {
      throw const PodcastFailure('Choose a JPG, PNG or WebP cover under 5 MB.');
    }
    try {
      final request = http.MultipartRequest('POST', _uri('/episodes'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['title'] = cleanTitle;
      if (articleId != null) request.fields['article_id'] = '$articleId';
      request.files.add(
        http.MultipartFile(
          'audio',
          audio.openRead(),
          await audio.length(),
          filename: audio.name,
        ),
      );
      if (cover != null) {
        request.files.add(
          http.MultipartFile(
            'cover',
            cover.openRead(),
            await cover.length(),
            filename: cover.name,
          ),
        );
      }
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(minutes: 3));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const PodcastFailure('Sign in again to upload a podcast.');
      }
      if (response.statusCode != 201) {
        final message = _serverMessage(response.body);
        throw PodcastFailure(
          message ?? 'Could not upload the podcast. Try again.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PodcastEpisode.fromJson(
        body['data'] as Map<String, dynamic>,
        baseUrl!,
      );
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not upload the podcast. Try again.');
    }
  }

  Future<PodcastEpisode> createLink({
    required String title,
    required String audioUrl,
    XFile? cover,
    required String token,
    int? articleId,
  }) async {
    final cleanTitle = title.trim();
    final uri = Uri.tryParse(audioUrl.trim());
    if (cleanTitle.isEmpty || cleanTitle.length > 120) {
      throw const PodcastFailure('Enter a title up to 120 characters.');
    }
    if (uri == null ||
        !_validHttpsAudio(uri) ||
        RegExp(
          r'(^|\.)((youtube\.com)|(youtu\.be)|(youtube-nocookie\.com))$',
          caseSensitive: false,
        ).hasMatch(uri.host) ||
        !uri.path.toLowerCase().endsWith('.mp3')) {
      throw const PodcastFailure('Enter a direct HTTPS link to an MP3 file.');
    }
    if (cover != null &&
        (!RegExp(
              r'\.(jpg|jpeg|png|webp)$',
              caseSensitive: false,
            ).hasMatch(cover.name) ||
            await cover.length() == 0 ||
            await cover.length() > 5 * 1024 * 1024)) {
      throw const PodcastFailure('Choose a JPG, PNG or WebP cover under 5 MB.');
    }
    try {
      final request = http.MultipartRequest('POST', _uri('/episodes/links'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['title'] = cleanTitle
        ..fields['audio_url'] = uri.toString();
      if (articleId != null) request.fields['article_id'] = '$articleId';
      if (cover != null) {
        request.files.add(
          http.MultipartFile(
            'cover',
            cover.openRead(),
            await cover.length(),
            filename: cover.name,
          ),
        );
      }
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(minutes: 1));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const PodcastFailure('Sign in again to publish a podcast.');
      }
      if (response.statusCode != 201) {
        throw PodcastFailure(
          _serverMessage(response.body) ??
              'Could not publish the podcast. Try again.',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PodcastEpisode.fromJson(
        body['data'] as Map<String, dynamic>,
        baseUrl!,
      );
    } on PodcastFailure {
      rethrow;
    } catch (_) {
      throw const PodcastFailure('Could not publish the podcast. Try again.');
    }
  }

  String? _serverMessage(String body) {
    try {
      final value = jsonDecode(body);
      final message = value is Map ? (value['error'] ?? value['detail']) : null;
      return message is String && message.length <= 180 ? message : null;
    } catch (_) {
      return null;
    }
  }
}
