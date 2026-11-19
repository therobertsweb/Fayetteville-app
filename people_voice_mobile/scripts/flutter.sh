#!/bin/sh
# Use one SDK for Flutter and Dart, including native build subprocesses.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
flutter_sdk=${FLUTTER_SDK:-"$HOME/flutter"}
if [ ! -x "$flutter_sdk/bin/flutter" ]; then
  echo "Set FLUTTER_SDK to a complete Flutter SDK installation." >&2
  exit 1
fi
export PATH="$flutter_sdk/bin:$PATH"
if [ -x "$HOME/.local/share/fayetteville-tools/jdk17/Contents/Home/bin/java" ]; then
  export JAVA_HOME="$HOME/.local/share/fayetteville-tools/jdk17/Contents/Home"
elif [ -x "$project_dir/.tooling/jdk/Contents/Home/bin/java" ]; then
  export JAVA_HOME="$project_dir/.tooling/jdk/Contents/Home"
fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/share/fayetteville-tools/android-sdk}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
exec "$flutter_sdk/bin/flutter" "$@"
