#!/bin/bash
# Create New Site Structure Script
# Usage: ./create_site_structure.sh [category] [domain]
# Example: ./create_site_structure.sh 05 example.com

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
if [ "$#" -ne 2 ]; then
    print_error "Usage: $0 [category] [domain]"
    print_error "Example: $0 05 example.com"
    exit 1
fi

CATEGORY=$1
DOMAIN=$2

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"

# Check if site already exists
if [ -d "${BASE_PATH}" ]; then
    print_error "Site structure already exists at: ${BASE_PATH}"
    read -p "Do you want to continue anyway? This won't overwrite existing files. (yes/no): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        exit 0
    fi
fi

print_status "Creating site structure for ${DOMAIN} (category: ${CATEGORY})"

# Create main directory structure
print_status "Creating directory structure..."

mkdir -p "${BASE_PATH}/releases"
mkdir -p "${BASE_PATH}/deployment_environments/live/assets/public/files"
mkdir -p "${BASE_PATH}/deployment_environments/staging/assets/public/files"
mkdir -p "${BASE_PATH}/settings/1"
mkdir -p "${BASE_PATH}/settings/2"
mkdir -p "${BASE_PATH}/backups/database"
mkdir -p "${BASE_PATH}/backups/files"

print_status "Created directory structure"

# Create placeholder docroot symlinks (will be updated when first release is deployed)
LIVE_DOCROOT="${BASE_PATH}/deployment_environments/live/docroot"
STAGING_DOCROOT="${BASE_PATH}/deployment_environments/staging/docroot"

if [ ! -L "${LIVE_DOCROOT}" ]; then
    print_status "Creating placeholder live docroot symlink"
    ln -s "../../releases/placeholder/code/web" "${LIVE_DOCROOT}"
fi

if [ ! -L "${STAGING_DOCROOT}" ]; then
    print_status "Creating placeholder staging docroot symlink"
    ln -s "../../releases/placeholder/code/web" "${STAGING_DOCROOT}"
fi

# Create README files in settings directories
cat > "${BASE_PATH}/settings/1/README.md" << EOF
# Database 1 Settings

Place your settings.local.php file here with credentials for database 1.

Example settings.local.php content:

\`\`\`php
<?php
\$databases['default']['default'] = array (
  'database' => 'd${DOMAIN//./_}_1',
  'username' => 'u${DOMAIN//./_}_1',
  'password' => 'your_password_here',
  'host' => 'localhost',
  'port' => '3306',
  'driver' => 'mysql',
);
\`\`\`
EOF

cat > "${BASE_PATH}/settings/2/README.md" << EOF
# Database 2 Settings

Place your settings.local.php file here with credentials for database 2.

Example settings.local.php content:

\`\`\`php
<?php
\$databases['default']['default'] = array (
  'database' => 'd${DOMAIN//./_}_2',
  'username' => 'u${DOMAIN//./_}_2',
  'password' => 'your_password_here',
  'host' => 'localhost',
  'port' => '3306',
  'driver' => 'mysql',
);
\`\`\`
EOF

# Set permissions
print_status "Setting permissions..."
chown -R rob:www-data "${BASE_PATH}"

# Directories: 750 (rwxr-x---)
find "${BASE_PATH}" -type d -exec chmod 750 {} \;

# Files: 640 (rw-r-----)
find "${BASE_PATH}" -type f -exec chmod 640 {} \;

# Public files directory needs to be writable by web server
chmod 770 "${BASE_PATH}/deployment_environments/live/assets/public/files"
chmod 770 "${BASE_PATH}/deployment_environments/staging/assets/public/files"

print_status "Site structure created successfully!"
print_status "Base path: ${BASE_PATH}"
print_status ""
print_status "Next steps:"
print_status "1. Create database(s) using create_database.sh or manually"
print_status "2. Create settings.local.php files in ${BASE_PATH}/settings/1 and/or ${BASE_PATH}/settings/2"
print_status "3. Create Apache vhost configuration using create_vhost.sh"
print_status "4. Create first release using create_release.sh"
print_status ""
print_status "Directory structure:"
tree -L 3 "${BASE_PATH}" 2>/dev/null || ls -la "${BASE_PATH}"
