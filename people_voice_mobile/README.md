# Fayetteville · The People Voice

Flutter client for iOS, macOS, and Android. The interface, validation messages, labels,
and help text are written in English and follow the visual identity of
The People Voice website.

## Current features

- Paginated news, article details, events, businesses, and comments.
- The home screen places Featured Posts below the lead story, and the reader
  repeats approved promoted stories at the end of each article. Paid placements
  require server-confirmed payment and admin approval before appearing.
- Complete articles and their images stored in SQLite for offline reading.
- Saved articles scoped to each account and synchronized when online.
- Secure sign-in with the access token stored in Apple Keychain.
- Offline article drafts saved after every change.
- Visual article editor with bold, italic, underline, headings, lists, quotes,
  links, undo/redo and a reading preview. The same editor is available in post management.
- Cover and inline images from local files or HTTPS URLs. Local images remain
  available offline and upload only on an explicit submission.
- YouTube, Facebook, TikTok, Vimeo and direct HTTPS videos with an in-app player
  and an external-link fallback. Videos require an internet connection.
- Explicit submission for review or publication; reconnecting never publishes
  a draft automatically.
- AI writing assistance with proposal review and one-step restoration of the
  previous text.
- Rankings for most commented and most saved articles.
- Administrator tools for drafts, articles, accounts, roles, contact messages,
  statistics, social publishing, and bulk publish/delete operations.
- Persistent in-app notifications, with optional Firebase data-only news and podcast updates while the app is active. See [Firebase setup](docs/PUSH_SETUP.md).
- Public podcasts with signed-in publishing, MP3 upload or a direct HTTPS MP3
  link, and an optional published article. The article's main image becomes the
  podcast cover; otherwise the author supplies one. Listeners can react and
  comment with a signed-in account; totals and comments are public. See
  [`podcast_service/README.md`](podcast_service/README.md) for the independent
  service and deployment requirements.

## Complete website template data

The mobile editor mirrors the website creation form. A publication sends all
fields supported by `POST /api/v1/posts`:

- `url`, `title`, `content`, and `photo_link`
- `info` for the primary category
- `tag_1` and `tag_2`
- `title_2` and `title_3`
- `subtitle` and `subtitle_2`
- `categories` for additional categories

The editor requires the fields used by the public article template before it
can publish. `title_3` stays synchronized with the main article title, matching
the website behavior. Optional fields remain available in an expandable panel.
Incomplete drafts can still be saved and edited offline.

The API and app apply the same maximum lengths and slug format. Cover images
can be selected locally or use an HTTPS URL or a `/static/` website path.
`POST /api/v1/media/images` accepts authenticated multipart uploads (`image`),
limited to 5 MB and 20 million pixels. The server verifies image contents and
re-encodes them as WebP; animated GIFs become a still image. Local upload receipts
are saved so a failed submission can reuse successfully uploaded images.

Use full public video URLs; shortened TikTok/Facebook share links must first be
opened to copy the full video address. Direct video URLs may include signed query
parameters and must return media playable by the device. Private, expired or
embedding-disabled videos may require opening the original service.

## Offline behavior and publication safety

SQLite persists downloaded articles, images, drafts, favorites, notifications,
and publication state across app restarts. Uninstalling the app or clearing its
files removes this local data.

Publication first creates a private server draft and records its remote ID
before requesting publication. A failed publication retries the known remote
record. If the creation response is lost, the app marks the submission as
unconfirmed and requires verification of the server article ID before it can
continue. This prevents accidental duplicate articles.

## Design

The app uses the website palette and bundled Montserrat, Roboto, and Raleway
fonts. The five-item mobile navigation includes a More menu for categories, writing,
and account access. It changes to a sidebar on wider displays, and
article/editor content uses a readable maximum width. The responsive tests cover
320, 390, 700, 834, and 1440 point layouts.

## Local API

The app now targets the production API by default:

```text
https://fayettevillethepeoplevoice.com/api/v1
```

The independent podcast service also defaults to its production HTTPS origin:

```text
https://podcasts.fayettevillethepeoplevoice.com
```

The editorial API is enabled by default for local testing. Override either
setting at build time when needed:

```sh
flutter run \
  --dart-define=API_BASE_URL=https://fayettevillethepeoplevoice.com \
  --dart-define=PODCAST_API_BASE_URL=https://podcasts.fayettevillethepeoplevoice.com \
  --dart-define=EDITORIAL_API_ENABLED=true
```

Keep OpenAI and social service credentials on the server. They must never be
embedded in Flutter, JavaScript, source control, or API responses.

## Run and verify

With a compatible Flutter SDK:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Use the project launcher to keep Flutter and Dart on the same SDK. It defaults
to `$HOME/flutter`; set `FLUTTER_SDK` to use another complete installation.
The old `.tooling/flutter` copy is incomplete and should not be used:

```sh
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh test tool/smoke_public_test.dart
```

When the project is in a synced Desktop folder, build Apple apps in a local
temporary copy to avoid Finder metadata interfering with framework signatures:

```sh
./scripts/build_apple_local.sh macos  # Release app, local signature
./scripts/build_apple_local.sh ios    # Debug app for the simulator
```

The script prints the built app path and leaves the source workspace in place.
These commands do not upload or publish the app.

The latest verification and release constraints are recorded in
[`docs/FINAL_REVIEW_2026-10-03.md`](docs/FINAL_REVIEW_2026-10-03.md).

- Static analysis has no issues.
- Automated tests cover public reading, offline storage, drafts, account isolation,
  session races, image download recovery, search pagination, and accessible layouts.
- The read-only production smoke test is `flutter test tool/smoke_public_test.dart`.
- `python3 scripts/release_preflight.py` checks native release configuration.
- The macOS release artifact uses an ad hoc signature for local verification.
  Store distribution still requires the owner's signing credentials and review.

The iOS build currently requires the iOS 26.5 component requested by Xcode and
an Apple development team. Android requires its SDK and a real upload keystore;
release builds deliberately reject missing signing configuration and debug keys.
See [`docs/PRODUCTION_READINESS.md`](docs/PRODUCTION_READINESS.md) for commands
and the external requirements. Authenticated backend flows and payments must be
verified with a test account and a test payment environment before distribution.

No production deployment, TestFlight upload, App Store submission, or live
social post is performed by the automated tests.

## Server implementation

The default API origin is `https://fayettevillethepeoplevoice.com`.
This workspace contains the Flutter client, not the backend project referenced
by older review documents. Do not treat historical server test counts as current
verification. The client-side contract is documented in
[`docs/EDITORIAL_API.md`](docs/EDITORIAL_API.md).

Keep service credentials on the server. Any credentials previously exposed
during development must be rotated by the service owner before distribution.

## iPhone editorial interface

iOS has a dedicated news interface inspired by the supplied Apple News references:
pure black background, pink accent, current date, category pills, a large lead
story, two-column secondary stories, compact article rows and a floating blurred
navigation capsule with separate search. News and cover images use the production
API and existing offline repository. The iOS default is dark; readers can choose
light mode under More options → Reading & notifications. macOS keeps its existing
layout and theme.

Advertise opens a dedicated introduction with the generated local-business
illustration in `assets/brand/advertise.png`. Signed-out readers can sign in,
then choose a published article and review server-priced promotion terms.
Checkout is available only when the server confirms that paid review is enabled.
No purchase is initiated by tapping Advertise.

Validation: `flutter test test/iphone_news_test.dart test/design_test.dart` covers
iOS navigation, advertising sign-in, small phones, landscape, enlarged text and
the existing responsive design. Build for the simulator with
`flutter build ios --simulator --debug`. Device distribution still requires an
Apple signing setup and a device/archive build.
