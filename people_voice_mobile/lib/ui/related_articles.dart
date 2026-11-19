import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'home.dart';
import 'responsive.dart';

/// Public stories sharing the current article's topics, without paid duplicates.
class RelatedArticles extends StatefulWidget {
  const RelatedArticles({
    super.key,
    required this.repository,
    required this.article,
    required this.promoted,
  });
  final Repository repository;
  final Json article;
  final Future<FeedResult> promoted;

  @override
  State<RelatedArticles> createState() => _RelatedArticlesState();
}

class _RelatedArticlesState extends State<RelatedArticles> {
  late Future<FeedResult> data = load();

  Future<FeedResult> load() async {
    final topics = Repository.articleCategories(widget.article)
        .toSet()
        .take(3)
        .toList();
    if (topics.isEmpty) return FeedResult({'data': <Json>[]});
    final excluded = <String>{'${widget.article['id']}'};
    try {
      final promotions = await widget.promoted;
      for (final post in List<Json>.from(
        promotions.body['data'] as List? ?? [],
      )) {
        excluded.add('${post['id']}');
      }
    } catch (_) {
      // Recommendations remain available when paid placements cannot load.
    }
    final matches = <String, Json>{};
    var failed = false;
    final warnings = <String>{};
    final normalized = topics.map((s) => s.toLowerCase()).toSet();
    for (final topic in topics) {
      try {
        final result = await widget.repository.categoryArticles(topic);
        if (result.warning != null) warnings.add(result.warning!);
        for (final post in List<Json>.from(
          result.body['data'] as List? ?? [],
        )) {
          final id = '${post['id']}';
          if (excluded.contains(id) || post['published'] == false) continue;
          if (!Repository.articleCategories(post)
              .any((s) => normalized.contains(s.toLowerCase()))) {
            continue;
          }
          matches.putIfAbsent(id, () => post);
        }
      } catch (_) {
        failed = true;
      }
    }
    if (failed && matches.isEmpty) {
      throw Exception('Related stories could not load.');
    }
    final rows = matches.values.toList();
    int score(Json post) =>
        Repository.articleCategories(post)
            .where((s) => normalized.contains(s.toLowerCase()))
            .length;
    rows.sort((a, b) {
      final relevance = score(b).compareTo(score(a));
      return relevance != 0
          ? relevance
          : '${b['created'] ?? ''}'.compareTo('${a['created'] ?? ''}');
    });
    return FeedResult({
      'data': rows.take(6).toList(),
    }, warning: warnings.isEmpty ? null : warnings.join(' '));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionHeading(
        'Related articles',
        subtitle: 'Keep reading stories on the same topics.',
      ),
      FutureBuilder<FeedResult>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                const Text('Related stories could not load.'),
                TextButton(
                  onPressed: () => setState(() => data = load()),
                  child: const Text('Try again'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = List<Json>.from(snapshot.data!.body['data'] as List);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.data!.warning != null)
                Notice(snapshot.data!.warning!),
              if (posts.isEmpty)
                const Text('No other stories on these topics yet.'),
              ArticleColumns(
                minWidth: 260,
                children: [
                  for (final post in posts)
                    EditorialStoryCard(
                      post: post,
                      repository: widget.repository,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}
