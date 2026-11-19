import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'ui/iphone_news.dart';

import 'package:flutter_quill/flutter_quill.dart';

import 'data/api.dart';
import 'data/push_notifications.dart';
import 'data/local_store.dart';
import 'data/repository.dart';
import 'data/promotions.dart';
import 'ui/home.dart';
import 'ui/brand.dart';
import 'ui/responsive.dart';
import 'ui/keyboard_dismiss.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId:
        'com.fayettevillepeoplevoice.peopleVoice.podcasts',
    androidNotificationChannelName: 'Podcast playback',
    androidNotificationOngoing: true,
  );
  try {
    final store = await LocalStore.open();
    final api = Api();
    final session = Session(api);
    await session.restore();
    unawaited(session.renewIfNeeded());
    runApp(
      PeopleVoiceApp(
        repository: Repository(
          api,
          store,
          session: session,
          promotions: PromotionApi(),
          push: InAppPush(store, owner: () => session.userId ?? 0),
        ),
        session: session,
      ),
    );
  } catch (_) {
    runApp(StorageRecoveryApp(onRetry: main));
  }
}

class StorageRecoveryApp extends StatefulWidget {
  const StorageRecoveryApp({super.key, required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  State<StorageRecoveryApp> createState() => _StorageRecoveryAppState();
}

class _StorageRecoveryAppState extends State<StorageRecoveryApp> {
  bool busy = false;

  Future<void> retry() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: defaultTargetPlatform == TargetPlatform.iOS
        ? iphoneTheme(Brightness.light)
        : Brand.theme(),
    darkTheme: defaultTargetPlatform == TargetPlatform.iOS
        ? iphoneTheme(Brightness.dark)
        : Brand.theme(brightness: Brightness.dark),
    home: Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppEmptyState(
                    title: 'Let’s reopen your stories',
                    message: 'Device storage could not be opened. Try again or restart the app. Keep the app data: it may contain your saved drafts.',
                    icon: Icons.folder_off_outlined,
                    actionLabel: 'Try again',
                    onAction: busy ? null : retry,
                  ),
                  if (busy)
                    const CircularProgressIndicator(
                      semanticsLabel: 'Opening device storage',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PeopleVoiceApp extends StatefulWidget {
  const PeopleVoiceApp({
    super.key,
    required this.repository,
    required this.session,
  });
  final Repository repository;
  final Session session;
  @override
  State<PeopleVoiceApp> createState() => _PeopleVoiceAppState();
}

class _PeopleVoiceAppState extends State<PeopleVoiceApp>
    with WidgetsBindingObserver {
  int? loadedOwner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.repository.push?.start());
    widget.session.addListener(accountChanged);
    accountChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final push = widget.repository.push;
    if (push == null) return;
    push.active = state == AppLifecycleState.resumed;
    if (push.active) unawaited(push.retry());
  }

  void accountChanged() {
    final owner = widget.session.userId ?? 0;
    if (loadedOwner == owner) return;
    loadedOwner = owner;
    widget.repository.experience.load(owner).catchError((Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repository.push?.dispose();
    widget.session.removeListener(accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repository.experience,
    builder: (context, _) => MaterialApp(
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      locale: const Locale('en', 'US'),
      supportedLocales: const [Locale('en', 'US')],
      title: 'Fayetteville · The People Voice',
      builder: (context, child) =>
          KeyboardDismiss(child: child ?? const SizedBox.shrink()),
      debugShowCheckedModeBanner: false,
      theme: defaultTargetPlatform == TargetPlatform.iOS
          ? iphoneTheme(Brightness.light)
          : Brand.theme(),
      darkTheme: defaultTargetPlatform == TargetPlatform.iOS
          ? iphoneTheme(Brightness.dark)
          : Brand.theme(brightness: Brightness.dark),
      themeMode:
          (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS) &&
              widget.repository.experience.theme == ThemeMode.system
          ? ThemeMode.dark
          : widget.repository.experience.theme,
      home: Home(repository: widget.repository, session: widget.session),
    ),
  );
}
