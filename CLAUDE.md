# CLAUDE.md — working conventions for this repository

Read this first. `PLAN.md` is the roadmap (tasks T00–T25); `docs/adr/` holds the 24 accepted decisions. Do not re-open accepted decisions; write a superseding ADR instead.

## Fixed facts

- GitHub repo: `akshatauppinventure/web-app-test` (private). Default branch `main`. Rulesets are unavailable on this private repo under the Free plan (owner decision P12 pending); protection is process-only: never push to `main` directly, always PR.
- POC hostname: `test-vinayak.duckdns.org` (DuckDNS, Let's Encrypt HTTP-01). No custom domain, Cloudflare or Apple login in the POC.
- Hosting target: UpCloud `us-nyc1`, two Ubuntu 26.04 VPS: A "edge" (Traefik, CrowdSec, frontend) and B "core" (Keycloak, backend, PostgreSQL, Portainer Server). WireGuard `10.10.0.1` (A) / `10.10.0.2` (B).
- Owner-only prerequisites (accounts, tokens, purchases) are listed in `PLAN.md` § "Owner prerequisites". Never fake them; stop and report when one is missing.

## How work is done

1. **One task = one branch = one PR.** Branch `task/T##-short-name`; PR title `T##: <title>`; body follows `.github/PULL_REQUEST_TEMPLATE.md` and names the ADRs implemented. Merge with squash.
2. **Test-driven.** Write the failing test first, then the minimum code to pass, then refactor. Every task's "Tests" list in `PLAN.md` is the minimum; each PR states how the tests were run.
3. **Definition of done** is the global list in `PLAN.md` plus the task's own "Done when". CI green from T11 onward; before that, the task's listed local checks must pass.
4. **No secrets in git.** Local dev secrets live in `.dev-secrets/` (gitignored); deployed secrets are SOPS+age encrypted in `infra/secrets/`. Never print secret values in logs, PRs or chat.
5. **Pinning (ADR-0020).** Renovate (`renovate.json`) keeps pins current; put a `# renovate: datasource=… depName=…` comment above any `ARG *_VERSION` so it is tracked. Validate config changes with `npx --yes --package renovate@<ver> renovate-config-validator renovate.json`. Container images: exact tag **and** `@sha256:` digest, never `latest`. GitHub Actions: full commit SHA with a version comment. Python/Node dependencies: locked (`uv.lock`, `pnpm-lock.yaml`).
6. **Docs move with code.** Update README, runbooks, `PLAN.md` status and this file in the same PR.
7. **Commit messages:** imperative subject ≤ 72 chars prefixed with the task id, e.g. `T01: add FastAPI scaffold with health endpoints`.

## Toolchain (local, macOS arm64)

| Area | Tools | Notes |
|---|---|---|
| Backend | `uv`, Python 3.14, `ruff`, `pyright`, `pytest` | `cd backend && uv sync --locked` |
| Frontend | `pnpm` 12 (exact version in `package.json`; `npm i -g pnpm@<ver>` if corepack fails), Node 24 | `cd frontend && pnpm install --frozen-lockfile` |
| Containers | Docker 29 (arm64 locally; CI builds `linux/amd64`), `hadolint` | Test images with `--read-only --cap-drop ALL --security-opt no-new-privileges` |
| Infra | `shellcheck`, `docker compose config`, `sops`, `age`, `tofu` (OpenTofu 1.12), `tflint` (release binary in `~/.local/bin`; no brew formula), `trivy` | `brew install sops age opentofu trivy` |

## CI (`.github/workflows/ci.yml`)

Jobs: `changes` (path filter) → `backend` (uv, ruff, pyright, pytest with `TEST_PG_REQUIRED=1` against `compose.test.yaml`), `frontend` (`pnpm check`), `infra policy` (hadolint, shellcheck, `scripts/ci/check-compose.sh`, `scripts/ci/check-published-ports.sh` vs `infra/policy/published-ports.txt`, `check-hardening.py`, Keycloak checksums, Renovate validator, host-config validation, OpenTofu fmt/validate/tflint/trivy, secrets round trip), `keycloak image + smoke`, `traefik image + routes`, `local stack e2e` (dev stack + `scripts/dev/smoke.sh` + image hardening), `shared` (zizmor with `zizmor.yml`, gitleaks with `.gitleaks.toml`, dependency review). On `push` to `main` everything runs; on PRs only the affected jobs. Every action is SHA-pinned with a version comment; `persist-credentials: false`; top-level `permissions: contents: read`.

Local equivalents before pushing: `make backend-check`, `make frontend-check`, `make hadolint`, `shellcheck $(git ls-files '*.sh')`, `scripts/ci/check-compose.sh`, `scripts/ci/check-published-ports.sh`, `uvx zizmor --config zizmor.yml .github/workflows/*.yml`, `gitleaks git --config .gitleaks.toml .`.

## Images (`.github/workflows/build-publish.yml`)

PRs build + Trivy-gate changed components without pushing; pushes to `main` gate, then push `ghcr.io/akshatauppinventure/<component>:sha-<sha>` with SBOM + provenance and cosign keyless signatures. `scripts/ci/changed-components.sh` maps paths to components (workflow/script/`.trivyignore` changes rebuild all). Exceptions go in `.trivyignore` with `exp:` dates. Runbook: `docs/runbooks/ci-images.md`.

## Deploys (`verify-deploy.yml`, `scripts/ci/bump-digest.py`)

After every publish, the deploy App opens one `deploy/<component>-<sha>` PR per component that only rewrites that component's `image:` lines. `verify-deploy` cosign-verifies every `ghcr.io` digest in `infra/stacks` + `infra/host/bootstrap` (placeholders `sha256:000…` are skipped), re-runs compose/ports/hardening checks, and squash-merges bot PRs when green. Never hand-edit digests without going through a PR. Runbook: `docs/runbooks/deploy-and-rollback.md`. Tests: `make bump-digest-test`.

## Commands

Targets are added to the `Makefile` as tasks land; `make help` lists them. Until then a stub target fails with the task id that will implement it.

- `make backend-check` — locked sync, ruff lint + format check, pyright (strict), pytest. Run before every backend commit.
- `make backend-run` — uvicorn on :8000 with `/docs` enabled (`ENVIRONMENT=local`).
- `make test-db-up` / `make test-db-down` — throwaway Postgres 18.6 from `compose.test.yaml` on `127.0.0.1:55432` (test-only passwords in `scripts/test/pg-secrets/`). DB tests skip when it is not running; run them before every backend PR.
- `make backend-migrate` — `alembic upgrade head`; needs `DATABASE_URL` for the `app_migrator` role.
- `make frontend-check` — frozen install, next-version guard, eslint, tsc, vitest, `next build`. Run before every frontend commit.
- `make tofu-check` — for every `infra/tofu/<provider>` module: `tofu fmt -check`, `tofu init -backend=false`, `tofu validate`, `tflint`, `trivy config`, then `scripts/test/tofu-contract.sh` (no credentials). `tofu plan` needs `UPCLOUD_TOKEN` (P6) or the OVH `openrc` (P15) and the rendered cloud-init files.
- `make secrets-check` — SOPS/age round trip with a throwaway key, `infra/secrets/SCHEMA.md` vs every referenced secret, generator coverage, dry-run push. `make secrets-gen` / `secrets-encrypt SRC=` / `secrets-push HOST=` are the owner's workflow (`docs/runbooks/secrets.md`).
- `make host-check` — validates `infra/host/*` (render both cloud-init templates with `scripts/test/host-vars.example`, `cloud-init schema`, `nft -c`, `wg-quick strip`, DOCKER-USER rules) in `ubuntu:26.04` containers.
- `make stacks-check` — `check-compose.sh`, `check-published-ports.sh` (allowlist `infra/policy/published-ports.txt`), `check-hardening.py` (baseline + `infra/policy/hardening-exceptions.yaml`) over every compose file. `make stacks-dryrun` starts the real `infra/stacks/*/compose.yaml` with the overlays in `scripts/test/stacks/` (local images, `.dev-secrets`, loopback binds).
- `make crowdsec-test` — after `make traefik-test`: bouncer registration, collections, AppSec detect-only, manual ban → 403, fail-open.
- `make traefik-test` — Traefik image + whoami upstreams on `127.0.0.1:18443` and `scripts/test/traefik-routes.sh` (routing, `/auth/admin` 404, headers, redirect, body limits, 429s, sniStrict). Run after any change under `infra/traefik/`.
- `make keycloak-image` / `make keycloak-smoke` — build the Keycloak image and run the smoke test against Postgres + Keycloak on `127.0.0.1:18080` (compose profile `keycloak`). Run the smoke test for every Keycloak or extension bump.
- `make dev-up` / `make dev-smoke` / `make dev-logs` / `make dev-down` / `make dev-reset` — local full stack from `compose.dev.yaml` (`docs/dev-setup.md`). `dev-smoke` runs the health checks and a real sign-in/sign-out. Run it after any change to auth, realm, compose or images.
- `make frontend-image` / `make frontend-image-test` — build `web-app-test/frontend:dev` and run `scripts/test/frontend-image.sh` (uid 1000, read-only FS with tmpfs `/app/.next/cache`, no npm, `/api/healthz`, no `X-Powered-By`, labels, HEALTHCHECK).
- `make backend-image` / `make backend-image-test` — build `web-app-test/backend:dev` and run `scripts/test/backend-image.sh` (uid 10001, read-only FS, no uv/pip, `/healthz`, OCI labels, HEALTHCHECK). `make hadolint` lints all Dockerfiles with `.hadolint.yaml` (warnings fail).

## Compose conventions

- Every service: explicit numeric `user:`, `read_only`, `cap_drop: [ALL]` (no `cap_add`), `no-new-privileges`, `mem_limit`, `pids_limit`, healthcheck, `restart`, `logging`, image pinned by digest; writable paths are `tmpfs`. `scripts/ci/check-hardening.py` enforces this on `infra/stacks/*`; the only exception is `edge/crowdsec` running as root (listed with a reason in `infra/policy/hardening-exceptions.yaml`). Postgres runs as uid 999 from the start (baked image), so it needs no capabilities.
- Configuration files are baked into images (`infra/postgres`, `infra/crowdsec`, `infra/keycloak`, `infra/traefik`), never bind-mounted from the repo: Portainer CE Git stacks cannot mount relative paths. Absolute host paths (`/var/log/auth.log`) and named volumes are fine.
- Stack env vars with `${VAR:?}` are required in Portainer; the policy checkers export placeholder values so `docker compose config` works in CI.
- Ports bind to `127.0.0.1` locally; in the stacks (T16) only Traefik binds `0.0.0.0`.
- Secrets are Compose `secrets:` (files), never environment variables. Apps read `*_FILE` or `/run/secrets/<name>`; the migrate job uses `DATABASE_URL_FILE`.
- Network `db` is `internal: true` with subnet `172.28.1.0/24` (fixed by `pg_hba.conf`); `core` is `172.28.2.0/24`. The test compose uses the same `db` subnet, so the dev stack and `make test-db-up` cannot run at the same time (`make dev-down` first; the Makefile guards this).

## Secrets conventions (`infra/secrets/`, `scripts/secrets/`)

- `SCHEMA.md` is the contract: every `file: /etc/app/secrets/<name>` in stacks/bootstrap and every `$SECRETS/<name>` in host scripts must have a row, and `gen-secrets.sh` must emit exactly the schema's names per host (`scripts/secrets/check-schema.sh`).
- Values shared by both hosts are generated once and copied with `--shared-from`; owner-supplied values are `CHANGE_ME` markers until filled.
- `secrets-push.sh` maps each name to a path, owner UID and mode; a secret without a rule fails the push. Values travel only over stdin to `ssh … tee`; never as arguments.
- The repo's `.sops.yaml` holds the owner's age recipient (P5). Tests never touch it: they use a throwaway key with `sops --config <temp>`.

## OpenTofu conventions (`infra/tofu/<provider>/`)

- One module per provider with an identical contract (ADR-0025): `upcloud` (reference) and `ovh` (OVHcloud US Public Cloud, OpenStack). `scripts/test/tofu-contract.sh` fails CI if a module lacks a shared variable/output, the standard files, an exact provider version, `ignore_changes = [user_data]`, or sets credentials in `providers.tf`. Provider-specific extras are fine; add shared ones to the test and to both modules.
- Providers: `UpCloudLtd/upcloud` (credentials only via `UPCLOUD_TOKEN`) and `terraform-provider-openstack/openstack` (credentials only via the `openrc` environment, `OS_*`). Exact versions in `versions.tf`, hash-pinned by the committed `.terraform.lock.hcl` (`tofu providers lock -platform=darwin_arm64 -platform=darwin_amd64 -platform=linux_amd64` after a bump).
- OVH specifics: vRack private network via `value_specs` (`provider:network_type = vrack` + VLAN id), subnet with `no_gateway`, security groups with `delete_default_rules = true` and IPv4-only rules; image chosen by `name_regex`; `PUBLIC_IF=ens3` in the host vars. Untested against a real project until P15.
- Private-network addresses are `10.0.0.11` (edge) and `10.0.0.2` (core) in both modules: UpCloud refuses `x.1` (SDN gateway). Cloud-init endpoints default to the same.
- Cloud-init is passed as `user_data` from files rendered by `infra/host/scripts/render-cloud-init.sh` into the gitignored `.tofu-rendered/`; `ignore_changes = [user_data]` (first boot only).
- UpCloud firewall rules are stateless: every outbound protocol the hosts use needs an inbound return rule (`firewall.tf` `return_rules`). Keep each server under 20 rules (`firewall_rule_counts` output). OpenStack security groups are stateful (no return rules).
- State and tfvars stay local; commit them only as `*.sops` (rules in `.sops.yaml`).

## Host conventions (`infra/host/`)

- The committed scripts/units/configs are the source of truth; `scripts/render-cloud-init.sh` embeds them into the cloud-init templates at render time. Never edit rendered output by hand.
- Placeholders are `__UPPER_SNAKE__`; the render script fails if any remain or if any WireGuard key is not a real 44-char key (a placeholder would brick the host: sshd listens on `wg0` only). `PUBLIC_IF=auto` is resolved from the default route at first boot (`scripts/resolve-public-if.sh`).
- WireGuard port: `WG_PORT` (render) / `wireguard_port` (both modules), default 51820. The POC runs the default 51820 with managed rulesets (the trial-mode attempt on 33434 failed: the fixed trial firewall is stateless and blocks TCP return traffic, PLAN deviation 5 resolved). The knobs stay for constrained accounts; the laptop config uses the same `ListenPort` as the servers.
- WireGuard keys (T20): the laptop generates a *bootstrap* key pair per host, rendered into user_data so all peers are valid at first boot; `scripts/host/finalize-wireguard.sh` then rotates both keys on the hosts (`wg-rotate-key.sh`, generated on the host, never leaves it), rewires peers, writes `psk-map` and prints the `peers.yaml` snippet. Only public keys go into `wireguard/peers.yaml`. Laptop config: `scripts/host/render-laptop-wg.sh`. Tests: `scripts/test/host-bootstrap.sh` (stubbed ssh).
- Host scripts read secrets from `/etc/app/secrets/<name>` and role settings from `/etc/app/host.env` (`HOST_ROLE`, `PEER_IP`, `PUBLIC_HOST`, `PUBLIC_IF`, `NOTIFY_WEBHOOK_URL`).
- Validation runs in `ubuntu:26.04` containers (`nft -c` needs `--privileged`; macOS `sed` has no `\|`, so use Python for multi-key substitutions in tests).

## Container image conventions

- Multi-stage; the runtime stage has no package manager for the language (no uv, no pip), runs as a fixed non-root UID, and works with `--read-only --cap-drop ALL --security-opt no-new-privileges`. Writable paths are `tmpfs`.
- `HEALTHCHECK` uses tools already in the image (python for the backend); no curl/wget added.
- OCI labels `source`, `revision`, `created` come from build args `GIT_SHA`, `BUILD_DATE`.
- Base images: exact tag **and** digest (multi-arch index digest, so the same line builds on arm64 locally and amd64 in CI).

## Frontend conventions (`frontend/`)

- pnpm 12 with `pnpm-workspace.yaml` supply-chain settings: `minimumReleaseAge: 4320` (3 days) blocks brand-new versions, so pick the newest version older than 3 days when pinning (`npm view <pkg> time --json`). Lifecycle scripts run only for `onlyBuiltDependencies`; anything else that needs a build goes in `ignoredBuiltDependencies` with a comment, never disable `strictDepBuilds`.
- ESLint stays on the newest 9.x until eslint-config-next's plugins support ESLint 10 (eslint-plugin-react 7.37 crashes on 10).
- Version floor for `next` is `16.3.3` (`scripts/check-next-version.mts`, tested); CI fails below it (T11).
- App Router only, TypeScript strict with `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`. Server-only code imports `server-only` (T07). No client-side token handling, ever.
- Tests: vitest (node environment) in `frontend/tests/*.test.ts`; test route handlers by importing and calling them. Pure logic lives in `frontend/lib/*` with injected `fetchImpl`/`now` so it is unit-testable; `auth.ts` is never imported by tests.
- Auth.js v5 gotchas learned in T07: with a lazy config (`NextAuth(() => cfg)`), `auth(handler)` returns a Promise, so `proxy.ts` must call `auth(req, event)` inline and rely on `callbacks.authorized`; explicit `authorization`/`token`/`userinfo` URLs skip OIDC discovery (browser → public issuer, server → `KEYCLOAK_INTERNAL_ISSUER`); `/api/auth/session` is blocked in the route handler so tokens never reach the browser; `next start` warns with `output: standalone` (the container runs `node server.js`).
- pnpm 12 build-script policy lives in `allowBuilds` (true/false per package) in `pnpm-workspace.yaml`; pnpm appends placeholder entries when a new package with scripts appears, so commit a deliberate `true`/`false`.
- `make frontend-e2e` (`scripts/test/frontend-e2e.sh`) drives sign-in → Keycloak form → callback → `/hello` → logout with curl; run it whenever auth code changes.

## Keycloak conventions (`infra/keycloak/`)

- Realm JSON is the source of truth and contains **no secrets**: `${ENV_VAR}` placeholders are substituted once at first import; `${vault.<key>}` reads `/run/secrets/app_<key>` on use (Keycloak file vault, built in with `--vault=file`).
- Build-time options (`db`, `http-relative-path`, `health`, `metrics`, `vault`) must be passed to `kc.sh build`; runtime env vars cannot change them on an `--optimized` image.
- Realm-import gotchas learned in T05: `defaultRole.composites` is ignored (define `default-roles-app` inside `roles.realm`); composites can only reference roles defined in the same file (built-ins like `uma_authorization` don't exist yet); users created via `partialImport` do not get default roles, users created via `POST /admin/realms/app/users` do.
- Third-party jars: record version, URL, sha256 and upstream sha512 in `checksums.txt`; the Dockerfile uses `ADD --checksum=sha256:…`; `scripts/verify-checksums.sh` cross-checks both.

## Traefik conventions (`infra/traefik/`)

- Static config is a file; env-dependent values go through `__PLACEHOLDER__`s rendered by the entrypoint. Dynamic files may use `{{ env "NAME" }}` Go templates.
- Traefik listens on 8080/8443 as uid 65532 and the stack publishes 80→8080, 443→8443, so no `NET_BIND_SERVICE` is needed (deviation from ADR-0012 §8 in the safe direction; the HTTP→HTTPS redirect targets `:443` explicitly).
- Only `/auth/realms/*` and `/auth/resources/*` reach Keycloak; every other `/auth*` path and every unknown Host returns the frontend's 404 page via `noop@internal` (418) + `errors` middleware `statusRewrites`.
- `sniStrict: true` means the test stack needs `scripts/test/traefik-test-certs.sh` (self-signed, gitignored under `.traefik-test/`).
- CrowdSec plugin runs fail-open (`updateMaxFailure: -1`, AppSec failure/unreachable not blocking) for the POC.
- `FORWARDED_TRUSTED_IPS` (Traefik entry points) and `CROWDSEC_FORWARDED_TRUSTED_IPS` (plugin) are empty in the POC; the test stack sets them to the Docker gateway so curl can simulate client IPs with `X-Forwarded-For`.

## CrowdSec conventions (`infra/crowdsec/`)

- One bouncer key, two secret names: `bouncer_key_traefik` (CrowdSec auto-registers) and `crowdsec_bouncer_key` (Traefik plugin). Generated by `infra/crowdsec/scripts/bootstrap-bouncer.sh`.
- Mount config as individual read-only files into `/etc/crowdsec/...`; the image rsyncs its staging tree at start and needs directories writable.
- AppSec phase 1 = `poc/appsec-detect` with `default_remediation: allow`; check hits with `cscli metrics show appsec-rule`. Phase 2 (block) is T25.
- cscli JSON keys: `appsec-configs`, `appsec-rules`, `parsers` (status `enabled,local` for local items), `appsec-engine`, `appsec-rule`.

## Backend conventions (`backend/`)

- App factory `create_app(settings)` in `app/main.py`; tests build apps with explicit `Settings`, never from the environment.
- `Settings` (`app/config.py`) reads env vars and secret files from `SECRETS_DIR` (default `/run/secrets`) via `load_settings()`. Secrets are `SecretStr`; nothing secret has a default.
- Logging is structlog JSON; `redact_sensitive` blanks keys like `authorization`, `cookie`, `*token*`, `password`. Never log request bodies or tokens.
- `/docs`, `/redoc`, `/openapi.json` exist only when `ENVIRONMENT=local`; `/healthz` and `/readyz` are unauthenticated and excluded from the schema.
- pytest runs with `filterwarnings = error` and `asyncio_mode = auto`; tests are a package (`tests/__init__.py`). DB fixtures live in `tests/db_fixtures.py` (registered as a pytest plugin); mark DB tests with `requires_postgres`.
- Database (`app/db.py`): `Database.user_session(sub)` opens one transaction and sets `app.user_id` transaction-locally; all user-data queries go through it. Never accept an owner id from the client.
- Migrations are hand-written Alembic files under `backend/alembic/versions/` (no autogenerate). Every user-data table gets `ENABLE` + `FORCE ROW LEVEL SECURITY`, a policy on `current_setting('app.user_id', true)` and explicit grants to `app_rw`. Migrations connect as `app_migrator`; `env.py` does `SET ROLE app_owner`.
- Postgres roles/config live in `infra/postgres/` (see its README). The `db` network subnet is fixed at `172.28.1.0/24`.
- Auth (`app/auth/`): `current_user` validates the bearer JWT (alg allowlist `RS256`/`ES256`, `iss`, `aud=api`, `azp=web-bff`, `typ=Bearer`, `exp`/`nbf`/`iat` with 30 s leeway, non-empty `sub`); `require_roles("user")` guards every `/v1` route. JWKS is cached in `JWKSClient`; unknown `kid` refreshes at most once per 60 s. OIDC settings (`OIDC_ISSUER`, `OIDC_JWKS_URL`, …) are env vars, not secrets.
- Test tokens come from `tests/keys.py` (RSA pair generated at import, fake JWKS served through `respx`). Add a negative test for every new claim check.

## Task status

| Task | Status | PR |
|---|---|---|
| T00 Repo skeleton, ADRs accepted | done | initial commit |
| T01 Backend scaffold | done | #1 |
| T02 DB schema, roles, migrations, RLS | done | #2 |
| T03 JWT validation and hello endpoints | done | #3 |
| T04 Backend container image | done | #4 |
| T05 Keycloak image and `app` realm | done | #7 |
| T06 Frontend scaffold | done | #5, #6 |
| T07 Frontend auth (Auth.js BFF) and /hello | done | #8 |
| T08 Frontend container image | done | #9 |
| T09 Local full stack + dev docs | done (Google login pending owner P2) | #10 |
| T10 Renovate + repo policy | done (app install pending owner P13) | #11 |
| T11 CI workflow (lint, test, policy) | done; negative PRs #20–#22 failed as intended | #19, #23–#25 |
| T12 build-publish (six images: scan, push, attest, sign) | done; negative PR #29 failed at the Trivy gate; packages private (P3 done), CI-enforced | #28, #30, #31, #33 |
| T14 Traefik image and configuration | done | #12 |
| T15 CrowdSec engine, bouncer, AppSec (detect-only) | done | #13 |
| T16 GitOps stacks (edge, core) + policy checks | done | #14 |
| T17 Host configuration (cloud-init, nftables, WireGuard, Docker, timers) | done | #15 |
| T18 OpenTofu module for UpCloud | done (plan/apply need owner P6) | #17 |
| T19 Secrets tooling (SOPS + age) | done; P5 done, `infra/secrets/*.sops.yaml` committed (P9/P10/CrowdSec values still `CHANGE_ME`) | #16, #47 |
| T13 deploy-PR bot + digest verification | done; six deploy PRs #39–#44 verified and auto-merged, negative PR #38 failed at cosign verify | #36, #37, #45 |
| T26 OpenTofu module for OVHcloud (second provider, contract test) | done (live plan/apply when the OVH POC starts, P15) | #48 |
| T20–T25 | not started | — |
