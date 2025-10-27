#!/bin/bash
################################################################################
# SSL Certificate Generator
#
# Purpose: Generate self-signed SSL certificate for OpenVSX
# Usage: ./generate-ssl-cert.sh
################################################################################

set -e

CERT_DIR="./deploy/docker/proxy/ssl"
DOMAIN="vsx.hgi.com"

echo "=================================================="
echo "SSL Certificate Generator for OpenVSX"
echo "=================================================="
echo ""

# Create directory for certificates
mkdir -p "$CERT_DIR"

# Generate self-signed certificate
echo "Generating self-signed certificate for $DOMAIN..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/nginx.key" \
  -out "$CERT_DIR/nginx.crt" \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=HGI/OU=IT/CN=$DOMAIN"

echo ""
echo "Certificate generated successfully!"
echo "Location: $CERT_DIR"
echo ""
echo "Files created:"
echo "  - nginx.key (private key)"
echo "  - nginx.crt (certificate)"
echo ""
echo "Next steps:"
echo "  1. Update docker-compose.yml to mount SSL certificates"
echo "  2. Update nginx.conf to enable HTTPS"
echo "  3. Restart nginx: docker compose restart proxy"
echo "  4. Trust the certificate in your browser/OS"
echo ""
echo "To trust the certificate on Windows:"
echo "  1. Double-click nginx.crt"
echo "  2. Click 'Install Certificate...'"
echo "  3. Select 'Local Machine'"
echo "  4. Select 'Place all certificates in the following store'"
echo "  5. Browse and select 'Trusted Root Certification Authorities'"
echo "  6. Click Next and Finish"
