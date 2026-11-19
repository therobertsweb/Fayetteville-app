#!/usr/bin/env python3
"""Read-only release configuration checks; never signs, uploads, or publishes.

Run with --api-url to verify the deployed API contract using anonymous GETs.
Run with --distribution to require local signing/toolchain configuration too.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("all", "android", "ios", "macos"), default="all")
    parser.add_argument("--distribution", action="store_true")
    parser.add_argument("--api-url", help="HTTPS website origin, without /api/v1")
    args = parser.parse_args()
    failures = []

    def check(condition, message):
        print(f"{'PASS' if condition else 'FAIL'} {message}")
        if not condition:
            failures.append(message)

    def plist(relative):
        with (ROOT / relative).open("rb") as handle:
            return plistlib.load(handle)

    targets = ("android", "ios", "macos") if args.target == "all" else (args.target,)
    if "android" in targets:
        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
        app = manifest.getroot().find("application")
        check(app is not None and app.get(ANDROID_NS + "usesCleartextTraffic") == "false",
              "Android release disallows cleartext traffic")
        check(app is not None and app.get(ANDROID_NS + "allowBackup") == "false",
              "Android disables account-data backup")
        gradle = (ROOT / "android/app/build.gradle.kts").read_text()
        check('signingConfigs.getByName("debug")' not in gradle
              and 'signingConfigs.getByName("release")' in gradle,
              "Android release uses its own signing configuration")
        check("validateReleaseSigning" in gradle, "Android validates upload-key configuration")
        if args.distribution:
            android_sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
            local = ROOT / "android/local.properties"
            if not android_sdk and local.is_file():
                match = re.search(r"^sdk\.dir=(.+)$", local.read_text(), re.MULTILINE)
                if match:
                    android_sdk = match.group(1).strip()
            sdk_root = Path(android_sdk) if android_sdk else None
            check(bool(sdk_root and list((sdk_root / "platforms").glob("*/android.jar"))),
                  "Android SDK has platform android.jar files (not just package folders)")
            check(bool(sdk_root and (sdk_root / "platform-tools/adb").is_file()),
                  "Android SDK includes adb")
            check(bool(sdk_root and list((sdk_root / "build-tools").glob("*/aapt2"))
                       and list((sdk_root / "build-tools").glob("*/lib/d8.jar"))),
                  "Android SDK includes build-tools binaries")
            variables = ("ANDROID_KEYSTORE_PATH", "ANDROID_KEYSTORE_PASSWORD",
                         "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
            check((ROOT / "android/key.properties").is_file()
                  or all(os.environ.get(name) for name in variables),
                  "Android private signing configuration is available (Gradle validates values)")

    for target in (name for name in targets if name in ("ios", "macos")):
        info = plist(f"{target}/Runner/Info.plist")
        ats = info.get("NSAppTransportSecurity", {})
        check(not ats.get("NSAllowsArbitraryLoads", False)
              and not ats.get("NSAllowsArbitraryLoadsInWebContent", False),
              f"{target} retains App Transport Security")
        check(info.get("CFBundleShortVersionString") == "$(FLUTTER_BUILD_NAME)"
              and info.get("CFBundleVersion") == "$(FLUTTER_BUILD_NUMBER)",
              f"{target} derives release version from Flutter")
        icons = ROOT / target / "Runner/Assets.xcassets/AppIcon.appiconset"
        icon_entries = json.loads((icons / "Contents.json").read_text())["images"]
        missing_icons = sorted({entry["filename"] for entry in icon_entries
                                if entry.get("filename")
                                and not (icons / entry["filename"]).is_file()})
        check(not missing_icons,
              f"{target} app icon files exist" +
              (f": missing {', '.join(missing_icons)}" if missing_icons else ""))
        project = (ROOT / f"{target}/Runner.xcodeproj/project.pbxproj").read_text()
        privacy = plist(f"{target}/Runner/PrivacyInfo.xcprivacy")
        file_reasons = set()
        for usage in privacy.get("NSPrivacyAccessedAPITypes", []):
            if usage.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryFileTimestamp":
                file_reasons.update(usage.get("NSPrivacyAccessedAPITypeReasons", []))
        check({"C617.1", "3B52.1"}.issubset(file_reasons)
              and "PrivacyInfo.xcprivacy in Resources" in project,
              f"{target} bundles reasons for app-container and user-selected file metadata")
        firebase_config = ROOT / target / "Runner/GoogleService-Info.plist"
        if firebase_config.is_file():
            firebase = plist(f"{target}/Runner/GoogleService-Info.plist")
            check(firebase.get("PROJECT_ID") == "fayetteville-the-people-voice"
                  and firebase.get("BUNDLE_ID") == ("com.fayettevillepeoplevoice.peopleVoice" if target == "ios"
                                                     else "com.fayettevillepeoplevoice.mac.a9x2dv8x8l")
                  and "GoogleService-Info.plist in Resources" in project,
                  f"{target} bundles the registered Firebase client configuration")
            check(info.get("FirebaseMessagingInstallationIdEnabled") is True
                  and info.get("FirebaseMessagingAutoInitEnabled") is False,
                  f"{target} enables FCM registration API with automatic opt-in disabled")
            push_entitlements = plist(f"{target}/Runner/" +
                                      ("Runner.entitlements" if target == "ios" else "Release.entitlements"))
            push_key = "aps-environment" if target == "ios" else "com.apple.developer.aps-environment"
            check(push_entitlements.get(push_key) in ("development", "production"),
                  f"{target} declares APNs capability (signed profile and real delivery still need validation)")
        if args.distribution:
            check(bool(re.search(r"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10};", project)),
                  f"{target} has an Apple development team (certificate/profile still need validation)")
            check(shutil.which("xcodebuild") is not None, f"{target} Xcode build tools are available")

    if "ios" in targets:
        check("keychain-access-groups" in plist("ios/Runner/Runner.entitlements")
              and (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text().count(
                  "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;") == 3,
              "iOS configures secure token storage")

    if "macos" in targets:
        check(plist("macos/Runner/Info.plist").get("LSApplicationCategoryType")
              == "public.app-category.news",
              "macOS declares the News category required by App Store Connect")
        entitlements = plist("macos/Runner/Release.entitlements")
        check(entitlements.get("com.apple.security.app-sandbox") is True,
              "macOS release is sandboxed")
        check(entitlements.get("com.apple.security.network.client") is True,
              "macOS release can connect to the API")
        check(not entitlements.get("com.apple.security.cs.allow-jit", False)
              and not entitlements.get("com.apple.security.network.server", False),
              "macOS release excludes debug JIT and incoming-server entitlements")
        project = (ROOT / "macos/Runner.xcodeproj/project.pbxproj").read_text()
        check("ENABLE_HARDENED_RUNTIME = YES;" in project,
              "macOS enables hardened runtime for distribution")
        check("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;" in project,
              "macOS release disables Xcode's injected debugger entitlement")

    if args.api_url:
        origin = urlparse(args.api_url)
        if (origin.scheme != "https" or not origin.hostname or origin.username
                or origin.password or origin.path not in ("", "/") or origin.query or origin.fragment):
            parser.error("--api-url must be a public HTTPS origin without a path, credentials, or query")
        endpoints = (("/posts", 200), ("/categories", 200), ("/events", 200),
                     ("/businesses", 200), ("/promotions/pricing", 200),
                     ("/me/preferences", 401))
        for path, expected in endpoints:
            request = Request(args.api_url.rstrip("/") + "/api/v1" + path,
                              headers={"Accept": "application/json",
                                       "User-Agent": "PeopleVoice-ReleasePreflight/1.0"})
            try:
                try:
                    response = urlopen(request, timeout=20)
                except HTTPError as error:
                    response = error
                with response:
                    status = response.code
                    content_type = response.headers.get_content_type()
                    secure = urlparse(response.geturl()).scheme == "https"
                    payload = response.read(2 * 1024 * 1024)
                try:
                    is_object = isinstance(json.loads(payload), dict)
                except (ValueError, UnicodeDecodeError):
                    is_object = False
                check(status == expected and content_type == "application/json" and is_object and secure,
                      f"API {path}: HTTP {status}, expected {expected} with a JSON object over HTTPS")
            except (URLError, TimeoutError, OSError) as error:
                check(False, f"API {path}: unavailable ({type(error).__name__})")

    print(f"\n{'FAILED' if failures else 'PASSED'}: {len(failures)} failed checks.")
    print("This checks configuration only. Signed builds, device testing, and store review are separate gates.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
