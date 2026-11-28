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

Print the certificate digest once, for later comparison with the published
value:

```sh
keytool -list -v -keystore consolarr-release.p12 -alias consolarr | grep 'SHA256:'
```

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

### 3. Protect the environment

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

Per-ABI APKs are published (arm64 for current phones, armeabi-v7a for older
ones). There is no universal APK: each APK must stay inside the 20 MiB size
gate, and mixing split and universal builds would give different version codes
and break upgrades.

### What the workflow guarantees

- Triggers: only version tags and manual runs; never `pull_request`.
- Permissions: `contents: read` by default; the publish job alone has
  `contents: write`; the provenance job alone has `id-token: write` and
  `attestations: write`.
- The keystore is decoded to a `600` file in the runner's temp directory, secrets
  reach scripts only through environment variables, and both the keystore and
  `key.properties` are removed in an `if: always()` step.
- The signature is verified with `apksigner` (build-tools 35); a debug
  certificate, or two different certificates, fail the run.
- Same gates as CI: hardened merged manifest and 20 MiB size budget.
- `.github/workflows/release-dry-run.yml` runs this exact path on pull requests
  that touch it, with a throwaway keystore generated at runtime.

## Verifying a release (for users)

```sh
sha256sum -c SHA256SUMS.txt --ignore-missing      # checksums of what you downloaded
apksigner verify --print-certs consolarr-vX.Y.Z-arm64-v8a.apk
gh attestation verify consolarr-vX.Y.Z-arm64-v8a.apk --repo venkataramanab/consolarr
```

The `SHA-256 digest` printed by `apksigner` must equal the signing certificate
digest published in [SECURITY.md](../SECURITY.md) and the README (added after
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
  keystore with the new password, update the four environment secrets, and run
  the dry run.
- **Suspected compromise** (a leaked secret, a leaked keystore, a hostile
  approval):
  1. Remove the environment secrets and disable the workflow.
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
