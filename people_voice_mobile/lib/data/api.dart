import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'local_store.dart';

class ApiFailure implements Exception {
  ApiFailure(this.message, {this.status, this.uncertain = false});
  final String message;
  final int? status;
  final bool uncertain;
  @override
  String toString() => message;
}

class Api {
  Api({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  static final Uri site = Uri.parse(
    const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://fayettevillethepeoplevoice.com',
    ),
  );

  Future<String> uploadImage(
    Uint8List bytes,
    String filename,
    String token,
  ) async {
    try {
      final request =
          http.MultipartRequest('POST', site.resolve('/api/v1/media/images'))
            ..headers['Authorization'] = 'Bearer $token'
            ..files.add(
              http.MultipartFile.fromBytes('image', bytes, filename: filename),
            );
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 201) {
        throw ApiFailure(
          response.statusCode == 401
              ? 'Sign in again to upload images.'
              : 'Could not upload the image (${response.statusCode}). Your local copy is saved.',
          status: response.statusCode,
        );
      }
      final source = jsonDecode(response.body)['data']?['url'];
      if (source is! String ||
          !source.startsWith('/static/media/posts/editor/')) {
        throw const FormatException('Invalid image response');
      }
      return source;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure(
        'Image upload failed. Your local copy is saved. Reconnect and retry.',
      );
    }
  }

  Future<String> featuredCheckout({
    required int postId,
    required String token,
    required String operationId,
  }) async {
    final response = await request(
      '/posts/$postId/featured/checkout',
      body: {'operation_id': operationId},
      token: token,
    );
    final url = response['data']?['checkout_url'];
    if (url is! String || !url.startsWith('https://checkout.stripe.com/')) {
      throw ApiFailure('Stripe returned an invalid checkout link.');
    }
    return url;
  }

  Future<Json> request(String path, {Json? body, String? token}) async {
    final uri = site.resolve('/api/v1$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode == 204) return {};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = switch (response.statusCode) {
          401 => 'Your session expired. Please sign in again.',
          403 =>
            'This account does not have permission to perform this action.',
          404 => 'This content is not available.',
          409 =>
            'This identifier is already in use. Review the previous operation.',
          429 =>
            'Too many requests. Please wait ${response.headers['retry-after'] ?? '60'} seconds.',
          >= 500 =>
            'The server could not complete the request (${response.statusCode}).',
          _ =>
            'The server rejected the data (${response.statusCode}). Check the fields.',
        };
        throw ApiFailure(
          message,
          status: response.statusCode,
          uncertain: body != null && response.statusCode >= 500,
        );
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Expected object');
      }
      return data;
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw ApiFailure(
        'The connection timed out. Your local data is still saved.',
        uncertain: body != null,
      );
    } on SocketException {
      throw ApiFailure(
        'You are offline. Your local data is still saved.',
        uncertain: body != null,
      );
    } on http.ClientException {
      throw ApiFailure(
        'Could not connect. Your local data is still saved.',
        uncertain: body != null,
      );
    } on FormatException {
      throw ApiFailure(
        'The server returned an unexpected response.',
        uncertain: body != null,
      );
    }
  }
}
