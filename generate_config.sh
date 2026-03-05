#!/bin/bash
# Generate configuration files from templates using .env variables

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env file if it exists
if [ -f .env ]; then
    # Export all variables from .env, handling special characters
    set -a
    source .env
    set +a
fi

# Set defaults if not defined
AUTHELIA_ADMIN_EMAIL="${AUTHELIA_ADMIN_EMAIL:-admin@example.com}"
AUTHELIA_SMTP_HOST="${AUTHELIA_SMTP_HOST:-smtp.fastmail.com}"
AUTHELIA_SMTP_PORT="${AUTHELIA_SMTP_PORT:-587}"

# DOMAIN must be set in .env file - no default for security
if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN environment variable is not set"
    echo "Please set it in your .env file"
    exit 1
fi

# Check for required OIDC secrets
if [ -z "$OPENWEBUI_OIDC_SECRET" ]; then
    echo "Warning: OPENWEBUI_OIDC_SECRET not set in .env"
    echo "Generating new secret..."
    OPENWEBUI_OIDC_SECRET=$(openssl rand -hex 32)
    echo "OPENWEBUI_OIDC_SECRET=$OPENWEBUI_OIDC_SECRET" >> .env
fi

if [ -z "$AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET" ]; then
    echo "Warning: AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET not set in .env"
    echo "Generating new secret..."
    AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET=$(openssl rand -hex 64)
    echo "AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET=$AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET" >> .env
fi

# Generate RSA private key if not exists
if [ -z "$AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY" ]; then
    echo "Warning: AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY not set in .env"
    echo "Generating new RSA key..."
    openssl genpkey -algorithm RSA -outform PEM -pkeyopt rsa_keygen_bits:4096 > /tmp/oidc_private_key.pem
    # Store base64 encoded in .env for reference
    AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY=$(cat /tmp/oidc_private_key.pem)
    echo "AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_B64=$(cat /tmp/oidc_private_key.pem | base64 -w0)" >> .env
    echo "Key generated and stored"
else
    # Decode from base64 if it exists
    if [ -n "$AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_B64" ]; then
        echo "$AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_B64" | base64 -d > /tmp/oidc_private_key.pem
    else
        # Try to use the existing key directly
        echo "$AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY" > /tmp/oidc_private_key.pem
    fi
fi

# Generate users_database.yml
echo "Generating users_database.yml..."
sed "s|\\\${AUTHELIA_ADMIN_EMAIL}|${AUTHELIA_ADMIN_EMAIL}|g" \
    services/authelia/users_database.yml.template \
    > services/authelia/users_database.yml

echo "  ✓ Generated users_database.yml with email: ${AUTHELIA_ADMIN_EMAIL}"

# Generate configuration.yml (first part - before OIDC)
echo "Generating configuration.yml..."
cat services/authelia/configuration.yml.template | \
    sed "s|\\\${DOMAIN}|${DOMAIN}|g" | \
    sed "s|\\\${AUTHELIA_ADMIN_EMAIL}|${AUTHELIA_ADMIN_EMAIL}|g" | \
    sed "s|\\\${AUTHELIA_NOTIFIER_SMTP_USERNAME}|${AUTHELIA_SMTP_USERNAME}|g" | \
    sed "s|\\\${AUTHELIA_NOTIFIER_SMTP_PASSWORD}|${AUTHELIA_SMTP_PASSWORD}|g" | \
    sed "s|\\\${AUTHELIA_NOTIFIER_SMTP_SENDER}|${AUTHELIA_SMTP_SENDER}|g" | \
    sed "s|\\\${OPENWEBUI_OIDC_SECRET}|${OPENWEBUI_OIDC_SECRET}|g" | \
    sed "s|\\\${AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET}|${AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET}|g" \
    > services/authelia/configuration.yml

# Now handle the private key separately (it's multi-line)
# Read the template again and replace the private key placeholder
sed -i "/issuer_private_key:/r /tmp/oidc_private_key.pem" services/authelia/configuration.yml
sed -i "s|issuer_private_key:.*|issuer_private_key:|" services/authelia/configuration.yml

echo "  ✓ Generated configuration.yml with domain: ${DOMAIN}"
echo "  ✓ OIDC secrets substituted"

echo "Done!"
