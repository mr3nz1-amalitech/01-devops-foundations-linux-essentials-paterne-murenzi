# AI Log

The rubric says thoughtful rejection scores higher than blind acceptance, so the
rejections matter more than the acceptances. Keep adding as you work.

## Session 1 — 2026-09-04 — Claude Code (Opus 5)

**Prompt:** "Cover anything that's pending, document commands, we'd use.
Scripts, document, docs I'd run. Instructions are in pngs in the instructions
folder." Then: "Simplify it, remove over engineering, and a lot of comments."

**Given:** the four instruction PNGs, `server-baseline-policy.md`, the repo
(branches, log, reflog), `DevOps_DORA_CALMS.docx`, and Module 02's layout.

**Produced:** `PENDING.md`, the scripts in `scripts/`, the docs here,
`hooks/pre-commit`, `systemd/kente-health.*`.

### Accepted

| Output | Why |
|---|---|
| The layered triage order in `diagnose-network.sh` | Matches how I'd debug it, and each layer narrows the next. The loopback-vs-NIC split is the test that separates "app broken" from "network broken". |
| Splitting `find -type d` / `-type f` instead of `chmod -R 750` | `chmod -R` would mark data files executable. Verified on a scratch dir. |
| The `usermod -aG` warning | Confirmed in `man usermod`: `-G` without `-a` replaces the whole supplementary group list. |
| `--force-with-lease` over `--force` | Refuses if the remote moved since my last fetch — the difference between overwriting my rewrite and overwriting a colleague's work. |
| Flagging `git user.email` as the previous engineer's | Real, and I hadn't noticed. Verified with `git config --local --list`. |
| Recovering orphaned commit `beb34ca` first | Confirmed with `git show --stat beb34ca` that it holds the hook and gitignore rules, and nothing references it. |

### Rejected or corrected

| Output | Problem | Instead |
|---|---|---|
| First version of everything | Genuinely over-engineered: two scripts (`audit-server.sh` and `verify-server.sh`) checked the same policy, the hook had a shell-syntax gate unrelated to secrets, and `COMMANDS.md` was 769 lines. | Folded verify into audit with a `--remote` flag, cut the hook to the two gates that are actually about secrets, halved the docs. |
| `FILE_MODE` defaulting to `640` | Least-privilege is the better engineering answer, but the policy says 750 on "everything under it". Picking the nicer answer over the written requirement is overriding the client's standard. | Literal `750` default, `--file-mode 640` available, ambiguity logged as a question (`ASSUMPTIONS_LOG.md` §3). |
| "Just `firewall-cmd --add-port` and move on" | Makes the test pass without establishing which layer was blocking. The diagnosis *is* the deliverable. | `remediate-server.sh` refuses to touch the firewall without `--open-port`. |
| Generic DORA/CALMS prose (the existing DOCX) | Accurate, but a definitions handout. The criterion needs *this incident* tied to a named DORA metric. | Rewrote `ONBOARDING.md` around MTTR and this outage; kept the DOCX as reference. |
| A `set -e` bug it introduced while simplifying the hook | The content-scan subshell ended on a false `[ -n ]` test, so `set -e` aborted and **every** commit was blocked, including clean ones. Caught by testing, not by reading. | Ended the subshell with `true`. Retested all 7 cases. |

### Not verified — don't defend these until you've run them

- Only `scan-secrets.sh`, `verify-repo.sh`, `parse-logs.sh`, the hook, and
  `remediate-server.sh --dry-run` have actually run, and only on Windows/git-bash.
- **Nothing has run on a Linux server.** `audit-server.sh`,
  `diagnose-network.sh`, `health-check.sh` and the real remediation are untested.
- `find -printf` is GNU-only. Fine on Amazon Linux/Ubuntu, not on Alpine.
- `parse-logs.sh` section 5 assumes combined-access-log field positions (`$9`).
  Check against the supplied log.
- The systemd units haven't been loaded. `systemd-analyze verify` them first.

### How I used it

To enumerate the surface area and draft boilerplate fast — not as the source of
truth for what's wrong with this server. Every finding about the actual sandbox
still has to come from running the audit.

## Session 2 — [date] — [tool]

**Prompt:**

**Accepted:**

**Rejected, and why:**
