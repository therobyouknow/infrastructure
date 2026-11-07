# Brief: automate creation of DigitalOcean "server 04" (Ubuntu 26.04 LTS)

Goal: a repeatable, mostly hands-off way to create and harden a new droplet, so that server 04 can be built now and rebuilt later without clicking through the DO console. Rob's own tickets #1–#4 (Provision droplet Ubuntu 26.04 LTS; Initial server hardening; Caddy with automatic HTTPS; Podman rootless + Quadlet) describe the intended end state; #21–#23 and #30–#31 (DDEV template, Spaces + restic, backup timer, ADRs, session handoff doc) are adjacent. Read `containerisation/planning/ROADMAP.md`, `containerisation/planning/2026-05-new-server-general-purpose.md` and `containerisation/planning/containerising-drupal-discussion.md` first, then `provision-site/toolkit/README.md` for how sites are laid out today (flat Apache + PHP + one MariaDB, `/var/www/[category]/[domain]/releases/...`).

Open decisions to confirm with Rob before writing anything (ask once, together):
1. Web stack on server 04: keep the toolkit's Apache + PHP-FPM flat layout (what servers 02/03 run; lowest risk for Drupal 11 sites), or the Caddy + Podman/Quadlet containers the tickets describe? Recommendation: flat Apache for the Drupal 11 sites now, with Docker/Podman installed only for isolated legacy workloads (a Drupal 7 Scratchpads container needs PHP 7.2); revisit containers after the first Drupal 11 site is live.
2. Droplet size/region, and whether server 04 replaces server 03 or sits beside it.
3. Ubuntu 26.04: check the DO image slugs (`doctl compute image list-distribution --public | grep -i ubuntu`) for a 26.04 image; if only 26.04 (not .1) is offered, DO images receive point updates via apt anyway, so take it.

Deliverables (into `provision-site/droplet/`):
- `create-droplet.sh`: wraps `doctl compute droplet create` with SSH key, tags, monitoring, backups flag, VPC, and `--user-data cloud-init.yaml`; prints the IP and waits for SSH. Idempotent (refuses to create a duplicate name). `doctl` is not installed on the Mac yet: `brew install doctl`, `doctl auth init` (token kept in the keychain/env, never in the repo).
- `cloud-init.yaml`: non-root user `rob` with SSH keys, sshd hardening (keys only, no root), ufw (22/80/443), unattended-upgrades, fail2ban, timezone, swap, base packages, and either the Apache/PHP/MariaDB set or Docker/Podman depending on decision 1. Keep secrets out; MariaDB root password set on first login, not in user-data.
- `verify-droplet.sh`: post-create checklist run over SSH (ufw status, sshd config, versions, disk, time sync).
- `docs/` note: how to rerun, how to destroy, cost.
- Optionally an OpenTofu/Terraform variant later; not for the first pass (adds state management for one droplet).

Rules: never store the DO token, passwords or private keys in the repo (it is public: therobyouknow/infrastructure). Do not create the droplet until Rob has confirmed the decisions above; dry-run (`--dry-run` flag in the script) first.

## Decisions taken by Rob on 2026-11-04 (supersede the open questions above)
- **Flat stack, no containers**: Apache 2.4 + PHP-FPM (the PHP that Ubuntu 26.04 ships, expected 8.4) + MariaDB + Composer + Drush launcher + Certbot, laid out per `provision-site/toolkit` (`/var/www/[category]/[domain]/...`, user `rob`, group `www-data`). Drupal 11 sites only. Docker is NOT installed on this server.
- **Ubuntu 26.04 LTS** (take the DO image available; point releases arrive via apt).
- Server name: **server 04**. Sits beside server 03; server 02 will be decommissioned separately.
- Rob will install `doctl` and run `doctl auth init` himself; the DO token is never given to Claude or stored in the repo. Claude writes the scripts and a dry-run; Rob runs the creation command himself (or asks Claude to run it explicitly, later).
