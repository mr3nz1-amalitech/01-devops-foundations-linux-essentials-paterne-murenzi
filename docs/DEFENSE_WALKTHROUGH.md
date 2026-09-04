# Defence Walkthrough

25% of the grade. The rubric: *"A learner who cannot explain a submitted
solution fails the defence component regardless of how it was produced."*

Two things must be **demonstrated**, not described: the secret is purged, and
the network fault is fixed.

## Before you start

```bash
script evidence/walkthrough-$(date +%Y%m%d).log     # record it
sudo -E ./scripts/audit-server.sh --remote <ip> | tail -3
./scripts/verify-repo.sh | tail -3
./scripts/scan-secrets.sh --verify; echo "exit=$?"
```

## Rough shape (15–20 min)

**Open with the conclusion**, not the journey:

> "Four things were wrong with the server, three with the repo. Every fix took
> minutes — the one that blocked Monday's release was `[the fault]`, and the app
> was healthy the whole time. The expensive problem was that all of this lived
> in one person's head."

**Repo (~4 min).** `git log --all --graph --oneline`. Point at the merge, say
what you chose and why. Then `git log --oneline | wc -l` and
`git branch --no-merged main` to show you didn't squash or leave work behind.

**The secret (~4 min).** Run it live:

```bash
git log --all --oneline -S'AKIA' --pickaxe-all    # it WAS there
git grep -I 'AKIA' $(git rev-list --all)          # gone from every tree
git fsck --unreachable | grep blob                # gone from the object store
./scripts/scan-secrets.sh --verify; echo "exit=$?"
```

Say the sentence that matters:

> "Purging the blob was the mechanical half. The credential still has to be
> rotated, because anyone who cloned before the rewrite still has a working
> copy. Purging limits future exposure; it does nothing about past exposure."

**Server (~5 min).** `sudo -E ./scripts/audit-server.sh`, then
`diff evidence/01-before.txt evidence/03-after.txt`. Then the network —
diagnosis first:

```bash
./scripts/diagnose-network.sh
```

> "Loopback returned 200 while the primary interface returned nothing. That one
> comparison proved the app was healthy and put the fault host-local — which is
> why I looked at `[layer]` and not at the code."

Then the proof, from your laptop not the server:
`curl -sS -i http://<public-ip>:8080/health`.

**The log fact (~2 min).** Re-run the pipeline live; don't read the answer off a
page.

**Value-add (~2 min).** Demo the approved one, then volunteer its limitation
before you're asked — it reads as competence.

**Close on DORA (~1 min).**

> "This was a Time-to-Restore failure. Repair was two minutes; everything else
> was detection and diagnosis, because nothing was watching and no runbook
> existed. So the two changes are a health probe and an audit script plus
> runbook — not a faster way to type `firewall-cmd`."

## The Day-2 incident

1. **Say what you're doing before you do it.** Thinking out loud *is* the graded
   artefact.
2. **Run the funnel** (`COMMANDS.md` §9) — what changed in the last hour, then
   diff the audit against the last known-good output.
3. **State a hypothesis, then the command that would disprove it.** "If it's the
   firewall, loopback still returns 200. Let me check."
4. **If stuck, say so and say what you'd try next.** Silence reads as not
   knowing.

## Questions you will get

**Why did you scope the audit that way?** The policy is the only written
definition of correct that exists, so it's the only defensible boundary. Going
further invents requirements the client hasn't agreed to, with a release
blocked. `ASSUMPTIONS_LOG.md` §1 lists what I left out.

**Why 750 on files? That marks data executable.** Agreed, least-privilege is
640. The policy says 750 on "everything under it", and when a written policy
disagrees with a convention the policy wins until the client changes it. I
flagged it as a question rather than silently reinterpreting their standard.

**Why trunk-based and not git flow?** Every problem I fixed traces to branches
living too long. Git flow assumes long-lived branches and adds a promotion step
that needs a person to shepherd it — on a two-person team that person is the
single point of failure that caused this.

**Why not squash the history?** Tidier, and it destroys the audit trail the
criteria ask for.

**Why not just disable the firewall?** It would have passed the test and been
the wrong fix. I opened one port scoped to one range.

**How much did AI write?** A lot of the boilerplate; `AI_LOG.md` has what I
accepted and rejected. Best example: it defaulted the file mode to 640 because
that's the better engineering answer, and I overrode it because it isn't what
the policy says. It also introduced a `set -e` bug in the hook that blocked
every commit — testing caught it, reading didn't. The log lists what I haven't
verified.

**What's still broken?** The previous engineer's access isn't revoked, `main`
isn't protected, there's no CI, and the bus factor is still one.
`EXECUTIVE_SUMMARY.md` has them in priority order.

## Avoid

- Reading an answer off a document — you'll be asked to re-run it.
- Claiming a script works when you haven't run it. `AI_LOG.md` has the
  unverified list; be straight about it.
- Fixing during diagnosis. Finish the diagnosis, state the conclusion, then fix.
- Defending a choice you don't believe. "Fair point, I'd change it to X" scores
  better.
