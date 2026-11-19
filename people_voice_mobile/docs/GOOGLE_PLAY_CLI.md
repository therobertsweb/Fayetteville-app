# Google Play CLI

Fastlane runs with a project-local Ruby because this Mac's Homebrew installation
belongs to another user. Ruby lives in `.tooling/ruby-local`; gems live in
`.tooling/bundle`. Both are excluded from version control.

- Cloud project: `fayetteville-tpv-play-20261017`
- Service account: `fastlane-play@fayetteville-tpv-play-20261017.iam.gserviceaccount.com`
- Android application ID: `com.fayettevillepeoplevoice.people_voice`
- Credentials: `.tooling/google-play/service-account.json` (private, mode 600).

Run from the project directory:

```sh
./tool/fastlane --version
./tool/fastlane android verify_credentials
./tool/fastlane android verify_access
```

`verify_credentials` checks Google authentication. `verify_access` additionally
checks access to the app's internal test track. Neither uploads a build.

The service account must be invited under Google Play Console > Users and
permissions. Grant access to this app, permission to view app information and
permission to release to testing tracks. A Google Cloud login alone does not grant
Play Console access. If this is a new app, create its Play Console listing and
complete the initial upload there before using Fastlane Supply.

The package name must match the Play Console app. Android releases also require
the existing upload keystore configuration in `android/key.properties` or the
supported environment variables. Do not create a replacement key for an existing
app without checking its Play App Signing setup.

To install the pinned gems after local Ruby is available:

```sh
PATH="$PWD/.tooling/ruby-local/bin:$PATH" BUNDLE_PATH="$PWD/.tooling/bundle" bundle install
```

Keep credentials outside source control; never paste the JSON contents into chat.
No upload or production release is performed as part of setup.

## Setup verification — 2026-10-17

- Installed Fastlane 2.241.1 with Ruby 3.4.11.
- Google service account credential validation succeeded.
- The app access check returned `Package not found: com.fayettevillepeoplevoice.people_voice`.
- The owner confirmed inviting the service account and that no Android build
  has been uploaded yet. Complete the first manual upload before retrying
  `./tool/fastlane android verify_access`.

## First Android build — 2026-10-18

Java 21 and the Android SDK are installed locally. Installed SDK components:
platform-tools, Android 36, build-tools 36.0.0 and NDK 28.2.13676358.

A new private RSA upload key was created for this app (the owner confirmed no
previous Android uploads). The key is `.tooling/android-signing/upload.jks`;
its passwords and absolute path are in `android/key.properties`. Both files
are private (mode 600) and excluded from source control. Keep a secure backup
of both files together; subsequent releases need the same upload key.

`tool/android-build` expects Java under `.tooling/jdk/Contents/Home` and the SDK
under `.tooling/android-sdk`, and keeps the Gradle cache in `.tooling/gradle-cache`.
Run `./tool/android-build --no-pub` to generate the signed release. The first
build downloads Gradle and Maven dependencies and needs network access.
Expected output: `build/app/outputs/bundle/release/app-release.aab`.
An expected path alone does not mean the build has succeeded.

Build completed on 2026-10-18 after switching networks resolved Google's Maven
download failures. Android distribution preflight passed all six checks.
`./tool/android-build --no-pub --verbose` succeeded with Gradle 9.3.1.

- Artifact: `build/app/outputs/bundle/release/app-release.aab` (64.5 MB).
- Package: `com.fayettevillepeoplevoice.people_voice`.
- Version: `1.0.0`, version code `2`; min SDK 24, target SDK 36.
- SHA-256: `c6a7f1d4aaf3db42d390dd467005794f041fddcf8a8a282994b2f12563ea46cf`.
- `bundletool` 1.18.3 validation passed; the manifest was read from the AAB.
- `jarsigner -verify` passed. The signer is the private upload key, CN=Fayetteville
  The People Voice, RSA 3072. Java reports self-signed certificate and ZIP entry
  ordering warnings; bundletool structural validation succeeded.
- Upload certificate SHA-256:
  `7B:D6:11:32:73:D9:6C:DC:3C:88:A1:E0:01:50:08:24:6F:52:38:4C:96:3A:D6:0D:2F:FF:05:D8:78:63:06:3F`.

Logs: `.tooling/android-build.log`, `.tooling/android-bundle-validation.txt`,
and `.tooling/android-bundle-manifest.xml`. This validates the build artifact;
it does not replace device testing. The AAB has not been uploaded to Google Play.

Once the signed AAB is ready, upload it through Play Console > Testing > Internal
testing > Create new release. The initial upload establishes the package name
`com.fayettevillepeoplevoice.people_voice`. Subsequent uploads can use Fastlane.

Reference: https://docs.fastlane.tools/actions/supply/#quick-start
