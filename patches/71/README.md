# CloudLinux backported security patches

**Generated** by `tools/import-cloudlinux-patches.py` — do not hand-edit.
Re-run the tool on a newer SRPM and review `git diff patches/`.

## Source

- SRPM: `ea-php71-php-7.1.33-20.el8.cloudlinux.17.src.rpm`
- release: `20.el8.cloudlinux.17`
- sha256: `d59f0b68bdb004d941c5e096f4a09adb80feecbb4bb711113e6d5ea347265e9f`
- url: https://repo.cloudlinux.com/cloudlinux/EA4/8.1/updates/src/ea-php71-php-7.1.33-20.el8.cloudlinux.17.src.rpm

## What is kept

140 of 174 applied patches are kept and applied by the build (see `series`); the rest are CloudLinux/LiteSpeed/EA4 runtime or build-packaging patches we do not use (full list + reason in `MANIFEST.tsv`).

| category | kept | skipped |
|---|---|---|
| CVE | 52 | 0 |
| bug | 43 | 0 |
| build/packaging | 0 | 19 |
| forced | 1 | 0 |
| hardened | 44 | 0 |
| vendor/sapi | 0 | 15 |

## CVEs covered (51)

CVE-2017-8923, CVE-2017-9118, CVE-2017-9119, CVE-2017-9120, CVE-2019-9025, CVE-2019-11048, CVE-2019-19246, CVE-2020-7067, CVE-2020-7068, CVE-2020-7069, CVE-2020-7070, CVE-2020-7071, CVE-2021-21703, CVE-2021-21705, CVE-2021-21707, CVE-2022-31625, CVE-2022-31626, CVE-2022-31628, CVE-2022-31629, CVE-2022-31631, CVE-2023-0567, CVE-2023-0568, CVE-2023-0662, CVE-2023-3247, CVE-2023-3823, CVE-2023-3824, CVE-2024-2756, CVE-2024-3096, CVE-2024-5458, CVE-2024-8925, CVE-2024-8927, CVE-2024-8929, CVE-2024-11233, CVE-2024-11234, CVE-2024-11236, CVE-2025-1217, CVE-2025-1219, CVE-2025-1220, CVE-2025-1735, CVE-2025-1736, CVE-2025-6491, CVE-2026-6722, CVE-2026-6735, CVE-2026-7260, CVE-2026-7261, CVE-2026-7262, CVE-2026-7568, CVE-2026-9672, CVE-2026-14355, CVE-2026-17543, CVE-2026-109618

## Skipped (34)

- `0001-php-5.3.0-recode.centos.patch` — build/packaging glue, not a source security/bug backport
- `0002-php-7.0.0-systzdata-v13.centos.patch` — build/packaging glue, not a source security/bug backport
- `0003-php-5.4.0-phpize.centos.patch` — build/packaging glue, not a source security/bug backport
- `0004-PHP-mail-header-patch-for-v7.1.x.patch` — build/packaging glue, not a source security/bug backport
- `0005-Removed-ZTS-support.patch` — build/packaging glue, not a source security/bug backport
- `0006-Ensure-that-php.d-is-not-scanned-when-PHPRC-is-set.patch` — build/packaging glue, not a source security/bug backport
- `0007-php-7.0.x-fpm-user-ini-docroot.patch` — build/packaging glue, not a source security/bug backport
- `0008-Chroot-FPM-users-with-noshell-and-jailshell.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `0009-php-fpm.epoll.patch` — build/packaging glue, not a source security/bug backport
- `0010-0020-PLESK-sig-block-reexec.patch` — build/packaging glue, not a source security/bug backport
- `0011-0021-PLESK-avoid-child-ignorance.patch` — build/packaging glue, not a source security/bug backport
- `0012-0022-PLESK-missed-kill.patch` — build/packaging glue, not a source security/bug backport
- `0013-php-5.6.3-datetests.centos.patch` — build/packaging glue, not a source security/bug backport
- `0014-php-7.0.0-oldpcre.centos.patch` — build/packaging glue, not a source security/bug backport
- `0015-Update-libxml-include-file-references.patch` — build/packaging glue, not a source security/bug backport
- `0016-Fix-libxml2-v2.15.0-compatibility.patch` — build/packaging glue, not a source security/bug backport
- `cloudlinux-php-fpm.7.0.dl.ea-php.v4.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `fix-bug-74960.patch` — build/packaging glue, not a source security/bug backport
- `litespeed-8.0.1-graceful_stop.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1-log.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1-move_override_ini.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1-process_lsapi_phpini.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1-tsrmls.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1-userini_homedir.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1.avoid_zombies.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1.crash_limit.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1.dis_keeplistener.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1.use_reject.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.0.1.wink_fix.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.1-cloudlinux.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `litespeed-8.3-document_root_env.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `php-7.1.33-caching-sha2-password.patch` — build/packaging glue, not a source security/bug backport
- `php-7.3.33-snmp-disable-des.patch` — build/packaging glue, not a source security/bug backport
- `php-8.2-fix-for-libxml2.13.patch` — build/packaging glue, not a source security/bug backport
