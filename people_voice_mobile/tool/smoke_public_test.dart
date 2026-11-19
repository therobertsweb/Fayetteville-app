import 'package:flutter_test/flutter_test.dart';
import 'package:people_voice/data/api.dart';

/// Live, read-only checks. No credentials, writes, or payments.
void main() {
  test('deployed public API works through the Flutter HTTP client', () async {
    final api = Api();
    addTearDown(api.client.close);
    for (final path in [
      '/posts?page=1',
      '/posts/featured',
      '/search?q=community',
      '/events',
      '/businesses',
      '/rankings?metric=comments&days=7',
    ]) {
      final result = await api.request(path);
      expect(result['data'], isA<List>(), reason: path);
    }
    final feed = await api.request('/posts?page=1');
    final rows = feed['data'] as List;
    if (rows.isNotEmpty) {
      final id = rows.first['id'];
      final detail = await api.request('/posts/$id');
      expect(detail['data']['content'], isA<String>());
      expect(
        (await api.request('/posts/$id/comments?page=1'))['data'],
        isA<List>(),
      );
    }
    await expectLater(
      api.request('/mobile/capabilities'),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
  });
}
