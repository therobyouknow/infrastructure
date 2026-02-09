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

# Run composer install (if composer.json exists)
if [ -f "composer.json" ]; then
    print_status "Running composer install..."
    ./composer install --no-dev --optimize-autoloader
fi

# Update the symlink to point to new release
print_status "Updating docroot symlink..."
RELATIVE_PATH="../../releases/${RELEASE}/code/web"
ln -sfn ${RELATIVE_PATH} ${DOCROOT_LINK}

print_status "Symlink updated: ${DOCROOT_LINK} -> ${RELATIVE_PATH}"

# Run Drush updates
print_status "Running Drush database updates..."
./drush updb -y

print_status "Clearing Drupal cache..."
./drush cr

print_status "Deployment completed successfully!"
print_status "Site is now running release ${RELEASE}"
