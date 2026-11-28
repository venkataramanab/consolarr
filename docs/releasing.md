<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Releasing Consolarr

Releases are built and signed by `.github/workflows/release.yml` and published
to **GitHub Releases only**. The workflow creates a **draft** release; the
owner reviews and publishes it by hand. No agent or contributor ever needs to
see the signing key.

```text
push tag vX.Y.Z -> verify (tag on main, matches pubspecs)
                -> build and sign   (environment "release": manual approval)
                -> build provenance (attestation)
                -> draft GitHub Release (APKs, SHA256SUMS.txt, cert digest)
```

## One-time setup (owner)

### 1. Create the keystore on your own machine

Do this on a machine you trust, never in CI and never in the repository.

```sh
keytool -genkeypair -v \
  -keystore consolarr-release.p12 -storetype PKCS12 \
  -alias consolarr -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Consolarr, O=Consolarr"
```

`keytool` asks for a password. Use a long random one (a password manager can
generate it). Use the same password for the store and the key (PKCS12 does not
support different ones).

Encode it for the secret:

```sh
base64 -w0 consolarr-release.p12 > consolarr-release.p12.base64   # Linux
base64 -i consolarr-release.p12 | tr -d '\n' > consolarr-release.p12.base64   # macOS
```

Where to keep things:

- Keep the `.p12` and its password in your password manager (or an encrypted
  volume), **and** make at least one **offline backup** (an encrypted USB stick
  or printed password in a safe, kept somewhere other than the primary copy).
- Delete the `.base64` file once the secret is saved.
- Never commit a keystore, not even a test one. `*.p12`, `*.jks`, `*.keystore`
  and `key.properties` are git-ignored, and gitleaks and the repo guard run in
  CI.

Print the certificate digest once. Every digest in the workflow, the release
files and these docs is **lowercase hex without colons**, so convert it the
same way:

```sh
keytool -list -v -keystore consolarr-release.p12 -alias consolarr \
  | grep 'SHA256:' | sed 's/.*SHA256: //' | tr -d ':' | tr 'A-F' 'a-f'
```

Keep the 64-character result: it is the value of the repository variable in
step 3.

### 2. Create the `release` environment and its secrets

Repository **Settings > Environments > New environment**, named exactly
`release`. Under **Environment secrets** (not repository secrets, and not
variables) add:

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | Contents of `consolarr-release.p12.base64` |
| `KEYSTORE_PASSWORD` | The keystore password |
| `KEY_ALIAS` | `consolarr` |
| `KEY_PASSWORD` | The key password (same as the store password for PKCS12) |

The password values must not contain line breaks.

### 3. Pin the signing certificate (repository variable)

Right after creating the secrets, add the digest from step 1 as a repository
**variable** (not a secret; the digest is public): **Settings > Secrets and
variables > Actions > Variables > New repository variable**, named exactly
`RELEASE_CERT_SHA256`.

The build then fails unless every APK is signed with exactly that
certificate, which protects against a swapped or wrongly generated keystore.
While the variable is empty the build only emits a `::warning::` and
continues, so the **first release can bootstrap**: after it, compare
`SIGNING-CERT-SHA256.txt` with your own record and set the variable before
the next release. The value may be given with or without colons and in any
case; it is normalised (colons and spaces removed, lowercase) before comparing.

### 4. Protect the environment

On the same page:

- **Required reviewers:** add yourself (the owner). Every release then waits
  for your manual approval before any job can read the secrets.
- **Deployment branches and tags:** choose *Selected branches and tags* and add
  a tag rule `v*.*.*`. Do not add branches. Jobs that run from anything but a
  version tag cannot use the environment, so the secrets are out of reach of
  pull requests, forks and branches.
- Leave "Allow administrators to bypass" off if you do not need it.

Also restrict who can push tags: **Settings > Rules > Rulesets** > new tag
ruleset targeting `v*.*.*`, restricting creation to maintainers.

## Releasing

Before the first release, finish step 3 as far as you can; after it, set
`RELEASE_CERT_SHA256`.

1. Bump `version:` (`MAJOR.MINOR.PATCH+BUILD`) in **both**
   `apps/consolarr/pubspec.yaml` and `apps/consolarr_play/pubspec.yaml` and
   merge it to `main`. Increase `+BUILD` on every release.
2. Tag the merge commit and push the tag:

   ```sh
   git switch main && git pull
   git tag -s vX.Y.Z -m "Consolarr vX.Y.Z"    # or: git tag -a
   git push origin vX.Y.Z
   ```

3. The workflow first checks that the tag is on `main` and that `vX.Y.Z`
   equals the `version:` of both pubspecs. A mismatch fails the run.
4. Open the run in the **Actions** tab and **approve** the `release` deployment
   after checking that the run is for the tag you pushed.
5. When it finishes, open **Releases**. A **draft** exists with:
   - `consolarr-vX.Y.Z-arm64-v8a.apk`, `consolarr-vX.Y.Z-armeabi-v7a.apk` and
     the same two for `consolarr_play`;
   - `SHA256SUMS.txt` and `SIGNING-CERT-SHA256.txt` (the signing certificate's
     SHA-256 digest);
   - generated notes covering the commits since the previous tag.
6. Compare the digest in `SIGNING-CERT-SHA256.txt` with the one you recorded
   in step 1, edit the notes, then **Publish release**.

Re-running: use **Re-run jobs** on the failed run, or start **Release** with
*Run workflow* choosing the **tag as the ref** and entering the tag name.
Workflow runs from a branch are refused. If a draft for the tag already exists,
delete the draft first (keep the tag). The obfuscation symbols
(`debug-info-<tag>`, kept 90 days) are a workflow artifact, never a release
asset; keep them if you need to symbolicate a crash.

If a run fails **before the draft release is created** (for example a workflow
bug), nothing was published, so the fix is to move the tag. Merge the fix to
`main`, then delete the tag and re-tag the same version on the fixed commit:

```sh
git push origin :refs/tags/vX.Y.Z                        # delete the remote tag
git tag -d vX.Y.Z                                        # delete the local tag
git switch main && git pull
git tag -a vX.Y.Z <sha> -m "Consolarr vX.Y.Z"            # <sha>: the fixed main commit
git push origin vX.Y.Z
```

This is **only safe while no release for that tag has been published** (no
draft, or a draft you delete first). Once a release is public, never move or
reuse its tag: bump the version and tag a new one.

Per-ABI APKs are published (arm64 for current phones, armeabi-v7a for older
ones). There is no universal APK: each APK must stay inside the 20 MiB size
gate, and mixing split and universal builds would give different version codes
and break upgrades.

### What the workflow guarantees

- Triggers: only version tags and manual runs; never `pull_request`.
- Permissions: `contents: read` by default; the publish job alone has
  `contents: write`; the provenance job alone has `id-token: write` and
  `attestations: write`.
- The keystore is decoded to a `600` file in the runner's temp directory, and
  secrets reach scripts only through environment variables. The signing step
  runs before the toolchain setup, so a missing secret fails in seconds.
- Gradle reads `key.properties` through `rootProject.file`, so the workflow
  writes one per app under `apps/*/android/` (mode `600`, git-ignored). Both it
  and the keystore are wiped (`shred`, then removed) by an `if: always()` step
  right after the signatures are verified, **before any artifact upload**, and
  again by a final `if: always()` step.
- The signature is verified with `apksigner` (build-tools 35, `--min-sdk-version
  26`): the v2 **and** v3 schemes must both verify, a debug certificate or two
  different certificates fail the run, and the certificate must equal the pinned
  `RELEASE_CERT_SHA256` (step 3).
- The publish job re-checks the artifact against the SHA-256 sums the build job
  recorded as job outputs, and that the tag still points at the commit the
  verify job checked, before it creates the draft.
- The tag is validated (`vMAJOR.MINOR.PATCH`) as the first statement of the
  first step, before it is printed anywhere.
- Same gates as CI: hardened merged manifest and 20 MiB size budget.
- `.github/workflows/release-dry-run.yml` runs this exact path on pull requests
  that touch it, with a throwaway keystore generated at runtime. Each workflow
  step is a single `bash tools/release/stage.sh <stage>` call, and the dry run
  runs the same command lines (it fails if `release.yml` calls anything else).
  Its negative tests cover: a wrong pinned digest, a v1-only signature, mixed
  and debug certificates, a moved tag, files changed between jobs, invalid
  tags and missing secrets.
  It also fails if a `release.yml` job runs a `tools/release/` script without an
  earlier `actions/checkout` step in the same job (`check_workflow_checkout.sh`,
  with a negative self-test).

Threat notes that need no code change: a heap dump of the runner process could
expose the secrets during the build (the environment's required reviewer and
tag-only rule are the control); and `shred` on the runner's copy-on-write disk
is best effort, the runner VM is discarded after the job.

## Verifying a release (for users)

```sh
sha256sum -c SHA256SUMS.txt --ignore-missing      # checksums of what you downloaded
apksigner verify --print-certs consolarr-vX.Y.Z-arm64-v8a.apk
gh attestation verify consolarr-vX.Y.Z-arm64-v8a.apk --repo venkataramanab/consolarr
```

The `SHA-256 digest` printed by `apksigner` (lowercase hex, no colons; convert
with `tr -d ':' | tr 'A-F' 'a-f'` if your tool prints colons) must equal the
signing certificate digest published in [SECURITY.md](../SECURITY.md) and the README (added after
the first release) and in `SIGNING-CERT-SHA256.txt`. Android itself refuses to
install an update signed with a different certificate. In **Obtainium** or
similar, pin that digest. A checksum file next to the APK only proves a download
was not corrupted; the certificate digest, published somewhere else, is what
proves who signed it.

`gh attestation verify` checks the build provenance: the APK was built by the
`release.yml` workflow of this repository from the tagged commit.

## Recovery: if the key is lost

Android only accepts an update signed with the **same** certificate. If the
keystore and all backups are lost, nothing can fix existing installs: you can
only publish under a new key, and users must **uninstall and reinstall** (and
set the app up again, because uninstalling deletes its data). Hence the offline
backup. Before that, check the password manager, the backups and any old
machines.

## Rotation and compromise

- **Routine rotation of the secrets** (a password change): re-encode the
  keystore with the new password, update the four environment secrets (the
  certificate and `RELEASE_CERT_SHA256` stay the same), and run the dry run.
- **Suspected compromise** (a leaked secret, a leaked keystore, a hostile
  approval):
  1. Remove the environment secrets and the `RELEASE_CERT_SHA256` variable
     and disable the workflow.
  2. Delete any draft or release you did not make; revoke the tokens and
     reviewers that were involved.
  3. Generate a **new** keystore (step 1, with a new alias if you like), set
     the new secrets, and publish a security advisory with the new certificate
     digest, the old one and the affected versions.
  4. Because the old certificate cannot be revoked on devices, users have to
     uninstall and reinstall to move to the new key. Tell them so in the
     advisory, and update the digest in `SECURITY.md` and the README.
- Never paste secrets into issues, logs or chat. If a secret may have been
  printed, treat it as compromised.
