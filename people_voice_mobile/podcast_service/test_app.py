import tempfile
import asyncio
import unittest
import json
import hmac
import hashlib
import time
import io
import os
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs

from fastapi.testclient import TestClient
import httpx

from podcast_service import app as service
from podcast_service import stripe_diagnostic


class PodcastServiceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.old_dir = service.DATA_DIR
        service.DATA_DIR = Path(self.directory.name)
        self.client = TestClient(service.app)

    def tearDown(self):
        self.client.close()
        service.DATA_DIR = self.old_dir
        self.directory.cleanup()

    def test_public_feed_and_authenticated_upload(self):
        self.assertEqual(self.client.get('/episodes').json()['data'], [])
        denied = self.client.post('/episodes', data={'title': 'News audio'}, files={
            'audio': ('voice.mp3', b'ID3' + b'\0' * 20, 'audio/mpeg'),
            'cover': ('cover.png', b'\x89PNG\r\n\x1a\n' + b'\0' * 20, 'image/png'),
        })
        self.assertEqual(denied.status_code, 401)

        async def authenticated(_):
            return 7, 'Reporter', 'token'

        with patch.object(service, 'authenticate', authenticated):
            created = self.client.post('/episodes', headers={'Authorization': 'Bearer token'},
                data={'title': 'News audio'}, files={
                    'audio': ('voice.mp3', b'ID3' + b'\0' * 20, 'audio/mpeg'),
                    'cover': ('cover.png', b'\x89PNG\r\n\x1a\n' + b'\0' * 20, 'image/png'),
                })
        self.assertEqual(created.status_code, 201, created.text)
        entry = created.json()['data']
        self.assertEqual(entry['author'], 'Reporter')
        self.assertTrue(entry['audio_url'].endswith('.mp3'))
        self.assertEqual(self.client.get('/episodes').json()['data'][0]['id'], entry['id'])
        media_key = entry['cover_url'].rsplit('/', 1)[-1]
        self.assertEqual(self.client.get('/media/' + media_key).status_code, 200)
        audio_key = entry['audio_url'].rsplit('/', 1)[-1]
        partial = self.client.get('/media/' + audio_key, headers={'Range': 'bytes=0-2'})
        self.assertEqual(partial.status_code, 206)
        self.assertEqual(partial.content, b'ID3')

    def test_article_uses_its_main_image(self):
        async def authenticated(_):
            return 8, 'Author', 'token'

        async def article(article_id, _):
            self.assertEqual(article_id, 42)
            return 'Article headline', 'https://fayettevillethepeoplevoice.com/static/main.jpg'

        with patch.object(service, 'authenticate', authenticated), patch.object(service, 'related_article', article):
            response = self.client.post('/episodes/links',
                headers={'Authorization': 'Bearer token'},
                data={'title': 'Discussion', 'article_id': '42',
                      'audio_url': 'https://media.example.com/episode.mp3'})
        self.assertEqual(response.status_code, 201, response.text)
        entry = response.json()['data']
        self.assertEqual(entry['cover_url'], 'https://fayettevillethepeoplevoice.com/static/main.jpg')
        self.assertEqual(entry['article'], {'id': 42, 'title': 'Article headline'})

    def test_youtube_is_not_misrepresented_as_mp3(self):
        with self.assertRaises(Exception):
            service.valid_audio_link('https://www.youtube.com/watch?v=123')

    def test_votes_are_one_per_account_and_comments_are_public(self):
        with service.db_connection() as db:
            db.execute("INSERT INTO episodes "
                "(title,author_id,author,audio_url,cover_file,created_at) "
                "VALUES (?,?,?,?,?,?)",
                ('Episode', 1, 'Author', 'https://media.example.com/a.mp3',
                 'https://site.example.com/main.jpg', '2026-10-20T10:00:00+00:00'))
            db.commit()

        async def authenticated(_):
            return 7, 'Listener', 'token'

        with patch.object(service, 'authenticate', authenticated):
            first = self.client.put('/episodes/1/reaction', json={'value': 'like'})
            again = self.client.put('/episodes/1/reaction', json={'value': 'like'})
            changed = self.client.put('/episodes/1/reaction', json={'value': 'dislike'})
            comment = self.client.post('/episodes/1/comments', json={'body': ' Insightful! '})
        self.assertEqual(first.json()['data']['likes'], 1)
        self.assertEqual(again.json()['data']['likes'], 1)
        self.assertEqual(changed.json()['data']['likes'], 0)
        self.assertEqual(changed.json()['data']['dislikes'], 1)
        self.assertEqual(comment.status_code, 201)
        self.assertEqual(comment.json()['data']['body'], 'Insightful!')
        self.assertEqual(comment.json()['data']['author_id'], 7)
        self.assertEqual(self.client.get('/episodes/1/comments').json()['data'][0]['author'], 'Listener')
        self.assertEqual(self.client.get('/episodes').json()['data'][0]['comment_count'], 1)

    def test_session_identity_and_article_ownership_come_from_news_api(self):
        calls = []

        class NewsClient:
            def __init__(self, **_):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_):
                pass

            async def get(self, url, **kwargs):
                calls.append((url, kwargs))
                if url.endswith('/mobile/capabilities'):
                    return httpx.Response(200, json={'data': {'user_id': 21,
                        'username': 'Verified author'}})
                return httpx.Response(200, json={'data': [
                    {'id': 31, 'published': True, 'title': 'Owned story',
                     'photo_link': '/static/main.jpg'},
                    {'id': 32, 'published': False, 'title': 'Draft'},
                ], 'next_cursor': None})

        with patch.object(service.httpx, 'AsyncClient', NewsClient):
            identity = asyncio.run(service.authenticate('Bearer real-token'))
            article = asyncio.run(service.related_article(31, identity[2]))
            with self.assertRaises(Exception):
                asyncio.run(service.related_article(32, identity[2]))
        self.assertEqual(identity[:2], (21, 'Verified author'))
        self.assertEqual(article, ('Owned story',
            'https://fayettevillethepeoplevoice.com/static/main.jpg'))
        self.assertTrue(all(call[1]['headers']['Authorization'] == 'Bearer real-token'
                            for call in calls))

    def test_only_admin_can_delete_episode_and_its_media_and_discussion(self):
        audio_name = 'a' * 32 + '.mp3'
        cover_name = 'b' * 32 + '.png'
        media_dir = service.DATA_DIR / 'media'
        media_dir.mkdir()
        (media_dir / audio_name).write_bytes(b'ID3')
        (media_dir / cover_name).write_bytes(b'cover')
        with service.db_connection() as db:
            db.execute(
                'INSERT INTO episodes '
                '(title,author_id,author,audio_url,cover_file,created_at) '
                'VALUES (?,?,?,?,?,?)',
                ('Episode', 7, 'Reporter',
                 f'{service.PUBLIC_BASE}/media/{audio_name}', cover_name,
                 '2026-10-20T10:00:00+00:00'),
            )
            db.execute('INSERT INTO comments '
                       '(episode_id,user_id,author,body,created_at) VALUES (1,7,?,?,?)',
                       ('Reporter', 'Comment', '2026-10-20T10:00:00+00:00'))
            db.execute('INSERT INTO reactions (episode_id,user_id,value) '
                       "VALUES (1,7,'like')")
            db.commit()

        role = 'commenter'

        class NewsClient:
            def __init__(self, **_):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_):
                pass

            async def get(self, *_args, **_kwargs):
                return httpx.Response(200, json={'data': {
                    'user_id': 7, 'role': role, 'username': 'Reporter',
                }})

        headers = {'Authorization': 'Bearer valid-token'}
        with patch.object(service.httpx, 'AsyncClient', NewsClient):
            self.assertEqual(self.client.delete('/episodes/1', headers=headers).status_code, 403)
            self.assertEqual(len(self.client.get('/episodes').json()['data']), 1)
            role = 'admin'
            self.assertEqual(self.client.delete('/episodes/1', headers=headers).status_code, 204)
            self.assertEqual(self.client.delete('/episodes/1', headers=headers).status_code, 404)
        self.assertEqual(self.client.get('/episodes').json()['data'], [])
        self.assertFalse((media_dir / audio_name).exists())
        self.assertFalse((media_dir / cover_name).exists())
        with service.db_connection() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM comments').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM reactions').fetchone()[0], 0)

    def test_paid_promotions_notify_admins_and_have_no_user_quota(self):
        next_id = 0

        class StripeClient:
            def __init__(self, **_):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_):
                pass

            async def post(self, _, **kwargs):
                nonlocal next_id
                next_id += 1
                promotion_id = kwargs['data']['client_reference_id']
                session_id = f'cs_test_{next_id}abc'
                return httpx.Response(200, json={
                    'id': session_id,
                    'url': f'https://checkout.stripe.com/c/pay/{session_id}',
                    'promotion_id': promotion_id,
                })

        async def authenticated(authorization, require_admin=False):
            if require_admin:
                if authorization != 'Bearer admin':
                    raise service.HTTPException(403, 'Administrators only')
                return 99, 'Admin', 'admin'
            if authorization == 'Bearer user-one':
                return 7, 'First author', 'user-one'
            if authorization == 'Bearer user-two':
                return 8, 'Second author', 'user-two'
            raise service.HTTPException(401, 'Sign in')

        async def article(article_id, token):
            return f'Article {article_id}', None

        async def public_article(article_id):
            return {'id': article_id, 'title': f'Article {article_id}',
                    'published': True,
                    'author': {'id': 7 if article_id in (10, 11) else 8,
                               'username': 'First author' if article_id in (10, 11)
                               else 'Second author'}}

        def webhook(promotion_id, session_id, buyer_id, article_id, event_id,
                    amount=500):
            payload = json.dumps({
                'id': event_id, 'type': 'checkout.session.completed',
                'livemode': False,
                'data': {'object': {'id': session_id, 'mode': 'payment',
                                    'amount_total': amount, 'currency': 'usd',
                                    'payment_status': 'paid',
                                    'metadata': {'promotion_id': str(promotion_id),
                                                 'buyer_id': str(buyer_id),
                                                 'article_id': str(article_id)}}},
            }).encode()
            timestamp = int(time.time())
            signed = hmac.new(b'whsec_test', str(timestamp).encode() + b'.' + payload,
                              hashlib.sha256).hexdigest()
            return payload, f't={timestamp},v1={signed}'

        with patch.object(service, 'STRIPE_SECRET_KEY', 'sk_test_fake'), \
             patch.object(service, 'STRIPE_WEBHOOK_SECRET', 'whsec_test'), \
             patch.object(service, 'authenticate', authenticated), \
             patch.object(service, 'related_article', article), \
             patch.object(service, 'public_article', public_article), \
             patch.object(service.httpx, 'AsyncClient', StripeClient):
            self.assertTrue(self.client.get('/promotions/pricing').json()['data']['available'])
            created = []
            for buyer, article_id, operation in [
                ('user-one', 10, 'a' * 32),
                ('user-one', 11, 'b' * 32),
                ('user-two', 12, 'c' * 32),
            ]:
                response = self.client.post('/promotions/checkout',
                    headers={'Authorization': f'Bearer {buyer}'},
                    json={'article_id': article_id, 'operation_id': operation})
                self.assertEqual(response.status_code, 201, response.text)
                created.append(response.json()['data'])
            # Retrying a checkout never creates another chargeable session.
            retry = self.client.post('/promotions/checkout',
                headers={'Authorization': 'Bearer user-one'},
                json={'article_id': 10, 'operation_id': 'a' * 32})
            self.assertEqual(retry.json()['data'], created[0])
            self.assertEqual(next_id, 3)
            self.assertEqual(self.client.get('/promotions/admin/pending',
                             headers={'Authorization': 'Bearer admin'}).json()['data'], [])

            payload, signature = webhook(created[0]['promotion_id'], 'cs_test_1abc',
                                         7, 10, 'evt_1')
            self.assertEqual(self.client.post('/promotions/stripe/webhook',
                content=payload, headers={'stripe-signature': 't=1,v1=bad'}).status_code, 400)
            wrong_amount, wrong_signature = webhook(created[0]['promotion_id'],
                'cs_test_1abc', 7, 10, 'evt_wrong_amount', amount=100)
            self.assertEqual(self.client.post('/promotions/stripe/webhook',
                content=wrong_amount,
                headers={'stripe-signature': wrong_signature}).status_code, 400)
            for promotion, session_id, buyer_id, article_id, event_id in [
                (created[0]['promotion_id'], 'cs_test_1abc', 7, 10, 'evt_1'),
                (created[1]['promotion_id'], 'cs_test_2abc', 7, 11, 'evt_2'),
                (created[2]['promotion_id'], 'cs_test_3abc', 8, 12, 'evt_3'),
            ]:
                payload, signature = webhook(promotion, session_id, buyer_id,
                                             article_id, event_id)
                response = self.client.post('/promotions/stripe/webhook',
                    content=payload, headers={'stripe-signature': signature})
                self.assertEqual(response.status_code, 200, response.text)
                self.assertEqual(self.client.post('/promotions/stripe/webhook',
                    content=payload,
                    headers={'stripe-signature': signature}).status_code, 200)
            self.assertEqual(self.client.get('/promotions/admin/pending',
                             headers={'Authorization': 'Bearer user-one'}).status_code, 403)
            pending = self.client.get('/promotions/admin/pending',
                                      headers={'Authorization': 'Bearer admin'}).json()['data']
            self.assertEqual(len(pending), 3)
            alerts = self.client.get('/promotions/admin/notifications',
                                     headers={'Authorization': 'Bearer admin'}).json()['data']
            self.assertEqual(len(alerts), 3)
            self.assertIn('Second author', alerts[0]['message'])
            self.assertEqual(self.client.post('/promotions/checkout',
                headers={'Authorization': 'Bearer user-one'},
                json={'article_id': 10, 'operation_id': 'a' * 32}).status_code, 409)
            another_purchase = self.client.post('/promotions/checkout',
                headers={'Authorization': 'Bearer user-one'},
                json={'article_id': 10, 'operation_id': 'd' * 32})
            self.assertEqual(another_purchase.status_code, 201, another_purchase.text)
            target = next(item for item in pending if item['article']['id'] == 12)
            approved = self.client.post(
                f"/promotions/admin/{target['id']}/decision",
                headers={'Authorization': 'Bearer admin'},
                json={'decision': 'approve', 'version': target['version']})
            self.assertEqual(approved.status_code, 200, approved.text)
            self.assertEqual(approved.json()['data']['status'], 'approved')
            self.assertEqual([p['id'] for p in self.client.get('/promotions/featured').json()['data']],
                             [12])
            self.assertEqual(self.client.post(
                f"/promotions/admin/{target['id']}/decision",
                headers={'Authorization': 'Bearer admin'},
                json={'decision': 'approve', 'version': target['version']}).status_code, 409)

    def test_payment_link_checkout_and_confirmed_payments(self):
        async def authenticated(_):
            return 7, 'Reporter', 'token'

        async def owned(*_):
            return ('Local story', None)

        async def article(*_):
            return {'title': 'Local story', 'author': {'id': 7, 'username': 'Maria'}}

        with patch.multiple(service, STRIPE_PAYMENT_LINK_URL='https://buy.stripe.com/test_example',
                            STRIPE_PAYMENT_LINK_ID='plink_example', STRIPE_SECRET_KEY='sk_test_local',
                            STRIPE_WEBHOOK_SECRET='whsec_local'), \
             patch.object(service, 'authenticate', authenticated), \
             patch.object(service, 'related_article', owned), \
             patch.object(service, 'public_article', article), \
             patch.object(service.httpx, 'AsyncClient', side_effect=AssertionError('No Stripe API call')):
            body = {'article_id': 42, 'operation_id': 'a' * 32}
            response = self.client.post('/promotions/checkout', json=body)
            self.assertEqual(response.status_code, 201, response.text)
            url = response.json()['data']['checkout_url']
            reference = url.split('client_reference_id=')[1]
            self.assertEqual(len(reference), 32)
            self.assertEqual(self.client.post('/promotions/checkout', json=body).json(), response.json())

            def send(event_id, session_id, **overrides):
                session = {'id': session_id, 'payment_link': 'plink_example',
                           'client_reference_id': reference, 'mode': 'payment',
                           'amount_total': 500, 'currency': 'usd', 'payment_status': 'paid'}
                session.update(overrides)
                event = {'id': event_id, 'type': 'checkout.session.completed',
                         'livemode': False, 'data': {'object': session}}
                payload = json.dumps(event).encode()
                stamp = str(int(time.time()))
                signature = hmac.new(b'whsec_local', stamp.encode() + b'.' + payload, hashlib.sha256).hexdigest()
                return self.client.post('/promotions/stripe/webhook', content=payload,
                                        headers={'stripe-signature': f't={stamp},v1={signature}'})

            self.assertEqual(send('evt_wrong', 'cs_test_one', amount_total=1).status_code, 400)
            self.assertEqual(send('evt_link', 'cs_test_one', payment_link='plink_other').status_code, 400)
            self.assertEqual(send('evt_ref', 'cs_test_one', client_reference_id='unknown').status_code, 400)
            self.assertEqual(send('evt_unpaid', 'cs_test_one', payment_status='unpaid').status_code, 200)
            with service.db_connection() as db:
                self.assertEqual(db.execute("SELECT count(*) FROM promotions WHERE status='pending'").fetchone()[0], 0)
            for event_id, session_id in [('evt_one', 'cs_test_one'), ('evt_one', 'cs_test_one'),
                                         ('evt_two', 'cs_test_two'), ('evt_other', 'cs_test_two')]:
                result = send(event_id, session_id)
                self.assertEqual(result.status_code, 200, result.text)
            with service.db_connection() as db:
                rows = db.execute("SELECT * FROM promotions WHERE status='pending'").fetchall()
                self.assertEqual(len(rows), 2)
                self.assertTrue(all(row['buyer_username'] == 'Maria' and row['article_id'] == 42
                                    and row['amount_cents'] == 500 for row in rows))

    def test_stripe_checkout_failure_keeps_safe_diagnostics(self):
        invalid_key = httpx.Response(401, json={
            'error': {'code': 'invalid_api_key',
                      'message': 'Invalid API Key provided: sk_live_SECRET'}},
            headers={'Request-Id': 'req_AbC123'})
        with self.assertLogs(service.__name__, level='ERROR') as logged:
            failure = service.stripe_checkout_failure(invalid_key)
        self.assertEqual(failure.status_code, 503)
        self.assertIn('server API key', failure.detail)
        self.assertIn('req_AbC123', failure.detail)
        self.assertNotIn('sk_live_SECRET', failure.detail)
        self.assertNotIn('sk_live_SECRET', logged.output[0])

        invalid_form = httpx.Response(400, json={
            'error': {'code': 'parameter_invalid_empty',
                      'param': 'line_items[0][price_data][product_data][name]',
                      'message': 'Missing product name'}},
            headers={'Request-Id': 'req_Form123'})
        with self.assertLogs(service.__name__, level='ERROR') as logged:
            failure = service.stripe_checkout_failure(invalid_form)
        self.assertIn('parameter_invalid_empty', failure.detail)
        self.assertIn('line_items[0][price_data][product_data][name]', failure.detail)
        self.assertIn('Missing product name', logged.output[0])

    def test_checkout_reports_the_failing_upstream_and_reaches_stripe_when_valid(self):
        real_async_client = httpx.AsyncClient
        stage = 'article_error'
        stripe_requests = []

        def outbound(request):
            if request.url.path.endswith('/mobile/capabilities'):
                self.assertEqual(request.headers['Authorization'], 'Bearer author-token')
                return httpx.Response(200, json={'data': {
                    'user_id': 7, 'username': 'Verified author',
                }})
            if request.url.path.endswith('/me/posts'):
                if stage == 'article_error':
                    return httpx.Response(503, json={'detail': 'News API unavailable'})
                return httpx.Response(200, json={'data': [{
                    'id': 42, 'title': 'Owned article', 'published': True,
                }], 'next_cursor': None})
            if request.url.path.endswith('/posts/42'):
                return httpx.Response(200, json={'data': {
                    'id': 42, 'title': 'Owned article', 'published': True,
                    'author': {'id': 7, 'username': 'Verified author'},
                }})
            if request.url.host == 'api.stripe.com':
                stripe_requests.append(request)
                self.assertEqual(request.url.path, '/v1/checkout/sessions')
                self.assertEqual(request.headers['Authorization'], 'Bearer sk_test_local')
                form = parse_qs(request.content.decode())
                self.assertEqual(form['metadata[article_id]'], ['42'])
                self.assertEqual(form['metadata[buyer_id]'], ['7'])
                if stage == 'stripe_error':
                    return httpx.Response(401, json={'error': {
                        'code': 'invalid_api_key',
                        'message': 'Invalid API Key provided: sk_test_local',
                    }}, headers={'Request-Id': 'req_Local123'})
                return httpx.Response(200, json={
                    'id': 'cs_test_local123',
                    'url': 'https://checkout.stripe.com/c/pay/cs_test_local123',
                })
            self.fail(f'Unexpected outbound request: {request.url}')

        def outbound_client(**kwargs):
            return real_async_client(transport=httpx.MockTransport(outbound), **kwargs)

        with patch.object(service, 'STRIPE_SECRET_KEY', 'sk_test_local'), \
             patch.object(service, 'STRIPE_WEBHOOK_SECRET', 'whsec_local'), \
             patch.object(service.httpx, 'AsyncClient', outbound_client):
            def checkout(operation):
                return self.client.post('/promotions/checkout',
                    headers={'Authorization': 'Bearer author-token'},
                    json={'article_id': 42, 'operation_id': operation})

            failed_article = checkout('a' * 32)
            self.assertEqual(failed_article.status_code, 503)
            self.assertEqual(failed_article.json()['detail'],
                             'Could not verify your article right now.')
            self.assertEqual(stripe_requests, [])

            stage = 'stripe_error'
            with self.assertLogs(service.__name__, level='ERROR') as logged:
                failed_stripe = checkout('b' * 32)
            self.assertEqual(failed_stripe.status_code, 503)
            self.assertIn('Stripe rejected the server API key',
                          failed_stripe.json()['detail'])
            self.assertIn('req_Local123', failed_stripe.json()['detail'])
            self.assertNotIn('sk_test_local', failed_stripe.text)
            self.assertNotIn('sk_test_local', '\n'.join(logged.output))
            self.assertEqual(len(stripe_requests), 1)

            stage = 'success'
            successful = checkout('c' * 32)
            self.assertEqual(successful.status_code, 201, successful.text)
            self.assertEqual(successful.json()['data']['checkout_url'],
                             'https://checkout.stripe.com/c/pay/cs_test_local123')
            self.assertEqual(len(stripe_requests), 2)

    def test_switching_to_live_replaces_an_unpaid_test_checkout(self):
        with service.db_connection() as db:
            db.execute("""INSERT INTO promotions
                (buyer_id,buyer_username,article_id,article_title,operation_id,
                 stripe_session_id,checkout_url,amount_cents,currency,created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?)""",
                (7, 'Reporter', 10, 'Story', 'a' * 32, 'cs_test_old123',
                 'https://checkout.stripe.com/c/pay/cs_test_old123',
                 500, 'usd', '2026-10-22T10:00:00+00:00'))
            db.commit()

        async def authenticated(_):
            return 7, 'Reporter', 'token'

        async def owned(article_id, _):
            return 'Story', None

        async def article(article_id):
            return {'id': article_id, 'title': 'Story', 'published': True,
                    'author': {'id': 7, 'username': 'Reporter'}}

        class StripeClient:
            def __init__(self, **_):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_):
                pass

            async def post(self, _, **kwargs):
                self_outer.assertEqual(kwargs['data']['client_reference_id'], '1')
                return httpx.Response(200, json={
                    'id': 'cs_live_new123',
                    'url': 'https://checkout.stripe.com/c/pay/cs_live_new123'})

        self_outer = self
        with patch.object(service, 'STRIPE_SECRET_KEY', 'sk_live_fake'), \
             patch.object(service, 'STRIPE_WEBHOOK_SECRET', 'whsec_fake'), \
             patch.object(service, 'authenticate', authenticated), \
             patch.object(service, 'related_article', owned), \
             patch.object(service, 'public_article', article), \
             patch.object(service.httpx, 'AsyncClient', StripeClient):
            response = self.client.post('/promotions/checkout',
                json={'article_id': 10, 'operation_id': 'a' * 32})
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()['data']['promotion_id'], 1)
        self.assertIn('cs_live_new123', response.json()['data']['checkout_url'])
        with service.db_connection() as db:
            row = db.execute('SELECT stripe_session_id FROM promotions WHERE id=1').fetchone()
            self.assertEqual(row['stripe_session_id'], 'cs_live_new123')

    def test_stripe_diagnostic_checks_container_key_without_printing_it(self):
        output = io.StringIO()
        response = httpx.Response(401, json={
            'error': {'code': 'invalid_api_key',
                      'message': 'Invalid API Key provided: sk_live_SECRET'}},
            headers={'Request-Id': 'req_Key123'})
        with patch.dict(os.environ, {'STRIPE_SECRET_KEY': 'sk_live_SECRET',
                                     'STRIPE_WEBHOOK_SECRET': 'whsec_FAKE'}), \
             patch.object(stripe_diagnostic.httpx, 'get', return_value=response), \
             redirect_stdout(output):
            self.assertEqual(stripe_diagnostic.main(), 1)
        result = output.getvalue()
        self.assertIn('stripe_key_mode=live', result)
        self.assertIn('stripe_account_http=401', result)
        self.assertIn('stripe_error_code=invalid_api_key', result)
        self.assertNotIn('sk_live_SECRET', result)


if __name__ == '__main__':
    unittest.main()
