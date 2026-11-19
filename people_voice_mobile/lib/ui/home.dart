import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:url_launcher/url_launcher.dart';

import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/notifications.dart';
import '../data/podcasts.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'community.dart';
import 'contact.dart';
import 'drafts.dart';
import 'for_you.dart';
import 'iphone_news.dart';
import 'my_articles.dart';
import 'macos_home.dart';
import 'news_tips.dart';
import 'notifications.dart';
import 'podcasts.dart';
import 'preferences.dart';
import 'promotion_carousel.dart';
import 'responsive.dart';
import 'search.dart';

/// Shows a short message over the current page, accepting plain text or
/// errors such as [ApiFailure] whose [Object.toString] is already readable.
void message(BuildContext context, Object? value) {
  if (value == null) return;
  final text = '$value';
  if (text.isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Inline informational block used for warnings and helper copy.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}

int _postId(Json post) => int.tryParse('${post['id']}') ?? 0;

/// Lists stop dead at their edges (a single pump after a drag must find a
/// settled offset) everywhere except iPhone, which keeps its bounce.
ScrollPhysics? _listPhysics(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS
    ? null
    : const ClampingScrollPhysics();

/// Full-width story row used on phones and inside single-column pages.
class ArticleTile extends StatelessWidget {
  const ArticleTile({
    super.key,
    required this.post,
    required this.repository,
    this.coverHeight = 120,
  });
  final Json post;
  final Repository repository;
  final double coverHeight;

  @override
  Widget build(BuildContext context) => MacosEditorialCard(
    post: post,
    repository: repository,
    style: coverHeight > 120 ? MacosCardStyle.large : MacosCardStyle.compact,
  );
}

/// Compact story card used inside responsive grids.
class EditorialStoryCard extends StatelessWidget {
  const EditorialStoryCard({
    super.key,
    required this.post,
    required this.repository,
  });
  final Json post;
  final Repository repository;

  @override
  Widget build(BuildContext context) => MacosEditorialCard(
    post: post,
    repository: repository,
    style: MacosCardStyle.compact,
  );
}

/// Paid placements rendered below editorial content.
class PromotionalFeatured extends StatelessWidget {
  const PromotionalFeatured({
    super.key,
    required this.repository,
    required this.data,
    this.excludeArticleId,
    this.showHeading = true,
  });
  final Repository repository;
  final Future<FeedResult> data;
  final int? excludeArticleId;
  final bool showHeading;

  @override
  Widget build(BuildContext context) => FutureBuilder<FeedResult>(
    future: data,
    builder: (context, snapshot) {
      final body = snapshot.data?.body;
      final rows = body == null
          ? <Json>[]
          : List<Json>.from(body['data'] as List? ?? const [])
                .where((post) => _postId(post) != excludeArticleId)
                .toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: showHeading
                      ? const Text(
                          'FEATURED POSTS',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (repository.session != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Brand.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 30),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AdvertisePage(
                          repository: repository,
                          session: repository.session!,
                        ),
                      ),
                    ),
                    child: const Text('PROMOTE'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Stories promoted this week',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Featured placement costs five dollars for 7 days. Your article must be published and approved before it appears here.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            PromotionCarousel(posts: rows, repository: repository),
          ],
        ),
      );
    },
  );
}

/// List of topics linking to their story pages.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.repository});
  final Repository repository;

  @override
  Widget build(BuildContext context) => FutureBuilder<FeedResult>(
    future: repository.categories(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading topics'),
        );
      }
      if (snapshot.hasError) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Notice('Topics could not load. ${snapshot.error}'),
            OutlinedButton.icon(
              onPressed: () => (context as Element).markNeedsBuild(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        );
      }
      final result = snapshot.data;
      final values = result == null
          ? const <String>[]
          : List<String>.from(result.body['data'] as List? ?? const []);
      if (values.isEmpty) {
        return const Center(
          child: AppEmptyState(
            title: 'No topics yet',
            message: 'Check back soon for new community topics.',
            icon: Icons.interests_outlined,
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (result?.warning != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Notice(result!.warning!),
            ),
          for (final category in values)
            ListTile(
              title: Text(category),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CategoryArticlesPage(
                    repository: repository,
                    category: category,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Stories filed under one topic, with paging.
class CategoryArticlesPage extends StatefulWidget {
  const CategoryArticlesPage({
    super.key,
    required this.repository,
    required this.category,
  });
  final Repository repository;
  final String category;

  @override
  State<CategoryArticlesPage> createState() => _CategoryArticlesPageState();
}

class _CategoryArticlesPageState extends State<CategoryArticlesPage> {
  int page = 1;
  int pages = 1;
  bool loading = false;
  bool loadedOnce = false;
  String? error;
  String? warning;
  List<Json> rows = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({int? target}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.repository.categoryArticles(
        widget.category,
        page: target ?? page,
      );
      if (!mounted) return;
      setState(() {
        rows = List<Json>.from(result.body['data'] as List? ?? const []);
        page = (result.body['page'] as int?) ?? (target ?? page);
        pages = (result.body['pages'] as int?) ?? page;
        warning = result.warning;
        loading = false;
        loadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadedOnce = true;
        error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _categoryBody();
    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: SafeArea(
        child: defaultTargetPlatform == TargetPlatform.iOS
            ? ContentWidth(child: content)
            : content,
      ),
    );
  }

  Widget _categoryBody() {
    if (!loadedOnce && loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading stories'),
      );
    }
    if (error != null && rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Notice('Stories could not load. $error'),
          OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    final cards = defaultTargetPlatform == TargetPlatform.iOS
        ? [
            for (final post in rows)
              ArticleTile(
                key: ValueKey('category-${_postId(post)}'),
                post: post,
                repository: widget.repository,
              ),
          ]
        : [
            ArticleColumns(
              children: [
                for (final post in rows)
                  EditorialStoryCard(
                    key: ValueKey('category-${_postId(post)}'),
                    post: post,
                    repository: widget.repository,
                  ),
              ],
            ),
          ];
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: _listPhysics(context),
      children: [
        if (warning != null) Notice(warning!),
        if (loading) const LinearProgressIndicator(),
        if (loadedOnce && rows.isEmpty)
          const Notice('No stories filed under this topic yet.'),
        ...cards,
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: page > 1 && !loading
                      ? () => load(target: page - 1)
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page $page of $pages'),
                TextButton(
                  onPressed: page < pages && !loading
                      ? () => load(target: page + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _FeedRowKind { masthead, notice, top, featured, promos, cards, tail }

class _FeedRow {
  const _FeedRow(this.kind, {this.posts = const [], this.keyPrefix = ''});
  final _FeedRowKind kind;
  final List<Json> posts;
  final String keyPrefix;
}

/// Latest stories with a top story, featured rows and a paged grid.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key, required this.repository});
  final Repository repository;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final items = <Json>[];
  int page = 0;
  int pages = 1;
  bool loading = false;
  bool loadedOnce = false;
  String? error;
  String? warning;
  late final Future<FeedResult> featured = widget.repository.feed(
    '/posts/featured',
  );
  late final ScrollController scroll = ScrollController()
    ..addListener(_settleOverscroll);
  ValueNotifier<bool>? _scrolling;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _scrolling?.removeListener(_settleIdle);
    scroll
      ..removeListener(_settleOverscroll)
      ..dispose();
    super.dispose();
  }

  /// A fast fling can land past a stale max extent when row heights settle;
  /// pull the offset back instead of stranding content above the viewport.
  void _settleOverscroll() {
    final scrolling = scroll.position.isScrollingNotifier;
    if (!identical(_scrolling, scrolling)) {
      _scrolling?.removeListener(_settleIdle);
      _scrolling = scrolling..addListener(_settleIdle);
    }
    _settleIdle();
  }

  void _settleIdle() {
    if (!mounted || !scroll.hasClients) return;
    final position = scroll.position;
    if (!position.hasContentDimensions) return;
    if (position.isScrollingNotifier.value) return;
    if (position.pixels > position.maxScrollExtent) {
      position.jumpTo(position.maxScrollExtent);
    }
  }

  Future<void> load({bool next = false}) async {
    if (loading) return;
    if (next && page >= pages) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final target = next ? page + 1 : 1;
      final result = await widget.repository.feed('/posts?page=$target');
      if (!mounted) return;
      final rows = List<Json>.from(result.body['data'] as List? ?? const []);
      setState(() {
        if (!next) {
          items.clear();
          page = 0;
        }
        page = (result.body['page'] as int?) ?? target;
        pages = (result.body['pages'] as int?) ?? page;
        for (final post in rows) {
          if (items.any((e) => '${e['id']}' == '${post['id']}')) continue;
          items.add(post);
        }
        warning = result.warning;
        loading = false;
        loadedOnce = true;
      });
      // Short feeds read better without paging controls.
      if (mounted && page < pages && items.length <= 12) {
        await load(next: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadedOnce = true;
        error = '$e';
      });
    }
  }

  List<_FeedRow> _rows(double width) {
    if (!loadedOnce && loading) return const [];
    if (error != null && items.isEmpty) {
      return const [_FeedRow(_FeedRowKind.tail)];
    }
    final rows = <_FeedRow>[const _FeedRow(_FeedRowKind.masthead)];
    if (warning != null) rows.add(const _FeedRow(_FeedRowKind.notice));
    if (items.isEmpty) return rows;
    rows.add(_FeedRow(_FeedRowKind.top, posts: [items.first]));
    if (items.length > 1) {
      rows.add(
        _FeedRow(
          _FeedRowKind.featured,
          posts: items.skip(1).take(2).toList(),
          keyPrefix: 'feature',
        ),
      );
    }
    rows.add(const _FeedRow(_FeedRowKind.promos));
    if (items.length > 3) {
      rows.addAll(
        _chunks(items.skip(3).take(4).toList(), _columns(width, 340)).map(
          (chunk) =>
              _FeedRow(_FeedRowKind.cards, posts: chunk, keyPrefix: 'compact'),
        ),
      );
    }
    if (items.length > 7) {
      rows.addAll(
        _chunks(items.skip(7).toList(), _columns(width, 400)).map(
          (chunk) =>
              _FeedRow(_FeedRowKind.cards, posts: chunk, keyPrefix: 'more'),
        ),
      );
    }
    rows.add(const _FeedRow(_FeedRowKind.tail));
    return rows;
  }

  int _columns(double width, double minWidth) =>
      (width / minWidth).floor().clamp(1, 3);

  List<List<Json>> _chunks(List<Json> posts, int columns) {
    final chunks = <List<Json>>[];
    for (var i = 0; i < posts.length; i += columns) {
      chunks.add(posts.skip(i).take(columns).toList());
    }
    return chunks;
  }

  Future<void> _openShop() async {
    final url = Uri.https('fayettevillethepeoplevoice.com', '/shop');
    try {
      if (!await launchUrl(url)) {
        if (mounted) message(context, 'The shop could not open.');
      }
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!loadedOnce && loading) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading news'),
        );
      }
      final rows = _rows(constraints.maxWidth);
      if (rows.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading news'),
        );
      }
      return ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: _listPhysics(context),
        // Keep editorial rows mounted across fast flings so row peers stay
        // measurable even when the viewport overshoots briefly.
        scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
        itemCount: rows.length,
        itemBuilder: (context, index) => _row(rows[index]),
      );
    },
  );

  Widget _row(_FeedRow row) {
    switch (row.kind) {
      case _FeedRowKind.masthead:
        return const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: BrandMasthead(),
        );
      case _FeedRowKind.notice:
        return Notice(warning!);
      case _FeedRowKind.top:
        final post = row.posts.single;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ArticleTile(
            key: const ValueKey('top-story-card'),
            post: post,
            repository: widget.repository,
            // Hero-sized cover: keeps the featured row below inside the
            // viewport when readers jump into the promotions section.
            coverHeight: 320,
          ),
        );
      case _FeedRowKind.featured:
      case _FeedRowKind.cards:
        return _cardRow(row);
      case _FeedRowKind.promos:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FEATURED POSTS',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              PromotionalFeatured(
                repository: widget.repository,
                data: featured,
                showHeading: false,
              ),
              const Notice('Promote my article · five dollars/week'),
              TextButton(
                onPressed: _openShop,
                child: const Text('Shop products'),
              ),
            ],
          ),
        );
      case _FeedRowKind.tail:
        if (error != null && items.isEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Notice('News could not load. $error'),
              OutlinedButton.icon(
                onPressed: load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          );
        }
        if (loadedOnce && items.isEmpty) {
          return const AppEmptyState(
            title: 'No stories yet',
            message: 'Check back soon for the latest community news.',
          );
        }
        if (page < pages) {
          return Center(
            child: loading
                ? const CircularProgressIndicator(
                    semanticsLabel: 'Loading more news',
                  )
                : OutlinedButton.icon(
                    onPressed: () => load(next: true),
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Load more news'),
                  ),
          );
        }
        if (loading) {
          return const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading more news',
            ),
          );
        }
        return const SizedBox.shrink();
    }
  }

  Widget _cardRow(_FeedRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final post in row.posts)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: post == row.posts.last ? 0 : 16),
              child: EditorialStoryCard(
                key: ValueKey('${row.keyPrefix}-${_postId(post)}'),
                post: post,
                repository: widget.repository,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Sign-in form and account summary.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.session});
  final Session session;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;
  bool busy = false;
  String? emailError;
  String? passwordError;
  String? error;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.session.removeListener(_refresh);
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> signIn() async {
    final address = email.text.trim();
    setState(() {
      emailError = address.contains('@') && address.contains('.')
          ? null
          : 'Enter a valid email address.';
      passwordError = password.text.isEmpty ? 'Enter your password.' : null;
      error = null;
    });
    if (emailError != null || passwordError != null) return;
    setState(() => busy = true);
    try {
      await widget.session.login(address, password.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
      message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    setState(() => busy = true);
    try {
      await widget.session.logout();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.session.userId;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (userId == null) ...[
                Text(
                  'Sign in to sync favorites, drafts and preferences across devices.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (error != null) Notice(error!, icon: Icons.error_outline),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    errorText: emailError,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: passwordError,
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : signIn,
                  child: Text(busy ? 'Signing in…' : 'Sign in'),
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(semanticsLabel: 'Signing in'),
                ],
              ] else ...[
                Text(
                  'Signed in as ${widget.session.username}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Notice(
                  'Favorites, drafts and preferences sync with this account.',
                  icon: Icons.cloud_done_outlined,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: busy ? null : signOut,
                  icon: const Icon(Icons.logout),
                  label: Text(busy ? 'Signing out…' : 'Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Offline reads and favorites kept on this device.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.repository});
  final Repository repository;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  Future<List<Json>>? saved;
  Future<List<Json>>? favorites;
  int? owner;

  @override
  void initState() {
    super.initState();
    widget.repository.session?.addListener(_accountChanged);
    reload();
  }

  @override
  void dispose() {
    widget.repository.session?.removeListener(_accountChanged);
    super.dispose();
  }

  void _accountChanged() {
    final current = widget.repository.session?.userId;
    if (current == owner) return;
    reload();
  }

  void reload() {
    setState(() {
      owner = widget.repository.session?.userId;
      saved = widget.repository.store.articles();
      favorites = owner == null
          ? Future.value(const <Json>[])
          : widget.repository.store.favoriteArticles(owner!);
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Saved'),
            Tab(text: 'Favorites'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          // A new account remounts the whole tab view: list futures and
          // keep-alive caches below must never leak across accounts.
          key: ValueKey('library-tabs-$owner'),
          children: [
            // Rebuild both lists from scratch when the account changes so no
            // stale snapshot survives behind the tab keep-alives.
            KeyedSubtree(
              key: ValueKey('saved-$owner'),
              child: FutureBuilder<List<Json>>(
                future: saved,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading saved stories',
                      ),
                    );
                  }
                  final rows = snapshot.data ?? const <Json>[];
                  if (rows.isEmpty) {
                    return const Center(
                      child: AppEmptyState(
                        title: 'Nothing saved yet',
                        message: 'Save stories for offline reading and they will wait here.',
                        icon: Icons.download_for_offline_outlined,
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) => ArticleTile(
                        key: ValueKey('saved-${_postId(rows[index])}'),
                        post: rows[index],
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
              ),
            ),
            KeyedSubtree(
              key: ValueKey('favorites-$owner'),
              child: FutureBuilder<List<Json>>(
                future: favorites,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading favorites',
                      ),
                    );
                  }
                  final rows = snapshot.data ?? const <Json>[];
                  if (rows.isEmpty) {
                    return const Center(
                      child: AppEmptyState(
                        title: 'Keep your favorites close',
                        message:
                            'Tap the bookmark on any story to keep it here.',
                        icon: Icons.bookmark_add_outlined,
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) => ArticleTile(
                        key: ValueKey('favorite-${rows[index]['id']}'),
                        post: rows[index],
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Paid promotion upsell shown from advertising entry points.
class AdvertisePage extends StatelessWidget {
  const AdvertisePage({
    super.key,
    required this.repository,
    required this.session,
  });
  final Repository repository;
  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final signedIn = session.userId != null;
      return Scaffold(
        appBar: AppBar(title: const Text('Advertise')),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 560,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Put your story in the spotlight.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Notice(
                  'Promoted stories appear in the featured section for one week.',
                  icon: Icons.campaign_outlined,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => signedIn
                          ? MyArticlesPage(
                              repository: repository,
                              session: session,
                            )
                          : AccountPage(session: session),
                    ),
                  ),
                  child: Text(
                    signedIn ? 'Choose an article' : 'Sign in to advertise',
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

const _sidebarEntries = [
  (0, 'News', Icons.newspaper),
  (1, 'For you', Icons.interests_outlined),
  (2, 'Community', Icons.groups_outlined),
  (3, 'Podcasts', Icons.podcasts_outlined),
  (5, 'Categories', Icons.grid_view_outlined),
  (6, 'My articles', Icons.article_outlined),
  (8, 'Library', Icons.bookmark_outline),
  (9, 'Account', Icons.person_outline),
];

/// Wide-window navigation mirroring the phone destinations.
class EditorialSidebar extends StatelessWidget {
  const EditorialSidebar({
    super.key,
    required this.index,
    required this.onSelect,
  });
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    var selected = 0;
    for (var i = 0; i < _sidebarEntries.length; i++) {
      if (_sidebarEntries[i].$1 == index) selected = i;
    }
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: (position) =>
          onSelect(_sidebarEntries[position].$1),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final entry in _sidebarEntries)
          NavigationRailDestination(
            icon: Icon(entry.$3),
            label: Text(entry.$2),
          ),
      ],
    );
  }
}

/// Overflow sections grouped behind the More destination.
class MoreMenu extends StatelessWidget {
  const MoreMenu({
    super.key,
    required this.repository,
    required this.session,
    this.onSelect,
  });
  final Repository repository;
  final Session session;

  /// When set, entries switch the shell tab instead of pushing a route.
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, IconData, Widget, int)>[
      (
        'Categories',
        Icons.grid_view_outlined,
        CategoriesPage(repository: repository),
        5,
      ),
      (
        'My articles',
        Icons.article_outlined,
        MyArticlesPage(repository: repository, session: session),
        6,
      ),
      (
        'Drafts',
        Icons.edit_note_outlined,
        DraftsPage(repository: repository, session: session),
        7,
      ),
      (
        'Library',
        Icons.bookmark_outline,
        LibraryPage(repository: repository),
        8,
      ),
      ('Contact', Icons.mail_outlined, ContactPage(api: repository.api), 10),
      (
        'News tips',
        Icons.lightbulb_outline,
        NewsTipsPage(repository: repository),
        11,
      ),
      (
        'Preferences',
        Icons.tune_outlined,
        PreferencesPage(repository: repository),
        12,
      ),
      ('Account', Icons.person_outline, AccountPage(session: session), 9),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in entries)
          ListTile(
            leading: Icon(entry.$2),
            title: Text(entry.$1),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final select = onSelect;
              if (select != null) {
                select(entry.$4);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => entry.$4 >= 5 && entry.$4 <= 8
                        ? Scaffold(
                            appBar: AppBar(title: Text(entry.$1)),
                            body: SafeArea(child: entry.$3),
                          )
                        : entry.$3,
                  ),
                );
              }
            },
          ),
      ],
    );
  }
}

/// App shell switching between phone, desktop and iPhone layouts.
class Home extends StatefulWidget {
  const Home({super.key, required this.repository, required this.session});
  final Repository repository;
  final Session session;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  static const _iosTabs = [0, 1, 3, 7];
  int index = 0;
  final built = <int>{0};
  final bodyKey = GlobalKey();
  late final PodcastApi podcastApi = PodcastApi();
  NotificationInbox? inbox;
  Timer? notificationTimer;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      WidgetsBinding.instance.addObserver(this);
      final notifications = _notifications();
      notifications.addListener(_inboxChanged);
      unawaited(notifications.refresh());
      notificationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == null || state == AppLifecycleState.resumed) {
          unawaited(notifications.refresh());
        }
      });
    }
  }

  void _inboxChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_notifications().refresh());
    }
  }

  void select(int value) => setState(() {
    index = value;
    built.add(value);
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationTimer?.cancel();
    inbox?.removeListener(_inboxChanged);
    inbox?.dispose();
    podcastApi.client.close();
    super.dispose();
  }

  NotificationInbox _notifications() => inbox ??= NotificationInbox(
    EditorialGateway(widget.repository.api, widget.session),
    widget.repository.store,
    preferences: widget.repository.experience,
    promotions: widget.repository.promotions,
  );

  void _openAccount() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountPage(session: widget.session),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _ios(context);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return MacosHome(repository: widget.repository, session: widget.session);
    }
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = <Widget>[
      FeedPage(repository: widget.repository),
      ForYouPage(repository: widget.repository),
      CommunityHub(repository: widget.repository),
      PodcastsPage(
        api: podcastApi,
        repository: widget.repository,
        onSignIn: _openAccount,
      ),
      MoreMenu(
        repository: widget.repository,
        session: widget.session,
        onSelect: select,
      ),
      CategoriesPage(repository: widget.repository),
      MyArticlesPage(repository: widget.repository, session: widget.session),
      DraftsPage(repository: widget.repository, session: widget.session),
      LibraryPage(repository: widget.repository),
      AccountPage(session: widget.session),
      ContactPage(api: widget.repository.api),
      NewsTipsPage(repository: widget.repository),
      PreferencesPage(repository: widget.repository),
    ];
    final visible = <Widget>[
      for (var i = 0; i < pages.length; i++)
        // Build destinations on first visit; IndexedStack keeps their state.
        built.contains(i) ? pages[i] : const SizedBox.shrink(),
    ];
    // The key keeps every destination alive when the shell switches
    // between the phone bar and the desktop sidebar on resize.
    final body = IndexedStack(
      key: bodyKey,
      index: index.clamp(0, pages.length - 1),
      children: visible,
    );
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              EditorialSidebar(index: index, onSelect: select),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index.clamp(0, 4),
        onDestinationSelected: select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            label: 'News',
            tooltip: 'News',
          ),
          NavigationDestination(
            icon: Icon(Icons.interests_outlined),
            label: 'For you',
            tooltip: 'For you',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Community',
            tooltip: 'Community',
          ),
          NavigationDestination(
            icon: Icon(Icons.podcasts_outlined),
            label: 'Podcasts',
            tooltip: 'Podcasts',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
            tooltip: 'More',
          ),
        ],
      ),
    );
  }

  Widget _ios(BuildContext context) {
    final position = _iosTabs.indexOf(index).clamp(0, _iosTabs.length - 1);
    Widget lazy(int slot, Widget child) =>
        built.contains(_iosTabs[slot]) ? child : const SizedBox.shrink();
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: position,
          children: [
            lazy(
              0,
              IphoneFeed(
                repository: widget.repository,
                unreadNotifications: inbox?.unread ?? 0,
                onAdvertise: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AdvertisePage(
                      repository: widget.repository,
                      session: widget.session,
                    ),
                  ),
                ),
                onAccount: _openAccount,
                onMore: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('More')),
                      body: SafeArea(
                        child: MoreMenu(
                          repository: widget.repository,
                          session: widget.session,
                        ),
                      ),
                    ),
                  ),
                ),
                onNotifications: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NotificationsPage(
                      inbox: _notifications(),
                      repository: widget.repository,
                    ),
                  ),
                ),
              ),
            ),
            lazy(1, CommunityHub(repository: widget.repository)),
            lazy(2, LibraryPage(repository: widget.repository)),
            lazy(
              3,
              PodcastsPage(
                api: podcastApi,
                repository: widget.repository,
                onSignIn: _openAccount,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: IphoneNavigation(
        index: _iosTabs[position],
        onSelect: select,
        onSearch: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SearchPage(repository: widget.repository),
          ),
        ),
      ),
    );
  }
}
