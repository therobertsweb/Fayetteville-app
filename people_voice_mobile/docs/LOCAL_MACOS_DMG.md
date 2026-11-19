# Local macOS DMG packaging

Build 6 contains the responsive news layout. The staged app in
`dist/The-People-Voice-1.0.0-build6.dmg` is signed with the available
`Apple Development: Roberto Castillo (CQ98422368)` identity. The bundle
reports version 1.0.0, build 6, and includes an Applications shortcut.

The build 4 DMG reproduced a dyld abort while loading FlutterMacOS.framework:
library validation rejected its unsigned team identity.
`codesign --verify --deep --strict` alone did not detect that launch failure.
For local packages, copy `macos/Runner/Release.entitlements` into the build
directory and add `com.apple.security.cs.disable-library-validation` with a
boolean value of `true`. Sign the staged app using
`codesign --force --sign <identity> --options runtime --entitlements <file> <app>`.
Keep the sandbox and network entitlements. Do not add this exception to the
production release entitlements; Developer ID/App Store distribution needs
its own signing and validation process.

Build 6 passed deep signature verification, `hdiutil verify`, and SHA-256
verification. Its read-only DMG mounted, and the bundled app launched and
remained running. `spctl --assess --type execute` rejected this development
signature. A publicly distributed package still needs a Developer ID
Application identity and notarization.
