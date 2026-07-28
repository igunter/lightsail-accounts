#!/usr/bin/env bash
#
# Lightsail Accounts - admin menu for managing accounts on this Nginx server.
# See readme.md for usage.

BASE_DIR="/var/www"
ACCOUNT_META_FILE=".account"

# Each account directory (/var/www/<username>) may contain a metadata file
# (.account) with KEY=VALUE lines: DOMAIN, SSL, STATUS, CREATED.
read_account_meta() {
    local account_dir="$1"
    local meta_path="${account_dir}/${ACCOUNT_META_FILE}"

    DOMAIN="-"
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
        accounts+=("$(basename "$entry")")
    done

    if [ ${#accounts[@]} -eq 0 ]; then
        echo "No accounts found in ${BASE_DIR}."
        return
    fi

    printf "%-20s %-30s %-6s %-10s\n" "USERNAME" "DOMAIN" "SSL" "STATUS"
    printf "%-20s %-30s %-6s %-10s\n" "--------" "------" "---" "------"

    for username in "${accounts[@]}"; do
        read_account_meta "${BASE_DIR}/${username}"
        printf "%-20s %-30s %-6s %-10s\n" "$username" "$DOMAIN" "$SSL" "$STATUS"
    done
}

create_account() {
    echo "Create Account: coming soon."
}

suspend_account() {
    echo "Suspend Account: coming soon."
}

delete_account() {
    echo "Delete Account: coming soon."
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
    echo "2) Create Account (Coming Soon)"
    echo "3) Suspend Account (Coming Soon)"
    echo "4) Delete Account (Coming Soon)"
    echo "5) Exit"
    echo "==============================="
}

main() {
    require_root

    while true; do
        show_menu
        read -rp "Select an option [1-5]: " choice
        echo ""

        case "$choice" in
            1) list_accounts ;;
            2) create_account ;;
            3) suspend_account ;;
            4) delete_account ;;
            5) echo "Goodbye."; exit 0 ;;
            *) echo "Invalid option, please select 1-5." ;;
        esac
    done
}

main
