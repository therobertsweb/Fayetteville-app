import 'package:flutter/material.dart';

import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/publisher.dart';
import '../data/repository.dart';
import 'article_editor.dart';
import 'brand.dart';
import 'home.dart';
import 'responsive.dart';

class AdminManagement extends StatefulWidget {
  const AdminManagement({
    super.key,
    required this.gateway,
    required this.store,
    required this.resource,
  });
  final EditorialGateway gateway;
  final LocalStore store;
  final String resource;
  @override
  State<AdminManagement> createState() => _AdminManagementState();
}

class _AdminManagementState extends State<AdminManagement> {
  late final operations = ManagementOperations(widget.gateway, widget.store);
  late final repository = Repository(
    widget.gateway.api,
    widget.store,
    session: widget.gateway.session,
  );
  List<Json> items = [];
  String query = '', role = 'all', status = 'all';
  String? error;
  bool loading = true, busy = false, pending = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.gateway.session.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    items = [];
    load();
  }

  @override
  void dispose() {
    widget.gateway.session.removeListener(accountChanged);
    super.dispose();
  }

  Future<void> load() async {
    final version = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.gateway.managementList(widget.resource);
      final receipt = await operations.pending();
      if (mounted && version == generation) {
        setState(() {
          items = result;
          pending = receipt != null;
        });
      }
    } catch (e) {
      if (mounted && version == generation) {
        setState(() {
          error = '$e';
          items = [];
        });
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  List<Json> get filtered => items.where((item) {
    final text =
        '${item['username'] ?? ''} ${item['email'] ?? ''} ${item['title'] ?? ''} ${item['name'] ?? ''} ${item['subject'] ?? ''} ${item['author']?['username'] ?? ''}'
            .toLowerCase();
    final matchesRole =
        role == 'all' || (item['role'] ?? item['author']?['role']) == role;
    final matchesState =
        status == 'all' ||
        (widget.resource == 'posts'
                ? (item['published'] == true ? 'published' : 'draft')
                : item['replied_at'] == null
                ? 'unanswered'
                : 'replied') ==
            status;
    return text.contains(query.toLowerCase()) && matchesRole && matchesState;
  }).toList();
  Future<void> change(Json item, Json changes, String summary) async {
    final owner = widget.gateway.session.userId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm change'),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (approved != true ||
        !mounted ||
        owner != widget.gateway.session.userId ||
        busy) {
      return;
    }
    setState(() => busy = true);
    try {
      if (widget.resource == 'posts' && changes['action'] == 'update') {
        final prepared = await Publisher(
          widget.gateway.api,
          widget.store,
        ).prepareMedia(changes, widget.gateway.session.token, persist: false);
        changes = {...prepared}..remove('uploaded_images');
      }
      await operations.run(widget.resource, item['id'] as int, {
        'version': item['version'],
        ...changes,
      });
      if (mounted) message(context, 'Change saved.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  Future<void> edit(Json item) async {
    final fields = widget.resource == 'users'
        ? ['username', 'email']
        : widget.resource == 'posts'
        ? [
            'title',
            'info',
            'tag_1',
            'tag_2',
            'title_2',
            'title_3',
            'subtitle',
            'subtitle_2',
            'photo_link',
            'categories',
            'content',
            'sponsor_name',
          ]
        : ['reply'];
    final controllers = {
      for (final key in fields)
        key: TextEditingController(text: '${item[key] ?? ''}'),
    };
    var selectedRole = item['role'] as String? ?? 'commenter';
    const labels = {
      'username': 'Username',
      'email': 'Email address',
      'title': 'Title',
      'info': 'Primary category',
      'tag_1': 'Secondary tag',
      'tag_2': 'Tag',
      'title_2': 'Short summary',
      'title_3': 'Secondary title',
      'subtitle': 'Homepage excerpt',
      'subtitle_2': 'Supporting description',
      'photo_link': 'Cover image URL',
      'categories': 'Categories',
      'content': 'Article body (HTML)',
      'sponsor_name': 'Sponsor name',
      'reply': 'Reply by email',
    };
    final route = DialogRoute<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            widget.resource == 'contacts'
                ? 'Reply to ${item['name']}'
                : 'Edit ${widget.resource == 'users' ? 'account' : 'article'}',
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.resource == 'contacts')
                    SelectableText(
                      'From: ${item['name']} <${item['email']}>\n${item['subject']}\n\n${item['message']}',
                    ),
                  if (widget.resource == 'users')
                    const Notice(
                      'Changing an email requires the user to verify it again. Account changes revoke existing sessions.',
                    ),
                  for (final key in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: key == 'content'
                          ? ArticleEditor(
                              controller: controllers[key]!,
                              repository: repository,
                            )
                          : key == 'photo_link'
                          ? CoverImageEditor(
                              controller: controllers[key]!,
                              repository: repository,
                            )
                          : TextField(
                              controller: controllers[key],
                              minLines: ['content', 'reply'].contains(key)
                                  ? 6
                                  : 1,
                              maxLines: ['content', 'reply'].contains(key)
                                  ? 16
                                  : 2,
                              maxLength: key == 'content'
                                  ? 100000
                                  : key == 'reply'
                                  ? 5000
                                  : key == 'title'
                                  ? 100
                                  : key == 'username'
                                  ? 50
                                  : key == 'email'
                                  ? 120
                                  : key == 'categories'
                                  ? 500
                                  : ['tag_1', 'tag_2'].contains(key)
                                  ? 200
                                  : ['title_2', 'title_3'].contains(key)
                                  ? 1000
                                  : key == 'sponsor_name'
                                  ? 150
                                  : 2000,
                              decoration: InputDecoration(
                                labelText: labels[key],
                              ),
                            ),
                    ),
                  if (widget.resource == 'users')
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: roleNames.entries
                          .map(
                            (role) => DropdownMenuItem(
                              value: role.key,
                              child: Text(role.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => update(() => selectedRole = value!),
                    ),
                  if (widget.resource == 'posts')
                    const Notice(
                      'Paid placements are managed in Paid promotions after payment confirmation.',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'action': widget.resource == 'contacts' ? 'reply' : 'update',
                for (final entry in controllers.entries)
                  entry.key: entry.value.text.trim(),
                if (widget.resource == 'users') 'role': selectedRole,
              }),
              child: const Text('Review changes'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (result != null && mounted) {
      await change(
        item,
        result,
        widget.resource == 'contacts'
            ? 'Send this reply to ${item['email']}?\n\n${result['reply']}'
            : 'Save these changes to ${item['username'] ?? item['title']}?${widget.resource == 'users' ? '\nRole: ${roleName(result['role'] as String)}\nEmail: ${result['email']}' : ''}',
      );
    }
  }

  Future<void> shareWithBuffer(Json item) async {
    if (busy || pending || item['published'] != true) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish on social media'),
        content: Text(
          'Send “${item['title']}” to the connected social media channels? Existing delivery records prevent duplicate posts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await widget.gateway.shareWithBuffer(item);
      final data = result['data'] as Json;
      if (mounted) {
        message(
          context,
          (data['errors'] as List).isNotEmpty
              ? 'The article is published on the website, but social media delivery could not be confirmed.'
              : data['created'] as int > 0
              ? 'Your article was published successfully on social media.'
              : 'The article was already sent to social media or is awaiting confirmation.',
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  String get pageTitle => switch (widget.resource) {
    'users' => 'Accounts',
    'posts' => 'All articles',
    'roles' => 'Roles & permissions',
    _ => 'Contact inbox',
  };

  String get description => switch (widget.resource) {
    'users' => 'Find accounts and manage access to the community.',
    'posts' => 'Review, edit and manage articles across the newsroom.',
    'roles' => 'Review account roles and publishing permissions.',
    _ => 'Read messages from the community and reply by email.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      leadingWidth: 56,
      title: Text(pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Refresh records',
          onPressed: loading || busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (MediaQuery.sizeOf(context).width < 600)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Management'),
                  ),
                ),
              ),
            SectionHeading(
              pageTitle,
              eyebrow: 'MANAGEMENT',
              subtitle: description,
            ),
            if (pending) ...[
              const Notice(
                'An earlier change is unconfirmed. Check its result before continuing.',
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await operations.reconcile();
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        } finally {
                          if (mounted) {
                            setState(() => busy = false);
                            await load();
                          }
                        }
                      },
                child: const Text('Check previous change'),
              ),
            ],
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            if (['users', 'posts'].contains(widget.resource))
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in {'all': 'All roles', ...roleNames}.entries)
                    ChoiceChip(
                      label: Text(r.value),
                      selected: role == r.key,
                      onSelected: (_) => setState(() => role = r.key),
                    ),
                ],
              ),
            if (['posts', 'contacts'].contains(widget.resource))
              Wrap(
                spacing: 8,
                children: [
                  for (final state
                      in widget.resource == 'posts'
                          ? ['all', 'draft', 'published']
                          : ['all', 'unanswered', 'replied'])
                    ChoiceChip(
                      label: Text(
                        state == 'all'
                            ? 'All statuses'
                            : '${state[0].toUpperCase()}${state.substring(1)}',
                      ),
                      selected: status == state,
                      onSelected: (_) => setState(() => status = state),
                    ),
                ],
              ),
            if (loading || busy) const LinearProgressIndicator(),
            if (error != null) Notice(error!),
            if (!loading && filtered.isEmpty)
              const Notice('No matching records.'),
            for (final item in filtered)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['username'] ?? item['title'] ?? item['subject'] ?? item['name']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (widget.resource == 'roles')
                        Text(
                          '${item['count']} accounts · ${item['can_publish'] == true ? 'Can publish articles' : 'Cannot publish by role'}',
                        ),
                      if (widget.resource == 'users')
                        Text(
                          '${item['email']}\n${roleName(item['role'] as String)} · ${item['is_banned'] == true ? 'Banned' : 'Active'} · ${item['email_verified'] == true ? 'Verified email' : 'Unverified email'} · ${item['posts_count']} articles',
                        ),
                      if (widget.resource == 'posts')
                        Text(
                          '${item['author']['username']} · ${roleName(item['author']['role'] as String)} · ${item['published'] == true ? 'Published' : 'Draft'}',
                        ),
                      if (widget.resource == 'contacts') ...[
                        Text('${item['name']} · ${item['email']}'),
                        SelectableText('${item['message']}'),
                        if (item['reply_message'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SelectableText(
                              'Reply (${item['replied_at']}):\n${item['reply_message']}',
                            ),
                          ),
                      ],
                      if (widget.resource != 'roles')
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              onPressed: busy || pending
                                  ? null
                                  : () => edit(item),
                              child: Text(
                                widget.resource == 'contacts'
                                    ? 'Reply by email'
                                    : 'Edit',
                              ),
                            ),
                            if (widget.resource == 'users')
                              TextButton(
                                onPressed: busy || pending
                                    ? null
                                    : () => change(
                                        item,
                                        {
                                          'action': 'update',
                                          'is_banned':
                                              item['is_banned'] != true,
                                        },
                                        '${item['is_banned'] == true ? 'Unban' : 'Ban'} ${item['username']}? Existing sessions will be revoked.',
                                      ),
                                child: Text(
                                  item['is_banned'] == true ? 'Unban' : 'Ban',
                                ),
                              ),
                            if (widget.resource == 'posts')
                              TextButton(
                                onPressed: busy || pending
                                    ? null
                                    : () => change(
                                        item,
                                        {
                                          'action': item['published'] == true
                                              ? 'unpublish'
                                              : 'publish',
                                        },
                                        '${item['published'] == true ? 'Unpublish' : 'Publish'} “${item['title']}”?',
                                      ),
                                child: Text(
                                  item['published'] == true
                                      ? 'Unpublish'
                                      : 'Publish',
                                ),
                              ),
                            if (widget.resource == 'posts' &&
                                item['published'] == true)
                              TextButton.icon(
                                onPressed: busy || pending
                                    ? null
                                    : () => shareWithBuffer(item),
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Social media'),
                              ),
                            TextButton(
                              onPressed: busy || pending
                                  ? null
                                  : () => change(
                                      item,
                                      {'action': 'delete'},
                                      'Delete ${item['username'] ?? item['title'] ?? item['subject']}?${widget.resource == 'users' ? '\nThis removes account access and personal details and unpublishes their articles.' : '\nThis cannot be undone.'}',
                                    ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            TextButton(
              onPressed: loading || busy ? null : load,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    ),
  );
}
