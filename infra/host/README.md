# Host configuration (ADR-0004, 0005, 0006, 0014, 0021, 0024, 0026)

Everything a VPS needs beyond Docker stacks: first-boot cloud-init, host firewall,
Docker daemon hardening, Portainer bootstrap, health/backup timers. WireGuard was removed from the POC
(ADR-0026); restoring it is item 1 of [`docs/production-hardening.md`](../../docs/production-hardening.md).

| Path | Purpose |
|---|---|
| `cloud-init/{edge,core}.yaml.tmpl` | First-boot config: admin user (keys only), Docker from Docker's apt repo (signing key embedded, fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`), packages, sysctl hardening, key-only sshd, unattended-upgrades with 04:00 UTC reboot, and every file below embedded |
| `scripts/render-cloud-init.sh` | Renders a template with a vars file (hostname, admin user + SSH key, public interface, private-network addresses, SSH source CIDRs) and embeds the repo files, so **the committed files are the single source of truth** |
| `nftables/{edge,core}.nft` | Layer-2 firewall, input/forward policy DROP: both accept SSH on the public interface from `ADMIN_SSH_CIDRS` only, at most 10 new connections per minute per source; A's 80/443 reach Traefik through Docker DNAT; IPv6 dropped except ICMPv6 essentials |
| `scripts/docker-user-rules.sh` + `systemd/docker-user-rules.service` | `DOCKER-USER` chain (iptables-nft, runs before Docker's rules): A → 80/443 public, 9001 from core's private address; B → 8080/8000 from edge's private address (`PEER_IP` in `/etc/app/host.env`, never via the public interface); every other new connection dropped. Re-applied after every Docker start |
| `docker/daemon.json` | `ip: 127.0.0.1` default bind, `no-new-privileges`, `live-restore`, `userland-proxy: false`, `icc: false`, `local` log driver with rotation, address pool `172.28.0.0/16` |
| `systemd/docker.service.d/ordering.conf` | Docker starts after nftables and `network-online.target` so private-network (`10.0.0.x`) binds succeed |
| `scripts/resolve-public-if.sh` | First boot: replaces `PUBLIC_IF=auto` in `nftables.conf` and `host.env` with the default-route interface (UpCloud and OVH name it differently) |
| `bootstrap/portainer-{server,agent}.compose.yaml` | Portainer CE 2.45 (digest-pinned) started by an admin as project `portainer` after secrets exist (ADR-0006 amendment); Server on `127.0.0.1:9443` (reached with `ssh -L`), Agent on edge's private address `10.0.0.11:9001` |
| `scripts/healthcheck.sh` + timer | Every 5 min: containers healthy, peer answers ping on the private network, disk < 80 %, backup age < 26 h (core), certificate expiry > 14 d (edge); journald + optional `NOTIFY_WEBHOOK_URL` in `/etc/app/host.env` |
| `scripts/pg-backup.sh` + timer (core) | 02:30 America/New_York: `pg_dump` of `app` and `keycloak`, `pg_dumpall --globals-only`, Portainer data → restic (`forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune`); success stamp `/var/lib/app/last-backup-ok` |
| `scripts/restic-check.sh` + timer (core) | Weekly `restic check`; `--read-data` variant monthly (run by hand or a second timer) |
| `scripts/restore-drill.sh` (core) | Restores the latest dumps into a scratch Postgres and prints a log row for `docs/runbooks/restore-drill-log.md` |

## Rendering and validating

```bash
cp scripts/test/host-vars.example /tmp/edge.vars   # edit: real admin key, interface, ADMIN_SSH_CIDRS
infra/host/scripts/render-cloud-init.sh edge /tmp/edge.vars /tmp/edge-cloud-init.yaml
make host-check     # shellcheck, cloud-init schema, nft -c, DOCKER-USER rules, render/boot-report/resolver tests (ubuntu:26.04 containers)
```

Provisioning order (T20, `docs/runbooks/provisioning.md`): render cloud-init for both hosts, then OpenTofu passes it as user data. First boot applies nftables, sshd and Docker. The admin SSHes to the public IPs, pushes secrets (T19) and starts the Portainer bootstrap project (T21).

Deviations from the ADRs, for review: `net.ipv4.ip_nonlocal_bind=1` lets Docker publish on the private-network address even if that interface comes up late; `net.ipv4.ip_forward=1` is required by Docker (the `forward` chain and `DOCKER-USER` keep the policy DROP); the unattended-upgrades reboot runs at 04:00 UTC (00:00 New York in summer) because the setting has no timezone of its own.
