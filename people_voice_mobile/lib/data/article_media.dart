import 'dart:convert';
import 'dart:ui' show ImmutableBuffer, ImageDescriptor;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:html/parser.dart' as html;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'api.dart';
import 'editorial.dart';
import 'local_store.dart';

const localImagePrefix = '/local-images/';

bool isHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !RegExp(r'[\s\\<>]').hasMatch(value);
}

/// Converts public provider URLs to player URLs without fetching remote pages.
String? videoSource(String value) {
  if (!isHttpsUrl(value)) return null;
  final uri = Uri.parse(value);
  final host = uri.host.toLowerCase();
  final parts = uri.pathSegments;
  bool domain(String name) => host == name || host.endsWith('.$name');
  if (domain('youtube.com') ||
      domain('youtube-nocookie.com') ||
      host == 'youtu.be') {
    final id = host == 'youtu.be'
        ? parts.firstOrNull
        : (parts.length >= 2 &&
                  ['embed', 'shorts', 'live'].contains(parts.first)
              ? parts[1]
              : uri.queryParameters['v']);
    if (id == null || !RegExp(r'^[\w-]+$').hasMatch(id)) return null;
    return 'https://www.youtube-nocookie.com/embed/$id';
  }
  if (domain('vimeo.com')) {
    final id = parts.where((p) => RegExp(r'^\d+$').hasMatch(p)).firstOrNull;
    if (id == null) return null;
    final hash =
        uri.queryParameters['h'] ?? (parts.length == 2 ? parts[1] : null);
    return Uri.https(
      'player.vimeo.com',
      '/video/$id',
      hash != null && hash != id ? {'h': hash} : null,
    ).toString();
  }
  if (domain('tiktok.com')) {
    final match = RegExp(r'/(?:video|player/v1|embed/v2)/(\d+)')
        .firstMatch(uri.path);
    return match == null
        ? null
        : 'https://www.tiktok.com/player/v1/${match[1]}';
  }
  if (domain('facebook.com')) {
    if (uri.path == '/plugins/video.php') {
      final original = uri.queryParameters['href'];
      if (original == null || !isHttpsUrl(original)) return null;
      final originalHost = Uri.parse(original).host;
      if (originalHost != 'facebook.com' &&
          !originalHost.endsWith('.facebook.com')) {
        return null;
      }
      return value;
    }
    if (!uri.path.contains('/videos/') &&
        !uri.path.startsWith('/reel/') &&
        !uri.path.startsWith('/watch') &&
        uri.path != '/video.php') {
      return null;
    }
    return Uri.https('www.facebook.com', '/plugins/video.php', {
      'href': value,
      'show_text': 'false',
    }).toString();
  }
  // Direct media may use signed URLs or an endpoint without a file extension.
  return value;
}

bool isProviderVideo(String source) {
  final host = Uri.tryParse(source)?.host ?? '';
  return [
    'youtube.com',
    'youtube-nocookie.com',
    'vimeo.com',
    'tiktok.com',
    'facebook.com',
  ].any((d) => host == d || host.endsWith('.$d'));
}

Document articleDocument({
  List<dynamic>? delta,
  String content = '',
  String plainText = '',
}) {
  if (delta != null && delta.isNotEmpty) return Document.fromJson(delta);
  if (content.isNotEmpty) {
    final fragment = html.parseFragment(content);
    // The importer understands video; represent provider iframes the same way.
    for (final frame in fragment.querySelectorAll('iframe')) {
      frame.replaceWith(
        html
            .parseFragment(
              '<video src="${const HtmlEscape().convert(frame.attributes['src'] ?? '')}"></video>',
            )
            .nodes
            .first,
      );
    }
    final imported = HtmlToDelta().convert(fragment.outerHtml);
    return imported.isEmpty ? Document() : Document.fromDelta(imported);
  }
  return Document()..insert(0, plainText);
}

String articleHtml(Document document) {
  final converter = QuillDeltaToHtmlConverter(document.toDelta().toJson());
  final fragment = html.parseFragment(converter.convert());
  for (final frame in fragment.querySelectorAll('iframe')) {
    final source = frame.attributes['src'] ?? '';
    if (!isProviderVideo(source)) {
      frame.replaceWith(
        html
            .parseFragment(
              '<video controls playsinline preload="metadata" src="${const HtmlEscape().convert(source)}"></video>',
            )
            .nodes
            .first,
      );
    }
  }
  return fragment.outerHtml;
}

Future<String?> selectArticleImage(LocalStore store) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        uniformTypeIdentifiers: [
          'public.jpeg',
          'public.png',
          'org.webmproject.webp',
          'com.compuserve.gif',
        ],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > 5 * 1024 * 1024) {
    throw ApiFailure('Choose an image smaller than 5 MB.');
  }
  final bytes = await file.readAsBytes();
  final buffer = await ImmutableBuffer.fromUint8List(bytes);
  ImageDescriptor? descriptor;
  try {
    descriptor = await ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 20000000) {
      throw ApiFailure('Choose an image with fewer than 20 million pixels.');
    }
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
  final extension = file.name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension)) {
    throw ApiFailure('Choose a JPG, PNG, WebP or GIF image.');
  }
  final key = '$localImagePrefix${operationId()}.$extension';
  await store.saveImage(key, bytes);
  return key;
}
