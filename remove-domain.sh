#!/usr/bin/env bash
#
# Lightsail Accounts - remove an extra domain from an existing account.
#
# Only domains tracked in ALT_DOMAINS (added via add-domain.sh) can be
# removed here - the account's primary DOMAIN (set at create time) can't be,
# since the vhost file, .account metadata and SSL cert are all keyed off it.
# To retire the primary domain, use add-domain.sh to add its replacement
# first, then delete and recreate the account once traffic has moved.
#
# Usage: sudo bash remove-domain.sh
# Can be run directly, or is invoked by index.sh's "Remove Domain" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
NGINX_CONF_D="/etc/nginx/conf.d"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash remove-domain.sh)."
        exit 1
    fi
}

read_account_meta() {
    local meta_path="${BASE_DIR}/${USERNAME}/${ACCOUNT_META_FILE}"

    DOMAIN="-"
    ALT_DOMAINS=""
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
ALT_DOMAINS="${ALT_DOMAINS}"
SSL="${SSL}"
STATUS="${STATUS}"
CREATED="${CREATED}"
EOF
    chown admin:www-data "$meta_path" 2>/dev/null || true
}

prompt_username() {
    while true; do
        read -rp "Username to remove a domain from: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi
        if [ ! -f "${NGINX_CONF_D}/${USERNAME}.conf" ]; then
            echo "No nginx vhost found at ${NGINX_CONF_D}/${USERNAME}.conf."
            continue
        fi

        read_account_meta
        if [ -z "$ALT_DOMAINS" ]; then
            echo "Account '${USERNAME}' has no extra domains to remove (only its primary domain, ${DOMAIN})."
            continue
        fi
        break
    done
}

prompt_remove_domain() {
    while true; do
        echo "Extra domains on '${USERNAME}': ${ALT_DOMAINS}"
        read -rp "Domain to remove: " REMOVE_DOMAIN
        if [ "$REMOVE_DOMAIN" = "$DOMAIN" ]; then
            echo "'${DOMAIN}' is the primary domain and can't be removed here (see add-domain.sh header for why)."
            continue
        fi
        if [[ ! " $ALT_DOMAINS " == *" $REMOVE_DOMAIN "* ]]; then
            echo "'${REMOVE_DOMAIN}' is not one of this account's extra domains."
            continue
        fi
        break
    done
}

compute_remaining_domains() {
    REMAINING_ALT_DOMAINS=""
    local d
    for d in $ALT_DOMAINS; do
        [ "$d" = "$REMOVE_DOMAIN" ] && continue
        REMAINING_ALT_DOMAINS="${REMAINING_ALT_DOMAINS} ${d}"
    done
    REMAINING_ALT_DOMAINS="$(echo "$REMAINING_ALT_DOMAINS" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
}

update_vhost_server_name() {
    local vhost_path="${NGINX_CONF_D}/${USERNAME}.conf"
    VHOST_BACKUP="${vhost_path}.bak-$(date +%s)"
    cp "$vhost_path" "$VHOST_BACKUP"

    local all_domains
    all_domains="$(echo "${DOMAIN} ${REMAINING_ALT_DOMAINS}" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"

    if ! sed -i -E "s/^[[:space:]]*server_name[[:space:]]+.*;/    server_name ${all_domains};/" "$vhost_path"; then
        echo "Failed to update server_name in ${vhost_path}."
        rm -f "$VHOST_BACKUP"
        exit 1
    fi
    if ! grep -qF "server_name ${all_domains};" "$vhost_path"; then
        echo "Could not find a server_name line to update in ${vhost_path} - reverting. Remove ${REMOVE_DOMAIN} manually."
        cp "$VHOST_BACKUP" "$vhost_path"
        rm -f "$VHOST_BACKUP"
        exit 1
    fi
}

revert_vhost() {
    if [ -n "${VHOST_BACKUP:-}" ] && [ -f "$VHOST_BACKUP" ]; then
        cp "$VHOST_BACKUP" "${NGINX_CONF_D}/${USERNAME}.conf"
        reload_nginx
    fi
}

reload_nginx() {
    if command -v nginx &>/dev/null; then
        if nginx -t &>/dev/null; then
            systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
        else
            echo "nginx config test failed for ${NGINX_CONF_D}/${USERNAME}.conf - check it manually."
            return 1
        fi
    fi
}

shrink_ssl_cert() {
    if [ "$SSL" != "yes" ]; then
        return
    fi
    if ! command -v certbot &>/dev/null; then
        echo "certbot is not installed - server_name was updated, but the SSL certificate for ${DOMAIN} still lists ${REMOVE_DOMAIN}. Remove it from the cert manually."
        return
    fi

    local -a certbot_args=(--nginx --cert-name "$DOMAIN" --expand --non-interactive --agree-tos --redirect --no-eff-email --register-unsafely-without-email)
    local d
    for d in $DOMAIN $REMAINING_ALT_DOMAINS; do
        certbot_args+=(-d "$d")
    done

    echo "Reissuing SSL certificate for ${DOMAIN} without ${REMOVE_DOMAIN}..."
    if ! certbot "${certbot_args[@]}"; then
        echo "certbot failed to reissue the certificate without ${REMOVE_DOMAIN} - reverting the vhost change."
        revert_vhost
        exit 1
    fi
}

remove_domain() {
    require_root
    prompt_username
    prompt_remove_domain
    compute_remaining_domains

    update_vhost_server_name
    if ! reload_nginx; then
        revert_vhost
        exit 1
    fi

    shrink_ssl_cert

    ALT_DOMAINS="$REMAINING_ALT_DOMAINS"
    write_account_meta

    echo ""
    echo "Domain '${REMOVE_DOMAIN}' removed from '${USERNAME}'."
    echo "  Primary domain: ${DOMAIN}"
    if [ -n "$ALT_DOMAINS" ]; then
        echo "  Remaining extra domains: ${ALT_DOMAINS}"
    else
        echo "  No extra domains remain."
    fi
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    remove_domain
fi
