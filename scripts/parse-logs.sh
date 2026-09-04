#!/usr/bin/env bash
# The log-parsing task: grep/sed/awk pipelines that narrow the network fault.
# Prints each pipeline before running it, so any one can be re-run by hand.
#
#   ./scripts/parse-logs.sh <logfile> | tee evidence/05-log-analysis.txt
#   ./scripts/parse-logs.sh --journal kente-retail
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

if [ "${1:-}" = "--journal" ]; then
  LOG="evidence/journal-${2:-kente-retail}.log"
  mkdir -p evidence
  journalctl -u "${2:-kente-retail}" --no-pager -o short-iso > "$LOG" || exit 1
  info "captured to $LOG"
else
  LOG="${1:-}"
fi
[ -r "${LOG:-}" ] || { echo "usage: $0 <logfile> | --journal <unit>" >&2; exit 2; }

show() { printf '\n  $ %s\n' "$1"; sh -c "$1" 2>/dev/null | list; }
info "$LOG — $(wc -l < "$LOG") lines"

section "1. What failure words does this log use?"
show "grep -oiE 'refused|timed? ?out|unreachable|reset by peer|EACCES|EADDR|denied' '$LOG' | tr A-Z a-z | sort | uniq -c | sort -rn"

section "2. What address and port is the app really on?"
show "grep -oiE 'listening on( port)? [0-9.:]+|0\.0\.0\.0:[0-9]+|127\.0\.0\.1:[0-9]+' '$LOG' | sort | uniq -c"

section "3. Which clients failed?"
show "grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' '$LOG' | sort | uniq -c | sort -rn | head -15"

section "4. When did it start?"
show "grep -iE 'refused|timed? ?out|denied' '$LOG' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}' | sort | uniq -c"
show "grep -niE 'refused|timed? ?out|denied' '$LOG' | head -3"

section "5. Status codes (if this is an access log)"
show "awk '\$9 ~ /^[1-5][0-9][0-9]\$/ {c[\$9]++} END {for (s in c) print s, c[s]}' '$LOG' | sort -k2 -rn"

section "6. Distinct failure shapes, not instances"
show "grep -iE 'refused|timed? ?out|denied|error' '$LOG' | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:.,+Z-]+/<TS>/g; s/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g; s/[0-9]+/<N>/g' | sort | uniq -c | sort -rn | head"

cat <<'EOF'

Report the fact in this shape, in docs/INCIDENT_REPORT.md:

  "<n> attempts from <range> were refused starting <timestamp>, while
   127.0.0.1 kept returning 200 — so the app was healthy and something
   host-local was dropping external traffic."
EOF
