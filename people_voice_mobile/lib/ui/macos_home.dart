import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/notifications.dart';
import '../data/podcasts.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'community.dart';
import 'for_you.dart';
import 'home.dart';
import 'my_articles.dart';
import 'notifications.dart';
import 'podcasts.dart';
import 'preferences.dart';
import 'reader.dart';
import 'search.dart';
import 'trends.dart';

/// Desktop navigation and editorial front page. Mobile keeps its own shell.
class MacosHome extends StatefulWidget {
  const MacosHome({super.key, required this.repository, required this.session});
  final Repository repository;
  final Session session;

  @override
  State<MacosHome> createState() => _MacosHomeState();
}

class _MacosHomeState extends State<MacosHome> with WidgetsBindingObserver {
  final scaffold = GlobalKey<ScaffoldState>();
  String selected = 'News';
  final visited = <String>{'News'};
  late final categories = widget.repository.categories();
  late final podcasts = PodcastApi();
  late final gateway = EditorialGateway(widget.repository.api, widget.session);
  late final inbox = NotificationInbox(
    gateway,
    widget.repository.store,
    preferences: widget.repository.experience,
    promotions: widget.repository.promotions,
  );
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(inbox.refresh());
    timer = Timer.periodic(const Duration(minutes: 1), (_) => inbox.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(inbox.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    inbox.dispose();
    podcasts.client.close();
    super.dispose();
  }

  void select(String value) => setState(() {
    selected = value;
    visited.add(value);
  });

  void open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Widget page(String name) => switch (name) {
    'News' => MacosNewsPage(
      repository: widget.repository,
      onSearch: () => select('Search'),
      onPromote: () => select('Promote'),
    ),
    'Search' => SearchPage(repository: widget.repository),
    'For you' => ForYouPage(repository: widget.repository),
    'Podcasts' => PodcastsPage(
      api: podcasts,
      repository: widget.repository,
      onSignIn: () => open(AccountPage(session: widget.session)),
    ),
    'Promote' => AdvertisePage(
      repository: widget.repository,
      session: widget.session,
    ),
    'Saved' => LibraryPage(repository: widget.repository),
    'My articles' => MyArticlesPage(
      repository: widget.repository,
      session: widget.session,
    ),
    'Community' => CommunityHub(repository: widget.repository),
    'All categories' => CategoriesPage(repository: widget.repository),
    'Preferences' => PreferencesPage(repository: widget.repository),
    'Trends' => TrendsPage(gateway: gateway, repository: widget.repository),
    'Notifications' => NotificationsPage(
      inbox: inbox,
      repository: widget.repository,
    ),
    'Account' => AccountPage(session: widget.session),
    'More' => MoreMenu(repository: widget.repository, session: widget.session),
    _ => CategoryArticlesPage(
      repository: widget.repository,
      category: name.substring('category:'.length),
    ),
  };

  Widget item(String label, IconData icon, {String? destination}) {
    final key = destination ?? label;
    final active = selected == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        key: ValueKey('mac-nav-$key'),
        selected: active,
        selectedTileColor: Brand.red,
        selectedColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 21),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        minTileHeight: 48,
        onTap: () {
          select(key);
          scaffold.currentState?.closeDrawer();
        },
      ),
    );
  }

  Widget group(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 28, 8, 16),
    child: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget sidebar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        item('Search', Icons.search),
        item('News', Icons.newspaper),
        item('For you', Icons.auto_awesome_outlined),
        item('Podcasts', Icons.podcasts),
        item('Promote', Icons.campaign_outlined),
        group('Library'),
        item('Saved', Icons.bookmark),
        item('My articles', Icons.edit_note),
        group('Explore'),
        item('Community', Icons.location_city),
        group('Sections'),
        item('All categories', Icons.grid_view_rounded),
        FutureBuilder<FeedResult>(
          future: categories,
          builder: (context, snapshot) {
            final names = List<String>.from(
              snapshot.data?.body['data'] as List? ?? [],
            );
            return Column(
              children: [
                for (final name in names)
                  item(
                    name,
                    name.toLowerCase() == 'business'
                        ? Icons.business_center_outlined
                        : Icons.label_outline,
                    destination: 'category:$name',
                  ),
              ],
            );
          },
        ),
        group('Your account'),
        item('Account', Icons.person_outline),
        item('Preferences', Icons.tune),
        item('More', Icons.more_horiz),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      key: scaffold,
      drawer: wide ? null : Drawer(child: SafeArea(child: sidebar())),
      appBar: AppBar(
        toolbarHeight: 68,
        title: const SizedBox(width: 240, child: BrandMasthead()),
        actions: [
          IconButton(
            tooltip: 'Promote',
            onPressed: () => select('Promote'),
            icon: const Icon(Icons.campaign_outlined),
          ),
          IconButton(
            tooltip: 'Preferences',
            onPressed: () => select('Preferences'),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Trends',
            onPressed: () => select('Trends'),
            icon: const Icon(Icons.trending_up),
          ),
          ListenableBuilder(
            listenable: inbox,
            builder: (context, _) => IconButton(
              tooltip: 'Notifications',
              onPressed: () => select('Notifications'),
              icon: Badge(
                isLabelVisible: inbox.unread > 0,
                label: Text('${inbox.unread}'),
                child: const Icon(Icons.notifications_none),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          if (wide) ...[
            SizedBox(width: 240, child: sidebar()),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: IndexedStack(
              index: visited.toList().indexOf(selected),
              children: [
                for (final name in visited)
                  KeyedSubtree(
                    key: ValueKey(name),
                    child: TickerMode(
                      enabled: selected == name,
                      child: page(name),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MacosNewsPage extends StatefulWidget {
  const MacosNewsPage({
    super.key,
    required this.repository,
    required this.onSearch,
    required this.onPromote,
  });
  final Repository repository;
  final VoidCallback onSearch, onPromote;

  @override
  State<MacosNewsPage> createState() => _MacosNewsPageState();
}

class _MacosNewsPageState extends State<MacosNewsPage> {
  final posts = <Json>[];
  late Future<FeedResult> featured;
  bool loading = false;
  String? error, warning;
  int current = 0, pages = 1;

  @override
  void initState() {
    super.initState();
    featured = widget.repository.feed('/posts/featured');
    load();
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.repository.feed(
        '/posts?page=${more ? current + 1 : 1}',
      );
      if (!mounted) return;
      setState(() {
        if (!more) posts.clear();
        for (final post in List<Json>.from(
          result.body['data'] as List? ?? [],
        )) {
          if (!posts.any((p) => p['id'] == post['id'])) posts.add(post);
        }
        current = result.body['page'] as int? ?? 1;
        pages = result.body['pages'] as int? ?? current;
        warning = result.warning;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() => featured = widget.repository.feed('/posts/featured'));
    await load();
  }

  void article(Json post) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReaderPage(
        repository: widget.repository,
        id: int.parse('${post['id']}'),
        title: '${post['title']}',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final padding = constraints.maxWidth > 1296
          ? (constraints.maxWidth - 1240) / 2
          : constraints.maxWidth >= 650
          ? 28.0
          : 16.0;
      final remaining = posts.skip(1).toList();
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          key: const PageStorageKey('macos-news-scroll'),
          padding: EdgeInsets.all(padding),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'News',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh news',
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              MaterialLocalizations.of(context)
                  .formatMediumDate(DateTime.now()),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(width: 44, height: 3, color: Brand.red),
                const Expanded(child: Divider(height: 1)),
              ],
            ),
            const SizedBox(height: 22),
            Semantics(
              button: true,
              label: 'Search articles, topics and authors',
              child: InkWell(
                onTap: widget.onSearch,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search articles, topics and authors',
                          style: TextStyle(
                            fontSize: 17,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (warning != null) Notice(warning!),
            if (error != null) ...[
              Notice(error!),
              TextButton(
                onPressed: () => load(),
                child: const Text('Try again'),
              ),
            ],
            if (loading && posts.isEmpty)
              const Center(child: CircularProgressIndicator()),
            if (!loading && error == null && posts.isEmpty)
              const AppEmptyState(
                title: 'No stories yet',
                message: 'Check back soon for community news.',
              ),
            if (posts.isNotEmpty) ...[
              MacosHeroStory(
                post: posts.first,
                repository: widget.repository,
                onTap: () => article(posts.first),
              ),
              const SizedBox(height: 28),
            ],
            PromotionalFeatured(repository: widget.repository, data: featured),
            const SizedBox(height: 28),
            MacosNewsSections(posts: remaining, repository: widget.repository),
            if (current < pages && posts.isNotEmpty)
              Center(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : () => load(more: true),
                  icon: const Icon(Icons.expand_more),
                  label: Text(loading ? 'Loading…' : 'Load more news'),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class MacosNewsSections extends StatelessWidget {
  const MacosNewsSections({
    super.key,
    required this.posts,
    required this.repository,
  });
  final List<Json> posts;
  final Repository repository;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = (constraints.maxWidth / (280 * scale)).floor().clamp(
        1,
        3,
      );
      Widget rows(List<Json> items, int count, MacosCardStyle style) => Column(
        children: [
          for (var start = 0; start < items.length; start += count)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var i = start;
                    i < start + count && i < items.length;
                    i++
                  ) ...[
                    if (i > start) const SizedBox(width: 16),
                    Expanded(
                      child: MacosEditorialCard(
                        key: ValueKey('mac-story-${items[i]['id']}'),
                        post: items[i],
                        repository: repository,
                        style: style,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (posts.isNotEmpty) ...[
            const SectionHeading(
              'Latest stories',
              eyebrow: 'Fresh from the newsroom',
              subtitle: 'The latest voices and reporting from our community.',
            ),
            rows(
              posts.take(2).toList(),
              constraints.maxWidth >= 620 * scale ? 2 : 1,
              MacosCardStyle.large,
            ),
          ],
          if (posts.length > 2) ...[
            const SizedBox(height: 16),
            const SectionHeading(
              'More to explore',
              eyebrow: 'Across the headlines',
            ),
            rows(
              posts.skip(2).take(3).toList(),
              columns,
              MacosCardStyle.compact,
            ),
          ],
          if (posts.length > 5) ...[
            const SizedBox(height: 16),
            const SectionHeading('In focus', eyebrow: 'A closer look'),
            MacosEditorialCard(
              key: ValueKey('mac-story-${posts[5]['id']}'),
              post: posts[5],
              repository: repository,
              style: MacosCardStyle.focus,
            ),
          ],
          if (posts.length > 6) ...[
            const SizedBox(height: 28),
            const SectionHeading('More news', eyebrow: 'Keep reading'),
            rows(posts.skip(6).toList(), columns, MacosCardStyle.compact),
          ],
        ],
      );
    },
  );
}

enum MacosCardStyle { large, compact, focus }

class MacosEditorialCard extends StatelessWidget {
  const MacosEditorialCard({
    super.key,
    required this.post,
    required this.repository,
    required this.style,
  });
  final Json post;
  final Repository repository;
  final MacosCardStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final date = DateTime.tryParse('${post['created']}');
      final author = post['author'] is Map
          ? '${post['author']['username'] ?? ''}'
          : '';
      final compact = style == MacosCardStyle.compact;
      Widget copy({bool stretch = false}) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Text(
              Repository.articleCategories(post).join(' · ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${post['title'] ?? 'Untitled story'}',
              maxLines: compact ? 4 : null,
              overflow: compact ? TextOverflow.ellipsis : null,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: compact ? 16 : 21, height: 1.2),
            ),
            if (!compact && '${post['subtitle'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${post['subtitle']}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (stretch) const Spacer() else const SizedBox(height: 20),
            Text(
              [
                if (author.isNotEmpty) author,
                if (date != null)
                  MaterialLocalizations.of(context)
                      .formatMediumDate(date.toLocal()),
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
      Widget cover() => _StoryImage(repository: repository, post: post);
      final wideFocus =
          style == MacosCardStyle.focus && constraints.maxWidth >= 700 * scale;
      Widget content;
      if (compact) {
        content = SizedBox(
          height: 180 * scale,
          child: Row(
            children: [
              Expanded(flex: 3, child: copy(stretch: true)),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.expand(child: cover()),
                  ),
                ),
              ),
            ],
          ),
        );
      } else if (wideFocus) {
        content = SizedBox(
          height: 360 * scale,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 330),
                  child: cover(),
                ),
              ),
              Expanded(flex: 2, child: copy(stretch: true)),
            ],
          ),
        );
      } else {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: cover()),
            copy(),
          ],
        );
      }
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReaderPage(
                repository: repository,
                id: int.parse('${post['id']}'),
                title: '${post['title']}',
              ),
            ),
          ),
          child: content,
        ),
      );
    },
  );
}

class _StoryImage extends StatelessWidget {
  const _StoryImage({required this.repository, required this.post});
  final Repository repository;
  final Json post;
  @override
  Widget build(BuildContext context) {
    final url = post['photo_link'] as String? ?? '';
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.newspaper, size: 40)),
    );
    if (url.isEmpty) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: repository.image(url),
      builder: (context, snapshot) {
        if (snapshot.data == null || snapshot.data!.isEmpty) return placeholder;
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, error, stack) => placeholder,
        );
      },
    );
  }
}

class MacosHeroStory extends StatelessWidget {
  const MacosHeroStory({
    super.key,
    required this.post,
    required this.repository,
    required this.onTap,
  });
  final Json post;
  final Repository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final date = DateTime.tryParse('${post['created']}');
      final author = post['author'] is Map
          ? '${post['author']['username'] ?? ''}'
          : '';
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _StoryImage(repository: repository, post: post),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .05),
                          Colors.black.withValues(alpha: .85),
                        ],
                        stops: const [0, 1],
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: compact ? 320 : constraints.maxWidth * .40,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 20 : 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: compact ? 70 : 90),
                        Text(
                          Repository.articleCategories(post)
                              .join(' · ')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xffffb0b0),
                            fontSize: 12,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${post['title'] ?? 'Untitled story'}',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: compact ? 26 : 34,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if ('${post['subtitle'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            '${post['subtitle']}',
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.3,
                              color: Colors.white,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          [
                            if (author.isNotEmpty) author,
                            if (date != null)
                              MaterialLocalizations.of(context)
                                  .formatMediumDate(date.toLocal()),
                          ].join('  ·  '),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
