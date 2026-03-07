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

OAUTH_CLIENT_SECRET_DIGEST=$(docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --password ${OAUTH_CLIENT_SECRET} --no-confirm | sed -e "s|Digest: ||")

# Generate users_database.yml
echo "Generating users_database.yml..."
sed "s|\\\${AUTHELIA_ADMIN_EMAIL}|${AUTHELIA_ADMIN_EMAIL}|g" \
    services/authelia/users_database.yml.template \
    > services/authelia/users_database.yml

echo "  ✓ Generated users_database.yml with email: ${AUTHELIA_ADMIN_EMAIL}"

# Generate configuration.yml
echo "Generating configuration.yml..."
cat services/authelia/configuration.yml.template | \
    sed "s|\\\${DOMAIN}|${DOMAIN}|g" | \
    sed "s|\\\${SUBDOMAIN}|${SUBDOMAIN}|g" | \
    sed "s|\\\${OAUTH_CLIENT_SECRET_DIGEST}|${OAUTH_CLIENT_SECRET_DIGEST}|g" | \    
    sed "s|\\\${AUTHELIA_ADMIN_EMAIL}|${AUTHELIA_ADMIN_EMAIL}|g" | \
    sed "s|\\\${AUTHELIA_NOTIFIER_SMTP_USERNAME}|${AUTHELIA_SMTP_USERNAME}|g" | \
    sed "s|\\\${AUTHELIA_NOTIFIER_SMTP_PASSWORD}|${AUTHELIA_SMTP_PASSWORD}|g" | \
    sed "s|\\\${AUTHELIA_NOTIFIER_SMTP_SENDER}|${AUTHELIA_SMTP_SENDER}|g" \
    > services/authelia/configuration.yml

echo "  ✓ Generated configuration.yml with domain: ${DOMAIN}"

echo "Done!"
