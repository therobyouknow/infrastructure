#!/bin/bash
# Database Restore Script
# Usage: ./restore_db.sh [category] [domain] [db_number] [backup_file]
# Example: ./restore_db.sh 05 example.com 1 /var/www/05/example.com/backups/database/dmysite_20240101_120000.sql.gz

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
    print_error "Usage: $0 [category] [domain] [db_number] [backup_file]"
    print_error "Example: $0 05 example.com 1 /path/to/backup.sql.gz"
    print_error "If backup_file is not provided, you'll be shown a list to choose from"
    exit 1
fi

CATEGORY=$1
DOMAIN=$2
DB_NUMBER=$3
BACKUP_FILE=$4

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
SETTINGS_FILE="${BASE_PATH}/settings/${DB_NUMBER}/settings.local.php"
BACKUP_DIR="${BASE_PATH}/backups/database"

# Validate settings file exists
if [ ! -f "${SETTINGS_FILE}" ]; then
    print_error "Settings file not found: ${SETTINGS_FILE}"
    exit 1
fi

# Extract database credentials
DB_NAME=$(grep "'database'" "${SETTINGS_FILE}" | sed "s/.*'database' => '\([^']*\)'.*/\1/")
DB_USER=$(grep "'username'" "${SETTINGS_FILE}" | sed "s/.*'username' => '\([^']*\)'.*/\1/")
DB_PASS=$(grep "'password'" "${SETTINGS_FILE}" | sed "s/.*'password' => '\([^']*\)'.*/\1/")

if [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ] || [ -z "${DB_PASS}" ]; then
    print_error "Could not extract database credentials from settings file"
    exit 1
fi

# If no backup file specified, list available backups
if [ -z "${BACKUP_FILE}" ]; then
    print_status "Available backups for ${DB_NAME}:"
    echo ""
    ls -lth "${BACKUP_DIR}"/${DB_NAME}_*.sql.gz 2>/dev/null || {
        print_error "No backups found in ${BACKUP_DIR}"
        exit 1
    }
    echo ""
    print_error "Please specify a backup file path as the 4th argument"
    exit 1
fi

# Validate backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    print_error "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

print_warning "WARNING: This will OVERWRITE the current database: ${DB_NAME}"
print_warning "A backup will be created before restoring"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
    print_status "Restore cancelled"
    exit 0
fi

# Backup current database before restore
print_status "Creating safety backup of current database..."
SAFETY_BACKUP="${BACKUP_DIR}/${DB_NAME}_pre_restore_$(date +"%Y%m%d_%H%M%S").sql.gz"
mysqldump -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" | gzip > "${SAFETY_BACKUP}"
chmod 640 "${SAFETY_BACKUP}"
print_status "Safety backup created: ${SAFETY_BACKUP}"

# Restore database
print_status "Restoring database from: ${BACKUP_FILE}"

# Check if file is gzipped
if [[ "${BACKUP_FILE}" == *.gz ]]; then
    gunzip < "${BACKUP_FILE}" | mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}"
else
    mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "${BACKUP_FILE}"
fi

print_status "Database restore completed successfully!"
print_status "Database ${DB_NAME} has been restored from ${BACKUP_FILE}"
