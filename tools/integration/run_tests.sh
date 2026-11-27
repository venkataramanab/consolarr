#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the emulator integration tests against the services started by
# start_services.sh. The Android emulator reaches the host as 10.0.2.2.
# Usage (from the repo root): tools/integration/run_tests.sh integration.env
set -euo pipefail
env_file="$(cd "$(dirname "${1:?env file}")" && pwd)/$(basename "$1")"
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
cd apps/consolarr
flutter test integration_test/servers_to_lists_test.dart \
  --dart-define=IT_HOST=10.0.2.2 \
  --dart-define=IT_SONARR_PORT=8989 \
  --dart-define=IT_QBIT_PORT=8080 \
  --dart-define=IT_TOXI_SONARR_PORT=28989 \
  --dart-define=IT_TOXI_API=http://10.0.2.2:8474 \
  --dart-define=IT_SONARR_API_KEY="$SONARR_API_KEY" \
  --dart-define=IT_QBIT_USERNAME="$QBIT_USERNAME" \
  --dart-define=IT_QBIT_PASSWORD="$QBIT_PASSWORD"
