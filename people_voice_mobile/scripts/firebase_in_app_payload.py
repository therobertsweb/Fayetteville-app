#!/usr/bin/env python3
"""Generate a public FCM HTTP v1 data-only payload; does not send anything."""
import argparse
import json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=('news', 'podcasts'), required=True)
    parser.add_argument('--content-id', type=int, required=True)
    parser.add_argument('--title', required=True)
    parser.add_argument('--body', required=True)
    args = parser.parse_args()
    if args.content_id < 1 or not args.title.strip():
        parser.error('A positive content ID and nonempty title are required')
    payload = {'message': {
        'topic': f'people_voice_{args.kind}_in_app_v1',
        'data': {'mode': 'in_app', 'kind': args.kind,
                 'content_id': str(args.content_id),
                 'title': args.title, 'body': args.body},
        'android': {'priority': 'normal', 'ttl': '0s'},
        'apns': {'headers': {'apns-push-type': 'background',
                             'apns-priority': '5', 'apns-expiration': '0'},
                 'payload': {'aps': {'content-available': 1}}},
    }}
    # FCM data messages have a 4096-byte payload limit. Leave room for metadata.
    if len(json.dumps(payload).encode('utf-8')) > 3500:
        parser.error('Message is too long; shorten the title/body')
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
