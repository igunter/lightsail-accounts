#!/usr/bin/env bash
#
# Lightsail Accounts - suspend an account.
#
# Creates a %%HOME%%/.suspended sentinel file that the account's nginx vhost
# (see nginx-vhost.template) checks on every request, returning 503 and
# serving the shared "Account Suspended" page instead of the site. No nginx
# config edit or reload is needed, so this never touches the ssl_certificate
# lines certbot injected into the vhost file. Also locks the account's Linux
# login and sets STATUS=suspended in its .account metadata file.
#
# Usage: sudo bash suspend.sh
# Can be run directly, or is invoked by index.sh's "Suspend Account" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
SUSPENDED_FLAG_FILE=".suspended"
SUSPENDED_ROOT="/var/www/_suspended"
SUSPENDED_PAGE_TEMPLATE="$(dirname "$0")/suspended-page.template"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash suspend.sh)."
        exit 1
    fi
}

prompt_username() {
    while true; do
        read -rp "Username to suspend: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi
        if [ -f "${BASE_DIR}/${USERNAME}/${SUSPENDED_FLAG_FILE}" ]; then
            echo "Account '${USERNAME}' is already suspended."
            continue
        fi
        break
    done
}

read_account_meta() {
    local meta_path="${BASE_DIR}/${USERNAME}/${ACCOUNT_META_FILE}"

    DOMAIN="-"
    SSL="-"
    STATUS="unknown"
    CREATED="-"

    if [ -f "$meta_path" ]; then
        # shellcheck disable=SC1090
        source "$meta_path"
    fi
}

write_account_meta() {
    local meta_path="${BASE_DIR}/${USERNAME}/${ACCOUNT_META_FILE}"
    cat > "$meta_path" <<EOF
DOMAIN="${DOMAIN}"
SSL="${SSL}"
STATUS="suspended"
CREATED="${CREATED}"
EOF
    chown "${USERNAME}:${USERNAME}" "$meta_path" 2>/dev/null || true
}

ensure_suspended_page() {
    if [ -f "${SUSPENDED_ROOT}/index.html" ]; then
        return
    fi
    if [ ! -f "$SUSPENDED_PAGE_TEMPLATE" ]; then
        echo "Suspended-page template not found: ${SUSPENDED_PAGE_TEMPLATE}. Skipping."
        return
    fi
    mkdir -p "$SUSPENDED_ROOT"
    cp "$SUSPENDED_PAGE_TEMPLATE" "${SUSPENDED_ROOT}/index.html"
}

lock_system_user() {
    if id "$USERNAME" &>/dev/null; then
        usermod -L "$USERNAME"
    else
        echo "No system user '${USERNAME}' found - skipping login lock."
    fi
}

suspend_account() {
    require_root
    prompt_username
    read_account_meta

    ensure_suspended_page
    touch "${BASE_DIR}/${USERNAME}/${SUSPENDED_FLAG_FILE}"
    lock_system_user
    write_account_meta

    echo ""
    echo "Account '${USERNAME}' suspended."
    echo "  Domain:  ${DOMAIN}"
    echo "  Visitors to ${DOMAIN} will now see the Account Suspended page (HTTP 503)."
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    suspend_account
fi
