#!/usr/bin/env bash
# Audit the server against server-baseline-policy.md. Read-only.
#
#   sudo -E ./scripts/audit-server.sh | tee evidence/01-before.txt
#   ./scripts/audit-server.sh --remote <public-ip>    # also prove it off-host
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

REMOTE=""
[ "${1:-}" = "--remote" ] && REMOTE="${2:-}"
PORT=$(app_port)
info "expected port $PORT"

section "1. Deployment directory"
if [ ! -d "$APP_DIR" ]; then
  fail "$APP_DIR does not exist"
else
  got=$(stat -c '%U:%G %a' "$APP_DIR")
  want="$DEPLOY_USER:$DEPLOY_GROUP $DIR_MODE"
  check "$APP_DIR is $want (got $got)" "$([ "$got" = "$want" ]; echo $?)"

  bad=$(find "$APP_DIR" \( ! -user "$DEPLOY_USER" -o ! -group "$DEPLOY_GROUP" \) -printf '%p (%u:%g)\n' 2>/dev/null)
  [ -z "$bad" ] && pass "tree owned by $DEPLOY_USER:$DEPLOY_GROUP" || { fail "mis-owned paths:"; echo "$bad" | list; }

  bad=$(find "$APP_DIR" -type d ! -perm "0$DIR_MODE" -printf '%M %p\n' 2>/dev/null)
  [ -z "$bad" ] && pass "dirs are $DIR_MODE" || { fail "dirs not $DIR_MODE:"; echo "$bad" | list; }

  bad=$(find "$APP_DIR" -type f ! -perm "0$FILE_MODE" -printf '%M %p\n' 2>/dev/null)
  [ -z "$bad" ] && pass "files are $FILE_MODE" || { fail "files not $FILE_MODE:"; echo "$bad" | list; }

  # The policy's actual rationale is "no world access", so check it directly.
  bad=$(find "$APP_ROOT" -perm /o=rwx -printf '%M %p\n' 2>/dev/null)
  [ -z "$bad" ] && pass "nothing world-accessible" || { fail "world-accessible:"; echo "$bad" | list; }
fi

section "2. Users & groups"
if getent passwd "$DEPLOY_USER" >/dev/null; then
  pass "user $DEPLOY_USER exists"
  home=$(getent passwd "$DEPLOY_USER" | cut -d: -f6)
  shell=$(getent passwd "$DEPLOY_USER" | cut -d: -f7)
  check "home is $DEPLOY_HOME (got $home)" "$([ "$home" = "$DEPLOY_HOME" ]; echo $?)"
  check "shell is $DEPLOY_SHELL (got $shell)" "$([ "$shell" = "$DEPLOY_SHELL" ]; echo $?)"
else
  fail "user $DEPLOY_USER missing"
fi
if getent group "$OPS_GROUP" >/dev/null; then
  pass "group $OPS_GROUP exists"
  id -nG "$DEPLOY_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$OPS_GROUP" \
    && pass "$DEPLOY_USER is in $OPS_GROUP" || fail "$DEPLOY_USER not in $OPS_GROUP"
else
  fail "group $OPS_GROUP missing"
fi
for u in admin test ec2-user ubuntu jenkins; do
  getent passwd "$u" >/dev/null || continue
  find "$APP_ROOT" -user "$u" -print -quit 2>/dev/null | grep -q . \
    && fail "generic account '$u' owns paths under $APP_ROOT"
done

section "3. Hostname"
h=$(hostname); static=$(cat /etc/hostname 2>/dev/null)
info "running=$h  /etc/hostname=$static"
echo "$h" | grep -Eq "$HOSTNAME_RE" && pass "matches kente-<role>-<env>" || fail "'$h' does not match kente-<role>-<env>"
check "persisted in /etc/hostname" "$([ "$h" = "$static" ]; echo $?)"

section "4. Network (port $PORT)"
listen=$(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null)
if echo "$listen" | grep -qE "[:.]$PORT[[:space:]]"; then
  pass "listening on $PORT"
  echo "$listen" | grep -E "[:.]$PORT[[:space:]]" | list
  echo "$listen" | grep -E "[:.]$PORT[[:space:]]" | grep -qE '127\.0\.0\.1:|\[::1\]:' \
    && fail "bound to loopback only — unreachable from the class network" \
    || pass "bound to a routable address"
else
  fail "nothing listening on $PORT"
  echo "$listen" | list
fi

curl_code() { curl -sS -m 5 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null; }
code=$(curl_code "http://127.0.0.1:$PORT/health")
check "loopback /health -> 200 (got ${code:-none})" "$([ "$code" = 200 ]; echo $?)"
ip=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$ip" ]; then
  code=$(curl_code "http://$ip:$PORT/health")
  check "http://$ip:$PORT/health -> 200 (got ${code:-none})" "$([ "$code" = 200 ]; echo $?)"
fi
if [ -n "$REMOTE" ]; then
  curl -sS -m 8 -i "http://$REMOTE:$PORT/health" 2>&1 | head -5 | list
  code=$(curl_code "http://$REMOTE:$PORT/health")
  check "off-host http://$REMOTE:$PORT/health -> 200 (got ${code:-none})" "$([ "$code" = 200 ]; echo $?)"
else
  warn "no --remote: loopback success does not prove the class network can reach it"
fi

if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --list-all 2>/dev/null | list
  firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | grep -qx "$PORT/tcp" \
    && pass "firewalld permits $PORT/tcp" || fail "firewalld does not permit $PORT/tcp"
elif have iptables; then
  iptables -S 2>/dev/null | list
fi
have getenforce && info "SELinux: $(getenforce)"

section "Durability"
if systemctl cat kente-retail >/dev/null 2>&1; then
  systemctl is-enabled kente-retail >/dev/null 2>&1 \
    && pass "kente-retail unit is enabled" || fail "kente-retail unit not enabled — dies on reboot"
  systemctl is-active kente-retail >/dev/null 2>&1 \
    && pass "kente-retail is active" || fail "kente-retail is not active"
else
  warn "no systemd unit — app is running from a bare nohup and will not survive a reboot"
fi

summary
