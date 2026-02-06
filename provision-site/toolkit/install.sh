#!/bin/bash
# Installation Script for Drupal Management Scripts
# This script sets up all management scripts in /usr/local/bin for system-wide access

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

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run with sudo"
    exit 1
fi

INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_status "Installing Drupal management scripts from ${SCRIPT_DIR}"
print_status "Installation directory: ${INSTALL_DIR}"
echo ""

# List of scripts to install
SCRIPTS=(
    "create_site_structure.sh"
    "create_database.sh"
    "create_vhost.sh"
    "create_release.sh"
    "deploy.sh"
    "update_symlink.sh"
    "backup_db.sh"
    "restore_db.sh"
    "drush_run.sh"
    "site_status.sh"
)

# Check if all scripts exist
MISSING=0
for SCRIPT in "${SCRIPTS[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${SCRIPT}" ]; then
        print_error "Script not found: ${SCRIPT}"
        MISSING=1
    fi
done

if [ ${MISSING} -eq 1 ]; then
    print_error "Some scripts are missing. Please ensure all scripts are in ${SCRIPT_DIR}"
    exit 1
fi

# Install each script
print_status "Installing scripts..."
for SCRIPT in "${SCRIPTS[@]}"; do
    # Remove .sh extension for cleaner command names
    COMMAND_NAME=$(basename "${SCRIPT}" .sh)
    
    # Copy script to install directory
    cp "${SCRIPT_DIR}/${SCRIPT}" "${INSTALL_DIR}/${COMMAND_NAME}"
    chmod 755 "${INSTALL_DIR}/${COMMAND_NAME}"
    
    print_status "Installed: ${COMMAND_NAME}"
done

echo ""
print_status "Installation complete!"
echo ""
print_status "You can now run these commands from anywhere:"
echo ""
echo "  create_site_structure [category] [domain]"
echo "  create_database [domain] [db_number]"
echo "  create_vhost [category] [domain] [environment]"
echo "  create_release [category] [domain] [version] [git_repo]"
echo "  deploy [category] [domain] [environment] [version]"
echo "  update_symlink [category] [domain] [environment] [version]"
echo "  backup_db [category] [domain] [db_number]"
echo "  restore_db [category] [domain] [db_number] [backup_file]"
echo "  drush_run [category] [domain] [environment] [command]"
echo "  site_status [category]"
echo ""
print_status "Run any command without arguments to see usage instructions"
print_status "Check ${SCRIPT_DIR}/README.md for detailed documentation"
