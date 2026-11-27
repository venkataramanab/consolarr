#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fails if a source file lacks the SPDX licence header in its first 5 lines.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

header='SPDX-License-Identifier: GPL-3.0-or-later'
missing=0
checked=0

while IFS= read -r file; do
  case "$file" in
    *.dart|*.kt|*.kts|*.gradle|*.java|*.sh|*.xml|*.yml|*.yaml|*.pro|*.toml) ;;
    *) continue ;;
  esac
  case "$file" in
    */build/*|*/.dart_tool/*|*/.idea/*) continue ;;
  esac
  [ -f "$file" ] || continue
  checked=$((checked + 1))
  if ! head -n 5 "$file" | grep -q "$header"; then
    echo "missing SPDX header: $file"
    missing=$((missing + 1))
  fi
done < <(git ls-files --cached --others --exclude-standard)

echo "SPDX check: $checked files checked, $missing missing."
[ "$missing" -eq 0 ]
