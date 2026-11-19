import 'package:flutter/material.dart';

import '../data/local_store.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'home.dart';
import 'responsive.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository});
  final Repository repository;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final query = TextEditingController();
  List<Json> results = [];
  String term = '', warning = '';
  bool busy = false, searched = false, failed = false;
  int page = 0, pages = 1, generation = 0;

  void clear() {
    generation++;
    query.clear();
    setState(() {
      results = [];
      term = warning = '';
      busy = searched = failed = false;
      page = 0;
      pages = 1;
    });
  }

  Future<void> search({bool more = false}) async {
    if (more && (busy || !searched || page >= pages)) return;
    final text = more ? term : query.text.trim();
    if (text.isEmpty) {
      clear();
      return;
    }
    FocusScope.of(context).unfocus();
    final nextPage = more ? page + 1 : 1;
    final version = ++generation;
    setState(() {
      term = text;
      busy = searched = true;
      failed = false;
      warning = '';
      if (!more) {
        results = [];
        page = 0;
        pages = 1;
      }
    });
    try {
      final data = await widget.repository.search(text, page: nextPage);
      if (!mounted || version != generation) return;
      final combined = <int, Json>{
        if (more)
          for (final post in results) post['id'] as int: post,
        for (final post in List<Json>.from(data.body['data'] as List))
          post['id'] as int: post,
      };
      setState(() {
        results = combined.values.toList();
        page = data.body['page'] as int? ?? nextPage;
        pages = data.body['pages'] as int? ?? page;
        warning = data.warning ?? '';
      });
    } catch (_) {
      if (mounted && version == generation) {
        setState(() {
          warning = 'Could not search. Check your connection and try again.';
          failed = true;
        });
      }
    } finally {
      if (mounted && version == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search')),
    body: SafeArea(
      child: ContentWidth(
        maxWidth: 1240,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            const SectionHeading(
              'Find your next story',
              eyebrow: 'THE ARCHIVE',
              subtitle:
                  'Explore the people, places and ideas shaping Fayetteville.',
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: query,
              builder: (context, value, _) => TextField(
                controller: query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                maxLength: 200,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  labelText: 'Articles, topics or authors',
                  prefixIcon: const Icon(Icons.search),
                  counterText: '',
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: clear,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : () => search(),
                icon: const Icon(Icons.search),
                label: Text(busy ? 'Searching…' : 'Search'),
              ),
            ),
            const SizedBox(height: 16),
            if (busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Searching articles',
              ),
            if (warning.isNotEmpty) Notice(warning),
            if (failed)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => search(more: results.isNotEmpty),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            if (!searched)
              const AppEmptyState(
                icon: Icons.manage_search_outlined,
                title: 'A whole community to discover',
                message: 'Search by a headline, a favorite writer or a topic. Articles saved on this device are searchable offline, too.',
              ),
            if (searched && !busy && results.isEmpty && !failed)
              AppEmptyState(
                icon: Icons.search_off_outlined,
                title: 'No stories found for “$term”',
                message: 'Try a shorter phrase, a different spelling or another topic.',
              ),
            if (results.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${results.length} ${results.length == 1 ? 'story' : 'stories'} for “$term”',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ArticleColumns(
                children: results
                    .map(
                      (post) => ArticleTile(
                        key: ValueKey(post['id']),
                        post: post,
                        repository: widget.repository,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (!busy && searched && results.isNotEmpty && page < pages)
              OutlinedButton.icon(
                onPressed: () => search(more: true),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more results'),
              ),
          ],
        ),
      ),
    ),
  );
}
