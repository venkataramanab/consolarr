#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: check_version.sh <tag> <pubspec.yaml>...
# The tag must be vMAJOR.MINOR.PATCH and equal the `version:` of every given
# pubspec, ignoring the +build suffix. Prints the version on success.
set -euo pipefail

tag="${1:?usage: check_version.sh <tag> <pubspec.yaml>...}"
shift
[ "$#" -ge 1 ] || { echo "No pubspec files given." >&2; exit 2; }

if ! [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "::error::Tag '${tag}' is not of the form vMAJOR.MINOR.PATCH." >&2
  exit 1
fi
want="${BASH_REMATCH[1]}"

for pubspec in "$@"; do
  line="$(grep -E '^version:' "$pubspec" || true)"
  if ! [[ "$line" =~ ^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?[[:space:]]*$ ]]; then
    echo "::error::Cannot read a version from ${pubspec}." >&2
    exit 1
  fi
  if [ "${BASH_REMATCH[1]}" != "$want" ]; then
    echo "::error::Tag ${tag} does not match version ${BASH_REMATCH[1]} in ${pubspec}." >&2
    exit 1
  fi
done
echo "$want"
