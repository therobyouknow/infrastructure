# New site checklist

From an empty folder to a site on the server behind HTTPS. Build steps are
in [README.md](README.md); server commands are from the
[provision-site toolkit](../../provision-site/toolkit/README.md).

Placeholders: `example.com` (site), `myserver` (ssh host), `NN` (category
folder), `1.2.3.4` (server IP), `owner/example` (GitHub repo).

## Build (local)

- [ ] DDEV project created, `name:` and `php_version: "8.3"` restored in `.ddev/config.yaml`
- [ ] Starter and forms recipes required; Drush in `require`; `platform.php` pinned
- [ ] Site installed; forms recipe applied
- [ ] `config_sync_directory` = `../config/sync`; `settings.local.php` include at the end of `settings.php`
- [ ] Content type and pages scripts run; checked in a normal browser
- [ ] Contact form email handler off until mail works
- [ ] `ddev drush cex -y`, committed, private GitHub repo created and pushed:
  `gh repo create owner/example --private --source=. --remote=origin --push`

## Server (once)

- [ ] Copy `templates/server-provision.sh` to `scripts/`, fill in the settings, commit
- [ ] Run it: `scp scripts/server-provision.sh myserver:example.com-provision.sh && ssh -t myserver sudo bash example.com-provision.sh`
- [ ] DNS: A records for `@` (and `www`) → `1.2.3.4`
- [ ] Re-run the script for the certificate. If the server's resolver is
      still caching "no such name" (`dig @8.8.8.8 example.com` works but the
      script says DNS isn't ready), run certbot by hand:
      `ssh -t myserver "sudo certbot --apache -d example.com -d www.example.com --cert-name example.com --non-interactive --redirect --expand"`

## First release

Either add a read-only deploy key for the repo on the server, or ship a git
bundle (no key needed):

```bash
git bundle create /tmp/example.bundle main
scp /tmp/example.bundle myserver:/tmp/example.com.bundle
ssh myserver create_release example.com 0.1.0 /tmp/example.com.bundle main
```

On the server:

```bash
cd /var/www/NN/example.com/releases/0.1.0/code
ln -sf ../../../../../../deployment_environments/live/assets/public/files web/sites/default/files
ln -sf /var/www/NN/example.com/settings/1/settings.local.php web/sites/default/settings.local.php
./composer install --no-dev --optimize-autoloader
```

Database from DDEV (`restore_db` asks for confirmation; pipe `yes` only when
the target database is the new, empty one):

```bash
ddev export-db --file=/tmp/example.sql.gz
scp /tmp/example.sql.gz myserver:/tmp/
ssh myserver 'echo yes | restore_db example.com 1 /tmp/example.sql.gz && rm /tmp/example.sql.gz'
```

Deploy (`deploy` runs `updb` and `cr`, not a config import):

```bash
ssh myserver 'deploy example.com live 0.1.0 && drush_run example.com live "cim -y"'
```

## Before sharing the link

- [ ] `http://` redirects to `https://`, for every host name
- [ ] Private window asks for the HTTP auth login (if used)
- [ ] Admin password changed: `drush_run example.com live "uli --uri=https://example.com"`
- [ ] Placeholder copy (`[to add]`) filled in or the page unpublished
- [ ] Client/third-party content only published with their agreement
- [ ] Repo runbook (`docs/deploy.md`) records the site's own values

## After launch

The server database becomes the master copy once anyone edits content
there. Pull it down with `fetch_and_import_env_db.sh myserver example.com live`
rather than pushing a local one up. Code changes go out as new releases.
