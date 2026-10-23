#!/usr/bin/env bash
# deploy-cpanel.sh — build, package and register NGM PHP 5.6 as a cPanel vendor SCL.
#
# Produces one native RPM for the current EL major release:
#   ngm-php56-5.6.40-<release>.el9.x86_64.rpm
#   ngm-php56-5.6.40-<release>.el10.x86_64.rpm
#
# The PHP runtime is compiled locally on the target host using build.sh (PHP_MINOR=5.6).
# Each RPM release uses an immutable runtime directory; the stable SCL adapter
# points at that release. This keeps upgrades transactional and preserves the
# stable cPanel-facing php.ini path.

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SERIES="5.6"
PHP_RELEASE="5.6.40"
SCL_NAME="ngm-php56"
RPM_NAME="$SCL_NAME"
RPM_RELEASE_FILE="${REPO_DIR}/packaging/cpanel/56/RPM_RELEASE"

MODE="deploy"
case "${1:-}" in
  "") ;;
  --rpm-only) MODE="rpm-only" ;;
  --verify-only) MODE="verify-only" ;;
  -h|--help)
    cat <<USAGE
Usage: $0 [--rpm-only|--verify-only]

  default        Build locally, create RPM, install/upgrade it, verify cPanel.
  --rpm-only     Build locally and create the RPM without installing it.
  --verify-only  Verify an already-installed ${SCL_NAME} package.
USAGE
    exit 0
    ;;
  *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

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

[ "$(id -u)" -eq 0 ] || die "run as root."
[ -r "$RPM_RELEASE_FILE" ] || die "missing ${RPM_RELEASE_FILE}."
RPM_RELEASE="$(tr -d '[:space:]' < "$RPM_RELEASE_FILE")"
[[ "$RPM_RELEASE" =~ ^[1-9][0-9]*$ ]] || die "RPM_RELEASE must be a positive integer."

[ -x /usr/local/cpanel/cpanel ] || die "cPanel & WHM was not detected on this host."
command -v dnf >/dev/null 2>&1 || die "dnf is required; this deploy target supports EL systems only."
command -v rpm >/dev/null 2>&1 || die "rpm is required."

EL_MAJOR="$(rpm -E '%{rhel}' 2>/dev/null || true)"
if [[ ! "$EL_MAJOR" =~ ^(9|10)$ ]]; then
  [ -r /etc/os-release ] || die "cannot determine EL major version."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${VERSION_ID:-}" in
    9|9.*) EL_MAJOR=9 ;;
    10|10.*) EL_MAJOR=10 ;;
    *) die "unsupported OS release ${VERSION_ID:-unknown}; expected EL9 or EL10." ;;
  esac
fi

ARCH="$(rpm -E '%{_arch}')"
[ "$ARCH" = "x86_64" ] || die "only x86_64 is currently packaged (detected ${ARCH})."
DIST_TAG="$(rpm -E '%{?dist}')"
[ -n "$DIST_TAG" ] || DIST_TAG=".el${EL_MAJOR}"
RPM_NEVR="${PHP_RELEASE}-${RPM_RELEASE}${DIST_TAG}"
RELEASE_KEY="${PHP_RELEASE}-${RPM_RELEASE}${DIST_TAG}"

CPANEL_VENDOR_ROOT="/opt/ngm"
SCL_DIR="${CPANEL_VENDOR_ROOT}/${SCL_NAME}"
SCL_ROOT="${SCL_DIR}/root"
RELEASES_ROOT="${CPANEL_VENDOR_ROOT}/cpanel/${SCL_NAME}/releases"
RELEASE_DIR="${RELEASES_ROOT}/${RELEASE_KEY}"
PHP_PREFIX="${RELEASE_DIR}/${PHP_SERIES}"
BUILD_ROOT="${BUILD_ROOT:-/usr/local/src/ngm-cpanel-${SCL_NAME}}"
RPM_TOPDIR="${BUILD_ROOT}/rpmbuild"
STAGE="${BUILD_ROOT}/stage"
SPEC_FILE="${RPM_TOPDIR}/SPECS/${RPM_NAME}.spec"
OUTPUT_DIR="${REPO_DIR}/dist/cpanel/el${EL_MAJOR}"

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

install_packaging_deps() {
  log "installing RPM/SCL packaging dependencies"
  dnf install -y rpm-build redhat-rpm-config >/dev/null
  if ! command -v scl >/dev/null 2>&1; then
    dnf install -y scl-utils >/dev/null || die "scl utility is required but scl-utils could not be installed."
  fi
  command -v rpmbuild >/dev/null 2>&1 || die "rpmbuild was not installed."
  command -v scl >/dev/null 2>&1 || die "scl utility is not available."
}

build_runtime() {
  local installed_nevr=""
  if rpm -q "$RPM_NAME" >/dev/null 2>&1; then
    installed_nevr="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$RPM_NAME")"
    if [ "$installed_nevr" = "$RPM_NEVR" ]; then
      die "${RPM_NAME}-${RPM_NEVR} is already installed. Bump packaging/cpanel/RPM_RELEASE before rebuilding a new package."
    fi
  fi

  rm -rf "$RELEASE_DIR"
  mkdir -p "$RELEASES_ROOT" "$BUILD_ROOT"

  log "native EL${EL_MAJOR} build for ${RPM_NAME}-${RPM_NEVR}"
  NGM_ROOT="$RELEASE_DIR" \
  PREFIX="$PHP_PREFIX" \
  BUILD_ROOT="${BUILD_ROOT}/php-build" \
  FORCE=1 \
  FORCE_DEPS=1 \
  RUN_REGRESSION_TESTS=1 \
  PHP_MINOR="$PHP_SERIES" \
    bash "${REPO_DIR}/build.sh"

  [ -x "${PHP_PREFIX}/bin/php" ] || die "built PHP CLI missing."
  [ -x "${PHP_PREFIX}/bin/php-cgi" ] || die "built php-cgi missing; cPanel CGI/suPHP discovery requires it."
  [ -x "${PHP_PREFIX}/sbin/php-fpm" ] || die "built php-fpm missing."
}

stage_package() {
  local stage_release="${STAGE}${RELEASE_DIR}"
  local stage_scl="${STAGE}${SCL_DIR}"
  local stable_etc="${stage_scl}/etc"
  local runtime_etc="${stage_release}/${PHP_SERIES}/etc"
  local openssl_libdir curl_libdir mcrypt_libdir
  local bin

  rm -rf "$STAGE" "$RPM_TOPDIR"
  mkdir -p \
    "$STAGE/etc/scl/prefixes" \
    "$(dirname "$stage_release")" \
    "${stage_scl}/root/usr/bin" \
    "${stage_scl}/root/usr/sbin" \
    "${stage_scl}/root/usr/var/run/php-fpm" \
    "${RPM_TOPDIR}/BUILD" "${RPM_TOPDIR}/BUILDROOT" "${RPM_TOPDIR}/RPMS" \
    "${RPM_TOPDIR}/SOURCES" "${RPM_TOPDIR}/SPECS" "${RPM_TOPDIR}/SRPMS"

  cp -a "$RELEASE_DIR" "$stage_release"

  # Keep cPanel-facing configuration at a stable path across RPM releases.
  cp -a "$runtime_etc" "$stable_etc"
  rm -rf "$runtime_etc"
  ln -s "$SCL_DIR/etc" "$runtime_etc"
  ln -s "$SCL_DIR/etc" "${stage_scl}/root/etc"

  # Rewrite managed Zend extension paths to the stable SCL facade so an RPM
  # upgrade can remove the old immutable release directory safely.
  if [ -f "${stable_etc}/conf.d/00-ioncube.ini" ]; then
    cat > "${stable_etc}/conf.d/00-ioncube.ini" <<EOF_ION
; Managed by deploy-cpanel.sh. ionCube must be the first Zend extension.
zend_extension=${SCL_ROOT}/usr/ioncube/ioncube_loader_lin_${PHP_SERIES}.so
EOF_ION
  fi
  if [ -f "${stable_etc}/conf.d/10-opcache.ini" ]; then
    cat > "${stable_etc}/conf.d/10-opcache.ini" <<EOF_OPCACHE
; Managed by deploy-cpanel.sh. Load after ionCube.
zend_extension=${SCL_ROOT}/usr/lib/php/extensions/no-debug-non-zts-20131226/opcache.so
EOF_OPCACHE
  fi

  printf '%s\n' "$CPANEL_VENDOR_ROOT" > "${STAGE}/etc/scl/prefixes/${SCL_NAME}"

  for bin in php php-cgi php-config phpize phar phar.phar; do
    if [ -e "${PHP_PREFIX}/bin/${bin}" ]; then
      ln -s "${PHP_PREFIX}/bin/${bin}" "${stage_scl}/root/usr/bin/${bin}"
    fi
  done
  ln -s "${PHP_PREFIX}/sbin/php-fpm" "${stage_scl}/root/usr/sbin/php-fpm"
  [ -d "${PHP_PREFIX}/lib" ] && ln -s "${PHP_PREFIX}/lib" "${stage_scl}/root/usr/lib"
  [ -d "${PHP_PREFIX}/lib64" ] && ln -s "${PHP_PREFIX}/lib64" "${stage_scl}/root/usr/lib64"
  [ -d "${PHP_PREFIX}/include" ] && ln -s "${PHP_PREFIX}/include" "${stage_scl}/root/usr/include"
  [ -d "${PHP_PREFIX}/share" ] && ln -s "${PHP_PREFIX}/share" "${stage_scl}/root/usr/share"
  [ -d "${PHP_PREFIX}/ioncube" ] && ln -s "${PHP_PREFIX}/ioncube" "${stage_scl}/root/usr/ioncube"

  openssl_libdir="$(find_libdir "${RELEASE_DIR}/openssl-3.5" 'libssl.so.3')" || die "private OpenSSL libdir missing."
  curl_libdir="$(find_libdir "${RELEASE_DIR}/curl-gnutls" 'libcurl.so.4*')" || die "private curl libdir missing."
  mcrypt_libdir="$(find_libdir "${RELEASE_DIR}/libmcrypt" 'libmcrypt.so*')" || die "private libmcrypt libdir missing."

  cat > "${stage_scl}/enable" <<EOF_ENABLE
# Generated by ${RPM_NAME} ${PHP_RELEASE}-${RPM_RELEASE}.
export X_SCLS="${SCL_NAME}\${X_SCLS:+ \${X_SCLS}}"
export PATH="${SCL_ROOT}/usr/bin:${SCL_ROOT}/usr/sbin\${PATH:+:\${PATH}}"
export LD_LIBRARY_PATH="${openssl_libdir}:${curl_libdir}:${mcrypt_libdir}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export OPENSSL_CONF="${RELEASE_DIR}/openssl-3.5/openssl.cnf"
EOF_ENABLE
  chmod 644 "${stage_scl}/enable"
}

write_spec() {
  local item rel
  cat > "$SPEC_FILE" <<EOF_SPEC
Name:           ${RPM_NAME}
Version:        ${PHP_RELEASE}
Release:        ${RPM_RELEASE}%{?dist}
Summary:        NGM maintained PHP ${PHP_RELEASE} vendor SCL for cPanel MultiPHP
License:        PHP-3.01
URL:            https://github.com/chrismfz/php
Requires:       scl-utils
Provides:       ${RPM_NAME}(api) = 20131106
Provides:       ${RPM_NAME}(zend-abi) = 20131226

%description
NGM maintained PHP ${PHP_RELEASE} runtime for cPanel MultiPHP. The package is
built natively on the target EL release and contains PHP, PHP-FPM, CGI, ionCube,
OPcache, the maintained OpenSSL 3.5 runtime, private GnuTLS libcurl and libmcrypt.

%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ${STAGE}/. %{buildroot}/

%files
%defattr(-,root,root,-)
/etc/scl/prefixes/${SCL_NAME}
%dir ${SCL_DIR}
${SCL_DIR}/enable
${SCL_DIR}/root
%dir ${SCL_DIR}/etc
%config(noreplace) ${SCL_DIR}/etc/php.ini
EOF_SPEC

  for item in "${STAGE}${SCL_DIR}/etc"/*; do
    [ -e "$item" ] || continue
    [ "$(basename "$item")" = "php.ini" ] && continue
    rel="${item#${STAGE}}"
    printf '%s\n' "$rel" >> "$SPEC_FILE"
  done

  cat >> "$SPEC_FILE" <<EOF_SPEC
${RELEASE_DIR}

%changelog
* Fri Aug 07 2026 NGM PHP Maintenance <root@localhost> - ${PHP_RELEASE}-${RPM_RELEASE}
- NGM cPanel vendor SCL release ${RPM_RELEASE}
EOF_SPEC
}

build_rpm() {
  local built_rpm
  write_spec
  log "building ${RPM_NAME}-${RPM_NEVR}.${ARCH}.rpm"
  rpmbuild --define "_topdir ${RPM_TOPDIR}" -bb "$SPEC_FILE"
  built_rpm="$(find "${RPM_TOPDIR}/RPMS" -type f -name "${RPM_NAME}-${PHP_RELEASE}-${RPM_RELEASE}*.rpm" -print -quit)"
  [ -n "$built_rpm" ] || die "rpmbuild completed but RPM was not found."
  mkdir -p "$OUTPUT_DIR"
  cp -f "$built_rpm" "$OUTPUT_DIR/"
  RPM_PATH="${OUTPUT_DIR}/$(basename "$built_rpm")"
  log "RPM ready: ${RPM_PATH}"
}

install_rpm() {
  local rpm_path="$1"
  rm -rf "$RELEASE_DIR"
  log "installing/upgrading ${rpm_path}"
  dnf install -y "$rpm_path"
}

verify_cpanel() {
  local versions available
  command -v scl >/dev/null 2>&1 || die "scl utility is unavailable."
  scl --list 2>/dev/null | grep -Fxq "$SCL_NAME" || die "${SCL_NAME} is not registered with SCL."

  log "testing SCL CLI"
  scl enable "$SCL_NAME" 'php -v'
  scl enable "$SCL_NAME" 'php -r '\''echo PHP_VERSION," ",OPENSSL_VERSION_TEXT,"\\n"; echo ioncube_loader_version(),"\\n";'\'''

  versions="$(whmapi1 --output=json php_get_installed_versions 2>/dev/null)"
  grep -Fq "\"${SCL_NAME}\"" <<<"$versions" || die "cPanel php_get_installed_versions does not list ${SCL_NAME}."

  available="$(/usr/local/cpanel/bin/rebuild_phpconf --available 2>&1)"
  grep -Eq "^${SCL_NAME}:" <<<"$available" || die "rebuild_phpconf does not expose handlers for ${SCL_NAME}."

  log "cPanel handler discovery:"
  grep -E "^${SCL_NAME}:" <<<"$available"
  log "${SCL_NAME} cPanel vendor-SCL verification passed"
}

main() {
  install_packaging_deps

  if [ "$MODE" = "verify-only" ]; then
    rpm -q "$RPM_NAME" >/dev/null 2>&1 || die "${RPM_NAME} is not installed."
    verify_cpanel
    return
  fi

  build_runtime
  stage_package
  build_rpm

  if [ "$MODE" = "rpm-only" ]; then
    log "rpm-only mode complete; package was not installed."
    return
  fi

  install_rpm "$RPM_PATH"
  verify_cpanel
}

main "$@"
