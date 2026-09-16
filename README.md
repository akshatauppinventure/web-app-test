# web-app-test — secure 2-VPS web app POC

A proof-of-concept "hello world" web application deployed on two hardened UpCloud VPS (New York) with a security-first design:

- **Edge VPS (A):** Traefik (TLS, routing, rate limits), CrowdSec (IPS/WAF), Next.js frontend (Auth.js BFF).
- **Core VPS (B):** Keycloak (identity, Google login), FastAPI backend (JWT validation), PostgreSQL 18 (Row-Level Security), Portainer Server (GitOps deploys).
- Hosts talk only over **WireGuard**; only ports 80/443 on the edge host are public.
- POC hostname: **`https://test-vinayak.duckdns.org`**.

## Where to look

| Document | Purpose |
|---|---|
| [`docs/adr/`](docs/adr/README.md) | The 24 accepted architecture decisions and their reasoning |
| [`PLAN.md`](PLAN.md) | Ordered task breakdown (T00–T25), sizes, tests and definition of done |
| [`docs/runbooks/`](docs/runbooks/README.md) | Operational procedures |
| [`docs/verification/`](docs/verification/README.md) | Recorded verification evidence |
| [`CLAUDE.md`](CLAUDE.md) | Working conventions for contributors and AI assistants |

## Repository layout (target)

```
backend/     FastAPI service (uv, Python 3.14)          — T01–T04
frontend/    Next.js 16 app (pnpm, Node 24)             — T06–T08
infra/       Images, stacks, host config, OpenTofu, secrets — T14–T19
scripts/     dev, ci, test, secrets and verify helpers
docs/        ADRs, runbooks, verification
.github/     CI/CD workflows, CODEOWNERS, PR template
```

## Working on the project

- One PR per task, branch `task/T##-short-name`, tests written first. See `CLAUDE.md`.
- Local development stack: `make dev-up` then `make dev-smoke` (see [`docs/dev-setup.md`](docs/dev-setup.md)).
- Never commit secrets. Local secrets live in `.dev-secrets/` (gitignored); deployed secrets are SOPS-encrypted under `infra/secrets/`.

## Status

Implementation is in progress; `PLAN.md` tracks task status.
