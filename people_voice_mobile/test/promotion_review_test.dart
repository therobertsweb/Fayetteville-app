import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:people_voice/data/api.dart';
import 'package:people_voice/data/editorial.dart';
import 'package:people_voice/data/local_store.dart';
import 'package:people_voice/data/repository.dart';
import 'package:people_voice/data/promotions.dart';
import 'package:people_voice/ui/promotion_review.dart';

class _UnusedStore extends Fake implements LocalStore {}

Session _session(Api api) => Session(api)
  ..value = {
    'user': {'id': 7, 'username': 'Admin'},
    'access_token': 'admin-token',
    'expires_at': DateTime.now()
        .add(const Duration(hours: 1))
        .toIso8601String(),
  };

final _request = <String, dynamic>{
  'id': 51,
  'version': 3,
  'status': 'pending',
  'payment_status': 'paid',
  'paid_at': '2026-10-20T18:00:00Z',
  'article': {'id': 72, 'title': 'Community story'},
  'user': {'id': 19, 'username': 'Author', 'email': 'author@example.com'},
};

void main() {
  test(
    'only an admin with promotion review access can decide paid requests',
    () async {
      final writes = <Map<String, dynamic>>[];
      var role = 'admin';
      var permissions = <String>['promotions:review'];
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/mobile/capabilities')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'user_id': 7,
                  'role': role,
                  'permissions': permissions,
                },
              }),
              200,
            );
          }
          expect(request.headers['Authorization'], 'Bearer admin-token');
          if (request.method == 'GET') {
            expect(request.url.path, '/api/v1/admin/promotions');
            return http.Response(
              jsonEncode({
                'data': [_request],
                'next_cursor': null,
              }),
              200,
            );
          }
          expect(request.url.path, '/api/v1/admin/promotions/51/decision');
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"data":{"status":"approved"}}', 200);
        }),
      );
      final gateway = EditorialGateway(api, _session(api));
      expect(await gateway.pendingPromotions(), hasLength(1));
      await gateway.decidePromotion(_request, decision: 'approve');
      expect(writes.single['decision'], 'approve');
      expect(writes.single['version'], 3);
      expect(writes.single['operation_id'], isA<String>());
      await gateway.decidePromotion(
        _request,
        decision: 'reject',
        reason: '  This article does not meet our advertising policy.  ',
      );
      expect(writes.last['decision'], 'reject');
      expect(
        writes.last['reason'],
        'This article does not meet our advertising policy.',
      );
      await expectLater(
        gateway.decidePromotion(_request, decision: 'reject', reason: ''),
        throwsArgumentError,
      );
      await expectLater(
        gateway.decidePromotion({
          ..._request,
          'payment_status': 'unpaid',
        }, decision: 'approve'),
        throwsA(isA<ApiFailure>()),
      );
      role = 'author';
      await expectLater(
        gateway.pendingPromotions(),
        throwsA(isA<ApiFailure>()),
      );
      permissions = [];
      role = 'admin';
      await expectLater(
        gateway.pendingPromotions(),
        throwsA(isA<ApiFailure>()),
      );
      expect(writes, hasLength(2));
      api.client.close();
    },
  );

  testWidgets(
    'admin sees buyer and article before approving the paid request',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      final api = Api(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final promotionApi = PromotionApi(
        client: MockClient((request) async {
          expect(request.url.host, 'podcasts.fayettevillethepeoplevoice.com');
          if (request.method == 'GET') {
            expect(request.url.path, '/promotions/admin/pending');
            return http.Response(
              jsonEncode({
                'data': [_request],
              }),
              200,
            );
          }
          expect(request.url.path, '/promotions/admin/51/decision');
          writes.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"data":{"status":"approved"}}', 200);
        }),
      );
      final session = _session(api);
      final gateway = EditorialGateway(api, session);
      await tester.pumpWidget(
        MaterialApp(
          home: PromotionReviewPage(
            gateway: gateway,
            repository: Repository(api, _UnusedStore(), session: session),
            promotionApi: promotionApi,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Community story'), findsOneWidget);
      expect(find.textContaining('Author · User #19'), findsOneWidget);
      expect(find.text('author@example.com'), findsOneWidget);
      expect(find.text('Article #72 · Payment confirmed'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('Approve promotion?'), findsOneWidget);
      await tester.tap(find.text('Approve').last);
      await tester.pumpAndSettle();
      expect(writes.single['decision'], 'approve');
      expect(writes.single['version'], 3);
      expect(tester.takeException(), isNull);
      api.client.close();
      promotionApi.client.close();
    },
  );
}
