#!/usr/bin/env bash
# Find secrets in git history, and prove they are gone after the purge.
#
#   ./scripts/scan-secrets.sh            # report
#   ./scripts/scan-secrets.sh --verify   # exit 1 if anything is found
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

PATTERNS='AKIA[0-9A-Z]{16}
ASIA[0-9A-Z]{16}
-----BEGIN [A-Z ]*PRIVATE KEY-----
gh[pousr]_[A-Za-z0-9]{36}
xox[baprs]-[A-Za-z0-9-]{10,}
aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}
(mongodb|postgres|mysql|redis|amqp)://[^[:space:]]*:[^[:space:]@]+@'

section "1. Secret-shaped paths that ever existed"
paths=$(git log --all --oneline --name-only --diff-filter=A \
  -- '*.env' '.env' '*.pem' '*.key' '*id_rsa*' '*credentials*' 2>/dev/null)
[ -z "$paths" ] && pass "none" || { fail "found:"; echo "$paths" | list; }

section "2. Content of every commit tree"
revs=$(git rev-list --all 2>/dev/null)
if [ -z "$revs" ]; then
  warn "no commits"
else
  info "$(echo "$revs" | wc -l) commits"
  hit=0
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    out=$(git grep -I -n -E "$pat" $revs 2>/dev/null | head -10)
    [ -n "$out" ] && { fail "matched /$pat/"; echo "$out" | list; hit=1; }
  done <<< "$PATTERNS"
  [ "$hit" = 0 ] && pass "no pattern matched"
fi

section "3. Pickaxe — commits that added or removed a key"
# Catches a "fix" that only deleted the secret going forward.
hit=0
for n in AKIA 'PRIVATE KEY' aws_secret_access_key; do
  out=$(git log --all --oneline -S"$n" --pickaxe-all 2>/dev/null)
  [ -n "$out" ] && { fail "commits touching '$n':"; echo "$out" | list; hit=1; }
done
[ "$hit" = 0 ] && pass "nothing"

section "4. Unreachable objects — the purge's blind spot"
# After a rewrite the old blobs survive until the reflog is expired and gc'd.
blobs=$(git fsck --unreachable --no-progress 2>/dev/null | awk '$2=="blob"{print $3}')
if [ -z "$blobs" ]; then
  pass "none"
else
  warn "$(echo "$blobs" | wc -l) unreachable blob(s); scanning"
  hit=0
  for b in $blobs; do
    if git cat-file blob "$b" 2>/dev/null | grep -qE 'AKIA[0-9A-Z]{16}|PRIVATE KEY'; then
      fail "blob $b still holds a secret"; hit=1
    fi
  done
  [ "$hit" = 0 ] && pass "none contain secrets"
  info "drop them: git reflog expire --expire=now --all && git gc --prune=now"
fi

if have gitleaks; then
  section "5. gitleaks"
  gitleaks detect --source . --log-opts=--all --redact --no-banner 2>&1 | tail -20 | list
fi

section "Result"
if [ "$FAIL" -eq 0 ]; then
  pass "history is clean"
  echo
  echo "Purging is half the job: a secret that was ever pushed must be ROTATED"
  echo "at the provider. Note that in docs/ASSUMPTIONS_LOG.md."
else
  echo
  echo "Purge with git-filter-repo (docs/COMMANDS.md section 3). A new commit"
  echo "that deletes the file does NOT satisfy the acceptance criterion."
  [ "${1:-}" = "--verify" ] && exit 1
fi
summary
