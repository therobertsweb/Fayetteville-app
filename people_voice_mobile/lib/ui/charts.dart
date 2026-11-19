import 'package:flutter/material.dart';

import '../data/local_store.dart';

/// Horizontal bars keep long article titles readable on phones and desktops.
class ArticleRankingChart extends StatelessWidget {
  const ArticleRankingChart({
    super.key,
    required this.items,
    required this.metric,
    this.onOpen,
  });
  final List<Json> items;
  final String metric;
  final ValueChanged<Json>? onOpen;

  @override
  Widget build(BuildContext context) {
    final ranked = [...items]
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    final maximum = ranked.fold<int>(
      1,
      (value, row) =>
          (row['count'] as int) > value ? row['count'] as int : value,
    );
    final unit = metric == 'comments' ? 'comments' : 'favorites';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric == 'comments'
                  ? 'Most commented articles'
                  : 'Most favorited articles',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Top 10 in the selected period.'),
            const SizedBox(height: 16),
            if (ranked.isEmpty) const Text('No activity in this period yet.'),
            for (final row in ranked.take(10))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  label: '${row['article']['title']}: ${row['count']} $unit',
                  child: InkWell(
                    onTap: onOpen == null
                        ? null
                        : () => onOpen!(row['article'] as Json),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['article']['title']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${row['count']} $unit',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, box) => Container(
                              height: 12,
                              width: box.maxWidth,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width:
                                    box.maxWidth *
                                    (row['count'] as int) /
                                    maximum,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
