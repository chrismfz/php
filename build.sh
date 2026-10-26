#!/usr/bin/env bash
#
# build.sh — build a legacy PHP (5.6, 7.0/7.1/7.2/7.3) for NGM, patched.
#
# One builder, one repo, every source-built minor. Pick it with PHP_MINOR
# (default 7.3 — the closest to the still-packaged 7.4 and therefore the easiest):
#
#   sudo PHP_MINOR=7.3 ./build.sh
#
# Production prefix:
#   /opt/ngm/php/<minor>            e.g. /opt/ngm/php/7.3
#
# Private runtime dependencies (shared across every minor, built once):
#   OpenSSL 3.5.x: /opt/ngm/php/openssl-3.5   (legacy provider on)
#   curl (GnuTLS): /opt/ngm/php/curl-gnutls   (so ext/curl can't drag a second
#                                              OpenSSL into the process)
#   libmcrypt:     /opt/ngm/php/libmcrypt      (5.6/7.0/7.1 — removed in 7.2)
#
# This repo carries only the builder + the CloudLinux patch series + our own
# patches + the ionCube loaders. The PHP source is the PRISTINE php.net release
# tarball, fetched here and patched at build time — exactly how CloudLinux's own
# SRPM is shaped, and the only sane way to serve many minors from one repo.
#
# Env knobs:
#   PHP_MINOR=5.6|7.0|7.1|7.2|7.3  which minor to build (default 7.3)
#   PHP_RELEASE=7.3.33          pin an exact patch release (default: newest known)
#   FORCE=1                     rebuild PHP even if the prefix already exists
#   FORCE_DEPS=1                also rebuild the shared OpenSSL/curl/libmcrypt
#   APPLY_PATCHES=0             build pristine (skip the CloudLinux security series)
#   RUN_REGRESSION_TESTS=0      skip the post-build OpenSSL regression suite
#   RUNTIME_ONLY=1              only (re)provision runtime config + verify/test
#   ENABLE_LEGACY_PROVIDER=0    disable the private OpenSSL legacy provider
#   ENABLE_IONCUBE=0            skip the bundled ionCube loader
#   ENABLE_SNUFFLEUPAGUS=1      build + install the Snuffleupagus hardening module (PHP 7.0+; off by default)
#   SNUFFLEUPAGUS_VERSION=X.Y.Z Snuffleupagus git tag to build (default 0.14.0)
#   PHP_LIBDIR_NAME=...         override the configure system library dir
#   JOBS=N                      parallel make jobs

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PHP_MINOR="${PHP_MINOR:-7.3}"
case "$PHP_MINOR" in
  5.6) PHP_RELEASE_DEFAULT="5.6.40" ;;
  7.0) PHP_RELEASE_DEFAULT="7.0.33" ;;
  7.1) PHP_RELEASE_DEFAULT="7.1.33" ;;
  7.2) PHP_RELEASE_DEFAULT="7.2.34" ;;
  7.3) PHP_RELEASE_DEFAULT="7.3.33" ;;
  *)   echo "ERROR: unsupported PHP_MINOR '${PHP_MINOR}' (expected 5.6|7.0|7.1|7.2|7.3)" >&2; exit 2 ;;
esac
PHP_SERIES="$PHP_MINOR"
PHP_RELEASE="${PHP_RELEASE:-$PHP_RELEASE_DEFAULT}"
PHP_MINOR_NODOT="${PHP_MINOR//./}"        # 7.3 -> 73 (patch-series dir + importer key)

# mcrypt was deprecated in 7.1 and REMOVED from core in 7.2 — only build/link it
# where the extension still exists.
USE_MCRYPT=0
case "$PHP_MINOR" in 5.6|7.0|7.1) USE_MCRYPT=1 ;; esac

# PHP 5: the old `mysql` extension still exists (removed in 7.0) and customers'
# code still calls mysql_*(), so 5.x builds it on mysqlnd. Snuffleupagus needs 7.0+.
PHP5=0
case "$PHP_MINOR" in 5.*) PHP5=1 ;; esac

# Known-good sha256 of the pristine php.net tarball, per release. Empty = not
# pinned yet: the download still happens over TLS-authenticated php.net and the
# computed digest is printed, but is not enforced until a value is filled in
# here (do that once, from a build you trust). A MISMATCH always aborts.
declare -A PHP_SHA256=(
  [5.6.40]="1369a51eee3995d7fbd1c5342e5cc917760e276d561595b6052b21ace2656d1c"
  [7.0.33]="ab8c5be6e32b1f8d032909dedaaaa4bbb1a209e519abb01a52ce3914f9a13d96"
  [7.1.33]="bd7c0a9bd5433289ee01fd440af3715309faf583f75832b64fe169c100d52968"
  [7.2.34]="409e11bc6a2c18707dfc44bc61c820ddfd81e17481470f3405ee7822d8379903"
  [7.3.33]="166eaccde933381da9516a2b70ad0f447d7cec4b603d07b9a916032b215b90cc"
)

NGM_ROOT="${NGM_ROOT:-/opt/ngm/php}"
PREFIX="${PREFIX:-${NGM_ROOT}/${PHP_SERIES}}"
BUILD_ROOT="${BUILD_ROOT:-/usr/local/src/ngm-php7-build}"
SRC_DIR="${BUILD_ROOT}/php-${PHP_RELEASE}"

OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.9}"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-${NGM_ROOT}/openssl-3.5}"
CURL_VERSION="${CURL_VERSION:-8.23.0}"
CURL_PREFIX="${CURL_PREFIX:-${NGM_ROOT}/curl-gnutls}"
MCRYPT_VERSION="${MCRYPT_VERSION:-2.5.8}"
MCRYPT_PREFIX="${MCRYPT_PREFIX:-${NGM_ROOT}/libmcrypt}"

# sha256 of the private build-dependency tarballs — same policy as PHP_SHA256:
# non-empty enforces (mismatch aborts), empty warns with the computed digest.
# OpenSSL tracks the latest 3.5.x LTS line; bump OPENSSL_VERSION + this together
# (tools/check-deps.py reports when a newer 3.5.x LTS ships). The three legacy-PHP
# repos share the /opt/ngm/php/openssl-3.5 prefix, so they MUST pin the same
# OpenSSL — otherwise a build for one version rebuilds the shared prefix out from
# under the others.
OPENSSL_SHA256="${OPENSSL_SHA256:-603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a}"  # openssl-3.5.9.tar.gz
CURL_SHA256="${CURL_SHA256:-8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5}"        # curl-8.23.0.tar.xz
MCRYPT_SHA256="${MCRYPT_SHA256:-e4eb6c074bbab168ac47b947c195ff8cef9d51a211cdd18ca9c9ef34d27a373e}"     # libmcrypt-2.5.8.tar.gz
# Snuffleupagus source tarball digest — same policy as above (empty warns with
# the computed digest; non-empty enforces, mismatch aborts). Pin per SNUFFLEUPAGUS_VERSION.
SNUFFLEUPAGUS_SHA256="${SNUFFLEUPAGUS_SHA256:-080cf7e24d15a8650e271837030fca546e627c7a4c7317710c683282fdcb71c6}"                                                       # v0.14.0 GitHub tag archive

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
FORCE="${FORCE:-0}"
FORCE_DEPS="${FORCE_DEPS:-0}"
RUN_REGRESSION_TESTS="${RUN_REGRESSION_TESTS:-1}"
ENABLE_LEGACY_PROVIDER="${ENABLE_LEGACY_PROVIDER:-1}"
ENABLE_IONCUBE="${ENABLE_IONCUBE:-1}"
RUNTIME_ONLY="${RUNTIME_ONLY:-0}"
APPLY_PATCHES="${APPLY_PATCHES:-1}"   # apply patches/<minor>/series; 0 = pristine build
PHP_LIBDIR_NAME="${PHP_LIBDIR_NAME:-}"
IONCUBE_LOADER="${REPO_DIR}/ioncube/ioncube_loader_lin_${PHP_SERIES}.so"

# Snuffleupagus (jvoisin/snuffleupagus) — PHP 7.0+/8.x hardening module. OFF by
# default: like the Remi/NGM policy, the module ships only WITH a rendered
# ruleset, so a build enables it explicitly (ENABLE_SNUFFLEUPAGUS=1) and the
# NGM/CFM manager renders the real .rules into SP_RULES_DIR. v0.13.0 fixed
# CVE-2026-22034 (upload_validation ACE) — never pin older than that. v0.14.0 adds
# cookie-encryption memory-safety fixes and rejects non-ASCII bytes in rules (keep
# rendered rules ASCII). It still guards PHP 7.0-7.2 paths in its source; a very
# old 7.0/7.1 may need an older tag if it fails to compile there, and the
# build + verify() step is the gate that catches that.
ENABLE_SNUFFLEUPAGUS="${ENABLE_SNUFFLEUPAGUS:-0}"
if [ "$PHP5" = "1" ] && [ "$ENABLE_SNUFFLEUPAGUS" = "1" ]; then
  echo "ERROR: Snuffleupagus needs PHP 7.0+; it cannot be built for PHP ${PHP_MINOR}." >&2; exit 2
fi
SNUFFLEUPAGUS_VERSION="${SNUFFLEUPAGUS_VERSION:-0.14.0}"
SNUFFLEUPAGUS_REPO="${SNUFFLEUPAGUS_REPO:-https://github.com/jvoisin/snuffleupagus}"
SP_RULES_DIR="${SP_RULES_DIR:-${PREFIX}/etc/snuffleupagus.d}"

FPM_USER="${FPM_USER:-nobody}"
if getent group nogroup >/dev/null 2>&1; then
  FPM_GROUP="${FPM_GROUP:-nogroup}"
else
  FPM_GROUP="${FPM_GROUP:-nobody}"
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

on_error() {
  local rc=$?
  printf '\033[1;31mERROR:\033[0m command failed at line %s (exit %s): %s\n' \
    "${BASH_LINENO[0]:-?}" "$rc" "${BASH_COMMAND:-?}" >&2
  exit "$rc"
}
trap on_error ERR

need_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root."
}

# check_sha256 <file> <expected> <label>: enforce when a digest is pinned (mismatch
# aborts — a tampered/wrong crypto tarball must never reach the build), warn with
# the computed digest when it is not, so a new version can be pinned from a trusted run.
check_sha256() {
  local file="$1" want="$2" label="$3" got
  got="$(sha256sum "$file" | awk '{print $1}')"
  if [ -n "$want" ]; then
    [ "$got" = "$want" ] || die "${label} sha256 mismatch: got ${got}, expected ${want}."
    log "verified ${label} sha256 ${got}"
  else
    warn "no pinned sha256 for ${label} — got ${got} (pin it once trusted)."
  fi
}

fetch() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    log "cached $(basename "$dest")"
    return
  fi
  log "download ${url}"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "${dest}.part" "$url"
  mv -f "${dest}.part" "$dest"
}

find_libdir() {
  local prefix="$1" pattern="$2" dir
  for dir in "${prefix}/lib" "${prefix}/lib64"; do
    if compgen -G "${dir}/${pattern}" >/dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

find_ca_bundle() {
  local file
  for file in \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/ca-bundle.pem; do
    if [ -s "$file" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done
  return 1
}

detect_php_libdir_name() {
  if [ -n "$PHP_LIBDIR_NAME" ]; then
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    PHP_LIBDIR_NAME="lib64"
  elif command -v dpkg-architecture >/dev/null 2>&1; then
    PHP_LIBDIR_NAME="lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
  else
    PHP_LIBDIR_NAME="lib"
  fi

  log "PHP configure library directory: ${PHP_LIBDIR_NAME}"
}

ensure_configure_lib_alias() {
  local prefix="$1" pattern="$2" actual expected
  actual="$(find_libdir "$prefix" "$pattern")" || die "library ${pattern} not found under ${prefix}."
  expected="${prefix}/${PHP_LIBDIR_NAME}"

  [ "$actual" = "$expected" ] && return
  if compgen -G "${expected}/${pattern}" >/dev/null 2>&1; then
    return
  fi
  if [ -e "$expected" ] || [ -L "$expected" ]; then
    die "${expected} exists but does not expose ${pattern}; refusing to replace it."
  fi

  mkdir -p "$(dirname "$expected")"
  ln -s "$actual" "$expected"
  log "created configure-only library alias ${expected} -> ${actual}"
}

install_deps() {
  if command -v dnf >/dev/null 2>&1; then
    log "installing Alma/RHEL build dependencies"
    dnf install -y 'dnf-command(config-manager)' || true
    dnf config-manager --set-enabled crb 2>/dev/null || true
    dnf install -y epel-release 2>/dev/null || true
    dnf install -y \
      gcc gcc-c++ make ca-certificates curl git patch pkgconf-pkg-config \
      perl perl-FindBin perl-IPC-Cmd perl-File-Compare perl-Data-Dumper \
      m4 tar gzip bzip2 xz \
      libxml2-devel gnutls-devel nettle-devel libjpeg-turbo-devel libpng-devel \
      freetype-devel bzip2-devel readline-devel libxslt-devel gmp-devel \
      sqlite-devel zlib-devel gettext-devel libxcrypt-devel oniguruma-devel \
      libzip-devel \
      libpq-devel openldap-devel cyrus-sasl-devel libtidy-devel aspell-devel
    if [ "$ENABLE_SNUFFLEUPAGUS" = "1" ]; then
      log "installing Snuffleupagus (phpize) build dependencies"
      dnf install -y autoconf automake libtool re2c
    fi
  elif command -v apt-get >/dev/null 2>&1; then
    log "installing Debian build dependencies"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git patch pkg-config perl m4 \
      tar gzip bzip2 xz-utils libxml2-dev libgnutls28-dev nettle-dev \
      libjpeg-dev libpng-dev libfreetype6-dev libbz2-dev libreadline-dev \
      libxslt1-dev libgmp-dev libsqlite3-dev zlib1g-dev libgettextpo-dev \
      libcrypt-dev libpq-dev libldap2-dev libsasl2-dev libtidy-dev \
      libaspell-dev libonig-dev
    if [ "$ENABLE_SNUFFLEUPAGUS" = "1" ]; then
      log "installing Snuffleupagus (phpize) build dependencies"
      apt-get install -y --no-install-recommends autoconf automake libtool re2c
    fi
  else
    die "unsupported package manager; expected dnf or apt-get."
  fi
}

build_openssl() {
  local tarball="${BUILD_ROOT}/openssl-${OPENSSL_VERSION}.tar.gz" libdir=""
  mkdir -p "$BUILD_ROOT"

  # Keep the matching source tarball even if OpenSSL is already installed;
  # provisioning openssl.cnf uses the source release's canonical config.
  fetch "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "$tarball"
  check_sha256 "$tarball" "$OPENSSL_SHA256" "openssl-${OPENSSL_VERSION}.tar.gz"

  libdir="$(find_libdir "$OPENSSL_PREFIX" 'libssl.so.3' || true)"
  if [ -n "$libdir" ] && [ -x "${OPENSSL_PREFIX}/bin/openssl" ] && [ "$FORCE_DEPS" != "1" ]; then
    if LD_LIBRARY_PATH="$libdir" "${OPENSSL_PREFIX}/bin/openssl" version 2>/dev/null | grep -Fq "OpenSSL ${OPENSSL_VERSION}"; then
      log "OpenSSL ${OPENSSL_VERSION} already at ${OPENSSL_PREFIX}"
      return
    fi
  fi

  rm -rf "${BUILD_ROOT}/openssl-${OPENSSL_VERSION}"
  tar -xzf "$tarball" -C "$BUILD_ROOT"

  pushd "${BUILD_ROOT}/openssl-${OPENSSL_VERSION}" >/dev/null
    local openssl_perl5lib
    openssl_perl5lib="${PWD}/util/perl:${PWD}/external/perl/Text-Template-1.56/lib"
    [ -r "${PWD}/util/perl/OpenSSL/fallback.pm" ] || die "OpenSSL bundled Perl fallback module is missing."
    [ -r "${PWD}/external/perl/Text-Template-1.56/lib/Text/Template.pm" ] || die "OpenSSL bundled Text::Template module is missing."

    log "building OpenSSL ${OPENSSL_VERSION} -> ${OPENSSL_PREFIX}"
    env -u PERL5OPT PERL5LIB="$openssl_perl5lib" ./config \
      --prefix="${OPENSSL_PREFIX}" \
      --openssldir="${OPENSSL_PREFIX}" \
      shared zlib -fPIC
    env -u PERL5OPT PERL5LIB="$openssl_perl5lib" make -j"$JOBS"
    env -u PERL5OPT PERL5LIB="$openssl_perl5lib" make install_sw
  popd >/dev/null

  find_libdir "$OPENSSL_PREFIX" 'libssl.so.3' >/dev/null || \
    die "OpenSSL installed, but libssl.so.3 was not found under ${OPENSSL_PREFIX}."
}

provision_openssl_runtime_files() {
  local tarball="${BUILD_ROOT}/openssl-${OPENSSL_VERSION}.tar.gz" ca_bundle
  local tmp_config openssl_libdir providers modules_dir=""

  install -d -m 755 "${OPENSSL_PREFIX}/certs"
  install -d -m 700 "${OPENSSL_PREFIX}/private"

  if [ ! -s "${OPENSSL_PREFIX}/openssl.cnf" ]; then
    [ -s "$tarball" ] || die "OpenSSL source tarball missing; cannot provision openssl.cnf."
    log "installing OpenSSL ${OPENSSL_VERSION} configuration"
    tar -xOf "$tarball" "openssl-${OPENSSL_VERSION}/apps/openssl.cnf" > "${OPENSSL_PREFIX}/openssl.cnf"
  fi

  # The private OpenSSL tree is dedicated to the maintained legacy PHP builds.
  # Enable the legacy provider here for application compatibility without
  # weakening the host/system OpenSSL configuration or global TLS SECLEVEL.
  tmp_config="${OPENSSL_PREFIX}/openssl.cnf.tmp.$$"
  awk '
    /^# BEGIN NGM OPENSSL35 LEGACY PROVIDER$/ { skip=1; next }
    /^# END NGM OPENSSL35 LEGACY PROVIDER$/   { skip=0; next }
    !skip { print }
  ' "${OPENSSL_PREFIX}/openssl.cnf" > "$tmp_config"

  if [ "$ENABLE_LEGACY_PROVIDER" = "1" ]; then
    cat >> "$tmp_config" <<'EOF'

# BEGIN NGM OPENSSL35 LEGACY PROVIDER
# Compatibility policy for isolated legacy PHP runtimes only.
[openssl_init]
providers = ngm_provider_sect

[ngm_provider_sect]
default = ngm_default_sect
legacy = ngm_legacy_sect

[ngm_default_sect]
activate = 1

[ngm_legacy_sect]
activate = 1
# END NGM OPENSSL35 LEGACY PROVIDER
EOF
  else
    log "OpenSSL legacy provider compatibility disabled"
  fi

  mv -f "$tmp_config" "${OPENSSL_PREFIX}/openssl.cnf"
  chmod 644 "${OPENSSL_PREFIX}/openssl.cnf"

  ca_bundle="$(find_ca_bundle)" || die "could not locate the system CA bundle."
  ln -sfn "$ca_bundle" "${OPENSSL_PREFIX}/cert.pem"

  [ -r "${OPENSSL_PREFIX}/openssl.cnf" ] || die "OpenSSL configuration is not readable."
  [ -r "${OPENSSL_PREFIX}/cert.pem" ] || die "OpenSSL CA bundle link is not readable."

  if [ "$ENABLE_LEGACY_PROVIDER" = "1" ]; then
    for modules_dir in "${OPENSSL_PREFIX}/lib64/ossl-modules" "${OPENSSL_PREFIX}/lib/ossl-modules"; do
      [ -e "${modules_dir}/legacy.so" ] && break
      modules_dir=""
    done
    [ -n "$modules_dir" ] || die "OpenSSL legacy provider module was not found."

    openssl_libdir="$(find_libdir "$OPENSSL_PREFIX" 'libssl.so.3')" || die "private OpenSSL library directory not found."
    providers="$(OPENSSL_CONF="${OPENSSL_PREFIX}/openssl.cnf" OPENSSL_MODULES="$modules_dir" LD_LIBRARY_PATH="$openssl_libdir" "${OPENSSL_PREFIX}/bin/openssl" list -providers)"
    grep -Eq '^[[:space:]]+default$' <<<"$providers" || die "private OpenSSL default provider did not load."
    grep -Eq '^[[:space:]]+legacy$' <<<"$providers" || die "private OpenSSL legacy provider did not load."
    log "private OpenSSL default + legacy providers enabled"
  fi
}

build_curl() {
  local existing_lib="" ca_bundle
  existing_lib="$(find_libdir "$CURL_PREFIX" 'libcurl.so.4*' || true)"

  if [ -n "$existing_lib" ] && \
     [ -x "${CURL_PREFIX}/bin/curl-config" ] && \
     "${CURL_PREFIX}/bin/curl-config" --version 2>/dev/null | grep -Fq "libcurl ${CURL_VERSION}" && \
     "${CURL_PREFIX}/bin/curl-config" --ssl-backends 2>/dev/null | grep -qi 'GnuTLS' && \
     [ "$FORCE_DEPS" != "1" ]; then
    log "curl ${CURL_VERSION} (GnuTLS) already at ${CURL_PREFIX}"
    return
  fi

  ca_bundle="$(find_ca_bundle)" || die "could not locate the system CA bundle."
  fetch "https://curl.se/download/curl-${CURL_VERSION}.tar.xz" "${BUILD_ROOT}/curl-${CURL_VERSION}.tar.xz"
  check_sha256 "${BUILD_ROOT}/curl-${CURL_VERSION}.tar.xz" "$CURL_SHA256" "curl-${CURL_VERSION}.tar.xz"
  rm -rf "${BUILD_ROOT}/curl-${CURL_VERSION}"
  tar -xJf "${BUILD_ROOT}/curl-${CURL_VERSION}.tar.xz" -C "$BUILD_ROOT"

  pushd "${BUILD_ROOT}/curl-${CURL_VERSION}" >/dev/null
    log "building curl ${CURL_VERSION} with GnuTLS -> ${CURL_PREFIX}"
    CFLAGS="-O2 -fPIC" ./configure \
      --prefix="${CURL_PREFIX}" \
      --enable-shared --disable-static \
      --with-gnutls --without-openssl \
      --with-zlib --with-ca-bundle="${ca_bundle}" \
      --without-libpsl --without-libidn2 --without-brotli --without-zstd \
      --without-nghttp2 --without-nghttp3 --without-ngtcp2 --without-quiche \
      --without-libssh2 --without-libssh --disable-ldap --disable-ldaps
    make -j"$JOBS"
    make install
  popd >/dev/null

  "${CURL_PREFIX}/bin/curl-config" --ssl-backends 2>/dev/null | grep -qi 'GnuTLS' || \
    die "private curl was not built with GnuTLS."
}

build_libmcrypt() {
  local existing_lib=""
  existing_lib="$(find_libdir "$MCRYPT_PREFIX" 'libmcrypt.so*' || true)"
  if [ -n "$existing_lib" ] && [ "$FORCE_DEPS" != "1" ]; then
    log "libmcrypt already at ${MCRYPT_PREFIX}"
    return
  fi

  fetch \
    "https://sourceforge.net/projects/mcrypt/files/Libmcrypt/${MCRYPT_VERSION}/libmcrypt-${MCRYPT_VERSION}.tar.gz/download" \
    "${BUILD_ROOT}/libmcrypt-${MCRYPT_VERSION}.tar.gz"
  check_sha256 "${BUILD_ROOT}/libmcrypt-${MCRYPT_VERSION}.tar.gz" "$MCRYPT_SHA256" "libmcrypt-${MCRYPT_VERSION}.tar.gz"
  rm -rf "${BUILD_ROOT}/libmcrypt-${MCRYPT_VERSION}"
  tar -xzf "${BUILD_ROOT}/libmcrypt-${MCRYPT_VERSION}.tar.gz" -C "$BUILD_ROOT"

  pushd "${BUILD_ROOT}/libmcrypt-${MCRYPT_VERSION}" >/dev/null
    log "building libmcrypt ${MCRYPT_VERSION} -> ${MCRYPT_PREFIX}"
    CFLAGS="-O2 -fPIC -fcommon -Wno-error=implicit-function-declaration -Wno-error=implicit-int" \
    CPPFLAGS="-D_DEFAULT_SOURCE" \
      ./configure --prefix="${MCRYPT_PREFIX}" --disable-posix-threads
    make -j"$JOBS"
    make install
  popd >/dev/null
}

fetch_php_source() {
  local tarball="${BUILD_ROOT}/php-${PHP_RELEASE}.tar.xz" got want
  mkdir -p "$BUILD_ROOT"

  # PRISTINE php.net release tarball (not a fork) + our patch series on top —
  # the CloudLinux SRPM shape, and what lets one repo serve every minor.
  fetch "https://www.php.net/distributions/php-${PHP_RELEASE}.tar.xz" "$tarball"

  got="$(sha256sum "$tarball" | awk '{print $1}')"
  want="${PHP_SHA256[$PHP_RELEASE]:-}"
  if [ -n "$want" ]; then
    [ "$got" = "$want" ] || die "php-${PHP_RELEASE}.tar.xz sha256 mismatch: got ${got}, expected ${want}."
    log "verified php-${PHP_RELEASE}.tar.xz sha256 ${got}"
  else
    warn "no pinned sha256 for php-${PHP_RELEASE} — downloaded over TLS from php.net, digest ${got} (pin it in PHP_SHA256 once trusted)."
  fi

  rm -rf "$SRC_DIR"
  tar -xJf "$tarball" -C "$BUILD_ROOT"
  [ -x "${SRC_DIR}/configure" ] || die "pristine tarball has no executable configure at ${SRC_DIR}."

  # Do not regenerate parser/scanner output with modern host tools — the tarball
  # ships the pre-generated files, same as the 5.x trees.
  touch \
    "${SRC_DIR}/Zend/zend_language_parser.c" \
    "${SRC_DIR}/Zend/zend_language_parser.h" \
    "${SRC_DIR}/Zend/zend_language_scanner.c" \
    "${SRC_DIR}/Zend/zend_ini_parser.c" \
    "${SRC_DIR}/Zend/zend_ini_parser.h" \
    "${SRC_DIR}/Zend/zend_ini_scanner.c" 2>/dev/null || true
}

# ── CloudLinux security patch series ─────────────────────────────────────────
# Apply the security/bug backports imported from CloudLinux's public EA4 SRPM
# for this minor (patches/<nodot>/, generated by tools/import-cloudlinux-patches.py)
# onto the freshly extracted pristine source. patches/<nodot>/ is verbatim
# CloudLinux in apply order; patches-local/<nodot>/ is our hand-maintained overlay
# that survives a refresh: `exclude` lists series entries we skip (with reasons)
# and patches-local/<nodot>/*.patch are our own adaptations.
#
# The only reject class we tolerate is test fixtures (never built into the
# runtime). Any other reject aborts the build: a security patch must never
# silently half-apply.
apply_patches() {
  [ "$APPLY_PATCHES" = "1" ] || { log "APPLY_PATCHES=0 — building pristine (no security series)"; return; }
  local pdir="${REPO_DIR}/patches/${PHP_MINOR_NODOT}"
  local series="${pdir}/series"
  local excl="${REPO_DIR}/patches-local/${PHP_MINOR_NODOT}/exclude"
  local localdir="${REPO_DIR}/patches-local/${PHP_MINOR_NODOT}"
  if [ ! -f "$series" ]; then
    warn "no patches/${PHP_MINOR_NODOT}/series yet — building PHP ${PHP_RELEASE} pristine (no security series)."
    return
  fi

  pushd "$SRC_DIR" >/dev/null
    local applied=0 skipped=0
    log "applying CloudLinux security patch series for ${PHP_MINOR}"
    while read -r f rest; do
      [ -z "$f" ] && continue
      case "$f" in \#*) continue ;; esac
      if [ -f "$excl" ] && grep -vE '^[[:space:]]*#' "$excl" | grep -qxF "$f"; then
        skipped=$((skipped+1)); continue
      fi
      local pl=1; case "$rest" in *-p0*) pl=0 ;; *-p2*) pl=2 ;; esac
      patch -p"$pl" --no-backup-if-mismatch -s -i "${pdir}/$f" || true
      applied=$((applied+1))
    done < "$series"

    if [ -d "$localdir" ]; then
      for lp in "${localdir}"/*.patch; do
        [ -e "$lp" ] || continue
        log "  local adaptation: $(basename "$lp")"
        patch -p1 --no-backup-if-mismatch -s -i "$lp" || die "local patch failed to apply: $lp"
      done
    fi

    local bad
    bad="$(find . -name '*.rej' | grep -vE '/tests/' || true)"
    if [ -n "$bad" ]; then
      warn "unexpected patch rejects:"; printf '%s\n' "$bad" >&2
      die "refusing to build with half-applied security patches (resolve via patches-local/${PHP_MINOR_NODOT}/)"
    fi
    find . -name '*.rej' -delete 2>/dev/null || true
    log "security series applied (${applied} patches, ${skipped} excluded)"
  popd >/dev/null
}

build_php() {
  local openssl_libdir curl_libdir mcrypt_libdir openssl_pc_prefix
  local -a mcrypt_configure=() php5_configure=()

  if [ -x "${PREFIX}/sbin/php-fpm" ] && [ "$FORCE" != "1" ]; then
    die "PHP ${PHP_SERIES} already exists at ${PREFIX}/sbin/php-fpm (use FORCE=1 to rebuild)."
  fi

  openssl_libdir="$(find_libdir "$OPENSSL_PREFIX" 'libssl.so.3')" || die "private OpenSSL library directory not found."
  curl_libdir="$(find_libdir "$CURL_PREFIX" 'libcurl.so.4*')" || die "private curl library directory not found."

  export PATH="${CURL_PREFIX}/bin:${PATH}"
  export PKG_CONFIG_PATH="${openssl_libdir}/pkgconfig:${curl_libdir}/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LD_LIBRARY_PATH="${openssl_libdir}:${curl_libdir}:${LD_LIBRARY_PATH:-}"
  export CFLAGS="-O2 -fPIC -fcommon -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion ${CFLAGS:-}"
  export CPPFLAGS="-D_DEFAULT_SOURCE -I${OPENSSL_PREFIX}/include -I${CURL_PREFIX}/include ${CPPFLAGS:-}"
  export LDFLAGS="-L${openssl_libdir} -L${curl_libdir} -Wl,-rpath,${openssl_libdir} -Wl,-rpath,${curl_libdir} ${LDFLAGS:-}"

  if [ "$USE_MCRYPT" = "1" ]; then
    mcrypt_libdir="$(find_libdir "$MCRYPT_PREFIX" 'libmcrypt.so*')" || die "private libmcrypt library directory not found."
    export PKG_CONFIG_PATH="${mcrypt_libdir}/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${mcrypt_libdir}:${LD_LIBRARY_PATH}"
    export CPPFLAGS="-I${MCRYPT_PREFIX}/include ${CPPFLAGS}"
    export LDFLAGS="-L${mcrypt_libdir} -Wl,-rpath,${mcrypt_libdir} ${LDFLAGS}"
    mcrypt_configure=("--with-mcrypt=${MCRYPT_PREFIX}")
  fi
  [ "$PHP5" = "1" ] && php5_configure=("--with-mysql=mysqlnd")

  pkg-config --exists openssl || die "private OpenSSL pkg-config metadata not found."
  openssl_pc_prefix="$(pkg-config --variable=prefix openssl)"
  [ "$openssl_pc_prefix" = "$OPENSSL_PREFIX" ] || \
    die "pkg-config resolved OpenSSL from ${openssl_pc_prefix}, expected ${OPENSSL_PREFIX}."

  pushd "$SRC_DIR" >/dev/null
    log "configure PHP ${PHP_RELEASE} -> ${PREFIX}"
    # --with-openssl intentionally has no explicit prefix: PHP then uses
    # pkg-config, which correctly resolves the private OpenSSL lib64 install.
    # --with-mysql only on 5.x (php5_configure): the extension was removed in 7.0.
    ./configure \
      --prefix="${PREFIX}" \
      --exec-prefix="${PREFIX}" \
      --with-config-file-path="${PREFIX}/etc" \
      --with-config-file-scan-dir="${PREFIX}/etc/conf.d" \
      --with-libdir="${PHP_LIBDIR_NAME}" \
      --enable-fpm \
      --with-fpm-user="${FPM_USER}" \
      --with-fpm-group="${FPM_GROUP}" \
      --with-openssl \
      --with-zlib \
      --enable-pdo \
      --enable-opcache \
      --enable-mbstring \
      --enable-bcmath \
      --enable-calendar \
      --enable-exif \
      --enable-ftp \
      --enable-pcntl \
      --enable-shmop \
      --enable-soap \
      --enable-sockets \
      --enable-sysvmsg --enable-sysvsem --enable-sysvshm \
      --enable-zip \
      --with-bz2 \
      --with-curl="${CURL_PREFIX}" \
      --with-gd --with-jpeg-dir=/usr --with-png-dir=/usr --with-freetype-dir=/usr \
      --with-gettext \
      --with-gmp \
      --with-iconv \
      "${mcrypt_configure[@]}" \
      --with-mhash \
      "${php5_configure[@]}" \
      --with-mysqli=mysqlnd \
      --with-pdo-mysql=mysqlnd \
      --with-pgsql \
      --with-pdo-pgsql \
      --with-ldap=/usr \
      --with-ldap-sasl=/usr \
      --with-tidy=/usr \
      --with-pspell=/usr \
      --with-sqlite3=/usr \
      --with-pdo-sqlite=/usr \
      --with-readline \
      --with-xsl \
      --without-pear

    log "make -j${JOBS}"
    make -j"$JOBS"
    make install

    install -d "${PREFIX}/etc" "${PREFIX}/etc/conf.d"
    if [ ! -f "${PREFIX}/etc/php.ini" ]; then
      cp php.ini-production "${PREFIX}/etc/php.ini"
    fi

    if [ ! -f "${PREFIX}/etc/php-fpm.conf" ]; then
      if [ -f "${PREFIX}/etc/php-fpm.conf.default" ]; then
        cp "${PREFIX}/etc/php-fpm.conf.default" "${PREFIX}/etc/php-fpm.conf"
      elif [ -f sapi/fpm/php-fpm.conf ]; then
        cp sapi/fpm/php-fpm.conf "${PREFIX}/etc/php-fpm.conf"
      fi
    fi

    if [ -d "${PREFIX}/etc/php-fpm.d" ] && [ ! -f "${PREFIX}/etc/php-fpm.d/www.conf" ]; then
      if [ -f "${PREFIX}/etc/php-fpm.d/www.conf.default" ]; then
        cp "${PREFIX}/etc/php-fpm.d/www.conf.default" "${PREFIX}/etc/php-fpm.d/www.conf"
      elif [ -f sapi/fpm/www.conf ]; then
        cp sapi/fpm/www.conf "${PREFIX}/etc/php-fpm.d/www.conf"
      fi
    fi
  popd >/dev/null
}

# ── Snuffleupagus — PHP 7.0+ hardening module (built from source) ─────────────
# Remi packages it for EL (php84-php-snuffleupagus etc.) and Sury has NO package,
# so for the source-built /opt/ngm/php runtimes (and any Debian/Sury build) we
# compile it here against the just-built PHP via that PHP's own phpize/php-config.
# SP is a plain PHP extension (no external libs). Gated behind ENABLE_SNUFFLEUPAGUS;
# the loader ini + monitor-safe starter ruleset are written in
# install_runtime_extensions(). PHP 5.x is NOT supported by SP and never reaches
# here (PHP5=1 refuses ENABLE_SNUFFLEUPAGUS up front).
build_snuffleupagus() {
  [ "$ENABLE_SNUFFLEUPAGUS" = "1" ] || { log "ENABLE_SNUFFLEUPAGUS=0 — skipping Snuffleupagus"; return; }

  local phpize="${PREFIX}/bin/phpize" php_config="${PREFIX}/bin/php-config"
  [ -x "$phpize" ] || die "phpize missing at ${phpize} — build PHP before Snuffleupagus."
  [ -x "$php_config" ] || die "php-config missing at ${php_config}."

  local ver="$SNUFFLEUPAGUS_VERSION"
  local tarball="${BUILD_ROOT}/snuffleupagus-${ver}.tar.gz"
  local srcroot="${BUILD_ROOT}/snuffleupagus-${ver}"

  # GitHub tag archives are v-prefixed (e.g. v0.14.0). Override SNUFFLEUPAGUS_REPO
  # or SNUFFLEUPAGUS_VERSION to change source/tag.
  fetch "${SNUFFLEUPAGUS_REPO}/archive/refs/tags/v${ver}.tar.gz" "$tarball"
  check_sha256 "$tarball" "$SNUFFLEUPAGUS_SHA256" "snuffleupagus-${ver}.tar.gz"
  rm -rf "$srcroot"
  tar -xzf "$tarball" -C "$BUILD_ROOT"
  [ -f "${srcroot}/src/config.m4" ] || die "unexpected Snuffleupagus layout: ${srcroot}/src/config.m4 missing."

  pushd "${srcroot}/src" >/dev/null
    log "building Snuffleupagus ${ver} against PHP ${PHP_SERIES} (${php_config})"
    "$phpize"
    ./configure --enable-snuffleupagus --with-php-config="${php_config}"
    make -j"$JOBS"
  popd >/dev/null

  local extension_dir="" so_built="${srcroot}/src/modules/snuffleupagus.so"
  extension_dir="$("${php_config}" --extension-dir)"
  [ -r "$so_built" ] || die "snuffleupagus.so was not produced at ${so_built}."
  install -d -m 755 "$extension_dir"
  install -m 755 "$so_built" "${extension_dir}/snuffleupagus.so"
  log "installed snuffleupagus.so -> ${extension_dir}/snuffleupagus.so"
}

install_runtime_extensions() {
  local ioncube_dir="${PREFIX}/ioncube"
  local ioncube_target="${ioncube_dir}/ioncube_loader_lin_${PHP_SERIES}.so"
  local ioncube_ini="${PREFIX}/etc/conf.d/00-ioncube.ini"
  local opcache_ini="${PREFIX}/etc/conf.d/10-opcache.ini"
  local extension_dir opcache_so

  install -d -m 755 "${PREFIX}/etc/conf.d"

  if [ "$ENABLE_IONCUBE" = "1" ]; then
    [ -r "$IONCUBE_LOADER" ] || die "ionCube loader missing from repository: ${IONCUBE_LOADER}"
    install -d -m 755 "$ioncube_dir"
    install -m 755 "$IONCUBE_LOADER" "$ioncube_target"
    cat > "$ioncube_ini" <<EOF
; Managed by build.sh. ionCube must be the first Zend extension.
zend_extension=${ioncube_target}
EOF
    chmod 644 "$ioncube_ini"
    log "installed ionCube Loader for PHP ${PHP_SERIES}"
  else
    rm -f "$ioncube_ini"
    log "ionCube Loader disabled"
  fi

  extension_dir="$("${PREFIX}/bin/php-config" --extension-dir)"
  opcache_so="${extension_dir}/opcache.so"
  [ -r "$opcache_so" ] || die "OPcache shared extension missing: ${opcache_so}"
  cat > "$opcache_ini" <<EOF
; Managed by build.sh. Load after ionCube.
zend_extension=${opcache_so}
EOF
  chmod 644 "$opcache_ini"
  log "enabled Zend OPcache"

  # Snuffleupagus loader + monitor-safe starter ruleset. The module ships ONLY
  # with a ruleset: this starter only sets a log sink so SP loads and enforces
  # NOTHING; the NGM/CFM manager renders the real .rules into SP_RULES_DIR. A
  # rules file that fails to parse aborts PHP startup, so verify() re-checks load.
  local sp_ini="${PREFIX}/etc/conf.d/90-snuffleupagus.ini"
  local sp_so="${extension_dir}/snuffleupagus.so"
  if [ "$ENABLE_SNUFFLEUPAGUS" = "1" ]; then
    if [ ! -r "$sp_so" ]; then
      warn "ENABLE_SNUFFLEUPAGUS=1 but ${sp_so} missing — run a full build (not RUNTIME_ONLY=1) to compile it; not writing ${sp_ini}."
      rm -f "$sp_ini"
    else
      install -d -m 755 "$SP_RULES_DIR"
      if [ ! -f "${SP_RULES_DIR}/00-ngm-default.rules" ]; then
        cat > "${SP_RULES_DIR}/00-ngm-default.rules" <<'RULES'
; NGM default Snuffleupagus policy - MONITOR/placeholder only.
; The real ruleset is rendered by the NGM/CFM manager. This file only sets a
; log sink so the module loads cleanly and enforces NOTHING until real rules land.
sp.log_media("syslog");
RULES
        chmod 640 "${SP_RULES_DIR}/00-ngm-default.rules"
      fi
      cat > "$sp_ini" <<EOF
; Managed by build.sh. Snuffleupagus PHP hardening module (loads last).
; Real rules render into ${SP_RULES_DIR} (NGM/CFM manager); monitor-first.
extension=snuffleupagus.so
sp.configuration_file=${SP_RULES_DIR}/*.rules
EOF
      chmod 644 "$sp_ini"
      log "enabled Snuffleupagus (rules dir: ${SP_RULES_DIR})"
    fi
  else
    rm -f "$sp_ini"
  fi
}

verify() {
  local php_bin="${PREFIX}/bin/php" fpm_bin="${PREFIX}/sbin/php-fpm"
  local openssl_libdir curl_libdir modules module actual_version openssl_text
  local curl_version curl_tls ldd_text
  local -a want_modules

  [ -x "$php_bin" ] || die "expected CLI binary missing: ${php_bin}"
  [ -x "$fpm_bin" ] || die "expected FPM binary missing: ${fpm_bin}"

  actual_version="$("$php_bin" -n -r 'echo PHP_VERSION;' 2>/dev/null)"
  [ "$actual_version" = "$PHP_RELEASE" ] || die "built PHP reports ${actual_version}, expected ${PHP_RELEASE}."

  openssl_text="$("$php_bin" -n -r 'echo OPENSSL_VERSION_TEXT;' 2>/dev/null)"
  case "$openssl_text" in
    *"OpenSSL ${OPENSSL_VERSION}"*) ;;
    *) die "PHP loaded an unexpected OpenSSL: ${openssl_text:-unknown}" ;;
  esac

  modules="$("$php_bin" -n -m 2>/dev/null)"
  want_modules=(openssl curl gd mbstring mysqli PDO pdo_mysql pgsql pdo_pgsql ldap tidy pspell sqlite3 pdo_sqlite zip)
  [ "$USE_MCRYPT" = "1" ] && want_modules+=(mcrypt)
  [ "$PHP5" = "1" ] && want_modules+=(mysql)
  for module in "${want_modules[@]}"; do
    grep -Fxq "$module" <<<"$modules" || die "expected PHP module missing: ${module}"
  done

  if [ "$ENABLE_IONCUBE" = "1" ]; then
    log "testing ionCube Loader through production PHP configuration"
    "$php_bin" -r 'if (!function_exists("ioncube_loader_version")) { fwrite(STDERR,"ionCube Loader is not active\n"); exit(1); } echo ioncube_loader_version(),"\n";'
  fi
  log "testing Zend OPcache through production PHP configuration"
  "$php_bin" -r 'if (!function_exists("opcache_get_status")) { fwrite(STDERR,"Zend OPcache is not active\n"); exit(1); }'

  if [ "$ENABLE_SNUFFLEUPAGUS" = "1" ]; then
    log "testing Snuffleupagus loads with its ruleset through production PHP configuration"
    "$php_bin" -m 2>/dev/null | grep -Fxq snuffleupagus \
      || die "Snuffleupagus enabled but not active under production config (missing .so, or a rules file that fails to load)."
  fi

  curl_version="$("$php_bin" -n -r '$v=curl_version(); echo $v["version"];' 2>/dev/null)"
  curl_tls="$("$php_bin" -n -r '$v=curl_version(); echo $v["ssl_version"];' 2>/dev/null)"
  [ "$curl_version" = "$CURL_VERSION" ] || die "PHP loaded libcurl ${curl_version:-unknown}, expected ${CURL_VERSION}."
  case "$curl_tls" in
    *GnuTLS*) ;;
    *) die "PHP's libcurl uses an unexpected TLS backend: ${curl_tls:-unknown}" ;;
  esac

  openssl_libdir="$(find_libdir "$OPENSSL_PREFIX" 'libssl.so.3')"
  curl_libdir="$(find_libdir "$CURL_PREFIX" 'libcurl.so.4*')"
  ldd_text="$(ldd "$php_bin" 2>/dev/null)"

  grep -F "libssl.so.3 => ${openssl_libdir}/" <<<"$ldd_text" >/dev/null || \
    die "PHP is not loading private libssl.so.3 from ${openssl_libdir}."
  grep -F "libcrypto.so.3 => ${openssl_libdir}/" <<<"$ldd_text" >/dev/null || \
    die "PHP is not loading private libcrypto.so.3 from ${openssl_libdir}."
  grep -F "libcurl.so.4 => ${curl_libdir}/" <<<"$ldd_text" >/dev/null || \
    die "PHP is not loading private libcurl from ${curl_libdir}."

  if grep -Eq 'lib(ssl|crypto)\.so\.1\.1([[:space:]]|$)' <<<"$ldd_text"; then
    printf '%s\n' "$ldd_text" | grep -E 'lib(curl|ssl|crypto)\.so' >&2 || true
    die "OpenSSL 1.1 is also loaded; refusing a mixed-ABI PHP build."
  fi

  log "testing OpenSSL HTTPS stream"
  "$php_bin" -n -r '$d=file_get_contents("https://example.com/"); var_dump($d !== false); if ($d === false) exit(1);'

  log "testing private curl/GnuTLS HTTPS"
  "$php_bin" -n -r '
    $c=curl_init("https://example.com/");
    curl_setopt($c,CURLOPT_RETURNTRANSFER,true);
    curl_setopt($c,CURLOPT_TIMEOUT,15);
    $d=curl_exec($c);
    if ($d === false) { fwrite(STDERR,curl_error($c)."\n"); exit(1); }
    curl_close($c);
  '

  if [ -f "${PREFIX}/etc/php-fpm.conf" ]; then
    log "testing FPM configuration"
    "$fpm_bin" -t
  else
    warn "FPM binary built, but no active php-fpm.conf was produced."
  fi

  log "installed: $("$php_bin" -n -v | sed -n '1p')"
  log "OpenSSL: ${openssl_text}"
  log "libcurl: ${curl_version} (${curl_tls})"
  log "dynamic TLS libraries:"
  printf '%s\n' "$ldd_text" | grep -E 'lib(curl|ssl|crypto|gnutls)\.so' | sed 's/^/    /'

  if [ "$ENABLE_LEGACY_PROVIDER" = "1" ]; then
    log "testing installed OpenSSL legacy provider through default PHP config"
    "$php_bin" -n -r '$d=openssl_digest("abc","md4"); var_dump($d === "a448017aaf21d8525fc10ae87aa6729d"); if ($d !== "a448017aaf21d8525fc10ae87aa6729d") exit(1);'
  fi
}

run_regression_tests() {
  local test

  if [ "$RUN_REGRESSION_TESTS" != "1" ]; then
    log "post-build regression suite disabled"
    return
  fi

  # test-openssl35.sh: linkage, TLS, RSA/AES, CSR/X509, PKCS#12, FPM config.
  # test-openssl35-legacy.sh: the legacy provider (MD4/RC4/DES/... old code uses).
  for test in test-openssl35.sh test-openssl35-legacy.sh; do
    [ -r "${REPO_DIR}/${test}" ] || die "required regression test missing: ${REPO_DIR}/${test}"
    log "running ${test} against ${PREFIX}"
    PHP_PREFIX="$PREFIX" PHP_RELEASE="$PHP_RELEASE" OPENSSL_PREFIX="$OPENSSL_PREFIX" \
      OPENSSL_VERSION="$OPENSSL_VERSION" CURL_VERSION="$CURL_VERSION" bash "${REPO_DIR}/${test}"
  done
  log "PHP ${PHP_SERIES} production regression suites passed"
}

main() {
  need_root
  mkdir -p "$BUILD_ROOT" "$NGM_ROOT"
  log "target: PHP ${PHP_RELEASE} (minor ${PHP_MINOR}) -> ${PREFIX}"

  if [ "$RUNTIME_ONLY" = "1" ]; then
    log "runtime-only provisioning / verification for PHP ${PHP_RELEASE} at ${PREFIX}"
    [ -x "${PREFIX}/bin/php" ] || die "existing PHP CLI binary missing: ${PREFIX}/bin/php"
    [ -x "${PREFIX}/sbin/php-fpm" ] || die "existing PHP FPM binary missing: ${PREFIX}/sbin/php-fpm"
    find_libdir "$OPENSSL_PREFIX" 'libssl.so.3' >/dev/null || die "private OpenSSL 3 runtime missing under ${OPENSSL_PREFIX}."
    provision_openssl_runtime_files
    install_runtime_extensions
    verify
    run_regression_tests
    return
  fi

  install_deps
  build_openssl
  provision_openssl_runtime_files
  build_curl
  [ "$USE_MCRYPT" = "1" ] && build_libmcrypt
  detect_php_libdir_name
  ensure_configure_lib_alias "$OPENSSL_PREFIX" 'libssl.so.3'
  ensure_configure_lib_alias "$CURL_PREFIX" 'libcurl.so.4*'
  [ "$USE_MCRYPT" = "1" ] && ensure_configure_lib_alias "$MCRYPT_PREFIX" 'libmcrypt.so*'
  fetch_php_source
  apply_patches
  build_php
  build_snuffleupagus
  install_runtime_extensions
  verify
  run_regression_tests
}

main "$@"
