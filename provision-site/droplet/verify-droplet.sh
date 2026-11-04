#!/usr/bin/env bash
# Post-create checklist for server04, run from your Mac over SSH.
#
#   ./verify-droplet.sh server04            # ssh config alias
#   ./verify-droplet.sh 1.2.3.4             # or an IP (user rob)
#   ./verify-droplet.sh rob@1.2.3.4 -i ~/.ssh/ssh_key_02
#
# Prints PASS/WARN/FAIL per check and exits non-zero if anything FAILed.
# Read-only apart from `sudo` reads (ufw/sshd/fail2ban need root to report).

set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }
TARGET="$1"; shift
[[ "${TARGET}" == *@* ]] || TARGET="rob@${TARGET}"

# Pure IP/hostname with no ssh-config alias still needs a user; alias entries
# carry their own user, so only prefix when the target looks like a host.
if [[ "${TARGET}" == rob@* ]] && ssh -G "${TARGET#rob@}" 2>/dev/null | grep -q '^user rob$'; then
    TARGET="${TARGET#rob@}"
fi

ssh -o BatchMode=yes -o ConnectTimeout=10 "$@" "${TARGET}" 'bash -s' <<'REMOTE'
# shellcheck disable=SC2015,SC2088,SC2012,SC1091  # "test && pass || fail" is the intended idiom; ~ is only in messages
set -u
fails=0; warns=0
pass() { printf '\033[0;32mPASS\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m  %s\n' "$*"; warns=$((warns+1)); }
fail() { printf '\033[0;31mFAIL\033[0m  %s\n' "$*"; fails=$((fails+1)); }
hdr()  { printf '\n== %s ==\n' "$*"; }

hdr "Host"
echo "hostname: $(hostname)   os: $(. /etc/os-release && echo "$PRETTY_NAME")   kernel: $(uname -r)"
echo "uptime:  $(uptime -p)   load: $(cut -d' ' -f1-3 /proc/loadavg)"
[ "$(id -un)" = rob ] && pass "logged in as rob" || fail "not logged in as rob ($(id -un))"
id -nG rob | tr ' ' '\n' | grep -qx www-data && pass "rob is in www-data" || fail "rob is not in www-data"
id -nG rob | tr ' ' '\n' | grep -qx sudo && pass "rob is in sudo" || fail "rob is not in sudo"
sudo -n true 2>/dev/null && pass "sudo works without password" || warn "sudo needs a password (fine if you set one)"

hdr "cloud-init"
ci=$(cloud-init status 2>/dev/null || true)
echo "${ci}"
case "${ci}" in
  *done*)  pass "cloud-init done" ;;
  *error*) fail "cloud-init reported errors (see /var/log/cloud-init-output.log)" ;;
  *)       warn "cloud-init not finished yet" ;;
esac
[ -f /var/log/server04-provision.log ] && { grep -q 'DONE' /var/log/server04-provision.log && pass "provision script reached DONE" || fail "provision script did not reach DONE (tail /var/log/server04-provision.log)"; } || fail "no /var/log/server04-provision.log"
grep -q WARNING /var/log/server04-provision.log 2>/dev/null && warn "provision log has WARNING lines: $(grep WARNING /var/log/server04-provision.log | head -2 | tr '\n' ';')"

hdr "sshd"
sshd_t=$(sudo sshd -T 2>/dev/null || true)
chk() { local key="$1" want="$2" got; got=$(echo "${sshd_t}" | awk -v k="$key" '$1==k {print $2; exit}')
        [ "${got}" = "${want}" ] && pass "sshd ${key} = ${got}" || fail "sshd ${key} = '${got}' (want ${want})"; }
chk permitrootlogin no
chk passwordauthentication no
chk kbdinteractiveauthentication no
chk pubkeyauthentication yes
echo "${sshd_t}" | grep -q '^allowusers rob$' && pass "sshd allowusers rob" || warn "sshd allowusers: $(echo "${sshd_t}" | grep '^allowusers' || echo unset)"
systemctl is-active -q ssh && pass "ssh service active" || fail "ssh service not active"

hdr "Firewall (ufw)"
ufw_s=$(sudo ufw status verbose 2>/dev/null || true)
echo "${ufw_s}" | grep -q '^Status: active' && pass "ufw active" || fail "ufw not active"
echo "${ufw_s}" | grep -q 'deny (incoming)' && pass "default deny incoming" || fail "default incoming is not deny"
for p in 22 80 443; do echo "${ufw_s}" | grep -Eq "^${p}/tcp +ALLOW IN" && pass "ufw allows ${p}/tcp" || fail "ufw does not allow ${p}/tcp"; done
extra=$(echo "${ufw_s}" | grep -E 'ALLOW IN' | grep -Ev '^(22|80|443)/tcp' | grep -v '(v6)' || true)
[ -z "${extra}" ] && pass "no other inbound rules" || warn "extra inbound rules: $(echo "${extra}" | tr '\n' ';')"

hdr "fail2ban"
if systemctl is-active -q fail2ban; then pass "fail2ban active"; sudo fail2ban-client status sshd 2>/dev/null | sed 's/^/      /' || fail "sshd jail not reporting"; else fail "fail2ban not active"; fi

hdr "Updates"
systemctl is-enabled -q unattended-upgrades 2>/dev/null && pass "unattended-upgrades enabled" || fail "unattended-upgrades not enabled"
grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null && pass "apt periodic unattended-upgrade on" || fail "20auto-upgrades missing"
[ -f /var/run/reboot-required ] && warn "reboot required (sudo reboot)" || pass "no reboot pending"

hdr "Time"
tds=$(timedatectl show 2>/dev/null || true)
echo "${tds}" | grep -q '^Timezone=Europe/London' && pass "timezone Europe/London" || fail "timezone: $(echo "${tds}" | grep '^Timezone')"
echo "${tds}" | grep -q '^NTPSynchronized=yes' && pass "NTP synchronized" || warn "NTP not (yet) synchronized"

hdr "Web stack"
apache2 -v 2>/dev/null | head -1 && (systemctl is-active -q apache2 && pass "apache2 active" || fail "apache2 not active") || fail "apache2 missing"
mods=$(sudo apache2ctl -M 2>/dev/null || true)
for m in mpm_event proxy_fcgi rewrite headers ssl; do echo "${mods}" | grep -q "${m}_module" && pass "apache mod ${m}" || fail "apache mod ${m} not loaded"; done
echo "${mods}" | grep -q 'php[0-9]*_module' && fail "mod_php loaded (should be php-fpm only)" || pass "no mod_php"
php -v 2>/dev/null | head -1 || fail "php missing"
fpm=$(systemctl list-units --type=service --state=running --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}' | head -1)
[ -n "${fpm}" ] && pass "${fpm} running" || fail "no php-fpm service running"
for ext in gd mbstring xml curl zip intl opcache mysqli pdo_mysql apcu; do
    php -m 2>/dev/null | grep -qi "^\(Zend \)\?${ext}$" && pass "php ext ${ext}" || fail "php ext ${ext} missing"; done
php -r 'echo "memory_limit=".ini_get("memory_limit")." upload_max_filesize=".ini_get("upload_max_filesize")."\n";' 2>/dev/null
mariadb --version 2>/dev/null || fail "mariadb client missing"
systemctl is-active -q mariadb && pass "mariadb active" || fail "mariadb not active"
sudo mariadb -e 'SELECT user,host,plugin FROM mysql.user WHERE user="root";' 2>/dev/null | sed 's/^/      /' || warn "could not query mariadb as root via sudo"
sudo mariadb -N -e 'SELECT COUNT(*) FROM mysql.user WHERE user="" ' 2>/dev/null | grep -qx 0 && pass "no anonymous mariadb users" || warn "anonymous mariadb users exist: run ~/first-login.sh (mariadb-secure-installation)"
composer --version --no-ansi 2>/dev/null | head -1 && pass "composer on PATH" || fail "composer missing"
[ -x /var/www/tools/dev/phpcomposer/composer.phar ] && pass "composer.phar at toolkit path" || fail "/var/www/tools/dev/phpcomposer/composer.phar missing"
drush --version 2>/dev/null | head -1 && pass "drush launcher on PATH" || warn "drush launcher not on PATH (use ./drush in each release)"
certbot --version 2>/dev/null && pass "certbot installed" || fail "certbot missing"
dpkg -s python3-certbot-apache >/dev/null 2>&1 && pass "certbot apache plugin" || fail "python3-certbot-apache missing"
command -v docker >/dev/null 2>&1 && warn "docker is installed (decision: no Docker on server04)" || pass "no docker"

hdr "Toolkit layout"
own=$(stat -c '%U:%G %a' /var/www 2>/dev/null || true)
[ "${own%% *}" = "rob:www-data" ] && pass "/var/www is rob:www-data (${own})" || fail "/var/www is ${own:-missing} (want rob:www-data)"
[ -d /home/rob/scripts ] && pass "~/scripts: $(ls /home/rob/scripts/*.sh 2>/dev/null | wc -l | tr -d ' ') scripts" || fail "/home/rob/scripts missing"
for c in deploy create_release create_site_structure create_vhost create_database site_status drush_run backup_db restore_db; do
    command -v "$c" >/dev/null 2>&1 || { fail "toolkit command '$c' not on PATH (sudo ~/scripts/install.sh)"; break; }; done
command -v deploy >/dev/null 2>&1 && pass "toolkit commands on PATH"
[ -x /home/rob/first-login.sh ] && pass "~/first-login.sh present" || warn "~/first-login.sh missing"

hdr "Disk / memory / swap"
df -h / | sed 's/^/      /'
free -h | sed 's/^/      /'
swapon --show --noheadings 2>/dev/null | grep -q . && pass "swap active: $(swapon --show --noheadings | awk '{print $1, $3}')" || fail "no swap"
use=$(df --output=pcent / | tail -1 | tr -dc '0-9'); [ "${use:-0}" -lt 80 ] && pass "root disk ${use}% used" || warn "root disk ${use}% used"

hdr "Summary"
echo "FAIL: ${fails}   WARN: ${warns}"
[ "${fails}" -eq 0 ]
REMOTE
