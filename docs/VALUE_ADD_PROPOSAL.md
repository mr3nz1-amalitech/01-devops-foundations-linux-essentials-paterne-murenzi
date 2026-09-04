# Value-Add Proposal

Two hygiene improvements. Both built, so either can be demoed live.

## A — pre-commit hook that blocks secrets

**Built:** `hooks/pre-commit`. Enable with `git config core.hooksPath hooks`.

An AWS credential was committed to this repo. Removing it took a full history
rewrite, a reflog expiry, a gc, a force-push, and a re-clone for everyone — and
the credential still has to be treated as compromised and rotated. Hours of
work plus a security incident, caused by one `git add`.

The hook checks staged content only, in under a second:

1. **Secret-shaped filenames** — `.env`, `*.pem`, `*.key`, `id_rsa`,
   `*credentials*`. Blocked whatever the contents, since a `.pem` is a secret
   either way. `.env.example` and friends are allowed.
2. **Secret-shaped content** — AWS keys, private-key PEM headers, GitHub and
   Slack tokens. Reports the line number and pattern, never the secret itself —
   hook output ends up in scrollback and CI logs.

**ROI:** one grep per commit against a multi-hour rewrite plus rotation. No
service, no dependency, no scheduled job — a shell script in the repo, so the
next hire gets it by cloning.

**Limitation:** it's client-side. `--no-verify` bypasses it, and a fresh clone
does nothing until someone sets `core.hooksPath` (the `prepare` script in
`package.json` does that on `npm install`). The hook is prevention; enforcement
is the same scan in CI, where it can't be bypassed. I'd ship both —
`COMMANDS.md` §7 has the workflow.

## B — systemd timer that health-checks the service

**Built:** `scripts/health-check.sh`, `systemd/kente-health.service`, `.timer`.

The network fault was found by a human noticing a blocked release. The app was
healthy throughout — loopback returned 200 — and the repair was one
`firewall-cmd`. **All the downtime was detection and diagnosis, none of it was
repair.**

Every two minutes: curl `/health`, retry three times before declaring failure,
then log the listener and unit state to the journal and restart the unit.

**Why systemd not cron:** `systemctl list-timers` shows schedule, last run and
next run; a cron entry shows nothing until it fails. Output lands in the journal
on the same timeline as the service's own logs, with no file to rotate.
`Persistent=true` runs a probe missed while the box was down. The unit is
sandboxed; a cron job isn't. And retry-before-restart matters — a probe that
restarts on one timeout is worse than no probe.

**ROI:** detection drops from days to two minutes, and a crashed process
self-heals before anyone is paged. A direct attack on **MTTR**, the DORA metric
this incident failed. `grep AUTO-RECOVERED` in the journal also gives the first
real reliability data this service has produced.

**Limitation:** it probes from inside the box, so it would **not** have caught
this incident — loopback was healthy the whole time. It catches crashes, hangs
and OOM kills, not external reachability. The version that would have caught
Monday's fault probes the public address from another host.

## If I had to pick one

**A.** It prevents a failure that has already happened here and carries a
security cost, where B reduces the cost of a failure class that hasn't happened
(this one was reachability, which B would have missed). A also has no ongoing
operational surface — nothing to monitor, no risk of a flapping probe
restarting a healthy service.

If the answer is both: ship A this week, B next, and make B's probe external
from the start.
