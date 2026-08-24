#!/usr/bin/env bash
#
# Build (or run) the Android app with Supabase credentials compiled in.
#
# The credentials are `String.fromEnvironment` constants, so they are baked in
# at compile time — a plain `flutter build apk` produces a binary where
# `SupabaseConfig.isConfigured` is false and Settings shows "Accounts
# unavailable". This script is the one-stop way to avoid that. See ADR-8.
#
# Usage:
#   scripts/build_android.sh                # release APK
#   scripts/build_android.sh apk            # release APK
#   scripts/build_android.sh bundle         # release AAB for Play
#   scripts/build_android.sh install        # release APK, then install on the device
#   scripts/build_android.sh run            # flutter run in debug on the device
#
# Extra arguments are forwarded to Flutter:
#   scripts/build_android.sh apk --split-per-abi
#   scripts/build_android.sh run -d <device-id>

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DEFINES_FILE="supabase.json"

if [[ ! -f "$DEFINES_FILE" ]]; then
  cat >&2 <<EOF
error: $DEFINES_FILE not found.

Accounts need Supabase credentials at compile time. Create the file from the
template and paste your project URL and anon/publishable key:

    cp supabase.example.json $DEFINES_FILE

It is gitignored, so it stays out of version control.
EOF
  exit 1
fi

if grep -q 'YOUR-PROJECT-REF\|paste-the-anon' "$DEFINES_FILE"; then
  echo "error: $DEFINES_FILE still holds template placeholders. Fill in the real values." >&2
  exit 1
fi

TARGET="${1:-apk}"
[[ $# -gt 0 ]] && shift

DEFINE_ARG="--dart-define-from-file=$DEFINES_FILE"

case "$TARGET" in
  apk)
    flutter build apk --release "$DEFINE_ARG" "$@"
    ;;
  bundle | aab | appbundle)
    flutter build appbundle --release "$DEFINE_ARG" "$@"
    ;;
  install)
    flutter build apk --release "$DEFINE_ARG" "$@"
    flutter install --release "$@"
    ;;
  run)
    flutter run "$DEFINE_ARG" "$@"
    ;;
  *)
    echo "error: unknown target '$TARGET' (expected apk, bundle, install or run)" >&2
    exit 2
    ;;
esac
