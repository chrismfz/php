# AGENTS.md

## Repository purpose

> **This repo is `chrismfz/php`** (renamed from `chrismfz/php7`; GitHub redirects
> the old url), the one home for every source-built legacy PHP: **5.3**, **5.6** and
> **7.0–7.3**. 5.3 and 5.6 moved in from the retired `chrismfz/php53` /
> `chrismfz/php56` source forks, which are archived.

This repository builds the end-of-life **PHP 5.3 / 5.6 / 7.0 / 7.1 / 7.2 / 7.3** runtimes
for NGM, security-patched and kept buildable on current Linux, past upstream EOL.

It carries **no PHP source**. One version-parameterised builder (`build.sh`, pick
the minor with `PHP_MINOR=5.3|5.6|7.0|7.1|7.2|7.3`) fetches the **pristine php.net
release tarball** and applies a CloudLinux-derived patch series on top. That is the
only sane way to serve many minors from one repo, and it mirrors how CloudLinux's
own SRPM is shaped.

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
  `patches-local/<nn>/*.patch` — not in `build.sh` via `sed`/text rewriting.
  Build-time source rewriting is for investigation only. Follow the naming, header
  and one-change-per-patch rules in README.md → "Our own patches".

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
libmcrypt — the last only for 5.3/5.6/7.0/7.1) are **version-pinned and sha256-verified**;
`tools/check-deps.py` reports when any pin is behind (OpenSSL 3.5 LTS, curl,
Snuffleupagus, the CloudLinux SRPM per minor); the weekly `check-deps` Action opens a
`deps/auto-update` PR with `--bump`'s diff. Review it like any refresh: validate the
apply, host-build, then merge. Never make a build fetch "latest" instead.

Hardening flags live in one place, `detect_hardening()` (probed per compiler), and
`verify_hardening()` proves them on the built binaries. Keep both in step. 

A successful build ends with `write_build_stamp()`: `/opt/ngm/php/<minor>/ngm-build`
(builder commit, the input paths that shape this minor, the sha256 of
`git ls-tree -r HEAD -- <inputs>`, PHP/CloudLinux/OpenSSL/curl versions). ngm's
"update available" check recomputes that hash on the remote branch using the
stamp's own `inputs`, so if a new file starts shaping a minor's binaries, add it
to the `inputs` list there, nowhere else. A docs-only commit never flags an update. Don't
raise `_FORTIFY_SOURCE` to 3 (or add any check that aborts at runtime) casually:
those can abort on old PHP code that is merely sloppy (struct-hack arrays), so each
is its own change with the full phpt suite compared before/after.

## OpenSSL maintenance

- Build against the private **OpenSSL 3.5 LTS** under `/opt/ngm/php/openssl-3.5`,
  shared by every minor (as is `/opt/ngm/php/curl-gnutls`). A build rebuilds a
  prefix whose version differs from its pin, so never let two pins exist: this repo
  is the only place OpenSSL/curl are pinned.
- Prefer feature guards when an OpenSSL symbol was genuinely removed in 3.x; avoid
  unsafe substitutions merely to make removed constants compile. Keep libcurl on
  GnuTLS and verify no second OpenSSL ABI loads into the PHP process.

## Verification

Do not declare a port complete because it compiles. At minimum verify: successful
build + install; expected PHP and OpenSSL versions; dynamic library linkage (private
libssl/libcrypto/libcurl, no 1.1 ABI); HTTPS/TLS via both the OpenSSL stream and the
GnuTLS curl; the crypto operations the OpenSSL-3 patch touches; X509/CSR/PKCS#12 when
OpenSSL configuration handling changes; and `php-fpm -t`. `test-openssl35.sh`,
`test-openssl35-legacy.sh` and `test-openssl35-phar.sh` are the reference suites and
run at the end of `build.sh` for every minor.

`.github/workflows/ci.yml` runs on every PR: `bash -n` + `shellcheck -S warning` on
the scripts, the Python tools compile, and for each minor the pristine tarball is
fetched (sha256 pin) and the series + `patches-local` applied through `build.sh`'s
own `fetch_php_source`/`apply_patches` (sourced; `main` runs only when executed).
It does not compile. A green CI means "the patches still apply", never "it
builds": a host build is still the gate for anything that touches the compile.

When a change could alter runtime behaviour (a new base, a big refresh, a new
compat patch), build old and new side by side in scratch prefixes (`NGM_ROOT=` and
`BUILD_ROOT=` keep the live `/opt/ngm/php` untouched) and compare: `php -m`, defined
constants and internal functions, library versions, then PHP's own phpt suite by
failure list. A failure only the new build has is either a test-file artifact (rerun
it with the new binary against the old tree's `.phpt`) or a regression to fix.

## The bigger picture

The cross-repo maintainer handoff — all three builder repos, the decisions, and the
runbooks (refresh a series, bump OpenSSL in lockstep, add a version, deploy) — lives
in the **ngm** repo at `docs/legacy-php-handoff.md`. Read it before structural work.
