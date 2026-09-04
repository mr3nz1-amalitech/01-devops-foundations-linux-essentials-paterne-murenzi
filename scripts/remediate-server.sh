#!/usr/bin/env bash
# Bring the server into line with server-baseline-policy.md. Idempotent.
#
#   sudo -E ./scripts/remediate-server.sh --dry-run --hostname kente-app-prod01
#   sudo -E ./scripts/remediate-server.sh --hostname kente-app-prod01 [--open-port]
#
# Touches the firewall only with --open-port, so diagnose-network.sh names the
# blocking layer before anything changes.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

NEW_HOST=""; OPEN_PORT=0; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --hostname) NEW_HOST="${2:-}"; shift ;;
    --open-port) OPEN_PORT=1 ;;
    --file-mode) FILE_MODE="${2:-}"; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN
[ "$DRY_RUN" = 1 ] || need_root
PORT=$(app_port)

section "Users & groups"
getent group "$DEPLOY_GROUP" >/dev/null || run groupadd --system "$DEPLOY_GROUP"
getent group "$OPS_GROUP" >/dev/null || run groupadd "$OPS_GROUP"
if getent passwd "$DEPLOY_USER" >/dev/null; then
  [ "$(getent passwd "$DEPLOY_USER" | cut -d: -f6)" = "$DEPLOY_HOME" ] \
    || run usermod --home "$DEPLOY_HOME" --move-home "$DEPLOY_USER"
  [ "$(getent passwd "$DEPLOY_USER" | cut -d: -f7)" = "$DEPLOY_SHELL" ] \
    || run usermod --shell "$DEPLOY_SHELL" "$DEPLOY_USER"
else
  run useradd -m -d "$DEPLOY_HOME" -s "$DEPLOY_SHELL" -g "$DEPLOY_GROUP" "$DEPLOY_USER"
fi
# -a matters: usermod -G without it replaces the whole supplementary group list.
id -nG "$DEPLOY_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$OPS_GROUP" \
  || run usermod -aG "$OPS_GROUP" "$DEPLOY_USER"

section "Deployment directory"
[ -d "$APP_DIR" ] || run mkdir -p "$APP_DIR"
run chown -R "$DEPLOY_USER:$DEPLOY_GROUP" "$APP_ROOT"
# Split dirs from files: chmod -R 750 would mark data files executable.
run find "$APP_ROOT" -type d -exec chmod "$DIR_MODE" {} +
run find "$APP_ROOT" -type f -exec chmod "$FILE_MODE" {} +

section "Hostname"
if [ -z "$NEW_HOST" ]; then
  warn "no --hostname given; policy 3 wants kente-<role>-<env>"
elif ! echo "$NEW_HOST" | grep -Eq "$HOSTNAME_RE"; then
  fail "'$NEW_HOST' does not match $HOSTNAME_RE"
else
  run hostnamectl set-hostname "$NEW_HOST"
  # Without the hosts entry, sudo and reverse lookups stall.
  grep -qE "(^|[[:space:]])$NEW_HOST([[:space:]]|$)" /etc/hosts 2>/dev/null \
    || run sh -c "echo '127.0.0.1 $NEW_HOST' >> /etc/hosts"
fi

section "Network"
if [ "$OPEN_PORT" = 0 ]; then
  info "skipping firewall (pass --open-port once diagnose-network.sh names the layer)"
elif have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
  run firewall-cmd --permanent --add-port="$PORT/tcp"
  run firewall-cmd --reload
elif have ufw; then
  run ufw allow "$PORT/tcp"
elif have iptables; then
  run iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
  warn "iptables rules are not persistent — save them"
fi

info "next: sudo -E ./scripts/audit-server.sh --remote <ip> | tee evidence/03-after.txt"
summary
