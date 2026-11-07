# Brief: decommission server 02

Preconditions (each must be true before destroying anything): taxanotes.org migrated to server 03 and verified for at least a week; navinales.com code archived to a private GitHub repo (in progress in a separate conversation); nothing else on the droplet is needed.

Steps:
1. Inventory on 02: `/var/www/*`, Apache vhosts, all MariaDB databases (`SHOW DATABASES`), crontabs (root and rob), systemd timers, SSL certs, any DNS records (all domains) pointing at its IP, DO floating IPs/volumes/firewalls attached, backups schedule.
2. For each item: migrated / archived / discard, with Rob's confirmation on the list as a whole.
3. Final archive: `mysqldump --all-databases` + tar of `/var/www`, `/etc/apache2/sites-available`, `/etc/letsencrypt`, crontabs; copy to the Mac and to DO Spaces if configured; checksum.
4. Take a DO droplet snapshot (cheap insurance, delete after 30 days).
5. Remove/repoint DNS records; wait for TTL; confirm nothing still resolves to the old IP.
6. Destroy the droplet; delete attached volumes/reserved IPs; confirm the billing line disappears.
7. Record what was removed and where the archive lives in `local/runbooks/`.

Rules: destruction only after Rob has seen the inventory and said yes explicitly; snapshot before destroy; never skip step 5.
