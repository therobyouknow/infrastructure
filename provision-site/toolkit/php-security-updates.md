# PHP security releases: how they reach the servers

PHP announces security releases a day ahead on https://www.php.net/ ("Upcoming
Critical PHP Security Release", usually a Thursday around 14:00 UTC). Both
servers run Canonical's PHP packages, so the fix arrives as an Ubuntu Security
Notice (USN) and not from php.net: watch
https://ubuntu.com/security/notices?details=php and the package pages
https://launchpad.net/ubuntu/+source/php8.3 (24.04, server03) and
https://launchpad.net/ubuntu/+source/php8.5 (26.04, server04). For the
21 October 2026 release (CVE-2026-109618/109619) USN-8948-1 shipped the same
day.

Ubuntu backports the fix onto the existing version, so `php -v` does not
change (server03 stays "8.3.6", server04 "8.5.4"). Verify by the package
version in the USN, e.g. `8.3.6-0ubuntu0.24.04.13`.

`unattended-upgrades` installs USNs on both servers, but only when its daily
timer fires (about 06:00 UTC), so a Thursday-afternoon fix would wait until
Friday morning. The two scripts below close that gap.

## On the day

From the workstation, once the php.net window opens:

```bash
cd provision-site/toolkit
./php_usn_poll.sh -i 15 -u 23:30 server03 server04 2>&1 | tee ~/php-usn-$(date +%Y%m%d).log
```

Every 15 minutes it runs `sudo php_security_update -c` on each server
(`apt-get update`, then installed versus candidate for every installed PHP
package). When a newer candidate appears it runs
`sudo php_security_update -a -y -d`, which, detached from the SSH session:

1. records the HTTP status of every vhost name (https and http, resolved to
   127.0.0.1, so DNS and certificates do not matter),
2. tars `/etc/php` and `/etc/apache2` to `/root/pre-php-update-<ts>.tgz`,
3. `apt-mark manual` on the PHP packages, so a later `autoremove` can never
   take them (the server02 outage of 2026-10-21),
4. `apt-get install --only-upgrade` of the PHP packages only (`-f` would do
   `full-upgrade` and `autoremove` instead, as separate steps),
5. reloads php-fpm and, on a mod_php server, Apache, so OPcache drops the
   old code,
6. takes the HTTP baseline again and diffs it. Any difference is a failure.

Everything from a run is in `/var/log/php-security-update/<timestamp>/`
(`baseline-before.txt`, `baseline-after.txt`, `apt.log`, `versions-*.txt`,
`status`). The poller prints the after-versions when a server reports OK and
the tail of the log when it reports FAIL, and keeps watching the other server.

By hand, on a server:

```bash
sudo php_security_update -c        # exit 0: update available; 10: current
sudo php_security_update -b        # just the HTTP baseline, to see what "normal" is
sudo php_security_update -a        # asks, then upgrades and verifies
```

On server03 `sudo` needs stdin closed when run over SSH without a tty
(`sudo php_security_update -c </dev/null`); `php_usn_poll.sh` does this.

## Which PHP each server runs

| Server | Ubuntu | PHP | How Apache runs it | Reload after a PHP change |
|---|---|---|---|---|
| server03 | 24.04 | 8.3, `php8.3-*` + `libapache2-mod-php8.3` | **mod_php**, prefork (php8.3-fpm is installed and running but no vhost uses it) | `systemctl reload apache2` |
| server04 | 26.04 | 8.5, `php8.5-*` | php-fpm through `proxy_fcgi`, mpm_event | `systemctl reload php8.5-fpm` |

The `deploy` script reloads both where present, for the same OPcache reason.
