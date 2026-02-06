#!/bin/bash
# Create Database Script
# Usage: ./create_database.sh [domain] [db_number]
# Example: ./create_database.sh example.com 1

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
    print_error "Usage: $0 [domain] [db_number]"
    print_error "Example: $0 example.com 1"
    exit 1
fi

DOMAIN=$1
DB_NUMBER=$2

# Create database name and username from domain
# Replace dots and dashes with underscores
CLEAN_DOMAIN=$(echo "${DOMAIN}" | sed 's/[.-]/_/g')
DB_NAME="d${CLEAN_DOMAIN}_${DB_NUMBER}"
DB_USER="u${CLEAN_DOMAIN}_${DB_NUMBER}"

# Generate a random password
DB_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-20)

print_status "Creating database for ${DOMAIN}"
print_status "Database name: ${DB_NAME}"
print_status "Database user: ${DB_USER}"
print_status "Password: ${DB_PASS}"
print_warning "IMPORTANT: Save this password! It will be shown only once."
echo ""

# Generate SQL commands
SQL_FILE="/tmp/create_db_${DB_NAME}.sql"
cat > "${SQL_FILE}" << EOF
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

print_status "SQL commands generated. You can execute them in one of two ways:"
echo ""
print_status "Option 1: Run this command to execute automatically (requires MySQL root password):"
echo "mysql -uroot -p < ${SQL_FILE}"
echo ""
print_status "Option 2: Manually run these commands in MySQL:"
cat "${SQL_FILE}"
echo ""

read -p "Do you want to execute these commands now? (yes/no): " CONFIRM

if [ "${CONFIRM}" = "yes" ]; then
    print_status "Executing SQL commands..."
    mysql -uroot -p < "${SQL_FILE}"
    print_status "Database created successfully!"
    rm -f "${SQL_FILE}"
else
    print_status "SQL commands saved to: ${SQL_FILE}"
    print_status "You can execute them later with: mysql -uroot -p < ${SQL_FILE}"
fi

echo ""
print_status "settings.local.php configuration:"
echo ""
cat << EOF
<?php
\$databases['default']['default'] = array (
  'database' => '${DB_NAME}',
  'username' => '${DB_USER}',
  'password' => '${DB_PASS}',
  'host' => 'localhost',
  'port' => '3306',
  'driver' => 'mysql',
);
EOF

echo ""
print_status "Copy the above configuration to your settings.local.php file"
