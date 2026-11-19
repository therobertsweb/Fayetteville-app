#!/bin/sh
# Build outside synced Desktop folders, which can inject Finder metadata and
# invalidate signatures while Xcode is assembling frameworks.
set -eu
target=${1:-macos}
case "$target" in
  macos|ios) ;;
  *) echo "Usage: $0 [macos|ios]" >&2; exit 1 ;;
esac
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_sdk=${FLUTTER_SDK:-"$HOME/flutter"}
export PATH="$flutter_sdk/bin:$PATH"
if [ ! -x "$flutter_sdk/bin/flutter" ]; then
  echo "Set FLUTTER_SDK to a complete Flutter SDK installation." >&2
  exit 1
fi
build_source=$(mktemp -d /private/tmp/people-voice-build.XXXXXX)
rsync -a --exclude '.tooling' --exclude 'build' --exclude 'dist' \
  --exclude '.dart_tool' --exclude '.git' --exclude '.gradle' \
  --exclude 'ephemeral' --exclude 'podcast_service' --exclude 'docs' \
  --exclude 'key.properties' "$project_dir/" "$build_source/"
cd "$build_source"
"$flutter_sdk/bin/flutter" pub get
if [ "$target" = macos ]; then
  "$flutter_sdk/bin/flutter" build macos --release --no-pub
  echo "Built app: $build_source/build/macos/Build/Products/Release/The People Voice.app"
else
  "$flutter_sdk/bin/flutter" build ios --simulator --debug --no-pub
  echo "Built simulator app: $build_source/build/ios/iphonesimulator/Runner.app"
fi
