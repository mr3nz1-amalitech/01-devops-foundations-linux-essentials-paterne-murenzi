# Command Runbook

Every command for the lab, in the order you would run them. Placeholders in
`<angle brackets>`.

## 0. Setup

The repo is configured with the previous engineer's identity — fix that before
your first commit, or the graded commit history is attributed to them.

```bash
cd base-repo
git config user.name  "Paterne Murenzi"
git config user.email "paterne.murenzi@amalitech.com"
git config core.hooksPath hooks
chmod +x hooks/pre-commit scripts/*.sh

python3 -m pip install --user git-filter-repo    # needed for section 3
sudo dnf install -y git curl jq nc iproute acl   # or apt-get on Debian
```

Keep a second SSH session open — you will lock yourself out of the first one
while working on the firewall.

## 1. Recon — change nothing yet

```bash
git log --all --graph --oneline --decorate
git status
git ls-files -u                                    # unmerged entries
ls .git/MERGE_HEAD 2>/dev/null                     # abandoned merge?
git grep -nE '^(<<<<<<< |=======$)' $(git rev-list --all)   # committed markers
git reflog --date=iso                              # work with no branch on it

sudo -E ./scripts/audit-server.sh | tee evidence/01-before.txt
```

## 2. Untangle the branches

Snapshot first — section 3 rewrites every commit.

```bash
git bundle create ../backup-$(date +%Y%m%d).bundle --all
```

Resolve the abandoned merge:

```bash
git diff --name-only --diff-filter=U
git checkout --conflict=diff3 -- <file>    # shows the common ancestor too
git log --merge -p -- <file>               # what each side did, and why
# resolve by hand, then
git add <file>
git diff --check
npm start & sleep 2; curl -sS localhost:8080/health; kill %1
git commit                                 # message says what you chose and why
```

Merge the outstanding work. `--no-ff` keeps the branch visible in history —
acceptance wants a meaningful history, not one squash.

```bash
git switch main || git switch -c main
git branch --no-merged main
git merge --no-ff feature/<x> -m "Merge feature/<x>: <what it delivers>"
git branch -d feature/<x>                  # -d refuses if not merged
```

If `develop` is the de-facto trunk: `git branch -M develop main && git push -u origin main`.

Recover the orphaned commit in this repo (`beb34ca`, on a detached HEAD, one
`git gc` from gone):

```bash
git branch recovered/pre-commit-hook beb34ca
git switch main && git cherry-pick beb34ca
```

## 3. Purge the committed secret

The criterion is *purged from history*, not deleted in a new commit — a
`git rm` leaves the blob reachable from every earlier commit.

Find it:

```bash
./scripts/scan-secrets.sh | tee evidence/06-secrets-before.txt

git grep -I -n -E 'AKIA[0-9A-Z]{16}' $(git rev-list --all)
git log --all --oneline -S'AKIA' --pickaxe-all
git log --all --diff-filter=A --name-only -- '*.env' '*.pem' '*.key'
```

Purge it:

```bash
cd .. && git clone --no-local base-repo purge-work && cd purge-work

# whole file was a secret
git filter-repo --invert-paths --path .env

# or, one line inside a file you keep
echo 'literal:AKIAIOSFODNN7EXAMPLE==>REDACTED' > /tmp/redact.txt
git filter-repo --replace-text /tmp/redact.txt
```

Expire the old objects — the step everyone forgets. Until this runs the secret
is still recoverable locally with `git fsck`.

```bash
git reflog expire --expire=now --expire-unreachable=now --all
git gc --prune=now
```

Prove it, then push:

```bash
./scripts/scan-secrets.sh --verify; echo "exit=$?"      # must be 0
git remote add origin <url>                             # filter-repo drops it
git push --force-with-lease --all origin
git push --force-with-lease --tags origin
```

**Then rotate the credential at the provider.** Anyone who cloned before the
rewrite still has a working copy, and so does every CI cache. Purging limits
future exposure only. Tell anyone with a clone to re-clone.

## 4. Fix the server

```bash
sudo -E ./scripts/remediate-server.sh --dry-run --hostname kente-app-prod01
sudo -E ./scripts/remediate-server.sh --hostname kente-app-prod01
sudo -E ./scripts/audit-server.sh | tee evidence/03-after.txt
```

By hand:

```bash
# users and groups first — you cannot chown to a user that doesn't exist
sudo groupadd --system deploy
sudo useradd -m -d /home/deploy -s /bin/bash -g deploy deploy
sudo groupadd ops
sudo usermod -aG ops deploy        # -a matters: -G alone replaces the group list

# split dirs from files; chmod -R 750 would mark data files executable
sudo chown -R deploy:deploy /opt/kente-retail
sudo find /opt/kente-retail -type d -exec chmod 750 {} +
sudo find /opt/kente-retail -type f -exec chmod 750 {} +

sudo hostnamectl set-hostname kente-app-prod01
echo '127.0.0.1 kente-app-prod01' | sudo tee -a /etc/hosts
```

> The policy says 750 "on the directory and everything under it", which
> literally means the executable bit on data files. The scripts default to that
> literal reading; `--file-mode 640` gives the least-privilege one. Record which
> you chose in the assumptions log.

Make it survive a reboot (not in the criteria; the CTO will ask):

```bash
sudo tee /etc/systemd/system/kente-retail.service >/dev/null <<'UNIT'
[Unit]
Description=Kente Retail order-service
After=network-online.target

[Service]
User=deploy
WorkingDirectory=/opt/kente-retail/app
Environment=PORT=8080
ExecStart=/usr/bin/node src/index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable --now kente-retail
```

## 5. Diagnose the network fault

Diagnose before you change. "I opened the port" scores worse than "loopback
returned 200 while the NIC returned nothing, so the app was fine".

```bash
./scripts/diagnose-network.sh --remote <public-ip> | tee evidence/02-network.txt
```

| Question | Command | If it fails |
|---|---|---|
| Process running? | `pgrep -af 'node.*index.js'` | app problem, not network |
| Listening where? | `ss -tlnp \| grep 8080` | nothing bound, or loopback-only |
| Loopback answers? | `curl -sS -i localhost:8080/health` | app fault — stop looking at the firewall |
| NIC answers? | `curl -sS -i http://$(hostname -I \| awk '{print $1}'):8080/health` | bind address or host filter |
| Firewall? | `firewall-cmd --list-all` / `iptables -L INPUT -nv` | port not permitted |
| SELinux? | `getenforce; ausearch -m avc -ts recent` | port not labelled |
| Routing? | `ip route; cat /etc/hosts` | bad hosts entry, no default route |
| Upstream? | `nc -vz <public-ip> 8080` from your laptop | security group / NACL |

The most useful trick — the rule whose counter climbs while you curl from
outside is the rule eating your traffic:

```bash
sudo iptables -Z
# curl from your laptop
sudo iptables -L INPUT -nv --line-numbers
```

Fixes:

```bash
# loopback-only bind: use server.listen(PORT) not listen(PORT,'127.0.0.1')
sudo systemctl restart kente-retail && ss -tlnp | grep 8080

sudo firewall-cmd --permanent --add-port=8080/tcp && sudo firewall-cmd --reload
diff <(sudo firewall-cmd --list-ports) <(sudo firewall-cmd --permanent --list-ports)

sudo iptables -L INPUT -n --line-numbers && sudo iptables -D INPUT <n>
sudo iptables-save | sudo tee /etc/sysconfig/iptables    # not persistent otherwise

sudo semanage port -a -t http_port_t -p tcp 8080

aws ec2 authorize-security-group-ingress --group-id <sg-id> \
  --protocol tcp --port 8080 --cidr <class-cidr>
```

Evidence — from your laptop, not the server:

```bash
./scripts/audit-server.sh --remote <public-ip> | tee evidence/04-verify.txt
curl -sS -i -m 8 http://<public-ip>:8080/health
```

## 6. Log parsing

```bash
./scripts/parse-logs.sh <log> | tee evidence/05-log-analysis.txt
```

The pipelines that carry the marks — you will be asked to re-run one live:

```bash
# what address/port is the app REALLY on, vs what the README claims
grep -oiE 'listening on( port)? [0-9.:]+|127\.0\.0\.1:[0-9]+' app.log | sort | uniq -c

# who failed — off-subnet clients failing while 127.0.0.1 gets 200s means a filter
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' app.log | sort | uniq -c | sort -rn | head

# when it started; the hour the count jumps is the change to correlate against
grep -iE 'refused|timed out' app.log | grep -oE '[0-9-]{10}T[0-9]{2}' | sort | uniq -c

# status codes and the paths that 4xx/5xx
awk '$9 ~ /^[1-5][0-9][0-9]$/ {c[$9]++} END {for (s in c) print s, c[s]}' access.log

# distinct failure shapes, not instances — 40k lines becomes five findings
grep -iE 'refused|denied|error' app.log \
  | sed -E 's/[0-9-]{10}T[0-9:.Z+-]+/<TS>/g; s/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP>/g; s/[0-9]+/<N>/g' \
  | sort | uniq -c | sort -rn | head
```

No log supplied? Use the server's own:

```bash
journalctl -u kente-retail --since '-2h' --no-pager -o short-iso
journalctl -k --since '-2h' --no-pager | grep -iE 'drop|reject'
```

## 7. Value-add

```bash
# A — the pre-commit hook. Prove it blocks:
printf 'AWS_SECRET_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE\n' > .env
git add -f .env && git commit -m test         # exit 1
git restore --staged .env && rm .env

# B — the health timer
sudo cp systemd/kente-health.* /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now kente-health.timer
systemctl list-timers kente-health.timer --no-pager

sudo systemctl stop kente-retail && sleep 150
journalctl -u kente-health -n 20 --no-pager | grep AUTO-RECOVERED
```

CI safety net, since a hook is client-side and `--no-verify` exists:

```yaml
# .github/workflows/secret-scan.yml
name: secret-scan
on: [push, pull_request]
jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: gitleaks/gitleaks-action@v2
```

## 8. Commits

Commit in visible steps — cadence is graded.

```
docs: add assumptions log with audit scoping decision
fix(repo): resolve inherited merge of feature/checkout into develop
chore(repo): purge committed AWS key from history with git-filter-repo
feat(ops): add server baseline audit script
fix(server): correct ownership and mode on /opt/kente-retail per policy 1
fix(net): permit 8080/tcp in firewalld, blocking Monday's release
docs: add onboarding one-pager and branching recommendation
feat(hooks): block committed secrets in pre-commit
```

## 9. Day-2 incident

Something changes mid-walkthrough. Run the funnel, don't guess.

```bash
# what changed in the last hour — always start here
sudo journalctl --since '-1h' -p warning --no-pager | tail -40
systemctl list-units --state=failed
sudo find /etc /opt/kente-retail -newermt '-2 hours' -type f 2>/dev/null | head

# the audit script is a drift detector
sudo -E ./scripts/audit-server.sh > evidence/09-day2.txt
diff evidence/03-after.txt evidence/09-day2.txt

./scripts/diagnose-network.sh --remote <ip>
git reflog --date=iso | head        # what someone just did, and the sha to return to
```

Recovering from the usual sabotage:

```bash
git reset --hard <sha-from-reflog>        # force-push / reset
git revert --no-commit <bad-sha>          # a bad commit
sudo -E ./scripts/remediate-server.sh --dry-run   # permissions widened again
```

Then write it up in `docs/INCIDENT_REPORT.md` while it is fresh.

## 10. Pre-submission gate

```bash
sudo -E ./scripts/audit-server.sh --remote <ip> | tee evidence/10-final-server.txt
./scripts/verify-repo.sh                        | tee evidence/11-final-repo.txt
./scripts/scan-secrets.sh --verify; echo "exit=$?"
```

All must end `fail=0`. Then:

- [ ] `main` clean, work merged `--no-ff`, no conflict markers
- [ ] Secret purged by rewrite and **rotated**
- [ ] Server: perms, users/groups, hostname pass
- [ ] Network fault diagnosed **and** proven fixed from off-host
- [ ] `evidence/05-log-analysis.txt` — the fact, with its pipeline
- [ ] `docs/ONBOARDING.md` — one page, lifecycle + CALMS + a DORA metric tied
      to this incident
- [ ] `docs/BRANCHING_RECOMMENDATION.md` — half a page
- [ ] `docs/ASSUMPTIONS_LOG.md`, `docs/AI_LOG.md`, `docs/INCIDENT_REPORT.md`
- [ ] `docs/VALUE_ADD_PROPOSAL.md` — two pitches, approved one built
- [ ] Commits are multi-step and attributed to you
