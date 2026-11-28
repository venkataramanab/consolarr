#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: build_release.sh <tag> <out-dir> <debug-info-dir>
#
# Builds both flavours as signed, obfuscated, per-ABI release APKs
# (arm64-v8a and armeabi-v7a), runs the same gates as CI on each (hardened
# merged manifest, 20 MiB size budget) and stages them as
# <out-dir>/<app>-<tag>-<abi>.apk. Signing needs key.properties in each app's
# android directory (see prepare_signing.sh); without it the Gradle build
# refuses to produce a release APK. Run from the repository root with
# `flutter` on PATH. Obfuscation symbols go to <debug-info-dir>/<app>/ and
# are never staged for release.
set -euo pipefail

tag="${1:?usage: build_release.sh <tag> <out-dir> <debug-info-dir>}"
out="${2:?}"
debug_info="${3:?}"
root="$(pwd)"
mkdir -p "$out" "$debug_info"
out="$(cd "$out" && pwd)"
debug_info="$(cd "$debug_info" && pwd)"

for app in consolarr consolarr_play; do
  echo "::group::Build ${app}"
  (
    cd "apps/${app}"
    mkdir -p "${debug_info}/${app}"
    flutter build apk --release \
      --split-per-abi \
      --target-platform android-arm64,android-arm \
      --obfuscate "--split-debug-info=${debug_info}/${app}"

    for abi in arm64-v8a armeabi-v7a; do
      python3 "${root}/tools/ci/check_merged_manifest.py" --release \
        "build/app/intermediates/merged_manifests/release/processReleaseManifest/${abi}/AndroidManifest.xml"
      apk="build/app/outputs/flutter-apk/app-${abi}-release.apk"
      bash "${root}/tools/ci/check_apk_size.sh" "$apk" 20
      cp "$apk" "${out}/${app}-${tag}-${abi}.apk"
    done
  )
  echo "::endgroup::"
done

ls -l "$out"
