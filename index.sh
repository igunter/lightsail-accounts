#!/usr/bin/env bash
#
# Lightsail Accounts - admin menu for managing accounts on this Nginx server.
# See readme.md for usage.

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"

# Each account directory (/var/www/<username>) may contain a metadata file
# (.account) with KEY=VALUE lines: DOMAIN, ALT_DOMAINS, SSL, STATUS, CREATED.
read_account_meta() {
    local account_dir="$1"
    local meta_path="${account_dir}/${ACCOUNT_META_FILE}"

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

list_accounts() {
    if [ ! -d "$BASE_DIR" ]; then
        echo "Base directory ${BASE_DIR} does not exist."
        return
    fi

    local accounts=()
    for entry in "$BASE_DIR"/*/; do
        [ -d "$entry" ] || continue
        local name
        name="$(basename "$entry")"
        # Directories starting with "_" (e.g. _deactivated) are shared
        # internal assets, not accounts - skip them.
        [[ "$name" == _* ]] && continue
        accounts+=("$name")
    done

    if [ ${#accounts[@]} -eq 0 ]; then
        echo "No accounts found in ${BASE_DIR}."
        return
    fi

    printf "%-20s %-45s %-6s %-10s\n" "USERNAME" "DOMAIN" "SSL" "STATUS"
    printf "%-20s %-45s %-6s %-10s\n" "--------" "------" "---" "------"

    for username in "${accounts[@]}"; do
        read_account_meta "${BASE_DIR}/${username}"
        local domains_display="$DOMAIN"
        if [ -n "$ALT_DOMAINS" ]; then
            domains_display="${DOMAIN}, ${ALT_DOMAINS// /, }"
        fi
        printf "%-20s %-45s %-6s %-10s\n" "$username" "$domains_display" "$SSL" "$STATUS"
    done
}

create_account() {
    local create_script
    create_script="$(dirname "$0")/create.sh"

    if [ ! -f "$create_script" ]; then
        echo "create.sh not found next to index.sh."
        return
    fi

    bash "$create_script"
}

deactivate_account() {
    local deactivate_script
    deactivate_script="$(dirname "$0")/deactivate.sh"

    if [ ! -f "$deactivate_script" ]; then
        echo "deactivate.sh not found next to index.sh."
        return
    fi

    bash "$deactivate_script"
}

reactivate_account() {
    local reactivate_script
    reactivate_script="$(dirname "$0")/reactivate.sh"

    if [ ! -f "$reactivate_script" ]; then
        echo "reactivate.sh not found next to index.sh."
        return
    fi

    bash "$reactivate_script"
}

delete_account() {
    local delete_script
    delete_script="$(dirname "$0")/delete.sh"

    if [ ! -f "$delete_script" ]; then
        echo "delete.sh not found next to index.sh."
        return
    fi

    bash "$delete_script"
}

enable_ssl() {
    local enable_ssl_script
    enable_ssl_script="$(dirname "$0")/enable-ssl.sh"

    if [ ! -f "$enable_ssl_script" ]; then
        echo "enable-ssl.sh not found next to index.sh."
        return
    fi

    bash "$enable_ssl_script"
}

add_domain() {
    local add_domain_script
    add_domain_script="$(dirname "$0")/add-domain.sh"

    if [ ! -f "$add_domain_script" ]; then
        echo "add-domain.sh not found next to index.sh."
        return
    fi

    bash "$add_domain_script"
}

remove_domain() {
    local remove_domain_script
    remove_domain_script="$(dirname "$0")/remove-domain.sh"

    if [ ! -f "$remove_domain_script" ]; then
        echo "remove-domain.sh not found next to index.sh."
        return
    fi

    bash "$remove_domain_script"
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash index.sh)."
        exit 1
    fi
}

show_menu() {
    echo ""
    echo "===== Lightsail Accounts ====="
    echo "1) List Accounts"
    echo "2) Create Account"
    echo "3) Deactivate Account"
    echo "4) Reactivate Account"
    echo "5) Delete Account"
    echo "6) Enable SSL"
    echo "7) Add Domain"
    echo "8) Remove Domain"
    echo "9) Exit"
    echo "==============================="
}

main() {
    require_root

    while true; do
        show_menu
        read -rp "Select an option [1-9]: " choice
        echo ""

        case "$choice" in
            1) list_accounts ;;
            2) create_account ;;
            3) deactivate_account ;;
            4) reactivate_account ;;
            5) delete_account ;;
            6) enable_ssl ;;
            7) add_domain ;;
            8) remove_domain ;;
            9) echo "Goodbye."; exit 0 ;;
            *) echo "Invalid option, please select 1-9." ;;
        esac
    done
}

main
