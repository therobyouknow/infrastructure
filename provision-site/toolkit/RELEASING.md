# Releasing a site: the standard

One way to put code live on every site, decided 2026-11-19. It is the way
selectamixmusic.com has always been deployed and the way
internationalgospelchoir.uk and the taxanotes.net instances are meant to be:
**every deploy is a git tag, a fresh release folder cloned from that tag, and
a symlink flip.** Nothing is ever `git pull`ed into the folder that is live.

Why: a release folder that matches a tag can be reproduced, compared and
rolled back by name (`update_symlink`), and a tag in the repository says
exactly what is running. A folder that has had twenty pulls (what
thesolentmetropolitan.com's `0.3` had grown into) can say none of that, and
the "pull, forget composer install, serve old core for a week" failure of
September 2026 cannot happen when every release is a clean checkout that
`deploy` installs from the lock file.

## The release, step by step

Locally, when the work is on `main`:

```bash
git tag -a 0.3.1 -m "0.3.1"       # see "Version numbers" and "Tag style" below
git push origin main 0.3.1
```

On the server, one command:

```bash
release thesolentmetropolitan.com live 0.3.1
```

`release` (toolkit `release.sh`) prints its plan, asks once, then runs:

1. `create_release` with the repository and the tag. The repository URL is
   taken from the release currently live; the tag must exist on the remote or
   the script stops, so a mistyped version cannot quietly deploy the tip of
   `main` (which `create_release` on its own would do).
2. The two symlinks every release needs: `settings.local.php` to the same
   `settings/N/` the current release uses (override with `-s N`), and
   `files` to the environment's `assets/public/files`.
3. `deploy`: database backup, `composer install --no-dev`, docroot symlink
   flip, OPcache reset (php-fpm reload, and an Apache reload on a mod_php
   server such as server03), `drush updb`, `drush cr`.
4. `drush config:import` if `drush config:status` shows differences, then
   another cache rebuild. Sites with no config sync directory are skipped.
5. Prints the git describe and Drupal version now serving, and the rollback
   command.

A staging run is the same with `staging` as the environment. A branch can be
deployed to staging by naming it as the fifth argument; `release` warns if
that is tried on live, but does not refuse, because occasionally a hotfix
branch is the right thing. Tag it afterwards.

Rollback, when the new release misbehaves:

```bash
update_symlink thesolentmetropolitan.com live 0.3      # points docroot back
sudo systemctl reload apache2                           # server03 (mod_php)
sudo systemctl reload php8.5-fpm                        # server04 (fpm)
drush_run thesolentmetropolitan.com live cr
# and, only if updb changed the schema:
restore_db thesolentmetropolitan.com 1 /var/www/09/thesolentmetropolitan.com/backups/database/<the dump deploy took>
```

## Version numbers

Semantic-ish, three parts, small and frequent: `0.3.1`, `0.3.2`, `0.3.3`.
The third number goes up for every release; bump the second for a batch of
visible new work; the first for a rebuild (the 2.x of the new ligchoir.com
theme). Small numbers are fine: a release is a release even when it is one
commit. A staging-only build of unmerged work is `X.Y.Z-staging` (the
repository stays untagged until it merges; see ligchoir's history for the
pattern).

## Tag style

Tag names are bare: `0.3.1`, not `v0.3.1`. The folder under `releases/` is
then the tag, and `create_release` finds it without being told.
selectamixmusic.com already uses `v0.1.2`; it keeps the `v` (mixing styles in
one repository is worse than either style), and `release` tries both forms.

## Where each site stands (2026-11-19)

| Site | Server | Path | Live settings | Repository | State | Next release |
|---|---|---|---|---|---|---|
| internationalgospelchoir.uk (ligchoir) | server03 | `/var/www/05/` | `settings/2` (dligc2) | `github.com/ligchoir/ligchoir` main | Fresh folder per release since 2.0; tags stopped at `2.0.3`, releases 2.0.4 to 2.0.15 are untagged commits of main | `2.0.16`, tagged |
| ligchoir.com (new theme, Drupal 11) | server04 | `/var/www/05/` | `settings/1` | same repo, branch `feat/new-theme` | Review builds `2.1.0-review`, `-review2`, `-review3` | merge, tag `2.1.0` at go-live |
| thesolentmetropolitan.com | server03 | `/var/www/09/` | `settings/1`; staging `settings/2` | `github.com/thesolentmetropolitan/thesolentmetropolitan.com` main | One folder `0.3` with 22 pulls into it; repo tags are descriptive names, not versions | `0.3.1`, tagged |
| taxanotes.org (web-community) | server04 | `/var/www/09/` | `settings/1` | `github.com/taxanotes/web-community` | Fresh folder per release (1.1.0 to 1.6.0) but each cloned from a feature branch, no tags, main not updated | merge to main, tag `1.6.1` |
| selectamixmusic.com | server04 | `/var/www/09/` | `settings/1` | `github.com/selectamixmusic/web-explorer` main | Already the standard: `v0.1.0` to `v0.1.2`, detached at the tag | `v0.1.3` |
| anthophila, mormyrids, myriatrix .taxanotes.net | server04 | `/var/www/09/` | `settings/1` | `github.com/taxanotes/web-explorer`, tags `0.5.0` to `0.8.1` | Tag per release already. Deployed by that repo's `scripts/hosting/new-instance.sh`, which calls `create_release`; its tarball mode leaves no `.git` in the folder, so `release` cannot learn the repository from it | keep using `new-instance.sh <slug> <version> --git <url> --ref <tag>` |
| ligc.choirtrack.net | server04 | `/var/www/09/` | `settings/1` | `github.com/choirtrack/web-distro-instance` branch `feat/drupal-11-server04` | One release `1.0.0` from a branch, no tag | merge, tag `1.0.1` |

Oddities seen while taking this inventory, to resolve separately:

- internationalgospelchoir.uk **staging** (`2.0.11-staging`) links `settings/2`,
  the live database, not `settings/1` (dligc). Staging edits land on live.
- server03 still has a `/var/www/09/selectamixmusic.com/releases/0.1` from
  before the site moved to server04, with no docroot pointing at it.
- `thesolentmetropolitan.com` staging has `0.3-staging` from a branch checked
  out in March; it is a long way behind live.

## The first release under the standard, per site

Nothing needs moving. The next release of each site is just made with
`release`, and the old folder stays for rollback:

```bash
# thesolentmetropolitan.com: tag main as 0.3.1 locally, push, then
release thesolentmetropolitan.com live 0.3.1
# taxanotes.org: merge the current branch to main, tag 1.6.1, push, then
release taxanotes.org live 1.6.1
# internationalgospelchoir.uk: tag main as 2.0.16, push, then
release internationalgospelchoir.uk live 2.0.16
```

`release` reads the repository URL and settings number from the folder that
is live, so the first run on each site needs no extra arguments as long as
that folder has a `.git` (every one above does). Check the plan it prints
before answering `yes`; after that first run, trust it.

## What the standard does not cover

- Content and files move the other way (server to local) with
  `fetch_and_import_env_db.sh` and `sync_files.sh pull`; a release never
  touches `assets/`.
- A release that uninstalls modules needs its entities deleted before the
  config import; ligchoir's `docs/devops/README.txt` has the recipe. Run
  `release` and, when `cim` fails, finish by hand in the release folder.
- Old release folders are not pruned. Delete by hand when disk is short,
  never the one live or the one before it.
