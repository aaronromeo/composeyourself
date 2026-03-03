#!/bin/bash
# Generate configuration files from templates using .env variables

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env file if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set defaults if not defined
AUTHELIA_ADMIN_EMAIL="${AUTHELIA_ADMIN_EMAIL:-admin@example.com}"
# DOMAIN must be set in .env file - no default for security
if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN environment variable is not set"
    echo "Please set it in your .env file"
    exit 1
fi

# Generate users_database.yml
echo "Generating users_database.yml..."
sed "s|\\\${AUTHELIA_ADMIN_EMAIL}|${AUTHELIA_ADMIN_EMAIL}|g" \
    services/authelia/users_database.yml.template \
    > services/authelia/users_database.yml

echo "  ✓ Generated users_database.yml with email: ${AUTHELIA_ADMIN_EMAIL}"

# Generate configuration.yml
echo "Generating configuration.yml..."
sed "s|\\\${DOMAIN}|${DOMAIN}|g" \
    services/authelia/configuration.yml.template \
    > services/authelia/configuration.yml

echo "  ✓ Generated configuration.yml with domain: ${DOMAIN}"

echo "Done!"
