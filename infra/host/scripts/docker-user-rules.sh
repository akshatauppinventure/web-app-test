#!/usr/bin/env bash
# Re-applies the DOCKER-USER chain (iptables-nft) after Docker starts (ADR-0014 layer 2, ADR-0026).
# Docker's own rules accept DNAT'd traffic to published ports; DOCKER-USER runs first, so this is
# where per-source restrictions for container ports live. Usage: docker-user-rules.sh edge|core
# PEER_IP (from /etc/app/host.env) is the other host's private-network address. Admin UIs are reached
# through SSH port forwarding, which originates on the host and never passes this chain.
set -euo pipefail
ROLE="${1:?role required: edge|core}"
PUBLIC_IF="${PUBLIC_IF:-$(ip -o -4 route show default | awk '{print $5}' | head -1)}"
PEER_IP="${PEER_IP:?PEER_IP must be the peer private-network address}"
[[ "$PEER_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "PEER_IP is not an IPv4 address: $PEER_IP" >&2; exit 2; }
IPT=(iptables -w 10)

"${IPT[@]}" -N DOCKER-USER 2>/dev/null || true
"${IPT[@]}" -F DOCKER-USER

# Return traffic and connections from containers outward are always fine.
"${IPT[@]}" -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
# Traffic arriving from Docker bridges (container-to-container, container-initiated) is fine.
"${IPT[@]}" -A DOCKER-USER -i docker0 -j RETURN
"${IPT[@]}" -A DOCKER-USER -i br+ -j RETURN

case "$ROLE" in
  edge)
    # Public: only Traefik (host ports 80/443; --ctorigdstport matches the pre-DNAT port).
    "${IPT[@]}" -A DOCKER-USER -i "$PUBLIC_IF" -p tcp -m conntrack --ctstate NEW --ctorigdstport 80  -j RETURN
    "${IPT[@]}" -A DOCKER-USER -i "$PUBLIC_IF" -p tcp -m conntrack --ctstate NEW --ctorigdstport 443 -j RETURN
    # Portainer Agent only from the core host's private address, never via the public interface.
    "${IPT[@]}" -A DOCKER-USER ! -i "$PUBLIC_IF" -s "$PEER_IP" -p tcp -m conntrack --ctstate NEW --ctorigdstport 9001 -j RETURN
    ;;
  core)
    # Keycloak and FastAPI only from the edge host's private address, never via the public interface.
    "${IPT[@]}" -A DOCKER-USER ! -i "$PUBLIC_IF" -s "$PEER_IP" -p tcp -m conntrack --ctstate NEW --ctorigdstport 8080 -j RETURN
    "${IPT[@]}" -A DOCKER-USER ! -i "$PUBLIC_IF" -s "$PEER_IP" -p tcp -m conntrack --ctstate NEW --ctorigdstport 8000 -j RETURN
    ;;
  *) echo "unknown role $ROLE" >&2; exit 2 ;;
esac

# Everything else that tries to reach a container from outside (public or private network) is dropped.
"${IPT[@]}" -A DOCKER-USER -i "$PUBLIC_IF" -m conntrack --ctstate NEW -j DROP
"${IPT[@]}" -A DOCKER-USER -m conntrack --ctstate NEW -j DROP
"${IPT[@]}" -A DOCKER-USER -j RETURN
echo "DOCKER-USER rules applied for role $ROLE on $PUBLIC_IF (peer $PEER_IP)"
