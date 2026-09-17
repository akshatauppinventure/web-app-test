# Architecture Decision Records

This folder records the significant architecture decisions for the web application POC:
two UpCloud VPS in New York, a Next.js frontend, a FastAPI backend, PostgreSQL, Keycloak, Traefik and Portainer.

- **Format:** lightweight Nygard-style ADRs, one decision per file. See [ADR-0001](0001-record-architecture-decisions.md) and [template.md](template.md).
- **Status lifecycle:** `Proposed` → `Accepted` → (`Deprecated` | `Superseded by ADR-XXXX`).
- **Research baseline:** 2026-09-14. Version numbers in these ADRs reflect that date.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](0002-hosting-upcloud-us-nyc1-portable-design.md) | Hosting on UpCloud US-NYC1 with a provider-portable design | Accepted |
| [0003](0003-topology-edge-core-poc-3-tier-target.md) | Edge/core 2-VPS topology for the POC, 3-tier for production | Accepted |
| [0004](0004-host-os-ubuntu-lts.md) | Host OS: Ubuntu Server 26.04 LTS | Accepted |
| [0005](0005-docker-compose-and-host-native-components.md) | Docker Compose for services; host-native security components | Accepted |
| [0006](0006-portainer-ce-placement-and-access.md) | Portainer CE LTS: placement and access | Accepted |
| [0007](0007-frontend-nextjs.md) | Frontend: Next.js 16 on Node.js 24 LTS | Accepted |
| [0008](0008-backend-fastapi.md) | Backend: FastAPI on Python 3.14 | Accepted |
| [0009](0009-postgresql-18.md) | Database: PostgreSQL 18 | Accepted |
| [0010](0010-identity-provider-keycloak.md) | Identity provider: Keycloak | Accepted |
| [0011](0011-auth-integration-bff-jwt-rls.md) | Auth integration: BFF sessions, JWT validation, RLS | Accepted |
| [0012](0012-reverse-proxy-traefik-file-provider.md) | Reverse proxy: Traefik with the file provider | Accepted |
| [0013](0013-waf-and-intrusion-prevention-crowdsec.md) | WAF and intrusion prevention: CrowdSec | Accepted |
| [0014](0014-network-firewall-layers-and-docker.md) | Network firewall layers and Docker port exposure | Accepted |
| [0015](0015-wireguard-admin-and-site-to-site.md) | WireGuard for admin access and site-to-site traffic | Accepted |
| [0016](0016-secrets-sops-age.md) | Secrets management: SOPS + age | Accepted |
| [0017](0017-ci-github-actions-ghcr.md) | CI: GitHub Actions and GHCR | Accepted |
| [0018](0018-cd-gitops-portainer-polling.md) | CD: GitOps with Portainer polling | Accepted |
| [0019](0019-supply-chain-security.md) | Software supply-chain security | Accepted |
| [0020](0020-image-and-version-pinning-policy.md) | Image and version pinning policy | Accepted |
| [0021](0021-backups-and-restore.md) | Backups and restore | Accepted |
| [0022](0022-poc-hostname-and-tls-duckdns.md) | POC hostname and TLS: DuckDNS + Let's Encrypt | Accepted |
| [0023](0023-cloudflare-edge-deferred.md) | Cloudflare edge proxy (deferred) | Accepted |
| [0024](0024-observability-deferred.md) | Observability (minimal for POC, full stack deferred) | Accepted |
| [0025](0025-ovhcloud-second-provider-module.md) | OVHcloud Public Cloud as the second provider module | Accepted |
