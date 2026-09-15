# ADR-0022: POC hostname and TLS: DuckDNS + Let's Encrypt

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0010, ADR-0011, ADR-0012, ADR-0014, ADR-0023

## Context

The owner has **no domain yet** (to be purchased after the POC) but wants the deployed POC to have HTTPS and a working **Google login**. Research (2026):

- **Google OAuth** rejects raw IP addresses as redirect URIs (only localhost is exempt) and requires the host to be under a public suffix.
- **Let's Encrypt** has issued **IP-address certificates** (6-day, `shortlived` profile) since **2026-01-15**. That gives HTTPS on a bare IP, but Google login still wouldn't work.
- **nip.io / sslip.io** are accepted by Google, but they are **not on the Public Suffix List**, so all their users share one Let's Encrypt rate-limit bucket, which is regularly exhausted.
- **DuckDNS** (`duckdns.org`) is free, **on the Public Suffix List** (each subdomain gets its own Let's Encrypt rate limit), and supports A/AAAA/TXT updates through a token-authenticated HTTPS API. Sign-in is through third-party accounts (e.g. Google, GitHub).
- **Apple login** requires a registered domain plus an Apple Developer Program membership, so it's out of scope until a domain exists.

The owner chose a **free DuckDNS name** on 2026-09-14.

## Decision

1. **Hostname:** one DuckDNS subdomain, `<name>.duckdns.org`, referred to as `<poc-host>` in other ADRs, for the whole POC:
   - `https://<poc-host>/` → Next.js
   - `https://<poc-host>/auth/realms/*`, `/auth/resources/*` → Keycloak (`KC_HTTP_RELATIVE_PATH=/auth`)
2. **DNS records:**
   - **A record = VPS-A's public IPv4 address**, set **once manually** in the DuckDNS web UI. The UpCloud IP is static, so no dynamic updater is needed.
   - **No AAAA record** for the POC (ADR-0014).
   - **The DuckDNS token is never placed on any server or in CI.** It's stored only in the admin password manager, because it controls every subdomain on the account.
3. **TLS:**
   - Traefik ACME with **HTTP-01** challenge (ADR-0012). This needs only port 80, and no DNS API token on the server.
   - Let's Encrypt production endpoint, after one successful test against staging.
4. **Google OAuth client (Google Cloud Console):**
   - OAuth consent screen: **External**, publishing status **Testing**, with the owner/testers added as **test users**. No Google app verification is needed in Testing mode.
   - OAuth client type **Web application**.
   - **Authorized redirect URI:** `https://<poc-host>/auth/realms/app/broker/google/endpoint`.
   - Add `<poc-host>` as an authorized domain if prompted.
   - For local development, a separate OAuth client with redirect URI `http://localhost:8080/auth/realms/app/broker/google/endpoint`, pointing at the local Keycloak.
   - Client ID and secret stored as `core` secrets (ADR-0016).
5. **Security guardrails for using a third-party free DNS service:**
   - The account used to sign in to DuckDNS **must have MFA enabled**. A takeover would let an attacker repoint the hostname and obtain certificates for it.
   - **No real users or real personal data** on the DuckDNS hostname.
   - The name is replaced by an owned domain before any production use (a superseding ADR, together with ADR-0023).

### Setup steps (reference)

1. Go to `https://www.duckdns.org` and sign in with one of the offered providers. **Use an account with MFA enabled** (e.g. GitHub or Google).
2. In the "domains" section, enter a subdomain name (e.g. `test-vinayak`) and click **add domain**. Pick a non-obvious name that doesn't identify the owner.
3. After VPS-A is provisioned, put **VPS-A's public IPv4 address** in the domain's *current ip* field and click **update ip**. Leave IPv6 empty.
4. Check that it resolves: `dig +short test-vinayak.duckdns.org` should return VPS-A's IP.
5. Copy the account **token** into the password manager only. If it's ever exposed, regenerate it on the DuckDNS account page.
6. **Optional (API instead of the web UI):** `curl "https://www.duckdns.org/update?domains=test-vinayak&token=<TOKEN>&ip=<VPS_A_IPV4>&verbose=true"` returns `OK` and `UPDATED`/`NOCHANGE`. Run it from the admin laptop, never from a server.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Let's Encrypt IP certificate on a bare IP | HTTPS works, but Google login is impossible |
| nip.io / sslip.io | Shared, exhausted Let's Encrypt rate limits → certificates may not issue |
| Buy a domain now (~$10–15/year) | Best option technically; owner prefers to buy after the POC |
| Self-signed certificate | Browser warnings; breaks OAuth flows; teaches bad habits |
| DNS-01 challenge via DuckDNS API | Would place the DuckDNS token on the server; HTTP-01 is sufficient |

## Consequences

**Positive**
- Free, real HTTPS with trusted certificates; Google login testable end to end; no secrets on servers for DNS.

**Negative / risks**
- Depends on a free third-party service with no SLA.
- A compromised DuckDNS account enables hostname hijack (mitigated by MFA and no real users).
- The single hostname shares cookies and origin between app and Keycloak paths (acceptable; split with the real domain).
- Apple login stays disabled until a domain exists.

**Follow-ups**
- After the POC: register a domain, supersede this ADR, implement ADR-0023 (Cloudflare), enable Apple login (ADR-0010).

## References

- https://www.duckdns.org/
- https://www.duckdns.org/spec.jsp
- https://publicsuffix.org/list/public_suffix_list.dat
- https://letsencrypt.org/docs/rate-limits/
- https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability
- https://github.com/cunnie/sslip.io/issues/108
- https://developers.google.com/identity/protocols/oauth2/web-server
- https://www.keycloak.org/docs/latest/server_admin/#_google
