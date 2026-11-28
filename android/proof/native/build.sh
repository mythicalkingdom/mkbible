#!/bin/sh
# cross-compile libmkbibjni.so for Android: build.sh a64 (phone) | x64 (emulator)
set -e
cd "$(dirname "$0")"
T=${1:-a64}
FPC=${FPC:-$HOME/fpcupdeluxe/fpc/bin/x86_64-linux/fpc}
C=${ANDROID_CROSS_BIN:-$HOME/fpcupdeluxe/cross/bin/all-android}
NDK=${NDK_SYSROOT_LIB:-$HOME/Android/Sdk/ndk/22.1.7171670/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib}
[ -x "$FPC" ] || { echo "FPC cross compiler not found at $FPC (set FPC=..., see android/README.md)"; exit 1; }
if [ "$T" = a64 ]; then CPU=aarch64; TR=aarch64-linux-android; ABI=arm64-v8a; else CPU=x86_64; TR=x86_64-linux-android; ABI=x86_64; fi
U=$HOME/fpcupdeluxe/fpc/units/$CPU-android
mkdir -p out-$T ../app/src/main/jniLibs/$ABI
$FPC -Tandroid -P$CPU -Fu$U/rtl -Fu$U/jni -Fu$U/paszlib -Fu$U/bzip2 -Fu$U/fcl-base -Fu$U/regexpr -Fu$U/sqlite -Fu$U/rtl-objpas -Fu$U/rtl-extra -Fu$U/rtl-unicode -Fu$U/hash -Fu../../../src -Fi../../../src -FUout-$T -FEout-$T \
  -O2 -XX -CX -Xs -FD$C/bin -Fl$NDK/$TR/29 -Fl$NDK/$TR -vew mkbibjni.pas
cp out-$T/libmkbibjni.so ../app/src/main/jniLibs/$ABI/
