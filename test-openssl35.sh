#!/usr/bin/env bash
#
# test-openssl35.sh — post-build production-parity checks for a source-built
# PHP (5.6 / 7.x) against the private OpenSSL 3.5 + GnuTLS curl. Version-agnostic: it
# reads the expected release from the environment (build.sh passes it), so the
# one script serves every minor.
#
#   PHP_PREFIX=/opt/ngm/php/7.3 PHP_RELEASE=7.3.33 ./test-openssl35.sh
#
set -Eeuo pipefail

NGM_ROOT="${NGM_ROOT:-/opt/ngm/php}"
PHP_PREFIX="${PHP_PREFIX:-${NGM_ROOT}/7.3}"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-${NGM_ROOT}/openssl-3.5}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5}"        # major.minor is enough to match
CURL_VERSION="${CURL_VERSION:-}"                 # optional exact match
PHP_RELEASE="${PHP_RELEASE:-}"                   # optional exact match
PHP_BIN="${PHP_PREFIX}/bin/php"
FPM_BIN="${PHP_PREFIX}/sbin/php-fpm"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

find_openssl_libdir() {
  local dir
  for dir in "${OPENSSL_PREFIX}/lib64" "${OPENSSL_PREFIX}/lib"; do
    if [ -e "${dir}/libssl.so.3" ] && [ -e "${dir}/libcrypto.so.3" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

[ -x "$PHP_BIN" ] || die "PHP binary missing: ${PHP_BIN}"
[ -x "$FPM_BIN" ] || die "PHP-FPM binary missing: ${FPM_BIN}"
openssl_libdir="$(find_openssl_libdir)" || die "private OpenSSL 3 library directory not found"

log "PHP / OpenSSL versions"
PHP_RELEASE="$PHP_RELEASE" OPENSSL_MM="$OPENSSL_VERSION" "$PHP_BIN" -n -r '
echo PHP_VERSION, "\n";
echo OPENSSL_VERSION_TEXT, "\n";
$want = getenv("PHP_RELEASE");
if ($want !== false && $want !== "" && PHP_VERSION !== $want) {
  fwrite(STDERR, "PHP version ".PHP_VERSION." != expected ".$want."\n"); exit(1);
}
if (strpos(OPENSSL_VERSION_TEXT, "OpenSSL 3.5.") !== 0) {
  fwrite(STDERR, "unexpected OpenSSL: ".OPENSSL_VERSION_TEXT."\n"); exit(2);
}
'

log "private OpenSSL linkage"
ldd_text="$(ldd "$PHP_BIN" 2>/dev/null)"
printf '%s\n' "$ldd_text" | grep -F "libssl.so.3 => ${openssl_libdir}/" >/dev/null || die "PHP is not using private libssl.so.3"
printf '%s\n' "$ldd_text" | grep -F "libcrypto.so.3 => ${openssl_libdir}/" >/dev/null || die "PHP is not using private libcrypto.so.3"
if printf '%s\n' "$ldd_text" | grep -Eq 'lib(ssl|crypto)\.so\.1\.1'; then
  die "PHP also loaded OpenSSL 1.1"
fi

if [ -n "$CURL_VERSION" ]; then
  log "private curl version + TLS backend"
  CURL_VERSION="$CURL_VERSION" "$PHP_BIN" -n -r '
  $v = curl_version();
  $want = getenv("CURL_VERSION");
  if ($v["version"] !== $want) { fwrite(STDERR,"libcurl ".$v["version"]." != ".$want."\n"); exit(1); }
  if (stripos($v["ssl_version"], "GnuTLS") === false) { fwrite(STDERR,"curl TLS ".$v["ssl_version"]."\n"); exit(2); }
  '
fi

log "HTTPS stream + CA verification"
"$PHP_BIN" -n -r '
$d = file_get_contents("https://example.com/");
var_dump($d !== false);
if ($d === false) exit(1);
'

log "RSA SHA-256 sign / verify"
"$PHP_BIN" -n -r '
$k = openssl_pkey_new(array("private_key_bits"=>2048,"private_key_type"=>OPENSSL_KEYTYPE_RSA));
if ($k === false) exit(1);
if (!openssl_sign("php7-openssl35", $sig, $k, OPENSSL_ALGO_SHA256)) exit(2);
$d = openssl_pkey_get_details($k);
$pub = openssl_pkey_get_public($d["key"]);
$v = openssl_verify("php7-openssl35", $sig, $pub, OPENSSL_ALGO_SHA256);
var_dump($v === 1);
if ($v !== 1) exit(3);
'

log "RSA OAEP encrypt / decrypt"
"$PHP_BIN" -n -r '
$k = openssl_pkey_new(array("private_key_bits"=>2048,"private_key_type"=>OPENSSL_KEYTYPE_RSA));
$d = openssl_pkey_get_details($k);
$pub = openssl_pkey_get_public($d["key"]);
$plain = "php7-openssl35-rsa";
if (!openssl_public_encrypt($plain, $enc, $pub, OPENSSL_PKCS1_OAEP_PADDING)) exit(1);
if (!openssl_private_decrypt($enc, $dec, $k, OPENSSL_PKCS1_OAEP_PADDING)) exit(2);
var_dump($dec === $plain);
if ($dec !== $plain) exit(3);
'

log "AES-256-CBC encrypt / decrypt"
"$PHP_BIN" -n -r '
$plain = "php7-openssl35-aes";
$key = hash("sha256", "test-key", true);
$iv = str_repeat("A", 16);
$enc = openssl_encrypt($plain, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
if ($enc === false) exit(1);
$dec = openssl_decrypt($enc, "aes-256-cbc", $key, OPENSSL_RAW_DATA, $iv);
var_dump($dec === $plain);
if ($dec !== $plain) exit(2);
'

log "CSR + self-signed X509"
"$PHP_BIN" -n -r '
$dn = array("commonName"=>"ngm-openssl35.local", "organizationName"=>"NGM test");
$k = openssl_pkey_new(array("private_key_bits"=>2048,"private_key_type"=>OPENSSL_KEYTYPE_RSA));
$csr = openssl_csr_new($dn, $k, array("digest_alg"=>"sha256"));
if ($csr === false) exit(1);
$crt = openssl_csr_sign($csr, null, $k, 1, array("digest_alg"=>"sha256"));
if ($crt === false) exit(2);
if (!openssl_x509_export($crt, $pem)) exit(3);
var_dump(strpos($pem, "BEGIN CERTIFICATE") !== false);
if (strpos($pem, "BEGIN CERTIFICATE") === false) exit(4);
'

log "PKCS#12 export / read"
"$PHP_BIN" -n -r '
$dn = array("commonName"=>"ngm-openssl35.local");
$k = openssl_pkey_new(array("private_key_bits"=>2048,"private_key_type"=>OPENSSL_KEYTYPE_RSA));
$csr = openssl_csr_new($dn, $k, array("digest_alg"=>"sha256"));
$crt = openssl_csr_sign($csr, null, $k, 1, array("digest_alg"=>"sha256"));
if (!openssl_pkcs12_export($crt, $p12, $k, "test-pass")) exit(1);
$out = array();
if (!openssl_pkcs12_read($p12, $out, "test-pass")) exit(2);
var_dump(isset($out["cert"]), isset($out["pkey"]));
if (!isset($out["cert"]) || !isset($out["pkey"])) exit(3);
'

if [ -f "${PHP_PREFIX}/etc/php-fpm.conf" ]; then
  log "FPM config test"
  "$FPM_BIN" -t
fi

log "all PHP OpenSSL 3.5 checks passed for ${PHP_PREFIX}"
