#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: check_workflow_checkout.sh <workflow.yml>
#
# Fails if a job has a step that runs tools/release/ without an earlier
# actions/checkout step in the same job (the script would not exist on the
# runner: exit code 127). Needs only python3; reads the workflow with a small
# indentation-based reader (jobs at two spaces, steps as "- " items at six),
# which is the layout of release.yml. Comment lines are ignored.
set -euo pipefail

python3 -I - "${1:?usage: check_workflow_checkout.sh <workflow.yml>}" <<'PY'
import re
import sys

path = sys.argv[1]
job = None
in_steps = False
step_no = 0
checked_out = False
failures = []
jobs_seen = 0
scripts_seen = 0
in_jobs = False

for lineno, raw in enumerate(open(path, encoding="utf-8"), 1):
    line = raw.rstrip("\n")
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    indent = len(line) - len(line.lstrip(" "))
    if indent == 0:
        in_jobs = stripped == "jobs:"
        job, in_steps = None, False
        continue
    if not in_jobs:
        continue
    if indent == 2 and stripped.endswith(":"):
        job, in_steps, step_no, checked_out = stripped[:-1], False, 0, False
        jobs_seen += 1
        continue
    if job is None:
        continue
    if indent == 4:
        in_steps = stripped == "steps:"
        continue
    if not in_steps:
        continue
    if indent == 6 and stripped.startswith("- "):
        step_no += 1
    if re.search(r"\buses:\s*actions/checkout@", stripped):
        checked_out = True
    if "tools/release/" in stripped:
        scripts_seen += 1
        if not checked_out:
            failures.append(f"{path}:{lineno}: job '{job}' step {step_no} runs tools/release/ without an earlier actions/checkout")

if jobs_seen == 0 or scripts_seen == 0:
    print(f"FAIL: found {jobs_seen} jobs and {scripts_seen} tools/release calls in {path}; the reader no longer matches the layout")
    sys.exit(1)
for f in failures:
    print("FAIL: " + f)
sys.exit(1 if failures else 0)
PY
