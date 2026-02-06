#!/bin/bash
# Drush Helper Script - Run drush commands on any site
# Usage: ./drush_run.sh [category] [domain] [environment] [drush_command]
# Example: ./drush_run.sh 05 example.com live "updb -y"
# Example: ./drush_run.sh 05 example.com staging "cr"

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

# Validate arguments
if [ "$#" -lt 4 ]; then
    print_error "Usage: $0 [category] [domain] [environment] [drush_command]"
    print_error "Example: $0 05 example.com live \"updb -y\""
    print_error "Example: $0 05 example.com staging \"status\""
    print_error "Example: $0 05 example.com live \"cr\""
    exit 1
fi

CATEGORY=$1
DOMAIN=$2
ENVIRONMENT=$3
shift 3
DRUSH_COMMAND="$@"

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
ENV_PATH="${BASE_PATH}/deployment_environments/${ENVIRONMENT}"
DOCROOT_LINK="${ENV_PATH}/docroot"

# Validate environment path exists
if [ ! -d "${ENV_PATH}" ]; then
    print_error "Environment path does not exist: ${ENV_PATH}"
    exit 1
fi

# Check if docroot symlink exists
if [ ! -L "${DOCROOT_LINK}" ]; then
    print_error "Docroot symlink does not exist: ${DOCROOT_LINK}"
    exit 1
fi

# Resolve the symlink to find the actual code path
ACTUAL_WEB_PATH=$(readlink -f "${DOCROOT_LINK}")
CODE_PATH=$(dirname "${ACTUAL_WEB_PATH}")

if [ ! -d "${CODE_PATH}" ]; then
    print_error "Code path does not exist: ${CODE_PATH}"
    exit 1
fi

# Check if drush exists
if [ ! -f "${CODE_PATH}/drush" ]; then
    print_error "Drush not found at: ${CODE_PATH}/drush"
    exit 1
fi

print_status "Running drush command on ${DOMAIN} (${ENVIRONMENT})"
print_status "Code path: ${CODE_PATH}"
print_status "Command: ${DRUSH_COMMAND}"
echo ""

# Navigate to code path and run drush
cd "${CODE_PATH}"
./drush ${DRUSH_COMMAND}

print_status "Command completed"
