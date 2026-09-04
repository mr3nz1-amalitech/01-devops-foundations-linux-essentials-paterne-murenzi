#!/usr/bin/env bash
# Layered triage for "the app is not reachable". Prints each command so any
# single check can be re-run by hand during the walkthrough.
#
#   ./scripts/diagnose-network.sh [--remote <public-ip>]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

REMOTE=""
[ "${1:-}" = "--remote" ] && REMOTE="${2:-}"
PORT=$(app_port)
CAUSE=""
cause() { [ -n "$CAUSE" ] || CAUSE="$*"; }
show() { printf '\n  $ %s\n' "$1"; sh -c "$1" 2>/dev/null | list; }

section "1. Is the process running?"
show "pgrep -af 'node.*index\.js'"
pgrep -f 'node.*index\.js' >/dev/null 2>&1 \
  && pass "process found" || { fail "no node process"; cause "the app is not running at all"; }

section "2. Is it listening, and where?"
show "ss -tlnp"
line=$(ss -tlnp 2>/dev/null | grep -E "[:.]$PORT[[:space:]]")
if [ -z "$line" ]; then
  fail "nothing bound to $PORT"
  cause "no listener on $PORT — app down, or on a different port"
elif echo "$line" | grep -qE '127\.0\.0\.1:|\[::1\]:'; then
  fail "bound to loopback only"
  cause "bound to 127.0.0.1 — reachable only from this host; bind 0.0.0.0"
else
  pass "bound to a routable address"
fi

section "3. Does loopback answer?"
show "curl -sS -m 5 -i http://127.0.0.1:$PORT/health"
code=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null)
if [ "$code" = 200 ]; then
  pass "200 — the app is healthy, so this is a network fault"
else
  fail "got ${code:-no response}"
  cause "the app does not serve /health locally — fix the app, not the firewall"
fi

section "4. Does the primary interface answer?"
ip=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$ip" ]; then
  code=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://$ip:$PORT/health" 2>/dev/null)
  if [ "$code" = 200 ]; then
    pass "reachable on $ip — the fault is off-host"
  else
    fail "$ip gives ${code:-no response} while loopback works"
    cause "loopback works but $ip does not — a host-local filter or bind address"
  fi
fi

section "5. Host firewall"
if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
  show "firewall-cmd --list-all"
  firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | grep -qx "$PORT/tcp" \
    && pass "firewalld permits $PORT/tcp" \
    || { fail "$PORT/tcp not permitted"; cause "firewalld drops $PORT/tcp — firewall-cmd --permanent --add-port=$PORT/tcp && firewall-cmd --reload"; }
elif have iptables; then
  # Counters are the tell: the rule whose count climbs while you curl from
  # outside is the rule eating your traffic.
  show "iptables -L INPUT -nv --line-numbers"
  if iptables -S 2>/dev/null | grep -E "dport $PORT" | grep -qE ' -j (DROP|REJECT)'; then
    fail "a DROP/REJECT rule matches $PORT"
    cause "iptables rule blocks $PORT — delete by line number: iptables -D INPUT <n>"
  else
    pass "no rule obviously blocks $PORT"
  fi
fi
if have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
  show "ufw status verbose"
  ufw status | grep -q "$PORT" || { fail "ufw blocks $PORT"; cause "ufw blocks $PORT — ufw allow $PORT/tcp"; }
fi

section "6. SELinux"
if have getenforce && [ "$(getenforce)" = Enforcing ]; then
  show "ausearch -m avc -ts recent"
  if ausearch -m avc -ts recent 2>/dev/null | grep -q denied; then
    fail "recent AVC denials"
    cause "SELinux denies the bind — semanage port -a -t http_port_t -p tcp $PORT"
  else
    pass "no recent denials"
  fi
else
  info "SELinux not enforcing"
fi

section "7. Routing and /etc/hosts"
show "ip route"
show "grep -vE '^\s*(\$|#)' /etc/hosts"
ip route 2>/dev/null | grep -q '^default' \
  && pass "default route present" || { fail "no default route"; cause "no default route"; }

section "8. Upstream of this host"
if [ -n "$REMOTE" ]; then
  show "curl -sS -m 8 -i http://$REMOTE:$PORT/health"
  code=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' "http://$REMOTE:$PORT/health" 2>/dev/null)
  if [ "$code" = 200 ]; then
    pass "reachable at $REMOTE — end-to-end path open"
  else
    fail "$REMOTE gives ${code:-no response}"
    cause "works on the host but not from outside — the block is upstream (security group / NACL)"
  fi
  have nc && show "nc -vz -w 5 $REMOTE $PORT"
else
  info "pass --remote <public-ip> from your laptop to test the full path"
fi

section "Verdict"
[ -n "$CAUSE" ] && printf '%sLikely cause:%s %s\n' "$BLD" "$OFF" "$CAUSE" \
  || printf 'Every layer passed. Test from the real client with --remote.\n'
summary
