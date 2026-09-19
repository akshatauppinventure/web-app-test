# ADR-0026: Remove WireGuard from the POC; key-only public SSH and the provider private network

- **Status:** Accepted (2026-09-19)
- **Date:** 2026-09-19
- **Deciders:** Project owner
- **Related:** supersedes ADR-0015; amends ADR-0003, ADR-0006, ADR-0010, ADR-0013, ADR-0014, ADR-0016; ADR-0002, ADR-0025

## Context

- ADR-0015 put every admin service (SSH, Portainer, the Keycloak admin console) and all traffic between the two servers on a WireGuard mesh (`wg0`, `10.10.0.0/24`, UDP 51820).
- Provisioning (T20, 2026-09-17) showed the cost of that design for a two-server POC. Each host needs a bootstrap key pair rendered on the laptop, a key rotation on first contact, per-peer pre-shared keys, and a laptop tunnel before anything can be checked. When the tunnel does not come up, the hosts cannot be reached at all except through the provider console, because sshd listened on the WireGuard address only.
- On 2026-09-19 the owner decided to disable WireGuard completely for the POC, remove its code, and track it as a production-hardening item instead ([`docs/production-hardening.md`](../production-hardening.md)).
- Both provider modules already give each server a private-network interface: UpCloud SDN (`10.0.0.11` edge, `10.0.0.2` core) and the OVH vRack network with the same addresses (ADR-0025). Until now that network only carried the WireGuard tunnel.

## Decision

We will run the POC without WireGuard.

1. **Admin SSH on the public interface.**
   - sshd listens on all addresses. The existing hardening stays: keys only, `AllowUsers admin`, no root, no passwords, `MaxAuthTries 3`.
   - nftables accepts TCP 22 on the public interface only from `ADMIN_SSH_CIDRS` (render variable) and limits new connections per source address.
   - The provider firewall allows TCP 22 only from the OpenTofu variable `admin_ssh_cidrs` (both modules).
   - Both default to `0.0.0.0/0`, because the owner's address is not fixed. Narrowing them to the owner's current address is recommended and is a one-line change.
2. **Site-to-site traffic over the provider private network.**
   - Keycloak and FastAPI publish on core's private address `10.0.0.2:8080` and `10.0.0.2:8000`. The Portainer Agent publishes on edge's private address `10.0.0.11:9001`.
   - `DOCKER-USER` allows those ports only from the peer's private address and never from the public interface. `rp_filter=1` drops packets that claim a private source address on the public interface.
   - Traffic on this network is **not encrypted** by us. The Portainer Server to Agent link is TLS. Keycloak and FastAPI traffic from edge to core is plain HTTP inside the provider's private network. We accept this for the POC.
3. **Admin UIs through SSH port forwarding.**
   - Portainer Server publishes on `127.0.0.1:9443` on core and is reached with `ssh -L 9443:127.0.0.1:9443`.
   - The Keycloak admin console is reached with `ssh -L 8080:10.0.0.2:8080`. `KC_HOSTNAME_ADMIN` is `http://localhost:8080/auth`.
   - Port forwarding comes from the host itself, so it passes through neither the public interface rules nor `DOCKER-USER`.
4. **Removed:** `wireguard-tools`, `wg0` templates, `peers.yaml`, the bootstrap and rotation scripts, the laptop config renderer, the WireGuard pre-shared-key secrets, the provider firewall rules for UDP 51820, the `wireguard_port` variable and the handshake health check. The `10.10.0.0/24` range is no longer used anywhere.
5. **CrowdSec** allowlists the private network `10.0.0.0/24` instead of `10.10.0.0/24`. Its sshd collection on edge now sees internet traffic. Decisions still apply only at the HTTP layer, because there is no firewall bouncer.

The previous design is preserved in ADR-0015 and in git history (last commit with WireGuard on `main`: `fe89dd9`). Restoring it is item 1 of the production-hardening list.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Keep WireGuard and finish T20 | The owner chose to drop it for the POC after the bootstrap difficulties |
| Tailscale / NetBird / Headscale | Still a VPN to bootstrap. ADR-0015's reasons for plain WireGuard still apply, and they belong to the production decision |
| SSH only from a fixed source IP, no default | The owner's address is dynamic. A wrong allowlist would lock them out, so the allowlist stays an opt-in variable |
| Bastion host | A third server and more cost for two hosts |
| TLS between Traefik/Next.js and Keycloak/FastAPI | Right for production (listed in the hardening list). It needs an internal CA and changes the images, which is not justified for the POC |

## Consequences

**Positive**
- The hosts are reachable over plain SSH as soon as cloud-init finishes. There is no bootstrap key, rotation step or laptop tunnel.
- Seven WireGuard-only files are gone: interface templates, the peer map, and the pre-shared-key, rotation, finalize and laptop-config scripts. Secrets lose two entries per host.
- The same design works on UpCloud and on OVH.

**Negative / risks**
- SSH is internet-visible on both hosts. It is mitigated by keys only, rate limits, the optional source allowlists and unattended security upgrades. CrowdSec cannot block SSH yet.
- Edge-to-core HTTP traffic, including OAuth codes, tokens and the BFF client secret on the token call, is plaintext on the provider's private network. The risk is the provider or another tenant on a compromised SDN.
- Admin UIs depend on SSH forwarding. This is acceptable for one admin.
- The ADR-0024 health check loses the tunnel handshake check. It is replaced by a ping of the peer's private address.

**Follow-ups**
- [`docs/production-hardening.md`](../production-hardening.md) item 1: restore a VPN for admin and site-to-site traffic, or add TLS between the tiers and a source allowlist for SSH.
- The running T20 servers were created with WireGuard-only SSH and must be re-created (`docs/runbooks/provisioning.md`).

## References

- ADR-0015 (superseded)
- https://man.openbsd.org/ssh#L
- https://upcloud.com/docs/products/networking/sdn-private-networks/
- https://wiki.nftables.org/wiki-nftables/index.php/Meters
