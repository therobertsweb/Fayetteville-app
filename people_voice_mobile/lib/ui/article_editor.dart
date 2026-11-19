import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../data/article_media.dart';
import '../data/repository.dart';
import 'article_body.dart';
import 'home.dart';
import 'reader.dart';

/// The HTML controller is shared with autosave and the server forms.
class ArticleEditor extends StatefulWidget {
  const ArticleEditor({
    super.key,
    required this.controller,
    required this.repository,
    this.readOnly = false,
    this.initialDelta,
    this.onDocumentChanged,
  });
  final TextEditingController controller;
  final Repository repository;
  final bool readOnly;
  final List<dynamic>? initialDelta;
  final ValueChanged<List<dynamic>>? onDocumentChanged;
  @override
  State<ArticleEditor> createState() => _ArticleEditorState();
}

class _ArticleEditorState extends State<ArticleEditor> {
  late final quill.QuillController editor;
  final editorFocus = FocusNode();
  final editorScroll = ScrollController();
  bool syncing = false, selecting = false, preview = false;
  late String lastHtml;
  @override
  void initState() {
    super.initState();
    lastHtml = widget.controller.text;
    editor = quill.QuillController(
      document: articleDocument(delta: widget.initialDelta, content: lastHtml),
      selection: const TextSelection.collapsed(offset: 0),
    );
    editor.addListener(changed);
    widget.controller.addListener(externalChange);
  }

  void changed() {
    if (syncing) return;
    syncing = true;
    final value = articleHtml(editor.document);
    if (value != lastHtml) {
      lastHtml = value;
      widget.onDocumentChanged?.call(editor.document.toDelta().toJson());
      widget.controller.text = value;
    }
    syncing = false;
    if (mounted) setState(() {});
  }

  void externalChange() {
    if (syncing || widget.controller.text == lastHtml) return;
    syncing = true;
    lastHtml = widget.controller.text;
    editor.document = articleDocument(content: lastHtml);
    widget.onDocumentChanged?.call(editor.document.toDelta().toJson());
    syncing = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(externalChange);
    editor.removeListener(changed);
    editor.dispose();
    editorFocus.dispose();
    editorScroll.dispose();
    super.dispose();
  }

  void embed(String kind, String source) {
    final start = editor.selection.isValid
        ? editor.selection.start
        : editor.document.length - 1;
    final length = editor.selection.isValid ? editor.selection.end - start : 0;
    editor.replaceText(
      start,
      length,
      quill.BlockEmbed(kind, source),
      TextSelection.collapsed(offset: start + 1),
    );
  }

  Future<void> localImage() async {
    setState(() => selecting = true);
    try {
      final source = await selectArticleImage(widget.repository.store);
      if (source != null && mounted) embed('image', source);
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Could not add the image. Choose a JPG, PNG, WebP or GIF under 5 MB and 20 million pixels.',
        );
      }
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  Future<void> addUrl(String kind) async {
    final selection = editor.selection;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _MediaUrlDialog(kind: kind),
    );
    if (result == null || !mounted) return;
    if (kind == 'link') {
      final start = selection.isValid
          ? selection.start
          : editor.document.length - 1;
      final length = selection.isValid ? selection.end - start : 0;
      if (length > 0) {
        editor.formatText(start, length, quill.LinkAttribute(result));
      } else {
        editor.replaceText(
          start,
          0,
          result,
          TextSelection.collapsed(offset: start + result.length),
        );
        editor.formatText(start, result.length, quill.LinkAttribute(result));
      }
    } else {
      embed(kind, kind == 'video' ? videoSource(result)! : result);
    }
  }

  Widget format(String label, IconData icon, quill.Attribute attribute) {
    final active =
        editor.getSelectionStyle().attributes[attribute.key]?.value ==
        attribute.value;
    return IconButton(
      tooltip: label,
      isSelected: active,
      onPressed: () => editor.formatSelection(
        active ? quill.Attribute.clone(attribute, null) : attribute,
      ),
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    editor.readOnly = widget.readOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Tell your story',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(() => preview = !preview),
              icon: Icon(preview ? Icons.edit : Icons.visibility_outlined),
              label: Text(preview ? 'Edit' : 'Preview'),
            ),
          ],
        ),
        if (!widget.readOnly && !preview) ...[
          Wrap(
            children: [
              format('Bold', Icons.format_bold, quill.Attribute.bold),
              format('Italic', Icons.format_italic, quill.Attribute.italic),
              format(
                'Underline',
                Icons.format_underlined,
                quill.Attribute.underline,
              ),
              format('Heading', Icons.title, quill.Attribute.h2),
              format(
                'Bullet list',
                Icons.format_list_bulleted,
                quill.Attribute.ul,
              ),
              format(
                'Numbered list',
                Icons.format_list_numbered,
                quill.Attribute.ol,
              ),
              format('Quote', Icons.format_quote, quill.Attribute.blockQuote),
              IconButton(
                tooltip: 'Undo',
                onPressed: editor.hasUndo ? editor.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: editor.hasRedo ? editor.redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: 'Add link',
                onPressed: () => addUrl('link'),
                icon: const Icon(Icons.link),
              ),
              IconButton(
                tooltip: 'Remove link',
                onPressed: () =>
                    editor.formatSelection(const quill.LinkAttribute(null)),
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: selecting ? null : localImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Local image'),
              ),
              TextButton.icon(
                onPressed: () => addUrl('image'),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Image URL'),
              ),
              TextButton.icon(
                onPressed: () => addUrl('video'),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Video'),
              ),
            ],
          ),
          if (selecting) const LinearProgressIndicator(),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: preview || widget.readOnly
                ? ArticleBody(
                    content: widget.controller.text,
                    repository: widget.repository,
                  )
                : quill.QuillEditor.basic(
                    controller: editor,
                    focusNode: editorFocus,
                    scrollController: editorScroll,
                    config: quill.QuillEditorConfig(
                      minHeight: 240,
                      scrollable: false,
                      placeholder: 'Write your article…',
                      embedBuilders: [
                        _ArticleEmbed('image', widget.repository),
                        _ArticleEmbed('video', widget.repository),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ArticleEmbed extends quill.EmbedBuilder {
  const _ArticleEmbed(this.key, this.repository);
  @override
  final String key;
  final Repository repository;
  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final source = embedContext.node.value.data as String;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (key == 'image')
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: OfflineImage(repository: repository, source: source),
          )
        else
          ArticleVideo(source: source),
        if (!embedContext.readOnly)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => embedContext.controller.replaceText(
                embedContext.node.documentOffset,
                1,
                '',
                null,
              ),
              icon: const Icon(Icons.close),
              label: Text(key == 'image' ? 'Remove image' : 'Remove video'),
            ),
          ),
      ],
    );
  }
}

class _MediaUrlDialog extends StatefulWidget {
  const _MediaUrlDialog({required this.kind});
  final String kind;
  @override
  State<_MediaUrlDialog> createState() => _MediaUrlDialogState();
}

class _MediaUrlDialogState extends State<_MediaUrlDialog> {
  final input = TextEditingController();
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit() {
    final value = input.text.trim();
    if (!isHttpsUrl(value) ||
        (widget.kind == 'video' && videoSource(value) == null)) {
      setState(
        () => error = widget.kind == 'video'
            ? 'Use the full public video URL or a direct HTTPS video URL.'
            : 'Enter a valid HTTPS URL.',
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add ${widget.kind}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.kind == 'video')
          const Text(
            'YouTube, Facebook, TikTok, Vimeo or a direct video URL. For shared short links, open the video and copy its full URL.',
          ),
        TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: 'HTTPS URL', errorText: error),
          onSubmitted: (_) => submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Insert')),
    ],
  );
}

class CoverImageEditor extends StatelessWidget {
  const CoverImageEditor({
    super.key,
    required this.controller,
    required this.repository,
    this.readOnly = false,
  });
  final TextEditingController controller;
  final Repository repository;
  final bool readOnly;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!value.text.startsWith(localImagePrefix))
          TextField(
            controller: controller,
            readOnly: readOnly,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Cover image URL',
              hintText: 'https://…',
            ),
          ),
        if (value.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: OfflineImage(repository: repository, source: value.text),
            ),
          ),
        if (!readOnly)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final source = await selectArticleImage(repository.store);
                    if (source != null && context.mounted) {
                      controller.text = source;
                    }
                  } catch (_) {
                    if (context.mounted) {
                      message(
                        context,
                        'Choose a valid image under 5 MB and 20 million pixels.',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.upload),
                label: const Text('Choose cover image'),
              ),
              if (value.text.isNotEmpty)
                TextButton(
                  onPressed: controller.clear,
                  child: const Text('Remove cover'),
                ),
            ],
          ),
      ],
    ),
  );
}
