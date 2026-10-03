#!/bin/bash
# Drupal Site Deployment Script
# Usage: ./deploy.sh [domain] [environment] [release_version]
# Example: ./deploy.sh example.com live 2.0.5

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Validate arguments
if [ "$#" -ne 3 ]; then
    print_error "Usage: $0 [domain] [environment] [release_version]"
    print_error "Example: $0 example.com live 2.0.5"
    exit 1
fi

DOMAIN=$1
ENVIRONMENT=$2  # live or staging
RELEASE=$3

# Find the category by searching /var/www/ for the domain directory
CATEGORY=$(basename $(dirname $(find /var/www -maxdepth 2 -mindepth 2 -type d -name "${DOMAIN}" | head -1)) 2>/dev/null)

if [ -z "${CATEGORY}" ]; then
    print_error "Could not find domain '${DOMAIN}' under /var/www/"
    exit 1
fi

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
RELEASE_PATH="${BASE_PATH}/releases/${RELEASE}"
CODE_PATH="${RELEASE_PATH}/code"
ENV_PATH="${BASE_PATH}/deployment_environments/${ENVIRONMENT}"
DOCROOT_LINK="${ENV_PATH}/docroot"

# Validate paths
if [ ! -d "${BASE_PATH}" ]; then
    print_error "Base path does not exist: ${BASE_PATH}"
    exit 1
fi

if [ ! -d "${RELEASE_PATH}" ]; then
    print_error "Release path does not exist: ${RELEASE_PATH}"
    print_error "Run create_release.sh first to create the release folder"
    exit 1
fi

if [ ! -d "${CODE_PATH}" ]; then
    print_error "Code path does not exist: ${CODE_PATH}"
    exit 1
fi

print_status "Starting deployment for ${DOMAIN} (${ENVIRONMENT}) - Release ${RELEASE}"

# Backup current database before deployment
print_status "Backing up database..."
DB_NUMBER=$(readlink "${CODE_PATH}/web/sites/default/settings.local.php" | grep -oP 'settings/\K[0-9]+')
./backup_db.sh ${DOMAIN} ${DB_NUMBER}

# Navigate to code directory
cd "${CODE_PATH}"

# Run composer install (if composer.json exists). Everything up to the symlink
# flip below leaves the live site untouched, so fail here rather than later.
if [ -f "composer.json" ]; then
    if [ -x "./composer" ]; then
        COMPOSER_CMD="./composer"
    elif command -v composer >/dev/null 2>&1; then
        COMPOSER_CMD="composer"
        print_warning "./composer is missing or dangling; using $(command -v composer) instead"
    else
        print_error "No usable composer: ./composer does not resolve and none is on PATH"
        if [ -L "./composer" ]; then
            print_error "./composer -> $(readlink ./composer) (dangling)"
            print_error "If the repository ships its own composer symlink, restore it with: git checkout -- composer"
        fi
        exit 1
    fi
    print_status "Running composer install (${COMPOSER_CMD})..."
    ${COMPOSER_CMD} install --no-dev --optimize-autoloader
fi

# Locate drush now that vendor/ exists, before anything the site can notice.
if [ -x "./drush" ]; then
    DRUSH_CMD="./drush"
elif [ -x "vendor/bin/drush" ]; then
    DRUSH_CMD="vendor/bin/drush"
else
    print_error "No usable drush: ./drush does not resolve and vendor/bin/drush is missing"
    exit 1
fi

# Update the symlink to point to new release
print_status "Updating docroot symlink..."
RELATIVE_PATH="../../releases/${RELEASE}/code/web"
ln -sfn ${RELATIVE_PATH} ${DOCROOT_LINK}

print_status "Symlink updated: ${DOCROOT_LINK} -> ${RELATIVE_PATH}"

# Reload PHP-FPM so OPcache drops the previous release's code. Without this the
# old core/modules kept running after a deploy (seen on staging, Sep 2026).
PHP_FPM_SERVICE=$(systemctl list-units --type=service --state=running --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "${PHP_FPM_SERVICE}" ]; then
    print_status "Reloading ${PHP_FPM_SERVICE} (clears OPcache)..."
    sudo systemctl reload "${PHP_FPM_SERVICE}"
else
    print_warning "No running php-fpm service found; reload it by hand so OPcache does not serve old code"
fi

# Run Drush updates
print_status "Running Drush database updates (${DRUSH_CMD})..."
${DRUSH_CMD} updb -y

print_status "Clearing Drupal cache..."
${DRUSH_CMD} cr

print_status "Deployment completed successfully!"
print_status "Site is now running release ${RELEASE}"
