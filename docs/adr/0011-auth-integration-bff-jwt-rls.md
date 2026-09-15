# ADR-0011: Auth integration: BFF sessions, JWT validation, RLS

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0007, ADR-0008, ADR-0009, ADR-0010

## Context

Keycloak is the identity provider (ADR-0010). We need to decide:
- how the browser, Next.js and FastAPI take part in login,
- where tokens live,
- how authorization is enforced down to the database.

Constraints:
- **No tokens in the browser.** XSS must not be able to steal access or refresh tokens.
- **VPS-A holds no database** (ADR-0003), so server-side session storage on A would need a new stateful component.
- **FastAPI is not publicly reachable;** only the Next.js server calls it.
- Defense in depth: a bug in one authorization layer should not expose other users' data.

Library status (2026): Auth.js (`next-auth` v5) supports the App Router and has a built-in Keycloak provider. It's maintained by the Better Auth team, and v5 is still published under the `beta` tag.

## Decision

1. **Backend-for-Frontend (BFF) pattern:**
   - Next.js is a **confidential OIDC client** (`web-bff`) using the **authorization code flow with PKCE (S256)**, plus `state` and `nonce`.
   - **Library:** `next-auth` v5 (Auth.js) with the Keycloak provider, **pinned to an exact version**. Upgrades go through Renovate PRs with login tests.
   - **Sessions:**
     - Auth.js JWT session strategy (encrypted JWE cookie; chunked if large).
     - Cookie attributes: `__Secure-` prefix, `HttpOnly`, `Secure`, `SameSite=Lax`, `Path=/`.
     - Stored in the cookie: access token, refresh token, ID token and expiry.
     - Encryption key `AUTH_SECRET` comes from a secret file (ADR-0016).
   - **Token refresh** happens server-side in the Auth.js `jwt` callback when the access token is within 60 seconds of expiry. If refresh fails, the session ends.
   - **Login buttons** start sign-in with the `kc_idp_hint` authorization parameter (`google`, later `apple`) to skip the Keycloak chooser page.
   - **Logout:** RP-initiated logout to Keycloak's `end_session_endpoint` with `id_token_hint`, then clear the cookie.
2. **Calls to the API:**
   - Only Next.js **server** code (route handlers / server components / server actions) calls FastAPI at `http://10.10.0.2:8000` over WireGuard, with `Authorization: Bearer <access_token>`.
   - Client components that need data call Next.js route handlers (same origin). Those route handlers check the `Origin` header on state-changing requests.
3. **Token validation in FastAPI** (every request, a FastAPI dependency):
   - Verify the signature with keys from Keycloak's JWKS (`http://keycloak:8080/auth/realms/app/protocol/openid-connect/certs` over B's internal network).
     - Keys cached in memory.
     - When a token has an unknown `kid`, refresh the key set (at most once per 60 s).
   - **Algorithm allowlist: `RS256`** (and `ES256` if keys rotate to EC). Never `none` or `HS*`.
   - Check `iss == https://<poc-host>/auth/realms/app` (public issuer), `aud` contains `api` (set by an audience mapper on `web-bff`), `azp == web-bff`, `exp`/`nbf`/`iat` with 30 s leeway, and `typ == Bearer`.
   - Reject tokens missing `sub`.
4. **Authorization (three layers):**
   1. **Coarse:** Keycloak realm roles (`realm_access.roles`, e.g. `user`, `admin`), checked by a `require_roles(...)` dependency.
   2. **Object-level:** every query for user-owned data is scoped to the caller's `sub` in the service layer. Endpoints never accept a user ID from the client for ownership.
   3. **Database Row-Level Security** as the safety net:
      - Each request's DB transaction runs `SELECT set_config('app.user_id', :sub, true)` (transaction-local).
      - Policies are like `USING (owner_sub = current_setting('app.user_id', true))` with matching `WITH CHECK`.
      - RLS is **forced**, and the runtime role `app_rw` is neither the owner nor `BYPASSRLS` (ADR-0009).
      - A missing context yields no rows (fail closed).
5. **Next.js middleware/proxy** may redirect unauthenticated users for convenience, but **is never relied on for authorization**.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Browser-held tokens (SPA + PKCE, tokens in memory/localStorage) | Tokens can be stolen through XSS; larger attack surface |
| Server-side session store (Redis/Postgres) for Next.js | Adds a stateful component on VPS-A or a cross-host dependency; encrypted cookie is sufficient for the POC |
| Public FastAPI with CORS | Extra public attack surface; conflicts with the edge/core design |
| `openid-client` (panva) directly | OpenID-certified and flexible, but more custom code; kept as a fallback if Auth.js v5's beta status causes issues |
| Better Auth with generic OAuth | Weaker documentation for Keycloak + refresh + SSR at research time |
| Token introspection on every request | Adds latency and a hard runtime dependency on Keycloak; local JWT validation with 5-minute tokens is standard |
| Authorization only in the app layer (no RLS) | A single missed `WHERE` clause leaks data; RLS provides fail-closed defense in depth |

## Consequences

**Positive**
- No tokens reachable by browser JavaScript.
- Short-lived tokens limit what a compromised edge can harvest.
- Database-enforced tenant isolation.

**Negative / risks**
- An encrypted cookie holding tokens can grow large (chunked cookies). Revocation takes effect at the next refresh (≤5 minutes).
- `next-auth` v5 carries a beta tag, so exact pins and tests are required.
- RLS adds per-request `set_config` and needs careful migration and testing (an RLS test suite in CI).

**Follow-ups**
- Tests: token validation negative cases (wrong `iss`/`aud`/alg, expired, tampered) and cross-user access tests at the API and SQL level.
- Revisit DPoP / sender-constrained tokens for production.

## References

- https://authjs.dev/getting-started/providers/keycloak
- https://authjs.dev/getting-started/migrating-to-v5
- https://skycloak.io/blog/keycloak-backend-for-frontend-bff-pattern/
- https://datatracker.ietf.org/doc/html/draft-ietf-oauth-browser-based-apps
- https://www.postgresql.org/docs/18/ddl-rowsecurity.html
- https://pyjwt.readthedocs.io/en/stable/usage.html#retrieve-rsa-signing-keys-from-a-jwks-endpoint
