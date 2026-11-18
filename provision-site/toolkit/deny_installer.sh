#!/bin/bash
# Deny Drupal's installer and cache-rebuild script in Apache vhosts.
# Usage: sudo ./deny_installer.sh <vhost .conf file> [more .conf files]
# Example: sudo ./deny_installer.sh /etc/apache2/sites-available/example.com*.conf
#
# Adds, inside every <VirtualHost> block of each file that does not already
# have it:
#     <LocationMatch "^/core/(install|rebuild)\.php$">
#         Require all denied
#     </LocationMatch>
# Keeps a timestamped backup next to each file it changes, runs
# "apache2ctl configtest" and only then reloads Apache. Safe to re-run.
# Background: SA-CORE-2026-017 (Drupal core, November 2026), whose
# mitigation is to make sure nobody can reach core/install.php.

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: sudo $0 <vhost .conf file> [more .conf files]" >&2
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: the vhost files and the Apache reload need root." >&2
    exit 1
fi

MARK='core/(install|rebuild)'
STAMP=$(date +%Y%m%d%H%M%S)
CHANGED=0

for FILE in "$@"; do
    if [ ! -f "$FILE" ]; then
        echo "skip (not a file): $FILE"
        continue
    fi
    if grep -q "$MARK" "$FILE"; then
        echo "already done: $FILE"
        continue
    fi
    if ! grep -q '</VirtualHost>' "$FILE"; then
        echo "skip (no <VirtualHost>): $FILE"
        continue
    fi
    cp -p "$FILE" "$FILE.bak-$STAMP"
    # Insert the block before every closing </VirtualHost>.
    awk '
        /<\/VirtualHost>/ {
            print ""
            print "    # Installer and cache-rebuild script are not used on a deployed site."
            print "    <LocationMatch \"^/core/(install|rebuild)\\.php$\">"
            print "        Require all denied"
            print "    </LocationMatch>"
        }
        { print }
    ' "$FILE.bak-$STAMP" > "$FILE"
    echo "updated: $FILE (backup $FILE.bak-$STAMP)"
    CHANGED=$((CHANGED + 1))
done

if [ "$CHANGED" -eq 0 ]; then
    echo "Nothing to change."
    exit 0
fi

if apache2ctl configtest; then
    systemctl reload apache2
    echo "Apache reloaded. Check: curl -s -o /dev/null -w '%{http_code}\n' https://<host>/core/install.php  -> 403"
else
    echo "configtest FAILED: restoring the backups, Apache not reloaded." >&2
    for FILE in "$@"; do
        [ -f "$FILE.bak-$STAMP" ] && cp -p "$FILE.bak-$STAMP" "$FILE"
    done
    exit 1
fi
