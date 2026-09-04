# Executive Summary — Kente Retail Handover

**To:** CTO · **From:** Paterne Murenzi · **Date:** [TODO]

`[TODO]` needs a real finding. Don't submit with them in.

## Bottom line

The release was blocked by **[TODO: N]** misconfigurations, none of which took
more than a few minutes to fix. It's unblocked, and the server now matches your
baseline policy — verified by a script you can re-run yourself.

The expensive problem wasn't any of them. It was that the state of this system
existed only in one person's head, so a resignation became an outage. That's
what the scripts and documentation address.

## What was wrong

| # | Finding | Impact | Status |
|---|---|---|---|
| 1 | [TODO] `/opt/kente-retail/app` was `<owner>` mode `<nnn>`, not `deploy:deploy` 750 | Deploys failed, or ran with wider access than intended | Fixed |
| 2 | [TODO] `deploy` user / `ops` group missing or misconfigured | No non-root identity could deploy | Fixed |
| 3 | [TODO] Hostname left at the provider default | Unidentifiable in logs; breaks your naming standard | Fixed — `kente-app-prod01` |
| 4 | [TODO] `<the fault>` blocking `<port>/tcp` | **This blocked Monday's release.** The app was healthy the whole time | Fixed, proven off-host |
| 5 | AWS credential in git history | Anyone with clone access had a working key | Purged; **[TODO: rotated / sandbox-only]** |
| 6 | Unresolved merge and [TODO: N] long-lived branches | Nobody could tell what was releasable | Resolved and merged |
| 7 | Work stranded on a detached HEAD (`beb34ca`) | One `git gc` from silently losing it | Recovered |
| 8 | No monitoring on the app port | The outage was found by a blocked release, not a monitor | Fixed — 2-minute probe |

## Evidence, not assertions

```bash
sudo -E ./scripts/audit-server.sh --remote <public-ip>   # server + live proof
./scripts/verify-repo.sh                                  # repo state
./scripts/scan-secrets.sh --verify                        # secret is gone
```

All end `fail=0`. Before/after transcripts are in `evidence/`.

## Cost

**Infrastructure: no change.** Nothing resized, added or upgraded. The health
probe is a curl every two minutes.

**Engineering: [TODO: N] hours**, roughly [TODO]h diagnosis and [TODO]h
documentation and tooling. More than half went to documentation, deliberately —
the fixes were minutes, and the missing documentation is why this became a
crisis.

## Risks still open

1. **[TODO] The previous engineer's access hasn't been revoked.** Urgent, but
   revoking during an active incident risks cutting off automation nobody has
   mapped — needs half an hour of deliberate work, not a hurried `userdel`.
2. **The leaked credential must be treated as compromised.** Purging it from
   history does nothing about past exposure; anyone who cloned before the
   rewrite still has a working copy.
3. **`main` isn't branch-protected.** Nothing prevents a force-push recreating
   this. Needs repo-admin rights.
4. **No CI.** The pre-commit hook is client-side and `--no-verify` bypasses it.
5. **Bus factor is still one.** Documentation reduces it; a second person
   actually deploying once is what fixes it.
6. **Out of scope this pass** per policy §5: TLS, log rotation, backups.

## What I need from you

1. Confirm the app's port — `README.md` says 8080, `.env.example` says 9080.
   I reconciled to [TODO]; one of them is wrong.
2. Confirm the CIDR for "the class network". I opened the narrowest range I
   could verify; `0.0.0.0/0` would also have passed the test and been wrong.
3. Decide whether the leaked key needs rotating and disclosure.
4. Confirm this is the only server.
5. Approve one of the two improvements in `docs/VALUE_ADD_PROPOSAL.md`.

## For the next hire

`docs/ONBOARDING.md` (one page), `docs/BRANCHING.md` (the missing convention),
`docs/COMMANDS.md` (every command needed to audit or fix this box).
