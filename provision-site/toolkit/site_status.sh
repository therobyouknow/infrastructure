#!/bin/bash
# Site Status Script - List all sites and their current deployments
# Usage: ./site_status.sh [category]
# Example: ./site_status.sh 05
# Example: ./site_status.sh (shows all categories)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

CATEGORY=$1

if [ -n "${CATEGORY}" ]; then
    # List specific category
    CATEGORIES=("${CATEGORY}")
else
    # List all categories
    CATEGORIES=($(ls -d /var/www/*/ 2>/dev/null | xargs -n 1 basename))
fi

if [ ${#CATEGORIES[@]} -eq 0 ]; then
    print_error "No sites found in /var/www/"
    exit 1
fi

print_header "DRUPAL SITES STATUS"
echo ""

for CAT in "${CATEGORIES[@]}"; do
    CAT_PATH="/var/www/${CAT}"
    
    if [ ! -d "${CAT_PATH}" ]; then
        continue
    fi
    
    # Find all domains in this category
    DOMAINS=($(ls -d ${CAT_PATH}/*/ 2>/dev/null | xargs -n 1 basename))
    
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        continue
    fi
    
    echo -e "${YELLOW}Category: ${CAT}${NC}"
    echo "----------------------------------------"
    
    for DOMAIN in "${DOMAINS[@]}"; do
        SITE_PATH="${CAT_PATH}/${DOMAIN}"
        
        echo -e "  ${GREEN}${DOMAIN}${NC}"
        
        # Check live environment
        LIVE_DOCROOT="${SITE_PATH}/deployment_environments/live/docroot"
        if [ -L "${LIVE_DOCROOT}" ]; then
            LIVE_TARGET=$(readlink "${LIVE_DOCROOT}")
            LIVE_RELEASE=$(echo "${LIVE_TARGET}" | grep -oP 'releases/\K[^/]+' || echo "unknown")
            
            if [ -d "${LIVE_DOCROOT}" ]; then
                echo -e "    Live:    ${GREEN}✓${NC} ${LIVE_RELEASE}"
            else
                echo -e "    Live:    ${RED}✗${NC} ${LIVE_RELEASE} (broken symlink)"
            fi
        else
            echo -e "    Live:    ${RED}✗${NC} No deployment"
        fi
        
        # Check staging environment
        STAGING_DOCROOT="${SITE_PATH}/deployment_environments/staging/docroot"
        if [ -L "${STAGING_DOCROOT}" ]; then
            STAGING_TARGET=$(readlink "${STAGING_DOCROOT}")
            STAGING_RELEASE=$(echo "${STAGING_TARGET}" | grep -oP 'releases/\K[^/]+' || echo "unknown")
            
            if [ -d "${STAGING_DOCROOT}" ]; then
                echo -e "    Staging: ${GREEN}✓${NC} ${STAGING_RELEASE}"
            else
                echo -e "    Staging: ${RED}✗${NC} ${STAGING_RELEASE} (broken symlink)"
            fi
        else
            echo -e "    Staging: ${YELLOW}○${NC} No deployment"
        fi
        
        # List available releases
        RELEASES_PATH="${SITE_PATH}/releases"
        if [ -d "${RELEASES_PATH}" ]; then
            RELEASES=($(ls -1 "${RELEASES_PATH}" 2>/dev/null | grep -v placeholder))
            if [ ${#RELEASES[@]} -gt 0 ]; then
                echo -e "    Releases: ${RELEASES[*]}"
            fi
        fi
        
        # Check database settings
        SETTINGS_PATH="${SITE_PATH}/settings"
        if [ -d "${SETTINGS_PATH}" ]; then
            DBS=""
            for DB_NUM in 1 2; do
                if [ -f "${SETTINGS_PATH}/${DB_NUM}/settings.local.php" ]; then
                    DB_NAME=$(grep "'database'" "${SETTINGS_PATH}/${DB_NUM}/settings.local.php" 2>/dev/null | sed "s/.*'database' => '\([^']*\)'.*/\1/")
                    if [ -n "${DB_NAME}" ]; then
                        DBS="${DBS} ${DB_NUM}:${DB_NAME}"
                    fi
                fi
            done
            if [ -n "${DBS}" ]; then
                echo -e "    Databases:${DBS}"
            fi
        fi
        
        # Check last backup
        BACKUP_PATH="${SITE_PATH}/backups/database"
        if [ -d "${BACKUP_PATH}" ]; then
            LAST_BACKUP=$(ls -1t "${BACKUP_PATH}"/*.sql.gz 2>/dev/null | head -1)
            if [ -n "${LAST_BACKUP}" ]; then
                BACKUP_DATE=$(stat -c %y "${LAST_BACKUP}" 2>/dev/null | cut -d' ' -f1)
                echo -e "    Last backup: ${BACKUP_DATE}"
            fi
        fi
        
        echo ""
    done
    
    echo ""
done

print_header "SUMMARY"
TOTAL_SITES=$(find /var/www -maxdepth 2 -mindepth 2 -type d | wc -l)
echo "Total sites: ${TOTAL_SITES}"
