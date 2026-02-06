# Drupal Site Management Scripts

A collection of bash scripts to automate management of Drupal 10/11 sites on DigitalOcean.

## Overview

These scripts help you manage multiple Drupal sites with a structured deployment workflow including:
- Site structure creation
- Release management
- Database backups and restores
- Code deployment
- Drush command execution
- Apache vhost configuration

## Directory Structure

Each site follows this structure:
```
/var/www/[category]/[domain]/
├── releases/
│   └── [version]/
│       └── code/
│           ├── web/
│           ├── composer
│           └── drush
├── deployment_environments/
│   ├── live/
│   │   ├── docroot -> ../../releases/[version]/code/web
│   │   └── assets/public/files/
│   └── staging/
│       ├── docroot -> ../../releases/[version]/code/web
│       └── assets/public/files/
├── settings/
│   ├── 1/
│   │   └── settings.local.php
│   └── 2/
│       └── settings.local.php
└── backups/
    ├── database/
    └── files/
```

## Installation

1. Copy all scripts to a directory on your server (e.g., `/home/rob/scripts/`)
2. Make all scripts executable:
   ```bash
   chmod +x *.sh
   ```

## Scripts Overview

### 1. create_site_structure.sh
Creates the complete directory structure for a new site.

**Usage:**
```bash
./create_site_structure.sh [category] [domain]
```

**Example:**
```bash
./create_site_structure.sh 05 example.com
```

**What it does:**
- Creates releases, deployment_environments, settings, and backups directories
- Sets up placeholder symlinks
- Creates README files in settings directories
- Sets proper permissions (rob:www-data)

### 2. create_database.sh
Generates MySQL commands and settings.local.php configuration for a new database.

**Usage:**
```bash
./create_database.sh [domain] [db_number]
```

**Example:**
```bash
./create_database.sh example.com 1
```

**What it does:**
- Generates database name, username, and secure password
- Creates SQL commands to set up the database
- Provides settings.local.php configuration
- Optionally executes the SQL commands

### 3. create_vhost.sh
Creates Apache virtual host configuration files.

**Usage:**
```bash
./create_vhost.sh [category] [domain] [environment]
```

**Examples:**
```bash
./create_vhost.sh 05 example.com live
./create_vhost.sh 05 example.com staging
```

**What it does:**
- Creates Apache vhost configuration file
- Sets up ServerName (staging.domain for staging)
- Optionally enables the site and reloads Apache
- Provides instructions for SSL setup with certbot

### 4. create_release.sh
Creates a new release directory and optionally clones code from git.

**Usage:**
```bash
./create_release.sh [category] [domain] [release_version] [git_repo_url]
```

**Examples:**
```bash
./create_release.sh 05 example.com 2.0.5 https://github.com/user/repo.git
./create_release.sh 05 example.com 2.0.6
```

**What it does:**
- Creates release directory structure
- Clones git repository (if provided)
- Sets up Drush and Composer symlinks
- Creates settings.local.php symlink (database 2 by default)
- Sets proper permissions

### 5. deploy.sh
Full deployment script that backs up database, updates symlink, and runs Drush updates.

**Usage:**
```bash
./deploy.sh [category] [domain] [environment] [release_version]
```

**Examples:**
```bash
./deploy.sh 05 example.com live 2.0.5
./deploy.sh 05 example.com staging 2.0.6
```

**What it does:**
- Backs up current database
- Runs composer install
- Updates docroot symlink to new release
- Runs drush updb (database updates)
- Runs drush cr (cache rebuild)

### 6. update_symlink.sh
Quick symlink update without running database updates or cache rebuilds.

**Usage:**
```bash
./update_symlink.sh [category] [domain] [environment] [release_version]
```

**Example:**
```bash
./update_symlink.sh 05 example.com live 2.0.5
```

**What it does:**
- Shows current symlink target
- Updates symlink to point to specified release
- Verifies the new symlink is working

### 7. backup_db.sh
Backs up a database to a compressed SQL file.

**Usage:**
```bash
./backup_db.sh [category] [domain] [db_number]
```

**Example:**
```bash
./backup_db.sh 05 example.com 1
```

**What it does:**
- Extracts credentials from settings.local.php
- Creates timestamped backup file
- Compresses backup with gzip
- Maintains only last 10 backups
- Sets secure permissions

### 8. restore_db.sh
Restores a database from a backup file.

**Usage:**
```bash
./restore_db.sh [category] [domain] [db_number] [backup_file]
```

**Examples:**
```bash
./restore_db.sh 05 example.com 1
./restore_db.sh 05 example.com 1 /var/www/05/example.com/backups/database/dmysite_20240101_120000.sql.gz
```

**What it does:**
- Lists available backups if no file specified
- Creates safety backup before restore
- Restores database from backup file
- Handles both gzipped and plain SQL files

### 9. drush_run.sh
Helper script to run Drush commands on any site/environment.

**Usage:**
```bash
./drush_run.sh [category] [domain] [environment] [drush_command]
```

**Examples:**
```bash
./drush_run.sh 05 example.com live "status"
./drush_run.sh 05 example.com live "updb -y"
./drush_run.sh 05 example.com staging "cr"
./drush_run.sh 05 example.com live "config:export -y"
```

**What it does:**
- Locates the correct code path for the environment
- Runs any Drush command in the proper context

## Complete Workflow: Setting Up a New Site

Here's the typical workflow for setting up a new Drupal site:

```bash
# 1. Create site structure
./create_site_structure.sh 05 example.com

# 2. Create database
./create_database.sh example.com 1

# 3. Manually create settings.local.php
# Copy the output from step 2 into:
# /var/www/05/example.com/settings/1/settings.local.php

# 4. Create vhost configurations
./create_vhost.sh 05 example.com live
./create_vhost.sh 05 example.com staging

# 5. Set up DNS for the domains
# Configure example.com and staging.example.com to point to your server

# 6. Run certbot for SSL (after DNS propagates)
sudo certbot --apache -d example.com
sudo certbot --apache -d staging.example.com

# 7. Create first release
./create_release.sh 05 example.com 1.0.0 https://github.com/user/repo.git

# 8. Set up files symlink
cd /var/www/05/example.com/releases/1.0.0/code/web/sites/default
ln -sf ../../../../../../deployment_environments/live/assets/public/files files

# 9. Run composer install
cd /var/www/05/example.com/releases/1.0.0/code
./composer install

# 10. Import database or install Drupal
# Option A: Import existing database
./restore_db.sh 05 example.com 1 /path/to/backup.sql.gz

# Option B: Install fresh Drupal
./drush_run.sh 05 example.com live "site:install standard --account-name=admin --account-pass=admin"

# 11. Deploy to live
./deploy.sh 05 example.com live 1.0.0
```

## Workflow: Deploying a New Release

```bash
# 1. Create new release
./create_release.sh 05 example.com 2.0.5 https://github.com/user/repo.git

# 2. Set up files symlink for staging
cd /var/www/05/example.com/releases/2.0.5/code/web/sites/default
ln -sf ../../../../../../deployment_environments/staging/assets/public/files files

# 3. Deploy to staging for testing
./deploy.sh 05 example.com staging 2.0.5

# 4. Test the staging site
# Visit staging.example.com and verify everything works

# 5. If all good, point live to the same release
./deploy.sh 05 example.com live 2.0.5

# Alternative: Just update symlink without running updates
./update_symlink.sh 05 example.com live 2.0.5
```

## Workflow: Updating Code in Existing Release

```bash
# 1. Navigate to release code directory
cd /var/www/05/example.com/releases/2.0.5/code

# 2. Pull latest changes
git pull

# 3. Update dependencies if needed
./composer install --no-dev --optimize-autoloader

# 4. Run database updates and clear cache
./drush updb -y
./drush cr

# Or use the drush_run helper:
./drush_run.sh 05 example.com live "updb -y"
./drush_run.sh 05 example.com live "cr"
```

## Tips and Best Practices

1. **Always test on staging first** - Deploy to staging, test thoroughly, then promote to live
2. **Backups are automatic** - deploy.sh creates a database backup before each deployment
3. **Keep releases** - Don't delete old release folders immediately; they allow quick rollbacks
4. **Database numbering** - Use database 1 for staging, database 2 for live (or vice versa)
5. **Files directory** - Each environment (live/staging) has its own files directory
6. **Permissions** - Scripts set rob:www-data with 750/640 permissions automatically
7. **Symlink updates** - Use update_symlink.sh for quick rollbacks without running updates

## Troubleshooting

### Symlink Issues
Check symlink targets:
```bash
ls -la /var/www/05/example.com/deployment_environments/live/
```

### Permission Issues
Reset permissions:
```bash
cd /var/www/05/example.com
sudo chown -R rob:www-data .
sudo find . -type d -exec chmod 750 {} \;
sudo find . -type f -exec chmod 640 {} \;
sudo chmod 770 deployment_environments/*/assets/public/files
```

### Database Connection Issues
Verify settings.local.php credentials match database:
```bash
cat /var/www/05/example.com/settings/1/settings.local.php
mysql -u[username] -p[password] [database]
```

### Drush Not Found
Check symlinks in code directory:
```bash
cd /var/www/05/example.com/releases/2.0.5/code
ls -la drush composer
```

## Security Notes

- All scripts require appropriate sudo/user permissions
- Database passwords are stored in settings.local.php with 640 permissions
- Backup files are created with 640 permissions (rob:www-data)
- Scripts validate paths before executing destructive operations
- Database restores require explicit confirmation

## Customization

These scripts can be customized by editing the following variables at the top of each script:
- BASE_PATH patterns
- Permission settings (chmod values)
- Backup retention policies
- Default database numbers

## Support

For issues or questions, check:
1. Script output messages (colored for clarity)
2. Apache error logs: `/var/log/apache2/error.log`
3. Apache access logs: `/var/log/apache2/access.log`
4. Drupal logs via Drush: `./drush_run.sh 05 example.com live "watchdog:show"`
