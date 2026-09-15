# ADR-0024: Observability (minimal for POC, full stack deferred)

- **Status:** Accepted (2026-09-15)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0005, ADR-0006, ADR-0013, ADR-0015, ADR-0021

## Context

A full observability stack (metrics, logs, traces, alerting) is valuable for production, but it's significant work and uses significant resources on small VPS. For the POC we need enough visibility to:
- detect outages, failed backups and attacks,
- debug problems,
- without adding new internet-exposed components.

## Decision

1. **POC (minimal, no new services):**
   - **Health checks:**
     - Docker `healthcheck` on every long-running container.
     - Traefik `ping`; FastAPI `/healthz` and `/readyz`; Keycloak management `/health/ready` on internal port 9000; `pg_isready`.
   - **Logs:**
     - Docker `local` log driver with rotation (ADR-0014).
     - Traefik JSON access log (consumed by CrowdSec) and FastAPI structured JSON logs.
     - Keycloak login/admin events enabled (realm `app` events kept 7 days).
     - Viewed via Portainer (over WireGuard) or `docker logs` over SSH.
   - **Security signals:** CrowdSec decisions and alerts (`crowdsec-cli alerts list`); Keycloak brute-force lockouts.
   - **Host checks:**
     - A systemd timer script (`infra/host/healthcheck.sh`) every 5 minutes checks: containers healthy, WireGuard A↔B handshake age < 3 minutes, disk usage < 80%, last backup success < 26 hours, certificate expiry > 14 days.
     - Failures are written to journald. **Notification:** email or webhook via a simple outbound call (e.g. a free ntfy.sh topic or SMTP), configured during implementation.
   - **External uptime:** one free external HTTPS uptime check against `https://<poc-host>/` (e.g. a free-tier uptime monitor), so outages are noticed even if both servers are down.
2. **Production (deferred; own ADR before production):**
   - Candidate FOSS stack: **Prometheus + Alertmanager + Grafana + Loki** (with Grafana Alloy or Promtail), plus node_exporter, cAdvisor, postgres_exporter, and Keycloak/Traefik/CrowdSec metrics.
   - Hosted on the **data/ops tier** (3-tier target), reachable only over WireGuard.
   - **Uptime Kuma** for synthetic checks; OpenTelemetry tracing for FastAPI/Next.js if needed.
   - Log retention and personal-data minimization policy.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Full Prometheus/Grafana/Loki in the POC | 1–2 GB extra RAM and more configuration; not needed to prove the architecture |
| SaaS observability (Datadog, Grafana Cloud, etc.) | Not FOSS; sends logs (possibly containing personal data) to third parties; free tiers are an option later |
| Nothing beyond Portainer | Backup failures, certificate expiry and tunnel failures would go unnoticed |

## Consequences

**Positive**
- Key failure modes (outage, backup, certificates, tunnel, disk, attacks) are detected with near-zero extra footprint.

**Negative / risks**
- No historical metrics or dashboards; troubleshooting relies on logs.
- Alert delivery via a free external service is a small dependency.

**Follow-ups**
- Production observability ADR; alert routing for CrowdSec and Keycloak events.

## References

- https://prometheus.io/
- https://grafana.com/oss/loki/
- https://github.com/louislam/uptime-kuma
- https://www.keycloak.org/observability/health
- https://doc.traefik.io/traefik/operations/ping/
