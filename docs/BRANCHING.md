# Branching Convention

The rule the previous setup was missing. Short on purpose.

## Model: trunk-based

`main` is the trunk and is always releasable. Everything else is a short-lived
branch off `main` that merges back within **two days**.

## Names

```
feat/<description>      feat/checkout-retry
fix/<description>       fix/orders-null-customer
chore/<description>     chore/bump-node-20
hotfix/<description>    hotfix/health-endpoint-500
docs/<description>      docs/onboarding
```

Lower case, hyphens. Ticket numbers go in the PR, not the branch name.

## Rules

1. **Branch from `main`, merge to `main`.** No `develop`, no `release/*` —
   those were part of what tangled this repo.
2. **Two days maximum.** Longer work goes behind a feature flag and merges
   incomplete. Long-lived branches caused the conflict that blocked the release.
3. **One PR, one reviewer, always** — even for one line. It's the only thing
   stopping one person from being the only one who knows how this works.
4. **Merge with `--no-ff`.** Never squash a multi-commit branch; the history is
   the audit trail.
5. **Delete the branch after merging** with `git branch -d` (lower-case, so it
   refuses if the work isn't actually merged).
6. **Rebase to update, merge to land.** `git pull --rebase origin main`
   mid-branch; `--no-ff` merge to deliver. Never rebase a branch someone else
   has pulled.
7. **No secrets, ever.** `hooks/pre-commit` enforces it —
   `git config core.hooksPath hooks`. Real values live in `/etc/kente/app.env`
   on the server; the repo carries `.env.example` with placeholders.
8. **`main` is protected.** No direct pushes, no force pushes, one approving
   review.

## Commit messages

```
<type>(<scope>): <what changed, imperative>

<why it changed — the part still useful in six months>
<what you verified, if not obvious>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`.

Good:

```
fix(net): permit 8080/tcp in firewalld

Monday's release was blocked because firewalld dropped external traffic while
loopback kept returning 200 — so the app was healthy and only the host
firewall was at fault.

Verified: curl http://<public-ip>:8080/health -> 200 from off-host.
```

Not good: `fix`, `update`, `wip`, `changes`.

## Releases

Tag `main` on deploy; the tag is what you roll back to. Never move a pushed tag.

```bash
git tag -a v1.1.0 -m "Add checkout retry; fix null-customer crash"
git push origin v1.1.0
```

Reasoning for trunk-based over git flow: `docs/BRANCHING_RECOMMENDATION.md`.
