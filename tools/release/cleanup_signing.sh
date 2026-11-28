#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: cleanup_signing.sh <key-dir> <app-android-dir>...
# Best-effort removal of the keystore and key.properties files. Never fails.
set -uo pipefail
dir="${1:-}"
shift || true
wipe() {
  [ -e "$1" ] || return 0
  shred --force --zero "$1" 2>/dev/null || true
  rm -f "$1"
}
for app in "$@"; do wipe "$app/key.properties"; done
if [ -n "$dir" ]; then
  wipe "$dir/release.jks"
  rmdir "$dir" 2>/dev/null || true
fi
echo "Signing material removed."
exit 0
