import 'responsive.dart';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'charts.dart';
import 'home.dart';
import 'admin_management.dart';
import 'community_admin.dart';
import 'promotion_review.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.gateway, required this.store});
  final EditorialGateway gateway;
  final LocalStore store;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final operations = AdminOperations(widget.gateway, widget.store);
  Capabilities capabilities = const Capabilities();
  List<Json> drafts = [];
  Json? stats, pending, integrations;
  List<Json> bufferChannels = [];
  String? error, statsError, integrationError;
  String role = 'all', search = '';
  int days = 30, tab = 0;
  bool loading = true, busy = false;
  final selected = <int>{};
  int loadVersion = 0;
  List<Json> get filtered => drafts
      .where(
        (d) =>
            (role == 'all' || d['author']['role'] == role) &&
            ('${d['title']} ${d['author']['username']}').toLowerCase().contains(
              search.toLowerCase(),
            ),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    widget.gateway.session.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    setState(() {
      capabilities = const Capabilities();
      drafts = [];
      stats = null;
      pending = null;
      integrations = null;
      bufferChannels = [];
      selected.clear();
    });
    load();
  }

  @override
  void dispose() {
    widget.gateway.session.removeListener(accountChanged);
    super.dispose();
  }

  Future<void> load() async {
    final version = ++loadVersion;
    setState(() {
      loading = true;
      error = null;
      statsError = null;
      integrationError = null;
      selected.clear();
    });
    try {
      final access = await widget.gateway.capabilities();
      final items = access.review ? await widget.gateway.drafts() : <Json>[];
      Json? statistics;
      if (access.analytics) {
        try {
          statistics = await widget.gateway.statistics(days);
        } catch (e) {
          statsError = '$e';
        }
      }
      Json? serviceStatus;
      if (access.role == 'admin') {
        try {
          serviceStatus = await widget.gateway.integrations();
        } catch (e) {
          integrationError = '$e';
        }
      }
      final receipt = access.review ? await operations.pending() : null;
      if (mounted && version == loadVersion) {
        setState(() {
          capabilities = access;
          drafts = items;
          stats = statistics;
          pending = receipt;
          integrations = serviceStatus;
        });
      }
    } catch (e) {
      if (mounted && version == loadVersion) {
        setState(() {
          error = '$e';
          capabilities = const Capabilities();
          drafts = [];
          stats = null;
        });
      }
    } finally {
      if (mounted && version == loadVersion) setState(() => loading = false);
    }
  }

  Future<void> checkBuffer() async {
    setState(() {
      busy = true;
      integrationError = null;
    });
    try {
      final result = await widget.gateway.bufferChannels();
      if (mounted) setState(() => bufferChannels = result);
    } catch (e) {
      if (mounted) setState(() => integrationError = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(String action, List<Json> items) async {
    if (items.isEmpty || busy || loading || pending != null) return;
    final owner = widget.gateway.session.userId;
    final deleting = action == 'delete';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${deleting ? 'Delete' : 'Publish'} ${items.length} ${items.length == 1 ? 'draft' : 'drafts'}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deleting
                    ? 'These drafts will be deleted from the server. This cannot be undone in the app.'
                    : 'These articles will be published under their original authors.',
              ),
              const SizedBox(height: 12),
              ...items.map(
                (d) => Text('• ${d['title']} — ${d['author']['username']}'),
              ),

              const SizedBox(height: 12),
              Text(
                'Scope: ${role == 'all' ? 'all roles' : roleName(role)}. Only the ${items.length} articles listed in this confirmation are included.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              deleting ? 'Delete permanently' : 'Confirm publication',
            ),
          ),
        ],
      ),
    );
    if (approved != true ||
        !mounted ||
        widget.gateway.session.userId != owner) {
      return;
    }
    setState(() => busy = true);
    try {
      final result = await operations.run(action, items);
      if (mounted) await showResults(result);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  Future<void> showResults(Json result) async {
    final results = List<Json>.from(result['results'] as List);
    final ok = results.where((r) => r['success'] == true).length;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$ok of ${results.length} completed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Failed articles are not resubmitted automatically.'),
              ...results
                  .where((r) => r['success'] != true)
                  .map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Article ${r['id']}: ${r['message'] ?? 'Could not complete.'}',
                      ),
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> reconcile() async {
    setState(() => busy = true);
    try {
      final result = await operations.reconcile();
      if (mounted) await showResults(result);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  void preview(Json draft) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              draft['title'] as String,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '${draft['author']['username']} · ${roleName(draft['author']['role'] as String)}',
            ),
            const Divider(height: 32),
            SelectableText(
              html.parse(draft['content'] as String? ?? '').body?.text ?? '',
              style: const TextStyle(fontSize: 17, height: 1.6),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  selected.add(draft['id'] as int);
                });
              },
              child: const Text('Select for management'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Administration'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: loading || busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Drafts'),
                    icon: Icon(Icons.inventory_2_outlined),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Statistics'),
                    icon: Icon(Icons.bar_chart),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text('Services'),
                    icon: Icon(Icons.hub_outlined),
                  ),
                ],
                selected: {tab},
                onSelectionChanged: (values) =>
                    setState(() => tab = values.first),
              ),
            ),
            if (loading || busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (error != null) Notice(error!),
                  if (!loading &&
                      !capabilities.review &&
                      !capabilities.analytics) ...[
                    const SectionHeading(
                      'Your editorial desk',
                      eyebrow: 'Administration',
                    ),
                    Notice(
                      widget.gateway.enabled
                          ? 'Sign in with an authorized administrator account to continue.'
                          : 'Admin tools are unavailable. Check your connection and account permissions.',
                    ),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Review articles by role',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Authors · Editors · Moderators · Administrators · Readers · Advertisers',
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Select multiple articles to publish or delete, review individual results and explore author statistics.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (tab == 0 && capabilities.review)
                    ...reviewWidgets()
                  else if (tab == 1 && capabilities.analytics) ...[
                    const SectionHeading(
                      'Your team activity',
                      eyebrow: 'Publications',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [7, 30, 90]
                          .map(
                            (value) => ChoiceChip(
                              label: Text('$value days'),
                              selected: days == value,
                              onSelected: loading || busy
                                  ? null
                                  : (_) {
                                      days = value;
                                      load();
                                    },
                            ),
                          )
                          .toList(),
                    ),
                    if (statsError != null) Notice(statsError!),
                    if (stats != null) AdminCharts(data: stats!),
                  ] else if (tab == 2 && capabilities.role == 'admin')
                    ...serviceWidgets(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> serviceWidgets() => [
    Card(
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        title: const Text('Paid promotions'),
        subtitle: Text(
          capabilities.role == 'admin'
              ? 'Review paid articles before they appear in Stories promoted this week.'
              : 'Administrator access is required.',
        ),
        trailing: capabilities.role == 'admin'
            ? const Icon(Icons.chevron_right)
            : null,
        onTap: capabilities.role == 'admin'
            ? () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PromotionReviewPage(
                    gateway: widget.gateway,
                    repository: Repository(
                      widget.gateway.api,
                      widget.store,
                      session: widget.gateway.session,
                    ),
                  ),
                ),
              )
            : null,
      ),
    ),
    const SectionHeading(
      'Connected services',
      eyebrow: 'Administration',
      subtitle:
          'Server credentials stay private and are never sent to this app.',
    ),
    if (integrationError != null) Notice(integrationError!),
    Card(
      child: ListTile(
        leading: const Icon(Icons.auto_awesome_outlined),
        title: const Text('OpenAI writing assistant'),
        subtitle: Text(
          integrations?['openai']?['configured'] == true
              ? 'Configured · ${integrations?['openai']?['model']}'
              : 'Not configured on the server',
        ),
        trailing: Icon(
          integrations?['openai']?['configured'] == true
              ? Icons.check_circle_outline
              : Icons.error_outline,
        ),
      ),
    ),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Social media publishing'),
            subtitle: Text(
              integrations?['social_media']?['configured'] == true
                  ? 'Configured · ${integrations?['social_media']?['mode']}'
                  : 'Not configured on the server',
            ),
            trailing: Icon(
              integrations?['social_media']?['configured'] == true
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
            ),
          ),
          if (integrations?['social_media']?['configured'] == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : checkBuffer,
                  icon: const Icon(Icons.sync),
                  label: const Text('Check connected social channels'),
                ),
              ),
            ),
          for (final channel in bufferChannels)
            ListTile(
              dense: true,
              title: Text(channel['name'] as String),
              subtitle: Text(channel['service'] as String),
            ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    Text('Management', style: Theme.of(context).textTheme.titleLarge),
    Card(
      child: ListTile(
        leading: const Icon(Icons.location_city_outlined),
        title: const Text('Community & newsroom'),
        subtitle: const Text(
          'Story submissions, reports, events and businesses',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CommunityAdminPage(
              gateway: widget.gateway,
              store: widget.store,
            ),
          ),
        ),
      ),
    ),
    const SizedBox(height: 8),
    for (final entry in const {
      'users': ('Accounts', Icons.people_outline),
      'posts': ('All articles', Icons.article_outlined),
      'roles': ('Roles and permissions', Icons.badge_outlined),
      'contacts': ('Contact inbox', Icons.inbox_outlined),
    }.entries)
      Card(
        child: ListTile(
          leading: Icon(entry.value.$2),
          title: Text(entry.value.$1),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AdminManagement(
                gateway: widget.gateway,
                store: widget.store,
                resource: entry.key,
              ),
            ),
          ),
        ),
      ),
  ];

  List<Widget> reviewWidgets() {
    final items = filtered;
    final roles =
        drafts.map((d) => d['author']['role'] as String).toSet().toList()
          ..sort();
    final active = !loading && !busy && pending == null;
    return [
      const SectionHeading(
        'Ready for review',
        eyebrow: 'Community drafts',
        subtitle:
            'Review articles and decide which to share with Fayetteville.',
      ),
      if (pending != null) ...[
        Notice(
          'An operation involving ${pending!['count']} articles is unconfirmed. Check its result before continuing.',
        ),
        OutlinedButton(
          onPressed: busy ? null : reconcile,
          child: const Text('Check previous operation'),
        ),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          ChoiceChip(
            label: const Text('All roles'),
            selected: role == 'all',
            onSelected: busy
                ? null
                : (_) => setState(() {
                    role = 'all';
                    selected.clear();
                  }),
          ),
          ...roles.map(
            (r) => ChoiceChip(
              label: Text(roleName(r)),
              selected: role == r,
              onSelected: busy
                  ? null
                  : (_) => setState(() {
                      role = r;
                      selected.clear();
                    }),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        decoration: const InputDecoration(
          labelText: 'Search by title or author',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() {
          search = value;
          selected.clear();
        }),
        enabled: !busy,
      ),
      const SizedBox(height: 12),
      Text('${items.length} drafts · ${selected.length} selected'),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: !active
                ? null
                : () => setState(() {
                    if (selected.length == items.length) {
                      selected.clear();
                    } else {
                      selected.addAll(items.map((d) => d['id'] as int));
                    }
                  }),
            child: Text(
              selected.length == items.length && items.isNotEmpty
                  ? 'Clear selection'
                  : 'Select all',
            ),
          ),
          FilledButton(
            onPressed: active && selected.isNotEmpty
                ? () => act(
                    'publish',
                    items.where((d) => selected.contains(d['id'])).toList(),
                  )
                : null,
            child: const Text('Publish selected'),
          ),
          OutlinedButton(
            onPressed: active && selected.isNotEmpty
                ? () => act(
                    'delete',
                    items.where((d) => selected.contains(d['id'])).toList(),
                  )
                : null,
            child: const Text('Delete selected'),
          ),
          TextButton(
            onPressed: active && items.isNotEmpty
                ? () => act('publish', items)
                : null,
            child: Text('Publish all (${items.length})'),
          ),
          TextButton(
            onPressed: active && items.isNotEmpty
                ? () => act('delete', items)
                : null,
            child: Text('Delete all (${items.length})'),
          ),
        ],
      ),
      if (items.isEmpty) const Notice('No drafts match this selection.'),
      for (final r in roles.where(
        (r) => items.any((d) => d['author']['role'] == r),
      )) ...[
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(
            roleName(r),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final author
            in (items
                .where((d) => d['author']['role'] == r)
                .map((d) => d['author']['username'] as String)
                .toSet()
                .toList()
              ..sort())) ...[
          CheckboxListTile(
            title: Text(
              author,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${items.where((d) => d['author']['role'] == r && d['author']['username'] == author).length} drafts',
            ),
            value: items
                .where(
                  (d) =>
                      d['author']['role'] == r &&
                      d['author']['username'] == author,
                )
                .every((d) => selected.contains(d['id'])),
            onChanged: !active
                ? null
                : (checked) => setState(() {
                    final ids = items
                        .where(
                          (d) =>
                              d['author']['role'] == r &&
                              d['author']['username'] == author,
                        )
                        .map((d) => d['id'] as int);
                    if (checked == true) {
                      selected.addAll(ids);
                    } else {
                      selected.removeAll(ids);
                    }
                  }),
          ),
          ...items
              .where(
                (d) =>
                    d['author']['role'] == r &&
                    d['author']['username'] == author,
              )
              .map(
                (d) => Card(
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: selected.contains(d['id']),
                        onChanged: !active
                            ? null
                            : (checked) => setState(() {
                                if (checked == true) {
                                  selected.add(d['id'] as int);
                                } else {
                                  selected.remove(d['id']);
                                }
                              }),
                        title: Text(d['title'] as String),
                        subtitle: Text(
                          '${d['author']['username']} · ${d['created'] ?? ''}',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy ? null : () => preview(d),
                          child: const Text('Review article'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    ];
  }
}

class AdminCharts extends StatelessWidget {
  const AdminCharts({super.key, required this.data});
  final Json data;
  @override
  Widget build(BuildContext context) {
    final authors = List<Json>.from(
      data['by_author'] as List,
    )..sort((a, b) => (b['published'] as int).compareTo(a['published'] as int));
    final max = authors.isEmpty
        ? 1
        : (authors.first['published'] as int).clamp(1, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in [
              ('Published articles', data['published']),
              ('Pending drafts', data['drafts']),
              ('Active authors', data['active_authors']),
            ])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.$2}',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 28,
                          color: Brand.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(item.$1),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (data['most_saved'] is List)
          ArticleRankingChart(
            items: List<Json>.from(data['most_saved']),
            metric: 'saves',
          ),
        if (data['most_commented'] is List)
          ArticleRankingChart(
            items: List<Json>.from(data['most_commented']),
            metric: 'comments',
          ),
        const SizedBox(height: 24),
        Text(
          'Publications by user',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Up to 20 authors, ordered by articles published in this period.',
        ),
        const SizedBox(height: 16),
        if (authors.isEmpty)
          const Notice('No publications in this period yet.'),
        ...authors
            .take(20)
            .map(
              (author) => Semantics(
                label:
                    '${author['username']}: ${author['published']} published articles',
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${author['username']} · ${roleName(author['role'] as String)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text('${author['published']}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          minHeight: 16,
                          value: (author['published'] as int) / max,
                          color: Theme.of(context).colorScheme.secondary,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
