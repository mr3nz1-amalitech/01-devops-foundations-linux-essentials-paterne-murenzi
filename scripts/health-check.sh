#!/usr/bin/env bash
# Probe the order-service; restart it if unhealthy. Driven by
# systemd/kente-health.timer.
#
#   ./scripts/health-check.sh [--restart]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

RESTART=0; UNIT="${KENTE_UNIT:-kente-retail}"
[ "${1:-}" = "--restart" ] && RESTART=1
PORT=$(app_port)
URL="http://127.0.0.1:$PORT/health"

probe() { curl -sS -m 5 -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null; }

# Retry first: one timeout during a GC pause is not an outage, and a flapping
# probe that restarts a healthy service is worse than no probe.
for i in 1 2 3; do
  code=$(probe)
  [ "$code" = 200 ] && { echo "healthy: $URL -> 200"; exit 0; }
  echo "attempt $i/3: $URL -> ${code:-no response}"
  [ "$i" -lt 3 ] && sleep 2
done

echo "UNHEALTHY: $URL -> ${code:-no response}"
ss -tlnp 2>/dev/null | grep -E "[:.]$PORT[[:space:]]" || echo "nothing listening on $PORT"
systemctl status "$UNIT" --no-pager -n 10 2>/dev/null | tail -12

[ "$RESTART" = 1 ] || exit 1
systemctl restart "$UNIT" || exit 1
sleep 5
if [ "$(probe)" = 200 ]; then
  # grep the journal for this line to count silent recoveries.
  echo "kente-health: AUTO-RECOVERED $UNIT at $(date -Is)"
  exit 0
fi
echo "still unhealthy after restart — escalate"
exit 1
