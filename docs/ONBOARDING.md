# Kente Retail — Ops Onboarding

*For whoever picks this up next. One page. Read it before you touch anything.*

## What you inherited

Our only ops-adjacent engineer left on a Friday with no handover. By Monday the
release was blocked by a repo with long-lived branches, a half-resolved merge
and an AWS key in its history — and a server whose deploy directory had the
wrong owner and mode, whose `deploy` user and `ops` group were missing, whose
hostname was still the cloud default, and whose app port was blocked so nothing
outside the box could reach it.

Every one of those was minutes to fix. What made it a crisis is that **it was
only in one person's head.**

## The DevOps lifecycle, in the shape of this incident

Eight phases, a loop not a line: **Plan → Code → Build → Test → Release →
Deploy → Operate → Monitor →** back to Plan.

It broke at **Deploy** and **Operate**. Code got merged, but the path from
"merged" to "running and reachable" existed only as steps one person
remembered. And because nothing at **Monitor** watched the port, nobody knew
until a release was already blocked.

The lesson isn't "write more docs". It's: **if a step isn't written down or
automated, it doesn't exist.**

## CALMS — the five things that went wrong

CALMS asks whether an organisation is ready to work this way. Each pillar names
a real failure here:

- **Culture** — one person owned ops, so nobody else could deploy, so nobody
  else could check the work.
- **Automation** — permissions, users and hostname were set by hand and
  drifted. `scripts/audit-server.sh` now checks all of it in one command.
- **Lean** — three branches sat unmerged for weeks. Big batches hide problems;
  the merge conflict was the interest on that delay.
- **Measurement** — nothing watched the port. `kente-health.timer` now probes
  `/health` every two minutes.
- **Sharing** — no handover notes. This file, `BRANCHING.md` and `COMMANDS.md`
  are the fix, and they're in the repo rather than a notebook.

## The DORA metric this hit: Time to Restore Service

DORA measures delivery on four numbers: deployment frequency, lead time for
changes, change failure rate, and **time to restore service (MTTR)**. This
incident is squarely the last one.

The app was healthy the whole time — `curl 127.0.0.1:8080/health` returned 200
throughout. The only fault was a host-local rule dropping external traffic: a
two-minute fix. It still took days, because nothing was watching the port, no
runbook existed, and only one person had ever configured the box.

**MTTR is dominated by detection and diagnosis, not repair.** That's why the two
changes here are a health probe (cuts detection) and a runbook plus audit script
(cuts diagnosis) — not a faster way to type `firewall-cmd`.

Lead time suffered too: work sat merged-but-not-deployed because deploying
depended on one person being available.

## Your first week

1. Read `docs/BRANCHING.md` and follow it from your first commit.
2. Run `sudo -E ./scripts/audit-server.sh` and `./scripts/verify-repo.sh`. Both
   should end `fail=0`; if not, the system has drifted — which is what they're
   for.
3. Set your own git identity before committing.
4. If you need a command that isn't in `docs/COMMANDS.md`, that's a bug in the
   document. Fix it.

## The one rule

**Never commit a secret.** `hooks/pre-commit` will stop you, but it's
client-side and `--no-verify` exists. If one does get pushed, purging it from
history is half the job — **rotate it at the provider immediately**, because
everyone who cloned in the meantime still has a working copy.
