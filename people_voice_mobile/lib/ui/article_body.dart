import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../data/api.dart';
import '../data/article_media.dart';
import '../data/repository.dart';
import 'home.dart';
import 'reader.dart';

Future<bool> openArticleLink(BuildContext context, String source) async {
  final uri = Api.site.resolve(source);
  if (!['https', 'http', 'mailto', 'tel'].contains(uri.scheme)) return false;
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
  } catch (_) {}
  if (context.mounted) {
    message(context, 'Could not open this link. Try again when online.');
  }
  return false;
}

class ArticleBody extends StatelessWidget {
  const ArticleBody({
    super.key,
    required this.content,
    required this.repository,
    this.imageVersion = 0,
  });
  final String content;
  final Repository repository;
  final int imageVersion;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository.experience,
    builder: (context, _) => HtmlWidget(
      content,
      textStyle: TextStyle(
        fontSize: repository.experience.fontSize,
        height: 1.6,
      ),
      onTapUrl: (url) => openArticleLink(context, url),
      customWidgetBuilder: (element) {
        if (element.localName == 'img') {
          final source = element.attributes['src'];
          final width = double.tryParse(element.attributes['width'] ?? '');
          final height = double.tryParse(element.attributes['height'] ?? '');
          final aspectRatio =
              width != null && height != null && width > 0 && height > 0
              ? (width / height).clamp(0.5, 3.0)
              : 16 / 9;
          return AspectRatio(
            aspectRatio: aspectRatio,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: OfflineImage(
                key: ValueKey('$source-$imageVersion'),
                repository: repository,
                source: source,
              ),
            ),
          );
        }
        if (['iframe', 'video'].contains(element.localName)) {
          final source =
              element.attributes['src'] ??
              element.querySelector('source')?.attributes['src'];
          if (source != null) {
            return ArticleVideo(key: ValueKey(source), source: source);
          }
        }
        return null;
      },
    ),
  );
}

class ArticleVideo extends StatefulWidget {
  const ArticleVideo({super.key, required this.source});
  final String source;
  @override
  State<ArticleVideo> createState() => _ArticleVideoState();
}

class _ArticleVideoState extends State<ArticleVideo> {
  WebViewController? controller;
  String? error;

  Future<void> play() async {
    final source = videoSource(widget.source);
    if (source == null) return;
    try {
      PlatformWebViewControllerCreationParams params =
          const PlatformWebViewControllerCreationParams();
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
        );
      }
      final player = WebViewController.fromPlatformCreationParams(params);
      await player.setJavaScriptMode(JavaScriptMode.unrestricted);
      await player.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            if (uri == null || !['https', 'http'].contains(uri.scheme)) {
              return NavigationDecision.prevent;
            }
            if (request.isMainFrame &&
                uri.host != Uri.parse(source).host &&
                uri.host != Api.site.host) {
              openArticleLink(context, request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (failure) {
            if (failure.isForMainFrame == true && mounted) {
              setState(
                () => error = 'Video unavailable. Check your connection or open it in your browser.',
              );
            }
          },
        ),
      );
      final escaped = const HtmlEscape().convert(source);
      final media = isProviderVideo(source)
          ? '<iframe src="$escaped" allow="fullscreen; encrypted-media; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>'
          : '<video controls playsinline preload="metadata" src="$escaped"></video>';
      await player.loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#111;height:100%}iframe,video{border:0;width:100%;height:100%}</style></head><body>$media</body></html>',
        baseUrl: Api.site.resolve('/').toString(),
      );
      if (mounted) {
        setState(() {
          controller = player;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not load the player. Open the video in your browser.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = videoSource(widget.source) != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller != null && error == null)
              SizedBox(
                height: widget.source.contains('tiktok.com') ? 480 : 280,
                child: WebViewWidget(controller: controller!),
              )
            else ...[
              const Icon(Icons.ondemand_video, size: 48),
              const SizedBox(height: 8),
              Text(
                error ??
                    (valid
                        ? 'Video · Internet connection required'
                        : 'Unsupported video link'),
              ),
              if (valid)
                FilledButton.tonalIcon(
                  onPressed: play,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play video'),
                ),
            ],
            if (valid)
              TextButton.icon(
                onPressed: () => openArticleLink(context, widget.source),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open video in browser'),
              ),
          ],
        ),
      ),
    );
  }
}
