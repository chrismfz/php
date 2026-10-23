# AGENTS.md

## Repository purpose

> **This repo is `chrismfz/php`** (renamed from `chrismfz/php7`; GitHub redirects
> the old url). It is meant to become the one home for every source-built legacy
> PHP: today it builds 7.0–7.3; 5.6 and 5.3 move in later as `patches/56/` and
> `patches/53/` on pristine tarballs. Until then they stay in `chrismfz/php53` and
> `chrismfz/php56`.

This repository builds the end-of-life **PHP 7.0 / 7.1 / 7.2 / 7.3** runtimes for
NGM, security-patched and kept buildable on current Linux, past upstream EOL.

Unlike `chrismfz/php53` and `chrismfz/php56` — which **are** a forked PHP source
tree — this repo carries **no PHP source**. One version-parameterised builder
(`build.sh`, pick the minor with `PHP_MINOR=7.0|7.1|7.2|7.3`) fetches the **pristine
php.net release tarball** and applies a CloudLinux-derived patch series on top. That
is the only sane way to serve four minors from one repo, and it mirrors how
CloudLinux's own SRPM is shaped.

## Where fixes live (this repo's model)

- **`patches/<nn>/`** is **machine-owned** — regenerated verbatim by
  `tools/import-cloudlinux-patches.py` from a CloudLinux EA4 SRPM. **Never
  hand-edit it.** `series` is the apply order; `MANIFEST.tsv` the kept/skipped
  audit; `SOURCE` the exact SRPM; `README.md` the generated CVE list.
- **`patches-local/<nn>/`** is the **hand-maintained overlay** the importer never
  touches, so it survives a refresh:
  - `exclude` — series entries we skip on our base, each with a reason;
  - `include` — basenames to force-keep that `classify()` would otherwise drop
    (notably CloudLinux's OpenSSL-3 build-compat patch, which is "build/packaging"
    by classification but load-bearing because we build on OpenSSL 3);
  - `*.patch` — our own adaptations (e.g. `CVE-2017-9118` rebased for the pristine
    7.x base, whose upstream copy's `ZSTR_MAX_LEN` deletion hunk doesn't apply).
- A genuine new source fix that is NOT a CloudLinux backport goes in
  `patches-local/<nn>/*.patch` with provenance in the commit message — not in
  `build.sh` via `sed`/text rewriting. Build-time source rewriting is for
  investigation only.

To change the security series, refresh from a newer SRPM and review the delta:

```sh
./tools/import-cloudlinux-patches.py --minor 73 <ea-php73-…-NEW.src.rpm>
git diff patches/73/
```

Validate the apply **without a host** first: extract the pristine tarball, replay
`patches/<nn>/series` honoring `patches-local/<nn>/exclude`, apply
`patches-local/<nn>/*.patch`, and assert zero non-test `.rej`.

## Build scripts

`build.sh` handles environment/packaging only — dependency versions and private
prefixes, compiler flags, configure options, installation layout, provider
provisioning, runtime linkage checks, and applying the patch series. It is NOT the
canonical store for source fixes. The private build dependencies (OpenSSL, curl,
libmcrypt — the last only for 7.0/7.1) are **version-pinned and sha256-verified**;
`tools/check-deps.py` reports when any pin is behind (OpenSSL 3.5 LTS, curl,
Snuffleupagus, the CloudLinux SRPM per minor); the weekly `check-deps` Action opens a
`deps/auto-update` PR with `--bump`'s diff. Review it like any refresh: validate the
apply, host-build, then merge. Never make a build fetch "latest" instead.

## OpenSSL maintenance

- Build against the private **OpenSSL 3.5 LTS** under `/opt/ngm/php/openssl-3.5`,
  shared with php53/php56. **This repo must pin the same OpenSSL version as those
  two** — the prefix is shared, so a mismatch makes one build rebuild it out from
  under the others. Any bump is a lockstep change across all three repos.
- Prefer feature guards when an OpenSSL symbol was genuinely removed in 3.x; avoid
  unsafe substitutions merely to make removed constants compile. Keep libcurl on
  GnuTLS and verify no second OpenSSL ABI loads into the PHP process.

## Verification

Do not declare a port complete because it compiles. At minimum verify: successful
build + install; expected PHP and OpenSSL versions; dynamic library linkage (private
libssl/libcrypto/libcurl, no 1.1 ABI); HTTPS/TLS via both the OpenSSL stream and the
GnuTLS curl; the crypto operations the OpenSSL-3 patch touches; and `php-fpm -t`. The
repo's `test-openssl35.sh` is the reference regression suite and runs at the end of
`build.sh`.

## The bigger picture

The cross-repo maintainer handoff — all three builder repos, the decisions, and the
runbooks (refresh a series, bump OpenSSL in lockstep, add a version, deploy) — lives
in the **ngm** repo at `docs/legacy-php-handoff.md`. Read it before structural work.
