#!/usr/bin/env bash
#
# Lightsail Accounts - deletes SSL certificates queued by delete.sh once
# their grace period has passed.
#
# When an account is deleted, its certificate isn't revoked immediately -
# delete.sh instead drops a file named after the domain into
# CERT_QUEUE_DIR containing the date (YYYY-MM-DD) it becomes eligible for
# deletion. This script is meant to run on a daily cron schedule; each run
# it:
#   - cancels the cleanup (and removes the queue entry) for any domain that
#     has since been reused by a live nginx vhost
#   - runs `certbot delete` for any domain whose eligible date has passed
#
# Usage: sudo bash cleanup-certs.sh
# Suggested cron entry (daily at 3am):
#   0 3 * * * root bash /lightsail-accounts/cleanup-certs.sh >> /var/log/lightsail-accounts-cert-cleanup.log 2>&1

set -euo pipefail

NGINX_CONF_D="/etc/nginx/conf.d"
CERT_QUEUE_DIR="/etc/lightsail-accounts/cert-cleanup-queue"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root (try: sudo bash cleanup-certs.sh)."
        exit 1
    fi
}

require_root

if [ ! -d "$CERT_QUEUE_DIR" ]; then
    exit 0
fi

today="$(date +%F)"

for queue_file in "$CERT_QUEUE_DIR"/*; do
    [ -f "$queue_file" ] || continue
    domain="$(basename "$queue_file")"
    eligible_date="$(tr -d '[:space:]' < "$queue_file")"

    if grep -rqF "$domain" "$NGINX_CONF_D" 2>/dev/null; then
        echo "${domain}: back in use by an nginx vhost - cancelling scheduled certificate cleanup."
        rm -f "$queue_file"
        continue
    fi

    if [[ "$today" < "$eligible_date" ]]; then
        continue
    fi

    if ! command -v certbot &>/dev/null; then
        echo "${domain}: certificate cleanup is due but certbot is not installed - skipping."
        continue
    fi

    echo "${domain}: grace period expired (eligible ${eligible_date}) - deleting certificate."
    if certbot delete --cert-name "$domain" --non-interactive; then
        rm -f "$queue_file"
    else
        echo "${domain}: certbot delete failed - leaving queued for retry."
    fi
done
