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
- Suspend Account
- Reactivate Account
- Delete Account (Coming Soon)

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

### Suspend Account

This option runs `suspend.sh`. You'll be asked for the account's username, then it:
- Creates a `.suspended` sentinel file in the account's home directory (`/var/www/<username>/.suspended`).
- Locks the account's Linux login (`usermod -L`).
- Sets `STATUS="suspended"` in the account's `.account` file.

Every vhost created by `create.sh` checks for that sentinel file on each request (see `nginx-vhost.template`) and, if present, returns `503 Service Unavailable` and serves a shared "Account Suspended" page (`/var/www/_suspended/index.html`, from `suspended-page.template`) instead of the site. No nginx config edit or reload is needed, so suspending never touches the SSL directives `certbot` added to the vhost file.

If the account's vhost predates this feature (e.g. it was set up by hand before this tool existed), `suspend.sh` detects that it's missing the check and patches it in automatically - it only ever inserts new lines right after the vhost's first `server {`, so it never rewrites the `ssl_certificate` lines `certbot` already added. A timestamped backup of the original file is kept alongside it (`<name>.conf.bak-<timestamp>`).

`suspend.sh` can also be run directly: `sudo bash suspend.sh`.

### Reactivate Account

This option runs `reactivate.sh` to undo a suspension: removes the `.suspended` sentinel file, unlocks the Linux login (`usermod -U`), and sets `STATUS="active"` again. Site traffic is served normally again immediately, with no nginx reload needed.

`reactivate.sh` can also be run directly: `sudo bash reactivate.sh`.

### Delete Account

This option will delete an account. You will be asked for the following information:
- Username