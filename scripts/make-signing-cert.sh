#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [keychain-path]\n' "$0" >&2
    exit 2
fi

keychain=${1:-"$HOME/Library/Keychains/login.keychain-db"}
if security find-certificate -c "DauKey Local" "$keychain" > /dev/null 2>&1; then
    printf 'A DauKey Local certificate already exists in "%s".\n' "$keychain"
    printf 'Reuse its identity with scripts/bundle.sh if its private key is available.\n'
    printf 'To replace it, first remove DauKey Local and its private key from that keychain in Keychain Access, then rerun this script.\n'
    exit 0
fi

# Restrict every temporary file, including the private key and PKCS#12 password.
umask 077
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/daukey-signing.XXXXXXXX")
trap 'rm -rf -- "$temporary_directory"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$temporary_directory/certificate.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = signing

[subject]
CN = DauKey Local

[signing]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CONFIG

/usr/bin/openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -config "$temporary_directory/certificate.cnf" \
    -keyout "$temporary_directory/private-key.pem" \
    -out "$temporary_directory/certificate.pem"
/usr/bin/openssl rand -base64 32 > "$temporary_directory/password"
# These PKCS#12 algorithms are supported by macOS's keychain importer.
/usr/bin/openssl pkcs12 -export -name "DauKey Local" \
    -inkey "$temporary_directory/private-key.pem" \
    -in "$temporary_directory/certificate.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -macalg sha1 \
    -passout "file:$temporary_directory/password" \
    -out "$temporary_directory/identity.p12"

printf 'macOS may request your login password to import and trust DauKey Local.\n'
security unlock-keychain "$keychain"
security import "$temporary_directory/identity.p12" -k "$keychain" \
    -P "$(cat "$temporary_directory/password")" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" \
    "$temporary_directory/certificate.pem"
security find-identity -v -p codesigning "$keychain"
