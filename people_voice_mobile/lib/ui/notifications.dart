import 'package:flutter/material.dart';

import '../data/notifications.dart';
import '../data/repository.dart';
import 'brand.dart';
import 'home.dart';
import 'preferences.dart';
import 'reader.dart';
import 'responsive.dart';
import 'community_admin.dart';
import 'promotion_review.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.inbox,
    required this.repository,
  });
  final NotificationInbox inbox;
  final Repository repository;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool unreadOnly = false;
  @override
  void initState() {
    super.initState();
    widget.inbox.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.inbox,
    builder: (context, _) {
      final inbox = widget.inbox;
      final items = inbox.items
          .where((item) => !unreadOnly || item['read'] != true)
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            IconButton(
              tooltip: 'Notification preferences',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PreferencesPage(repository: widget.repository),
                ),
              ),
              icon: const Icon(Icons.tune),
            ),
            IconButton(
              tooltip: 'Refresh notifications',
              onPressed: inbox.busy ? null : inbox.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: ContentWidth(
            child: RefreshIndicator(
              onRefresh: inbox.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  SectionHeading(
                    'Your activity',
                    eyebrow: 'STAY CONNECTED',
                    subtitle: inbox.unread == 0
                        ? 'Updates from your stories and your community.'
                        : '${inbox.unread} unread ${inbox.unread == 1 ? 'update' : 'updates'} from your community.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: !unreadOnly,
                        onSelected: (_) => setState(() => unreadOnly = false),
                      ),
                      ChoiceChip(
                        label: Text('Unread (${inbox.unread})'),
                        selected: unreadOnly,
                        onSelected: (_) => setState(() => unreadOnly = true),
                      ),
                      TextButton(
                        onPressed: inbox.unread == 0
                            ? null
                            : () => inbox.markRead(
                                inbox.items
                                    .where((n) => n['read'] != true)
                                    .map((n) => n['id'] as String)
                                    .toList(),
                              ),
                        child: const Text('Mark all as read'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (inbox.busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: LinearProgressIndicator(
                        semanticsLabel: 'Refreshing notifications',
                      ),
                    ),
                  if (inbox.error != null) Notice(inbox.error!),
                  if (!inbox.gateway.enabled)
                    const Notice(
                      'Your submissions from this device appear here. Account activity will appear when the server is available.',
                    ),
                  if (inbox.gateway.session.expired)
                    const Notice('Sign in to receive account notifications.'),
                  if (items.isEmpty && !inbox.busy && inbox.error == null)
                    AppEmptyState(
                      icon: unreadOnly
                          ? Icons.done_all
                          : Icons.notifications_none_outlined,
                      title: unreadOnly
                          ? 'You are all caught up'
                          : 'Your community, in the loop',
                      message: unreadOnly
                          ? 'No unread notifications. You can revisit previous updates in All.'
                          : 'Replies, followed authors and saved event reminders will appear here.',
                    ),
                  for (final item in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: item['read'] == true
                          ? null
                          : Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: .22),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 19,
                                  backgroundColor: item['read'] == true
                                      ? Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                      : Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                  foregroundColor: item['read'] == true
                                      ? Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                      : Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                  child: Icon(
                                    _icon(item['kind'] ?? item['type']),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item['title'] as String,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: item['read'] == true
                                              ? FontWeight.w600
                                              : FontWeight.w800,
                                        ),
                                  ),
                                ),
                                if (item['read'] != true) ...[
                                  const SizedBox(width: 8),
                                  Semantics(
                                    label: 'Unread',
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(top: 8),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item['message'] as String,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _date(item['created'] as String),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (item['kind'] == 'promotion_review' &&
                                    item['promotion_id'] is int)
                                  TextButton.icon(
                                    onPressed: () {
                                      inbox.markRead([item['id'] as String]);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => PromotionReviewPage(
                                            gateway: inbox.gateway,
                                            repository: widget.repository,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.campaign_outlined),
                                    label: const Text('Review promotion'),
                                  ),
                                if (item['kind'] == 'newsroom')
                                  TextButton.icon(
                                    onPressed: () {
                                      inbox.markRead([item['id'] as String]);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => CommunityAdminPage(
                                            gateway: inbox.gateway,
                                            store: widget.repository.store,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.inbox_outlined),
                                    label: const Text('Open newsroom'),
                                  ),
                                if (item['read'] != true)
                                  TextButton(
                                    onPressed: () =>
                                        inbox.markRead([item['id'] as String]),
                                    child: const Text('Mark as read'),
                                  ),
                                if (item['article_id'] is int)
                                  TextButton.icon(
                                    onPressed: () {
                                      inbox.markRead([item['id'] as String]);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ReaderPage(
                                            repository: widget.repository,
                                            id: item['article_id'] as int,
                                            title: 'Article',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.arrow_forward,
                                      size: 18,
                                    ),
                                    label: const Text('View article'),
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
        ),
      );
    },
  );

  IconData _icon(Object? kind) => switch (kind) {
    'reply' || 'replies' || 'comment_reply' => Icons.forum_outlined,
    'authors' => Icons.article_outlined,
    'events' => Icons.event_outlined,
    'newsroom' => Icons.inbox_outlined,
    'promotion_review' => Icons.campaign_outlined,
    _ => Icons.notifications_outlined,
  };

  String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return 'Date unavailable';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(date)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }
}
