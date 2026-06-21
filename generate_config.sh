#!/bin/bash
# Generate configuration files from templates using .env variables
#
# Called by deploy.sh (first deploy) and update.sh (subsequent updates).
#
# Behavior:
#   - configuration.yml: Always regenerated from template (safe to overwrite)
#   - users_database.yml: Only generated on FIRST deploy. Skipped on updates
#     to preserve password changes made on the server.
#   - OIDC keys: Always regenerated (Authelia handles key rotation)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    echo -e "${RED}Error: DOMAIN environment variable is not set${NC}"
    echo "Please set it in your .env file"
    exit 1
fi

# --- Authelia (only on hosts that run it, i.e. OAUTH_CLIENT_SECRET is set) ---
if [ -z "${OAUTH_CLIENT_SECRET}" ]; then
    echo -e "${GREEN}  ✓ OAUTH_CLIENT_SECRET not set — skipping Authelia config (not needed on this host)${NC}"
else
    # --- OIDC Keys ---
    echo -e "${YELLOW}Generating OIDC keys...${NC}"
    sudo rm -rf services/authelia/keys 2> /dev/null
    mkdir -p services/authelia/keys
    openssl genrsa -out services/authelia/keys/private.pem 2048
    openssl rsa -in services/authelia/keys/private.pem -outform PEM -pubout -out services/authelia/keys/public.pem
    cat services/authelia/keys/private.pem | sed '/----/d' | tr -d '\n' > services/authelia/keys/private.b64

    # --- OIDC Client Secret Hash ---
    OAUTH_CLIENT_SECRET_DIGEST=$(docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 --password "${OAUTH_CLIENT_SECRET}" --no-confirm | sed -e "s|Digest: ||")
    export OAUTH_CLIENT_SECRET_DIGEST

    # --- Users Database ---
    if [ -f services/authelia/users_database.yml ]; then
        echo -e "${GREEN}  ✓ users_database.yml already exists, skipping (preserving existing passwords)${NC}"
    else
        echo -e "${YELLOW}Generating users_database.yml (first-time setup)...${NC}"

        # Get the admin password - from env var or interactive prompt
        if [ -n "$AUTHELIA_ADMIN_PASSWORD" ]; then
            ADMIN_PASSWORD="$AUTHELIA_ADMIN_PASSWORD"
            echo "  Using admin password from AUTHELIA_ADMIN_PASSWORD environment variable"
        else
            # Interactive prompt - only works when called from a terminal
            if [ -t 0 ]; then
                echo ""
                echo -e "${YELLOW}  Set the initial admin password for Authelia.${NC}"
                echo "  (Minimum 8 characters, must include uppercase, lowercase, number, and special character)"
                echo ""
                while true; do
                    read -s -p "  Enter admin password: " ADMIN_PASSWORD
                    echo ""
                    read -s -p "  Confirm admin password: " ADMIN_PASSWORD_CONFIRM
                    echo ""
                    if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ]; then
                        if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
                            break
                        else
                            echo -e "${RED}  Password must be at least 8 characters. Try again.${NC}"
                        fi
                    else
                        echo -e "${RED}  Passwords do not match. Try again.${NC}"
                    fi
                done
            else
                echo -e "${RED}Error: No terminal available for password input and AUTHELIA_ADMIN_PASSWORD is not set.${NC}"
                echo "Set AUTHELIA_ADMIN_PASSWORD in your environment or .env file for non-interactive use."
                exit 1
            fi
        fi

        # Hash the password using Authelia's built-in tool
        echo "  Hashing admin password..."
        ADMIN_PASSWORD_HASH=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "${ADMIN_PASSWORD}" --no-confirm | sed -e "s|Digest: ||")

        if [ -z "$ADMIN_PASSWORD_HASH" ] || [ "$ADMIN_PASSWORD_HASH" = "" ]; then
            echo -e "${RED}Error: Failed to generate password hash${NC}"
            exit 1
        fi

        # Substitute placeholders into the template
        sed -e "s|\${AUTHELIA_ADMIN_EMAIL}|${AUTHELIA_ADMIN_EMAIL}|g" \
            -e "s|\${ADMIN_PASSWORD_HASH}|${ADMIN_PASSWORD_HASH}|g" \
            services/authelia/users_database.yml.template \
            > services/authelia/users_database.yml

        # Restrict permissions - file contains password hashes
        chmod 600 services/authelia/users_database.yml

        echo -e "${GREEN}  ✓ Generated users_database.yml with email: ${AUTHELIA_ADMIN_EMAIL}${NC}"

        # Clear sensitive variables
        unset ADMIN_PASSWORD ADMIN_PASSWORD_CONFIRM ADMIN_PASSWORD_HASH
    fi

    # --- Configuration ---
    echo "Generating configuration.yml..."
    envsubst '$DOMAIN $SUBDOMAIN $OAUTH_CLIENT_SECRET_DIGEST $AUTHELIA_ADMIN_EMAIL $AUTHELIA_SMTP_USERNAME $AUTHELIA_SMTP_PASSWORD $AUTHELIA_SMTP_SENDER $AUTHELIA_NOTIFIER_SMTP_SENDER' \
      < services/authelia/configuration.yml.template \
      > services/authelia/configuration.yml

    echo -e "${GREEN}  ✓ Generated configuration.yml with domain: ${DOMAIN}${NC}"
fi

# --- OpenWebUI default model seed ---
# Copy the committed config.json into the bind-mounted data dir so OWUI imports
# it on next boot, re-asserting the declared default model.
#
# Why re-copy every deploy:
#   OWUI renames config.json -> old_config.json after importing it, so the file
#   is consumed. Re-copying on each deploy means the default model is always
#   reset to the value declared in services/agenticui-config/config.json, which
#   is the "strictly declarative" behaviour we want.
#
# NOTE: This only controls `ui.default_models` (and any other keys present in
#   config.json). All other admin-panel settings continue to persist in webui.db
#   across restarts (ENABLE_PERSISTENT_CONFIG defaults to true).
#
# PersistentConfig gotcha: DEFAULT_MODELS env var is only read on FIRST boot;
#   after that the DB wins. This file-based seed re-applies the default on every
#   deploy regardless of prior DB state — the env var alone is not enough.
echo -e "${YELLOW}Seeding OpenWebUI default model config...${NC}"
mkdir -p services/agenticui
cp services/agenticui-config/config.json services/agenticui/config.json
echo -e "${GREEN}  ✓ Copied agenticui-config/config.json -> services/agenticui/config.json${NC}"

echo -e "${GREEN}Done!${NC}"
