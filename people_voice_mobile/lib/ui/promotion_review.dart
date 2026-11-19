import 'package:flutter/material.dart';

import '../data/editorial.dart';
import '../data/local_store.dart';
import '../data/repository.dart';
import '../data/promotions.dart';
import 'home.dart' show Notice, message;
import 'reader.dart';
import 'responsive.dart';

/// Review of paid promotion requests. The server remains the authority for
/// payment, article eligibility, and whether a placement is made visible.
class PromotionReviewPage extends StatefulWidget {
  const PromotionReviewPage({
    super.key,
    required this.gateway,
    required this.repository,
    this.promotionApi,
  });

  final EditorialGateway gateway;
  final Repository repository;
  final PromotionApi? promotionApi;

  @override
  State<PromotionReviewPage> createState() => _PromotionReviewPageState();
}

class _PromotionReviewPageState extends State<PromotionReviewPage> {
  late final PromotionApi promotionApi =
      widget.promotionApi ?? widget.repository.promotions ?? PromotionApi();
  List<Json> requests = [];
  String? error;
  bool loading = false;
  bool deciding = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    widget.gateway.session.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    requests = [];
    load();
  }

  @override
  void dispose() {
    generation++;
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
      final result = await promotionApi.pending(widget.gateway.session.token);
      if (mounted && generation == version) {
        setState(() => requests = result);
      }
    } catch (e) {
      if (mounted && generation == version) {
        setState(() {
          requests = [];
          error = '$e';
        });
      }
    } finally {
      if (mounted && generation == version) setState(() => loading = false);
    }
  }

  Future<void> decide(Json request, String decision) async {
    if (deciding) return;
    final article = request['article'] as Json;
    final user = request['user'] as Json;
    final owner = widget.gateway.session.userId;
    var explanation = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          decision == 'approve' ? 'Approve promotion?' : 'Reject promotion?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Article: ${article['title']}\nRequested by: ${user['username']}',
            ),
            const SizedBox(height: 12),
            Text(
              decision == 'approve'
                  ? 'The paid article will appear in Stories promoted this week after the server confirms this decision.'
                  : 'The paid request will not appear. The newsroom must handle the refund or other remedy according to its policy.',
            ),
            if (decision == 'reject') ...[
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => explanation = value.trim(),
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for rejection',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(decision == 'approve' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        owner != widget.gateway.session.userId) {
      return;
    }
    if (decision == 'reject' && explanation.isEmpty) {
      message(context, 'Add a reason before rejecting this paid request.');
      return;
    }
    setState(() => deciding = true);
    try {
      await promotionApi.decide(
        request['id'] as int,
        widget.gateway.session.token,
        decision: decision,
        version: request['version'] as int,
        reason: decision == 'reject' ? explanation : null,
      );
      if (mounted) {
        message(
          context,
          decision == 'approve'
              ? 'Promotion approved.'
              : 'Promotion rejected. Review the payment remedy.',
        );
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) {
        setState(() => deciding = false);
        await load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Paid promotions'),
      actions: [
        IconButton(
          tooltip: 'Refresh paid promotions',
          onPressed: loading || deciding ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Awaiting your approval',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Only payments confirmed by the server are listed here. Review the article before approving its placement.',
            ),
            if (loading || deciding) const LinearProgressIndicator(),
            if (error != null) Notice(error!),
            if (!loading && error == null && requests.isEmpty)
              const Notice('There are no paid promotions awaiting review.'),
            for (final request in requests)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${request['article']['title']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Requested by ${request['user']['username']} · User #${request['user']['id']}',
                      ),
                      if (request['user']['email'] is String)
                        SelectableText('${request['user']['email']}'),
                      Text(
                        'Article #${request['article']['id']} · Payment confirmed',
                      ),
                      if (request['paid_at'] is String)
                        Text('Paid ${request['paid_at']}'),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ReaderPage(
                                  repository: widget.repository,
                                  id: request['article']['id'] as int,
                                  title: request['article']['title'] as String,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.article_outlined),
                            label: const Text('Read article'),
                          ),
                          FilledButton(
                            onPressed: deciding
                                ? null
                                : () => decide(request, 'approve'),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            onPressed: deciding
                                ? null
                                : () => decide(request, 'reject'),
                            child: const Text('Reject'),
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
  );
}
