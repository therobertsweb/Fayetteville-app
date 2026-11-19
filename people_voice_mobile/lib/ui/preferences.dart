import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'brand.dart';
import 'home.dart' show Notice, message;
import 'responsive.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key, required this.repository});
  final Repository repository;
  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  double? previewSize;
  bool syncing = false;

  Future<void> save(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (mounted) {
        message(context, 'Could not save this setting. Please try again.');
      }
    }
  }

  Future<void> sync() async {
    setState(() => syncing = true);
    try {
      await widget.repository.experience.sync();
      if (mounted) {
        message(
          context,
          widget.repository.experience.syncWarning ??
              'Preferences are up to date.',
        );
      }
    } catch (_) {
      if (mounted) {
        message(
          context,
          'Could not sync. Your saved settings are still on this device.',
        );
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.repository.experience;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final textSize = previewSize ?? prefs.fontSize;
        final categories = prefs.strings('categories');
        final authors = prefs.strings('authors');
        final blocked = prefs.strings('blocked');
        return Scaffold(
          appBar: AppBar(title: const Text('Reading & notifications')),
          body: SafeArea(
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SectionHeading(
                    'Make yourself at home',
                    eyebrow: 'YOUR PREFERENCES',
                    subtitle:
                        'Choose how you read and which updates reach you.',
                  ),
                  _PreferenceSection(
                    icon: Icons.contrast,
                    title: 'Appearance',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose a theme',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in [
                              (
                                'system',
                                'System',
                                Icons.brightness_auto_outlined,
                              ),
                              ('light', 'Light', Icons.light_mode_outlined),
                              ('dark', 'Dark', Icons.dark_mode_outlined),
                            ])
                              ChoiceChip(
                                avatar: Icon(entry.$3, size: 18),
                                label: Text(entry.$2),
                                selected: prefs.theme.name == entry.$1,
                                onSelected: (_) =>
                                    save(prefs.set('theme', entry.$1)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Article text size: ${textSize.round()}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Slider(
                          value: textSize,
                          min: 14,
                          max: 28,
                          divisions: 7,
                          label: '${textSize.round()}',
                          semanticFormatterCallback: (value) =>
                              '${value.round()} point text',
                          onChanged: (value) =>
                              setState(() => previewSize = value),
                          onChangeEnd: (value) async {
                            await save(prefs.set('fontSize', value));
                            if (mounted) setState(() => previewSize = null);
                          },
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'READING PREVIEW',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Your community, your voice.',
                                style: TextStyle(
                                  fontSize: textSize,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.repository.push case final push?)
                    ListenableBuilder(
                      listenable: push,
                      builder: (context, _) => _PreferenceSection(
                        icon: Icons.notifications_active_outlined,
                        title: 'Live updates in the app',
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('News and podcasts'),
                              subtitle: const Text(
                                'Updates appear in your inbox while the app is open. No system banners or sounds.',
                              ),
                              value: push.enabled,
                              onChanged: push.ready && !push.busy
                                  ? push.setEnabled
                                  : null,
                            ),
                            if (push.busy) const LinearProgressIndicator(),
                            if (push.error != null) ...[
                              Notice(push.error!),
                              TextButton(
                                onPressed: push.busy ? null : push.retry,
                                child: const Text('Retry'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  _PreferenceSection(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    child: Column(
                      children: [
                        for (final entry in [
                          (
                            'replies',
                            'Replies to my comments',
                            'Keep the conversation going.',
                          ),
                          (
                            'authors',
                            'Authors I follow',
                            'New stories from your favorite voices.',
                          ),
                          (
                            'events',
                            'Saved event reminders',
                            'A reminder before your saved events.',
                          ),
                        ])
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.$2),
                            subtitle: Text(entry.$3),
                            value: prefs.enabled(entry.$1),
                            onChanged: (value) =>
                                save(prefs.set('notify:${entry.$1}', value)),
                          ),
                        const SizedBox(height: 8),
                        const Notice(
                          'Account activity appears in this inbox. Live news and podcast updates can be enabled above; all updates are shown inside the app.',
                          icon: Icons.info_outline,
                        ),
                      ],
                    ),
                  ),
                  _PreferenceSection(
                    icon: Icons.interests_outlined,
                    title: 'Your interests',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Followed topics',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (categories.isEmpty)
                          Text(
                            'Follow a topic from Categories to see its stories in For you.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final category in categories)
                                InputChip(
                                  label: Text(category),
                                  onDeleted: () => save(
                                    prefs.toggle('categories', category),
                                  ),
                                  deleteButtonTooltipMessage:
                                      'Unfollow $category',
                                ),
                            ],
                          ),
                        const Divider(height: 32),
                        Text(
                          'Followed authors',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (authors.isEmpty)
                          Text(
                            'Tap Follow author in an article to keep up with their work.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        for (final id in authors)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(
                              prefs.value['authorName:$id'] as String? ??
                                  'Author $id',
                            ),
                            trailing: IconButton(
                              tooltip: 'Unfollow author',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () =>
                                  save(prefs.toggle('authors', id)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _PreferenceSection(
                    icon: Icons.shield_outlined,
                    title: 'Your community controls',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (blocked.isEmpty)
                          Text(
                            'No blocked users. You can manage who you see from the comments on any article.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        for (final id in blocked)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_off_outlined),
                            title: Text('User $id'),
                            trailing: TextButton(
                              onPressed: () =>
                                  save(prefs.toggle('blocked', id)),
                              child: const Text('Unblock'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Notice(
                    prefs.owner == 0
                        ? 'Your preferences are saved on this device. Sign in to sync them across devices.'
                        : prefs.syncWarning ?? 'Preferences sync with your account across devices.',
                    icon: prefs.owner == 0
                        ? Icons.phone_android
                        : Icons.cloud_done_outlined,
                  ),
                  if (prefs.owner != 0)
                    OutlinedButton.icon(
                      onPressed: syncing ? null : sync,
                      icon: const Icon(Icons.sync),
                      label: Text(syncing ? 'Syncing…' : 'Sync preferences'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
}
