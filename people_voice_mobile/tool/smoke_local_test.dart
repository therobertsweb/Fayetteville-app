import 'package:people_voice/data/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter client reads the local API and image uploads require authentication', () async {
    final api = Api();
    addTearDown(api.client.close);
    final posts = await api.request('/posts');
    expect(posts['data'], isA<List>());
    if ((posts['data'] as List).isNotEmpty) {
      final first = posts['data'][0];
      final article = await api.request('/posts/${first['id']}');
      expect(article['data']['content'], isA<String>());
    }
    await expectLater(
      api.request('/media/images', body: {}),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 401)),
    );
  });

  const email = String.fromEnvironment('SMOKE_EMAIL');
  const password = String.fromEnvironment('SMOKE_PASSWORD');
  test(
    'Flutter client reaches authenticated editorial management',
    () async {
      final api = Api();
      addTearDown(api.client.close);
      final login = await api.request(
        '/auth/login',
        body: {'email': email, 'password': password},
      );
      final token = login['access_token'] as String;
      final capabilities = await api.request(
        '/mobile/capabilities',
        token: token,
      );
      final drafts = await api.request('/admin/drafts', token: token);
      expect(capabilities['data']['role'], 'admin');
      expect(drafts['data'], isA<List>());
    },
    skip: email.isEmpty || password.isEmpty
        ? 'Provide SMOKE_EMAIL and SMOKE_PASSWORD for a test administrator.'
        : false,
  );
}
