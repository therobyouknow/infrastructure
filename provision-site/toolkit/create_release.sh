#!/bin/bash
# Create New Release Script
# Usage: ./create_release.sh [category] [domain] [release_version] [git_repo_url]
# Example: ./create_release.sh 05 example.com 2.0.5 https://github.com/user/repo.git

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
if [ "$#" -lt 3 ]; then
    print_error "Usage: $0 [category] [domain] [release_version] [git_repo_url]"
    print_error "Example: $0 05 example.com 2.0.5 https://github.com/user/repo.git"
    print_error "Git repo URL is optional if you want to clone code"
    exit 1
fi

CATEGORY=$1
DOMAIN=$2
RELEASE=$3
GIT_REPO=$4

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
RELEASES_PATH="${BASE_PATH}/releases"
RELEASE_PATH="${RELEASES_PATH}/${RELEASE}"
CODE_PATH="${RELEASE_PATH}/code"

# Validate base path exists
if [ ! -d "${BASE_PATH}" ]; then
    print_error "Base path does not exist: ${BASE_PATH}"
    print_error "Run create_site_structure.sh first"
    exit 1
fi

# Check if release already exists
if [ -d "${RELEASE_PATH}" ]; then
    print_error "Release ${RELEASE} already exists at: ${RELEASE_PATH}"
    exit 1
fi

print_status "Creating new release: ${RELEASE} for ${DOMAIN}"

# Create release directory structure
mkdir -p "${RELEASE_PATH}"
print_status "Created release directory: ${RELEASE_PATH}"

# Clone or create code directory
if [ -n "${GIT_REPO}" ]; then
    print_status "Cloning repository from: ${GIT_REPO}"
    git clone "${GIT_REPO}" "${CODE_PATH}"
    
    # Checkout specific tag if release looks like a tag
    cd "${CODE_PATH}"
    if git rev-parse "v${RELEASE}" >/dev/null 2>&1; then
        print_status "Checking out tag: v${RELEASE}"
        git checkout "v${RELEASE}"
    elif git rev-parse "${RELEASE}" >/dev/null 2>&1; then
        print_status "Checking out tag: ${RELEASE}"
        git checkout "${RELEASE}"
    else
        print_warning "Tag ${RELEASE} not found, staying on default branch"
    fi
else
    print_status "Creating empty code directory"
    mkdir -p "${CODE_PATH}"
fi

# Set up symlinks for Drush and Composer
cd "${CODE_PATH}"

print_status "Setting up Drush symlink..."
if [ -f "vendor/drush/drush/drush" ]; then
    ln -sf vendor/drush/drush/drush drush
    print_status "Drush symlink created"
else
    print_warning "Drush not found in vendor/drush/drush/drush"
    print_warning "You may need to run composer install first"
fi

print_status "Setting up Composer symlink..."
COMPOSER_PATH="${BASE_PATH}/../../tools/dev/phpcomposer/composer.phar"
if [ -f "${COMPOSER_PATH}" ]; then
    # Calculate relative path to composer
    RELATIVE_COMPOSER="../../../../../../tools/dev/phpcomposer/composer.phar"
    ln -sf "${RELATIVE_COMPOSER}" composer
    print_status "Composer symlink created"
else
    print_warning "Composer not found at: ${COMPOSER_PATH}"
fi

# Set up settings.local.php symlink (database 2 by default, can be changed later)
print_status "Setting up settings.local.php symlink (database 2)..."
WEB_DEFAULT_PATH="${CODE_PATH}/web/sites/default"
if [ -d "${WEB_DEFAULT_PATH}" ]; then
    SETTINGS_SYMLINK="${WEB_DEFAULT_PATH}/settings.local.php"
    RELATIVE_SETTINGS="../../../../../../settings/2/settings.local.php"
    ln -sf "${RELATIVE_SETTINGS}" "${SETTINGS_SYMLINK}"
    print_status "Settings symlink created"
else
    print_warning "web/sites/default directory not found"
fi

# Set permissions
print_status "Setting permissions..."
chown -R rob:www-data "${RELEASE_PATH}"
find "${RELEASE_PATH}" -type d -exec chmod 750 {} \;
find "${RELEASE_PATH}" -type f -exec chmod 640 {} \;

# Make scripts executable if they exist
if [ -f "${CODE_PATH}/drush" ]; then
    chmod 750 "${CODE_PATH}/drush"
fi
if [ -f "${CODE_PATH}/composer" ]; then
    chmod 750 "${CODE_PATH}/composer"
fi

print_status "Release ${RELEASE} created successfully!"
print_status "Location: ${RELEASE_PATH}"
print_status ""
print_status "Next steps:"
print_status "1. If needed, update the database number symlink in web/sites/default/settings.local.php"
print_status "2. Set up the files symlink: cd ${CODE_PATH}/web/sites/default && ln -sf ../../../../../../deployment_environments/live/assets/public/files files"
print_status "3. Run composer install: cd ${CODE_PATH} && ./composer install"
print_status "4. Deploy to environment: ./deploy.sh ${CATEGORY} ${DOMAIN} [live|staging] ${RELEASE}"
