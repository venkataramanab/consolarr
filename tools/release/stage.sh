#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: stage.sh <tag|prepare|build|verify|cleanup|publish>
#
# The single place that knows the arguments of every tools/release/* script.
# release.yml runs `bash tools/release/stage.sh <stage>` for each step, and
# dry_run.sh runs the very same command, so the dry run cannot drift from the
# workflow (dry_run.sh also fails if release.yml calls anything else).
#
# Environment: TAG (every stage but cleanup), RUNNER_TEMP (scratch root),
# GITHUB_REF/GITHUB_OUTPUT/GITHUB_STEP_SUMMARY (tag, verify, publish), the four
# signing secrets (prepare), EXPECTED_CERT_SHA256 (verify), SHA, GH_REPO,
# RECORDED_SUMS_SHA256, RECORDED_CERT_SHA256 (publish).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage="${1:?usage: stage.sh <tag|prepare|build|verify|cleanup|publish>}"
tmp="${RUNNER_TEMP:?RUNNER_TEMP must be set}"
android_dirs=(apps/consolarr/android apps/consolarr_play/android)
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
output="${GITHUB_OUTPUT:-/dev/null}"

# Must run before TAG is printed anywhere. Never echoes the value.
require_valid_tag() {
  if ! [[ "${TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::The tag is not of the form vMAJOR.MINOR.PATCH." >&2
    exit 1
  fi
}

case "$stage" in
  tag)
    require_valid_tag
    # The code that runs must be the code at the tag, so a manual run has to
    # be started from the tag itself, never from a branch.
    if [ "${GITHUB_REF:-}" != "refs/tags/${TAG}" ]; then
      echo "::error::Run this workflow from the tag ${TAG}."
      exit 1
    fi
    version="$(bash "$here/check_version.sh" "$TAG" apps/consolarr/pubspec.yaml apps/consolarr_play/pubspec.yaml)"
    sha="$(git rev-parse "refs/tags/${TAG}^{commit}")"
    if [ "$sha" != "$(git rev-parse HEAD)" ]; then
      echo "::error::Checked-out commit is not the tag commit."
      exit 1
    fi
    git fetch --no-tags origin main:refs/remotes/origin/main
    if ! git merge-base --is-ancestor "$sha" refs/remotes/origin/main; then
      echo "::error::Tag ${TAG} (${sha}) is not on main."
      exit 1
    fi
    echo "Tag ${TAG} is on main and matches version ${version}."
    echo "sha=${sha}" >> "$output"
    echo "version=${version}" >> "$output"
    ;;

  prepare)
    bash "$here/prepare_signing.sh" "$tmp/signing" "${android_dirs[@]}"
    ;;

  build)
    require_valid_tag
    bash "$here/build_release.sh" "$TAG" "$tmp/release" "$tmp/debug-info"
    ;;

  verify)
    require_valid_tag
    export APKSIGNER="${APKSIGNER:-${ANDROID_HOME:-}/build-tools/35.0.0/apksigner}"
    cd "$tmp/release"
    bash "$here/verify_signature.sh" SIGNING-CERT-SHA256.txt -- ./*.apk
    sha256sum -- ./*.apk | sed 's|  \./|  |' > SHA256SUMS.txt
    cat SHA256SUMS.txt
    sums="$(sha256sum SHA256SUMS.txt | cut -d' ' -f1)"
    cert="$(cat SIGNING-CERT-SHA256.txt)"
    {
      echo "sums_sha256=${sums}"
      echo "cert_sha256=${cert}"
    } >> "$output"
    {
      echo "### Release ${TAG}"
      echo "Signing certificate SHA-256: \`${cert}\`"
      echo '```'
      cat SHA256SUMS.txt
      echo '```'
    } >> "$summary"
    ;;

  cleanup)
    bash "$here/cleanup_signing.sh" "$tmp/signing" "${android_dirs[@]}"
    ;;

  publish)
    require_valid_tag
    bash "$here/publish_release.sh" release
    ;;

  *)
    echo "Unknown stage." >&2
    exit 2
    ;;
esac
