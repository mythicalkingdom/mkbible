#!/bin/sh
# Build the Android app: the Pascal library for both ABIs, then the APK.
#   ./build.sh          debug APK -> app/build/outputs/apk/debug/app-debug.apk
set -e
cd "$(dirname "$0")"
native/build.sh a64
native/build.sh x64
./gradlew assembleDebug
echo "APK: $(pwd)/app/build/outputs/apk/debug/app-debug.apk"
