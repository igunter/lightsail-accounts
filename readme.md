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
- Suspend Accounts (Coming Soon)
- Delete Accounts (Coming Soon)

### List Accounts

This option will list the accounts that you have created.

### Create Account

This option runs `create.sh`, which will ask you for:
- Username
- Password
- Domain Name
- SSL Required

It then creates a Linux system user, a webroot at `/var/www/<username>/public` (PHP-FPM, Laravel-style rewrite to `index.php`), an nginx vhost at `/etc/nginx/conf.d/<username>.conf` for the domain, requests an SSL certificate via `certbot` if SSL was requested, and writes the account's `.account` metadata file. The PHP-FPM socket is auto-detected from `/run/php/php*-fpm.sock`.

### Suspend Accounts

This option will suspend an account. You will be asked for the following information:
- Username

### Delete Accounts

This option will delete an account. You will be asked for the following information:
- Username