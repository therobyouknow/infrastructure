#!/usr/bin/env bash
# php_usn_poll.sh - from the workstation, watch one or more servers for a PHP
# security update in the Ubuntu archive and apply it the moment it lands.
#
# Local-dev script (macOS or Linux). It needs `php_security_update` installed
# on each server (install.sh) and sudo working non-interactively over SSH.
# Each poll runs `sudo php_security_update -c` on the server; when that finds
# a newer candidate it runs `sudo php_security_update -a -y -d` (detached, so
# an SSH drop cannot interrupt dpkg) and waits for the run's status file.
#
# Usage: php_usn_poll.sh [-i MINUTES] [-u HH:MM] [-n] [-f] ssh_host [ssh_host ...]
#
#   -i MINUTES  poll interval (default 10)
#   -u HH:MM    give up at this local time (default 23:30); a time already
#               past when the script starts means tomorrow, so an evening
#               start can run through the night
#   -n          check only; report when an update appears, never apply
#   -f          apply with -f (full-upgrade + autoremove) rather than PHP only
#
# Example: ./php_usn_poll.sh -i 10 -u 22:00 server03 server04 2>&1 | tee ~/php-usn-poll.log

set -euo pipefail

INTERVAL=10
UNTIL="23:30"
CHECK_ONLY=0
FULL=0

for arg in "$@"; do
    case "$arg" in
        --help) set -- -h ;;
    esac
done

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while getopts "hi:u:nf" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        i) INTERVAL="$OPTARG" ;;
        u) UNTIL="$OPTARG" ;;
        n) CHECK_ONLY=1 ;;
        f) FULL=1 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi
if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || [ "${INTERVAL}" -lt 1 ]; then
    echo "ERROR: -i takes whole minutes" >&2
    exit 1
fi
if ! [[ "${UNTIL}" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    echo "ERROR: -u takes HH:MM" >&2
    exit 1
fi
command -v ssh >/dev/null 2>&1 || { echo "ERROR: ssh not found" >&2; exit 1; }

PENDING="$*"
# Deadline as an epoch: today's HH:MM, or tomorrow's if that has passed.
NOW=$(date +%s)
SINCE_MIDNIGHT=$(( 10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S) ))
UNTIL_EPOCH=$(( NOW - SINCE_MIDNIGHT + 10#${UNTIL%%:*} * 3600 + 10#${UNTIL##*:} * 60 ))
if [ "${UNTIL_EPOCH}" -le "${NOW}" ]; then
    UNTIL_EPOCH=$(( UNTIL_EPOCH + 86400 ))
    UNTIL="${UNTIL} tomorrow"
fi
# Version each host had when we started, as "host=version" words, so an
# update installed by something else (unattended-upgrades overnight) is noticed.
FIRST_SEEN=""
APPLY_FLAGS="-a -y -d"
[ "${FULL}" -eq 1 ] && APPLY_FLAGS="${APPLY_FLAGS} -f"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $*"; }

# sudo over SSH: server03 has no NOPASSWD rule but an empty password, so plain
# sudo works only with stdin closed; server04 has NOPASSWD. </dev/null suits both.
remote() {
    local host=$1; shift
    ssh -n -o BatchMode=yes -o ConnectTimeout=20 "${host}" "sudo $* </dev/null"
}

apply_on() {
    local host=$1 run_dir status i
    log "${host}: applying (${APPLY_FLAGS})"
    # The detached run prints its run directory as the last line.
    run_dir=$(remote "${host}" "php_security_update ${APPLY_FLAGS}" | tee /dev/stderr | tail -1)
    if [ -z "${run_dir}" ] || ! [[ "${run_dir}" =~ ^/var/log/php-security-update/ ]]; then
        log "${host}: could not start the detached run (got '${run_dir}')"
        return 1
    fi
    # Wait up to 20 minutes for the status file to leave RUNNING.
    for i in $(seq 1 60); do
        sleep 20
        status=$(remote "${host}" "cat ${run_dir}/status" 2>/dev/null || echo "RUNNING")
        case "${status}" in
            RUNNING) ;;
            OK)
                log "${host}: OK"
                remote "${host}" "cat ${run_dir}/versions-after.txt" | sed 's/^/    /'
                return 0 ;;
            *)
                log "${host}: ${status}. Log on the server: $(dirname "${run_dir}")/detached-*.log and ${run_dir}/"
                remote "${host}" "tail -40 \$(ls -t $(dirname "${run_dir}")/detached-*.log | head -1)" | sed 's/^/    /' || true
                return 1 ;;
        esac
    done
    log "${host}: still RUNNING after 20 minutes; look at ${run_dir} by hand"
    return 1
}

log "Watching ${PENDING} every ${INTERVAL} min until ${UNTIL} (check only: ${CHECK_ONLY})"
FAILED=""
while [ -n "${PENDING}" ]; do
    if [ "$(date +%s)" -ge "${UNTIL_EPOCH}" ]; then
        log "Deadline ${UNTIL} reached with no update for: ${PENDING}"
        exit 2
    fi
    STILL=""
    for host in ${PENDING}; do
        if out=$(remote "${host}" "php_security_update -c" 2>&1); then
            log "${host}: UPDATE AVAILABLE"
            echo "${out}" | sed 's/^/    /'
            if [ "${CHECK_ONLY}" -eq 1 ]; then
                continue
            fi
            if ! apply_on "${host}"; then
                FAILED="${FAILED} ${host}"
            fi
        else
            rc=$?
            if [ "${rc}" -eq 10 ]; then
                ver=$(echo "${out}" | sed -n 's/.*PHP is current: \([^ ]*\).*/\1/p')
                first=$(echo "${FIRST_SEEN}" | tr ' ' '\n' | sed -n "s/^${host}=//p")
                if [ -z "${first}" ]; then
                    FIRST_SEEN="${FIRST_SEEN} ${host}=${ver}"
                elif [ "${ver}" != "${first}" ]; then
                    log "${host}: now ${ver} (was ${first}); updated by something else, probably unattended-upgrades. Checking the sites:"
                    remote "${host}" "php_security_update -b" | sed 's/^/    /' || true
                    continue
                fi
                log "${host}: current (${ver})"
            else
                log "${host}: check failed (exit ${rc}); will retry"
                echo "${out}" | tail -5 | sed 's/^/    /'
            fi
            STILL="${STILL} ${host}"
        fi
    done
    PENDING=$(echo "${STILL}" | sed 's/^ *//')
    [ -n "${PENDING}" ] && sleep $((INTERVAL * 60))
done
if [ -n "${FAILED}" ]; then
    log "Finished with failures on:${FAILED}"
    exit 1
fi
log "Finished: every server updated and verified"
