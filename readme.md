# Lightsail Accounts

This script is to administer Lightsail accounts on a Nginx server.

## How to Run the Script

Connect to your server in a terminal window (Putty, Terminal, etc) and run the following command:

If this is the first time you are running this script, then you need to run the following command:
```
sudo git clone https://github.com/igunter/lightsail-accounts.git /lightsail-accounts && cd /lightsail-accounts && sudo bash seed-accounts.sh && sudo bash index.sh
```
`seed-accounts.sh` creates a `.account` metadata file (from `account.template`) for any existing account under `/var/www` that doesn't already have one. It only needs to be run once - after that, edit each account's `.account` file with its real domain, SSL and status details. Existing `.account` files are never overwritten, so it's safe to run again later if new accounts are added outside of this script.

else you need to run
```
cd /lightsail-accounts && sudo bash index.sh
```
or if you want to update the script
```
cd /lightsail-accounts && sudo git pull && sudo bash index.sh
```

## What the Script Does

After running the script, you will then be displayed with a menu of options.
- List Accounts
- Create Account
- Deactivate Account
- Reactivate Account
- Delete Account

### List Accounts

This option will list the accounts that you have created.

### Create Account

This option runs `create.sh`, which will ask you for:
- Username
- Password
- Domain Name
- SSL Required

It then creates a Linux system user, a webroot at `/var/www/<username>/public` (PHP-FPM, Laravel-style rewrite to `index.php`), an nginx vhost at `/etc/nginx/conf.d/<username>.conf` for the domain, requests an SSL certificate via `certbot` if SSL was requested, and writes the account's `.account` metadata file. The PHP-FPM socket is auto-detected from `/run/php/php*-fpm.sock`.

The account's home directory is `chmod`'d `711` (traversable, not listable) and `public/` `755`, so nginx/php-fpm can actually read the site even though it runs as a different user. A placeholder "Site Coming Soon" page (`placeholder-page.template`) is seeded into `public/` if it's empty, so a freshly created account doesn't 403 before real content is deployed.

### Deactivate Account

This option runs `deactivate.sh`. You'll be asked for the account's username, then it:
- Creates a `.deactivated` sentinel file in the account's home directory (`/var/www/<username>/.deactivated`).
- Locks the account's Linux login (`usermod -L`).
- Sets `STATUS="deactivated"` in the account's `.account` file.

Every vhost created by `create.sh` checks for that sentinel file on each request (see `nginx-vhost.template`) and, if present, returns `503 Service Unavailable` and serves a shared "Account Deactivated" page (`/var/www/_deactivated/index.html`, from `deactivated-page.template`) instead of the site. No nginx config edit or reload is needed, so deactivating never touches the SSL directives `certbot` added to the vhost file.

If the account's vhost predates this feature (e.g. it was set up by hand before this tool existed), `deactivate.sh` detects that it's missing the check and patches it in automatically - it only ever inserts new lines right after the vhost's first `server {`, so it never rewrites the `ssl_certificate` lines `certbot` already added. A timestamped backup of the original file is kept alongside it (`<name>.conf.bak-<timestamp>`).

`deactivate.sh` can also be run directly: `sudo bash deactivate.sh`.

### Reactivate Account

This option runs `reactivate.sh` to undo a deactivation: removes the `.deactivated` sentinel file, unlocks the Linux login (`usermod -U`), and sets `STATUS="active"` again. Site traffic is served normally again immediately, with no nginx reload needed.

`reactivate.sh` can also be run directly: `sudo bash reactivate.sh`.

### Delete Account

This option runs `delete.sh`. **The account must already be deactivated** (option 3) - this is a deliberate guardrail so a live account can't be deleted by mistake; `delete.sh` will refuse and tell you to deactivate first otherwise.

You'll be asked for the username, shown a summary of what will be removed, and then must type the username again to confirm. Once confirmed, it:
- Archives `/var/www/<username>` to `/var/backups/lightsail-accounts/<username>-<timestamp>.tar.gz`.
- Removes the nginx vhost (`/etc/nginx/conf.d/<username>.conf`) and any `patch_legacy_vhost` backups for it.
- Queues the SSL certificate for deletion 28 days from now (see below) rather than revoking it immediately.
- Deletes the Linux system user and its home directory (`userdel -r`).

`delete.sh` can also be run directly: `sudo bash delete.sh`.

#### SSL certificate cleanup (`cleanup-certs.sh`)

Certificates aren't revoked at delete time - `delete.sh` drops a file named after the domain into `/etc/lightsail-accounts/cert-cleanup-queue/` containing the date it becomes eligible for deletion (today + 28 days). This gives you a grace period in case the domain gets reused (e.g. `create.sh` recreates the account) before then, in which case the next cleanup run cancels it automatically instead of deleting a certificate that's back in use.

`cleanup-certs.sh` is meant to run on a daily cron schedule and processes that queue - deleting (via `certbot delete`) any certificate whose grace period has passed, and cancelling the cleanup for any domain it finds is back in an active nginx vhost. Add it to root's crontab, e.g.:
```
sudo crontab -e
```
```
0 3 * * * bash /lightsail-accounts/cleanup-certs.sh >> /var/log/lightsail-accounts-cert-cleanup.log 2>&1
```