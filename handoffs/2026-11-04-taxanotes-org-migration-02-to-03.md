# Brief: migrate taxanotes.org from server 02 to server 03

Goal: a straight lift-and-shift of the taxanotes.org Drupal site from the droplet Rob calls server 02 to server 03, using the existing `provision-site/toolkit` scripts, so server 02 can be decommissioned.

Read first: `provision-site/toolkit/README.md` (site layout, `create_site_structure.sh`, `backup_db.sh`, `fetch_db_dump.sh`, `restore_db.sh`, `sync_files.sh`, `deploy.sh`, `create_vhost.sh`, `site_status.sh`).

Ask Rob once for: the SSH hostnames/aliases of server 02 and 03 (check `~/.ssh/config` first), which category number taxanotes.org uses, where the code repo is (taxanotes org on GitHub, probably `web-community`), and whether the site is still being edited (freeze window for the final sync).

Steps: 1) `site_status.sh` on 02 to inventory the site (Drupal version, PHP, DB name, files size, cron). 2) Dry run: full DB + files backup from 02 (`backup_db.sh`, `sync_files.sh`), create the structure on 03, deploy the code, restore DB, settings.local.php with new credentials, vhost + certbot on 03, test via `/etc/hosts` override before DNS. 3) Cut-over: content freeze, final DB + files sync, lower DNS TTL beforehand, switch the A/AAAA record, verify, keep 02 untouched for a week as rollback. 4) Record the runbook under `local/runbooks/`.

Rules: no destructive action on 02 in this task (decommissioning is a separate brief). Rotate any DB password that was ever committed to a public repo, rather than reusing it.
