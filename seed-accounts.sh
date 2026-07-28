#!/usr/bin/env bash
#
# One-off helper: seeds a .account metadata file (from account.template) into
# every existing account directory under /var/www that doesn't already have one.
# Existing .account files are left untouched.
#
# Usage: sudo bash seed-accounts.sh

BASE_DIR="/var/www"
TEMPLATE_FILE="$(dirname "$0")/account.template"
ACCOUNT_META_FILE=".account"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (try: sudo bash seed-accounts.sh)."
    exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template file not found: ${TEMPLATE_FILE}"
    exit 1
fi

if [ ! -d "$BASE_DIR" ]; then
    echo "Base directory ${BASE_DIR} does not exist."
    exit 1
fi

created=0
skipped=0

for entry in "$BASE_DIR"/*/; do
    [ -d "$entry" ] || continue
    username="$(basename "$entry")"
    meta_path="${entry}${ACCOUNT_META_FILE}"

    if [ -f "$meta_path" ]; then
        echo "Skipping ${username}: .account already exists."
        skipped=$((skipped + 1))
        continue
    fi

    cp "$TEMPLATE_FILE" "$meta_path"
    echo "Seeded ${username}: created ${meta_path} - edit it with the account's real details."
    created=$((created + 1))
done

echo ""
echo "Done. Created ${created}, skipped ${skipped}."
