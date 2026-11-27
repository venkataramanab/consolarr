#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Creates the toxiproxy proxies the fault-scenario integration test drives.
# The test itself adds and removes toxics (latency, then a connection drop)
# through the toxiproxy API on port 8474.
set -euo pipefail
api=http://127.0.0.1:8474
curl -fsS -X POST "$api/proxies" -d '{"name":"sonarr","listen":"0.0.0.0:28989","upstream":"it-sonarr:8989"}' >/dev/null
curl -fsS -X POST "$api/proxies" -d '{"name":"qbit","listen":"0.0.0.0:28080","upstream":"it-qbit:8080"}' >/dev/null
echo "toxiproxy proxies ready"
