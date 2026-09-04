# Recommendation: trunk-based development

**To:** CTO · **Re:** Git flow or trunk-based, going forward

## Recommendation

Trunk-based. `main` is the trunk, always releasable; everything else is a
branch off it that merges back within two days.

## Why — from what actually went wrong here

Every problem I fixed traces to branches living too long:

- The **merge conflict** existed because two branches edited the same route
  block weeks apart. Merged within two days it would have been trivial.
- The **committed AWS key** survived because no PR review ever looked at that
  commit — it came along inside a bulk merge.
- The **history was unreadable** because branch-to-branch merges had crossed.

Git flow — `develop`, `release/*`, `hotfix/*` on top of `main` — adds ceremony
to exactly the thing that broke. It *assumes* long-lived branches, and needs
someone to shepherd promotions between them. On a two-person team that person is
a single point of failure, which is the failure mode that caused this.

It also fits the metric this incident failed. This was a Time-to-Restore failure
(see `ONBOARDING.md`); trunk-based puts a fix one short branch and one PR from
production, where git flow routes an urgent fix through `hotfix/*` and two
merges — and under pressure people bypass that, which is how undocumented state
gets created.

Smaller batches make review real, too. A reviewer reads a 40-line diff
properly; nobody reads a 900-line merge, which is how the secret got through.

## What it costs, honestly

- A genuinely three-week feature must merge incomplete behind a flag. That's
  real discipline and the main adoption cost.
- With no `develop` to absorb breakage, `main` must stay green — which is why
  branch protection and one required review are part of this recommendation,
  not optional.
- **Revisit this** if Kente Retail ever supports several customer versions at
  once. That's the one case where `release/*` branches earn their cost.

## What to put in place

1. `main` protected: no direct pushes, no force pushes, one approving review.
2. Branch naming and the two-day limit, per `docs/BRANCHING.md`.
3. `--no-ff` merges, so history shows when each branch landed.
4. Secret scanning in CI as well as the hook — the hook is bypassable.
5. Tag `main` on every deploy, so there's always a known-good commit.

**Bottom line:** the failure was long-lived branches and undocumented state.
Trunk-based attacks both. Git flow would formalise the first and do nothing
about the second.
