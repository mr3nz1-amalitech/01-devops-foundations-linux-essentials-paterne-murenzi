#!/usr/bin/env bash
# Repo acceptance test: merge resolved, work merged, secret purged, convention
# documented, plus the process-evidence checks.
#
#   ./scripts/verify-repo.sh [--main main] | tee evidence/07-repo.txt
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. scripts/lib/common.sh

MAIN=""
[ "${1:-}" = "--main" ] && MAIN="${2:-}"
if [ -z "$MAIN" ]; then
  for b in main master develop; do
    git show-ref --verify -q "refs/heads/$b" && { MAIN=$b; break; }
  done
fi
: "${MAIN:=main}"
info "integration branch: $MAIN"

section "No unresolved merge"
[ -e .git/MERGE_HEAD ] || [ -e .git/rebase-merge ] || [ -e .git/rebase-apply ] \
  && fail "mid-merge or mid-rebase" || pass "no merge/rebase in progress"
[ -z "$(git ls-files -u)" ] && pass "index is clean" || fail "unmerged index entries"
# Committed markers pass `git status` and break production.
m=$(git grep -nE '^(<<<<<<< |=======$|>>>>>>> )' -- . ':(exclude)docs/*' 2>/dev/null)
[ -z "$m" ] && pass "no conflict markers" || { fail "conflict markers:"; echo "$m" | list; }

section "Feature work merged into $MAIN"
if git show-ref --verify -q "refs/heads/$MAIN"; then
  u=$(git branch --no-merged "$MAIN" 2>/dev/null | sed 's/^[* ]*//')
  [ -z "$u" ] && pass "all local branches merged" || { fail "not merged:"; echo "$u" | list; }
else
  fail "branch '$MAIN' does not exist"
fi

section "Secret purged from history"
if ./scripts/scan-secrets.sh --verify >/dev/null 2>&1; then
  pass "scan-secrets.sh --verify is clean"
else
  fail "secrets still found — run ./scripts/scan-secrets.sh"
fi
[ -d .git/filter-repo ] && pass "history was rewritten with git-filter-repo" \
  || warn "no filter-repo artefacts — confirm the purge was a rewrite, not a delete-forward commit"

section "Required documents"
for f in docs/ONBOARDING.md docs/BRANCHING.md docs/BRANCHING_RECOMMENDATION.md \
         docs/ASSUMPTIONS_LOG.md docs/AI_LOG.md docs/INCIDENT_REPORT.md; do
  [ -r "$f" ] && pass "$f" || fail "$f missing"
done
if [ -r docs/ONBOARDING.md ]; then
  grep -qiE 'deployment frequency|lead time|change failure|time to restore|mttr' docs/ONBOARDING.md \
    && pass "onboarding names a DORA metric" || fail "onboarding names no DORA metric"
  grep -qiE 'calms|culture|automation' docs/ONBOARDING.md \
    && pass "onboarding covers CALMS" || fail "onboarding does not cover CALMS"
fi

section "Process evidence"
n=$(git rev-list --count HEAD 2>/dev/null)
[ "${n:-0}" -ge 5 ] && pass "$n commits — not one squash" \
  || fail "only ${n:-0} commit(s); the criterion wants a meaningful history"
git log --format='        %h %an  %s' -15 2>/dev/null
lazy=$(git log --format='%s' 2>/dev/null | grep -icE '^(wip|fix|update|changes|stuff|temp)$')
[ "${lazy:-0}" = 0 ] && pass "no placeholder subjects" || fail "$lazy placeholder subject(s)"
me=$(git config user.email)
case "$me" in
  ""|*noreply*|*mr3nz1*)
    fail "git user.email is '$me' — commits are not attributed to you:"
    echo '        git config user.email "paterne.murenzi@amalitech.com"' ;;
  *) pass "committing as $me" ;;
esac

section "Hygiene"
grep -qE '^\.env' .gitignore 2>/dev/null && pass ".gitignore excludes .env" || fail ".gitignore does not exclude .env"
if [ -x hooks/pre-commit ]; then
  pass "hooks/pre-commit is executable"
  [ "$(git config core.hooksPath)" = hooks ] && pass "core.hooksPath=hooks" \
    || warn "run: git config core.hooksPath hooks"
else
  warn "hooks/pre-commit missing"
fi

summary
