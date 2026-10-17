# Verifying a release

Every release attaches the per-host distributions as tarballs (see
[`distributions.md`](distributions.md)), a `SHA256SUMS-<version>.txt`, and the capability
registry `platforms-<version>.json`. Each of those files carries a **build provenance
attestation**: a Sigstore-signed statement, produced by `actions/attest-build-provenance`
in `release.yml`'s `dist-assets` job, that names the workflow, the commit and the run that
built the file. No peer plugin publishes one; it is what makes "this tarball is what the
repository built at tag `vX.Y.Z`" a verifiable claim rather than a filename.

## Verify an asset

```bash
ver=5.0.0
gh release download "v$ver" --repo Tamircohen28/tamirs-superpowers \
  --pattern "tamirs-superpowers-$ver-codex.tar.gz" --pattern "SHA256SUMS-$ver.txt"

# 1. The checksum the release published.
sha256sum --check --ignore-missing "SHA256SUMS-$ver.txt"

# 2. The provenance: signed by this repository's release workflow, for this file.
gh attestation verify "tamirs-superpowers-$ver-codex.tar.gz" --repo Tamircohen28/tamirs-superpowers
```

`gh attestation verify` fetches the attestation from GitHub's store, checks the Sigstore
signature and the certificate's identity (the workflow in this repository), and compares the
file's digest. It needs `gh` 2.49 or newer and network access; `--format json` prints the
statement.

## What is and is not attested

| Artifact | Attested | Why |
|---|---|---|
| `tamirs-superpowers-<version>-<target>.tar.gz` | yes | the per-host subsets |
| `SHA256SUMS-<version>.txt` | yes | so the sums file itself is provable |
| `platforms-<version>.json` | yes | the capability registry as a consumable |
| the `claude` tag's tree | no | it is a git commit, verifiable by its hash and the generated commit's parent chain (`git log claude`), not a file |
| the repository tag `v<version>` | no | a git tag; GitHub's release page records who cut it |

## When verification fails

A digest mismatch means the file is not the one the workflow built; a certificate-identity
mismatch means it was signed by something other than this repository's `release.yml`. In
both cases discard the file and download again from the release page; if it fails twice,
open an issue with the `gh attestation verify --format json` output.
