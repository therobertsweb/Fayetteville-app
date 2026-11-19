import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/local_store.dart';
import '../data/editorial.dart';
import '../data/article_media.dart';
import '../data/api.dart';
import 'home.dart' show Notice, message;
import 'reader.dart' show OfflineImage;

class NewsTipsPage extends StatefulWidget {
  const NewsTipsPage({
    super.key,
    required this.repository,
    this.kind = 'news_tip',
    this.targetId,
    this.initialTitle = '',
    this.initialBody = '',
  });
  final Repository repository;
  final String kind, initialTitle, initialBody;
  final int? targetId;
  @override
  State<NewsTipsPage> createState() => _NewsTipsPageState();
}

class _NewsTipsPageState extends State<NewsTipsPage> {
  late final title = TextEditingController(text: widget.initialTitle);
  late final body = TextEditingController(text: widget.initialBody);
  final location = TextEditingController();
  String? photo;
  Json? pending;
  bool busy = false;
  late final int? owner = widget.repository.session?.userId;
  late Future<List<Json>> submissions = load();
  String get cacheKey =>
      'submission-pending:$owner:${widget.kind}:${widget.targetId}';
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final saved = await widget.repository.store.cached(cacheKey);
    if (!mounted || saved == null || saved.isEmpty) return;
    setState(() {
      pending = saved;
      title.text = saved['title'];
      body.text = saved['body'];
      location.text = saved['location'] ?? '';
    });
  }

  Future<List<Json>> load() async {
    final session = widget.repository.session;
    if (session == null || session.expired || session.userId != owner) {
      return [];
    }
    final token = session.token;
    final rows = <Json>[];
    String? cursor;
    do {
      final result = await widget.repository.api.request(
        '/me/submissions${cursor == null ? '' : '?cursor=$cursor'}',
        token: token,
      );
      if (session.userId != owner) return [];
      rows.addAll(List<Json>.from(result['data'] as List));
      cursor = result['next_cursor'] as String?;
    } while (cursor != null);
    return rows.reversed.toList();
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    location.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => busy = true);
    try {
      final session = widget.repository.session;
      if (session == null || session.expired || session.userId != owner) {
        throw ApiFailure(
          'Sign in, then reopen this form to submit and track your story.',
        );
      }
      final token = session.token;
      if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
        throw ApiFailure('Enter a title and details.');
      }
      if (pending == null) {
        String? encoded;
        if (photo != null) {
          final bytes = await widget.repository.store.image(photo!);
          if (bytes == null) throw ApiFailure('Select the photo again.');
          encoded = base64Encode(bytes);
        }
        pending = {
          'operation_id': operationId(),
          'kind': widget.kind,
          'title': title.text.trim(),
          'body': body.text.trim(),
          'location': location.text.trim(),
          'target_id': ?widget.targetId,
          'photo': ?encoded,
        };
      }
      await widget.repository.store.cache(cacheKey, pending!);
      await widget.repository.api.request(
        '/me/submissions',
        token: token,
        body: pending,
      );
      await widget.repository.store.cache(cacheKey, {});
      if (!mounted || session.userId != owner) return;
      message(
        context,
        'Received by the newsroom. You can track its status below.',
      );
      setState(() {
        pending = null;
        photo = null;
        title.clear();
        body.clear();
        location.clear();
        submissions = load();
      });
    } catch (e) {
      if (e is ApiFailure && !e.uncertain && e.status != 409) {
        pending = null;
        await widget.repository.store.cache(cacheKey, {});
      }
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.kind == 'news_tip' ? 'Send a story' : 'Send for review',
      ),
    ),
    body: ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(24),
      children: [
        const Notice(
          'Signed-in readers can send stories, photos and neighborhood issues. Photos are private to you and the newsroom; submitting does not publish them.',
        ),
        for (final field in [
          (title, 'Title', 180),
          (body, 'Details', 10000),
          (location, 'Location (optional)', 300),
        ])
          TextField(
            controller: field.$1,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            readOnly: busy || pending != null,
            maxLength: field.$3,
            minLines: field.$1 == body ? 4 : 1,
            maxLines: field.$1 == body ? 10 : 1,
            decoration: InputDecoration(labelText: field.$2),
          ),
        if (photo != null)
          SizedBox(
            height: 180,
            child: OfflineImage(repository: widget.repository, source: photo),
          ),
        if (widget.kind == 'news_tip')
          Wrap(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Attach photo'),
                onPressed: busy || pending != null
                    ? null
                    : () async {
                        try {
                          final source = await selectArticleImage(
                            widget.repository.store,
                          );
                          if (mounted && source != null) {
                            setState(() => photo = source);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            message(context, 'Could not select this image.');
                          }
                        }
                      },
              ),
              if (photo != null)
                TextButton(
                  onPressed: busy || pending != null
                      ? null
                      : () => setState(() => photo = null),
                  child: const Text('Remove photo'),
                ),
            ],
          ),
        FilledButton(
          onPressed: busy ? null : send,
          child: Text(
            busy
                ? 'Sending…'
                : pending == null
                ? 'Send to newsroom'
                : 'Retry same submission',
          ),
        ),
        if (pending != null)
          const Notice(
            'A previous delivery is unconfirmed. Retrying uses the same receipt and will not create another submission.',
          ),
        const Divider(height: 32),
        Text('My submissions', style: Theme.of(context).textTheme.titleLarge),
        TextButton(
          onPressed: () => setState(() {
            submissions = load();
          }),
          child: const Text('Refresh status'),
        ),
        FutureBuilder<List<Json>>(
          future: submissions,
          builder: (context, snapshot) => Column(
            children: [
              if (snapshot.connectionState != ConnectionState.done)
                const LinearProgressIndicator(),
              if (snapshot.hasError)
                Notice('Could not load submission status. ${snapshot.error}'),
              for (final row in snapshot.data ?? <Json>[])
                ListTile(
                  title: Text('${row['title']}'),
                  subtitle: Text(
                    '${row['status'].toString().replaceAll('_', ' ')}${row['note'] == null || row['note'] == '' ? '' : '\n${row['note']}'}',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
