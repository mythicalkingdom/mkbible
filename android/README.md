# mkbible for Android (work in progress)

A Kotlin / Jetpack Compose reader on top of the same Pascal core the desktop programs use. The Pascal units are
cross-compiled into `libmkbibjni.so` (one JNI library, `proof/native/mkbibjni.pas`); the app calls it for modules,
chapters (as styled events), search, notes and Strong's lookups.

What works: reading (red letters, notes, cross references, headings), go to / search, Strong's lookup, importing
Sword module zips, downloading modules from the CrossWire and eBible.org Sword repositories, text size, spacing,
font and light / dark theme.  Sword Bible modules only for now.

## Build
Needs, all free:
- the Android SDK (platform 35, build-tools 35) and **NDK r21e or r22b** (FPC 3.2.x needs GNU `as` / `ld`, which newer
  NDKs no longer ship),
- JDK 17 or newer (a full JDK, not just the JRE),
- the Free Pascal Android cross compilers (aarch64 and x86_64), for instance from `fpcupdeluxe`.

    cd android/proof
    ./build.sh                       # native libraries for arm64 and x86_64, then ./gradlew assembleDebug

The paths in `native/build.sh` can be overridden with `FPC`, `ANDROID_CROSS_BIN` and `NDK_SYSROOT_LIB`.
The first Gradle build downloads the standard modules the app ships with (World English Bible Updated from eBible.org;
ASV, KJV with Strong's numbers, StrongsGreek and StrongsHebrew from CrossWire); they are not stored in git.  The texts
are public domain; CrossWire distributes the KJV module under the GPL.  `local.properties` must point `sdk.dir` at your Android SDK.

For a smaller APK: `./build.sh release` makes one APK per CPU (arm64-v8a for phones, x86_64 for emulators) and a
universal one, about 14.5 MB each instead of 24.7 MB (R8 code shrinking).  The release APKs are signed with the debug
key for now, so they can be installed by hand but are not ready for a store.

Install on an emulator or phone: `adb install -r app/build/outputs/apk/debug/app-debug.apk`.
