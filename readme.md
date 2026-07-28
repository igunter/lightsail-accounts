# Lightsail Accounts

This script is to administer Lightsail accounts on a Nginx server.

## How to Run the Script

Connect to your server in a terminal window (Putty, Terminal, etc) and run the following command:

If this is the first time you are running this script, then you need to run the following command:
```
git clone https://github.com/igunter/lightsail-accounts.git && cd lightsail-accounts && sudo bash seed-accounts.sh && sudo bash index.sh
```
`seed-accounts.sh` creates a `.account` metadata file (from `account.template`) for any existing account under `/var/www` that doesn't already have one. It only needs to be run once - after that, edit each account's `.account` file with its real domain, SSL and status details. Existing `.account` files are never overwritten, so it's safe to run again later if new accounts are added outside of this script.

else you need to run
```
cd lightsail-accounts && git pull && sudo bash index.sh
```

## What the Script Does

After running the script, you will then be displayed with a menu of options.
- List Accounts
- Create Accounts
- Suspend Accounts
- Delete Accounts

### List Accounts

This option will list the accounts that you have created.

### Create Accounts

This option will create an account. You will be asked for the following information:
- Username
- Password
- Domain Name
- SSL Required

### Suspend Accounts

This option will suspend an account. You will be asked for the following information:
- Username

### Delete Accounts

This option will delete an account. You will be asked for the following information:
- Username