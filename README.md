# Kente Retail — Order Service

Minimal HTTP service backing Kente Retail's order pipeline (sandbox copy for training).

## Running locally

```bash
npm start
```

Serves on port 8080 by default (override with `PORT`).

- `GET /health` — liveness check
- `GET /api/orders` — list orders (stubbed)

## Deployment

Deployed to `/opt/kente-retail/app` on the application server. See the ops team's
server-baseline-policy for the expected permissions, users, and hostname convention.

## Handover documentation

| Document | What it is |
|---|---|
| [`docs/ONBOARDING.md`](docs/ONBOARDING.md) | One page. Read first. Lifecycle, CALMS, and the DORA metric this incident hit. |
| [`docs/COMMANDS.md`](docs/COMMANDS.md) | Every command needed to audit or fix this service, in order. |
| [`docs/BRANCHING.md`](docs/BRANCHING.md) | The branching convention. |
| [`docs/BRANCHING_RECOMMENDATION.md`](docs/BRANCHING_RECOMMENDATION.md) | Why trunk-based, not git flow. |
| [`docs/EXECUTIVE_SUMMARY.md`](docs/EXECUTIVE_SUMMARY.md) | What was wrong, what was fixed, what risks remain. |
| [`docs/ASSUMPTIONS_LOG.md`](docs/ASSUMPTIONS_LOG.md) | Scoping decisions and open questions. |
| [`docs/VALUE_ADD_PROPOSAL.md`](docs/VALUE_ADD_PROPOSAL.md) | The two hygiene improvements. |
| [`docs/INCIDENT_REPORT.md`](docs/INCIDENT_REPORT.md) | Incident notes. |
| [`docs/AI_LOG.md`](docs/AI_LOG.md) | AI use: accepted, rejected, why. |

## Checking this service

```bash
sudo -E ./scripts/audit-server.sh --remote <public-ip>   # server vs policy + live proof
./scripts/verify-repo.sh                                  # repo state and hygiene
./scripts/scan-secrets.sh --verify                        # no secrets in history
./scripts/diagnose-network.sh                             # triage when unreachable
./scripts/parse-logs.sh <logfile>                         # log analysis
```

Each ends `pass=N fail=N warn=N`. `fail=0` is the bar.

Enable the secret-blocking hook once per clone (`npm install` also does it):

```bash
git config core.hooksPath hooks
```
