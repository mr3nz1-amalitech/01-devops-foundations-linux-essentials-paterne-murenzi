# Assumptions Log

The CTO said "tell me what's actually wrong" without saying how deep to go.
These are the decisions I made instead of asking. `[TODO]` needs a real
observation from the sandbox.

## 1. Audit scope

Covered exactly the four sections of `server-baseline-policy.md` plus the repo,
and stopped there. The policy is the only written definition of "correct" that
exists, so it is the only defensible boundary — and the release is blocked, so
breadth costs time I don't have.

Noted but not fixed: TLS, log rotation and backups (out of scope per policy §5);
OS patch level (patching mid-incident risks a second outage); SSH hardening
(changing sshd while it's my only access is how people lock themselves out);
anything AWS beyond the one blocked port.

## 2. What "handover-ready" means

A new engineer can, on day one without talking to me: run one command to check
the server (`audit-server.sh`), one to check the repo (`verify-repo.sh`), find
the fix in `COMMANDS.md`, and know the commit convention from `BRANCHING.md`.

The root cause wasn't any single misconfiguration — each was minutes to fix. It
was that the state lived in one person's head. So the check has to be
**executable**, not prose, or it rots the moment the server drifts. Cost: three
scripts took longer than a findings memo would have.

## 3. The 750 ambiguity

Policy §1 says `750` "on the directory and everything under it". Literally that
puts the executable bit on data files; least-privilege would be `750` dirs /
`640` files.

Defaulted to the literal reading, with `--file-mode 640` for the other. When a
written policy disagrees with a convention, the policy wins until the client
changes it — I don't get to reinterpret their standard silently. The stated
rationale ("no world access") holds either way.

**Question for the CTO:** is 750 on files intended, or should the policy say
750 dirs / 640 files?

## 4. Network fault

[TODO after running `diagnose-network.sh`] Fixed at layer `<N>` (`<which>`)
because `<the evidence — e.g. loopback returned 200 while the NIC returned
nothing>`.

Opened only the one port the release needs, scoped to `<CIDR>`, rather than
disabling the firewall. Disabling it would also have made the test pass and
would have been the wrong answer. Verified the fix survives a reload by
comparing firewalld runtime and permanent rules.

## 5. Secret purge and rotation

Purged with `git-filter-repo`, then expired the reflog and ran
`git gc --prune=now`, then force-pushed with `--force-with-lease`. A `git rm`
commit would leave the blob reachable from every earlier commit —
`git show <old-sha>:.env` would still print the key.

[TODO — state which] Either the key was rotated at the provider on `<date>`, or
it was a sandbox key with no live grants. **In a real engagement it must be
treated as compromised and rotated immediately**: everyone who cloned before the
rewrite still holds a working copy. Purging limits future exposure only.

The rewrite changed every commit SHA after the leak, so anyone with a clone must
re-clone. [TODO — confirm nobody else has one, or that they were told.]

## 6. Gaps found in the departed engineer's setup

| Gap | Fixed? | Reasoning |
|---|---|---|
| Orphaned commit `beb34ca` on a detached HEAD — real work, no ref, one `git gc` from gone | Yes | Recovered onto a branch. It held the pre-commit hook and the `.gitignore` secret rules. |
| `git user.email` was the previous engineer's, so my commits would be misattributed | Yes | Set my own identity first. Attribution is what makes history usable as an audit trail. |
| Port disagrees: `README.md` says 8080, `.env.example` says 9080 | [TODO] | Why the diagnosis started from what is actually listening, not what the docs claim. Settled on `<port>` because `<evidence>`. |
| App running from a bare `nohup` — dies with the shell, no reboot survival | [TODO] | Not in the criteria, but a release that vanishes on reboot isn't fixed. Unit in `COMMANDS.md` §4. |
| No `.gitignore` rule for `.env` | Yes | Cheapest prevention of a repeat, and the hook depends on the `.env` vs `.env.example` distinction. |
| No monitoring on the app port | Yes (value-add B) | The MTTR root cause: the outage was found by a blocked release, not a monitor. |
| No branch protection on the remote | [TODO] | Proposed; needs repo-admin rights I may not have. |

## 7. Questions I'd have asked the CTO

Recorded rather than asked, each with the assumption I proceeded on so nothing
was blocked:

1. **Expected port, 8080 or 9080?** → used whatever was actually listening.
2. **Which CIDR is "the class network"?** → the narrowest I could confirm. A
   `0.0.0.0/0` rule would have passed the test and been wrong.
3. **Is 750 on files intended?** → see §3.
4. **Was the leaked key ever live, and who owns rotation?** → changes whether
   this is a cleanup or a security incident with a disclosure obligation.
5. **Does anyone else have a clone?** → determines whether the force-push is
   safe or needs coordinating.
6. **Is this box prod or staging?** → policy §3 wants `kente-<role>-<env>`.
   Used `<chosen>`; trivially changeable.
7. **Is there a second server?** → a handover for one box that turns out to be
   one of four isn't a handover.

## 8. Chose not to do

- **Didn't squash the history.** Tidier, and it destroys the audit trail the
  criteria explicitly ask for.
- **Didn't revoke the previous engineer's SSH keys yet.** [TODO — note what you
  found.] Urgent, but revoking during an active incident risks cutting off
  automation nobody has mapped. First follow-up item.
- **Didn't disable the firewall** to make the test green.
- **Didn't upgrade Node or patch the OS** mid-diagnosis.
