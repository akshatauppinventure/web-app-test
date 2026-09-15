# ADR-0013: WAF and intrusion prevention: CrowdSec

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0010, ADR-0012, ADR-0014, ADR-0023

## Context

The public edge (VPS-A) needs:
- automated blocking of abusive IPs (scanners, credential stuffing, known-bad reputation),
- protection against common web exploits (SQL injection, XSS, path traversal, known CVEs) in front of Next.js and Keycloak.

Research (2026):
- **CrowdSec** is the modern successor to fail2ban. It's written in Go, IPv6-aware, handles Docker logs properly, uses community blocklists, and separates detection from enforcement ("bouncers").
- The **CrowdSec Traefik bouncer plugin** supports stream mode and **AppSec** (a WAF with virtual patching and ModSecurity/CRS-compatible rules).
- Coraza (OWASP) is also available as a Traefik WASM plugin.

## Decision

1. **Engine:**
   - The **CrowdSec** security engine runs as a container on VPS-A (`crowdsecurity/crowdsec`, pinned by digest).
   - Reads Traefik's JSON access log (read-only volume) and host `auth.log` / journald for sshd.
   - Collections: `crowdsecurity/traefik`, `crowdsecurity/http-cve`, `crowdsecurity/base-http-scenarios`, `crowdsecurity/sshd`, `crowdsecurity/appsec-virtual-patching`, `crowdsecurity/appsec-generic-rules`.
2. **Local API (LAPI) and AppSec listeners:** reachable **only on the `edge` Docker network** (not published). Bouncer API keys are secrets (ADR-0016).
3. **Enforcement:**
   - The **Traefik CrowdSec bouncer plugin** (ADR-0012), in **stream mode** (decisions pulled every 60 s), applied to all public routers.
   - **AppSec enabled.**
   - **Phase 1 (first 2 weeks of the POC): AppSec findings logged, not blocked** (detection only), to find false positives on Next.js and Keycloak flows.
   - **Phase 2:** switch AppSec to **blocking** once tuned. IP-reputation bans block from day one.
   - Bans: default 4 hours, escalating for repeat offenders.
4. **Behavior if LAPI is unreachable:** **fail-open** during the POC (traffic flows, alert logged), so a CrowdSec outage doesn't take the site down. **Revisit for production** (fail-closed for `/auth` paths).
5. **Community blocklist:**
   - Enroll the engine in the free CrowdSec Console to receive community blocklists.
   - Enrollment shares attacking IPs and scenario names (no request bodies). Accepted for the POC.
6. **Complements, not replacements:**
   - Keycloak brute-force detection (ADR-0010).
   - Traefik rate limits (ADR-0012).
   - SSH isn't publicly reachable anyway (ADR-0015); the sshd collection covers WireGuard-side misuse.
7. **Allowlist:** admin WireGuard subnet `10.10.0.0/24` and the monitoring source (later) are allowlisted to prevent self-lockout.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| fail2ban | Single-host only, slower, no community intel, awkward with Docker JSON logs |
| Coraza WAF (WASM plugin) + OWASP CRS | Strong, but CrowdSec AppSec gives WAF + IP reputation in one component; WASM plugin adds latency; keep as an option |
| ModSecurity | Legacy engine (end of commercial support), no native Traefik integration |
| Cloudflare WAF | Not FOSS; deferred to post-POC as an extra outer layer (ADR-0023) |
| CrowdSec host firewall bouncer (nftables) | Useful for non-HTTP ports; our only public non-HTTP port is WireGuard (silent), so the HTTP-layer bouncer suffices for the POC |

## Consequences

**Positive**
- Blocks known-bad IPs and common exploit patterns before they reach Next.js or Keycloak; FOSS; low overhead.

**Negative / risks**
- WAF false positives can break login flows. Mitigated by a detection-only phase and targeted rule exclusions.
- Fail-open trades security for availability during the POC.
- Behind Cloudflare later, the real client IP must be configured correctly, or CrowdSec will ban Cloudflare IPs (ADR-0023).

**Follow-ups**
- Tune AppSec and switch to blocking.
- Alert routing (email/webhook) with the observability stack (ADR-0024).

## References

- https://docs.crowdsec.net/u/bouncers/traefik/
- https://github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
- https://www.crowdsec.net/blog/waf-traefik-crowdsec
- https://itrpoka.com/blog/fail2ban-vs-crowdsec/
- https://plugins.traefik.io/plugins/65f2aea146079255c9ffd1ec/coraza-waf
