import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'home.dart' show ArticleTile, CategoriesPage, Notice;
import 'preferences.dart';
import 'responsive.dart';

class ForYouPage extends StatefulWidget {
  const ForYouPage({super.key, required this.repository});
  final Repository repository;
  @override
  State<ForYouPage> createState() => _ForYouPageState();
}

class _PersonalFeed {
  const _PersonalFeed(this.posts, {this.pages = 1, this.warning});
  final List<Json> posts;
  final int pages;
  final String? warning;
}

class _ForYouPageState extends State<ForYouPage> {
  late Future<_PersonalFeed> data;
  late String following;
  int page = 1;

  String get preferenceKey {
    final prefs = widget.repository.experience;
    return '${prefs.owner}:${prefs.strings('categories').join(',')}:${prefs.strings('authors').join(',')}';
  }

  @override
  void initState() {
    super.initState();
    following = preferenceKey;
    data = load();
    widget.repository.experience.addListener(preferencesChanged);
  }

  void preferencesChanged() {
    final next = preferenceKey;
    if (following == next || !mounted) return;
    following = next;
    setState(() {
      page = 1;
      data = load();
    });
  }

  @override
  void dispose() {
    widget.repository.experience.removeListener(preferencesChanged);
    super.dispose();
  }

  Future<_PersonalFeed> load() async {
    final requestedPage = page;
    final repository = widget.repository;
    final prefs = repository.experience;
    String? warning;
    final session = repository.session;
    if (session != null && !session.expired) {
      try {
        await prefs.sync();
        final response = await repository.api.request(
          '/me/feed?page=$requestedPage',
          token: session.token,
        );
        return _PersonalFeed(
          List<Json>.from(response['data'] as List),
          pages: response['pages'] as int? ?? 1,
        );
      } catch (_) {
        warning = 'Your live feed is unavailable. Showing matching stories saved on this device.';
      }
    }
    if (prefs.strings('categories').isEmpty &&
        prefs.strings('authors').isEmpty) {
      return _PersonalFeed(const [], warning: warning);
    }
    try {
      final recent = await repository.feed('/posts?page=1');
      await Future.wait(
        List<Json>.from(recent.body['data'] as List).map(repository.preview),
      );
    } catch (_) {}
    for (final category in prefs.strings('categories')) {
      try {
        await repository.search(category);
      } catch (_) {}
    }
    return _PersonalFeed(
      await repository.store.searchableArticles(),
      warning: warning,
    );
  }

  Future<void> refresh() async {
    setState(() {
      page = 1;
      data = load();
    });
    try {
      await data;
    } catch (_) {
      // The FutureBuilder presents the failure with a retry action.
    }
  }

  void browseTopics() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Discover topics')),
        body: SafeArea(
          child: ContentWidth(
            child: CategoriesPage(repository: widget.repository),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository.experience,
    builder: (context, _) => FutureBuilder<_PersonalFeed>(
      key: ValueKey(widget.repository.experience.owner),
      future: data,
      builder: (context, snapshot) {
        final prefs = widget.repository.experience;
        final loading = snapshot.connectionState != ConnectionState.done;
        final categories = prefs.strings('categories');
        final authors = prefs.strings('authors');
        final hasFollows = categories.isNotEmpty || authors.isNotEmpty;
        final posts =
            (snapshot.data?.posts ?? [])
                .where(
                  (post) =>
                      !prefs.blocked(post['author']?['id'] as int?) &&
                      (prefs.followsAuthor(
                            post['author']?['id'] as int? ?? -1,
                          ) ||
                          Repository.articleCategories(post)
                              .any(prefs.followsCategory)),
                )
                .toList()
              ..sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));
        final pages = snapshot.data?.pages ?? 1;
        return ContentWidth(
          maxWidth: 1240,
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                const SectionHeading(
                  'Your community. Your interests.',
                  eyebrow: 'FOR YOU',
                  subtitle: 'A personal reading list from the topics and voices you follow.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasFollows)
                      Text(
                        '${categories.length} topics · ${authors.length} authors',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PreferencesPage(repository: widget.repository),
                        ),
                      ),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Manage interests'),
                    ),
                    TextButton.icon(
                      onPressed: loading ? null : refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading your stories',
                  ),
                if (snapshot.data?.warning != null)
                  Notice(snapshot.data!.warning!),
                if (snapshot.hasError)
                  AppEmptyState(
                    title: 'Your stories could not load',
                    message: 'Check your connection and refresh to try again.',
                    icon: Icons.cloud_off_outlined,
                    actionLabel: 'Try again',
                    onAction: refresh,
                  ),
                if (!loading && !snapshot.hasError && posts.isEmpty)
                  AppEmptyState(
                    title: hasFollows
                        ? 'Your next story is on its way'
                        : 'Make the news your own',
                    message: hasFollows
                        ? 'No matching stories here yet. Explore more topics or check back for new stories from your favorite writers.'
                        : 'Follow a topic from its page, or a writer from any article. Their stories will come together here.',
                    icon: hasFollows
                        ? Icons.auto_stories_outlined
                        : Icons.interests_outlined,
                    actionLabel: 'Discover topics',
                    onAction: browseTopics,
                  ),
                ArticleColumns(
                  children: posts
                      .map(
                        (post) => ArticleTile(
                          key: ValueKey(post['id']),
                          post: post,
                          repository: widget.repository,
                        ),
                      )
                      .toList(),
                ),
                if (!loading && !snapshot.hasError && pages > 1)
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: page > 1
                            ? () => setState(() {
                                page--;
                                data = load();
                              })
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      Text('Page $page of $pages'),
                      TextButton.icon(
                        onPressed: page < pages
                            ? () => setState(() {
                                page++;
                                data = load();
                              })
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
