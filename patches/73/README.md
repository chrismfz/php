# CloudLinux backported security patches

**Generated** by `tools/import-cloudlinux-patches.py` — do not hand-edit.
Re-run the tool on a newer SRPM and review `git diff patches/`.

## Source

- SRPM: `ea-php73-php-7.3.33-15.el8.cloudlinux.18.src.rpm`
- release: `15.el8.cloudlinux.18`
- sha256: `c024e966a2d39813666985a7f9b2cd88ac2abc826f6da7893aac51a5aa7b9f7d`
- url: https://repo.cloudlinux.com/cloudlinux/EA4/8.1/updates/src/ea-php73-php-7.3.33-15.el8.cloudlinux.18.src.rpm

## What is kept

81 of 114 applied patches are kept and applied by the build (see `series`); the rest are CloudLinux/LiteSpeed/EA4 runtime or build-packaging patches we do not use (full list + reason in `MANIFEST.tsv`).

| category | kept | skipped |
|---|---|---|
| CVE | 39 | 0 |
| build/packaging | 0 | 18 |
| forced | 1 | 0 |
| hardened | 41 | 0 |
| vendor/sapi | 0 | 15 |

## CVEs covered (39)

CVE-2017-8923, CVE-2017-9118, CVE-2022-31625, CVE-2022-31626, CVE-2022-31628, CVE-2022-31629, CVE-2022-31631, CVE-2022-37454, CVE-2023-0567, CVE-2023-0568, CVE-2023-0662, CVE-2023-3247, CVE-2023-3823, CVE-2023-3824, CVE-2024-2756, CVE-2024-3096, CVE-2024-5458, CVE-2024-8925, CVE-2024-8927, CVE-2024-8929, CVE-2024-11233, CVE-2024-11234, CVE-2024-11236, CVE-2025-1217, CVE-2025-1219, CVE-2025-1220, CVE-2025-1736, CVE-2025-6491, CVE-2025-14178, CVE-2026-6722, CVE-2026-6735, CVE-2026-7260, CVE-2026-7261, CVE-2026-7262, CVE-2026-7568, CVE-2026-9672, CVE-2026-14355, CVE-2026-17543, CVE-2026-109618

## Skipped (33)

- `0001-Modify-recode-to-allow-IMAP-and-recode-to-be-simulta.patch` — build/packaging glue, not a source security/bug backport
- `0002-Prevent-PEAR-package-from-bringing-in-devel.patch` — build/packaging glue, not a source security/bug backport
- `0003-Modify-standard-mail-extenstion-to-add-X-PHP-Script-.patch` — build/packaging glue, not a source security/bug backport
- `0004-Removed-ZTS-support.patch` — build/packaging glue, not a source security/bug backport
- `0006-FPM-Ensure-docroot-is-in-the-user-s-homedir.patch` — build/packaging glue, not a source security/bug backport
- `0007-Chroot-FPM-users-with-noshell-and-jailshell.patch` — CloudLinux/LiteSpeed/EA4 runtime- or SAPI-specific
- `0008-Patch-epoll.c-per-bug-report-in-upstream.patch` — build/packaging glue, not a source security/bug backport
- `0009-Add-support-for-use-of-the-system-timezone-database-.patch` — build/packaging glue, not a source security/bug backport
- `0010-Add-AUTOCONF-AUTOHEADER-variables-for-C6.patch` — build/packaging glue, not a source security/bug backport
- `0011-0020-PLESK-sig-block-reexec.patch` — build/packaging glue, not a source security/bug backport
- `0012-0021-PLESK-avoid-child-ignorance.patch` — build/packaging glue, not a source security/bug backport
- `0013-0022-PLESK-missed-kill.patch` — build/packaging glue, not a source security/bug backport
- `0014-Revert-new-.user.ini-search-behavior.patch` — build/packaging glue, not a source security/bug backport
- `0015-libxml2-2.13-makes-changes-to-how-the-parsing-state-.patch` — build/packaging glue, not a source security/bug backport
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
- `php-7.3.33-caching-sha2-password.patch` — build/packaging glue, not a source security/bug backport
- `php-7.3.33-snmp-disable-des.patch` — build/packaging glue, not a source security/bug backport
