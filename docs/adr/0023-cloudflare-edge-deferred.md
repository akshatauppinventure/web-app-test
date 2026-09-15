# ADR-0023: Cloudflare edge proxy (deferred)

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0012, ADR-0013, ADR-0014, ADR-0022

## Context

Putting Cloudflare's free proxy in front of the origin:
- hides the origin IP,
- absorbs volumetric DDoS attacks,
- adds an optional managed WAF/bot layer.

The owner plans to add Cloudflare **after the POC**. Cloudflare isn't FOSS, but its free tier is widely used. The proxy requires a domain whose DNS is hosted on Cloudflare, so it **can't be used with the DuckDNS POC hostname** (ADR-0022).

## Decision

1. **Deferred:** no Cloudflare during the POC.
2. **The POC design stays Cloudflare-ready.** Enabling it later requires only configuration:
   1. **Domain:** register a domain and move its DNS to Cloudflare. Create proxied (orange-cloud) records `app.<domain>` and `auth.<domain>`, or a single host with `/auth` as in the POC.
   2. **TLS:** SSL mode **Full (strict)**. The origin serves either a Let's Encrypt certificate (DNS-01 via Cloudflare API token) or a **Cloudflare Origin CA** certificate. Optionally enable **Authenticated Origin Pulls** (mTLS from Cloudflare to Traefik).
   3. **Origin lock-down:** provider firewall and nftables allow TCP 80/443 **only from Cloudflare's published IPv4/IPv6 ranges** (refreshed by a scheduled job). Direct-to-IP requests then fail.
   4. **Real client IP:**
      - Traefik `entryPoints.websecure.forwardedHeaders.trustedIPs` = Cloudflare ranges.
      - CrowdSec and Traefik logs use `CF-Connecting-IP` / `X-Forwarded-For` from trusted proxies only, so bans target real clients, not Cloudflare.
      - Keycloak/FastAPI proxy settings unchanged (they trust only Traefik).
   5. **Cloudflare settings:** "Always Use HTTPS", HSTS (preload with a real domain), minimum TLS 1.2, Bot Fight Mode (review compatibility with the OAuth callback paths `/auth/realms/app/broker/*`), cache bypass for `/auth/*` and authenticated routes.
   6. **Keycloak / Google / Apple redirect URIs:** update to the new hostname. This also unblocks enabling **Apple login** (ADR-0010).
3. **CrowdSec and Traefik rate limits stay in place** as origin-side defense in depth.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Enable Cloudflare in the POC | No owned domain yet; DuckDNS isn't compatible |
| Self-hosted DDoS mitigation | Not realistic at VPS scale; provider-level mitigation plus Cloudflare later is the practical path |
| Other CDN/WAF (Bunny, Fastly, etc.) | Cloudflare's free tier has the broadest adoption; revisit if requirements change |

## Consequences

**Positive**
- A clear, low-effort path to origin-IP hiding and DDoS absorption once a domain exists.

**Negative / risks**
- During the POC the origin IP is public and relies on UpCloud's network DDoS mitigation.
- Cloudflare terminates TLS, so it can see plaintext traffic (a trust decision for production).

**Follow-ups**
- Buy a domain; supersede ADR-0022 with a production hostname ADR; implement this checklist.

## References

- https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/
- https://www.cloudflare.com/ips/
- https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/
- https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
- https://doc.traefik.io/traefik/routing/entrypoints/#forwarded-headers
