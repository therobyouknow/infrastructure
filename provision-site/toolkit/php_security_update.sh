#!/usr/bin/env bash
# php_security_update.sh - check for, and apply, a PHP security update from
# the Ubuntu archive without taking the sites down unnoticed.
#
# Runs ON the server as root (sudo). Written for the PHP security releases
# that php.net announces on a Thursday and Canonical ships as a USN the same
# day or the next (see php-security-updates.md). unattended-upgrades would
# install it overnight; this applies it now and proves the sites still answer.
#
# Usage: php_security_update.sh -c | -b | -a [-f] [-d] [-y]
#
#   -c   check: apt-get update, then compare installed and candidate versions
#        of every installed PHP package. Exit 0 when an upgrade is available,
#        10 when everything is current.
#   -b   baseline only: record the HTTP status of every vhost name and print it.
#   -a   apply: baseline, back up /etc/php and /etc/apache2, mark the PHP
#        packages manually installed, upgrade only the PHP packages, reload
#        Apache / restart php-fpm as needed, take the baseline again and diff.
#        Exit 0 only when every vhost answers exactly as before.
#   -f   with -a: full-upgrade then autoremove (as separate steps) instead of
#        only the PHP packages. Bigger blast radius; use when the box is due
#        a general update anyway.
#   -d   with -a: detach. Re-executes itself under setsid/nohup so an SSH drop
#        cannot leave dpkg half-done, prints the run directory and returns at
#        once. Poll <run dir>/status for RUNNING, OK or FAIL.
#   -y   do not ask for confirmation before changing anything.
#
# Every run writes to /var/log/php-security-update/<timestamp>/ : baseline
# before and after, the apt log, the package versions, and a status file.
#
# Example: sudo php_security_update -c && sudo php_security_update -a -y -d

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

MODE=""
FULL=0
DETACH=0
ASSUME_YES=0
LOG_ROOT="/var/log/php-security-update"

for arg in "$@"; do
    case "$arg" in
        --help) set -- -h ;;
    esac
done

while getopts "hcbafdy" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        c) MODE=check ;;
        b) MODE=baseline ;;
        a) MODE=apply ;;
        f) FULL=1 ;;
        d) DETACH=1 ;;
        y) ASSUME_YES=1 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "${MODE}" ] || [ "$#" -ne 0 ]; then
    usage
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    print_error "Run with sudo (apt and the Apache config need root)"
    exit 1
fi

for tool in apt-get apt-cache dpkg-query curl systemctl apache2ctl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print_error "Required tool not found: $tool"
        exit 1
    fi
done

# --- helpers ----------------------------------------------------------------

# Installed PHP packages: the versioned ones (php8.3-cli, php8.5-fpm, ...) and
# the Apache module. The versionless metapackages (php-cli, php-mysql) are
# left out on purpose: they are what pulled a new major in on server02 when
# the PPA moved them (see memory: ppa-metapackage-autoremove-trap).
php_packages() {
    dpkg-query -W -f='${binary:Package} ${Status}\n' 2>/dev/null \
        | awk '$NF == "installed" && ($1 ~ /^php[0-9]+\.[0-9]+(-|$)/ || $1 ~ /^libapache2-mod-php[0-9]/) {print $1}'
}

# "package installed candidate" for each PHP package, from one apt-cache call.
php_versions() {
    # shellcheck disable=SC2046
    apt-cache policy $(php_packages) 2>/dev/null \
        | awk '/^[^ ]+:$/ {pkg = substr($1, 1, length($1) - 1)}
               /^  Installed:/ {inst = $2}
               /^  Candidate:/ {print pkg, inst, $2}'
}

# Every ServerName and ServerAlias in the enabled vhosts, once each.
vhost_names() {
    grep -h -E '^[[:space:]]*Server(Name|Alias)[[:space:]]' /etc/apache2/sites-enabled/*.conf 2>/dev/null \
        | awk '{for (i = 2; i <= NF; i++) print $i}' | sort -u
}

# HTTP status of every vhost name over https and http, resolved to this box,
# so the result does not depend on DNS or on a certificate being valid.
http_baseline() {
    local name code
    for name in $(vhost_names); do
        code=$(curl -s -o /dev/null -k -m 20 --resolve "${name}:443:127.0.0.1" -w '%{http_code}' "https://${name}/" || echo "000")
        echo "${name} https ${code}"
        code=$(curl -s -o /dev/null -m 20 --resolve "${name}:80:127.0.0.1" -w '%{http_code}' "http://${name}/" || echo "000")
        echo "${name} http ${code}"
    done
}

php_summary() {
    echo "php -v: $(php -v 2>/dev/null | head -1)"
    php_versions | awk '{print "  " $1 " " $2}'
}

apache_uses_mod_php() {
    apache2ctl -M 2>/dev/null | grep -q php_module
}

fpm_services() {
    systemctl list-units --type=service --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}'
}

# --- check -------------------------------------------------------------------

if [ "${MODE}" = "check" ]; then
    print_status "Refreshing package lists..."
    if ! apt-get update -qq > "/tmp/php_security_update.apt-update.$$" 2>&1; then
        cat "/tmp/php_security_update.apt-update.$$" >&2
        rm -f "/tmp/php_security_update.apt-update.$$"
        print_error "apt-get update failed"
        exit 1
    fi
    rm -f "/tmp/php_security_update.apt-update.$$"
    UPGRADABLE=0
    while read -r pkg installed candidate; do
        if [ "${installed}" != "${candidate}" ]; then
            echo -e "${YELLOW}UPGRADE${NC}  ${pkg}  ${installed} -> ${candidate}"
            UPGRADABLE=1
        fi
    done < <(php_versions)
    if [ "${UPGRADABLE}" -eq 1 ]; then
        print_status "A PHP upgrade is available"
        exit 0
    fi
    print_status "PHP is current: $(php_versions | awk '$1 ~ /^php[0-9.]+-cli$/ {print $2; exit}') ($(php_packages | wc -l) packages checked)"
    exit 10
fi

# --- baseline ----------------------------------------------------------------

RUN_DIR="${LOG_ROOT}/$(date +%Y%m%d-%H%M%S)"
mkdir -p "${RUN_DIR}"
chmod 750 "${RUN_DIR}"

if [ "${MODE}" = "baseline" ]; then
    http_baseline | tee "${RUN_DIR}/baseline-before.txt"
    php_summary | tee "${RUN_DIR}/versions-before.txt"
    print_status "Baseline written to ${RUN_DIR}/baseline-before.txt"
    exit 0
fi

# --- apply -------------------------------------------------------------------

# Detach: hand the real work to a session-less copy of ourselves so a dropped
# SSH connection cannot kill dpkg mid-upgrade. The redirect is done by the
# child's own shell, inside the root context.
if [ "${DETACH}" -eq 1 ]; then
    rmdir "${RUN_DIR}"  # the child makes its own
    DETACH_LOG="${LOG_ROOT}/detached-$(date +%Y%m%d-%H%M%S).log"
    FLAGS="-a -y"
    [ "${FULL}" -eq 1 ] && FLAGS="${FLAGS} -f"
    setsid nohup bash -c "exec \"$0\" ${FLAGS} > \"${DETACH_LOG}\" 2>&1" </dev/null >/dev/null 2>&1 &
    sleep 2
    # The child's run directory is the newest one; report it so a caller can poll.
    CHILD_DIR=$(ls -1d "${LOG_ROOT}"/20* 2>/dev/null | sort | tail -1)
    print_status "Detached. Log: ${DETACH_LOG}"
    print_status "Run directory: ${CHILD_DIR}  (poll ${CHILD_DIR}/status for RUNNING, OK or FAIL)"
    echo "${CHILD_DIR}"
    exit 0
fi

echo "RUNNING" > "${RUN_DIR}/status"
finish() {
    local rc=$?
    if [ "${rc}" -eq 0 ]; then
        echo "OK" > "${RUN_DIR}/status"
    else
        echo "FAIL ${rc}" > "${RUN_DIR}/status"
        print_error "Failed (exit ${rc}). Everything from this run is in ${RUN_DIR}"
    fi
}
trap finish EXIT

print_status "Run directory: ${RUN_DIR}"
print_status "Refreshing package lists..."
apt-get update -qq > "${RUN_DIR}/apt-update.log" 2>&1 || { cat "${RUN_DIR}/apt-update.log" >&2; print_error "apt-get update failed"; exit 1; }

print_status "PHP packages before:"
php_versions | tee "${RUN_DIR}/versions-before.txt" | awk '$2 != $3 {print "  " $1 " " $2 " -> " $3; n++} END {if (!n) print "  (nothing to upgrade)"}'
if [ "${FULL}" -eq 0 ] && ! php_versions | awk '$2 != $3 {found=1} END {exit !found}'; then
    print_warning "No PHP package has a newer candidate. Nothing to do (use -f for a general full-upgrade)."
    exit 0
fi

if [ "${ASSUME_YES}" -ne 1 ]; then
    read -r -p "Upgrade now? (yes/no): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        print_status "Cancelled"
        exit 0
    fi
fi

print_status "Taking HTTP baseline of every vhost..."
http_baseline > "${RUN_DIR}/baseline-before.txt"
awk '{print "  " $0}' "${RUN_DIR}/baseline-before.txt"

BACKUP="/root/pre-php-update-$(basename "${RUN_DIR}").tgz"
print_status "Backing up /etc/php and /etc/apache2 to ${BACKUP}"
tar czf "${BACKUP}" /etc/php /etc/apache2 2>/dev/null

print_status "Marking the installed PHP packages as manually installed (autoremove must never take them)"
# shellcheck disable=SC2046
apt-mark manual $(php_packages) >/dev/null

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
if [ "${FULL}" -eq 1 ]; then
    print_status "apt-get full-upgrade (log: ${RUN_DIR}/apt.log)..."
    # shellcheck disable=SC2086
    apt-get ${APT_OPTS} full-upgrade >> "${RUN_DIR}/apt.log" 2>&1
    print_status "apt-get autoremove..."
    # shellcheck disable=SC2086
    apt-get ${APT_OPTS} autoremove >> "${RUN_DIR}/apt.log" 2>&1
else
    print_status "apt-get install --only-upgrade of the PHP packages (log: ${RUN_DIR}/apt.log)..."
    # shellcheck disable=SC2046,SC2086
    apt-get ${APT_OPTS} install --only-upgrade $(php_packages) >> "${RUN_DIR}/apt.log" 2>&1
fi

# The packages restart php-fpm and reload Apache themselves; make sure of it,
# because an OPcache still holding old opcodes defeats the point.
for svc in $(fpm_services); do
    if systemctl is-active --quiet "${svc}"; then
        print_status "${svc} is running; reloading it"
        systemctl reload "${svc}" || systemctl restart "${svc}"
    else
        print_warning "${svc} is not running; starting it"
        systemctl start "${svc}"
    fi
done
if apache_uses_mod_php; then
    print_status "Apache runs mod_php; graceful reload"
    systemctl reload apache2
fi
if ! systemctl is-active --quiet apache2; then
    print_error "apache2 is not running after the upgrade"
    systemctl status apache2 --no-pager || true
    exit 2
fi
sleep 3

print_status "PHP packages after:"
php_summary | tee "${RUN_DIR}/versions-after.txt" | sed 's/^/  /'

print_status "Taking HTTP baseline again..."
http_baseline > "${RUN_DIR}/baseline-after.txt"
if diff "${RUN_DIR}/baseline-before.txt" "${RUN_DIR}/baseline-after.txt" > "${RUN_DIR}/baseline.diff"; then
    print_status "Every vhost answers exactly as before ($(wc -l < "${RUN_DIR}/baseline-after.txt") checks)"
else
    print_error "HTTP responses changed:"
    sed 's/^/  /' "${RUN_DIR}/baseline.diff"
    print_error "Config backup: ${BACKUP}. apt log: ${RUN_DIR}/apt.log"
    exit 3
fi

if [ -f /var/run/reboot-required ]; then
    print_warning "The system says a reboot is required (probably a kernel from the same update run, not PHP)"
fi
print_status "Done. PHP security update applied and verified."
