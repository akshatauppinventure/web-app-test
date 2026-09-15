# ADR-0010: Identity provider: Keycloak

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0003, ADR-0009, ADR-0011, ADR-0012, ADR-0022

## Context

We need self-hosted, FOSS authentication and authorization, with **Google and Apple sign-up**, that is reliable and widely adopted worldwide. The owner reviewed the research and **chose Keycloak** on 2026-09-14.

Comparison (research 2026-09-13/14):

| | **Keycloak** | Authentik | Zitadel |
|---|---|---|---|
| License | Apache-2.0, fully open; CNCF incubating project | Open core: MIT + enterprise-licensed directory | AGPL-3.0 (since 2025) |
| Adoption | ~36k GitHub stars; large enterprise and government use | ~22k stars; self-hosting / small-business focus | Smaller |
| Google login | Built in | Built in | Built in |
| Apple login | Community extension (`klausbetz/apple-identity-provider-keycloak`, works with Keycloak ≥ 26.5) | Built in (free) | Built in |
| Resources | Heaviest: JVM, ~1.25 GB base recommendation | Lighter | ~150 MB (Go) + separate login-UI container |
| 2026 security record | 10+ advisories in 2025–26, highest CVSS 8.2 | CVE-2026-49448 authentication bypass (CVSS 9.8), CVE-2026-42849 XSS (CVSS 9.3), CVE-2026-49443 (CVSS 8.8) | Regular security releases |
| Paid tiers | None (Red Hat commercial support optional) | Enterprise $5/internal user/month, $0.02/external user/month (not needed for our features) | Cloud offering |

- **Current version:** Keycloak **26.7.2** (2026-08-19).
- **Keycloak has no LTS:** only the latest version gets fixes.

## Decision

1. **Identity provider: Keycloak 26.7.x**, as a **custom image** built in CI from `quay.io/keycloak/keycloak:26.7.2` (pinned by digest):
   - Adds the **Apple identity provider extension** (klausbetz, pinned version, checksum verified) to `/opt/keycloak/providers/`.
   - Runs `kc.sh build` with `--db=postgres --http-relative-path=/auth --health-enabled=true --metrics-enabled=true` to produce an **optimized image**, started with `start --optimized`.
2. **Runtime configuration:**
   - Runs on **VPS-B**. Uses the `keycloak` database on the shared PostgreSQL (ADR-0009).
   - `KC_HOSTNAME=https://<poc-host>/auth` (ADR-0022); `KC_PROXY_HEADERS=xforwarded`; `KC_HTTP_ENABLED=true`. TLS ends at Traefik, and the A→B hop is encrypted by WireGuard.
   - Keycloak's HTTP port is published only on `10.10.0.2:8080`. The management port 9000 (health/metrics) isn't published.
   - Admin console: **not routed publicly** (Traefik exposes only `/auth/realms/*` and `/auth/resources/*`, ADR-0012). Admins reach it at `http://10.10.0.2:8080/auth/admin` over WireGuard (a private address, so the master realm's "Require SSL: external requests" still holds).
3. **Realms:**
   - `master`: administration only, with MFA (TOTP or passkey) for all admin users. The temporary bootstrap admin is replaced by a named admin, then deleted.
   - `app`: application users.
     - User registration on.
     - Email verification on once SMTP is configured (post-POC).
     - Brute-force detection on.
     - Password policy: minimum length 12, not the username, blocklist.
     - WebAuthn passkeys available as an optional second factor.
   - Realm configuration is committed as JSON (without secrets) and imported on first start. Later changes are made in the admin console and re-exported to git.
4. **Identity providers in realm `app`:**
   - **Google:** enabled (OIDC). Client ID and secret come from secrets (ADR-0016).
   - **Apple:** **installed but disabled** until the owner has an Apple Developer Program membership and a registered domain (ADR-0022/0023).
   - First-login flow: create the user or link to an existing account only after email verification (prevents account takeover through unverified emails).
5. **Clients and tokens:** see ADR-0011.
   - `web-bff`: confidential client, standard flow + PKCE S256.
   - `api`: bearer-only audience.
   - Access token lifetime **5 minutes**.
   - **Refresh token rotation** ("Revoke Refresh Token" on, max reuse 0).
   - SSO session idle 30 minutes, max 10 hours.
6. **Upgrade policy:**
   - Track the latest Keycloak minor within 2 weeks of release; security patches within 48 hours (ADR-0020).
   - **Every Keycloak upgrade PR runs a smoke test** that starts the image, checks the Apple provider loads, and runs an OIDC login with a test user.
   - **Fallback if the Apple extension becomes unmaintained:** configure Apple as a generic OIDC provider, with the Apple client-secret JWT (maximum 6-month validity) regenerated on a schedule, or migrate to an alternative identity provider via a superseding ADR.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Authentik | Easier to run, lighter, native Apple; but open core, smaller adoption and more severe 2026 CVEs. Not chosen by owner. |
| Zitadel | Native Apple, very light; AGPL, smaller community, v4 architecture change (separate login UI) |
| Ory Kratos/Hydra | API-first, requires building our own login UI; more services |
| Better Auth / Auth.js only (no identity-provider server) | Ties identity to the Next.js app; no central IdP for future mobile/API clients |
| Managed IdP (Auth0, Clerk, Cognito) | Not FOSS/self-hosted; recurring cost; data residency outside our control |

## Consequences

**Positive**
- A standards-based (OIDC/OAuth 2.1-style) central IdP, reusable for future mobile apps and APIs. A fully open license with no feature paywall; the largest community.

**Negative / risks**
- Apple support depends on a single-maintainer community extension (~295 stars). Mitigated by pinning, smoke tests and the documented fallback.
- JVM memory footprint (≥1.25 GB): sized into VPS-B (8 GB).
- Keycloak's large feature surface means many CVEs. Mitigated by admin console isolation, limited public paths and a fast patch SLA.
- The default login theme is basic. A custom theme (e.g. Keycloakify) is a post-POC task.

**Follow-ups**
- Enable Apple login after the Apple Developer Program + domain.
- Configure SMTP for email verification and password reset.
- Custom login theme.

## References

- https://www.keycloak.org/2026/08/keycloak-2672-released
- https://www.keycloak.org/server/reverseproxy
- https://www.keycloak.org/server/hostname
- https://github.com/klausbetz/apple-identity-provider-keycloak
- https://github.com/keycloak/keycloak/issues/12468
- https://skycloak.io/blog/open-source-authentication-comparison-2026/
- https://skycloak.io/blog/keycloak-vs-authentik-comparison/
- https://goauthentik.io/pricing/
- https://docs.goauthentik.io/enterprise/enterprise-features/
- https://app.opencve.io/cve/CVE-2026-49448
