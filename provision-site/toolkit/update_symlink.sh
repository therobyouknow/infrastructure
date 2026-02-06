#!/bin/bash
# Update Symlink Script - Quick deployment without running updates
# Usage: ./update_symlink.sh [category] [domain] [environment] [release_version]
# Example: ./update_symlink.sh 05 example.com live 2.0.5

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
if [ "$#" -ne 4 ]; then
    print_error "Usage: $0 [category] [domain] [environment] [release_version]"
    print_error "Example: $0 05 example.com live 2.0.5"
    exit 1
fi

CATEGORY=$1
DOMAIN=$2
ENVIRONMENT=$3
RELEASE=$4

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
RELEASE_PATH="${BASE_PATH}/releases/${RELEASE}"
CODE_PATH="${RELEASE_PATH}/code"
ENV_PATH="${BASE_PATH}/deployment_environments/${ENVIRONMENT}"
DOCROOT_LINK="${ENV_PATH}/docroot"

# Validate paths
if [ ! -d "${RELEASE_PATH}" ]; then
    print_error "Release path does not exist: ${RELEASE_PATH}"
    exit 1
fi

if [ ! -d "${CODE_PATH}/web" ]; then
    print_error "Web directory does not exist in release: ${CODE_PATH}/web"
    exit 1
fi

# Show current symlink
if [ -L "${DOCROOT_LINK}" ]; then
    CURRENT_TARGET=$(readlink "${DOCROOT_LINK}")
    print_status "Current symlink: ${DOCROOT_LINK} -> ${CURRENT_TARGET}"
else
    print_warning "Docroot symlink does not exist yet"
fi

RELATIVE_PATH="../../releases/${RELEASE}/code/web"
print_status "New target: ${RELATIVE_PATH}"

read -p "Update symlink to point to release ${RELEASE}? (yes/no): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
    print_status "Symlink update cancelled"
    exit 0
fi

# Update the symlink
ln -sfn ${RELATIVE_PATH} ${DOCROOT_LINK}

# Verify the symlink
if [ -L "${DOCROOT_LINK}" ]; then
    NEW_TARGET=$(readlink "${DOCROOT_LINK}")
    print_status "Symlink updated successfully!"
    print_status "${DOCROOT_LINK} -> ${NEW_TARGET}"
    
    # Check if target exists
    if [ -d "${DOCROOT_LINK}" ]; then
        print_status "Target directory is accessible"
    else
        print_error "Warning: Target directory is not accessible!"
    fi
else
    print_error "Failed to create symlink"
    exit 1
fi

print_status "Deployment to ${ENVIRONMENT} complete!"
print_warning "Remember to run drush updb and drush cr if database updates are needed"
