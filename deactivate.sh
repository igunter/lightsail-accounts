#!/usr/bin/env bash
#
# Lightsail Accounts - deactivate an account.
#
# Creates a %%HOME%%/.deactivated sentinel file that the account's nginx
# vhost (see nginx-vhost.template) checks on every request, returning 503
# and serving the shared "Account Deactivated" page instead of the site. No
# nginx config edit or reload is needed, so this never touches the
# ssl_certificate lines certbot injected into the vhost file. Also locks the
# account's Linux login and sets STATUS=deactivated in its .account
# metadata file.
#
# Usage: sudo bash deactivate.sh
# Can be run directly, or is invoked by index.sh's "Deactivate Account" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
DEACTIVATED_FLAG_FILE=".deactivated"
DEACTIVATED_ROOT="/var/www/_deactivated"
DEACTIVATED_PAGE_TEMPLATE="$(dirname "$0")/deactivated-page.template"
NGINX_CONF_D="/etc/nginx/conf.d"
DEACTIVATE_MARKER="# lightsail-accounts: deactivate check (managed - do not remove)"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash deactivate.sh)."
        exit 1
    fi
}

prompt_username() {
    while true; do
        read -rp "Username to deactivate: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi
        if [ -f "${BASE_DIR}/${USERNAME}/${DEACTIVATED_FLAG_FILE}" ]; then
            echo "Account '${USERNAME}' is already deactivated."
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
STATUS="deactivated"
CREATED="${CREATED}"
EOF
    chown "${USERNAME}:${USERNAME}" "$meta_path" 2>/dev/null || true
}

ensure_deactivated_page() {
    if [ -f "${DEACTIVATED_ROOT}/index.html" ]; then
        return
    fi
    if [ ! -f "$DEACTIVATED_PAGE_TEMPLATE" ]; then
        echo "Deactivated-page template not found: ${DEACTIVATED_PAGE_TEMPLATE}. Skipping."
        return
    fi
    mkdir -p "$DEACTIVATED_ROOT"
    cp "$DEACTIVATED_PAGE_TEMPLATE" "${DEACTIVATED_ROOT}/index.html"
    chmod 755 "$DEACTIVATED_ROOT"
    chmod 644 "${DEACTIVATED_ROOT}/index.html"
}

# Vhosts written by create.sh already contain the deactivate check (marked by
# DEACTIVATE_MARKER). Vhosts that predate this feature, or were created by
# hand, don't - this inserts the check into an existing vhost so
# deactivating an older account actually takes effect. It only ever inserts
# new lines right after the first "server {" and never rewrites existing
# lines, so any ssl_certificate directives certbot already added are left
# untouched.
patch_legacy_vhost() {
    local home="${BASE_DIR}/${USERNAME}"
    local vhost_path="${NGINX_CONF_D}/${USERNAME}.conf"

    if [ ! -f "$vhost_path" ]; then
        echo "No nginx vhost found at ${vhost_path} - deactivate will lock the login and update metadata, but can't redirect web traffic."
        return
    fi
    if grep -qF "$DEACTIVATE_MARKER" "$vhost_path"; then
        return
    fi

    echo "Vhost ${vhost_path} predates deactivate support - patching it in."
    local backup_path="${vhost_path}.bak-$(date +%s)"
    cp "$vhost_path" "$backup_path"

    local snippet
    snippet=$(cat <<EOF
    ${DEACTIVATE_MARKER}
    if (-f "${home}/${DEACTIVATED_FLAG_FILE}") {
        return 503;
    }
    error_page 503 @deactivated;
    location @deactivated {
        root ${DEACTIVATED_ROOT};
        rewrite ^ /index.html break;
    }
EOF
)

    local tmp_path
    tmp_path="$(mktemp)"
    if ! awk -v ins="$snippet" '
        !done && /^[[:space:]]*server[[:space:]]*\{/ { print; print ins; done=1; next }
        { print } END { exit !done }
    ' "$vhost_path" > "$tmp_path"; then
        echo "Could not find a \"server {\" line in ${vhost_path} - leaving it untouched. Add the deactivate check manually."
        rm -f "$tmp_path" "$backup_path"
        return
    fi

    mv "$tmp_path" "$vhost_path"

    if command -v nginx &>/dev/null; then
        if nginx -t &>/dev/null; then
            systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
            echo "Patched and reloaded nginx (backup saved at ${backup_path})."
        else
            echo "nginx config test failed after patching ${vhost_path} - reverting from backup."
            cp "$backup_path" "$vhost_path"
        fi
    fi
}

lock_system_user() {
    if id "$USERNAME" &>/dev/null; then
        usermod -L "$USERNAME"
    else
        echo "No system user '${USERNAME}' found - skipping login lock."
    fi
}

deactivate_account() {
    require_root
    prompt_username
    read_account_meta

    ensure_deactivated_page
    patch_legacy_vhost
    touch "${BASE_DIR}/${USERNAME}/${DEACTIVATED_FLAG_FILE}"
    lock_system_user
    write_account_meta

    echo ""
    echo "Account '${USERNAME}' deactivated."
    echo "  Domain:  ${DOMAIN}"
    echo "  Visitors to ${DOMAIN} will now see the Account Deactivated page (HTTP 503)."
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deactivate_account
fi
