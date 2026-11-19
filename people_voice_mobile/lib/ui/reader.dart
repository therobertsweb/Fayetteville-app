import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;

import '../data/api.dart';
import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/repository.dart';
import 'article_body.dart';
import 'brand.dart';
import 'comment_composer.dart';
import 'home.dart';
import 'news_tips.dart';
import 'preferences.dart';
import 'responsive.dart';
import 'related_articles.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.repository,
    required this.id,
    required this.title,
  });
  final Repository repository;
  final int id;
  final String title;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  Json? article;
  late final Future<FeedResult> promoted = widget.repository.feed(
    '/posts/featured',
  );
  String? error;
  bool busy = false, downloading = false;
  int imageVersion = 0;
  bool favorite = false, favoriteBusy = false;
  int get owner => widget.repository.session?.userId ?? 0;
  Future<void> toggleFavorite() async {
    setState(() => favoriteBusy = true);
    try {
      final next = !favorite;
      await widget.repository.store.setFavorite(
        owner,
        widget.id,
        next,
        operationId(),
      );
      if (mounted) {
        setState(() => favorite = next);
        message(
          context,
          next ? 'Added to your favorites.' : 'Removed from favorites.',
        );
      }
      final session = widget.repository.session;
      if (session != null) {
        unawaited(
          EditorialGateway(
            widget.repository.api,
            session,
          ).syncFavorites(widget.repository.store).catchError((Object _) {}),
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => favoriteBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool refresh = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.article(
        widget.id,
        refresh: refresh,
      );
      final saved = await widget.repository.store.favorite(owner, widget.id);
      if (mounted) {
        setState(() {
          article = result;
          favorite = saved;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiFailure
              ? e.message
              : 'Could not load this article. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> images() async {
    setState(() => downloading = true);
    try {
      final missing = await widget.repository.downloadImages(article!);
      if (mounted) {
        setState(() => imageVersion++);
        message(
          context,
          missing == 0
              ? 'Text and images saved for offline reading.'
              : 'Text saved. $missing images could not be downloaded. You can try again.',
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Widget image(String? src) => OfflineImage(
    key: ValueKey('$src-$imageVersion'),
    repository: widget.repository,
    source: src,
  );

  int get readingMinutes {
    final text =
        html.parse(article?['content'] as String? ?? '').body?.text ?? '';
    return (text.trim().split(RegExp(r'\s+')).length / 220).ceil().clamp(
      1,
      999,
    );
  }

  Future<void> copyLink() async {
    final slug = article?['url'] as String?;
    if (slug == null || slug.isEmpty) return;
    try {
      final uri = Api.site.resolve('/blog/${Uri.encodeComponent(slug)}');
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (mounted) {
        message(context, 'Article link copied. You can share it anywhere.');
      }
    } catch (_) {
      if (mounted) {
        message(context, 'Could not copy the article link. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Read article'),
      actions: [
        IconButton(
          tooltip: 'Copy article link',
          icon: const Icon(Icons.share_outlined),
          onPressed: (article?['url'] as String? ?? '').isEmpty
              ? null
              : copyLink,
        ),
        IconButton(
          tooltip: favorite ? 'Remove favorite' : 'Save favorite',
          onPressed: favoriteBusy || article == null ? null : toggleFavorite,
          icon: Icon(favorite ? Icons.bookmark : Icons.bookmark_outline),
        ),
        PopupMenuButton<String>(
          tooltip: 'Reading options',
          onSelected: (value) {
            if (value == 'refresh') load(refresh: true);
            if (value == 'preferences') {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PreferencesPage(repository: widget.repository),
                ),
              );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'preferences',
              child: Text('Text size & appearance'),
            ),
            PopupMenuItem(
              value: 'refresh',
              enabled: !busy,
              child: const Text('Refresh article'),
            ),
          ],
        ),
      ],
    ),
    body: SafeArea(
      // Keep the whole viewport responsive to desktop wheel/trackpad events,
      // including the margins beside the centered article.
      child: SingleChildScrollView(
        key: PageStorageKey('article-${widget.id}'),
        primary: true,
        // On macOS a trackpad can keep pushing past the article end. The
        // elastic return then competes with reversing the gesture to read up.
        physics: Theme.of(context).platform == TargetPlatform.macOS
            ? const ClampingScrollPhysics()
            : null,
        // The HTML body is already one continuous column. Keep the surrounding
        // media mounted too: recycling it on the way back up restarts image
        // loading and replaces its measured height with the placeholder height.
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (article != null &&
                    Repository.articleCategories(article!).isNotEmpty) ...[
                  Text(
                    Repository.articleCategories(article!)
                        .join(' · ')
                        .toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  article?['title'] as String? ?? widget.title,
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w800, height: 1.18),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Loading article',
                    ),
                  ),
                if (error != null) ...[
                  Notice(error!),
                  if (article == null)
                    const AppEmptyState(
                      title: 'This story is not available yet',
                      message: 'Connect to the internet to download it. Once opened, the full text will be available offline.',
                      icon: Icons.cloud_off_outlined,
                    ),
                  TextButton(
                    onPressed: busy ? null : () => load(refresh: true),
                    child: const Text('Retry'),
                  ),
                ],
                if (article != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if ((article!['author']?['username'] as String? ?? '')
                          .isNotEmpty)
                        Text(
                          'By ${article!['author']['username']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if ((article!['created'] as String? ?? '').isNotEmpty)
                        Text(
                          (article!['created'] as String).split('T').first,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      Text(
                        '$readingMinutes min read',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (article!['author']?['id'] is int)
                    ListenableBuilder(
                      listenable: widget.repository.experience,
                      builder: (context, _) {
                        final prefs = widget.repository.experience;
                        final author = article!['author']['id'] as int;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: Icon(
                              prefs.followsAuthor(author)
                                  ? Icons.person_remove_outlined
                                  : Icons.person_add_alt,
                              size: 18,
                            ),
                            label: Text(
                              prefs.followsAuthor(author)
                                  ? 'Unfollow author'
                                  : 'Follow author',
                            ),
                            onPressed: () async {
                              try {
                                await prefs.set(
                                  'authorName:$author',
                                  article!['author']['username'],
                                );
                                if (!prefs.followsAuthor(author)) {
                                  await prefs.set(
                                    'followedAt:$author',
                                    DateTime.now().toUtc().toIso8601String(),
                                  );
                                }
                                await prefs.toggle('authors', '$author');
                              } catch (_) {
                                if (context.mounted) {
                                  message(
                                    context,
                                    'Could not update your followed authors. Please try again.',
                                  );
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
                  if (article!['is_sponsored'] == true)
                    const Notice('Sponsored article · Paid promotion'),
                  const SizedBox(height: 20),
                  if (widget.repository.imageUrl(
                        article!['photo_link'] as String?,
                      ) !=
                      null)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: image(article!['photo_link'] as String),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SelectionArea(
                    child: ArticleBody(
                      content: article!['content'] as String,
                      repository: widget.repository,
                      imageVersion: imageVersion,
                    ),
                  ),
                  const Divider(height: 48),
                  const Notice(
                    'Text saved on this device. Take the images with you for a complete offline read.',
                    icon: Icons.offline_pin_outlined,
                  ),
                  OutlinedButton.icon(
                    onPressed: downloading ? null : images,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      downloading
                          ? 'Downloading images…'
                          : 'Save images for offline reading',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CommentsPage(
                          repository: widget.repository,
                          postId: widget.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Read comments'),
                  ),
                  const SizedBox(height: 24),
                  PromotionalFeatured(
                    repository: widget.repository,
                    data: promoted,
                    excludeArticleId: widget.id,
                  ),
                  const SizedBox(height: 28),
                  RelatedArticles(
                    key: ValueKey('related-${widget.id}-$imageVersion'),
                    repository: widget.repository,
                    article: article!,
                    promoted: promoted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class OfflineImage extends StatefulWidget {
  const OfflineImage({
    super.key,
    required this.repository,
    required this.source,
    this.fit = BoxFit.contain,
  });
  final Repository repository;
  final String? source;
  final BoxFit fit;
  @override
  State<OfflineImage> createState() => _OfflineImageState();
}

class _OfflineImageState extends State<OfflineImage> {
  late Future<Uint8List?> data = load();
  Future<Uint8List?> load() {
    final url = widget.repository.imageUrl(widget.source);
    return url == null ? Future.value() : widget.repository.image(url);
  }

  @override
  void didUpdateWidget(covariant OfflineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) data = load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: data,
    builder: (context, snapshot) {
      if (snapshot.data == null) {
        return _ImagePlaceholder(
          loading: snapshot.connectionState != ConnectionState.done,
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth && constraints.maxWidth > 0
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(1, 4096);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              snapshot.data!,
              fit: widget.fit,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => const _ImagePlaceholder(),
            ),
          );
        },
      );
    },
  );
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colors.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? 0 : 140,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    color: colors.onSurfaceVariant,
                    size: 28,
                  ),
                  if (constraints.maxHeight > 100) ...[
                    const SizedBox(height: 10),
                    Text(
                      loading ? 'Loading image…' : 'Image unavailable',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.repository,
    required this.postId,
  });
  final Repository repository;
  final int postId;
  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  int page = 1;
  bool posting = false;
  late Future<FeedResult> data = fetch();

  @override
  void initState() {
    super.initState();
    widget.repository.loadAdminUserNames().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<FeedResult> fetch() =>
      widget.repository.feed('/posts/${widget.postId}/comments?page=$page');

  String authorName(dynamic comment) {
    final author = comment['author'];
    final supplied = author is Map ? author['username'] : author;
    for (final candidate in [
      supplied,
      comment['author_username'],
      widget.repository.authorName(comment['author_id'] as int?),
    ]) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return 'Community member';
  }

  Future<void> compose({int? parentId}) async {
    final session = widget.repository.session;
    if (session == null || session.expired) {
      message(context, 'Sign in to comment or reply.');
      return;
    }
    if (posting) return;
    setState(() => posting = true);
    final published = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommentComposer(
        session: session,
        postId: widget.postId,
        parentId: parentId,
      ),
    );
    if (!mounted) return;
    setState(() {
      posting = false;
      if (published == true) {
        page = 1;
        data = fetch();
      }
    });
    if (published == true) {
      message(
        context,
        parentId == null ? 'Comment published.' : 'Reply published.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Comments'),
      actions: [
        IconButton(
          tooltip: 'Add comment',
          onPressed: posting ? null : () => compose(),
          icon: const Icon(Icons.add_comment_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: ContentWidth(
        child: FutureBuilder<FeedResult>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SectionHeading(
                  'Join the conversation',
                  eyebrow: 'COMMUNITY VOICES',
                  subtitle: 'Share your perspective and keep the conversation respectful.',
                ),
                if (snapshot.hasError) Notice('${snapshot.error}'),
                if (snapshot.data?.warning != null)
                  Notice(snapshot.data!.warning!),
                if (snapshot.hasData) ...[
                  if ((snapshot.data!.body['data'] as List).isEmpty)
                    const AppEmptyState(
                      title: 'Be the first to share your thoughts',
                      message: 'No comments yet. Add your voice to this story.',
                      icon: Icons.forum_outlined,
                    ),
                  ...(snapshot.data!.body['data'] as List).map(
                    (comment) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(authorName(comment)),
                            if (comment['parent_id'] != null)
                              Text('Reply to comment ${comment['parent_id']}'),
                            const SizedBox(height: 8),
                            if (widget.repository.experience.blocked(
                              comment['author_id'] as int?,
                            ))
                              const Text('Comment hidden — blocked user')
                            else
                              HtmlWidget(comment['content'] as String),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => NewsTipsPage(
                                        repository: widget.repository,
                                        kind: 'comment_report',
                                        targetId: comment['id'],
                                        initialTitle:
                                            'Report comment ${comment['id']}',
                                        initialBody:
                                            'Article ID: ${widget.postId}\nReason: ',
                                      ),
                                    ),
                                  ),
                                  child: const Text('Report'),
                                ),
                                if (comment['author_id'] is int)
                                  TextButton(
                                    onPressed: () async {
                                      await widget.repository.experience.toggle(
                                        'blocked',
                                        '${comment['author_id']}',
                                      );
                                      if (mounted) setState(() {});
                                    },
                                    child: Text(
                                      widget.repository.experience.blocked(
                                            comment['author_id'] as int?,
                                          )
                                          ? 'Unblock user'
                                          : 'Block user',
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: posting
                                    ? null
                                    : () => compose(
                                        parentId: comment['id'] as int,
                                      ),
                                icon: const Icon(Icons.reply, size: 18),
                                label: const Text('Reply'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: page > 1
                            ? () => setState(() {
                                page--;
                                data = fetch();
                              })
                            : null,
                        child: const Text('Previous'),
                      ),
                      Text('Page $page'),
                      TextButton(
                        onPressed: page < (snapshot.data!.body['pages'] as int)
                            ? () => setState(() {
                                page++;
                                data = fetch();
                              })
                            : null,
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
                TextButton(
                  onPressed: () => setState(() {
                    data = fetch();
                  }),
                  child: const Text('Refresh'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: posting ? null : () => compose(),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: Text(posting ? 'Publishing…' : 'Add a comment'),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
