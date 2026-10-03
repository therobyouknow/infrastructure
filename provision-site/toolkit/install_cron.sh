#!/bin/bash
# Install the scheduled jobs for a site into the current user's crontab.
# Usage: ./install_cron.sh [domain] [environment] [alert_to]
# Example: ./install_cron.sh internationalgospelchoir.uk live "<superadmin address>,someone@example.com"
#
# Adds (replacing any earlier block for the same domain/environment):
#   - drush cron hourly (webform purge, queue, updates)
#   - mail-health daily check at 07:10 and weekly digest Mondays at 07:20
#     (scripts/devops/mail-health.php in the deployed release)
#   - Zoho mailbox purge nightly at 02:30 (scripts/devops/zoho-mailbox-purge.py,
#     needs ~/.config/ligc/zoho-imap.env)
# Every job resolves the current release through the environment's docroot
# symlink at run time, so releases can change without touching the crontab.
# Logs go to /var/www/<category>/<domain>/logs/.

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$#" -lt 2 ]; then
    print_error "Usage: $0 [domain] [environment] [alert_to]"
    exit 1
fi
DOMAIN=$1
ENVIRONMENT=$2
ALERT_TO=$(echo "${3:-}" | tr -d "[:space:]")   # "a@x, b@y" -> "a@x,b@y": a space would split the cron argument

CATEGORY=$(basename $(dirname $(find /var/www -maxdepth 2 -mindepth 2 -type d -name "${DOMAIN}" | head -1)) 2>/dev/null)
if [ -z "${CATEGORY}" ]; then
    print_error "Could not find domain '${DOMAIN}' under /var/www/"
    exit 1
fi
BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
DOCROOT_LINK="${BASE_PATH}/deployment_environments/${ENVIRONMENT}/docroot"
LOG_DIR="${BASE_PATH}/logs"
if [ ! -L "${DOCROOT_LINK}" ]; then
    print_error "Docroot symlink does not exist: ${DOCROOT_LINK}"
    exit 1
fi
mkdir -p "${LOG_DIR}"

# The code directory of whatever release the environment points at, resolved when the job runs.
CODE='$(dirname "$(readlink -f '"${DOCROOT_LINK}"')")'
TO_OPT=""
if [ -n "${ALERT_TO}" ]; then
    TO_OPT=" --to=${ALERT_TO}"
fi
MARK_START="# BEGIN ligc-jobs ${DOMAIN} ${ENVIRONMENT}"
MARK_END="# END ligc-jobs ${DOMAIN} ${ENVIRONMENT}"

BLOCK=$(cat <<CRON
${MARK_START}
0 * * * * cd ${CODE} && ./drush cron >> ${LOG_DIR}/cron.log 2>&1
10 7 * * * cd ${CODE} && ./drush php:script scripts/devops/mail-health.php -- daily${TO_OPT} --mailbox-log=${LOG_DIR}/mailbox-purge.log >> ${LOG_DIR}/mail-health.log 2>&1
20 7 * * 1 cd ${CODE} && ./drush php:script scripts/devops/mail-health.php -- weekly${TO_OPT} --mailbox-log=${LOG_DIR}/mailbox-purge.log >> ${LOG_DIR}/mail-health.log 2>&1
30 2 * * * cd ${CODE} && python3 scripts/devops/zoho-mailbox-purge.py --days 30 --yes --log ${LOG_DIR}/mailbox-purge.log >> ${LOG_DIR}/mailbox-purge.out 2>&1
${MARK_END}
CRON
)

EXISTING=$(crontab -l 2>/dev/null || true)
# Drop any earlier block for this domain/environment, then append the new one.
CLEANED=$(printf '%s\n' "${EXISTING}" | awk -v s="${MARK_START}" -v e="${MARK_END}" '$0==s{skip=1} !skip{print} $0==e{skip=0}')
printf '%s\n%s\n' "${CLEANED}" "${BLOCK}" | sed '/^$/N;/^\n$/D' | crontab -
print_status "Installed for ${DOMAIN} (${ENVIRONMENT}). Current crontab:"
crontab -l | sed -n "/${MARK_START}/,/${MARK_END}/p"
print_status "Logs: ${LOG_DIR}/"
