#!/bin/bash
################################################################################
# Advanced SSL Certificate Generator with SAN
#
# Purpose: Generate self-signed SSL certificate with multiple domains/IPs
# Usage: ./generate-ssl-cert-advanced.sh
################################################################################

set -e

CERT_DIR="./deploy/docker/proxy/ssl"
DOMAIN="vsx.hgi.com"

echo "=================================================="
echo "Advanced SSL Certificate Generator"
echo "=================================================="
echo ""

# Create directory for certificates
mkdir -p "$CERT_DIR"

# Create OpenSSL config file with SAN
cat > "$CERT_DIR/openssl.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=KR
ST=Seoul
L=Seoul
O=HGI
OU=IT
CN=$DOMAIN

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
basicConstraints = CA:FALSE

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
DNS.3 = *.hgi.com
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

echo "Generating SSL certificate with SAN (Subject Alternative Names)..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/nginx.key" \
  -out "$CERT_DIR/nginx.crt" \
  -config "$CERT_DIR/openssl.cnf" \
  -extensions v3_req

echo ""
echo "Certificate generated successfully!"
echo "Location: $CERT_DIR"
echo ""
echo "Certificate includes:"
echo "  - CN: $DOMAIN"
echo "  - SAN: $DOMAIN, localhost, *.hgi.com"
echo "  - IP: 127.0.0.1, ::1"
echo ""
echo "Next steps:"
echo "  1. Restart nginx: docker compose restart proxy"
echo "  2. Trust the certificate in your OS"
echo ""
echo "To trust the certificate on Windows:"
echo "  1. Copy nginx.crt to Windows"
echo "  2. Double-click nginx.crt"
echo "  3. Click 'Install Certificate...'"
echo "  4. Select 'Local Machine' (requires admin)"
echo "  5. Select 'Place all certificates in the following store'"
echo "  6. Browse and select 'Trusted Root Certification Authorities'"
echo "  7. Click Next and Finish"
echo ""
echo "To verify:"
echo "  openssl x509 -in $CERT_DIR/nginx.crt -text -noout | grep -A 1 'Subject Alternative Name'"
