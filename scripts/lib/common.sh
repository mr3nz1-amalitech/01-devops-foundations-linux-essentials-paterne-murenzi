#!/usr/bin/env bash
# Shared helpers. Sourced, not executed.

: "${APP_DIR:=/opt/kente-retail/app}"
: "${APP_ROOT:=/opt/kente-retail}"
: "${DEPLOY_USER:=deploy}"
: "${DEPLOY_GROUP:=deploy}"
: "${OPS_GROUP:=ops}"
: "${DEPLOY_HOME:=/home/deploy}"
: "${DEPLOY_SHELL:=/bin/bash}"
: "${HOSTNAME_RE:=^kente-[a-z0-9]+-[a-z0-9]+$}"
: "${DIR_MODE:=750}"
: "${FILE_MODE:=750}"

PASS=0; FAIL=0; WARN=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLD=$'\033[1m'; OFF=$'\033[0m'
else
  RED=''; GRN=''; YEL=''; BLD=''; OFF=''
fi

section() { printf '\n%s== %s ==%s\n' "$BLD" "$*" "$OFF"; }
pass() { PASS=$((PASS+1)); printf '%sPASS%s  %s\n' "$GRN" "$OFF" "$*"; }
fail() { FAIL=$((FAIL+1)); printf '%sFAIL%s  %s\n' "$RED" "$OFF" "$*"; }
warn() { WARN=$((WARN+1)); printf '%sWARN%s  %s\n' "$YEL" "$OFF" "$*"; }
info() { printf 'INFO  %s\n' "$*"; }
list() { sed 's/^/        /'; }

check() { # check "label" <test-exit-status>
  if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1"; fi
}

summary() {
  printf '\npass=%d fail=%d warn=%d\n' "$PASS" "$FAIL" "$WARN"
  [ "$FAIL" -eq 0 ]
}

have() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  [ "$(id -u)" -eq 0 ] && return 0
  printf 'must run as root: sudo -E %s\n' "$0" >&2
  exit 2
}

run() {
  if [ "${DRY_RUN:-0}" = 1 ]; then printf '  [dry-run] %s\n' "$*"; return 0; fi
  printf '  + %s\n' "$*"
  "$@"
}

# README says 8080, .env.example says 9080 — trust config over docs.
app_port() {
  [ -n "${APP_PORT:-}" ] && { echo "$APP_PORT"; return; }
  for f in .env "$APP_DIR/.env" .env.example; do
    [ -r "$f" ] || continue
    p=$(sed -n 's/^[[:space:]]*PORT[[:space:]]*=[[:space:]]*\([0-9]\{2,5\}\).*/\1/p' "$f" | head -1)
    [ -n "$p" ] && { echo "$p"; return; }
  done
  echo 8080
}
