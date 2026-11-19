import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'local_store.dart';

/// App-only promotion service. Stripe payment confirmation is handled by its
/// server webhook; returning from Checkout never counts as a paid promotion.
class PromotionApi {
  PromotionApi({Uri? baseUrl, http.Client? client})
    : baseUrl =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'PODCAST_API_BASE_URL',
              defaultValue: 'https://podcasts.fayettevillethepeoplevoice.com',
            ),
          ),
      client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client client;

  Uri _uri(String path) {
    if (baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty) {
      throw ApiFailure('The promotion service is not configured.');
    }
    return baseUrl.resolve(path);
  }

  Future<Json> _request(String path, {String? token, Json? body}) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      };
      final response =
          await (body == null
                  ? client.get(_uri(path), headers: headers)
                  : client.post(
                      _uri(path),
                      headers: headers,
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = () {
          try {
            return (jsonDecode(response.body) as Json)['detail'] as String?;
          } catch (_) {
            return null;
          }
        }();
        throw ApiFailure(
          detail ??
              switch (response.statusCode) {
                401 => 'Sign in again to promote an article.',
                403 => 'Administrator access is required.',
                404 => 'Promotion service update is not installed yet.',
                409 => 'This promotion changed. Refresh and try again.',
                _ => 'Promotion service error (${response.statusCode}).',
              },
          status: response.statusCode,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Json) throw const FormatException('Invalid response');
      return decoded;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure('Could not reach the promotion service. Try again.');
    }
  }

  Future<Json> pricing() => _request('/promotions/pricing');

  Future<String> checkout({
    required int articleId,
    required String token,
    required String operationId,
  }) async {
    final response = await _request(
      '/promotions/checkout',
      token: token,
      body: {'article_id': articleId, 'operation_id': operationId},
    );
    final value = response['data']?['checkout_url'];
    if (value is! String) throw ApiFailure('Invalid Stripe Checkout link.');
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != 'https' ||
        !{'checkout.stripe.com', 'buy.stripe.com'}.contains(url.host) ||
        url.userInfo.isNotEmpty) {
      throw ApiFailure('Invalid Stripe Checkout link.');
    }
    return value;
  }

  Future<List<Json>> featured() async {
    final response = await _request('/promotions/featured');
    final values = response['data'];
    if (values is! List ||
        values.any(
          (item) =>
              item is! Json || item['id'] is! int || item['title'] is! String,
        )) {
      throw ApiFailure('The promoted article list is invalid.');
    }
    return List<Json>.from(values);
  }

  Future<List<Json>> pending(String token) async {
    final response = await _request('/promotions/admin/pending', token: token);
    final values = response['data'];
    if (values is! List || values.any((item) => item is! Json)) {
      throw ApiFailure('The paid promotion list is invalid.');
    }
    return List<Json>.from(values);
  }

  Future<List<Json>> notifications(String token) async {
    final response = await _request(
      '/promotions/admin/notifications',
      token: token,
    );
    final values = response['data'];
    if (values is! List || values.any((item) => item is! Json)) {
      throw ApiFailure('The paid promotion alerts are invalid.');
    }
    return List<Json>.from(values);
  }

  Future<Json> decide(
    int promotionId,
    String token, {
    required String decision,
    required int version,
    String? reason,
  }) => _request(
    '/promotions/admin/$promotionId/decision',
    token: token,
    body: {'decision': decision, 'version': version, 'reason': reason},
  );

  Future<List<Json>> mine(String token) async {
    final response = await _request('/promotions/mine', token: token);
    final values = response['data'];
    if (values is! List || values.any((item) => item is! Json)) {
      throw ApiFailure('Your promotion list is invalid.');
    }
    return List<Json>.from(values);
  }
}
