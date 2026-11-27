#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fails when an analysis_options.yaml other than the root one does not
# `include:` the root file. The custom lints (consolarr_lints) are enabled by
# the root file's `plugins:` section; a nested file that neither includes the
# root nor declares the plugin would silently switch them off for its
# directory. The only exemption is the lint plugin package itself, which is
# excluded from root analysis and must not load itself.
#
# Usage: tools/ci/check_analysis_options.sh [repo-root]   (default: git toplevel)
set -euo pipefail
root=${1:-$(git rev-parse --show-toplevel)}
cd "$root"

exempt='tools/consolarr_lints/analysis_options.yaml'
root_abs=$(realpath "$root/analysis_options.yaml")
status=0

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = analysis_options.yaml ] && continue
  [ "$f" = "$exempt" ] && continue
  inc=$(sed -n -E 's/^include:[[:space:]]*["'"'"']?([^"'"'"'#[:space:]]+).*$/\1/p' "$f" | head -n1)
  target=
  if [ -n "$inc" ] && [[ "$inc" != package:* ]]; then
    target=$(realpath -m "$(dirname "$f")/$inc")
  fi
  if [ "$target" != "$root_abs" ]; then
    echo "::error file=$f::analysis_options.yaml must 'include:' the root analysis_options.yaml (relative path); otherwise the consolarr_lints plugin is not loaded here."
    status=1
  fi
done < <(git ls-files --cached --others --exclude-standard -- 'analysis_options.yaml' '**/analysis_options.yaml' | sort -u)

[ "$status" -eq 0 ] && echo "Every analysis_options.yaml includes the root one."
exit "$status"
