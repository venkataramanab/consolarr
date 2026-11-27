#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Project Semgrep scan. Inline suppressions are disabled, there is no file size
# limit (--max-target-bytes 0: the default 1 MB limit let a padded file hide a
# violation), findings fail the build, and so does any skipped file other than
# the .semgrepignore'd build output. Usage: semgrep_scan.sh [paths...]
# (default: apps packages). Run from the repository root.
set -uo pipefail
repo=$(git rev-parse --show-toplevel)
[ "$#" -gt 0 ] || set -- apps packages
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rc=0
semgrep scan --config "${SEMGREP_CONFIG:-$repo/tools/semgrep/consolarr.yml}" --disable-nosem \
  --max-target-bytes 0 --error --metrics=off --disable-version-check \
  --verbose --json-output="$tmp/out.json" "$@" > "$tmp/log.txt" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  cat "$tmp/log.txt"
  echo "::error::semgrep exited with status $rc (findings or a scan error)"
fi
[ -s "$tmp/out.json" ] || { echo "::error::semgrep produced no JSON report"; exit 1; }
python3 -I "$repo/tools/ci/semgrep_skipped.py" "$tmp/out.json" || rc=1
[ "$rc" -eq 0 ] && echo "semgrep scan clean"
exit "$rc"
