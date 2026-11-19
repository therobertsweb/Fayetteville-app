import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/repository.dart';

/// Keeps text and the server draft ID until publication is confirmed.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.session,
    required this.postId,
    this.parentId,
  });
  final Session session;
  final int postId;
  final int? parentId;
  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final text = TextEditingController();
  int? draftId;
  bool busy = false, uncertainCreation = false;
  String? error;
  late final owner = widget.session.userId;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (busy || uncertainCreation) return;
    final content = const HtmlEscape()
        .convert(text.text.trim())
        .replaceAll('\n', '<br>');
    if (content.isEmpty || content.length > 5000) {
      setState(
        () => error = 'Enter a comment of up to 5,000 encoded characters.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.session.userId != owner) {
        throw ApiFailure(
          'Your account changed. Close this window and sign in again.',
        );
      }
      final token = widget.session.token;
      if (draftId == null) {
        try {
          final result = await widget.session.api.request(
            '/posts/${widget.postId}/comments',
            body: {'content': content, 'parent_id': widget.parentId},
            token: token,
          );
          final id = result['data']?['id'];
          if (id is! int) {
            throw ApiFailure(
              'Comment creation was not confirmed.',
              uncertain: true,
            );
          }
          draftId = id;
        } on ApiFailure catch (e) {
          uncertainCreation = e.uncertain;
          rethrow;
        }
      }
      await widget.session.api.request(
        '/comments/$draftId/publish',
        body: {},
        token: token,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = uncertainCreation
              ? 'The connection was interrupted before creation was confirmed. Copy your text before closing; check your comments before submitting again.'
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.parentId == null ? 'Add a comment' : 'Reply to comment',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                maxLength: 5000,
                readOnly: busy || draftId != null || uncertainCreation,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write your comment…',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!),
                ),
              if (draftId != null && error != null)
                const Text('Retry publishes the same saved comment.'),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: busy || uncertainCreation ? null : publish,
          child: Text(
            busy
                ? 'Publishing…'
                : draftId != null
                ? 'Retry publishing'
                : 'Publish',
          ),
        ),
      ],
    ),
  );
}
