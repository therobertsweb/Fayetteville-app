import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/local_store.dart';
import '../data/api.dart';
import '../data/repository.dart';
import '../data/community_tools.dart';
import 'brand.dart';
import 'contact.dart';
import 'news_tips.dart';
import 'home.dart' show ArticleTile, Notice, message;
import 'responsive.dart';

class CommunityHub extends StatefulWidget {
  const CommunityHub({super.key, required this.repository});
  final Repository repository;
  @override
  State<CommunityHub> createState() => _CommunityHubState();
}

class _CommunityHubState extends State<CommunityHub> {
  bool events = true;
  String filter = '';
  bool free = false, family = false, savedOnly = false;
  String period = 'all';
  final search = TextEditingController();
  final listings = <bool, Future<FeedResult>>{};
  final stories = <bool, Future<FeedResult>>{};
  final storyPages = <bool, int>{true: 1, false: 1};

  Future<FeedResult> directory(bool kind) => listings.putIfAbsent(
    kind,
    () => widget.repository.feed(kind ? '/events' : '/businesses'),
  );
  Future<FeedResult> news(bool kind) => stories.putIfAbsent(
    kind,
    () => widget.repository.search(
      kind ? 'events' : 'business',
      page: storyPages[kind]!,
    ),
  );

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void refresh() => setState(() {
    listings.remove(events);
    stories.remove(events);
  });

  void propose() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ContactPage(
        api: widget.repository.api,
        initialSubject: events
            ? 'Community event submission'
            : 'Business directory submission',
        initialMessage: events
            ? 'Event name: \nDate and time (with timezone): \nVenue and address: \nDetails and admission: \nOfficial link: '
            : 'Business name: \nCategory: \nAddress: \nOpening hours: \nWebsite or phone: \nDescription: ',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SectionHeading(
        'Community',
        eyebrow: 'FAYETTEVILLE',
        subtitle:
            'Discover local activities and connect with local businesses.',
      ),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            label: Text('Events'),
            icon: Icon(Icons.event_outlined),
          ),
          ButtonSegment(
            value: false,
            label: Text('Businesses'),
            icon: Icon(Icons.storefront_outlined),
          ),
        ],
        selected: {events},
        onSelectionChanged: (selection) => setState(() {
          events = selection.first;
          search.clear();
          filter = '';
        }),
      ),
      const SizedBox(height: 16),
      if (events)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in [
              ('all', 'Any date'),
              ('today', 'Today'),
              ('week', 'Next 7 days'),
            ])
              ChoiceChip(
                label: Text(option.$2),
                selected: period == option.$1,
                onSelected: (_) => setState(() => period = option.$1),
              ),
            FilterChip(
              label: const Text('Free'),
              selected: free,
              onSelected: (v) => setState(() => free = v),
            ),
            FilterChip(
              label: const Text('Family friendly'),
              selected: family,
              onSelected: (v) => setState(() => family = v),
            ),
            FilterChip(
              label: const Text('Saved events'),
              selected: savedOnly,
              onSelected: (v) => setState(() => savedOnly = v),
            ),
          ],
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: propose,
            icon: const Icon(Icons.add),
            label: Text(events ? 'Suggest an event' : 'Suggest a business'),
          ),
          TextButton.icon(
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Suggestions are sent to our team for review before listing.',
        ),
      ),
      TextField(
        controller: search,
        onChanged: (value) =>
            setState(() => filter = value.trim().toLowerCase()),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          labelText: events
              ? 'Filter listed events'
              : 'Filter listed businesses',
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<FeedResult>(
        key: ValueKey('directory-$events'),
        future: directory(events),
        builder: (context, snapshot) {
          if (!(events && savedOnly) &&
              snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (!(events && savedOnly) && snapshot.hasError) {
            return const Notice(
              'The directory could not be loaded. Tap Refresh to retry.',
            );
          }
          final all = events && savedOnly
              ? widget.repository.experience.savedEvents
              : List<Json>.from(snapshot.data!.body['data'] as List);
          final matches = all
              .where(
                (row) =>
                    (!events ||
                        eventMatches(
                          row,
                          period: period,
                          free: free,
                          family: family,
                        )) &&
                    [
                          row['title'],
                          row['name'],
                          row['category'],
                          row['location'],
                          row['address'],
                        ]
                        .whereType<String>()
                        .join(' ')
                        .toLowerCase()
                        .contains(filter),
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snapshot.data?.warning != null)
                Notice(snapshot.data!.warning!),
              if (all.isEmpty)
                Notice(
                  events
                      ? 'No approved event listings yet. Explore event coverage below or suggest an event.'
                      : 'No verified business listings yet. Explore business coverage below or suggest a business.',
                ),
              if (all.isNotEmpty && matches.isEmpty)
                const Notice('No listings match your search.'),
              for (final row in matches)
                Card(
                  child: ListTile(
                    leading: Icon(
                      events ? Icons.event_outlined : Icons.storefront_outlined,
                      color: Brand.red,
                    ),
                    title: Text('${row[events ? 'title' : 'name'] ?? ''}'),
                    subtitle: Text(
                      events
                          ? '${row['location'] ?? 'Location not provided'}\n${row['starts_at'] ?? ''}'
                          : '${row['category'] ?? ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CommunityDetails(
                          item: row,
                          event: events,
                          repository: widget.repository,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const Divider(height: 32),
      Text(
        events ? 'Event coverage' : 'Business coverage',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Related published articles — separate from directory listings.',
      ),
      const SizedBox(height: 12),
      FutureBuilder<FeedResult>(
        key: ValueKey('stories-$events'),
        future: news(events),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return const Notice(
              'Could not load related articles. Tap Refresh to retry.',
            );
          }
          final result = snapshot.data!;
          final rows = List<Json>.from(result.body['data'] as List);
          final page = storyPages[events]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (result.warning != null) Notice(result.warning!),
              if (rows.isEmpty) const Notice('No related articles available.'),
              for (final row in rows)
                ArticleTile(post: row, repository: widget.repository),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page <= 1
                        ? null
                        : () => setState(() {
                            storyPages[events] = page - 1;
                            stories.remove(events);
                          }),
                    child: const Text('Previous'),
                  ),
                  Text('Page $page'),
                  TextButton(
                    onPressed: page >= (result.body['pages'] as int? ?? 1)
                        ? null
                        : () => setState(() {
                            storyPages[events] = page + 1;
                            stories.remove(events);
                          }),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}

class CommunityDetails extends StatelessWidget {
  const CommunityDetails({
    super.key,
    required this.item,
    required this.event,
    required this.repository,
  });
  final Repository repository;
  final Json item;
  final bool event;

  @override
  Widget build(BuildContext context) {
    final location = (item[event ? 'location' : 'address'] as String? ?? '')
        .trim();
    return Scaffold(
      appBar: AppBar(title: Text(event ? 'Event details' : 'Business details')),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${item[event ? 'title' : 'name'] ?? ''}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              for (final field
                  in event
                      ? [
                          ('starts_at', 'Date and time'),
                          ('location', 'Location'),
                          ('description', 'Details'),
                        ]
                      : [
                          ('category', 'Category'),
                          ('address', 'Address'),
                          ('description', 'About'),
                          ('opening_hours', 'Opening hours'),
                          ('phone', 'Phone'),
                          ('website', 'Website'),
                        ])
                if ((item[field.$1]?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SelectableText('${field.$2}\n${item[field.$1]}'),
                  ),
              if (location.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open map'),
                  onPressed: () async {
                    final uri = Uri.https('maps.apple.com', '/', {
                      'q': location,
                    });
                    try {
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw Exception('Could not open map.');
                      }
                    } catch (_) {
                      if (context.mounted) {
                        message(context, 'Could not open map.');
                      }
                    }
                  },
                ),
              if (event)
                ListenableBuilder(
                  listenable: repository.experience,
                  builder: (context, _) => OutlinedButton.icon(
                    icon: const Icon(Icons.bookmark_outline),
                    label: Text(
                      repository.experience.savedEvents.any(
                            (e) => e['id'] == item['id'],
                          )
                          ? 'Remove saved event'
                          : 'Save event',
                    ),
                    onPressed: () => repository.experience.saveEvent(item),
                  ),
                ),
              if (event && DateTime.tryParse('${item['starts_at']}') != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Export to calendar (.ics)'),
                  onPressed: () async {
                    try {
                      if (defaultTargetPlatform == TargetPlatform.iOS ||
                          defaultTargetPlatform == TargetPlatform.android) {
                        final uri = Api.site.resolve(
                          '/api/v1/events/${item['id']}/calendar.ics',
                        );
                        if (!await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw Exception('Could not open calendar file.');
                        }
                        return;
                      }
                      final location = await getSaveLocation(
                        suggestedName: 'community-event.ics',
                      );
                      if (location == null) return;
                      await XFile.fromData(
                        utf8.encode(calendarEvent(item)),
                        mimeType: 'text/calendar',
                        name: 'community-event.ics',
                      ).saveTo(location.path);
                      if (context.mounted) {
                        message(
                          context,
                          'Calendar file saved. Open it with your calendar app.',
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        message(
                          context,
                          'Calendar export is not available on this device.',
                        );
                      }
                    }
                  },
                ),
              for (final link in [
                if (item['website'] is String)
                  (item['website'] as String, 'Visit website'),
                if (item['organizer_url'] is String)
                  (item['organizer_url'] as String, 'Organizer page'),
                if (!event && item['phone'] is String)
                  ('tel:${item['phone']}', 'Call business'),
              ])
                TextButton(
                  onPressed: () async {
                    final uri = Uri.tryParse(link.$1);
                    if (uri == null ||
                        !['https', 'http', 'tel'].contains(uri.scheme)) {
                      return;
                    }
                    try {
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw Exception();
                      }
                    } catch (_) {
                      if (context.mounted) {
                        message(context, 'Could not open this link.');
                      }
                    }
                  },
                  child: Text(link.$2),
                ),
              if (!event)
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Request a listing correction'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => NewsTipsPage(
                        repository: repository,
                        kind: 'business_change',
                        targetId: item['id'],
                        initialTitle: 'Business correction: ${item['name']}',
                        initialBody: 'Your relationship to the business: \nRequested changes: \nVerification link: ',
                      ),
                    ),
                  ),
                ),
              if (event)
                const Notice(
                  'Confirm the schedule and admission with the organizer before attending.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
