import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'reader.dart';

/// Complete cards rotate in readable groups; no paid placement is truncated away.
class PromotionCarousel extends StatefulWidget {
  const PromotionCarousel({
    super.key,
    required this.posts,
    required this.repository,
  });
  final List<Json> posts;
  final Repository repository;

  @override
  State<PromotionCarousel> createState() => _PromotionCarouselState();
}

class _PromotionCarouselState extends State<PromotionCarousel>
    with WidgetsBindingObserver {
  final controller = PageController();
  Timer? timer;
  int page = 0, columns = 1;
  String? layout;
  bool paused = false,
      hovered = false,
      focused = false,
      touching = false,
      active = true;
  int get groups => widget.posts.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted ||
          paused ||
          hovered ||
          focused ||
          touching ||
          !active ||
          groups <= 1) {
        return;
      }
      if (MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context) ||
          !TickerMode.valuesOf(context).enabled ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.overlaps(Offset.zero & MediaQuery.sizeOf(context))) return;
      advance(1);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
  }

  void advance(int delta) {
    if (!controller.hasClients ||
        controller.position.isScrollingNotifier.value) {
      return;
    }
    final target = page + delta;
    if (target < 0) {
      controller.jumpToPage(groups - 1);
    } else if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(target);
    } else {
      controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        columns = (constraints.maxWidth / (265 * scale)).floor().clamp(1, 3);
        final nextLayout =
            '$columns:${widget.posts.map((post) => post['id']).join(',')}';
        if (layout != nextLayout) {
          layout = nextLayout;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !controller.hasClients) return;
            controller.jumpToPage(0);
            if (page != 0) setState(() => page = 0);
          });
        }
        final height = 230.0 * scale;
        return MouseRegion(
          onEnter: (_) => hovered = true,
          onExit: (_) => hovered = false,
          child: Focus(
            onFocusChange: (value) => focused = value,
            child: Listener(
              onPointerDown: (_) => touching = true,
              onPointerUp: (_) => touching = false,
              onPointerCancel: (_) => touching = false,
              child: Column(
                children: [
                  SizedBox(
                    height: height,
                    child: PageView.builder(
                      controller: controller,
                      onPageChanged: (value) => setState(() => page = value),
                      itemCount: groups <= 1 ? 1 : null,
                      itemBuilder: (context, index) {
                        final start = index % groups;
                        final posts = groups > 1
                            ? List.generate(
                                columns.clamp(1, widget.posts.length),
                                (offset) =>
                                    widget.posts[(start + offset) %
                                        widget.posts.length],
                              )
                            : widget.posts;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < columns; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                child: i < posts.length
                                    ? PromotionStoryCard(
                                        post: posts[i],
                                        repository: widget.repository,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  if (groups > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${page % groups + 1} / $groups',
                              semanticsLabel:
                                  'Promotion group ${page % groups + 1} of $groups',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Previous promotions',
                            onPressed: () => advance(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          IconButton(
                            tooltip: paused
                                ? 'Play promotions'
                                : 'Pause promotions',
                            onPressed: () => setState(() => paused = !paused),
                            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                          ),
                          IconButton(
                            tooltip: 'Next promotions',
                            onPressed: () => advance(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
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
}

class PromotionStoryCard extends StatelessWidget {
  const PromotionStoryCard({
    super.key,
    required this.post,
    required this.repository,
  });
  final Json post;
  final Repository repository;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.newspaper_outlined)),
    );
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.circle, size: 12, color: Brand.red),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'THE PEOPLE VOICE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.campaign_outlined,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${post['title']}',
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox.expand(
                          child: FutureBuilder<Uint8List?>(
                            future: repository.image(
                              '${post['photo_link'] ?? ''}',
                            ),
                            builder: (context, snapshot) =>
                                snapshot.data == null || snapshot.data!.isEmpty
                                ? placeholder
                                : Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, error, stack) =>
                                        placeholder,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sponsored · 7 days',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
