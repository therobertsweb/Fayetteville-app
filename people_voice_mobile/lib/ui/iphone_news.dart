import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/repository.dart';
import 'home.dart' show CategoryArticlesPage, Notice;
import 'reader.dart';

const newsAccent = Color(0xffff2d60);

ThemeData iphoneTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: newsAccent,
        brightness: brightness,
      ).copyWith(
        primary: newsAccent,
        onPrimary: Colors.white,
        onSurface: dark ? Colors.white : const Color(0xff1c1c1e),
        onSurfaceVariant: dark
            ? const Color(0xff98989f)
            : const Color(0xff636366),
        surface: dark ? const Color(0xff1c1c1e) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff242426)
            : const Color(0xfff2f2f7),
      );
  return ThemeData(
    useMaterial3: true,
    platform: TargetPlatform.iOS,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Colors.black : const Color(0xfff2f2f7),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? Colors.black : const Color(0xfff2f2f7),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
  );
}

/// A blurred capsule with a separate search control, above the home indicator.
class IphoneNavigation extends StatelessWidget {
  const IphoneNavigation({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onSearch,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;

  Widget glass(BuildContext context, Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(40),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .18),
          ),
        ),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: glass(
            context,
            Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  for (final item in const [
                    (0, CupertinoIcons.news_solid, 'Today'),
                    (7, CupertinoIcons.mic, 'Podcasts'),
                    (1, CupertinoIcons.square_grid_2x2, 'Community'),
                    (3, CupertinoIcons.bookmark, 'Saved'),
                  ])
                    Expanded(
                      child: Semantics(
                        selected: index == item.$1,
                        child: Material(
                          color: index == item.$1
                              ? Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: .10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(32),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(32),
                            onTap: () => onSelect(item.$1),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.$2,
                                    size: 24,
                                    color: index == item.$1 ? newsAccent : null,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.$3,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: index == item.$1
                                          ? newsAccent
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        glass(
          context,
          IconButton(
            constraints: const BoxConstraints(minWidth: 58, minHeight: 64),
            tooltip: 'Search',
            onPressed: onSearch,
            icon: const Icon(CupertinoIcons.search, size: 28),
          ),
        ),
      ],
    ),
  );
}

class IphoneFeed extends StatefulWidget {
  const IphoneFeed({
    super.key,
    required this.repository,
    required this.onAdvertise,
    required this.onAccount,
    required this.onMore,
    required this.onNotifications,
    this.unreadNotifications = 0,
  });
  final Repository repository;
  final VoidCallback onAdvertise, onAccount, onMore, onNotifications;
  final int unreadNotifications;
  @override
  State<IphoneFeed> createState() => _IphoneFeedState();
}

class _IphoneFeedState extends State<IphoneFeed> {
  List<Json> posts = [], sponsored = [];
  late final categories = widget.repository.categories();
  int page = 0, pages = 1;
  bool busy = false, promotionsBusy = false;
  String? warning, promotionsWarning;

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> loadPromotions() async {
    setState(() {
      promotionsBusy = true;
      promotionsWarning = null;
    });
    try {
      final result = await widget.repository.feed('/posts/featured');
      if (!mounted) return;
      setState(() {
        sponsored = List<Json>.from(result.body['data'] as List);
        promotionsWarning = result.warning;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => promotionsWarning = 'Promoted stories could not be refreshed. Pull down to try again.',
        );
      }
    } finally {
      if (mounted) setState(() => promotionsBusy = false);
    }
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      warning = null;
    });
    final promotions = reset ? loadPromotions() : Future<void>.value();
    try {
      final next = reset ? 1 : page + 1;
      final result = await widget.repository.feed('/posts?page=$next');
      if (!mounted) return;
      setState(() {
        final combined = [
          if (!reset) ...posts,
          ...List<Json>.from(result.body['data'] as List),
        ];
        posts = {for (final post in combined) post['id']: post}.values.toList();
        page = next;
        pages = result.body['pages'] as int? ?? 1;
        warning = result.warning;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => warning = 'Could not refresh the news. Check your connection and try again.',
        );
      }
    } finally {
      await promotions;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'FAYETTEVILLE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Notifications',
                onPressed: widget.onNotifications,
                icon: Badge.count(
                  count: widget.unreadNotifications,
                  isLabelVisible: widget.unreadNotifications > 0,
                  child: const Icon(CupertinoIcons.bell, size: 20),
                ),
              ),
              IconButton(
                tooltip: 'More options',
                onPressed: widget.onMore,
                icon: const Icon(CupertinoIcons.ellipsis, size: 22),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => load(reset: true),
            child: ListView(
              key: const PageStorageKey('iphone-news'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final brand = GestureDetector(
                      onTap: widget.onAccount,
                      child: Semantics(
                        button: true,
                        label: 'The People Voice account',
                        child: const Text(
                          'The People\nVoice',
                          style: TextStyle(
                            fontSize: 32,
                            height: .96,
                            letterSpacing: -1.4,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                    final advertise = FilledButton(
                      onPressed: widget.onAdvertise,
                      child: const Text('Advertise'),
                    );
                    if (constraints.maxWidth < 330 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          brand,
                          const SizedBox(height: 12),
                          advertise,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: brand),
                        const SizedBox(width: 10),
                        advertise,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '${months[now.month - 1]} ${now.day}',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                FutureBuilder<FeedResult>(
                  future: categories,
                  builder: (context, snapshot) {
                    final topics =
                        (snapshot.data?.body['data'] as List?)
                            ?.whereType<String>()
                            .toList() ??
                        [];
                    if (topics.isEmpty) return const SizedBox.shrink();
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final topic in topics)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surface,
                                side: BorderSide.none,
                                shape: const StadiumBorder(),
                                label: Text(
                                  topic,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => CategoryArticlesPage(
                                      repository: widget.repository,
                                      category: topic,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  'Top Stories',
                  style: TextStyle(
                    color: newsAccent,
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 14),
                if (warning != null) Notice(warning!),
                if (posts.isNotEmpty)
                  IphoneStory(
                    post: posts.first,
                    repository: widget.repository,
                    lead: true,
                  ),
                Container(
                  key: const ValueKey('weekly-promotions'),
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SPONSORED',
                        style: TextStyle(
                          color: newsAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Promoted this week',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (promotionsBusy)
                        const LinearProgressIndicator(
                          semanticsLabel: 'Loading promoted stories',
                        ),
                      if (promotionsWarning != null) Notice(promotionsWarning!),
                      if (!promotionsBusy &&
                          promotionsWarning == null &&
                          sponsored.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'No promoted stories this week. Put your published article in the spotlight.',
                          ),
                        ),
                      for (final post in sponsored)
                        IphoneStory(
                          key: ValueKey('promoted-${post['id']}'),
                          post: post,
                          repository: widget.repository,
                          sponsored: true,
                        ),
                      FilledButton.icon(
                        onPressed: widget.onAdvertise,
                        icon: const Icon(CupertinoIcons.speaker_2, size: 18),
                        label: const Text('Promote your article'),
                      ),
                    ],
                  ),
                ),

                if (posts.length > 1)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final pair = posts.skip(1).take(2).toList();
                      final columns =
                          constraints.maxWidth >= 340 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                      if (!columns) {
                        return Column(
                          children: [
                            for (final post in pair)
                              IphoneStory(
                                post: post,
                                repository: widget.repository,
                              ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < pair.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: IphoneStory(
                                post: pair[i],
                                repository: widget.repository,
                                tile: true,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                for (final post in posts.skip(3))
                  IphoneStory(post: post, repository: widget.repository),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!busy && posts.isEmpty)
                  const Notice(
                    'No stories available yet. Pull down to refresh. Your downloaded stories are in Saved.',
                  ),
                if (!busy && page < pages)
                  OutlinedButton(
                    onPressed: load,
                    child: const Text('More stories'),
                  ),
                if (!busy)
                  TextButton(
                    onPressed: () => load(reset: true),
                    child: const Text('Refresh news'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class IphoneStory extends StatefulWidget {
  const IphoneStory({
    super.key,
    required this.post,
    required this.repository,
    this.lead = false,
    this.tile = false,
    this.sponsored = false,
  });
  final Json post;
  final Repository repository;
  final bool lead, tile, sponsored;
  @override
  State<IphoneStory> createState() => _IphoneStoryState();
}

class _IphoneStoryState extends State<IphoneStory> {
  late Future<Json?> preview = widget.repository.preview(widget.post);
  @override
  void didUpdateWidget(covariant IphoneStory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      preview = widget.repository.preview(widget.post);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository.experience,
    builder: (context, _) => FutureBuilder<Json?>(
      future: preview,
      builder: (context, snapshot) {
        final post = {...widget.post, ...?snapshot.data};
        if (widget.repository.experience.blocked(
          post['author']?['id'] as int?,
        )) {
          return const SizedBox.shrink();
        }
        final source = widget.repository.imageUrl(
          post['photo_link'] as String?,
        );
        final title = post['title'] as String? ?? 'Story';
        final created = DateTime.tryParse(post['created'] as String? ?? '');
        final date = created == null
            ? 'Fayetteville'
            : MaterialLocalizations.of(context)
                  .formatShortDate(created.toLocal());
        final compact =
            !widget.lead &&
            !widget.tile &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.sponsored
                  ? 'THE PEOPLE VOICE · SPONSORED'
                  : 'THE PEOPLE VOICE',
              style: TextStyle(
                fontSize: widget.tile ? 10 : 12,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: widget.lead ? 25 : 20,
                fontWeight: FontWeight.w800,
                height: 1.13,
                letterSpacing: -.5,
              ),
            ),
          ],
        );
        Widget photo() => source == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: const Center(
                  child: Icon(CupertinoIcons.news, size: 44, color: newsAccent),
                ),
              )
            : OfflineImage(
                repository: widget.repository,
                source: source,
                fit: BoxFit.cover,
              );
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReaderPage(
                  repository: widget.repository,
                  id: post['id'] as int,
                  title: title,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact)
                  AspectRatio(
                    aspectRatio: widget.lead ? 4 / 3 : 1.35,
                    child: photo(),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      if (compact && source != null) ...[
                        const SizedBox(width: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 108,
                            height: 118,
                            child: photo(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          date,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Read story',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ReaderPage(
                              repository: widget.repository,
                              id: post['id'] as int,
                              title: title,
                            ),
                          ),
                        ),
                        icon: const Icon(
                          CupertinoIcons.arrow_up_right,
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
