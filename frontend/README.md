# frontend

Next.js 16 app (ADR-0007) acting as the browser-facing BFF. Node 24, pnpm (exact version in `package.json`).

```bash
pnpm install --frozen-lockfile
pnpm check            # next-version guard, eslint, tsc, vitest, next build
pnpm dev              # http://localhost:3000
```

- `output: "standalone"`; the container (T08) copies `.next/standalone` + `.next/static` + `public`.
- `scripts/check-next-version.mts` fails when `next` is older than the floor `16.3.3`.
- Supply-chain settings live in `pnpm-workspace.yaml`: lifecycle scripts only for allowlisted packages, `minimumReleaseAge` of 3 days (new versions cannot be installed on release day).
- Routes: `/` (landing + sign-in buttons), `/hello` (server component calling `GET /v1/hello`), `/api/healthz`, `/api/auth/*` (Auth.js; `/api/auth/session` is disabled), `/api/logout` (POST, same-origin, RP-initiated logout).

## Authentication (Auth.js v5 BFF, ADR-0011)

- `auth.ts` builds the config lazily (secrets read at request time). Keycloak provider with explicit `authorization` (public issuer, for the browser) and `token`/`userinfo` (`KEYCLOAK_INTERNAL_ISSUER`, for the server) URLs, so no discovery call and no hairpin through the public hostname.
- Session = encrypted JWT cookie (`__Secure-authjs.session-token` when `AUTH_URL` is https; HttpOnly, SameSite=Lax). Tokens live only inside it; `/api/auth/session` returns 404 so nothing is readable from client JS.
- `lib/token-refresh.ts`: refresh when ≤ 60 s remain; a failed refresh invalidates the session. Results are memoized per refresh token because Keycloak revokes a refresh token on first use and the proxy plus a server component may both run the callback for one request.
- `lib/api-client.ts` (`server-only`): bearer calls to `API_BASE_URL`, no cookies, 5 s timeout, errors carry only the status.
- `proxy.ts` only redirects unauthenticated `/hello` visitors; authorization is enforced in the page and again by FastAPI.
- Environment: see `.env.example`. Copy it to `.env.local` for `pnpm dev`.

End-to-end check without a browser (needs Keycloak, backend and frontend running):

```bash
make test-db-up && make keycloak-smoke        # Keycloak on :18080 with the smoke user
make backend-migrate DATABASE_URL=postgresql+psycopg://app_migrator:test-only-app-migrator@127.0.0.1:55432/app
# terminal 1: backend  (OIDC_ISSUER=http://localhost:18080/auth/realms/app OIDC_JWKS_URL=http://localhost:18080/auth/realms/app/protocol/openid-connect/certs DATABASE_URL=... make backend-run)
# terminal 2: frontend (cp .env.example .env.local, set AUTH_KEYCLOAK_ISSUER=http://localhost:18080/auth/realms/app, pnpm build && pnpm start)
make frontend-e2e
```

## Container image

```bash
make frontend-image        # docker build (pnpm frozen install, next build, standalone runtime)
make frontend-image-test   # hardening checks (scripts/test/frontend-image.sh)
```

Runtime: uid 1000 (`node`), only `server.js` + `.next/static` + `public`, no npm/yarn/corepack; `CMD node server.js` on :3000. Mount a `tmpfs` at `/app/.next/cache` when running read-only. Configuration comes from `AUTH_*`, `KEYCLOAK_INTERNAL_ISSUER`, `API_BASE_URL` and `*_FILE` secrets (see `.env.example`).
