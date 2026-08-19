#!/usr/bin/env bash
#
# Lightsail Accounts - permanently delete a deactivated account.
#
# Only works on accounts that are currently deactivated (see deactivate.sh) -
# this is a deliberate guardrail so an account can't be deleted while it's
# still serving live traffic. Before deleting anything it:
#   - archives /var/www/<username> to a .tar.gz under BACKUP_DIR
#   - removes the nginx vhost (and any patch_legacy_vhost backups)
#   - queues the SSL certificate for deletion 28 days from now, instead of
#     revoking it immediately, in case the domain gets reused before then
#     (see cleanup-certs.sh)
#   - deletes the Linux system user and its home directory
#
# Usage: sudo bash delete.sh
# Can be run directly, or is invoked by index.sh's "Delete Account" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
DEACTIVATED_FLAG_FILE=".deactivated"
NGINX_CONF_D="/etc/nginx/conf.d"
BACKUP_DIR="/var/backups/lightsail-accounts"
CERT_QUEUE_DIR="/etc/lightsail-accounts/cert-cleanup-queue"
CERT_GRACE_DAYS=28

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash delete.sh)."
        exit 1
    fi
}

prompt_username() {
    while true; do
        read -rp "Username to delete: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi
        if [ ! -f "${BASE_DIR}/${USERNAME}/${DEACTIVATED_FLAG_FILE}" ]; then
            echo "Account '${USERNAME}' is not deactivated. Deactivate it first (option 3) before deleting."
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

confirm_deletion() {
    echo ""
    echo "About to permanently delete account '${USERNAME}':"
    echo "  Domain:  ${DOMAIN}"
    echo "  Home:    ${BASE_DIR}/${USERNAME}"
    echo "  SSL:     ${SSL}"
    echo ""
    echo "This will archive and remove the Linux user, its home directory, and its nginx vhost."
    read -rp "Type '${USERNAME}' to confirm permanent deletion: " confirm_input
    if [ "$confirm_input" != "$USERNAME" ]; then
        echo "Confirmation did not match. Aborting - nothing was deleted."
        return 1
    fi
}

backup_account() {
    mkdir -p "$BACKUP_DIR"
    local backup_path="${BACKUP_DIR}/${USERNAME}-$(date +%Y%m%d%H%M%S).tar.gz"
    tar -czf "$backup_path" -C "$BASE_DIR" "$USERNAME"
    echo "Backed up account files to ${backup_path}."
}

remove_nginx_vhost() {
    local vhost_path="${NGINX_CONF_D}/${USERNAME}.conf"

    rm -f "$vhost_path" "${vhost_path}".bak-*

    if command -v nginx &>/dev/null; then
        if nginx -t &>/dev/null; then
            systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
        else
            echo "nginx config test failed after removing ${vhost_path} - check the nginx config manually."
        fi
    fi
}

queue_cert_cleanup() {
    if [ "$SSL" != "yes" ] || [ "$DOMAIN" = "-" ]; then
        return
    fi
    if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
        return
    fi

    mkdir -p "$CERT_QUEUE_DIR"
    local eligible_date
    eligible_date="$(date -d "+${CERT_GRACE_DAYS} days" +%F)"
    echo "$eligible_date" > "${CERT_QUEUE_DIR}/${DOMAIN}"
    echo "SSL certificate for ${DOMAIN} will be auto-deleted on ${eligible_date} (${CERT_GRACE_DAYS} days) if the domain isn't back in use by then - see cleanup-certs.sh."
}

delete_system_user() {
    if id "$USERNAME" &>/dev/null; then
        if ! userdel -r "$USERNAME"; then
            echo "userdel failed (see error above) - remove the account manually: sudo userdel -r ${USERNAME}"
            return 1
        fi
    fi
}

delete_account() {
    require_root
    prompt_username
    read_account_meta

    if ! confirm_deletion; then
        return
    fi

    backup_account
    remove_nginx_vhost
    queue_cert_cleanup

    echo ""
    if delete_system_user; then
        echo "Account '${USERNAME}' deleted."
    else
        echo "Account '${USERNAME}' NOT fully deleted - the Linux user/home directory still exist. Its nginx vhost was removed and its files were backed up, but you must remove the system user manually (see above)."
        return 1
    fi
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    delete_account
fi
