#!/usr/bin/env bash
# release.sh - one command per release: a pushed git tag becomes a new release
# folder on the server and is deployed to an environment.
#
# This is the standard release flow (see RELEASING.md). It strings together
# create_release, the two symlinks every release needs, deploy, and the config
# import that deploy leaves out, so a release is always a fresh folder checked
# out from a tag rather than a `git pull` into the folder that is live.
#
# Usage: release.sh [-y] [-s N] [domain] [environment] [version] [git_repo_url] [git_ref]
#
#   -y        do not ask for confirmation
#   -s N      link settings/N/settings.local.php (default: whatever the release
#             currently live in [environment] links, else 2)
#   git_repo_url  defaults to the origin of the release currently deployed to
#             [environment]
#   git_ref   defaults to the tag named [version] or v[version]; the release
#             is refused when neither exists on the remote, because the point
#             of the standard is that every release folder matches a tag.
#
# Example: release.sh selectamixmusic.com live 0.1.3
# Example: release.sh thesolentmetropolitan.com staging 0.3.1-staging https://github.com/x/y.git feat/menu

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

ASSUME_YES=0
SETTINGS_NUMBER=""

# Fold --help to -h so getopts can handle it.
for arg in "$@"; do
    case "$arg" in
        --help) set -- -h ;;
    esac
done

while getopts "hys:" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        y) ASSUME_YES=1 ;;
        s) SETTINGS_NUMBER="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
    usage
    exit 1
fi

DOMAIN=$1
ENVIRONMENT=$2
RELEASE=$3
GIT_REPO=${4:-}
GIT_REF=${5:-}

case "${ENVIRONMENT}" in
    live|staging) ;;
    *) print_error "Environment must be live or staging, not '${ENVIRONMENT}'"; exit 1 ;;
esac

if [ -n "${SETTINGS_NUMBER}" ] && ! [[ "${SETTINGS_NUMBER}" =~ ^[0-9]+$ ]]; then
    print_error "-s takes a settings number, not '${SETTINGS_NUMBER}'"
    exit 1
fi

for tool in git find realpath; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print_error "Required tool not found: $tool"
        exit 1
    fi
done

# Toolkit commands: siblings when run as ./release.sh from the toolkit folder,
# the installed names in /usr/local/bin otherwise (install.sh drops the .sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
toolkit_cmd() {
    if [ -x "${SCRIPT_DIR}/$1.sh" ]; then
        echo "${SCRIPT_DIR}/$1.sh"
    elif command -v "$1" >/dev/null 2>&1; then
        command -v "$1"
    else
        print_error "Toolkit command not found: $1 (run install.sh or run this from the toolkit folder)"
        exit 1
    fi
}
CREATE_RELEASE=$(toolkit_cmd create_release)
DEPLOY=$(toolkit_cmd deploy)

# Find the category by searching /var/www/ for the domain directory
CATEGORY=$(basename "$(dirname "$(find /var/www -maxdepth 2 -mindepth 2 -type d -name "${DOMAIN}" | head -1)")" 2>/dev/null)
if [ -z "${CATEGORY}" ] || [ "${CATEGORY}" = "." ]; then
    print_error "Could not find domain '${DOMAIN}' under /var/www/"
    exit 1
fi

BASE_PATH="/var/www/${CATEGORY}/${DOMAIN}"
RELEASES_PATH="${BASE_PATH}/releases"
RELEASE_PATH="${RELEASES_PATH}/${RELEASE}"
CODE_PATH="${RELEASE_PATH}/code"
ENV_PATH="${BASE_PATH}/deployment_environments/${ENVIRONMENT}"
DOCROOT_LINK="${ENV_PATH}/docroot"

if [ ! -d "${ENV_PATH}" ]; then
    print_error "Environment directory does not exist: ${ENV_PATH}"
    exit 1
fi

if [ -e "${RELEASE_PATH}" ]; then
    print_error "Release ${RELEASE} already exists at: ${RELEASE_PATH}"
    print_error "A release folder is never reused. Tag a new version, or redeploy this one with: deploy ${DOMAIN} ${ENVIRONMENT} ${RELEASE}"
    exit 1
fi

# The release currently serving this environment, if any. It supplies the
# defaults (git remote, settings number) and the rollback hint at the end.
CURRENT_RELEASE=""
CURRENT_CODE=""
if [ -L "${DOCROOT_LINK}" ]; then
    CURRENT_TARGET=$(readlink "${DOCROOT_LINK}")
    CURRENT_RELEASE=$(echo "${CURRENT_TARGET}" | sed -n 's#.*releases/\([^/]*\)/code/web.*#\1#p')
    if [ -n "${CURRENT_RELEASE}" ] && [ -d "${RELEASES_PATH}/${CURRENT_RELEASE}/code" ]; then
        CURRENT_CODE="${RELEASES_PATH}/${CURRENT_RELEASE}/code"
    fi
fi

# Git remote: explicit argument, else the current release's origin, else the
# origin of the newest release folder that has one.
if [ -z "${GIT_REPO}" ]; then
    if [ -n "${CURRENT_CODE}" ] && [ -d "${CURRENT_CODE}/.git" ]; then
        GIT_REPO=$(git -C "${CURRENT_CODE}" remote get-url origin 2>/dev/null || true)
    fi
    if [ -z "${GIT_REPO}" ]; then
        for candidate in $(ls -1 "${RELEASES_PATH}" 2>/dev/null | sort -V -r); do
            if [ -d "${RELEASES_PATH}/${candidate}/code/.git" ]; then
                GIT_REPO=$(git -C "${RELEASES_PATH}/${candidate}/code" remote get-url origin 2>/dev/null || true)
                [ -n "${GIT_REPO}" ] && break
            fi
        done
    fi
    if [ -z "${GIT_REPO}" ]; then
        print_error "No git repository given and no existing release of ${DOMAIN} has an origin remote"
        print_error "Pass the repository URL as the fourth argument"
        exit 1
    fi
    print_status "Git repository (from existing release): ${GIT_REPO}"
fi

# Resolve the ref. Without one the tag must exist on the remote; create_release
# would silently fall back to the default branch, which is exactly what this
# standard is meant to stop.
print_status "Checking ${GIT_REPO} for the release tag..."
REMOTE_REFS=$(git ls-remote --tags --heads --refs "${GIT_REPO}" 2>/dev/null | awk '{print $2}') || {
    print_error "Could not reach ${GIT_REPO}"
    exit 1
}
if [ -z "${GIT_REF}" ]; then
    if echo "${REMOTE_REFS}" | grep -qx "refs/tags/${RELEASE}"; then
        GIT_REF="${RELEASE}"
    elif echo "${REMOTE_REFS}" | grep -qx "refs/tags/v${RELEASE}"; then
        GIT_REF="v${RELEASE}"
    else
        print_error "No tag '${RELEASE}' or 'v${RELEASE}' on ${GIT_REPO}"
        print_error "Tag and push first:  git tag -a ${RELEASE} -m '${RELEASE}' && git push origin ${RELEASE}"
        print_error "To deploy a branch instead (staging only, please), pass it as the fifth argument"
        exit 1
    fi
    print_status "Tag found: ${GIT_REF}"
else
    if echo "${REMOTE_REFS}" | grep -qx -e "refs/tags/${GIT_REF}" -e "refs/heads/${GIT_REF}"; then
        print_status "Ref found on remote: ${GIT_REF}"
    elif [[ "${GIT_REF}" =~ ^[0-9a-f]{7,40}$ ]]; then
        print_warning "Ref ${GIT_REF} looks like a commit; it will be checked out after the clone"
    else
        print_error "No tag or branch '${GIT_REF}' on ${GIT_REPO}"
        exit 1
    fi
    if [ "${ENVIRONMENT}" = "live" ] && ! echo "${REMOTE_REFS}" | grep -qx "refs/tags/${GIT_REF}"; then
        print_warning "Deploying something other than a tag to live. The standard is a tag per live release."
    fi
fi

# Settings number: -s, else the one the current release links, else 2.
if [ -z "${SETTINGS_NUMBER}" ]; then
    if [ -n "${CURRENT_CODE}" ] && [ -L "${CURRENT_CODE}/web/sites/default/settings.local.php" ]; then
        SETTINGS_NUMBER=$(readlink "${CURRENT_CODE}/web/sites/default/settings.local.php" | sed -n 's#.*settings/\([0-9][0-9]*\)/settings.local.php#\1#p')
    fi
    if [ -z "${SETTINGS_NUMBER}" ]; then
        SETTINGS_NUMBER=2
        print_warning "Could not tell which settings number ${ENVIRONMENT} uses; defaulting to settings/2 (override with -s)"
    fi
fi
if [ ! -f "${BASE_PATH}/settings/${SETTINGS_NUMBER}/settings.local.php" ]; then
    print_error "Settings file does not exist: ${BASE_PATH}/settings/${SETTINGS_NUMBER}/settings.local.php"
    exit 1
fi

echo ""
print_status "Release plan for ${DOMAIN} (${ENVIRONMENT})"
echo "  Release folder : ${RELEASE_PATH}"
echo "  Repository     : ${GIT_REPO}"
echo "  Ref            : ${GIT_REF}"
echo "  Settings       : settings/${SETTINGS_NUMBER}/settings.local.php"
echo "  Files          : deployment_environments/${ENVIRONMENT}/assets/public/files"
echo "  Currently      : ${CURRENT_RELEASE:-nothing deployed}"
echo "  Steps          : create_release -> symlinks -> deploy (backup_db, composer install, symlink flip, opcache reset, updb, cr) -> cim if config differs"
echo ""

if [ "${ASSUME_YES}" -ne 1 ]; then
    read -r -p "Proceed? (yes/no): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        print_status "Release cancelled"
        exit 0
    fi
fi

# 1. Fresh clone at the tag.
"${CREATE_RELEASE}" "${DOMAIN}" "${RELEASE}" "${GIT_REPO}" "${GIT_REF}"

# 2. The two symlinks create_release leaves to the operator.
WEB_DEFAULT="${CODE_PATH}/web/sites/default"
if [ ! -d "${WEB_DEFAULT}" ]; then
    print_error "${WEB_DEFAULT} does not exist; is this a Drupal composer project?"
    exit 1
fi
# From web/sites/default up to the site root is six levels.
UP="../../../../../.."
ln -sfn "${UP}/settings/${SETTINGS_NUMBER}/settings.local.php" "${WEB_DEFAULT}/settings.local.php"
ln -sfn "${UP}/deployment_environments/${ENVIRONMENT}/assets/public/files" "${WEB_DEFAULT}/files"
if [ ! -f "${WEB_DEFAULT}/settings.local.php" ] || [ ! -d "${WEB_DEFAULT}/files" ]; then
    print_error "A symlink in ${WEB_DEFAULT} does not resolve:"
    ls -la "${WEB_DEFAULT}/settings.local.php" "${WEB_DEFAULT}/files" >&2 || true
    exit 1
fi
print_status "Linked settings/${SETTINGS_NUMBER} and the ${ENVIRONMENT} files directory"

# 3. Deploy: backup, composer install, symlink flip, opcache reset, updb, cr.
"${DEPLOY}" "${DOMAIN}" "${ENVIRONMENT}" "${RELEASE}"

# 4. Config import, which deploy does not do. Skipped when the site has no
# config sync directory (drush config:status fails) or nothing differs.
cd "${CODE_PATH}"
if [ -x "./drush" ]; then
    DRUSH="./drush"
elif [ -x "vendor/bin/drush" ]; then
    DRUSH="vendor/bin/drush"
else
    print_error "No drush in ${CODE_PATH} after deploy"
    exit 1
fi

if CONFIG_DIFF=$(${DRUSH} config:status --format=list 2>/dev/null); then
    if [ -n "${CONFIG_DIFF}" ]; then
        print_status "Configuration differs from the sync directory; importing..."
        echo "${CONFIG_DIFF}" | sed 's/^/    /'
        ${DRUSH} config:import -y
        ${DRUSH} cache:rebuild
    else
        print_status "Configuration matches the sync directory; nothing to import"
    fi
else
    print_warning "drush config:status failed (no config sync directory?); skipping config import"
fi

# 5. Show what is now running.
echo ""
print_status "Deployed ${DOMAIN} ${ENVIRONMENT} -> release ${RELEASE}"
echo "  git: $(git -C "${CODE_PATH}" describe --tags --always 2>/dev/null) on $(git -C "${CODE_PATH}" rev-parse --short HEAD 2>/dev/null)"
${DRUSH} status --fields=drupal-version,drush-version 2>/dev/null | sed 's/^/  /' || true
if [ -n "${CURRENT_RELEASE}" ]; then
    echo ""
    print_status "Rollback: update_symlink ${DOMAIN} ${ENVIRONMENT} ${CURRENT_RELEASE}  (then reload PHP and drush cr; restore_db if updb changed the schema)"
fi
