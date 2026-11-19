import 'responsive.dart';

import 'package:flutter/material.dart';

import '../data/editorial.dart';
import '../data/local_store.dart';
import 'brand.dart';
import 'home.dart';

class AiAssistant extends StatefulWidget {
  const AiAssistant({
    super.key,
    required this.gateway,
    required this.title,
    required this.content,
  });
  final EditorialGateway gateway;
  final String title, content;
  @override
  State<AiAssistant> createState() => _AiAssistantState();
}

class _AiAssistantState extends State<AiAssistant> {
  final instruction = TextEditingController();
  late String task = widget.content.trim().isEmpty
      ? 'Create a draft'
      : 'Improve clarity';
  bool busy = false;
  Json? proposal;
  String? error;
  @override
  void dispose() {
    instruction.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    if (widget.content.trim().isEmpty && instruction.text.trim().isEmpty) {
      message(context, 'Write some text or describe your idea to get started.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      proposal = null;
    });
    try {
      final result = await widget.gateway.improve(
        title: widget.title,
        content: widget.content,
        instruction: '$task. ${instruction.text.trim()}',
      );
      if (mounted) setState(() => proposal = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Writing assistant')),
    body: SafeArea(
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SectionHeading(
              'Shape your story',
              eyebrow: 'AI writing help',
              subtitle: 'Your voice comes first. Review the suggestion and choose what to keep.',
            ),
            if (!widget.gateway.enabled)
              const Notice(
                'AI assistance is not available yet. You can keep writing and save your draft offline.',
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                        'Improve clarity',
                        'Fix spelling',
                        'Suggest a title',
                        'Create a draft',
                      ]
                      .map(
                        (label) => ChoiceChip(
                          label: Text(label),
                          selected: task == label,
                          onSelected: busy
                              ? null
                              : (_) => setState(() => task = label),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: instruction,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: task == 'Create a draft'
                    ? 'Describe the story you want to write'
                    : 'What would you like to improve?',
                hintText: task == 'Create a draft'
                    ? 'Topic, confirmed facts, audience and tone.'
                    : 'For example: a friendly tone and shorter sentences.',
              ),
            ),
            const Notice(
              'Requesting a suggestion sends your title, text and instructions to the AI service. Check names, dates and facts before applying changes.',
            ),
            FilledButton.icon(
              onPressed: busy || !widget.gateway.enabled ? null : generate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(busy ? 'Preparing suggestion…' : 'Get suggestion'),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (error != null) Notice(error!),
            if (proposal != null) ...[
              const SizedBox(height: 24),
              const SectionHeading('Review the changes'),
              ExpansionTile(
                title: const Text('Your original text'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      '${widget.title}\n\n${widget.content}',
                    ),
                  ),
                ],
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proposal!['title'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      SelectableText(proposal!['content'] as String),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, proposal),
                child: const Text('Apply suggestion to draft'),
              ),
              TextButton(
                onPressed: () => setState(() => proposal = null),
                child: const Text('Keep my text'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
