#!/usr/bin/env bash
#
# Lightsail Accounts - add an extra domain to an existing account.
#
# The account's original DOMAIN (set at create time) stays the primary
# hostname; extra domains are tracked space-separated in ALT_DOMAINS in
# .account. This rewrites the account's nginx vhost server_name line to
# include every domain, and - if the account has SSL - expands its
# certificate to cover the new domain too.
#
# Usage: sudo bash add-domain.sh
# Can be run directly, or is invoked by index.sh's "Add Domain" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
NGINX_CONF_D="/etc/nginx/conf.d"
DOMAIN_RE='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash add-domain.sh)."
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
        read -rp "Username to add a domain to: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi
        if [ ! -f "${NGINX_CONF_D}/${USERNAME}.conf" ]; then
            echo "No nginx vhost found at ${NGINX_CONF_D}/${USERNAME}.conf - create the account/vhost first."
            continue
        fi
        break
    done
}

# Checks whether $1 is already used in another account's vhost, so two
# accounts never end up claiming the same hostname.
domain_used_elsewhere() {
    local domain="$1"
    local vhost_path="${NGINX_CONF_D}/${USERNAME}.conf"
    local hit
    hit="$(grep -rlE "(^|[[:space:]])${domain}([[:space:]]|;)" "$NGINX_CONF_D" 2>/dev/null | grep -vF "$vhost_path" || true)"
    [ -n "$hit" ]
}

prompt_new_domain() {
    while true; do
        read -rp "Domain to add (e.g. www.example.com): " NEW_DOMAIN
        if [[ ! "$NEW_DOMAIN" =~ $DOMAIN_RE ]]; then
            echo "Invalid domain name."
            continue
        fi
        if [ "$NEW_DOMAIN" = "$DOMAIN" ] || [[ " $ALT_DOMAINS " == *" $NEW_DOMAIN "* ]]; then
            echo "'${NEW_DOMAIN}' is already on this account."
            continue
        fi
        if domain_used_elsewhere "$NEW_DOMAIN"; then
            echo "'${NEW_DOMAIN}' already appears in another account's nginx vhost. Choose a different domain."
            continue
        fi
        break
    done
}

update_vhost_server_name() {
    local vhost_path="${NGINX_CONF_D}/${USERNAME}.conf"
    VHOST_BACKUP="${vhost_path}.bak-$(date +%s)"
    cp "$vhost_path" "$VHOST_BACKUP"

    local all_domains="${DOMAIN} ${ALT_DOMAINS} ${NEW_DOMAIN}"
    all_domains="$(echo "$all_domains" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"

    if ! sed -i -E "s/^[[:space:]]*server_name[[:space:]]+.*;/    server_name ${all_domains};/" "$vhost_path"; then
        echo "Failed to update server_name in ${vhost_path}."
        rm -f "$VHOST_BACKUP"
        exit 1
    fi
    if ! grep -qF "server_name ${all_domains};" "$vhost_path"; then
        echo "Could not find a server_name line to update in ${vhost_path} - reverting. Add ${NEW_DOMAIN} manually."
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

expand_ssl_cert() {
    if [ "$SSL" != "yes" ]; then
        return
    fi
    if ! command -v certbot &>/dev/null; then
        echo "certbot is not installed - server_name was updated, but the SSL certificate for ${DOMAIN} does not cover ${NEW_DOMAIN} yet. Install certbot and expand it manually."
        return
    fi

    local -a certbot_args=(--nginx --cert-name "$DOMAIN" --expand --non-interactive --agree-tos --redirect --no-eff-email --register-unsafely-without-email)
    local d
    for d in $DOMAIN $ALT_DOMAINS $NEW_DOMAIN; do
        certbot_args+=(-d "$d")
    done

    echo "Expanding SSL certificate for ${DOMAIN} to include ${NEW_DOMAIN}..."
    if ! certbot "${certbot_args[@]}"; then
        echo "certbot failed to expand the certificate for ${NEW_DOMAIN} - reverting the vhost change. Check DNS for ${NEW_DOMAIN} points at this server and retry."
        revert_vhost
        exit 1
    fi
}

add_domain() {
    require_root
    prompt_username
    read_account_meta
    prompt_new_domain

    update_vhost_server_name
    if ! reload_nginx; then
        revert_vhost
        exit 1
    fi

    expand_ssl_cert

    ALT_DOMAINS="$(echo "${ALT_DOMAINS} ${NEW_DOMAIN}" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
    write_account_meta

    echo ""
    echo "Domain '${NEW_DOMAIN}' added to '${USERNAME}'."
    echo "  Primary domain: ${DOMAIN}"
    echo "  All domains:    ${DOMAIN} ${ALT_DOMAINS}"
    echo "  SSL:            ${SSL}"
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    add_domain
fi
