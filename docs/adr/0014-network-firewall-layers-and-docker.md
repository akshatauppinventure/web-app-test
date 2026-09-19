# ADR-0014: Network firewall layers and Docker port exposure

- **Status:** Accepted (2026-09-15); amended by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md) (SSH on the public interface, site-to-site rules use private-network addresses)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0002, ADR-0003, ADR-0005, ADR-0006, ADR-0012, ADR-0015

## Context

The owner wants everything blocked from outside except what is strictly needed. A well-known pitfall: **Docker writes its own iptables rules** (DNAT in `PREROUTING`, the `DOCKER` chain off `FORWARD`), so **published container ports bypass UFW/INPUT rules**. The supported hook for user filtering is the **`DOCKER-USER`** chain. Since Docker Engine 27, ip6tables management is on by default, so IPv6 needs the same care.

UpCloud's classic firewall is stateless; SDN firewall rules are stateful. OVH's Edge Network Firewall allows 20 rules per IP (ADR-0002).

## Decision

We will enforce **three independent layers**, all default-deny.

### Layer 1: provider firewall (outside the host; Docker can't bypass it)

| Server | Inbound allowed | Everything else |
|---|---|---|
| VPS-A (edge) | TCP 80, TCP 443 from any; UDP 51820 from any; ICMP echo (rate-limited if supported) | DROP |
| VPS-B (core) | UDP 51820 from any; ICMP echo | DROP |

- Outbound: allowed (POC).
- With the stateless classic firewall, explicit rules for return traffic (DNS, NTP, HTTPS responses) are added. Stateful SDN rules are preferred where available. **Validated during provisioning** by checking `apt update`, image pulls and NTP.
- The ruleset stays under 20 entries per server, for OVH portability.

### Layer 2: host firewall (nftables, source of truth, committed in `infra/host/`)

- **`inet filter input` policy DROP.** Accept `lo`, `established,related`, ICMP/ICMPv6 essentials.
  - **VPS-A:** TCP 80/443 on the public interface; UDP 51820 on the public interface.
  - **VPS-B:** UDP 51820 only.
  - **Both:** TCP 22 **only on `wg0` from admin peers `10.10.0.10–19`**.
- **`forward` policy DROP** except what Docker needs, with filtering placed in **`DOCKER-USER`** (iptables-nft), which runs before Docker's own rules:
  - **VPS-A:**
    - Allow new connections to Traefik (80/443) from the public interface.
    - Allow Portainer Agent (9001) **only from `10.10.0.2` on `wg0`**.
    - Drop all other new inbound forwarded connections.
  - **VPS-B:**
    - Allow Keycloak 8080 and FastAPI 8000 **only from `10.10.0.1` on `wg0`**.
    - Allow Portainer 9443 and Keycloak admin 8080 from admin peers `10.10.0.10–19` on `wg0`.
    - Drop all other new inbound forwarded connections.
  - Match the original destination port with `conntrack --ctorigdstport`, because DNAT has already rewritten the port.
- The same rules are mirrored for **IPv6**, or IPv6 is disabled on Docker networks and the public IPv6 input policy is DROP except the explicitly allowed services. **POC choice: no public AAAA record** (ADR-0022), Docker networks IPv4-only, and the host IPv6 input policy DROP.
- Rules persist across reboots and `docker` restarts (systemd unit ordering: nftables → docker → DOCKER-USER rules re-applied).

### Layer 3: Docker exposure rules

- **`/etc/docker/daemon.json`** (both servers):
  ```json
  {
    "ip": "127.0.0.1",
    "no-new-privileges": true,
    "live-restore": true,
    "userland-proxy": false,
    "icc": false,
    "log-driver": "local",
    "log-opts": { "max-size": "10m", "max-file": "5" }
  }
  ```
  `"ip": "127.0.0.1"` makes any `ports:` entry without an explicit IP bind to localhost, so an accidental exposure isn't public.
- **Published ports allowlist.** Anything not in this table must not appear in compose files; CI checks this.

  | Server | Service | Bind |
  |---|---|---|
  | A | Traefik | `0.0.0.0:80`, `0.0.0.0:443` |
  | A | Portainer Agent | `10.10.0.1:9001` |
  | B | Keycloak | `10.10.0.2:8080` |
  | B | FastAPI | `10.10.0.2:8000` |
  | B | Portainer Server | `10.10.0.2:9443` |
  | B | PostgreSQL | **not published** |

- Internal-only Docker networks use `internal: true` (e.g. `db` on B).

## Alternatives considered

| Option | Why not chosen |
|---|---|
| UFW alone | Bypassed by Docker-published ports unless `DOCKER-USER`/ufw-docker rules are added; nftables gives one explicit ruleset |
| `"iptables": false` in Docker | Breaks container networking/NAT and requires hand-written NAT rules; fragile |
| Provider firewall only | Doesn't protect against a misconfiguration on the host side or a future provider without a capable firewall |
| Docker nftables backend (experimental in 29.x) | Not production-ready yet; revisit when stable |

## Consequences

**Positive**
- An accidental port publish is blocked by three layers. Only 80/443 (A) and a silent WireGuard port are internet-visible.

**Negative / risks**
- `DOCKER-USER` rules must be re-applied reliably after Docker restarts; tested in verification.
- Stateless provider rules can accidentally block return traffic; validated at provisioning.
- Outbound traffic is unrestricted in the POC (an exfiltration path after compromise). Production follow-up.

**Follow-ups**
- Production: outbound filtering (allowlisted destinations/ports) on B/C.
- Verification: run `nmap` TCP/UDP scans from outside, and a test container published on `0.0.0.0:8081` must stay unreachable.

## References

- https://docs.docker.com/engine/network/packet-filtering-firewalls/
- https://github.com/docker/for-linux/issues/690
- https://github.com/chaifeng/ufw-docker
- https://upcloud.com/docs/products/networking/firewall/
- https://docs.ovhcloud.com/en/guides/bare-metal-cloud/dedicated-servers/firewall-network
