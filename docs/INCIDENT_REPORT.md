# Day-2 Incident Note

Fill in during or right after the live incident — the timestamps are the most
valuable part and the first thing you forget. Keep
`script evidence/day2.log` running.

## Incident

**Detected:** [time] by [the health timer / audit script / a failed curl]

**Symptom:** [what was observably wrong — a status code, a timeout, the exact
error]

**Impact:** [what a user or the release couldn't do]

## Timeline

| Time | Did | Told me |
|---|---|---|
| | `journalctl --since '-1h' -p warning` | |
| | `./scripts/audit-server.sh \| diff evidence/03-after.txt -` | |
| | | |

## Diagnosis

**What broke:** [the specific change — a rule, a permission, a stopped unit]

**How I established that rather than guessed:** [the one command whose output
was decisive, and why. This is the sentence the defence is graded on, e.g.
"`ss -tlnp` showed the listener had moved to 127.0.0.1 while loopback still
returned 200 — so the app was up and the bind address had changed, which ruled
out the firewall before I touched it."]

**Ruled out:** [thing] by [command]; [thing] by [command]

## Resolution

```bash
[the exact commands, including the verification]
```

**Evidence:** [paste the real curl output with the status line, not a
description of it]

**Time to restore:** [detected] → [resolved] = [N] min, of which diagnosis was
[N] and repair was [N]. *That split is the point — see the MTTR argument in
ONBOARDING.md.*

## What would have prevented it

Be concrete. "More monitoring" isn't an answer; "an external probe, because the
internal one returns 200 during exactly this failure mode" is.

1. **Prevention:** [why this control catches this failure]
2. **Detection:** [what would have shortened the detection half of MTTR]
3. **Recovery:** [what would have made the fix safe to apply blind]

## What this changes in the handover

- [ ] Command to add to `COMMANDS.md`, because you needed it and it wasn't there
- [ ] Check to add to `audit-server.sh`, because it would have caught this

*A Day-2 incident that changes none of the documentation means the
documentation wasn't really tested.*
