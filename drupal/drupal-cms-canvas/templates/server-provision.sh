#!/usr/bin/env bash
#
# One-off root setup for a Drupal CMS site on a server with the
# provision-site toolkit installed (../../../provision-site/toolkit).
#
# Copy to scripts/server-provision.sh, fill in the settings, then from the
# project folder (asks for your sudo password once):
#   scp scripts/server-provision.sh myserver:example.com-provision.sh
#   ssh -t myserver sudo bash example.com-provision.sh
#
# Safe to re-run: each step skips what already exists. Creates the site
# folders, database and settings.local.php, an Apache vhost (optionally
# behind HTTP auth) and, once DNS points at the server, the HTTPS certificate.
# No secrets are printed: generated logins go to a file in the owner's home.

set -euo pipefail

# --- Settings ---------------------------------------------------------------

SITE=example.com                 # Full host name; also the toolkit's site key
ALIASES=(www.example.com)        # Extra host names, or () for none
CATEGORY=04                      # /var/www/<category>/<site>
DB_NAME=dexample_1               # Database and user, matching create_database.sh
DB_USER=uexample_1
SERVER_IP=                       # Public IPv4 the A records should point at
MAIL=noreply@example.com         # system.site mail until real mail is set up
AUTH_USERS=(preview)             # HTTP auth logins, or () for a public site
AUTH_NAME="Example preview"
OWNER=${SUDO_USER:?Run with sudo} # Owns the site files and gets the logins file

# ----------------------------------------------------------------------------

[ -n "$SERVER_IP" ] || { echo "Set SERVER_IP first."; exit 1; }

BASE=/var/www/$CATEGORY/$SITE
ENV_DIR=$BASE/deployment_environments/live
DOCROOT=$ENV_DIR/docroot
SETTINGS=$BASE/settings/1/settings.local.php
PASSWD_DIR=/etc/apache2/sites-passwords/$SITE
VHOST=/etc/apache2/sites-available/$SITE.conf
LOGINS=/home/$OWNER/$SITE-preview-logins.txt

say() { printf '\n==> %s\n' "$*"; }

say "Site folders"
if [ ! -d "$BASE" ]; then
  create_site_structure "$CATEGORY" "$SITE"
fi
mkdir -p "$ENV_DIR/assets/private"
chown -R "$OWNER":www-data "$BASE"
chmod 2775 "$ENV_DIR/assets/public/files" "$ENV_DIR/assets/private"

say "Database"
if [ -f "$SETTINGS" ]; then
  echo "settings.local.php exists; leaving database as it is."
else
  DB_PASS=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)
  mysql <<SQL
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
  hosts=""
  for host in "$SITE" ${ALIASES[@]+"${ALIASES[@]}"}; do
    hosts+="'^${host//./\\.}\$', "
  done
  cat > "$SETTINGS" <<PHP
<?php

\$databases['default']['default'] = [
  'database' => '$DB_NAME',
  'username' => '$DB_USER',
  'password' => '$DB_PASS',
  'host' => 'localhost',
  'port' => '3306',
  'driver' => 'mysql',
];
\$settings['hash_salt'] = '$(openssl rand -base64 48 | tr -d '\n')';
\$settings['trusted_host_patterns'] = [${hosts%, }];
\$settings['file_private_path'] = '$ENV_DIR/assets/private';
\$config['system.site']['mail'] = '$MAIL';
PHP
  chown "$OWNER":www-data "$SETTINGS"
  chmod 640 "$SETTINGS"
  echo "Created $DB_NAME and $SETTINGS"
fi

AUTH_BLOCK=""
if [ ${#AUTH_USERS[@]} -gt 0 ]; then
  say "Preview logins (HTTP auth)"
  mkdir -p "$PASSWD_DIR"
  if [ ! -f "$PASSWD_DIR/.htpasswd" ]; then
    : > "$LOGINS"
    for user in "${AUTH_USERS[@]}"; do
      pass=$(openssl rand -base64 12 | tr -d '=+/' | cut -c1-14)
      htpasswd -bB $([ -f "$PASSWD_DIR/.htpasswd" ] || echo -c) "$PASSWD_DIR/.htpasswd" "$user" "$pass" 2>/dev/null
      echo "$user  $pass" >> "$LOGINS"
    done
    chown "$OWNER":"$OWNER" "$LOGINS"
    chmod 600 "$LOGINS"
    echo "Logins written to $LOGINS"
  else
    echo ".htpasswd exists; leaving logins as they are."
  fi
  chown root:www-data "$PASSWD_DIR/.htpasswd"
  chmod 640 "$PASSWD_DIR/.htpasswd"
  AUTH_BLOCK="
        # Preview login. To go public, delete these four lines here and in
        # $SITE-le-ssl.conf, then reload Apache.
        AuthType Basic
        AuthName \"$AUTH_NAME\"
        AuthUserFile $PASSWD_DIR/.htpasswd
        Require valid-user"
fi

say "Apache vhost"
if [ ! -f "$VHOST" ]; then
  SERVER_ALIAS=""
  [ ${#ALIASES[@]} -gt 0 ] && SERVER_ALIAS="ServerAlias ${ALIASES[*]}"
  cat > "$VHOST" <<APACHE
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName $SITE
    $SERVER_ALIAS
    DocumentRoot $DOCROOT
    ErrorLog \${APACHE_LOG_DIR}/${SITE}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SITE}_access.log combined

    <Directory "$DOCROOT">
        Options FollowSymLinks
        AllowOverride All$AUTH_BLOCK
    </Directory>
</VirtualHost>
APACHE
  a2ensite "$SITE.conf" >/dev/null
fi
apache2ctl configtest
systemctl reload apache2

say "HTTPS certificate"
# The server's resolver can cache "no such name" for a while after a record
# is added. If this says DNS isn't ready but `dig @8.8.8.8 <host>` shows the
# record, run the certbot line below by hand with each -d host.
domains=()
for host in "$SITE" ${ALIASES[@]+"${ALIASES[@]}"}; do
  if getent ahostsv4 "$host" | grep -q "^$SERVER_IP "; then
    domains+=(-d "$host")
  else
    echo "DNS for $host does not point at $SERVER_IP yet."
  fi
done
if [ ${#domains[@]} -eq 0 ]; then
  echo "Add the A records, then re-run this script."
else
  # --expand adds aliases to the certificate if it was issued before they resolved.
  certbot --apache "${domains[@]}" --cert-name "$SITE" --non-interactive --redirect --keep-until-expiring --expand
fi

say "Done"
