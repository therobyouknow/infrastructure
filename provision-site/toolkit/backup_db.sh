#!/bin/bash
# Database Backup Script
# Usage: ./backup_db.sh [domain] [db_number]
# Example: ./backup_db.sh example.com 1

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate arguments
if [ "$#" -ne 2 ]; then
    print_error "Usage: $0 [domain] [db_number]"
    print_error "Example: $0 example.com 1"
    exit 1
fi

DOMAIN=$1
DB_NUMBER=$2

# Find the category by searching /var/www/ for the domain directory
CATEGORY=$(basename $(dirname $(find /var/www -maxdepth 2 -mindepth 2 -type d -name "${DOMAIN}" | head -1)) 2>/dev/null)

if [ -z "${CATEGORY}" ]; then
    print_error "Could not find domain '${DOMAIN}' under /var/www/"
    exit 1
fi

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
SETTINGS_FILE="${BASE_PATH}/settings/${DB_NUMBER}/settings.local.php"
BACKUP_DIR="${BASE_PATH}/backups/database"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Validate settings file exists
if [ ! -f "${SETTINGS_FILE}" ]; then
    print_error "Settings file not found: ${SETTINGS_FILE}"
    exit 1
fi

# Extract database credentials from settings file
DB_NAME=$(grep "'database'" "${SETTINGS_FILE}" | sed "s/.*'database' => '\([^']*\)'.*/\1/")
DB_USER=$(grep "'username'" "${SETTINGS_FILE}" | sed "s/.*'username' => '\([^']*\)'.*/\1/")
DB_PASS=$(grep "'password'" "${SETTINGS_FILE}" | sed "s/.*'password' => '\([^']*\)'.*/\1/")

if [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ] || [ -z "${DB_PASS}" ]; then
    print_error "Could not extract database credentials from settings file"
    exit 1
fi

# Create backup filename with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"

print_status "Backing up database: ${DB_NAME}"
print_status "Backup location: ${BACKUP_FILE}"

# Perform backup
mysqldump -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" | gzip > "${BACKUP_FILE}"

# Set permissions
chmod 640 "${BACKUP_FILE}"

# Check file size
FILE_SIZE=$(stat -f%z "${BACKUP_FILE}" 2>/dev/null || stat -c%s "${BACKUP_FILE}" 2>/dev/null)
FILE_SIZE_MB=$(echo "scale=2; ${FILE_SIZE}/1048576" | bc)

print_status "Backup completed successfully!"
print_status "File size: ${FILE_SIZE_MB} MB"

# Optional: Keep only last 10 backups
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/${DB_NAME}_*.sql.gz 2>/dev/null | wc -l)
if [ ${BACKUP_COUNT} -gt 10 ]; then
    print_status "Removing old backups (keeping last 10)..."
    ls -1t "${BACKUP_DIR}"/${DB_NAME}_*.sql.gz | tail -n +11 | xargs rm -f
fi

echo "${BACKUP_FILE}"
