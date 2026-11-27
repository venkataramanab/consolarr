#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Starts pinned Sonarr, qBittorrent and Toxiproxy containers for the nightly
# integration test and writes their connection details to $1 (default
# integration.env) as KEY=VALUE lines. Everything is generated per run: no
# fixed credentials exist anywhere in the repository.
#
# Images are pinned by tag AND digest. Bump them deliberately.
set -euo pipefail

out="${1:-integration.env}"
sonarr_image="lscr.io/linuxserver/sonarr:4.0.20.3014-ls6@sha256:339814bbf50599ac3b59077c252f29833d0138b59a062d0e82ce37bdc7f04f86"
qbit_image="lscr.io/linuxserver/qbittorrent:5.3.1_v2.1.3-ls490@sha256:1fa2f9692501f27ce51c4fffd771d63ec38f1163cb648941c324344b7c5a3915"
toxi_image="ghcr.io/shopify/toxiproxy:2.12.0"

docker network create consolarr-it >/dev/null 2>&1 || true

docker run -d --name it-sonarr --network consolarr-it -p 8989:8989 \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  "$sonarr_image" >/dev/null
docker run -d --name it-qbit --network consolarr-it -p 8080:8080 \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC -e WEBUI_PORT=8080 \
  "$qbit_image" >/dev/null
docker run -d --name it-toxiproxy --network consolarr-it \
  -p 8474:8474 -p 28989:28989 -p 28080:28080 \
  "$toxi_image" >/dev/null

wait_http() { # wait_http <url> <seconds>
  for _ in $(seq 1 "$2"); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$1" || true)
    [ "$code" != "000" ] && [ "$code" != "502" ] && return 0
    sleep 2
  done
  echo "timeout waiting for $1" >&2
  return 1
}

wait_http "http://127.0.0.1:8989/ping" 90
wait_http "http://127.0.0.1:8080/" 90
wait_http "http://127.0.0.1:8474/version" 30

# Sonarr generates its API key on first start; read it from its config.
for _ in $(seq 1 30); do
  key=$(docker exec it-sonarr sh -c "sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' /config/config.xml" 2>/dev/null || true)
  [ -n "$key" ] && break
  sleep 2
done
[ -n "${key:-}" ] || { echo "could not read the Sonarr API key" >&2; exit 1; }

# qBittorrent prints a one-time WebUI password on first start.
for _ in $(seq 1 30); do
  qpass=$(docker logs it-qbit 2>&1 | sed -n 's/.*temporary password[^:]*: *\([^ ]*\).*/\1/p' | tail -n1 || true)
  [ -n "$qpass" ] && break
  sleep 2
done
[ -n "${qpass:-}" ] || { echo "could not read the qBittorrent password" >&2; exit 1; }

echo "::add-mask::$key" 2>/dev/null || true
echo "::add-mask::$qpass" 2>/dev/null || true
{
  echo "SONARR_API_KEY=$key"
  echo "QBIT_USERNAME=admin"
  echo "QBIT_PASSWORD=$qpass"
} > "$out"
echo "services up; details written to $out"
