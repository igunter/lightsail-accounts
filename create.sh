#!/usr/bin/env bash
#
# Lightsail Accounts - create a new account.
#
# Creates a Linux system user, a webroot under /var/www/<username>, an nginx
# vhost for the given domain, optionally issues an SSL cert via certbot, and
# writes a .account metadata file (see account.template).
#
# Usage: sudo bash create.sh
# Can be run directly, or is invoked by index.sh's "Create Account" option.

set -euo pipefail

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"
NGINX_CONF_D="/etc/nginx/conf.d"
PHP_SOCK_GLOB="/run/php/php*-fpm.sock"
TEMPLATE_FILE="$(dirname "$0")/nginx-vhost.template"
DEACTIVATED_ROOT="/var/www/_deactivated"
DEACTIVATED_PAGE_TEMPLATE="$(dirname "$0")/deactivated-page.template"
PLACEHOLDER_PAGE_TEMPLATE="$(dirname "$0")/placeholder-page.template"

USERNAME_RE='^[a-z][a-z0-9_-]{2,31}$'
DOMAIN_RE='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash create.sh)."
        exit 1
    fi
}

prompt_username() {
    while true; do
        read -rp "Username: " USERNAME
        if [[ ! "$USERNAME" =~ $USERNAME_RE ]]; then
            echo "Invalid username. Use lowercase letters, digits, - or _, 3-32 chars, starting with a letter."
            continue
        fi
        if id "$USERNAME" &>/dev/null; then
            echo "A system user named '${USERNAME}' already exists. Choose another."
            continue
        fi
        if [ -e "${BASE_DIR}/${USERNAME}" ]; then
            echo "${BASE_DIR}/${USERNAME} already exists. Choose another username."
            continue
        fi
        break
    done
}

prompt_password() {
    while true; do
        read -rsp "Password: " PASSWORD
        echo ""
        if [ "${#PASSWORD}" -lt 8 ]; then
            echo "Password must be at least 8 characters."
            continue
        fi
        read -rsp "Confirm password: " PASSWORD_CONFIRM
        echo ""
        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            echo "Passwords do not match."
            continue
        fi
        break
    done
}

prompt_domain() {
    while true; do
        read -rp "Domain name (e.g. example.com): " DOMAIN
        if [[ ! "$DOMAIN" =~ $DOMAIN_RE ]]; then
            echo "Invalid domain name."
            continue
        fi
        break
    done
}

prompt_ssl() {
    while true; do
        read -rp "SSL required? [y/N]: " ssl_choice
        case "${ssl_choice,,}" in
            y|yes) SSL="yes"; break ;;
            n|no|"") SSL="no"; break ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

create_system_user() {
    local webroot="${BASE_DIR}/${USERNAME}"
    echo "Creating system user '${USERNAME}'..."
    useradd -m -d "$webroot" -s /usr/sbin/nologin "$USERNAME"
    echo "${USERNAME}:${PASSWORD}" | chpasswd
    mkdir -p "${webroot}/public"

    # useradd's default home dir mode can be as restrictive as 700, which
    # blocks nginx/php-fpm (running as a different user) from traversing in.
    # 711 on the home dir allows traversal without listing; 755 on public/
    # makes the actual served content readable.
    chmod 711 "$webroot"
    chmod -R 755 "${webroot}/public"

    seed_placeholder_page "$webroot"
}

seed_placeholder_page() {
    local webroot="$1"
    local index_path="${webroot}/public/index.html"

    if [ -e "$index_path" ] || [ -e "${webroot}/public/index.php" ]; then
        return
    fi
    if [ ! -f "$PLACEHOLDER_PAGE_TEMPLATE" ]; then
        return
    fi

    cp "$PLACEHOLDER_PAGE_TEMPLATE" "$index_path"
    chmod 644 "$index_path"
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

detect_php_sock() {
    local sock
    for sock in $PHP_SOCK_GLOB; do
        if [ -S "$sock" ]; then
            echo "$sock"
            return 0
        fi
    done
    return 1
}

create_nginx_vhost() {
    local home="${BASE_DIR}/${USERNAME}"
    local webroot="${home}/public"

    ensure_deactivated_page

    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "nginx vhost template not found: ${TEMPLATE_FILE}. Skipping vhost setup."
        return 1
    fi
    if [ ! -d "$NGINX_CONF_D" ]; then
        echo "${NGINX_CONF_D} not found (is nginx installed?). Skipping vhost setup."
        return 1
    fi

    local vhost_path="${NGINX_CONF_D}/${USERNAME}.conf"
    if [ -e "$vhost_path" ]; then
        echo "nginx vhost ${vhost_path} already exists. Skipping vhost setup."
        return 1
    fi

    local php_sock
    if ! php_sock="$(detect_php_sock)"; then
        echo "No php-fpm socket found matching ${PHP_SOCK_GLOB}. Skipping vhost setup - install/start php-fpm and create the vhost manually."
        return 1
    fi

    echo "Creating nginx vhost for ${DOMAIN} (php-fpm socket: ${php_sock})..."
    local content
    content="$(cat "$TEMPLATE_FILE")"
    content="${content//%%DOMAIN%%/$DOMAIN}"
    content="${content//%%WEBROOT%%/$webroot}"
    content="${content//%%PHP_SOCK%%/$php_sock}"
    content="${content//%%HOME%%/$home}"
    content="${content//%%DEACTIVATED_ROOT%%/$DEACTIVATED_ROOT}"
    printf '%s\n' "$content" > "$vhost_path"

    if command -v nginx &>/dev/null; then
        if nginx -t &>/dev/null; then
            systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
        else
            echo "nginx config test failed after adding ${DOMAIN}. Check ${vhost_path} manually."
            return 1
        fi
    fi
}

issue_ssl_cert() {
    if [ "$SSL" != "yes" ]; then
        return
    fi

    if ! command -v certbot &>/dev/null; then
        echo "certbot is not installed. Skipping SSL issuance for ${DOMAIN} - install certbot and run it manually."
        SSL="no"
        return
    fi

    echo "Requesting SSL certificate for ${DOMAIN} via certbot..."
    if ! certbot --nginx -d "$DOMAIN" \
        --non-interactive --agree-tos --redirect --no-eff-email \
        --register-unsafely-without-email; then
        echo "certbot failed for ${DOMAIN}. SSL was not enabled - retry manually later."
        SSL="no"
    fi
}

write_account_meta() {
    local meta_path="${BASE_DIR}/${USERNAME}/${ACCOUNT_META_FILE}"
    cat > "$meta_path" <<EOF
DOMAIN="${DOMAIN}"
SSL="${SSL}"
STATUS="active"
CREATED="$(date +%F)"
EOF
}

create_account() {
    require_root
    prompt_username
    prompt_password
    prompt_domain
    prompt_ssl

    create_system_user
    local vhost_created="yes"
    create_nginx_vhost || vhost_created="no"
    if [ "$vhost_created" = "yes" ]; then
        issue_ssl_cert
    else
        SSL="no"
    fi
    write_account_meta
    chown -R admin:www-data "${BASE_DIR}/${USERNAME}"

    echo ""
    echo "Account '${USERNAME}' created."
    echo "  Home:    ${BASE_DIR}/${USERNAME}"
    echo "  Webroot: ${BASE_DIR}/${USERNAME}/public"
    echo "  Domain:  ${DOMAIN}"
    echo "  SSL:     ${SSL}"
    if [ "$vhost_created" = "no" ]; then
        echo ""
        echo "WARNING: the nginx vhost was NOT created (see message above) - ${DOMAIN} is not being served yet. Fix the issue and create ${NGINX_CONF_D}/${USERNAME}.conf manually, or remove and re-run this script."
    fi
}

# Allow this script to be sourced (e.g. by index.sh) without auto-running.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_account
fi
