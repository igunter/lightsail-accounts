#!/usr/bin/env bash
#
# Lightsail Accounts - reactivate a deactivated account.
#
# Removes the %%HOME%%/.deactivated sentinel file (see deactivate.sh /
# nginx-vhost.template), unlocks the account's Linux login, and sets
# STATUS=active in its .account metadata file.
#
# Usage: sudo bash reactivate.sh
# Can be run directly, or is invoked by index.sh's "Reactivate Account" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
DEACTIVATED_FLAG_FILE=".deactivated"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash reactivate.sh)."
        exit 1
    fi
}

prompt_username() {
    while true; do
        read -rp "Username to reactivate: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi
        if [ ! -f "${BASE_DIR}/${USERNAME}/${DEACTIVATED_FLAG_FILE}" ]; then
            echo "Account '${USERNAME}' is not deactivated."
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
STATUS="active"
CREATED="${CREATED}"
EOF
    chown admin:www-data "$meta_path" 2>/dev/null || true
}

unlock_system_user() {
    if id "$USERNAME" &>/dev/null; then
        usermod -U "$USERNAME"
    else
        echo "No system user '${USERNAME}' found - skipping login unlock."
    fi
}

reactivate_account() {
    require_root
    prompt_username
    read_account_meta

    rm -f "${BASE_DIR}/${USERNAME}/${DEACTIVATED_FLAG_FILE}"
    unlock_system_user
    write_account_meta

    echo ""
    echo "Account '${USERNAME}' reactivated."
    echo "  Domain: ${DOMAIN}"
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    reactivate_account
fi
