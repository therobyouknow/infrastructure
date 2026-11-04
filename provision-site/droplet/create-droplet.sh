#!/usr/bin/env bash
# Create the "server04" DigitalOcean droplet from droplet.env + cloud-init.yaml.
#
#   ./create-droplet.sh --dry-run     render user-data, print the doctl command, exit
#   ./create-droplet.sh               create the droplet, wait for SSH + cloud-init
#   ./create-droplet.sh --env FILE    use a different settings file (default: droplet.env)
#
# Needs: doctl (brew install doctl) already authenticated (doctl auth init).
# The API token lives in doctl's keychain config, never in this repo.
# Refuses to create a droplet whose name already exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/droplet.env"
TEMPLATE="${SCRIPT_DIR}/cloud-init.yaml"
RENDERED="${SCRIPT_DIR}/cloud-init.rendered.yaml"
DRY_RUN=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- arguments -------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)   DRY_RUN=1 ;;
        --env)       shift; ENV_FILE="${1:-}"; [ -n "${ENV_FILE}" ] || die "--env needs a file" ;;
        -h|--help)   usage; exit 0 ;;
        *)           usage; die "Unknown argument: $1" ;;
    esac
    shift
done

# --- settings ---------------------------------------------------------------
[ -f "${ENV_FILE}" ] || die "Settings file not found: ${ENV_FILE}
Create it with:  cp ${SCRIPT_DIR}/droplet.env.example ${ENV_FILE}   (then edit)"
[ -f "${TEMPLATE}" ] || die "Template not found: ${TEMPLATE}"

set -a
# shellcheck source=/dev/null
. "${ENV_FILE}"
set +a

: "${DROPLET_NAME:?DROPLET_NAME must be set in ${ENV_FILE}}"
: "${DROPLET_REGION:?DROPLET_REGION must be set}"
: "${DROPLET_SIZE:?DROPLET_SIZE must be set}"
: "${DROPLET_IMAGE:?DROPLET_IMAGE must be set}"
: "${ROB_AUTHORIZED_KEYS_FILES:?ROB_AUTHORIZED_KEYS_FILES must list at least one .pub file}"
DROPLET_TAGS="${DROPLET_TAGS:-}"
DROPLET_ENABLE_BACKUPS="${DROPLET_ENABLE_BACKUPS:-no}"
DROPLET_SSH_KEYS="${DROPLET_SSH_KEYS:-}"
DROPLET_VPC_UUID="${DROPLET_VPC_UUID:-}"
DROPLET_PROJECT_ID="${DROPLET_PROJECT_ID:-}"
ROB_SSH_IDENTITY_FILE="${ROB_SSH_IDENTITY_FILE:-}"
SSH_WAIT_SECONDS="${SSH_WAIT_SECONDS:-1200}"
TOOLKIT_REPO_URL="${TOOLKIT_REPO_URL:-https://github.com/therobyouknow/infrastructure.git}"
TOOLKIT_REPO_REF="${TOOLKIT_REPO_REF:-main}"

[[ "${DROPLET_NAME}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] \
    || die "DROPLET_NAME '${DROPLET_NAME}' is not a valid hostname (lowercase letters, digits, - and .)"

if [ -z "${DROPLET_SSH_KEYS}" ]; then
    warn "DROPLET_SSH_KEYS is empty: DigitalOcean will EMAIL a root password for this droplet."
    warn "Set it from 'doctl compute ssh-key list' to avoid that (root login is disabled by cloud-init regardless)."
fi

# --- gather Rob's public keys -----------------------------------------------
expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

AUTHORIZED_KEYS=()
# shellcheck disable=SC2206  # intentional word-splitting of a space-separated list
KEY_FILES=( ${ROB_AUTHORIZED_KEYS_FILES} )
for f in "${KEY_FILES[@]}"; do
    path="$(expand_tilde "${f}")"
    [ -f "${path}" ] || die "Public key file not found: ${path}"
    [[ "${path}" == *.pub ]] || die "Refusing ${path}: only .pub files may go into user-data"
    while IFS= read -r line; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        [[ "${line}" =~ ^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp[0-9]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)\  ]] \
            || die "Line in ${path} does not look like an OpenSSH public key: ${line:0:40}..."
        [[ "${line}" == *PRIVATE* ]] && die "${path} looks like a private key; aborting"
        AUTHORIZED_KEYS+=("${line}")
    done < "${path}"
done
[ "${#AUTHORIZED_KEYS[@]}" -gt 0 ] || die "No public keys read from ${ROB_AUTHORIZED_KEYS_FILES}"
info "Read ${#AUTHORIZED_KEYS[@]} public key(s) for user rob"

# --- render cloud-init -----------------------------------------------------
# The key placeholder is a whole list item; replace that line with one item per
# key at the same indentation. The other placeholders are plain substitutions.
grep -q '@@ROB_SSH_AUTHORIZED_KEYS@@' "${TEMPLATE}" || die "Template has no @@ROB_SSH_AUTHORIZED_KEYS@@ placeholder"
KEYS_JOINED="$(printf '%s\n' "${AUTHORIZED_KEYS[@]}")"
export KEYS_JOINED DROPLET_NAME TOOLKIT_REPO_URL TOOLKIT_REPO_REF
awk '
    /@@ROB_SSH_AUTHORIZED_KEYS@@/ {
        match($0, /^[ ]*- /); indent = substr($0, 1, RLENGTH)
        n = split(ENVIRON["KEYS_JOINED"], keys, "\n")
        for (i = 1; i <= n; i++) if (keys[i] != "") print indent "\"" keys[i] "\""
        next
    }
    {
        gsub(/@@DROPLET_NAME@@/,     ENVIRON["DROPLET_NAME"])
        gsub(/@@TOOLKIT_REPO_URL@@/, ENVIRON["TOOLKIT_REPO_URL"])
        gsub(/@@TOOLKIT_REPO_REF@@/, ENVIRON["TOOLKIT_REPO_REF"])
        print
    }
' "${TEMPLATE}" > "${RENDERED}"
chmod 600 "${RENDERED}"

if grep -n '@@[A-Z_]*@@' "${RENDERED}"; then
    die "Unreplaced placeholders remain in ${RENDERED}"
fi
head -1 "${RENDERED}" | grep -q '^#cloud-config' || die "Rendered file does not start with #cloud-config"
SIZE=$(wc -c < "${RENDERED}" | tr -d ' ')
[ "${SIZE}" -lt 65536 ] || die "Rendered user-data is ${SIZE} bytes; DigitalOcean's limit is 64 KiB"
if grep -Ei 'PRIVATE KEY|password[[:space:]]*[:=][[:space:]]*[^[:space:]]' "${RENDERED}" >/dev/null; then
    die "Rendered user-data appears to contain a secret; refusing to continue"
fi
info "Rendered user-data: ${RENDERED} (${SIZE} bytes)"

# --- build the doctl command -------------------------------------------------
CMD=(doctl compute droplet create "${DROPLET_NAME}"
     --region "${DROPLET_REGION}"
     --size "${DROPLET_SIZE}"
     --image "${DROPLET_IMAGE}"
     --enable-monitoring
     --user-data-file "${RENDERED}"
     --wait
     --format "ID,Name,PublicIPv4,Region,Image,Status"
)
[ -n "${DROPLET_SSH_KEYS}" ]  && CMD+=(--ssh-keys "${DROPLET_SSH_KEYS}")
[ -n "${DROPLET_TAGS}" ]      && CMD+=(--tag-names "${DROPLET_TAGS}")
[ -n "${DROPLET_VPC_UUID}" ]  && CMD+=(--vpc-uuid "${DROPLET_VPC_UUID}")
[ -n "${DROPLET_PROJECT_ID}" ] && CMD+=(--project-id "${DROPLET_PROJECT_ID}")
case "$(printf '%s' "${DROPLET_ENABLE_BACKUPS}" | tr '[:upper:]' '[:lower:]')" in   # macOS bash 3.2 has no ${var,,}
    yes|true|1) CMD+=(--enable-backups) ;;
    no|false|0|"") ;;
    *) die "DROPLET_ENABLE_BACKUPS must be yes or no (got '${DROPLET_ENABLE_BACKUPS}')" ;;
esac

echo
info "doctl command:"
printf '   '; printf '%q ' "${CMD[@]}"; echo
echo

if [ "${DRY_RUN}" -eq 1 ]; then
    info "Dry run: nothing was sent to DigitalOcean. Review ${RENDERED}, then run without --dry-run."
    exit 0
fi

# --- preflight (needs an authenticated doctl) ------------------------------
command -v doctl >/dev/null || die "doctl not found. Install with: brew install doctl"
doctl account get >/dev/null 2>&1 \
    || die "doctl is not authenticated. Run: doctl auth init   (token stays in doctl's keychain config)"

if doctl compute droplet list --format Name --no-header | grep -qx "${DROPLET_NAME}"; then
    die "A droplet named '${DROPLET_NAME}' already exists. Refusing to create a duplicate.
To rebuild: doctl compute droplet delete ${DROPLET_NAME}   (destroys it and its data!), then rerun."
fi

doctl compute image list-distribution --public --format Slug --no-header | grep -qx "${DROPLET_IMAGE}" \
    || die "Image slug '${DROPLET_IMAGE}' not offered. Check: doctl compute image list-distribution --public | grep -i ubuntu"

# --- create -----------------------------------------------------------------
info "Creating droplet ${DROPLET_NAME} (${DROPLET_SIZE}, ${DROPLET_REGION}, ${DROPLET_IMAGE})..."
"${CMD[@]}"

DROPLET_ID=$(doctl compute droplet list --format ID,Name --no-header | awk -v n="${DROPLET_NAME}" '$2==n {print $1; exit}')
[ -n "${DROPLET_ID}" ] || die "Droplet was created but its ID could not be read back"
IP=$(doctl compute droplet get "${DROPLET_ID}" --format PublicIPv4 --no-header)
[ -n "${IP}" ] || die "Droplet ${DROPLET_ID} has no public IPv4 yet; check: doctl compute droplet get ${DROPLET_ID}"
info "Droplet ID ${DROPLET_ID}, IP ${IP}"

# --- wait for SSH as rob, then for cloud-init to finish ----------------------
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="${HOME}/.ssh/known_hosts")
if [ -n "${ROB_SSH_IDENTITY_FILE}" ]; then
    SSH_OPTS+=(-i "$(expand_tilde "${ROB_SSH_IDENTITY_FILE}")")
fi

info "Waiting up to ${SSH_WAIT_SECONDS}s for SSH as rob@${IP}..."
deadline=$(( $(date +%s) + SSH_WAIT_SECONDS ))
until ssh "${SSH_OPTS[@]}" "rob@${IP}" true 2>/dev/null; do
    [ "$(date +%s)" -lt "${deadline}" ] || die "SSH not reachable after ${SSH_WAIT_SECONDS}s. Console: doctl compute droplet get ${DROPLET_ID}"
    sleep 10
done
info "SSH is up. Waiting for cloud-init to finish (packages, Composer, toolkit; the box may reboot once)..."
# cloud-init status --wait blocks until done; a reboot drops the connection, so loop.
until ssh "${SSH_OPTS[@]}" "rob@${IP}" 'cloud-init status --wait >/dev/null 2>&1; cloud-init status' 2>/dev/null | grep -Eq 'status: (done|error)'; do
    [ "$(date +%s)" -lt "${deadline}" ] || { warn "cloud-init still running after ${SSH_WAIT_SECONDS}s; check /var/log/cloud-init-output.log on the box"; break; }
    sleep 15
done
ssh "${SSH_OPTS[@]}" "rob@${IP}" 'cloud-init status --long' 2>/dev/null || true

echo
info "server04 is up: ${IP}"
cat <<EOF

Next steps:
  1. Add to ~/.ssh/config:
       Host server04
         Hostname ${IP}
         User rob
         IdentityFile ${ROB_SSH_IDENTITY_FILE:-~/.ssh/<your key>}
  2. Verify:   ${SCRIPT_DIR}/verify-droplet.sh server04
  3. First login (sets the MariaDB root password, never stored here):
       ssh server04 ~/first-login.sh
  4. Point DNS at ${IP}, then per site: create_site_structure, create_database,
     create_vhost, sudo certbot --apache -d <domain>   (see provision-site/toolkit/README.md)
EOF
