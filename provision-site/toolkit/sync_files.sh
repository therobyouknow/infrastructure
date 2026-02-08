#!/bin/bash
# Sync Site Files Script (runs locally)
# Syncs the Drupal public files directory between local dev and a remote server.
# Usage: ./sync_files.sh [push|pull] [ssh_host] [category] [domain] [environment]
# Example: ./sync_files.sh pull server03 05 example.com live

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
if [ "$#" -ne 5 ]; then
    print_error "Usage: $0 [push|pull] [ssh_host] [category] [domain] [environment]"
    print_error "Example: $0 pull server03 05 example.com live"
    exit 1
fi

DIRECTION=$1
SSH_HOST=$2
CATEGORY=$3
DOMAIN=$4
ENVIRONMENT=$5

# Validate direction
if [ "${DIRECTION}" != "push" ] && [ "${DIRECTION}" != "pull" ]; then
    print_error "Direction must be 'push' or 'pull' (got '${DIRECTION}')"
    print_error "Usage: $0 [push|pull] [ssh_host] [category] [domain] [environment]"
    exit 1
fi

REMOTE_PATH="/var/www/${CATEGORY}/${DOMAIN}/deployment_environments/${ENVIRONMENT}/assets/public/files/"
LOCAL_PATH="./files/"

print_status "Direction:   ${DIRECTION}"
print_status "SSH host:    ${SSH_HOST}"
print_status "Remote path: ${REMOTE_PATH}"
print_status "Local path:  ${LOCAL_PATH}"

if [ "${DIRECTION}" = "pull" ]; then
    # Create local directory if it doesn't exist
    if [ ! -d "${LOCAL_PATH}" ]; then
        print_status "Creating local directory: ${LOCAL_PATH}"
        mkdir -p "${LOCAL_PATH}"
    fi

    print_status "Pulling files from ${SSH_HOST}..."
    rsync -avz --progress "${SSH_HOST}:${REMOTE_PATH}" "${LOCAL_PATH}"

elif [ "${DIRECTION}" = "push" ]; then
    # Verify local directory exists
    if [ ! -d "${LOCAL_PATH}" ]; then
        print_error "Local directory does not exist: ${LOCAL_PATH}"
        exit 1
    fi

    print_warning "You are about to push local files to ${SSH_HOST}:${REMOTE_PATH}"
    print_warning "This will overwrite any changed files on the server."
    echo -n "Continue? [y/N] "
    read -r CONFIRM
    if [ "${CONFIRM}" != "y" ] && [ "${CONFIRM}" != "Y" ]; then
        print_status "Aborted."
        exit 0
    fi

    print_status "Pushing files to ${SSH_HOST}..."
    rsync -avz --progress "${LOCAL_PATH}" "${SSH_HOST}:${REMOTE_PATH}"
fi

# Print summary
echo ""
LOCAL_COUNT=$(find "${LOCAL_PATH}" -type f 2>/dev/null | wc -l | tr -d ' ')
LOCAL_SIZE=$(du -sh "${LOCAL_PATH}" 2>/dev/null | cut -f1)
print_status "Sync complete!"
print_status "Local files: ${LOCAL_COUNT} files, ${LOCAL_SIZE}"
