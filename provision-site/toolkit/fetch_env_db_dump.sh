#!/bin/bash
# Fetch Database Dump by Environment (runs locally)
# SSHes into a remote server, resolves the database from an environment's symlink chain,
# dumps the database, and downloads the file via SCP.
# Usage: ./fetch_env_db_dump.sh [ssh_host] [domain] [environment]
# Example: ./fetch_env_db_dump.sh server03 example.com live

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
if [ "$#" -ne 3 ]; then
    print_error "Usage: $0 [ssh_host] [domain] [environment]"
    print_error "Example: $0 server03 example.com live"
    exit 1
fi

SSH_HOST=$1
DOMAIN=$2
ENVIRONMENT=$3

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

print_status "Connecting to ${SSH_HOST}..."

# Find the category by searching /var/www/ for the domain directory
CATEGORY=$(ssh "${SSH_HOST}" "basename \$(dirname \$(find /var/www -maxdepth 2 -mindepth 2 -type d -name '${DOMAIN}' | head -1)) 2>/dev/null")

if [ -z "${CATEGORY}" ]; then
    print_error "Could not find domain '${DOMAIN}' under /var/www/ on ${SSH_HOST}"
    exit 1
fi

print_status "Found ${DOMAIN} in category: ${CATEGORY}"

# Resolve the settings.local.php path by following the symlink chain on the server
SETTINGS_FILE=$(ssh "${SSH_HOST}" "readlink -f '/var/www/${CATEGORY}/${DOMAIN}/deployment_environments/${ENVIRONMENT}/docroot/sites/default/settings.local.php'")

if [ -z "${SETTINGS_FILE}" ]; then
    print_error "Could not resolve settings.local.php for environment '${ENVIRONMENT}'"
    exit 1
fi

print_status "Resolved settings: ${SETTINGS_FILE}"

# Extract database credentials from settings file on the remote server
DB_NAME=$(ssh "${SSH_HOST}" "grep \"'database'\" '${SETTINGS_FILE}' | sed \"s/.*'database' => '\\([^']*\\)'.*/\\1/\"")
DB_USER=$(ssh "${SSH_HOST}" "grep \"'username'\" '${SETTINGS_FILE}' | sed \"s/.*'username' => '\\([^']*\\)'.*/\\1/\"")
DB_PASS=$(ssh "${SSH_HOST}" "grep \"'password'\" '${SETTINGS_FILE}' | sed \"s/.*'password' => '\\([^']*\\)'.*/\\1/\"")

if [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ] || [ -z "${DB_PASS}" ]; then
    print_error "Could not extract database credentials from ${SETTINGS_FILE}"
    exit 1
fi

REMOTE_DUMP="/tmp/${DB_NAME}_${TIMESTAMP}.sql.gz"

# Resolve local path relative to git root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "${GIT_ROOT}" ]; then
    print_error "Not inside a git repository. Run this from within your project."
    exit 1
fi
LOCAL_DIR="${GIT_ROOT}/databases"
mkdir -p "${LOCAL_DIR}"
LOCAL_FILE="${LOCAL_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"

print_status "Dumping database: ${DB_NAME}"

# Run mysqldump on the remote server
if ! ssh "${SSH_HOST}" "set -o pipefail; mysqldump -u'${DB_USER}' -p'${DB_PASS}' '${DB_NAME}' | gzip > '${REMOTE_DUMP}'"; then
    print_error "mysqldump failed on remote server. Check database credentials and connectivity."
    ssh "${SSH_HOST}" "rm -f '${REMOTE_DUMP}'" 2>/dev/null
    exit 1
fi

# Download the dump file
print_status "Downloading dump file..."
scp "${SSH_HOST}:${REMOTE_DUMP}" "${LOCAL_FILE}"

# Remove the temp file from the server
ssh "${SSH_HOST}" "rm -f '${REMOTE_DUMP}'"

# Check file size
FILE_SIZE=$(stat -f%z "${LOCAL_FILE}" 2>/dev/null || stat -c%s "${LOCAL_FILE}" 2>/dev/null)
if [ "${FILE_SIZE}" -lt 100 ]; then
    print_error "Downloaded dump file is too small (${FILE_SIZE} bytes) - mysqldump likely failed on the server."
    rm -f "${LOCAL_FILE}"
    exit 1
fi
FILE_SIZE_MB=$(echo "scale=2; ${FILE_SIZE}/1048576" | bc)

print_status "Download complete! (${FILE_SIZE_MB} MB)"

echo "${LOCAL_FILE}"
