# Legacy PHP for NGM security-patched, source-built

> **This repo is `chrismfz/php`** (renamed from `chrismfz/php7`; GitHub redirects
> the old url), the one home for every source-built legacy PHP: **5.3**, **5.6** and
> **7.0–7.3**. 5.3 and 5.6 moved in from the retired `chrismfz/php53` /
> `chrismfz/php56` source forks, which are archived.

One builder for the end-of-life **PHP 5.3 / 5.6 / 7.0 / 7.1 / 7.2 / 7.3** runtimes NGM
compiles and runs past php.net's EOL. Neither Remi (EL starts at 7.4) nor — on
EL — anyone else packages these, so NGM builds them from source into
`/opt/ngm/php/<minor>` and auto-discovers the result. On Debian these come from
Sury; this tree is for the EL gap.

This repo carries no PHP source, only:

- **`build.sh`** — one version-parameterized builder
  (`PHP_MINOR=5.3|5.6|7.0|7.1|7.2|7.3`, default 7.3);
- **`patches/<nn>/`** — the CloudLinux security series per minor;
- **`patches-local/<nn>/`** — our hand-maintained overlay per minor;
- **`ioncube/`** — the bundled ionCube loaders;
- **`tools/`** — the deterministic patch importer and `check-deps.py`;
- **`deploy-cpanel.sh`** — packages any of them as a cPanel vendor SCL RPM
  (`ngm-phpNN`, shown in WHM's MultiPHP Manager).

The PHP source itself is the **pristine php.net release tarball**, fetched and
patched at build time — exactly how CloudLinux's own SRPM is shaped, and the only
sane way to serve many minors from one repo.

Each build produces, all under `/opt/ngm/php` and baked in by RPATH so they never
collide with the host:

- a **private OpenSSL 3.5** (legacy provider on) — the same shared prefix every
  minor links against;
- a **GnuTLS libcurl** (so `ext/curl` can't drag a second OpenSSL into the
  process);
- the bundled **ionCube** loader and **Zend OPcache**;
- for **5.3 / 5.6 / 7.0 / 7.1** only, a private **libmcrypt** (`ext/mcrypt` was
  removed from core in 7.2); **5.x** also builds the old `mysql` extension (on
  mysqlnd). Snuffleupagus needs 7.0+, so 5.x refuses `ENABLE_SNUFFLEUPAGUS=1`.
  **5.3** has no Zend OPcache (bundled from 5.5 on), so none is built or loaded.

Everything is compiled with the **distro hardening flags** — the set Fedora/RHEL and
Debian give their own PHP packages: `-fstack-protector-strong`,
`-fstack-clash-protection`, `-fcf-protection` (x86), `_FORTIFY_SOURCE=2`, full RELRO
(`-z relro -z now`), a non-executable stack and a **PIE** `php`/`php-fpm`. They change
nothing PHP does; a memory-corruption bug becomes a crash instead of code execution.
Each compiler flag is probed (an older gcc or another arch goes without the one it
lacks) and the build fails if the result is not PIE + full RELRO + stack protector +
FORTIFY. The shared OpenSSL/curl/libmcrypt pick the flags up on their next rebuild
(`FORCE_DEPS=1`, or a pin bump).

NGM auto-discovers the result at `/opt/ngm/php/<minor>/sbin/php-fpm`; nothing else
on the host is touched.

## Quick start

Two ways to use these builds. Both need an **x86_64** server and **root**. The
builder installs its own build dependencies, using dnf on EL 8/9/10 or apt on
Debian/Ubuntu.

| | install where | who finds it |
|---|---|---|
| **A. Standalone** (any server, no NGM) | `/opt/ngm/php/<minor>` | you: CLI, PHP-FPM, your web server |
| **B. cPanel** | an `ngm-phpNN` RPM under `/opt/ngm/ngm-phpNN` | WHM → MultiPHP Manager, next to `ea-phpNN` and `alt-phpNN` |

The prefix is **`ngm-php`** (`ngm-php53` … `ngm-php73`). cPanel's own packages are
`ea-php`, CloudLinux's are `alt-php`, and ours are `ngm-php`.

### A. Standalone (any EL or Debian server)

```sh
git clone https://github.com/chrismfz/php.git && cd php
sudo PHP_MINOR=7.3 ./build.sh          # or 5.3 | 5.6 | 7.0 | 7.1 | 7.2 (default 7.3)
```

This takes about 10–20 minutes per minor; the first one also builds the private
OpenSSL and curl. You end up with:

- **CLI:** `/opt/ngm/php/7.3/bin/php -v`.
- **Config:** `/opt/ngm/php/7.3/etc/php.ini`, plus `etc/conf.d/` for ionCube and OPcache.
- **PHP-FPM:** `/opt/ngm/php/7.3/sbin/php-fpm`, with `etc/php-fpm.conf` (on 7.x the pool
  is in `etc/php-fpm.d/www.conf`). The default pool listens on `127.0.0.1:9000`, so
  give each minor its own port or socket if you run several.

To run FPM as a service, put this unit in `/etc/systemd/system/php73-fpm.service`:

```ini
[Unit]
Description=PHP 7.3 FPM (ngm build)
After=network.target

[Service]
ExecStart=/opt/ngm/php/7.3/sbin/php-fpm --nodaemonize --fpm-config /opt/ngm/php/7.3/etc/php-fpm.conf
ExecReload=/bin/kill -USR2 $MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl daemon-reload && sudo systemctl enable --now php73-fpm
```

Then point your web server at it (nginx: `fastcgi_pass 127.0.0.1:9000;`; Apache:
`SetHandler "proxy:fcgi://127.0.0.1:9000"`). **NGM** needs none of this: it finds
`/opt/ngm/php/<minor>/sbin/php-fpm` on its own and runs it per customer.

**Updating** (new security patches): `git pull`, then `sudo FORCE=1 PHP_MINOR=7.3 ./build.sh`,
then restart FPM.

Useful env:

| variable | effect |
|---|---|
| `APPLY_PATCHES=0` | builds pristine, without the security series |
| `FORCE=1` | recompiles in place, reusing the cached OpenSSL, curl and toolchain |
| `FORCE_DEPS=1` | also rebuilds the shared OpenSSL, curl and libmcrypt |
| `RUN_REGRESSION_TESTS=0` | skips the post-build suite |
| `PHP_RELEASE=7.3.33` | pins an exact patch release |
| `ENABLE_IONCUBE=0` | leaves out ionCube |

The default patch releases are the last of each line: **5.3.29, 5.6.40, 7.0.33, 7.1.33,
7.2.34, 7.3.33.**

### B. cPanel & WHM (MultiPHP Manager)

Requirements: cPanel & WHM on **EL 9 or EL 10** x86_64 (AlmaLinux, Rocky, CloudLinux),
run as root.

```sh
git clone https://github.com/chrismfz/php.git && cd php
sudo ./deploy-cpanel.sh --minor 7.3                    # one minor
sudo ./deploy-cpanel.sh --minor all                    # all six, one after the other
```

With `--minor all`, a failing minor doesn't stop the others. At the end it prints which
passed and which failed, with one log per minor in `/root/ngm-deploy-logs/`. A minor
whose package is already installed at the same release is only re-checked, not rebuilt.

For each minor it builds that PHP on the server, packs it into an RPM
(`dist/cpanel/el9/ngm-php73-7.3.33-1.el9.x86_64.rpm`), installs it with dnf and checks
that cPanel sees it. The RPM includes the private OpenSSL, curl, ionCube and OPcache,
so it doesn't touch `ea-php`, `alt-php` or the system libraries.

Then go to **WHM → Software → MultiPHP Manager**. `ngm-php73` (and the others) appear
in the PHP version list, and you set it per domain or as the system default, like any
`ea-phpNN`. The handlers cPanel offers for each one are printed at the end of the
deploy: `/usr/local/cpanel/bin/rebuild_phpconf --available`.

| task | how |
|---|---|
| check an installed one | `sudo ./deploy-cpanel.sh --minor 7.3 --verify-only` |
| only make the RPM (e.g. to copy to other servers of the same EL) | `--rpm-only` |
| update after `git pull` | raise the number in `packaging/cpanel/73/RPM_RELEASE`, then run the deploy again; dnf upgrades it in place and keeps the `php.ini` |
| remove | first move the domains to another PHP in MultiPHP Manager, then `sudo dnf remove ngm-php73` |

**Later: automatic updates on cPanel** (not built yet). The pieces are already there:

- Every build leaves its stamp in the RPM at
  `/opt/ngm/cpanel/ngm-phpNN/releases/<rel>/<minor>/ngm-build`. Its `inputs_tree` is the
  hash of `build.sh` + `patches/<nn>` + `patches-local/<nn>` + the ionCube loader, the
  same signal ngm uses for "update available".
- So a `deploy-cpanel.sh --update [--minor all]` would:
  1. `git pull`;
  2. recompute that hash for each installed `ngm-phpNN` and compare it with the stamp;
  3. rebuild only the minors that changed;
  4. upgrade the RPM in place (dnf keeps `php.ini`).
- Two things are needed for it:
  - an RPM release that rises on its own, e.g. derived from the git commit count, instead
    of the hand-bumped `packaging/cpanel/<nn>/RPM_RELEASE`;
  - a weekly cron or systemd timer to run it.

## Our own patches (`patches-local/<nn>/*.patch`)

Anything WE change in PHP's source — a backport CloudLinux doesn't ship (yet), a
fix of our own, a hardening, a build-compat change — is a separate, named patch in
`patches-local/<nn>/`, never an edit of the source and never a `sed` in `build.sh`.
The importer never touches that directory, so these survive every refresh. The
rules that keep it maintainable:

- **Name by kind:** `CVE-YYYY-NNNN.patch` (an upstream backport), `ngm-fix-<topic>`,
  `ngm-hardening-<topic>`, `ngm-compat-<topic>`.
- **One change per patch.** Easy to drop, rebase, or port to another minor.
- **A header in every patch:** what and why; provenance (upstream sha, ticket, or
  "ours"); whether customers see a behaviour change; and **when it can be deleted**
  (e.g. "once CloudLinux ships it", "with 5.6").
- **Applied after the CloudLinux series** (`build.sh` does this); a refresh that
  makes one conflict fails the build loudly instead of half-applying.
- **Behaviour-changing hardening sits behind an ini switch** with a safe default,
  so one customer can be exempted without a rebuild.
- **Prefer no C at all:** an ini default, a Snuffleupagus rule (7.x) or an ngm slice
  property needs no rebuild and no rebase. A C patch is code we maintain forever.

Work on them in a real tree: pristine tarball (= upstream tag `php-X.Y.Z`) + the
series as commits, so `git cherry-pick -x <php-src sha>` does a 3-way merge; then
`git format-patch` the result into `patches-local/<nn>/`.

## Security patches — where they come from

CloudLinux keeps backporting security/bug fixes to EOL PHP and ships them, one
patch per fix, inside the **public** EA4 source RPMs at
`https://repo.cloudlinux.com/cloudlinux/EA4/`. Each minor has its own source RPM
(`ea-php70`, `ea-php71`, `ea-php72`, `ea-php73`), so the importer runs per minor
and writes into `patches/<nn>/`.

- **`patches/<nn>/`** — the imported series, verbatim, in apply order.
  Machine-owned: regenerated by the importer, never hand-edited.
- **`patches/<nn>/series`** / **`MANIFEST.tsv`** / **`SOURCE`** — the ordered apply
  list, the full kept/skipped audit with sha256s, and the exact source SRPM.
- **`patches-local/<nn>/`** — our hand-maintained overlay, which the importer never
  touches, so adaptations survive a refresh:
  - `exclude` — series entries we skip, each with a reason.
  - `*.patch` — our own adaptations.

## Refreshing to a newer CloudLinux release

Mechanical, and the delta is reviewable:

```sh
# 1. grab the newest SRPM for a minor (see patches/<nn>/SOURCE for the current one)
curl -fSLO https://repo.cloudlinux.com/cloudlinux/EA4/8.1/updates/src/ea-php73-php-7.3.33-<REL>.src.rpm

# 2. regenerate patches/73/ from it (deterministic — same SRPM => identical output)
./tools/import-cloudlinux-patches.py --minor 73 ea-php73-php-7.3.33-<REL>.src.rpm

# 3. review ONLY the delta, then rebuild + test
git diff patches/73/
```

The private **OpenSSL** is pinned the same way (`build.sh`: `OPENSSL_VERSION` +
`OPENSSL_SHA256`, currently the latest **3.5 LTS**) — deliberately not "latest at
build time": pinning keeps the build reproducible, lets the tarball be
sha256-verified before it touches the crypto path, and keeps every minor on the
ONE shared `/opt/ngm/php/openssl-3.5` prefix (one repo, one pin — the same holds for
the shared `curl-gnutls` prefix). To learn when a newer
3.5 LTS ships, run **`./tools/check-deps.py`**. curl and libmcrypt are sha-pinned
too.

**Dependency watch.** `tools/check-deps.py` checks every pinned input against
upstream: the OpenSSL 3.5 LTS, curl, Snuffleupagus and the CloudLinux SRPM series
per minor. It only reports by default; `--bump` rewrites the pins and re-imports a
newer series for review. The weekly Action `.github/workflows/check-deps.yml` runs
`--bump` and opens (or refreshes) one `deps/auto-update` PR. Detection is
automatic, adoption is a reviewed merge after a host build. It also **watches**
Freexian ELTS (below): a new upload shows up in the same PR with the names of the
new `debian/patches`; `--bump` there only records what was seen. The same goes for
CloudLinux's own **alt-php** builds (`altphp/<nn>/ALTPHP`, check `altphp`): they
have shipped fixes weeks before the ea-php SRPM we import, so a new alt-php release
is reported with the CVEs its new changelog entries name that our patches do not.

## Plan B — a second source of backports (Freexian ELTS)

CloudLinux's EA4 source RPMs are public today (el8 and el9; `EA4/10` carries no
EOL PHP), but nothing obliges them to stay that way, and their newer platforms
already ship through TuxCare behind a token. So this repo does not depend on
them alone:

- **Nothing we have is lost.** Every imported patch lives in `patches/<nn>/`; if
  the EA4 tree closed tomorrow, every build keeps working. Only *new* fixes stop.
- **Freexian ELTS** (Debian's extended LTS) publishes, in the open, the patched
  sources for **php5 (5.6), php7.0, php7.3 and php7.4**
  (`https://deb.freexian.com/extended-lts/pool/main/p/`), one Debian patch per
  fix, with the same speed (their PHP2SHELL upload is dated 2026-10-21, like
  CloudLinux's). `elts/{56,70,73}/ELTS` records the upload we last looked at and
  `elts/<nn>/series` its patch list (its own directory: the CloudLinux importer
  regenerates `patches/<nn>/` from scratch); `check-deps.py` (check `elts`) reports a new one.
- **`tools/elts-audit.py`** answers "what does ELTS fix that our tree lacks",
  without trusting names: it builds our patched tree and dry-runs every ELTS patch
  whose CVE our series never mentions. **PRESENT** (applies in reverse, already in),
  **MISSING** (applies forward cleanly), **LOOK** (code differs: read it). With
  `--from` it checks the minors ELTS does not cover against the nearest one
  (`--minor 72 --from 73`, `--minor 71 --from 70`, `--minor 53 --from 56`).
- **CloudLinux alt-php** (`alt-phpNN`, CloudLinux's own build of the same EOL
  PHP, public SRPMs at `repo.cloudlinux.com/cloudlinux/8/cloudlinux-x86_64-server-8/Source/Packages/`)
  is a third watch, and a lead rather than a source: its changelog says which CVEs
  it fixed, often before the ea-php SRPM does (CVE-2025-14181 and CVE-2026-91765
  reached alt-php53/56/72 in 2026-10, while ea-php still lacked them in 2026-11).
  `check-deps.py` (check `altphp`) reports a new release and the CVEs it names that
  our patches do not; we then check our tree and port, as with ELTS.
- **If EA4 closes:** keep the last series; take new fixes from ELTS for 5.6/7.0/7.3
  (the audit says which apply as-is), port them to 7.1/7.2 and 5.3 the same way, and
  carry them as `patches-local/<nn>/CVE-*.patch` with the usual header. Upstream's
  own security commits (php-src 8.x branches, GHSA advisories) stay the last resort,
  as with GH-25089.

The first audit (2026-11-03) already found fixes ELTS carries and the CloudLinux
series does not, e.g. for 7.3: an OOB read in `php_openssl_matches_wildcard_name()`,
a heap overflow in the convert stream filters, phar tar entry injection, unbounded
recursion in SOAP parsing, mysqlnd packet overreads. So ELTS is not only a fallback:
adopting its MISSING fixes is the next step (its own reviewed change).

## Status

| minor | default release | patches | notes |
|------|-----------------|---------|-------|
| 7.3  | 7.3.33          | ✅ 76 series + 1 local (35 CVEs) | **built & verified** (ionCube, OPcache); sha256 pinned |
| 7.2  | 7.2.34          | ✅ 82 series + 1 local (35 CVEs) | **built & verified**; sha256 pinned; no `ext/mcrypt` |
| 7.1  | 7.1.33          | ✅ 127 series + 1 local (39 CVEs) | **built & verified**; sha256 pinned; `ext/mcrypt` present (deprecated) |
| 7.0  | 7.0.33          | ✅ 240 series + 1 local (45 CVEs) | **built & verified**; sha256 pinned; `ext/mcrypt` present |

All four were built & verified on AlmaLinux 10 against the private **OpenSSL 3.5.8**,
GnuTLS libcurl 8.21.0, ionCube 15.5 and Zend OPcache. The pins have since moved to
OpenSSL 3.5.9 + Snuffleupagus 0.14.0 and the 2026-10-23 CloudLinux refresh below;
those are apply-verified on the pristine tarballs, host build pending. Every
dependency tarball (OpenSSL / curl / libmcrypt) and every PHP release is now
**sha256-pinned and verified at build time**.

**5.3 source:** from `ea-php53-php-5.3.29-29.el8.cloudlinux.69` — 323 of 362
applied patches kept, with the foundational `p_option.patch` and CloudLinux's OpenSSL
1.1 port force-kept (`patches-local/53/include`); 152 CVEs. On the pristine 5.3.29
tarball the whole series applies with **no rejects and no excludes**, and every `.re`
change ships with its generated `.c`, so no autoconf/bison/re2c toolchain is needed
(the old fork needed one only because a raw git tree has no `configure`). CloudLinux
builds ea-php53 only on EL8 (OpenSSL 1.1), so two small patches on top are ours:
`patches-local/53/ngm-compat-openssl3.patch` (the `RSA_SSLV23_PADDING` guard CloudLinux
ships for 5.6/7.x, plus `OPENSSL_NO_SSL3` guards on the SSLv3 methods) and
`ngm-compat-openssl-dss1.patch` (keeps `OPENSSL_ALGO_DSS1` mapped to SHA-1, as the
old fork did, so DSA signing code keeps working).

**5.6 source:** from `ea-php56-php-5.6.40-25.el8.cloudlinux.18` — 183 of 218
applied patches kept, plus CloudLinux's OpenSSL 1.1 port and OpenSSL 3.0 follow-up
force-kept (`patches-local/56/include`); 49 CVEs. On the pristine 5.6.40 tarball the
whole series applies with **no rejects and no excludes** — the 40 excludes the old
`chrismfz/php56` fork needed existed only because its boogermann base already held
those fixes in another shape.

**7.3 source:** from `ea-php73-php-7.3.33-15.el8.cloudlinux.18`. Of 114 applied
CloudLinux patches, 80 are kept in the series and 1 (CVE-2017-9118) is rebased in
`patches-local/73/` for the pristine 7.3.33 base; the rest are CloudLinux/LiteSpeed/
EA4 runtime + build-packaging glue. CloudLinux's `php-7.3.33-fix-for-openssl-3.0.x.patch`
is force-kept (`patches-local/73/include`) — it is what lets 7.3 build against the
private OpenSSL 3.5. **Every CVE in the series is covered.**

**7.2 source:** from `ea-php72-php-7.2.34-12.el8.cloudlinux.18`. 92 of 125 applied
patches are kept in the series, plus the same rebased CVE-2017-9118 in
`patches-local/72/` and the same force-kept OpenSSL-3.0 fix. 45 CVEs; every CVE in
the series is covered. Apply verified clean on a pristine 7.2.34 tree; host build
pending.

**7.1 source:** from `ea-php71-php-7.1.33-20.el8.cloudlinux.17` — 139 of 174 applied
patches kept + rebased CVE-2017-9118 + force-kept OpenSSL-3.0 fix; 51 CVEs.
**7.0 source:** from `ea-php70-php-7.0.33-29.el8.cloudlinux.17` — 255 of 291 applied
patches kept + rebased CVE-2017-9118 + force-kept OpenSSL-3.0 fix (7.0 ships its
own `php-7.0.33-...` copy); 59 CVEs. Both apply clean on their pristine trees; host
build pending. 7.0/7.1 keep `ext/mcrypt` (private libmcrypt), removed in 7.2.

**PHP2SHELL (CVE-2026-109618 / CVE-2026-109619)** is in every series since the
2026-10-23 refresh. It is a deliberate EOL trade: exceeding `memory_limit` (or an
allocator overflow) now ends the worker with `_exit(1)` instead of a catchable
fatal error, so shutdown functions don't run and the client sees a 502; on 7.x
`session.upload_progress` is also disabled.

## History

This repo started as `chrismfz/php7` (7.0–7.3 only) and was renamed `chrismfz/php`
on 2026-10-23. 5.6 (2026-10-23) and 5.3 (2026-11-02) moved in from their own source
forks, which are archived read-only; their git history is where to look for the
reasoning behind older decisions:

- **`chrismfz/php56`** — PHP 5.6.40 from the
  [`boogermann/php5`](https://github.com/boogermann/php5) fork, with the CloudLinux
  series on top (40 excludes, because boogermann already carried many fixes in
  another shape). Its in-tree OpenSSL port (`49bff4ec`, on the boogermann base) is
  replaced here by CloudLinux's own `php-5.6.40-openssl11.patch` +
  `php-5.6.40-fix-for-openssl-3.0.x.patch`. Its `CVE-2019-11048-rfc1867-size_t.patch`
  existed only because boogermann had half-fixed that overflow (`int` → `unsigned
  int`); on the pristine base CloudLinux's full `size_t` fix applies as shipped.
- **`chrismfz/php53`** — a raw PHP 5.3.29 git tree, so it needed a private
  autoconf 2.59 / bison 2.6.4 / re2c toolchain to generate `configure` and the
  parsers; the tarball ships them. Its in-tree OpenSSL port (`2cfb431` for 1.1,
  `44f26af` for 3.5) is replaced by CloudLinux's `php-5.3.29-openssl11.patch` plus
  our `patches-local/53/ngm-compat-openssl3.patch` (the SSLv23-padding and SSLv3
  guards) and `ngm-compat-openssl-dss1.patch` (DSS1 → SHA-1, as the fork had); the
  `OBJ_create` duplicate-OID fix is already in CloudLinux's patch.

Both moves were validated old-vs-new on the ngm devbox (identical modules, constants,
functions and library versions; phpt failure lists compared) before the forks were
retired.

## Licence

PHP is under the **PHP License 3.01**; these patches are derivatives of the PHP
source under the same terms, redistributed publicly by CloudLinux. Full
provenance is kept in `patches/<nn>/SOURCE` and `MANIFEST.tsv`; no CloudLinux
branding is carried. ionCube loaders are redistributed under ionCube's own
licence (`ioncube/LICENSE.txt`). This is not legal advice.
