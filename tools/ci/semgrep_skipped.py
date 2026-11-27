#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fails when Semgrep skipped any file it was not meant to skip.

Reads the JSON written by `semgrep scan --verbose --json-output=FILE`. The only
accepted skip reason is `semgrepignore_patterns_match` (the anchored build
output directories in .semgrepignore). Anything else, notably
`exceeded_size_limit`, means a file went unscanned and could hide a violation.
"""
import json
import sys

ALLOWED = {"semgrepignore_patterns_match"}


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        paths = json.load(f).get("paths", {})
    bad = [s for s in paths.get("skipped", []) if s.get("reason") not in ALLOWED]
    for s in bad:
        print("::error::semgrep skipped %s (%s)" % (s.get("path"), s.get("reason")))
    if bad:
        return 1
    print("semgrep skipped no files outside .semgrepignore")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
