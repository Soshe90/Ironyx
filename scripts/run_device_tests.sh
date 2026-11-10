#!/usr/bin/env bash
#
# Run the on-device journeys in integration_test/ against a USB-connected
# Android phone or an emulator.
#
# Guards the real app's data. Flutter's integration-test runner can delete a
# release install of Ironyx in two ways, and both happened or nearly
# happened on 2026-09-29:
#
#   1. On install. A debug-signed test APK cannot update a release-signed
#      app with the same id, so Flutter uninstalls the real app first.
#      Fixed by giving every debug build the id com.soshe90.ironyx.debug
#      (android/app/build.gradle.kts), proved on a built APK below and
#      checked again on the device after the run.
#   2. After the run. Flutter then runs `adb uninstall com.soshe90.ironyx`,
#      the *real* id, whatever the APK was called. Fixed with
#      --no-uninstall, removing only the .e2e app ourselves.
#
# Neither fix is trusted alone: the script refuses to run at all while the
# real app is on the device. Move its data out first (Settings > Export),
# or run on a phone or emulator without it.
#
# No Supabase credentials are passed, and the harness pins accounts off
# (ADR-8: nothing in the suite reaches the network).
#
# Usage:
#   scripts/run_device_tests.sh -d <device-id>          # every journey
#   scripts/run_device_tests.sh integration_test/timer_journey_test.dart -d <id>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REAL_APP="com.soshe90.ironyx"
TEST_APP="com.soshe90.ironyx.debug"

TARGET="integration_test"
if [[ $# -gt 0 && "$1" != -* ]]; then
  TARGET="$1"
  shift
fi

DEVICE=""
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    -d | --device-id) DEVICE="${ARGS[$((i + 1))]:-}" ;;
    -d=* | --device-id=*) DEVICE="${ARGS[$i]#*=}" ;;
  esac
done
if [[ -z "$DEVICE" ]]; then
  echo "error: pass the device explicitly with -d <device-id> (see 'adb devices')." >&2
  exit 2
fi

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${LOCALAPPDATA:-$HOME}/Android/Sdk}}"
# Git Bash on Windows sees LOCALAPPDATA as C:\...; turn it into /c/...
command -v cygpath >/dev/null 2>&1 && SDK="$(cygpath -u "$SDK")"
ADB=""
for candidate in "$SDK/platform-tools/adb" "$SDK/platform-tools/adb.exe" adb adb.exe; do
  if command -v "$candidate" >/dev/null 2>&1; then
    ADB="$candidate"
    break
  fi
done
[[ -n "$ADB" ]] || { echo "error: adb not found (looked under $SDK/platform-tools and PATH)." >&2; exit 1; }

# Guard 0: the real app must not be on the device at all. Fails closed: if
# the device cannot be asked, nothing runs.
if [[ "$("$ADB" -s "$DEVICE" get-state 2>/dev/null | tr -d '\r')" != "device" ]]; then
  echo "error: device $DEVICE is not connected and ready (adb get-state)." >&2
  exit 1
fi
if ! PACKAGES="$("$ADB" -s "$DEVICE" shell pm list packages)" || [[ -z "$PACKAGES" ]]; then
  echo "error: could not list packages on $DEVICE; refusing to run." >&2
  exit 1
fi
if tr -d '\r' <<<"$PACKAGES" | grep -qx "package:$REAL_APP"; then
  cat >&2 <<EOF
error: $REAL_APP is installed on $DEVICE.

Refusing to run: Flutter's integration-test runner can uninstall it, and
uninstalling deletes its training data. Export its data first
(Settings > Data > Export) and uninstall it yourself, or use another device.
EOF
  exit 1
fi

# Guard 1: build one test APK and prove its package before installing.
PROBE="integration_test/app_test.dart"
[[ -f "$TARGET" ]] && PROBE="$TARGET"
flutter build apk --debug --target "$PROBE"
AAPT="$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1)aapt"
[[ -x "$AAPT" || -x "$AAPT.exe" ]] || { echo "error: aapt not found under $SDK/build-tools" >&2; exit 1; }
PACKAGE="$("$AAPT" dump badging build/app/outputs/flutter-apk/app-debug.apk \
  | tr -d '\r' | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
if [[ "$PACKAGE" != "$TEST_APP" ]]; then
  echo "error: test APK package is '$PACKAGE', not $TEST_APP. Refusing to install." >&2
  exit 1
fi

# Guard 2: never let Flutter run its own uninstall; remove only the test app.
status=0
flutter test "$TARGET" --no-uninstall "$@" || status=$?

# The real app was absent before the run (guard 0), so if it exists now the
# test build went in under the real id and the rename is broken.
if "$ADB" -s "$DEVICE" shell pm list packages | tr -d '\r' | grep -qx "package:$REAL_APP"; then
  echo "error: the test build installed as $REAL_APP, not $TEST_APP." >&2
  echo "The debug applicationIdSuffix is not taking effect; fix it before the next run." >&2
  status=1
fi
"$ADB" -s "$DEVICE" uninstall "$TEST_APP" >/dev/null 2>&1 || true
exit "$status"
