# Host configuration (ADR-0004, 0005, 0006, 0014, 0015, 0021, 0024)

Everything a VPS needs beyond Docker stacks: first-boot cloud-init, host firewall, WireGuard,
Docker daemon hardening, Portainer bootstrap, health/backup timers.

| Path | Purpose |
|---|---|
| `cloud-init/{edge,core}.yaml.tmpl` | First-boot config: admin user (keys only), Docker from Docker's apt repo (signing key embedded, fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`), packages, sysctl hardening, sshd on the WireGuard IP, unattended-upgrades with 04:00 UTC reboot, and every file below embedded |
| `scripts/render-cloud-init.sh` | Renders a template with a vars file (hostname, admin user + SSH key, public interface, WireGuard peer keys/endpoints) and embeds the repo files, so **the committed files are the single source of truth** |
| `nftables/{edge,core}.nft` | Layer-2 firewall, input/forward policy DROP: A accepts 80/443 (via Docker DNAT) + UDP 51820; B accepts UDP 51820 only; SSH only on `wg0` from `10.10.0.10–19`; IPv6 dropped except ICMPv6 essentials |
| `scripts/docker-user-rules.sh` + `systemd/docker-user-rules.service` | `DOCKER-USER` chain (iptables-nft, runs before Docker's rules): A → 80/443 public, 9001 from `10.10.0.2`; B → 8080/8000 from `10.10.0.1`, 9443/8080 from admin peers; everything else new from `eth0`/`wg0` dropped. Re-applied after every Docker start |
| `docker/daemon.json` | `ip: 127.0.0.1` default bind, `no-new-privileges`, `live-restore`, `userland-proxy: false`, `icc: false`, `local` log driver with rotation, address pool `172.28.0.0/16` |
| `systemd/docker.service.d/wireguard.conf` | Docker starts after `wg-quick@wg0` and nftables so `10.10.0.x` binds succeed |
| `wireguard/wg0-{edge,core}.conf.tmpl`, `wireguard/peers.yaml`, `scripts/wg-apply-psks.sh`, `scripts/wg-rotate-key.sh` | Interface templates rendered with a **bootstrap** key pair generated on the laptop (so every peer is valid at first boot); on first contact `wg-rotate-key.sh` replaces it with a key generated on the host that never leaves it (`scripts/host/finalize-wireguard.sh` drives this for both hosts); public-key peer map; PostUp hook applying pre-shared keys from `/etc/wireguard/psk-*` files pushed as secrets |
| `scripts/resolve-public-if.sh` | First boot: replaces `PUBLIC_IF=auto` in `nftables.conf` and `host.env` with the default-route interface (UpCloud and OVH name it differently) |
| `bootstrap/portainer-{server,agent}.compose.yaml` | Portainer CE 2.45 (digest-pinned) started by an admin as project `portainer` after secrets exist (ADR-0006 amendment); Server on `10.10.0.2:9443`, Agent on `10.10.0.1:9001` |
| `scripts/healthcheck.sh` + timer | Every 5 min: containers healthy, WireGuard handshake < 3 min, disk < 80 %, backup age < 26 h (core), certificate expiry > 14 d (edge); journald + optional `NOTIFY_WEBHOOK_URL` in `/etc/app/host.env` |
| `scripts/pg-backup.sh` + timer (core) | 02:30 America/New_York: `pg_dump` of `app` and `keycloak`, `pg_dumpall --globals-only`, Portainer data → restic (`forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune`); success stamp `/var/lib/app/last-backup-ok` |
| `scripts/restic-check.sh` + timer (core) | Weekly `restic check`; `--read-data` variant monthly (run by hand or a second timer) |
| `scripts/restore-drill.sh` (core) | Restores the latest dumps into a scratch Postgres and prints a log row for `docs/runbooks/restore-drill-log.md` |

## Rendering and validating

```bash
cp scripts/test/host-vars.example /tmp/edge.vars   # edit: real admin key, interface, peer keys
infra/host/scripts/render-cloud-init.sh edge /tmp/edge.vars /tmp/edge-cloud-init.yaml
make host-check     # shellcheck, cloud-init schema, nft -c, wg-quick strip, DOCKER-USER rules (ubuntu:26.04 containers)
```

Provisioning order (T20, `docs/runbooks/provisioning.md`): the laptop generates one bootstrap WireGuard key pair per host and renders them into cloud-init → OpenTofu passes it as user data → first boot brings `wg0` up with valid peers → the laptop tunnel (`scripts/host/render-laptop-wg.sh`) connects → `scripts/host/finalize-wireguard.sh` rotates both host keys on the hosts, rewires every peer and prints the `peers.yaml` snippet → secrets are pushed (T19) → the Portainer bootstrap project starts (T21). Bootstrap private keys exist only in the gitignored `.tofu-rendered/` and in the provider's user_data until rotation, then are deleted.

Deviations from the ADRs, for review: sshd binds the WireGuard IP with `net.ipv4.ip_nonlocal_bind=1` so it can start before `wg0` exists (nftables still allows port 22 only on `wg0`); `net.ipv4.ip_forward=1` is required by Docker (the `forward` chain and `DOCKER-USER` keep the policy DROP); the unattended-upgrades reboot runs at 04:00 UTC (00:00 New York in summer) because the setting has no timezone of its own.
