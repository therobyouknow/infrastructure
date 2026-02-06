#!/bin/bash
# Create Apache VHost Configuration Script
# Usage: ./create_vhost.sh [category] [domain] [environment]
# Example: ./create_vhost.sh 05 example.com live
# Example: ./create_vhost.sh 05 example.com staging

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
    print_error "Usage: $0 [category] [domain] [environment]"
    print_error "Example: $0 05 example.com live"
    print_error "Example: $0 05 example.com staging"
    exit 1
fi

CATEGORY=$1
DOMAIN=$2
ENVIRONMENT=$3

if [ "${ENVIRONMENT}" != "live" ] && [ "${ENVIRONMENT}" != "staging" ]; then
    print_error "Environment must be 'live' or 'staging'"
    exit 1
fi

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
DOCROOT_PATH="${BASE_PATH}/deployment_environments/${ENVIRONMENT}/docroot"

# Validate base path exists
if [ ! -d "${BASE_PATH}" ]; then
    print_error "Base path does not exist: ${BASE_PATH}"
    print_error "Run create_site_structure.sh first"
    exit 1
fi

# Set ServerName based on environment
if [ "${ENVIRONMENT}" = "staging" ]; then
    SERVER_NAME="staging.${DOMAIN}"
    VHOST_FILE="/etc/apache2/sites-available/staging.${DOMAIN}.conf"
else
    SERVER_NAME="${DOMAIN}"
    VHOST_FILE="/etc/apache2/sites-available/${DOMAIN}.conf"
fi

# Check if vhost already exists
if [ -f "${VHOST_FILE}" ]; then
    print_warning "VHost file already exists: ${VHOST_FILE}"
    read -p "Do you want to overwrite it? (yes/no): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        exit 0
    fi
fi

print_status "Creating Apache VHost configuration for ${SERVER_NAME}"

# Create the vhost configuration
cat > "${VHOST_FILE}" << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName ${SERVER_NAME}
    DocumentRoot ${DOCROOT_PATH}
    ErrorLog \${APACHE_LOG_DIR}/${SERVER_NAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SERVER_NAME}_access.log combined
    
    <Directory "${DOCROOT_PATH}">
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

print_status "VHost configuration created: ${VHOST_FILE}"
echo ""
cat "${VHOST_FILE}"
echo ""

print_status "Next steps:"
print_status "1. Enable the site: sudo a2ensite $(basename ${VHOST_FILE})"
print_status "2. Test Apache configuration: sudo apache2ctl configtest"
print_status "3. Reload Apache: sudo systemctl reload apache2"
print_status "4. Set up DNS for ${SERVER_NAME} to point to your server"
print_status "5. Run certbot to get SSL certificate: sudo certbot --apache -d ${SERVER_NAME}"
echo ""

read -p "Do you want to enable this site now? (yes/no): " ENABLE

if [ "${ENABLE}" = "yes" ]; then
    print_status "Enabling site..."
    sudo a2ensite $(basename ${VHOST_FILE})
    
    print_status "Testing Apache configuration..."
    sudo apache2ctl configtest
    
    read -p "Reload Apache now? (yes/no): " RELOAD
    if [ "${RELOAD}" = "yes" ]; then
        sudo systemctl reload apache2
        print_status "Apache reloaded successfully!"
    fi
fi

print_status "VHost setup complete!"
print_warning "Remember to configure DNS before running certbot for SSL"
