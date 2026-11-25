#!/bin/zsh
# Makes "Console Local Signing", a self-signed code signing certificate in your login keychain, which build.sh then signs Console with.
# With the same signature on every build, macOS keeps the Accessibility permission (used to close notification banners) across updates;
# signed ad hoc, each build is a new app to it. The certificate works on this Mac only, needs no Apple account, and lasts 10 years.
# macOS asks for your password twice: to trust the certificate for code signing, and (the first build) to let codesign use its key.
set -e
NAME="Console Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "$NAME already exists"; exit 0; fi
T=$(mktemp -d); trap 'rm -rf $T' EXIT
cat > $T/cfg <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout $T/key.pem -out $T/cert.pem -config $T/cfg 2>/dev/null
P=$(openssl rand -hex 12)
openssl pkcs12 -export -inkey $T/key.pem -in $T/cert.pem -name "$NAME" -out $T/id.p12 -passout pass:$P $( openssl version | grep -q '^OpenSSL 3' && echo -legacy )
security import $T/id.p12 -k ~/Library/Keychains/login.keychain-db -P $P -T /usr/bin/codesign >/dev/null
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db $T/cert.pem
echo "made $NAME"
