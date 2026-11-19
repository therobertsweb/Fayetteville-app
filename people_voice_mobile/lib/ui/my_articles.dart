import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/publisher.dart';
import '../data/promotions.dart';
import '../data/repository.dart';
import 'article_editor.dart';
import 'drafts.dart';
import 'home.dart' show Notice, message;
import 'reader.dart';

class MyArticlesPage extends StatefulWidget {
  const MyArticlesPage({
    super.key,
    required this.repository,
    required this.session,
    this.showServer = false,
  });
  final Repository repository;
  final Session session;
  final bool showServer;
  @override
  State<MyArticlesPage> createState() => _MyArticlesPageState();
}

class _MyArticlesPageState extends State<MyArticlesPage> {
  late bool submitted = widget.showServer;
  late Future<List<Json>> data = load();
  int? loadedOwner;
  @override
  void initState() {
    super.initState();
    loadedOwner = widget.session.userId;
    widget.session.addListener(accountChanged);
  }

  void accountChanged() {
    if (loadedOwner == widget.session.userId) return;
    loadedOwner = widget.session.userId;
    if (mounted) {
      setState(() {
        data = load();
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(accountChanged);
    super.dispose();
  }

  Future<List<Json>> load() async {
    if (widget.session.expired) return [];
    final owner = widget.session.userId;
    final token = widget.session.token;
    final rows = <Json>[];
    String? cursor;
    final seen = <String>{};
    for (var page = 0; page < 100; page++) {
      final result = await widget.repository.api.request(
        '/me/posts${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
        token: token,
      );
      if (owner != widget.session.userId) return [];
      rows.addAll(List<Json>.from(result['data'] as List));
      cursor = result['next_cursor'] as String?;
      if (cursor == null) {
        final articles = rows.reversed.toList();
        if (widget.repository.promotions != null) {
          try {
            final purchases = await widget.repository.promotions!.mine(token);
            final newest = <int, Json>{};
            for (final purchase in purchases) {
              final articleId = purchase['article']?['id'];
              if (articleId is int) {
                newest.putIfAbsent(articleId, () => purchase);
              }
            }
            for (final article in articles) {
              final purchase = newest[article['id']];
              if (purchase != null) {
                article['app_promotion_status'] = purchase['status'];
                article['app_promotion_ends_at'] = purchase['ends_at'];
              }
            }
          } catch (_) {
            // Articles remain available while the independent service is down.
          }
        }
        return articles;
      }
      if (!seen.add(cursor)) break;
    }
    throw ApiFailure(
      'Could not load the complete article list. Please refresh and try again.',
    );
  }

  void refresh() => setState(() {
    data = load();
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Device drafts')),
            ButtonSegment(value: true, label: Text('My server articles')),
          ],
          selected: {submitted},
          onSelectionChanged: (v) => setState(() {
            submitted = v.first;
            data = load();
          }),
        ),
      ),
      Expanded(
        child: !submitted
            ? DraftsPage(repository: widget.repository, session: widget.session)
            : FutureBuilder<List<Json>>(
                key: ValueKey(loadedOwner),
                future: data,
                builder: (context, snapshot) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'My articles',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    TextButton.icon(
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    if (widget.session.expired)
                      const Notice(
                        'Sign in to see your articles on all devices.',
                      ),
                    if (snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator(),
                    if (snapshot.hasError)
                      Notice('Could not load your articles. ${snapshot.error}'),
                    if (snapshot.hasData &&
                        snapshot.data!.isEmpty &&
                        !widget.session.expired)
                      const Notice(
                        'No server articles yet. Your device drafts are in the first tab.',
                      ),
                    for (final post in snapshot.data ?? <Json>[])
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${post['title']}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                '${post['status']} · Reads: ${post['views']} · Comments: ${post['comment_count']}',
                              ),
                              if (post['featured_until'] != null &&
                                  (post['promotion_status'] == 'approved' ||
                                      post['promotion_status'] == null))
                                Text(
                                  'Sponsored placement through ${post['featured_until']}',
                                ),
                              if (post['promotion_status'] == 'pending')
                                const Text(
                                  'Payment confirmed · awaiting editorial approval',
                                ),
                              if (post['promotion_status'] == 'rejected')
                                const Text(
                                  'Promotion declined · contact the newsroom about your payment',
                                ),
                              if (post['app_promotion_status'] == 'pending')
                                const Text(
                                  'Payment confirmed · administrators have been notified',
                                ),
                              if (post['app_promotion_status'] == 'approved')
                                Text(
                                  'App promotion active through ${post['app_promotion_ends_at']}',
                                ),
                              if (post['app_promotion_status'] == 'rejected')
                                const Text(
                                  'Paid promotion declined · contact the newsroom about your payment',
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (post['status'] == 'draft')
                                    TextButton(
                                      onPressed: () async {
                                        try {
                                          await widget.repository.api.request(
                                            '/me/posts/${post['id']}/review',
                                            body: {},
                                            token: widget.session.token,
                                          );
                                          if (mounted) refresh();
                                        } catch (e) {
                                          if (context.mounted) {
                                            message(context, e);
                                          }
                                        }
                                      },
                                      child: const Text(
                                        'Request newsroom review',
                                      ),
                                    ),
                                  if (post['published'] == true)
                                    TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ReaderPage(
                                            repository: widget.repository,
                                            id: post['id'],
                                            title: post['title'],
                                          ),
                                        ),
                                      ),
                                      child: const Text('Read'),
                                    ),
                                  if (post['can_edit'] == true)
                                    TextButton(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => OwnArticleEditor(
                                              repository: widget.repository,
                                              post: post,
                                            ),
                                          ),
                                        );
                                        if (mounted) refresh();
                                      },
                                      child: const Text('Edit'),
                                    ),
                                  if (post['published'] == true)
                                    OutlinedButton(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => PromotionPage(
                                              repository: widget.repository,
                                              post: post,
                                            ),
                                          ),
                                        );
                                        if (mounted) refresh();
                                      },
                                      child: const Text('Promote article'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    ],
  );
}

class PromotionPage extends StatefulWidget {
  const PromotionPage({
    super.key,
    required this.repository,
    required this.post,
  });
  final Repository repository;
  final Json post;
  @override
  State<PromotionPage> createState() => _PromotionPageState();
}

class _PromotionPageState extends State<PromotionPage> {
  late final PromotionApi promotionApi =
      widget.repository.promotions ?? PromotionApi();
  late Future<Json> pricing = promotionApi.pricing();
  bool busy = false;
  String? warning;
  Future<void> checkout() async {
    if (busy) return;
    setState(() => busy = true);
    final session = widget.repository.session;
    try {
      if (session == null || session.expired) {
        throw ApiFailure('Sign in before promoting your article.');
      }
      final owner = session.userId;
      final token = session.token;
      final key = 'checkout:$owner:${widget.post['id']}';
      final previous = await widget.repository.store.cached(key);
      var identifier = previous?['operation_id'] as String? ?? operationId();
      if (previous != null) {
        final purchases = await promotionApi.mine(token);
        if (purchases.any(
          (purchase) =>
              purchase['operation_id'] == identifier &&
              (purchase['payment_status'] == 'paid' ||
                  purchase['status'] == 'failed'),
        )) {
          identifier = operationId();
        }
      }
      await widget.repository.store.cache(key, {'operation_id': identifier});
      final url = await promotionApi.checkout(
        articleId: widget.post['id'] as int,
        token: token,
        operationId: identifier,
      );
      if (session.userId != owner) {
        throw ApiFailure('Your account changed. Open the promotion again.');
      }
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw ApiFailure(
          'Could not open Stripe Checkout. Retry to open the same payment session.',
        );
      }
      if (mounted) {
        setState(
          () => warning = 'Complete payment in Stripe, then return to the app. Only a payment confirmed by Stripe sends your article and account to administrators for review.',
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Promote your article')),
    body: FutureBuilder<Json>(
      future: pricing,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${widget.post['title']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (snapshot.connectionState != ConnectionState.done)
            const LinearProgressIndicator(),
          if (snapshot.hasError) Notice('${snapshot.error}'),
          if (snapshot.data?['data'] case final Map price) ...[
            Text(
              '${(price['currency'] as String).toUpperCase()} ${(price['amount_cents'] / 100).toStringAsFixed(2)} · ${price['days']} days',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Notice(
              'One-time payment, not a subscription. After payment, the newsroom must approve your article before its Sponsored placement begins. No card details are stored by this app.',
            ),
            FilledButton(
              onPressed:
                  busy ||
                      price['available'] != true ||
                      price['review_enabled'] != true
                  ? null
                  : checkout,
              child: Text(
                busy ? 'Opening secure checkout…' : 'Continue to Stripe',
              ),
            ),
            if (price['available'] != true)
              const Notice(
                'Promotion payments are not configured on the app service yet.',
              ),
            if (price['available'] == true && price['review_enabled'] != true)
              const Notice(
                'The app service must confirm that payment review is enabled before Checkout can start.',
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final approved = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Start a separate checkout?'),
                          content: const Text(
                            'First check My articles for an active promotion. Starting again can create another payment. Use only after an expired or completed checkout.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Start new'),
                            ),
                          ],
                        ),
                      );
                      if (approved != true || !mounted) return;
                      final owner = widget.repository.session?.userId;
                      await widget.repository.store.cache(
                        'checkout:$owner:${widget.post['id']}',
                        {'operation_id': operationId()},
                      );
                      if (mounted) {
                        setState(
                          () => warning = 'A new checkout is ready. Continue to Stripe when you are ready.',
                        );
                      }
                    },
              child: const Text('Previous checkout expired or completed?'),
            ),
          ],
          if (warning != null) Notice(warning!),
        ],
      ),
    ),
  );
}

class OwnArticleEditor extends StatefulWidget {
  const OwnArticleEditor({
    super.key,
    required this.repository,
    required this.post,
  });
  final Repository repository;
  final Json post;
  @override
  State<OwnArticleEditor> createState() => _OwnArticleEditorState();
}

class _OwnArticleEditorState extends State<OwnArticleEditor> {
  late final title = TextEditingController(text: widget.post['title']);
  late final content = TextEditingController(text: widget.post['content']);
  late final categories = TextEditingController(
    text: widget.post['categories'] as String? ?? '',
  );
  bool busy = false;
  bool restoring = true, saved = false, conflict = false;
  Json? pending;
  late final owner = widget.repository.session?.userId;
  late String baseVersion = widget.post['version'] as String;
  late String cover = widget.post['photo_link'] as String? ?? '';
  String get key => 'own-edit:$owner:${widget.post['id']}';
  Future<void> writes = Future.value();
  String? localError;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    try {
      final cached = await widget.repository.store.cached(key);
      if (!mounted) return;
      if (cached != null && cached.isNotEmpty) {
        title.text = cached['title'];
        content.text = cached['content'];
        categories.text = cached['categories'];
        pending = cached['pending'] == null
            ? null
            : Map<String, dynamic>.from(cached['pending']);
        baseVersion = cached['base_version'] as String? ?? baseVersion;
        cover = cached['photo_link'] as String? ?? cover;
      }
    } catch (_) {
      localError =
          'Could not restore local edits. Keep this screen open until saved.';
    } finally {
      if (mounted) {
        for (final c in [title, content, categories]) {
          c.addListener(changed);
        }
        setState(() => restoring = false);
      }
    }
  }

  Future<void> persist() {
    final snapshot = {
      'title': title.text,
      'content': content.text,
      'categories': categories.text,
      'pending': pending,
      'base_version': baseVersion,
      'photo_link': cover,
    };
    final operation = writes.then(
      (_) => widget.repository.store.cache(key, snapshot),
    );
    writes = operation.catchError((Object _) {});
    return operation;
  }

  void changed() {
    if (restoring || saved) return;
    persist().catchError((Object _) {
      if (mounted) {
        setState(
          () => localError = 'Device storage could not save these edits. Keep this screen open.',
        );
      }
    });
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    categories.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || restoring) return;
    setState(() => busy = true);
    try {
      final session = widget.repository.session!;
      final token = session.token;
      if (session.userId != owner || owner != widget.post['author']['id']) {
        throw ApiFailure('Sign in with the article owner account.');
      }
      if (pending == null) {
        final media =
            await Publisher(
              widget.repository.api,
              widget.repository.store,
            ).prepareMedia(
              {
                ...widget.post,
                'title': title.text.trim(),
                'content': content.text,
                'photo_link': cover,
              },
              token,
              persist: false,
            );
        pending = {
          'operation_id': operationId(),
          'version': baseVersion,
          'title': media['title'],
          'content': media['content'],
          'photo_link': media['photo_link'],
          'categories': categories.text.trim(),
        };
      }
      await persist();
      final response = await widget.repository.api.request(
        '/me/posts/${widget.post['id']}',
        body: pending,
        token: token,
      );
      if (response['data']?['published'] == true) {
        await widget.repository.store.saveArticle(
          Map<String, dynamic>.from(response['data']),
        );
      }
      saved = true;
      await writes;
      await widget.repository.store.cache(key, {});
      if (mounted) {
        message(context, 'Article saved.');
        Navigator.pop(context);
      }
    } catch (e) {
      conflict = e is ApiFailure && e.status == 409;
      if (e is ApiFailure && !e.uncertain) {
        pending = null;
        await persist();
      }
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reloadServer() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace local edits with the server version?'),
        content: const Text(
          'Copy any text you want to keep first. This discards the edits saved on this device for this article.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reload server version'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      final session = widget.repository.session!;
      if (session.userId != owner) throw ApiFailure('Your account changed.');
      final response = await widget.repository.api.request(
        '/me/posts/${widget.post['id']}',
        token: session.token,
      );
      if (!mounted || session.userId != owner) return;
      final post = response['data'] as Json;
      pending = null;
      baseVersion = post['version'];
      cover = post['photo_link'] as String? ?? '';
      title.text = post['title'];
      content.text = post['content'];
      categories.text = post['categories'] ?? '';
      conflict = false;
      await persist();
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit my article')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Notice(
          'Edits are kept on this device until you save them to the server. Published articles stay public. Keep this screen open until saving finishes.',
        ),
        if (restoring) const LinearProgressIndicator(),
        if (localError != null) Notice(localError!),
        if (conflict) ...[
          const Notice(
            'The server version changed. Your edits are still saved locally; copy any text you want to keep before reloading.',
          ),
          TextButton(
            onPressed: busy ? null : reloadServer,
            child: const Text('Reload current server article'),
          ),
        ],
        TextField(
          controller: title,
          maxLength: 100,
          readOnly: restoring || busy || pending != null,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        TextField(
          controller: categories,
          readOnly: restoring || busy || pending != null,
          decoration: const InputDecoration(
            labelText: 'Categories (comma-separated)',
          ),
        ),
        ArticleEditor(
          controller: content,
          repository: widget.repository,
          readOnly: restoring || busy || pending != null,
        ),
        FilledButton(
          onPressed: restoring || busy ? null : save,
          child: Text(
            busy
                ? 'Saving…'
                : pending == null
                ? 'Save changes'
                : 'Retry same save',
          ),
        ),
      ],
    ),
  );
}
