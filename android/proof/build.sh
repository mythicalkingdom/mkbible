#!/bin/sh
# Build the Android app: the Pascal library for both ABIs, then the APK.
#   ./build.sh          debug APK -> app/build/outputs/apk/debug/app-debug.apk
#   ./build.sh release  smaller release APKs (arm64-v8a, x86_64, universal) -> app/build/outputs/apk/release/
set -e
cd "$(dirname "$0")"
native/build.sh a64
native/build.sh x64
if [ "$1" = release ]; then
  ./gradlew assembleRelease
  ls -l app/build/outputs/apk/release/*.apk
else
  ./gradlew assembleDebug
  echo "APK: $(pwd)/app/build/outputs/apk/debug/app-debug.apk"
fi
