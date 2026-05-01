# Infrastructure Roadmap

Source-of-truth plan for the `therobyouknow/infrastructure` repo. Each entry below is shaped so you can paste it directly into GitHub as an issue. Milestones map to GitHub Milestones; the suggested labels are listed for each.

## Architecture at a glance

```
                    ┌─────────────────────────────────────┐
   Internet ──443──▶│  Caddy (host, automatic HTTPS)      │
                    └─────────────────────────────────────┘
                          │            │             │
                  127.0.0.1:8001  :8002        :8501
                          ▼            ▼             ▼
                    ┌─────────┐  ┌─────────┐   ┌──────────┐
                    │Drupal   │  │ React   │   │Streamlit │
                    │+MariaDB │  │ static  │   │ container│
                    │(podman) │  │(podman) │   │          │
                    └─────────┘  └─────────┘   └──────────┘

Subdomains:
  api.therobyouknow.com      → Drupal (headless)
  app.therobyouknow.com      → React frontend
  data.therobyouknow.com     → Streamlit
```

## Tech stack decisions

| Concern                  | Choice                                | Why                                          |
|--------------------------|---------------------------------------|----------------------------------------------|
| Host OS                  | Ubuntu 26.04 LTS (Resolute Raccoon)   | Podman 5.7, systemd 259, stable until 2031   |
| Reverse proxy / TLS      | Caddy (host)                          | Automatic Let's Encrypt, simple Caddyfile    |
| Containers               | Podman (rootless) + Quadlet           | Daemonless, systemd-native, open source      |
| Drupal DB                | MariaDB 11.8 LTS (container)          | First-class in Ubuntu 26.04 main             |
| Image registry           | GitHub Container Registry (ghcr.io)   | Free, private, next to source                |
| CI                       | GitHub Actions                        | Free tier, standard YAML, portable           |
| Backups                  | restic → DigitalOcean Spaces (S3)     | Open source, encrypted, dedupe, S3-portable  |
| Local dev                | DDEV (per Drupal project)             | Matches existing workflow                    |
| Dependency updates       | Renovate (self-hosted or app)         | Open source, standard, replaces Dependabot   |
| Monitoring (initial)     | systemd journal + uptime-kuma         | Open source, lightweight                     |

## Suggested labels

- `area:server` `area:caddy` `area:podman` `area:drupal` `area:react` `area:streamlit` `area:backup` `area:ci` `area:docs`
- `type:setup` `type:script` `type:config` `type:docs` `type:investigation`
- `priority:p1` `priority:p2` `priority:p3`
- `blocked` `good-first-issue` `epic`

## Milestones

1. **M1 — Server Foundation** (provision + harden + Caddy + Podman)
2. **M2 — Headless Drupal** (api.therobyouknow.com live)
3. **M3 — React Frontend** (app.therobyouknow.com consuming the API)
4. **M4 — Streamlit App** (data.therobyouknow.com)
5. **M5 — Image Registry & CI** (build → push → pull workflow)
6. **M6 — Dev/Prod Data Flow** (DB pulls, file sync, DDEV)
7. **M7 — Backup & Restore** (with tested restore drill)
8. **M8 — Updates & Maintenance** (host, containers, Drupal)
9. **M9 — Operations & Continuity** (runbooks, ADRs, handoff)

---

# M1 — Server Foundation

### Issue: Provision DigitalOcean droplet (Ubuntu 26.04 LTS)

**Description**
Create the production droplet that will host all containerised applications.

**Tasks**
- [ ] 4 GB / 2 vCPU droplet, Ubuntu 26.04 LTS, in chosen region (LON1 likely)
- [ ] Attach a 50 GB block storage volume for `/var/lib/containers` data
- [ ] Enable automated backups
- [ ] Reserved IP attached to the droplet (free, allows blue-green later)
- [ ] Record droplet ID, IP, region in `docs/server-inventory.md`

**Acceptance criteria**
- Droplet reachable via SSH key auth
- Block volume mounted and persistent across reboots
- Reserved IP assigned

**Labels**: `area:server` `type:setup` `priority:p1`

---

### Issue: Initial server hardening

**Description**
Lock down the fresh droplet before any services are exposed.

**Tasks**
- [ ] Create non-root sudo user `rob`
- [ ] Disable root SSH login and password auth
- [ ] Configure UFW: allow 22, 80, 443; deny everything else
- [ ] Install and configure `fail2ban` for SSH
- [ ] Enable `unattended-upgrades` for security patches
- [ ] Set timezone, hostname, `/etc/hosts`
- [ ] Run `loginctl enable-linger rob` (rootless Podman persistence)

**Acceptance criteria**
- SSH key-only access as `rob`
- `ufw status` shows only 22/80/443
- `fail2ban-client status sshd` running
- Documented in `scripts/01-harden-server.sh`

**Labels**: `area:server` `type:script` `priority:p1`

---

### Issue: Install Caddy with automatic HTTPS

**Description**
Caddy runs on the host (not in a container) and handles all TLS termination. It will reverse-proxy to localhost ports for each containerised app.

**Tasks**
- [ ] Install Caddy from the official Cloudsmith repo
- [ ] Verify the systemd service starts on boot
- [ ] Create a placeholder Caddyfile at `/etc/caddy/Caddyfile`
- [ ] Test with a single subdomain returning a 200
- [ ] Verify Let's Encrypt cert issued automatically

**Acceptance criteria**
- `systemctl status caddy` healthy
- A test subdomain serves a "hello" page over HTTPS with valid cert
- Caddyfile under version control in this repo at `caddy/Caddyfile`

**Labels**: `area:caddy` `type:setup` `priority:p1`

---

### Issue: Install Podman (rootless) and Quadlet directory

**Description**
Set up rootless Podman with strict registry config (Ubuntu 26.04 default) and prepare the Quadlet directory.

**Tasks**
- [ ] `apt install podman podman-compose podman-docker`
- [ ] Verify `podman info` runs as the `rob` user without sudo
- [ ] Create `~/.config/containers/systemd/` for Quadlet units
- [ ] Test: pull `docker.io/library/hello-world` (note: fully qualified names mandatory)
- [ ] Configure subuid/subgid if not already set
- [ ] Document image-naming rule in `docs/podman-conventions.md`

**Acceptance criteria**
- Rootless `podman run` succeeds
- A trivial `.container` Quadlet file starts on boot
- Conventions documented

**Labels**: `area:podman` `type:setup` `priority:p1`

---

### Issue: Configure DNS for subdomains

**Description**
Point the planned subdomains at the droplet's reserved IP.

**Tasks**
- [ ] `api.therobyouknow.com` A → reserved IP
- [ ] `app.therobyouknow.com` A → reserved IP
- [ ] `data.therobyouknow.com` A → reserved IP
- [ ] Document TTLs and provider in `docs/dns.md`
- [ ] Verify with `dig` from external host

**Acceptance criteria**
- All three subdomains resolve to the reserved IP
- Caddy can issue certs for each

**Labels**: `area:server` `type:config` `priority:p1`

---

# M2 — Headless Drupal

### Issue: Drupal Containerfile (headless build)

**Description**
A Containerfile (OCI Dockerfile) that builds a Drupal image with Composer, Drush, and the JSON:API + CORS modules pre-installed.

**Tasks**
- [ ] Base on `docker.io/drupal:11-apache` or `php:8.3-apache` + Composer
- [ ] Install Drush globally
- [ ] Add `drupal/jsonapi_extras` and `drupal/simple_oauth` via composer.json
- [ ] Layer build for cacheable composer install
- [ ] Configure Apache for `/var/www/html/web` doc root
- [ ] Bind app on port 80 (Caddy proxies in via 127.0.0.1:8001)

**Acceptance criteria**
- `podman build` succeeds
- Container starts and serves Drupal install page
- Image tagged and pushed manually to ghcr.io for first time

**Labels**: `area:drupal` `type:config` `priority:p1`

---

### Issue: MariaDB container Quadlet

**Description**
Persistent MariaDB instance for Drupal. Rootless, with a named volume for `/var/lib/mysql`.

**Tasks**
- [ ] Create `mariadb-drupal.container` Quadlet unit
- [ ] Use `docker.io/library/mariadb:11.8`
- [ ] Pass `MYSQL_*` env from systemd `EnvironmentFile=` (secret, not committed)
- [ ] Named volume `drupal-db-data` mapped to `/var/lib/mysql`
- [ ] No published port — only Drupal container connects via Podman network

**Acceptance criteria**
- `systemctl --user start mariadb-drupal` succeeds
- Volume survives container restart
- Auto-starts after host reboot

**Labels**: `area:drupal` `area:podman` `type:config` `priority:p1`

---

### Issue: Drupal app Quadlet + first-run install

**Description**
Wire up the Drupal container to MariaDB and complete the initial site install.

**Tasks**
- [ ] Create `drupal-api.container` Quadlet unit
- [ ] `PublishPort=127.0.0.1:8001:80`
- [ ] Volumes: `drupal-files` → `/var/www/html/web/sites/default/files`, `drupal-config-sync` → `/var/www/html/config/sync`
- [ ] Network connection to MariaDB container
- [ ] Run `drush site:install` once via `podman exec`
- [ ] Enable JSON:API, JSON:API Extras, CORS settings in `services.yml`

**Acceptance criteria**
- `curl http://127.0.0.1:8001` returns Drupal output
- `/jsonapi` endpoint returns valid JSON
- CORS allows configured origins

**Labels**: `area:drupal` `priority:p1`

---

### Issue: Caddyfile entry for api.therobyouknow.com

**Description**
Add reverse proxy block for the Drupal API.

**Tasks**
- [ ] Append block to `caddy/Caddyfile`:
  ```caddyfile
  api.therobyouknow.com {
      reverse_proxy 127.0.0.1:8001
      encode gzip zstd
  }
  ```
- [ ] `caddy validate` then `systemctl reload caddy`
- [ ] Verify HTTPS cert issued
- [ ] Test `curl https://api.therobyouknow.com/jsonapi`

**Acceptance criteria**
- Public HTTPS endpoint serves the Drupal API

**Labels**: `area:caddy` `area:drupal` `priority:p1`

---

# M3 — React Frontend

### Issue: React app scaffolding (Vite)

**Description**
A minimal React app that fetches and displays content from the Drupal JSON:API.

**Tasks**
- [ ] `npm create vite@latest react-frontend -- --template react-ts`
- [ ] Add a content list component fetching `/jsonapi/node/article`
- [ ] Configure `.env` with `VITE_API_BASE=https://api.therobyouknow.com`
- [ ] Repo lives separately or as a subdirectory — decide and document

**Acceptance criteria**
- Local `npm run dev` displays articles from the live Drupal API

**Labels**: `area:react` `type:setup` `priority:p2`

---

### Issue: React Containerfile (multi-stage build)

**Description**
Multi-stage build: Node for compilation, then a minimal static server (Caddy or nginx-alpine) for serving.

**Tasks**
- [ ] Stage 1: `node:22-alpine`, `npm ci`, `npm run build`
- [ ] Stage 2: `caddy:alpine` serving `/srv` from build output
- [ ] Or alternative: serve directly from host filesystem via Caddy `root *` (no container)
- [ ] Decide and document the choice

**Acceptance criteria**
- Image < 100 MB
- Container serves built React app
- SPA routing works (try_files fallback to index.html)

**Labels**: `area:react` `type:config` `priority:p2`

---

### Issue: Caddyfile entry for app.therobyouknow.com

**Description**
Serve the React build over HTTPS.

**Tasks**
- [ ] Add Caddyfile block (reverse_proxy or file_server depending on M3.2 decision)
- [ ] Ensure SPA routing falls back to index.html

**Acceptance criteria**
- `https://app.therobyouknow.com` loads the React app
- Routes work on hard refresh

**Labels**: `area:caddy` `area:react` `priority:p2`

---

# M4 — Streamlit App

### Issue: Streamlit Containerfile

**Description**
Containerise a Streamlit app with Pandas and the libraries you'll use for data analysis experiments.

**Tasks**
- [ ] Base on `python:3.12-slim`
- [ ] `requirements.txt` with streamlit, pandas, plotly, numpy, etc.
- [ ] `CMD streamlit run app.py --server.port 8501 --server.address 0.0.0.0 --server.headless true`
- [ ] Document dev pattern: bind-mount source for live reload during development

**Acceptance criteria**
- Container builds and serves a sample app on `localhost:8501`

**Labels**: `area:streamlit` `type:config` `priority:p2`

---

### Issue: Streamlit Quadlet + Caddy proxy with WebSockets

**Description**
Streamlit relies on WebSockets for live updates. Caddy's `reverse_proxy` handles upgrades transparently — this issue documents and verifies that.

**Tasks**
- [ ] Create `streamlit-data.container` Quadlet
- [ ] Add Caddyfile block proxying to `127.0.0.1:8501`
- [ ] Test WebSocket upgrade by interacting with the Streamlit app remotely
- [ ] Document any `header_up` rules if needed (likely none)

**Acceptance criteria**
- Streamlit app fully interactive at `https://data.therobyouknow.com`
- Auto-restart after reboot

**Labels**: `area:streamlit` `area:caddy` `priority:p2`

---

### Issue: Sample Streamlit app showcasing data analysis

**Description**
A first real app demonstrating Pandas analysis from your 2024 course — a portfolio piece, not just a hello world.

**Tasks**
- [ ] Choose a dataset (Kaggle, public-domain, or your course exercises)
- [ ] Build app with file upload, summary stats, charts
- [ ] Add a sidebar with filters
- [ ] Document in repo's `apps/streamlit/README.md`

**Acceptance criteria**
- App live, shareable as a portfolio link

**Labels**: `area:streamlit` `priority:p3`

---

# M5 — Image Registry & CI

### Issue: Set up GitHub Container Registry for project images

**Description**
Use ghcr.io to host built images. Free, private, integrates with GitHub Actions.

**Tasks**
- [ ] Create personal access token (PAT) with `write:packages` scope, OR use GITHUB_TOKEN in Actions
- [ ] Document `podman login ghcr.io` on the server using a deploy token
- [ ] Naming convention: `ghcr.io/therobyouknow/<app>:<tag>`
- [ ] Document in `docs/registry.md`

**Acceptance criteria**
- Manual `podman push` to ghcr.io works from local and from server
- Conventions documented

**Labels**: `area:ci` `type:setup` `priority:p2`

---

### Issue: GitHub Actions workflow — build & push images

**Description**
On commit to main, build container images and push to ghcr.io with both `:latest` and `:<sha>` tags.

**Tasks**
- [ ] `.github/workflows/build-images.yml` per app
- [ ] Use `docker/build-push-action` (works for OCI images consumed by Podman)
- [ ] Cache layers via GitHub Actions cache
- [ ] Tag with both `latest` and short SHA
- [ ] Optional: tag with semver from git tags

**Acceptance criteria**
- A push to main produces a new image in ghcr.io within minutes
- Workflow status badge in repo README

**Labels**: `area:ci` `type:config` `priority:p2`

---

### Issue: Server-side pull-and-restart script

**Description**
A small script the server runs (manually or on webhook) to pull the latest image and restart the relevant Quadlet service.

**Tasks**
- [ ] `scripts/deploy-app.sh <app-name>` that:
  - `podman pull ghcr.io/therobyouknow/<app>:latest`
  - `systemctl --user restart <app>.service`
- [ ] Optional: webhook receiver via Caddy + small handler
- [ ] Document manual deploy flow

**Acceptance criteria**
- One command to deploy a new image version
- Rollback path documented

**Labels**: `area:ci` `type:script` `priority:p2`

---

# M6 — Dev/Prod Data Flow

### Issue: Database export script (prod → backup file)

**Description**
A script to dump the live Drupal DB to a sanitized, gzipped SQL file for local development use.

**Tasks**
- [ ] `scripts/db-pull.sh` runs `drush sql:dump` inside the Drupal container
- [ ] Pipe through `drush sql:sanitize` for any PII before export
- [ ] Output to `~/db-exports/api-YYYYMMDD.sql.gz`
- [ ] Optional: SCP target to local dev machine

**Acceptance criteria**
- Sanitized DB dump produced reliably
- Restorable to a DDEV project

**Labels**: `area:drupal` `type:script` `priority:p2`

---

### Issue: Files sync workflow (prod → local)

**Description**
Pull `sites/default/files` from production to local DDEV without overwriting local changes accidentally.

**Tasks**
- [ ] `scripts/files-pull.sh` using `rsync` over SSH
- [ ] Default to dry-run; require explicit flag for actual sync
- [ ] Document the local destination path

**Acceptance criteria**
- Reliable, idempotent files sync
- Local-only changes not destroyed

**Labels**: `area:drupal` `type:script` `priority:p3`

---

### Issue: DDEV project template for Drupal sites

**Description**
A reusable DDEV configuration that mirrors the production container setup as closely as practical.

**Tasks**
- [ ] PHP version matching production
- [ ] MariaDB version matching production
- [ ] `.ddev/config.yaml` template documented
- [ ] Optional: `.ddev/commands/host/db-import` to ingest exports from M6.1

**Acceptance criteria**
- Fresh `ddev start` + DB import gives a working local site
- Template versioned in repo

**Labels**: `area:drupal` `type:config` `priority:p2`

---

# M7 — Backup & Restore

### Issue: Set up DigitalOcean Spaces and restic

**Description**
Provision an S3-compatible bucket and configure restic to use it for encrypted backups.

**Tasks**
- [ ] Create DO Spaces bucket `therobyouknow-backups` in same region as droplet
- [ ] Generate Spaces access key + secret
- [ ] Install restic on the host
- [ ] Initialise repo: `restic -r s3:... init`
- [ ] Store credentials in `/etc/restic.env` (root-readable only)
- [ ] Document the bucket layout and retention plan

**Acceptance criteria**
- `restic snapshots` runs against the bucket
- Credentials not committed

**Labels**: `area:backup` `type:setup` `priority:p1`

---

### Issue: Backup systemd timer

**Description**
Run nightly backups of databases (via dump) and Drupal files volumes.

**Tasks**
- [ ] `backup.service` runs:
  - `podman exec mariadb-drupal mariadb-dump --all-databases > /var/backups/drupal.sql`
  - `restic backup /var/backups /home/rob/.local/share/containers/storage/volumes`
  - `restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune`
- [ ] `backup.timer` schedules daily at 03:00
- [ ] Email/notify on failure (uptime-kuma push or simple SMTP)

**Acceptance criteria**
- Backups present in Spaces after first scheduled run
- Pruning works (snapshot count stays bounded)

**Labels**: `area:backup` `type:script` `priority:p1`

---

### Issue: Disaster-recovery drill

**Description**
The backup that matters is the one you've successfully restored. This issue exists to be done at least once, then re-done quarterly.

**Tasks**
- [ ] Spin up a fresh test droplet
- [ ] Follow `docs/restore-procedure.md` end to end
- [ ] Time how long it takes
- [ ] Note any gaps in the runbook and fix them
- [ ] Tear down test droplet

**Acceptance criteria**
- Full restore completed from backup only
- Runbook updated with real-world timings and gotchas

**Labels**: `area:backup` `type:investigation` `priority:p1`

---

# M8 — Updates & Maintenance

### Issue: Renovate configuration for container base images

**Description**
Renovate opens PRs when base images, npm/Composer packages, or GitHub Actions versions update.

**Tasks**
- [ ] Install Renovate App on the repo (free for OSS, free tier for private)
- [ ] `renovate.json` with sensible defaults: weekly schedule, group minor/patch, automerge patches
- [ ] Configure for Containerfiles, package.json, composer.json, Actions YAML

**Acceptance criteria**
- Renovate creates a first PR within 24h of install
- Automerge works for patches

**Labels**: `area:ci` `type:config` `priority:p2`

---

### Issue: Drupal core/contrib update workflow

**Description**
Adapt the existing automation scripts (from the previous Claude work) for the containerised setup.

**Tasks**
- [ ] Update `update_modules.sh` to run inside the Drupal container
- [ ] Add a step that runs `drush updb` and `drush cr` after composer update
- [ ] Document in repo `runbooks/drupal-updates.md`

**Acceptance criteria**
- Single command to update + run db updates + clear cache
- Rollback path documented (image SHA + DB backup before update)

**Labels**: `area:drupal` `type:script` `priority:p2`

---

### Issue: Verify reboot resilience

**Description**
The whole stack must come back automatically after `reboot`.

**Tasks**
- [ ] All Quadlet `.container` files have `[Install] WantedBy=default.target`
- [ ] Caddy systemd service enabled
- [ ] Reboot the droplet
- [ ] Verify all subdomains respond within 60s

**Acceptance criteria**
- Hard reboot → full stack online with no manual intervention
- Test result captured in repo

**Labels**: `area:server` `type:investigation` `priority:p1`

---

# M9 — Operations & Continuity

### Issue: Repository README with architecture

**Description**
The README is the front door — make it answer "what is this and how do I work on it?"

**Tasks**
- [ ] Architecture diagram (the one from this roadmap)
- [ ] Directory tour
- [ ] Links to runbooks and ADRs
- [ ] Link to ROADMAP.md

**Acceptance criteria**
- A new collaborator (or future-you) can orient in 5 minutes

**Labels**: `area:docs` `priority:p2`

---

### Issue: Runbooks for common operations

**Description**
Short, specific docs for the things you'll do repeatedly.

**Tasks**
- [ ] `runbooks/deploy-new-image.md`
- [ ] `runbooks/restore-from-backup.md`
- [ ] `runbooks/add-new-subdomain.md`
- [ ] `runbooks/rotate-secrets.md`

**Acceptance criteria**
- Each runbook is < 1 page and tested

**Labels**: `area:docs` `priority:p2`

---

### Issue: Architecture Decision Records (ADRs)

**Description**
Capture the *why* behind choices (Podman over Docker, Caddy over nginx, ghcr over Docker Hub, etc.) so future-you doesn't re-litigate them.

**Tasks**
- [ ] `docs/adr/0001-podman-over-docker.md`
- [ ] `docs/adr/0002-caddy-on-host.md`
- [ ] `docs/adr/0003-ghcr-for-images.md`
- [ ] `docs/adr/0004-restic-for-backups.md`
- [ ] Use the standard ADR template (Context, Decision, Consequences)

**Acceptance criteria**
- 4 ADRs committed
- README links to ADR index

**Labels**: `area:docs` `priority:p3`

---

### Issue: Session handoff document

**Description**
A living `STATUS.md` updated at end of each working session: what's done, what's next, current blocker, decisions taken since last update.

**Tasks**
- [ ] Create `STATUS.md` template
- [ ] Habit: update at end of every Claude session
- [ ] Reference the current open issue at top

**Acceptance criteria**
- Picking up after a 2-week gap takes < 10 minutes to get oriented

**Labels**: `area:docs` `priority:p2`

---

## Working rhythm

- **Active work** lives in GitHub Issues against the current milestone
- **Plan changes** go here in `ROADMAP.md` (PR review your own plan changes)
- **Architectural changes** become ADRs
- **End each session**: update `STATUS.md` with what's next

## Picking up after a break

1. Read `STATUS.md`
2. Check open issues in the current milestone
3. Pull latest changes, `caddy validate`, `systemctl --user status` for sanity
4. Start the next task
