import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/editorial.dart';
import '../data/local_store.dart';
import 'home.dart';
import 'responsive.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({
    super.key,
    required this.api,
    this.initialSubject = '',
    this.initialMessage = '',
    this.story = false,
    this.enabled = const bool.fromEnvironment(
      'EDITORIAL_API_ENABLED',
      defaultValue: true,
    ),
  });
  final bool enabled;
  final bool story;
  final Api api;
  final String initialSubject;
  final String initialMessage;
  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final name = TextEditingController(),
      email = TextEditingController(),
      subject = TextEditingController(),
      body = TextEditingController();
  bool busy = false, sent = false;
  Json? submission;
  @override
  void initState() {
    super.initState();
    subject.text = widget.initialSubject;
    body.text = widget.initialMessage;
  }

  Future<void> send() async {
    if (!widget.enabled || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if ([name, email, subject, body].any((c) => c.text.trim().isEmpty) ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      message(context, 'Complete every field and enter a valid email address.');
      return;
    }
    submission ??= {
      'operation_id': operationId(),
      'name': name.text.trim(),
      'email': email.text.trim(),
      'subject': subject.text.trim(),
      'message': body.text.trim(),
    };
    setState(() => busy = true);
    try {
      await widget.api.request('/contact', body: submission);
      if (mounted) setState(() => sent = true);
    } catch (e) {
      if (e is ApiFailure && !e.uncertain && e.status != 409) {
        submission = null;
      }
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendEmail() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final uri = Uri(
      scheme: 'mailto',
      path: 'reporter@fayettevillethepeoplevoice.com',
      query:
          {
                'subject': subject.text.trim().isEmpty
                    ? 'Story for The People Voice'
                    : subject.text.trim(),
                'body':
                    '${body.text.trim()}\n\n'
                    'Name: ${name.text.trim()}\nEmail: ${email.text.trim()}',
              }.entries
              .map(
                (e) =>
                    '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
              )
              .join('&'),
    );
    try {
      if (await launchUrl(uri)) {
        if (mounted) {
          message(
            context,
            'Finish sending in your email app. You can attach photos there.',
          );
        }
        return;
      }
    } catch (_) {
      // Keep the form intact and offer a copyable draft below.
    }
    if (!mounted) return;
    message(
      context,
      'Could not open an email app. Copy the message below and send it to reporter@fayettevillethepeoplevoice.com.',
    );
  }

  Future<void> copyEmail() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            'To: reporter@fayettevillethepeoplevoice.com\n'
            'Subject: ${subject.text.trim()}\n\n${body.text.trim()}\n\n'
            'Name: ${name.text.trim()}\nEmail: ${email.text.trim()}',
      ),
    );
    if (mounted) message(context, 'Email draft copied.');
  }

  @override
  void dispose() {
    for (final c in [name, email, subject, body]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.story ? 'Send a story' : 'Contact us')),
    body: SafeArea(
      child: ContentWidth(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          children: [
            if (!widget.enabled)
              const Notice(
                'Use the email option below to contact the newsroom.',
              ),
            if (sent) ...[
              const Icon(Icons.check_circle_outline, size: 64),
              const Notice(
                'Your message has been received. Our team can reply to your email address.',
              ),
            ] else ...[
              Notice(
                widget.story
                    ? 'Send your story through our contact form. Include the location and relevant details. To attach photos, use email below.'
                    : 'Questions, corrections or story ideas? Send a message to The People Voice team.',
              ),
              for (final field in [
                (name, 'Your name', 100),
                (email, 'Email address', 120),
                (subject, 'Subject', 200),
                (body, 'Message', 10000),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextField(
                    controller: field.$1,
                    readOnly: busy || submission != null,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    maxLength: field.$3,
                    keyboardType: field.$1 == email
                        ? TextInputType.emailAddress
                        : TextInputType.multiline,
                    minLines: field.$1 == body ? 5 : 1,
                    maxLines: field.$1 == body ? 12 : 1,
                    decoration: InputDecoration(labelText: field.$2),
                  ),
                ),
              if (submission != null && !busy)
                const Notice(
                  'Retry sends the same message identifier to prevent duplicates.',
                ),
              FilledButton(
                onPressed: !widget.enabled || busy ? null : send,
                child: Text(
                  busy
                      ? 'Sending…'
                      : submission == null
                      ? 'Send message'
                      : 'Retry sending',
                ),
              ),
              const SizedBox(height: 16),
              const Notice(
                'You can also email reporter@fayettevillethepeoplevoice.com. Your email app will open with your message; confirm sending there.',
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : sendEmail,
                icon: const Icon(Icons.email_outlined),
                label: const Text('Open email draft'),
              ),
              TextButton(
                onPressed: busy ? null : copyEmail,
                child: const Text('Copy email draft'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
