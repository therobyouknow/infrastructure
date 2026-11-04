# server04: DigitalOcean droplet, Ubuntu 26.04 LTS, flat Drupal stack

Repeatable creation and hardening of "server04" without clicking through the
DigitalOcean console. One command creates the droplet; cloud-init hardens it
and installs the stack on first boot; a checklist confirms it.

What you get (decisions of 2026-11-04, see `handoffs/2026-11-04-server04-provisioning.md`):

- Ubuntu 26.04 LTS, timezone Europe/London, 2 GB swap, unattended security updates
- user `rob` (groups `sudo`, `www-data`), SSH keys only, root login off, password auth off
- ufw allowing 22/80/443 only; fail2ban on sshd
- Apache 2.4 (event MPM) + PHP-FPM as shipped by 26.04, with gd, mbstring, xml,
  curl, zip, intl, opcache, mysql, apcu and Drupal-friendly ini settings
- MariaDB (root password set by you on first login, never in user-data)
- Composer at `/var/www/tools/dev/phpcomposer/composer.phar` (+ `/usr/local/bin/composer`),
  Drush launcher, Certbot with the Apache plugin
- `/var/www` owned `rob:www-data`; toolkit scripts in `/home/rob/scripts` and on PATH
  (`deploy`, `create_release`, ...), per `provision-site/toolkit/README.md`
- No Docker.

## Files

| File | Purpose |
|---|---|
| `droplet.env.example` | Settings (name, region, size, image, key files). Copy to `droplet.env`, which is gitignored. |
| `cloud-init.yaml` | User-data template. `@@PLACEHOLDERS@@` are filled from `droplet.env` into `cloud-init.rendered.yaml` (gitignored). |
| `create-droplet.sh` | Renders user-data, refuses duplicates, runs `doctl compute droplet create`, waits for SSH and cloud-init, prints the IP. |
| `verify-droplet.sh` | PASS/WARN/FAIL checklist over SSH: sshd, ufw, fail2ban, updates, time, versions, extensions, layout, disk, swap. |

## The three commands Rob runs

```bash
brew install doctl                 # once
doctl auth init                    # once; paste a DO API token (read/write). It is stored by
                                   # doctl in ~/Library/Application Support/doctl (macOS keychain-
                                   # backed), NOT in this repo.
cd provision-site/droplet
cp droplet.env.example droplet.env # edit: DROPLET_SSH_KEYS (doctl compute ssh-key list),
                                   #       ROB_AUTHORIZED_KEYS_FILES (your .pub files)
./create-droplet.sh --dry-run      # prints the exact doctl command, sends nothing
./create-droplet.sh                # creates server04 and waits (~10-15 min first boot)
```

Then:

```bash
./verify-droplet.sh <ip-or-alias>   # the checklist; add a Host server04 block to ~/.ssh/config first
ssh -t server04 ./first-login.sh    # runs mariadb-secure-installation (sets the root password)
```

After that, sites are created with the toolkit exactly as on server03
(`create_site_structure`, `create_database`, `create_vhost`,
`sudo certbot --apache -d domain`, `create_release`, `deploy`).

## Dry run

`./create-droplet.sh --dry-run` reads `droplet.env`, reads your public key files,
renders `cloud-init.rendered.yaml`, checks it for placeholders, size (DO limit 64 KiB)
and anything that looks like a secret, then prints the `doctl` command and exits.
It never calls `doctl`, so it works before `doctl auth init`. Inspect the rendered
file; it is what the droplet will receive.

Without `--dry-run` the script additionally checks that doctl is authenticated,
that no droplet of that name exists (it refuses rather than creating a second one),
and that the image slug is still offered.

## Rebuild

Server04 is disposable: everything on it comes from this directory plus site
backups. To rebuild from scratch:

```bash
doctl compute droplet delete server04      # destroys the droplet and its disk; prompts y/N
ssh-keygen -R <old-ip>                      # forget the old host key
./create-droplet.sh                         # new droplet, possibly a new IP
```

Rebuild with the same public IP later by attaching a DigitalOcean Reserved IP
(free while assigned) and pointing DNS at that instead of the droplet IP.

To change what a rebuild installs, edit `cloud-init.yaml` and dry-run again.
Changes to the template do not affect a running droplet; apply them by hand or rebuild.

## Destroy

```bash
doctl compute droplet list                  # find it
doctl compute droplet delete server04       # or: --force to skip the prompt
```

Take a final `backup_db`/files copy first; deletion is immediate and
unrecoverable. If backups were enabled, DO's snapshots of the droplet are
deleted with it.

## Cost (DigitalOcean list prices, November 2026, USD)

| Item | Monthly |
|---|---|
| `s-2vcpu-4gb` Basic/Regular: 2 vCPU, 4 GB RAM, 80 GB SSD, 4 TB transfer | $24.00 ($0.0357/h) |
| Automated backups, weekly (`DROPLET_ENABLE_BACKUPS=yes`) | +20% = $4.80 |
| Automated backups, daily | +30% = $7.20 |
| Monitoring (`--enable-monitoring`) | free |
| Reserved IP while assigned to a droplet | free |

So $24/month, or about $29/month with weekly backups. Billing is hourly while
the droplet exists (including powered off). The planning docs suggest 4 GB /
2 vCPU as the starting size (`containerisation/planning/ROADMAP.md`); resize up
later with `doctl compute droplet-action resize` if needed.

## Secrets

- The DigitalOcean API token is never stored in this repository. `doctl auth init`
  keeps it in doctl's own config on your Mac; the scripts only call `doctl`.
- `droplet.env` and `cloud-init.rendered.yaml` are gitignored. They contain no
  secrets either (only public keys), but they are machine-specific.
- `create-droplet.sh` refuses to read anything but `*.pub` files and aborts if the
  rendered user-data looks like it contains a private key or a password.
- User-data is readable from inside the droplet by any process
  (`curl 169.254.169.254/metadata/v1/user-data`), which is why the MariaDB root
  password is set interactively by `~/first-login.sh` and not by cloud-init.

## Notes and things to check

- Image slug `ubuntu-26-04-x64` comes from DO's release note of 1 July 2026
  (https://docs.digitalocean.com/notes/2026/ubuntu-26-04/). The non-dry run
  re-checks it against `doctl compute image list-distribution --public`.
- PHP version is whatever 26.04 ships (expected 8.4); `cloud-init.yaml` detects
  it at boot rather than hard-coding `php8.4`.
- `rob` has passwordless sudo because cloud-init creates the user with no password.
  `first-login.sh` shows how to set a password and require it for sudo if you prefer.
- `unattended-upgrades` does not auto-reboot; `verify-droplet.sh` warns when a
  reboot is pending.
- The Drush launcher project is archived upstream. It still works as a global
  `drush` that defers to each site's `vendor/bin/drush`, and the toolkit uses
  `./drush` inside each release anyway, so its absence is a WARN not a FAIL.
- Logs on the box: `/var/log/cloud-init-output.log`, `/var/log/server04-provision.log`.
