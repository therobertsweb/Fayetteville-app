import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../data/api.dart';
import '../data/local_store.dart';
import '../data/podcasts.dart';
import '../data/repository.dart';
import 'home.dart' show Notice, message;
import 'reader.dart';

class PodcastsPage extends StatefulWidget {
  const PodcastsPage({
    super.key,
    required this.api,
    required this.repository,
    this.onSignIn,
  });
  final PodcastApi api;
  final Repository repository;
  final VoidCallback? onSignIn;

  @override
  State<PodcastsPage> createState() => _PodcastsPageState();
}

class _PodcastsPageState extends State<PodcastsPage> {
  final player = AudioPlayer();
  final episodes = <PodcastEpisode>[];
  int? nextPage = 1;
  int? playingId;
  int? deletingId;
  bool busy = false, opening = false;
  bool admin = false;
  String? checkedToken;
  int adminGeneration = 0;
  String? error;
  final resolvingAuthorArticles = <int>{};

  String authorName(PodcastEpisode episode) {
    final known = widget.repository.authorName(episode.authorId);
    if (known != null) return known;
    final name = episode.author.trim();
    if (name.isEmpty || RegExp(r'^User \d+$').hasMatch(name)) {
      return 'Community member';
    }
    return name;
  }

  @override
  void initState() {
    super.initState();
    widget.repository.session?.addListener(accountChanged);
    accountChanged();
    if (widget.api.configured) {
      load();
    } else {
      nextPage = null;
    }
  }

  @override
  void dispose() {
    widget.repository.session?.removeListener(accountChanged);
    unawaited(player.dispose());
    super.dispose();
  }

  void accountChanged() {
    final session = widget.repository.session;
    final token = session != null && !session.expired ? session.token : null;
    if (token == checkedToken) return;
    checkedToken = token;
    final generation = ++adminGeneration;
    if (admin && mounted) setState(() => admin = false);
    if (token == null) return;
    unawaited(checkAdmin(token, session!.userId!, generation));
  }

  Future<void> checkAdmin(String token, int owner, int generation) async {
    try {
      final response = await widget.repository.api.request(
        '/mobile/capabilities',
        token: token,
      );
      if (mounted &&
          generation == adminGeneration &&
          widget.repository.session?.userId == owner) {
        setState(
          () => admin =
              response['data']?['user_id'] == owner &&
              response['data']?['role'] == 'admin',
        );
      }
    } catch (_) {
      if (mounted && generation == adminGeneration) {
        setState(() => admin = false);
      }
    }
  }

  Future<void> deleteEpisode(PodcastEpisode episode) async {
    final session = widget.repository.session;
    if (!admin || deletingId != null || session == null || session.expired) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete podcast?'),
        content: Text(
          '“${episode.title}” and its comments and reactions will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || session.expired) return;
    setState(() => deletingId = episode.id);
    try {
      await widget.api.deleteEpisode(episode.id, session.token);
      if (playingId == episode.id) {
        await player.stop();
      }
      if (!mounted) return;
      setState(() {
        episodes.removeWhere((item) => item.id == episode.id);
        if (playingId == episode.id) playingId = null;
      });
      message(context, 'Podcast deleted.');
    } catch (error) {
      if (mounted) message(context, error);
    } finally {
      if (mounted) setState(() => deletingId = null);
    }
  }

  Future<void> load({bool refresh = false}) async {
    if (busy || (!refresh && nextPage == null)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.list(page: refresh ? 1 : nextPage!);
      if (!mounted) return;
      setState(() {
        if (refresh) episodes.clear();
        final existing = episodes.map((e) => e.id).toSet();
        episodes.addAll(result.episodes.where((e) => existing.add(e.id)));
        nextPage = result.nextPage;
      });
      unawaited(resolveArticleAuthors(result.episodes));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resolveArticleAuthors(List<PodcastEpisode> loaded) async {
    for (final episode in loaded) {
      final articleId = episode.articleId;
      final authorId = episode.authorId;
      final suppliedName = episode.author.trim();
      if (articleId == null ||
          authorId == null ||
          widget.repository.authorName(authorId) != null ||
          (suppliedName.isNotEmpty &&
              suppliedName != 'Community member' &&
              !RegExp(r'^User \d+$').hasMatch(suppliedName)) ||
          !resolvingAuthorArticles.add(articleId)) {
        continue;
      }
      try {
        final response = await widget.repository.api.request(
          '/posts/$articleId',
        );
        final article = response['data'];
        if (article is Json &&
            article['id'] == articleId &&
            article['author']?['id'] == authorId) {
          widget.repository.rememberAuthor(article);
          if (mounted) setState(() {});
        }
      } catch (_) {
        // The episode remains playable if its related article is unavailable.
      } finally {
        resolvingAuthorArticles.remove(articleId);
      }
    }
  }

  Future<void> toggle(PodcastEpisode episode) async {
    if (opening) return;
    try {
      if (playingId == episode.id) {
        if (player.playing) {
          await player.pause();
        } else {
          unawaited(player.play());
        }
        return;
      }
      setState(() => opening = true);
      final audioSession = await AudioSession.instance;
      await audioSession.configure(const AudioSessionConfiguration.speech());
      await player.stop();
      await player.setAudioSource(
        AudioSource.uri(
          episode.audioUrl,
          tag: MediaItem(
            id: 'podcast-${episode.id}',
            album: 'The People Voice Podcasts',
            title: episode.title,
            artist: authorName(episode),
            artUri: episode.coverUrl,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => playingId = episode.id);
      unawaited(player.play());
    } catch (_) {
      if (mounted) message(context, 'Could not play this podcast. Try again.');
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> upload() async {
    final session = widget.repository.session;
    if (session == null || session.expired) {
      widget.onSignIn?.call();
      message(context, 'Sign in to publish a podcast.');
      return;
    }
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PodcastUploadPage(api: widget.api, repository: widget.repository),
      ),
    );
    if (created == true) await load(refresh: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: RefreshIndicator(
      onRefresh: () => load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text('Podcasts', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          const Text(
            'Listen to community voices and explore the stories behind each episode.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.api.configured ? upload : null,
            icon: const Icon(Icons.mic_outlined),
            label: const Text('Publish a podcast'),
          ),
          if (!widget.api.configured)
            const Notice('The podcast service is not connected yet.'),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Notice(error!),
          if (episodes.isEmpty &&
              !busy &&
              error == null &&
              widget.api.configured)
            const Notice('No podcasts yet. Be the first to share an episode.'),
          for (final episode in episodes)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            episode.coverUrl.toString(),
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 84,
                              height: 84,
                              child: Icon(Icons.podcasts, size: 40),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                episode.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text('By ${authorName(episode)}'),
                              Text(
                                MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(episode.createdAt.toLocal()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, snapshot) => TextButton.icon(
                        onPressed: opening ? null : () => toggle(episode),
                        icon: Icon(
                          playingId == episode.id && player.playing
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        label: Text(
                          playingId == episode.id && player.playing
                              ? 'Pause podcast'
                              : 'Play podcast',
                        ),
                      ),
                    ),
                    if (playingId == episode.id)
                      StreamBuilder<Duration>(
                        stream: player.positionStream,
                        builder: (context, snapshot) => Text(
                          '${_clock(snapshot.data ?? Duration.zero)} / ${_clock(player.duration ?? Duration.zero)}',
                        ),
                      ),
                    if (episode.articleId != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ReaderPage(
                                repository: widget.repository,
                                id: episode.articleId!,
                                title:
                                    episode.articleTitle ?? 'Related article',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.article_outlined),
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Read the related article'),
                              Text(
                                episode.articleTitle ?? 'Open article',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    PodcastEngagement(
                      api: widget.api,
                      repository: widget.repository,
                      episode: episode,
                      onSignIn: widget.onSignIn,
                      onUpdated: () => load(refresh: true),
                    ),
                    if (admin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: deletingId == null
                              ? () => deleteEpisode(episode)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete podcast'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!busy && nextPage != null)
            OutlinedButton(onPressed: load, child: const Text('More podcasts')),
        ],
      ),
    ),
  );

  String _clock(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}

class PodcastEngagement extends StatefulWidget {
  const PodcastEngagement({
    super.key,
    required this.api,
    required this.repository,
    required this.episode,
    this.onSignIn,
    this.onUpdated,
  });
  final PodcastApi api;
  final Repository repository;
  final PodcastEpisode episode;
  final VoidCallback? onSignIn;
  final VoidCallback? onUpdated;

  @override
  State<PodcastEngagement> createState() => _PodcastEngagementState();
}

class _PodcastEngagementState extends State<PodcastEngagement> {
  late int likes = widget.episode.likes;
  late int dislikes = widget.episode.dislikes;
  late int comments = widget.episode.commentCount;
  String? mine;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    loadMine();
  }

  @override
  void didUpdateWidget(covariant PodcastEngagement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.id != widget.episode.id) {
      likes = widget.episode.likes;
      dislikes = widget.episode.dislikes;
      comments = widget.episode.commentCount;
      mine = null;
      loadMine();
    } else if (!identical(oldWidget.episode, widget.episode)) {
      likes = widget.episode.likes;
      dislikes = widget.episode.dislikes;
      comments = widget.episode.commentCount;
    }
  }

  Future<void> loadMine() async {
    final session = widget.repository.session;
    if (session == null || session.expired) return;
    final owner = session.userId;
    final episodeId = widget.episode.id;
    try {
      final reaction = await widget.api.reaction(episodeId, session.token);
      if (mounted &&
          owner == session.userId &&
          episodeId == widget.episode.id) {
        setState(() {
          likes = reaction.likes;
          dislikes = reaction.dislikes;
          mine = reaction.mine;
        });
      }
    } catch (_) {
      /* Public totals remain available. */
    }
  }

  Future<void> vote(String value) async {
    final session = widget.repository.session;
    if (session == null || session.expired) {
      widget.onSignIn?.call();
      message(context, 'Sign in to react to a podcast.');
      return;
    }
    if (busy) return;
    final owner = session.userId;
    final episodeId = widget.episode.id;
    setState(() => busy = true);
    try {
      final response = await widget.api.setReaction(
        episodeId,
        session.token,
        mine == value ? 'none' : value,
      );
      if (mounted &&
          owner == session.userId &&
          episodeId == widget.episode.id) {
        setState(() {
          likes = response.likes;
          dislikes = response.dislikes;
          mine = response.mine;
        });
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      TextButton.icon(
        onPressed: busy ? null : () => vote('like'),
        icon: Icon(mine == 'like' ? Icons.thumb_up : Icons.thumb_up_outlined),
        label: Text('$likes'),
      ),
      TextButton.icon(
        onPressed: busy ? null : () => vote('dislike'),
        icon: Icon(
          mine == 'dislike' ? Icons.thumb_down : Icons.thumb_down_outlined,
        ),
        label: Text('$dislikes'),
      ),
      TextButton.icon(
        onPressed: () async {
          final added = await Navigator.push<int>(
            context,
            MaterialPageRoute(
              builder: (_) => PodcastCommentsPageView(
                api: widget.api,
                repository: widget.repository,
                episode: widget.episode,
                onSignIn: widget.onSignIn,
              ),
            ),
          );
          if (!mounted) return;
          if (added != null) setState(() => comments += added);
          widget.onUpdated?.call();
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text('$comments comments'),
      ),
    ],
  );
}

class PodcastCommentsPageView extends StatefulWidget {
  const PodcastCommentsPageView({
    super.key,
    required this.api,
    required this.repository,
    required this.episode,
    this.onSignIn,
  });
  final PodcastApi api;
  final Repository repository;
  final PodcastEpisode episode;
  final VoidCallback? onSignIn;

  @override
  State<PodcastCommentsPageView> createState() =>
      _PodcastCommentsPageViewState();
}

class _PodcastCommentsPageViewState extends State<PodcastCommentsPageView> {
  final input = TextEditingController();
  final rows = <PodcastComment>[];
  int? nextPage = 1;
  int added = 0;
  bool busy = false, publishing = false;
  String? error;

  String authorName(PodcastComment comment) {
    final known = widget.repository.authorName(comment.authorId);
    if (known != null) return known;
    final name = comment.author.trim();
    if (name.isEmpty || RegExp(r'^User \d+$').hasMatch(name)) {
      return 'Community member';
    }
    return name;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (busy || nextPage == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await widget.api.comments(
        widget.episode.id,
        page: nextPage!,
      );
      if (!mounted) return;
      setState(() {
        rows.addAll(page.comments);
        nextPage = page.nextPage;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    final session = widget.repository.session;
    if (session == null || session.expired) {
      widget.onSignIn?.call();
      return;
    }
    if (publishing) return;
    setState(() {
      publishing = true;
      error = null;
    });
    try {
      final comment = await widget.api.addComment(
        widget.episode.id,
        session.token,
        input.text,
      );
      if (!mounted) return;
      setState(() {
        rows.insert(0, comment);
        added++;
        input.clear();
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => publishing = false);
    }
  }

  void signIn() {
    Navigator.pop(context, added);
    widget.onSignIn?.call();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Comments · ${widget.episode.title}'),
      leading: BackButton(onPressed: () => Navigator.pop(context, added)),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Notice(error!),
          if (rows.isEmpty && !busy && error == null)
            const Notice('No comments yet.'),
          for (final comment in rows)
            Card(
              child: ListTile(
                title: Text(authorName(comment)),
                subtitle: Text(comment.body),
                trailing: Text(
                  MaterialLocalizations.of(context)
                      .formatMediumDate(comment.createdAt.toLocal()),
                ),
              ),
            ),
          if (nextPage != null && !busy)
            OutlinedButton(onPressed: load, child: const Text('More comments')),
          const SizedBox(height: 16),
          if (widget.repository.session?.expired ?? true)
            OutlinedButton(
              onPressed: signIn,
              child: const Text('Sign in to comment'),
            )
          else ...[
            TextField(
              controller: input,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Your comment'),
              onChanged: (_) => setState(() {}),
            ),
            FilledButton(
              onPressed: publishing || input.text.trim().isEmpty
                  ? null
                  : publish,
              child: Text(publishing ? 'Publishing…' : 'Post comment'),
            ),
          ],
        ],
      ),
    ),
  );
}

class PodcastUploadPage extends StatefulWidget {
  const PodcastUploadPage({
    super.key,
    required this.api,
    required this.repository,
  });
  final PodcastApi api;
  final Repository repository;
  @override
  State<PodcastUploadPage> createState() => _PodcastUploadPageState();
}

class _PodcastUploadPageState extends State<PodcastUploadPage> {
  final title = TextEditingController();
  final audioLink = TextEditingController();
  XFile? audio, cover;
  int? articleId;
  String? articleImage;
  bool useLink = false;
  bool busy = false;
  String? error;
  late final Future<List<Json>> articles = _articles();

  @override
  void dispose() {
    title.dispose();
    audioLink.dispose();
    super.dispose();
  }

  Future<List<Json>> _articles() async {
    final session = widget.repository.session;
    if (session == null || session.expired) return [];
    final owner = session.userId;
    final token = session.token;
    final rows = <Json>[];
    String? cursor;
    final seen = <String>{};
    do {
      final response = await widget.repository.api.request(
        '/me/posts${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
        token: token,
      );
      if (owner != session.userId) return [];
      rows.addAll(
        List<Json>.from(response['data'] as List)
            .where((post) => post['published'] == true && post['id'] is int),
      );
      cursor = response['next_cursor'] as String?;
      if (cursor != null && (!seen.add(cursor) || seen.length >= 100)) {
        throw ApiFailure('Could not load the complete article list.');
      }
    } while (cursor != null);
    return rows;
  }

  Future<void> pickAudio() async {
    final selected = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'MP3 audio',
          extensions: ['mp3'],
          uniformTypeIdentifiers: ['public.mp3'],
        ),
      ],
    );
    if (selected != null && mounted) setState(() => audio = selected);
  }

  Future<void> pickCover() async {
    final selected = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Cover image',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          uniformTypeIdentifiers: [
            'public.jpeg',
            'public.png',
            'org.webmproject.webp',
          ],
        ),
      ],
    );
    if (selected != null && mounted) setState(() => cover = selected);
  }

  Future<void> publish() async {
    if (busy ||
        (cover == null && articleImage == null) ||
        (!useLink && audio == null)) {
      return;
    }
    final session = widget.repository.session;
    if (session == null || session.expired) {
      setState(() => error = 'Sign in to publish a podcast.');
      return;
    }
    final owner = session.userId;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (useLink) {
        await widget.api.createLink(
          title: title.text,
          audioUrl: audioLink.text,
          cover: articleImage == null ? cover : null,
          token: session.token,
          articleId: articleId,
        );
      } else {
        await widget.api.upload(
          title: title.text,
          audio: audio!,
          cover: articleImage == null ? cover : null,
          token: session.token,
          articleId: articleId,
        );
      }
      if (mounted && owner == session.userId) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Publish a podcast')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'New podcast episode',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Episode title'),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Upload MP3')),
              ButtonSegment(value: true, label: Text('MP3 link')),
            ],
            selected: {useLink},
            onSelectionChanged: busy
                ? null
                : (value) => setState(() => useLink = value.first),
          ),
          if (useLink) ...[
            const SizedBox(height: 12),
            TextField(
              controller: audioLink,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Direct HTTPS link to an MP3',
                helperText: 'YouTube links cannot play as audio-only here.',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: busy ? null : pickAudio,
              icon: const Icon(Icons.audio_file_outlined),
              label: Text(audio?.name ?? 'Choose MP3 (up to 85 MB)'),
            ),
          if (articleImage != null) ...[
            const SizedBox(height: 12),
            Image.network(
              articleImage!,
              height: 160,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Notice('Article cover unavailable.'),
            ),
            const Text(
              'The article’s main image will be this podcast’s cover.',
            ),
          ] else
            OutlinedButton.icon(
              onPressed: busy ? null : pickCover,
              icon: const Icon(Icons.image_outlined),
              label: Text(cover?.name ?? 'Choose cover (up to 5 MB)'),
            ),
          FutureBuilder<List<Json>>(
            future: articles,
            builder: (context, snapshot) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator(),
                if (snapshot.hasError)
                  Notice(
                    'Could not load your articles. You can publish without a related article.',
                  ),
                if (snapshot.hasData)
                  DropdownButtonFormField<int?>(
                    initialValue: articleId,
                    decoration: const InputDecoration(
                      labelText: 'Related article (optional)',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('No related article'),
                      ),
                      for (final post in snapshot.data!)
                        DropdownMenuItem<int?>(
                          value: post['id'] as int,
                          child: Text(
                            '${post['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            articleId = value;
                            final selected = snapshot.data!.where(
                              (post) => post['id'] == value,
                            );
                            articleImage = selected.isEmpty
                                ? null
                                : widget.repository.imageUrl(
                                    selected.first['photo_link'] as String?,
                                  );
                          }),
                  ),
              ],
            ),
          ),
          if (error != null) Notice(error!),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                busy ||
                    (cover == null && articleImage == null) ||
                    (useLink ? audioLink.text.trim().isEmpty : audio == null)
                ? null
                : publish,
            icon: const Icon(Icons.publish_outlined),
            label: Text(busy ? 'Publishing…' : 'Publish for everyone'),
          ),
        ],
      ),
    ),
  );
}
