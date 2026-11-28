#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: publish_release.sh <release-dir>
#
# Creates the DRAFT GitHub Release from the downloaded artifact. Needs `gh`,
# and in the environment: TAG (already validated), SHA (the commit verified in
# the first job), GH_REPO, RECORDED_SUMS_SHA256 (SHA-256 of SHA256SUMS.txt as
# recorded by the build job) and RECORDED_CERT_SHA256 (the digest recorded by
# the build job). Refuses to publish if the files changed between jobs, or if
# the tag no longer points at the verified commit.
set -euo pipefail

dir="${1:?usage: publish_release.sh <release-dir>}"
: "${TAG:?}" "${SHA:?}" "${GH_REPO:?}" "${RECORDED_SUMS_SHA256:?}" "${RECORDED_CERT_SHA256:?}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"

if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Invalid tag or commit." >&2
  exit 1
fi

cd "$dir"
# The artifact crossed a job boundary: compare it with what the build job saw.
if [ "$(sha256sum SHA256SUMS.txt | cut -d' ' -f1)" != "$RECORDED_SUMS_SHA256" ]; then
  echo "::error::SHA256SUMS.txt differs from the one the build job recorded." >&2
  exit 1
fi
if [ "$(cat SIGNING-CERT-SHA256.txt)" != "$RECORDED_CERT_SHA256" ]; then
  echo "::error::SIGNING-CERT-SHA256.txt differs from the digest the build job recorded." >&2
  exit 1
fi
sha256sum -c SHA256SUMS.txt
# Every APK must be listed (no extra file smuggled into the artifact).
for apk in ./*.apk; do
  grep -qF -- "  ${apk#./}" SHA256SUMS.txt || { echo "::error::An APK is not listed in SHA256SUMS.txt." >&2; exit 1; }
done

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "::error::A release for ${TAG} already exists. Delete it (and keep the tag) before re-running."
  exit 1
fi

# Previous version tag, for release notes "since the last release".
previous="$(gh api --paginate "repos/${GH_REPO}/git/matching-refs/tags/v" --jq '.[].ref' \
  | sed 's|^refs/tags/||' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  | { cat; echo "$TAG"; } | sort -uV \
  | grep -B1 -x "$TAG" | head -n1 || true)"
notes_args=(--generate-notes)
if [ -n "$previous" ] && [ "$previous" != "$TAG" ]; then
  notes_args+=(--notes-start-tag "$previous")
fi

# The tag could have been moved after the verify job: re-check right before
# publishing.
current="$(gh api "repos/${GH_REPO}/commits/${TAG}" --jq .sha)"
if [ "$current" != "$SHA" ]; then
  echo "::error::Tag moved after verification."
  exit 1
fi

gh release create "$TAG" \
  --draft \
  --verify-tag \
  --title "Consolarr ${TAG}" \
  "${notes_args[@]}" \
  ./*.apk SHA256SUMS.txt SIGNING-CERT-SHA256.txt
{
  echo "### Draft release created for ${TAG}"
  echo "Review it on the Releases page and publish it by hand."
} >> "$summary"
