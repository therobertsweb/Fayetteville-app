import 'responsive.dart';

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../data/api.dart';
import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/publisher.dart';
import '../data/repository.dart';
import 'home.dart';
import 'brand.dart';
import 'ai_assistant.dart';
import 'article_editor.dart';

String draftStatus(Json draft) => switch (draft['state']) {
  'published' => 'Published',
  'remote' => 'Submitted for review · not published yet',
  'creating' || 'uncertain' => 'Unconfirmed submission · review required',
  _ => 'Saved on this device',
};

class DraftsPage extends StatefulWidget {
  const DraftsPage({
    super.key,
    required this.repository,
    required this.session,
  });
  final Repository repository;
  final Session session;
  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
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

  Future<List<Json>> load() =>
      widget.repository.store.drafts(widget.session.userId);
  Future<void> edit([Json? draft]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DraftEditor(
          repository: widget.repository,
          session: widget.session,
          initial: draft,
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
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      child: ContentWidth(
        maxWidth: 1040,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your drafts',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Write'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Notice(
                'Write offline. Your drafts stay here until you choose to submit them online.',
                icon: Icons.offline_pin_outlined,
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Json>>(
                key: ValueKey(loadedOwner),
                future: data,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Notice(
                      'Could not read drafts. Reopen this section.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (snapshot.data!.isEmpty)
                        const Notice(
                          'Your next story starts here. Tap Write to create a draft.',
                        ),
                      ...snapshot.data!.map(
                        (draft) => Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            leading: Icon(
                              draft['state'] == 'published'
                                  ? Icons.check_circle_outline
                                  : Icons.edit_note,
                            ),
                            title: Text(
                              (draft['title'] as String? ?? '').trim().isEmpty
                                  ? 'Untitled'
                                  : draft['title'] as String,
                            ),
                            subtitle: Text(draftStatus(draft)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => edit(draft),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DraftEditor extends StatefulWidget {
  const DraftEditor({
    super.key,
    required this.repository,
    required this.session,
    this.initial,
  });
  final Repository repository;
  final Session session;
  final Json? initial;
  @override
  State<DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<DraftEditor> {
  late Json draft;
  late final TextEditingController title,
      url,
      content,
      photo,
      category,
      primaryCategory,
      tagPrimary,
      tagSecondary,
      shortSummary,
      supportingDescription,
      homepageExcerpt;
  late final Publisher publisher;
  Future<void> pending = Future.value();
  int revision = 0, savedRevision = 0;
  bool busy = false, leaving = false;
  String? saveError;
  bool get editable => draft['state'] == 'local';
  @override
  void initState() {
    super.initState();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    draft = Map<String, dynamic>.from(
      widget.initial ??
          {
            'local_id': id,
            'url': 'mobile-$id',
            'title': '',
            'title_2': '',
            'title_3': '',
            'subtitle': '',
            'subtitle_2': '',
            'tag_1': '',
            'tag_2': '',
            'info': 'Local News',
            'content': '',
            'plain_text': '',
            'photo_link': '',
            'categories': '',
            'state': 'local',
            'owner_id': widget.session.userId,
          },
    );
    String value(String key, [String fallback = '']) =>
        draft[key] as String? ?? fallback;
    title = TextEditingController(text: value('title'));
    url = TextEditingController(text: value('url', 'mobile-$id'));
    content = TextEditingController(
      text: value('content').isNotEmpty
          ? value('content')
          : '<p>${const HtmlEscape().convert(value('plain_text')).replaceAll('\n', '<br>')}</p>',
    );
    photo = TextEditingController(text: value('photo_link'));
    category = TextEditingController(text: value('categories'));
    const primaryCategories = {
      'Local News',
      'Community',
      'Business',
      'Technology',
      'Opinion',
      'Events',
    };
    final storedPrimaryCategory = value('info', 'Local News');
    primaryCategory = TextEditingController(
      text: primaryCategories.contains(storedPrimaryCategory)
          ? storedPrimaryCategory
          : 'Local News',
    );
    tagPrimary = TextEditingController(text: value('tag_2'));
    tagSecondary = TextEditingController(text: value('tag_1'));
    shortSummary = TextEditingController(text: value('title_2'));
    supportingDescription = TextEditingController(text: value('subtitle_2'));
    homepageExcerpt = TextEditingController(text: value('subtitle'));
    publisher = Publisher(widget.repository.api, widget.repository.store);
    for (final controller in [
      title,
      url,
      content,
      photo,
      category,
      primaryCategory,
      tagPrimary,
      tagSecondary,
      shortSummary,
      supportingDescription,
      homepageExcerpt,
    ]) {
      controller.addListener(changed);
    }
    if (widget.initial == null) persist();
  }

  void changed() {
    persist();
  }

  Future<void> persist() {
    if (!editable) return pending;
    final current = ++revision;
    draft.addAll({
      'url': url.text.trim(),
      'title': title.text,
      // The web form keeps title_3 synchronized with the article title.
      'title_3': title.text,
      'title_2': shortSummary.text.trim(),
      'subtitle': homepageExcerpt.text.trim(),
      'subtitle_2': supportingDescription.text.trim(),
      'tag_1': tagSecondary.text.trim(),
      'tag_2': tagPrimary.text.trim(),
      'info': primaryCategory.text.trim(),
      'plain_text': html.parseFragment(content.text).text ?? '',
      'content': content.text,
      'photo_link': photo.text.trim(),
      'categories': category.text.trim(),
    });
    final snapshot = Map<String, dynamic>.from(draft);
    // Serialize all writes so an older keystroke cannot overwrite a newer one.
    pending = pending.then((_) async {
      try {
        await widget.repository.store.saveDraft(snapshot);
        savedRevision = current;
        saveError = null;
      } catch (_) {
        saveError = 'Could not save. Check available storage and try again.';
      }
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
    return pending;
  }

  Future<void> leave() async {
    if (busy) return;
    await persist();
    if (!mounted) return;
    if (saveError != null) {
      message(context, saveError!);
      return;
    }
    setState(() => leaving = true);
    if (mounted) Navigator.pop(context);
  }

  Future<void> publish({bool review = false}) async {
    await persist();
    if (!mounted || saveError != null) return;
    if ((html.parseFragment(content.text).text ?? '').trim().isEmpty) {
      message(context, 'Write the article content before publishing.');
      return;
    }
    try {
      Publisher.validate(draft);
      widget.session.token;
      if (!widget.session.canPublish) {
        throw ApiFailure(
          'This account does not have permission to perform this action. Your draft is still saved.',
        );
      }
    } catch (e) {
      message(context, e);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(review ? 'Submit for review' : 'Publish article'),
        content: Text(
          review
              ? '“${title.text}” will be saved on the server as a draft by ${widget.session.username}, without being made public.'
              : '“${title.text}” will appear on the website under the account ${widget.session.username}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(review ? 'Submit draft' : 'Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await publisher.publish(
        draft['local_id'] as String,
        userId: widget.session.userId!,
        token: widget.session.token,
        publishNow: !review,
      );
      if (mounted) {
        message(
          context,
          review
              ? 'Draft submitted for review. Your local copy is saved.'
              : 'Article published. Your local copy is saved.',
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      final stored = await widget.repository.store.draft(
        draft['local_id'] as String,
      );
      if (mounted) {
        setState(() {
          if (stored != null) draft = stored;
          busy = false;
        });
      }
    }
  }

  Future<void> recover() async {
    final controller = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link previous submission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If the server received the draft, find its ID on the website or ask an administrator. We will verify the account and identifier before linking it.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Article ID'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Check'),
          ),
        ],
      ),
    );
    final id = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (id == null || !mounted) return;
    final remoteId = int.tryParse(id);
    if (remoteId == null || remoteId <= 0) {
      message(context, 'Enter a valid ID.');
      return;
    }
    setState(() => busy = true);
    try {
      final token = widget.session.token;
      await publisher.recover(
        draft['local_id'] as String,
        remoteId,
        userId: widget.session.userId!,
        token: token,
      );
      final saved = await widget.repository.store.draft(
        draft['local_id'] as String,
      );
      if (saved != null) draft = saved;
      if (mounted) message(context, 'Submission linked. You can continue.');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> assist() async {
    await persist();
    if (!mounted || saveError != null) return;
    final original = {'title': title.text, 'content': content.text};
    final proposal = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => AiAssistant(
          gateway: EditorialGateway(widget.repository.api, widget.session),
          title: title.text,
          content: html.parseFragment(content.text).text ?? '',
        ),
      ),
    );
    if (proposal == null || !mounted) return;
    draft['ai_previous'] = original;
    title.text = proposal['title'] as String;
    content.text =
        '<p>${const HtmlEscape().convert(proposal['content'] as String).replaceAll('\n', '<br>')}</p>';
    await persist();
  }

  Future<void> undoAi() async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore previous text'),
        content: const Text(
          'This replaces the current title and text with the version from before the latest AI suggestion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (restore != true || !mounted) return;
    final original = draft.remove('ai_previous') as Json;
    title.text = original['title'] as String;
    content.text =
        original['content'] as String? ??
        '<p>${const HtmlEscape().convert(original['plain_text'] as String? ?? '')}</p>';
    await persist();
  }

  @override
  void dispose() {
    for (final controller in [
      title,
      url,
      content,
      photo,
      category,
      primaryCategory,
      tagPrimary,
      tagSecondary,
      shortSummary,
      supportingDescription,
      homepageExcerpt,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Your story'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy ? null : leave,
        ),
      ),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Brand.heading, Color(0xff527a9f)],
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THE PEOPLE VOICE',
                      style: TextStyle(
                        color: Color(0xffd7e7f7),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Share your story',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Our community voices matter.',
                      style: TextStyle(color: Color(0xffe6eff7)),
                    ),
                  ],
                ),
              ),
              Notice(
                saveError ??
                    (savedRevision < revision ? 'Saving…' : draftStatus(draft)),
                icon: saveError == null
                    ? Icons.save_outlined
                    : Icons.error_outline,
              ),
              if (saveError != null)
                TextButton(
                  onPressed: persist,
                  child: const Text('Retry saving'),
                ),
              if (!editable)
                const Notice(
                  'This submission keeps its original content. Use post management to edit articles on the server.',
                ),
              if (editable) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : assist,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Write with AI'),
                ),
                if (draft['ai_previous'] != null)
                  TextButton(
                    onPressed: busy ? null : undoAi,
                    child: const Text('Restore text from before AI'),
                  ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: title,
                readOnly: !editable || busy,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: url,
                readOnly: !editable || busy,
                maxLength: 100,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Article URL',
                  hintText: 'your-article-url',
                  helperText: 'Lowercase letters, numbers and hyphens only.',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue:
                    const [
                      'Local News',
                      'Community',
                      'Business',
                      'Technology',
                      'Opinion',
                      'Events',
                    ].contains(primaryCategory.text)
                    ? primaryCategory.text
                    : 'Local News',
                decoration: const InputDecoration(
                  labelText: 'Primary category',
                ),
                items:
                    const [
                          'Local News',
                          'Community',
                          'Business',
                          'Technology',
                          'Opinion',
                          'Events',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: !editable || busy
                    ? null
                    : (value) {
                        primaryCategory.text = value!;
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tagPrimary,
                readOnly: !editable || busy,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Tag',
                  hintText: 'Local news',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: shortSummary,
                readOnly: !editable || busy,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Short summary',
                  hintText: 'A short summary for article cards',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: supportingDescription,
                readOnly: !editable || busy,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Supporting description',
                  hintText: 'Add context that encourages readers to continue.',
                ),
              ),
              const SizedBox(height: 16),
              ArticleEditor(
                controller: content,
                repository: widget.repository,
                initialDelta: draft['editor_delta'] as List<dynamic>?,
                onDocumentChanged: (delta) => draft['editor_delta'] = delta,
                readOnly: !editable || busy,
              ),
              const SizedBox(height: 24),
              CoverImageEditor(
                controller: photo,
                repository: widget.repository,
                readOnly: !editable || busy,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Choose a local cover or paste an image URL. Local images upload when you submit the article.',
                ),
              ),
              TextField(
                controller: category,
                readOnly: !editable || busy,
                decoration: const InputDecoration(
                  labelText: 'Additional categories (optional)',
                  hintText: 'Separate multiple categories with commas',
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Additional template fields'),
                subtitle: const Text(
                  'Optional fields supported by the website API',
                ),
                children: [
                  TextField(
                    controller: homepageExcerpt,
                    readOnly: !editable || busy,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Homepage excerpt (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tagSecondary,
                    readOnly: !editable || busy,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Secondary tag (optional)',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'The secondary title used by the website is synchronized with the article title automatically.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (editable)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await persist();
                          if (context.mounted) {
                            message(
                              context,
                              saveError ?? 'Draft saved on this device.',
                            );
                          }
                        },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save draft'),
                ),
              if (editable)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => publish(review: true),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Submit for review'),
                ),
              if (['creating', 'uncertain'].contains(draft['state'])) ...[
                const Notice(
                  'We will not create another article: the server may have received it even though the response was lost.',
                ),
                SelectableText('Identifier: ${draft['url']}'),
                OutlinedButton(
                  onPressed: busy ? null : recover,
                  child: const Text('Link server ID'),
                ),
              ] else if (draft['state'] != 'published')
                FilledButton.icon(
                  onPressed: busy ? null : publish,
                  icon: const Icon(Icons.publish),
                  label: Text(busy ? 'Publishing…' : 'Publish online'),
                ),
              if (draft['remote_id'] != null)
                Text('Server ID: ${draft['remote_id']}'),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
