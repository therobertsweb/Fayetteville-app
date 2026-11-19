# The People Voice 1.0.0 (13) — distribution artifacts

Created 2026-10-22 for App Store Connect distribution. These files have not
been submitted for public review.

The iOS and macOS build 13 packages were uploaded to App Store Connect on
2026-10-22; Xcode reported successful uploads. Processing and tester
availability must still be confirmed in App Store Connect.

| Platform | Artifact | SHA-256 |
| --- | --- | --- |
| iOS | `The-People-Voice-1.0.0-build13-ios-AppStore.ipa` | `9f65befbed82c879a53146d4c2050809906748a431122cc7bb1779c2ab6eae56` |
| macOS | `The-People-Voice-1.0.0-build13-macos-AppStore.pkg` | `4ea8a71403a7e7a732048825f8ad8e6ada8e4af17653ae74088e2d60604be3f1` |

Validation: Flutter analyze passed; 117 Flutter tests passed; iOS and macOS
distribution preflight passed. Xcode archive/export succeeded for both Apple
platforms. `codesign --verify --deep --strict` passed for the exported iOS app
and macOS archive; `pkgutil --check-signature` passed for the macOS PKG. The iOS
export has `get-task-allow=false`. Public news and podcast list endpoints both
responded with HTTP 200 during packaging.

Android is pending restoration of the original upload keystore referenced by
`android/key.properties`; the app has already been uploaded to Google Play, so
generating a replacement key would break the normal update path. The local JDK
21 and Android SDK 36 were restored on 2026-10-22; `flutter doctor -v` reports
the Android toolchain ready and all SDK licenses accepted. The missing original
`upload.jks` remains the Android signing blocker.

Before a public store submission, review the in-app Stripe promotion purchase
flow against [Apple App Review Guideline 3.1.3(g)](https://developer.apple.com/app-store/review/guidelines/)
and the [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en).
An actual authenticated purchase and device playback were not tested as part of
this packaging pass.

The separate podcast server diagnostic update is packaged as
`people-voice-podcast-service-stripe-diagnostics-2026-10-22.zip` (SHA-256
`e02f916f4a6e17a506ac9d6855de4cc13d8ba8f5a9b5871bf99427fb7f4cded7`).
It records Stripe's failure code and request ID without returning API secrets,
and includes a read-only check for the account and mode used by the container.
It has not yet been deployed to the production server, so the live checkout
failure remains unresolved pending the exact Stripe error and deployment.

On 2026-10-22 the running podcast container was confirmed to use an `sk_test_`
Stripe key. The account's live webhook endpoint is enabled, but the container
cannot create real Checkout sessions until it has a live API key and the
matching live webhook signing secret. The test-mode Checkout failure still
needs its exact Stripe error before this release can be considered ready.

The preferred Ubuntu server package is now
`people-voice-podcast-service-systemd-2026-10-22.zip` (SHA-256
`54b17d6a180883ec40b5e0abb1c930d5e83d29add7f93c616e813d23d032a1ba`).
It runs directly under systemd on `127.0.0.1:8001` with a dedicated user and
root-only environment file. Its two-phase installer prepares and diagnoses
Stripe without stopping the current service, then migrates the SQLite database
and media from the existing Docker volume with a rollback path. The package was
extracted and passed 17 Python tests; the API also passed a local Uvicorn HTTP
smoke test. The actual Ubuntu systemd unit and server Stripe credentials remain
unverified until installation on the server. Do not use the earlier Docker ZIP
for the systemd migration.
