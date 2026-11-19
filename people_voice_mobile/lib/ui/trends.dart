import 'package:flutter/material.dart';

import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'charts.dart';
import 'reader.dart';
import 'home.dart';

class TrendsPage extends StatefulWidget {
  const TrendsPage({
    super.key,
    required this.gateway,
    required this.repository,
  });
  final EditorialGateway gateway;
  final Repository repository;
  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  String metric = 'comments';
  int days = 30;
  Future<List<Json>>? data;
  @override
  void initState() {
    super.initState();
    if (widget.gateway.enabled) data = widget.gateway.rankings(metric, days);
  }

  void reload() => setState(() {
    if (widget.gateway.enabled) data = widget.gateway.rankings(metric, days);
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SectionHeading(
        'What is happening in Fayetteville',
        eyebrow: 'Community favorites',
        subtitle: 'Discover the stories that spark conversation and that readers save most.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in [
            ('comments', 'Most commented'),
            ('saves', 'Most favorited'),
          ])
            ChoiceChip(
              label: Text(item.$2),
              selected: metric == item.$1,
              onSelected: (_) {
                metric = item.$1;
                reload();
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [7, 30, 90]
            .map(
              (value) => ChoiceChip(
                label: Text('$value days'),
                selected: days == value,
                onSelected: (_) {
                  days = value;
                  reload();
                },
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 20),
      if (!widget.gateway.enabled)
        const Notice(
          'Community statistics are currently unavailable. Try refreshing when connected.',
        ),
      if (data != null)
        FutureBuilder<List<Json>>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) return Notice('${snapshot.error}');
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return const Notice('No statistics for this period.');
            }
            return ArticleRankingChart(
              items: items,
              metric: metric,
              onOpen: (article) => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReaderPage(
                    repository: widget.repository,
                    id: article['id'] as int,
                    title: article['title'] as String,
                  ),
                ),
              ),
            );
          },
        ),
      TextButton(
        onPressed: widget.gateway.enabled ? reload : null,
        child: const Text('Refresh'),
      ),
    ],
  );
}
