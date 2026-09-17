#!/usr/bin/env bash
#
# Lightsail Accounts - enable SSL for an existing account that was created
# without it (or whose earlier certbot request failed).
#
# Requests a certificate via certbot for the account's domain, lets certbot
# wire up the ssl_certificate directives and HTTP->HTTPS redirect in the
# account's nginx vhost, and sets SSL="yes" in its .account metadata file.
#
# Usage: sudo bash enable-ssl.sh
# Can be run directly, or is invoked by index.sh's "Enable SSL" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
NGINX_CONF_D="/etc/nginx/conf.d"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash enable-ssl.sh)."
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

prompt_username() {
    while true; do
        read -rp "Username to enable SSL for: " USERNAME
        if [ ! -d "${BASE_DIR}/${USERNAME}" ]; then
            echo "No account found at ${BASE_DIR}/${USERNAME}."
            continue
        fi

        read_account_meta

        if [ "$DOMAIN" = "-" ]; then
            echo "Account '${USERNAME}' has no DOMAIN set in its .account file - fix that first."
            continue
        fi
        if [ "$SSL" = "yes" ]; then
            echo "Account '${USERNAME}' already has SSL=yes."
            continue
        fi
        if [ ! -f "${NGINX_CONF_D}/${USERNAME}.conf" ]; then
            echo "No nginx vhost found at ${NGINX_CONF_D}/${USERNAME}.conf - create it before requesting a certificate."
            continue
        fi
        break
    done
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

issue_ssl_cert() {
    if ! command -v certbot &>/dev/null; then
        echo "certbot is not installed. Install it and re-run this script."
        exit 1
    fi

    local -a certbot_args=(--nginx --non-interactive --agree-tos --redirect --no-eff-email --register-unsafely-without-email -d "$DOMAIN")
    local d
    for d in $ALT_DOMAINS; do
        certbot_args+=(-d "$d")
    done

    echo "Requesting SSL certificate for ${DOMAIN}${ALT_DOMAINS:+ (plus ${ALT_DOMAINS})} via certbot..."
    if ! certbot "${certbot_args[@]}"; then
        echo "certbot failed for ${DOMAIN}. SSL was not enabled - check DNS for the domain(s) points at this server and retry."
        exit 1
    fi
}

enable_ssl() {
    require_root
    prompt_username

    issue_ssl_cert
    SSL="yes"
    write_account_meta

    echo ""
    echo "SSL enabled for '${USERNAME}'."
    echo "  Domain: ${DOMAIN}"
    echo "  https://${DOMAIN} is now served over SSL, with HTTP redirecting to it."
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    enable_ssl
fi
