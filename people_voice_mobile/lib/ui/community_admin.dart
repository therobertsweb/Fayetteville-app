import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/editorial.dart';
import '../data/local_store.dart';
import 'home.dart' show Notice, message;

/// All permissions are checked again by the server, including private photos.
class CommunityAdminPage extends StatefulWidget {
  const CommunityAdminPage({
    super.key,
    required this.gateway,
    required this.store,
  });
  final EditorialGateway gateway;
  final LocalStore store;
  @override
  State<CommunityAdminPage> createState() => _CommunityAdminPageState();
}

class _CommunityAdminPageState extends State<CommunityAdminPage> {
  String kind = 'submissions';
  late Future<List<Json>> data = load();
  Future<List<Json>> load() async {
    final owner = widget.gateway.session.userId;
    final token = widget.gateway.session.token;
    final route = kind == 'submissions'
        ? '/admin/submissions'
        : '/admin/directory/$kind';
    final rows = <Json>[];
    String? cursor;
    do {
      final response = await widget.gateway.api.request(
        '$route${cursor == null ? '' : '?cursor=$cursor'}',
        token: token,
      );
      if (widget.gateway.session.userId != owner) return [];
      rows.addAll(List<Json>.from(response['data'] as List));
      cursor = response['next_cursor'] as String?;
    } while (cursor != null);
    return rows.reversed.toList();
  }

  Future<void> edit(Json? row) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CommunityReviewForm(
          gateway: widget.gateway,
          store: widget.store,
          kind: kind,
          row: row,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        data = load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Community & newsroom')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['submissions', 'events', 'businesses'])
              ChoiceChip(
                label: Text(value),
                selected: value == kind,
                onSelected: (_) => setState(() {
                  kind = value;
                  data = load();
                }),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => setState(() {
                data = load();
              }),
              icon: const Icon(Icons.refresh),
            ),
            if (kind != 'submissions')
              FilledButton.icon(
                onPressed: () => edit(null),
                icon: const Icon(Icons.add),
                label: const Text('Create listing'),
              ),
          ],
        ),
        FutureBuilder<List<Json>>(
          future: data,
          builder: (context, snapshot) => Column(
            children: [
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator(),
              if (snapshot.hasError) Notice('${snapshot.error}'),
              if (snapshot.hasData && snapshot.data!.isEmpty)
                const Notice('No records yet.'),
              for (final row in snapshot.data ?? <Json>[])
                Card(
                  child: ListTile(
                    title: Text('${row['title'] ?? row['name']}'),
                    subtitle: Text(
                      kind == 'submissions'
                          ? '${row['kind']} · ${row['status']}'
                          : (row['approved'] == true || row['verified'] == true
                                ? 'Public listing'
                                : 'Awaiting approval'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => edit(row),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CommunityReviewForm extends StatefulWidget {
  const CommunityReviewForm({
    super.key,
    required this.gateway,
    required this.store,
    required this.kind,
    this.row,
  });
  final EditorialGateway gateway;
  final LocalStore store;
  final String kind;
  final Json? row;
  @override
  State<CommunityReviewForm> createState() => _CommunityReviewFormState();
}

class _CommunityReviewFormState extends State<CommunityReviewForm> {
  final fields = <String, TextEditingController>{};
  late final int? owner = widget.gateway.session.userId;
  late String status = widget.row?['status'] as String? ?? 'received';
  late bool approved =
      widget.row?['approved'] == true || widget.row?['verified'] == true;
  late bool free = widget.row?['is_free'] == true,
      family = widget.row?['family_friendly'] == true;
  bool busy = false, restoring = true;
  Json? pending;
  late Future<Json> cities = widget.gateway.api.request(
    '/admin/directory/cities',
    token: widget.gateway.session.token,
  );
  int? city;
  String get cacheKey =>
      'community-admin:$owner:${widget.kind}:${widget.row?['id'] ?? 'new'}';
  bool get submission => widget.kind == 'submissions';
  TextEditingController field(String name) => fields.putIfAbsent(
    name,
    () => TextEditingController(text: '${widget.row?[name] ?? ''}'),
  );
  @override
  void initState() {
    super.initState();
    city = widget.row?['city_id'] as int?;
    restore();
  }

  Future<void> restore() async {
    try {
      final saved = await widget.store.cached(cacheKey);
      if (!mounted) return;
      if (saved != null && saved.isNotEmpty) {
        pending = saved;
        for (final entry in saved.entries) {
          if (entry.value is String) field(entry.key).text = entry.value;
        }
        status = saved['status'] as String? ?? status;
        city = saved['city_id'] as int? ?? city;
        approved = saved['approved'] == true || saved['verified'] == true;
        free = saved['is_free'] == true;
        family = saved['family_friendly'] == true;
      }
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || restoring) return;
    setState(() => busy = true);
    try {
      if (widget.gateway.session.userId != owner) {
        throw ApiFailure('Your account changed. Reopen this screen.');
      }
      final token = widget.gateway.session.token;
      pending ??= {
        'operation_id': operationId(),
        if (widget.row != null) 'version': widget.row!['version'],
        if (submission) ...{
          'status': status,
          'note': field('note').text.trim(),
          if (status == 'published')
            'article_id': int.tryParse(field('article_id').text),
        } else ...{
          'city_id': city,
          for (final entry in fields.entries)
            entry.key: entry.value.text.trim(),
          if (widget.kind == 'events') ...{
            'approved': approved,
            'is_free': free,
            'family_friendly': family,
          } else
            'verified': approved,
        },
      };
      await widget.store.cache(cacheKey, pending!);
      final route = submission
          ? '/admin/submissions/${widget.row!['id']}'
          : '/admin/directory/${widget.kind}${widget.row == null ? '' : '/${widget.row!['id']}'}';
      await widget.gateway.api.request(route, token: token, body: pending);
      await widget.store.cache(cacheKey, {});
      if (mounted) {
        message(context, 'Saved.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (e is ApiFailure && !e.uncertain) {
        pending = null;
        await widget.store.cache(cacheKey, {});
      }
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showPhoto() async {
    try {
      final response = await widget.gateway.api.client
          .get(
            Api.site.resolve('/api/v1/submissions/${widget.row!['id']}/photo'),
            headers: {
              'Authorization': 'Bearer ${widget.gateway.session.token}',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ApiFailure('Could not load the private photo.');
      }
      final Uint8List bytes = response.bodyBytes;
      if (!mounted || widget.gateway.session.userId != owner) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: SizedBox(
            width: 600,
            height: 400,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = busy || restoring || pending != null;
    Widget input(String name, String label, {int lines = 1}) => TextField(
      controller: field(name),
      readOnly: disabled,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 12,
      decoration: InputDecoration(labelText: label),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(submission ? 'Review submission' : 'Directory listing'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (restoring) const LinearProgressIndicator(),
          if (submission) ...[
            Text(
              '${widget.row!['title']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SelectableText('${widget.row!['body']}'),
            if (widget.row!['location'] != '')
              Text('Location: ${widget.row!['location']}'),
            if (widget.row!['target_id'] != null)
              Text(
                'Related ${widget.row!['kind']} ID: ${widget.row!['target_id']}',
              ),
            if (widget.row!['has_photo'] == true)
              TextButton(
                onPressed: showPhoto,
                child: const Text('View private photo'),
              ),
            const Notice(
              'Review the information before publishing or changing a listing. Marking a request resolved does not automatically edit or delete its subject.',
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(status),
              initialValue: status,
              items: ['received', 'in_review', 'published', 'resolved']
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.replaceAll('_', ' ')),
                    ),
                  )
                  .toList(),
              onChanged: disabled ? null : (v) => setState(() => status = v!),
            ),
            input('note', 'Update visible to the sender', lines: 3),
            if (status == 'published')
              input('article_id', 'ID of the published article'),
          ] else ...[
            FutureBuilder<Json>(
              future: cities,
              builder: (context, snapshot) => snapshot.hasError
                  ? Notice('${snapshot.error}')
                  : DropdownButtonFormField<int>(
                      initialValue: city,
                      decoration: const InputDecoration(labelText: 'City'),
                      items: [
                        for (final item
                            in snapshot.data?['data'] as List? ?? [])
                          DropdownMenuItem<int>(
                            value: item['id'],
                            child: Text(item['name']),
                          ),
                      ],
                      onChanged: disabled
                          ? null
                          : (v) => setState(() => city = v),
                    ),
            ),
            input(widget.kind == 'events' ? 'title' : 'name', 'Name'),
            input('description', 'Description', lines: 4),
            if (widget.kind == 'events') ...[
              input('location', 'Venue / address'),
              input('starts_at', 'Start: YYYY-MM-DDTHH:MM (Fayetteville time)'),
              input('ends_at', 'End (optional)'),
              input('organizer_url', 'Organizer HTTPS URL'),
              SwitchListTile(
                title: const Text('Free admission'),
                value: free,
                onChanged: disabled ? null : (v) => setState(() => free = v),
              ),
              SwitchListTile(
                title: const Text('Family friendly'),
                value: family,
                onChanged: disabled ? null : (v) => setState(() => family = v),
              ),
            ] else ...[
              input('slug', 'Unique URL slug (lowercase-with-hyphens)'),
              input('category', 'Activity / category'),
              input('address', 'Address'),
              input('phone', 'Phone'),
              input('website', 'Website URL'),
              input('opening_hours', 'Opening hours', lines: 3),
            ],
            SwitchListTile(
              title: const Text('Approved for public listing'),
              value: approved,
              onChanged: disabled ? null : (v) => setState(() => approved = v),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy || restoring ? null : save,
            child: Text(
              busy
                  ? 'Saving…'
                  : pending == null
                  ? 'Save'
                  : 'Retry same operation',
            ),
          ),
        ],
      ),
    );
  }
}
