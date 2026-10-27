# Drupal CMS + Canvas playbook

How to build a small business or community site on **Drupal CMS 2** (Drupal
11) with the **Canvas** page builder and the **Mercury** theme, locally in
DDEV, with pages and content types created by Drush scripts so the build can
be repeated. Hosting is covered by the [provision-site toolkit](../../provision-site/toolkit/README.md);
[NEW-SITE-CHECKLIST.md](NEW-SITE-CHECKLIST.md) links the two.

Used for three sites so far (October 2026), built with AI assistance (Claude).

| File | What it is |
|---|---|
| [lib/CanvasTree.php](lib/CanvasTree.php) | Shared helper: builds Canvas pages (hero, sections, cards, Views blocks, webform), menu links, Mercury header and footer |
| [templates/setup-pages.php](templates/setup-pages.php) | Example pages script using the helper |
| [templates/setup-content-type.php](templates/setup-content-type.php) | Content type + vocabulary + view with card blocks per term |
| [templates/server-provision.sh](templates/server-provision.sh) | Root setup on the server: folders, database, vhost, HTTP auth, certificate |

## 1. Create the project

```bash
mkdir example.com && cd example.com
ddev config --project-type=drupal11 --docroot=web --project-name=example-com --php-version=8.3
ddev start
ddev composer create-project drupal/cms --no-interaction
```

`create-project` replaces `.ddev/config.yaml` with Drupal CMS's own, which has
no `name:` or `php_version:`. Put them back at the top, or the next `ddev`
command fails with "this project root already contains a project named ...":

```yaml
name: example-com
type: drupal11
php_version: "8.3"
```

Then `ddev restart`.

## 2. Recipes, Drush and PHP version

```bash
ddev composer require drupal/drupal_cms_starter drupal/drupal_cms_forms --update-with-all-dependencies
ddev composer require drush/drush           # into require, not require-dev
ddev composer config platform.php 8.3.6     # match the server's PHP
ddev composer update --with-all-dependencies
```

- **Drush in `require`**: releases are installed with `composer install --no-dev`,
  and the toolkit's `deploy` and `drush_run` need Drush on the server. If it
  is still listed under `require-dev`, remove it from there.
- **PHP platform**: DDEV defaults to a newer PHP than many servers. Without
  the pin, the lock file can pick packages (e.g. `symfony/css-selector` 8.x)
  that refuse to install on PHP 8.3.

## 3. Install

```bash
ddev drush site:install /var/www/html/recipes/drupal_cms_starter --site-name="Example" --yes
ddev drush recipe /var/www/html/recipes/drupal_cms_forms
```

The starter recipe gives you Canvas, Mercury, the `page` content type, media
types, SEO tools, Klaro cookie consent, Gin admin and an editor role. The
forms recipe adds Webform with a `contact_form`, Honeypot and ALTCHA.

The install prints an admin password. Use `ddev drush uli` instead of
copying it anywhere.

## 4. Config in Git

In `web/sites/default/settings.php`:

```php
$settings['config_sync_directory'] = '../config/sync';
```

and at the end, so each server keeps its database, hash salt and trusted
hosts out of Git:

```php
if (file_exists($app_root . '/' . $site_path . '/settings.local.php')) {
  include $app_root . '/' . $site_path . '/settings.local.php';
}
```

Add to `.gitignore`: `/.ddev/db_snapshots`, `*.sql`, `*.sql.gz` (the
Drupal CMS one already ignores `vendor`, `web/core`, contrib and `files`).

```bash
ddev drush cex -y
git init -b main && git add -A && git commit -m "Initial site: Drupal CMS 2 with Canvas"
```

## 5. Content types and pages

Copy `lib/CanvasTree.php` to `scripts/lib/` and the templates you need to
`scripts/`, edit, then run them in order:

```bash
ddev drush php:script scripts/setup-content-type.php
ddev drush php:script scripts/setup-pages.php
ddev drush cex -y
```

Re-running a pages script rebuilds every page it lists, so once someone has
edited a page in Canvas, change it there (or take it out of the script).

### Things that trip up page scripts

- **Every prop with a default must be present.** `CanvasTree::add()` fills
  them in from the component's definition; Canvas validation fails otherwise.
- **Views blocks need `items_per_page` of 1 or more.** 0 ("all") is rejected
  by Canvas validation even though Views accepts it; pass e.g. 24.
- **Validate before saving.** `canvas_save_pages()` prints violations and
  skips that page rather than saving a broken one.
- **Header and footer are not pages.** They live in the `theme_mercury`
  page variant; use `canvas_set_header_footer()`.
- **Icons** are [Phosphor](https://phosphoricons.com) names (`drop`,
  `lifebuoy`, `paint-roller`). An unknown name renders nothing rather than
  failing.
- **The `page` content type uses a Canvas content template** for its full
  view. New content types don't, so their own pages render with Mercury's
  plain node template. Fine for card-only content; for detail pages, build a
  content template in Canvas.

## 6. Contact form and mail

A new server usually has no working mail transport, and Webform's email
handler then shows visitors an error. The pages template turns that handler
off and purges submissions after 180 days (they are still saved and visible
under Structure → Webforms → Results). Once SMTP is set up (e.g. Zoho, with
MX/SPF/DKIM records), configure it under Symfony Mailer Lite and re-enable
the handler.

## 7. Checking it locally

The Claude desktop app's built-in browser blocks the site's CSS on
`*.ddev.site` (`ERR_BLOCKED_BY_CLIENT`), so pages look unstyled there. Use a
normal browser, or headless Chrome for screenshots:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --ignore-certificate-errors --hide-scrollbars --window-size=1280,2400 \
  --screenshot=home.png https://example-com.ddev.site/
```

## 8. Hosting

See [NEW-SITE-CHECKLIST.md](NEW-SITE-CHECKLIST.md).
