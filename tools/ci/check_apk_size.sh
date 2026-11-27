#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: check_apk_size.sh <apk> [max_megabytes=20]
# Prints a size report (also to the GitHub step summary) and fails when the
# APK is larger than the budget.
set -euo pipefail

apk="${1:?usage: check_apk_size.sh <apk> [max_megabytes]}"
max_mb="${2:-20}"
max_bytes=$((max_mb * 1024 * 1024))
size=$(stat -c %s "$apk")
size_mb=$(awk -v s="$size" 'BEGIN { printf "%.2f", s / 1048576 }')

line="${apk}: ${size_mb} MiB (budget ${max_mb} MiB)"
echo "$line"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "- $line" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$size" -gt "$max_bytes" ]; then
  echo "::error::$apk is ${size_mb} MiB, over the ${max_mb} MiB budget."
  exit 1
fi
