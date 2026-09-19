# Provider firewall (ADR-0014 layer 1). UpCloud's server firewall is stateless and applies to the
# public interface, so return traffic for outbound connections needs explicit inbound rules. The
# host nftables ruleset (infra/host/nftables) remains the source of truth; this is the outer layer
# and stays under 20 rules per server for OVH portability.

locals {
  # Inbound return traffic for outbound connections the hosts make (apt, registries, ACME, DNS, NTP).
  return_rules = [
    { comment = "return: HTTPS responses", protocol = "tcp", source_port_start = "443", source_port_end = "443" },
    { comment = "return: HTTP responses (apt)", protocol = "tcp", source_port_start = "80", source_port_end = "80" },
    { comment = "return: DNS udp", protocol = "udp", source_port_start = "53", source_port_end = "53" },
    { comment = "return: DNS tcp", protocol = "tcp", source_port_start = "53", source_port_end = "53" },
    { comment = "return: NTP", protocol = "udp", source_port_start = "123", source_port_end = "123" },
  ]

  edge_service_rules = [
    { comment = "HTTP to Traefik (ACME + redirect)", protocol = "tcp", destination_port_start = "80", destination_port_end = "80" },
    { comment = "HTTPS to Traefik", protocol = "tcp", destination_port_start = "443", destination_port_end = "443" },
  ]

  core_service_rules = []

  rulesets = {
    edge = local.edge_service_rules
    core = local.core_service_rules
  }
}

resource "upcloud_firewall_rules" "this" {
  for_each  = var.manage_provider_firewall ? upcloud_server.this : {}
  server_id = each.value.id

  # 1. Drop all IPv6 (no IPv6 interface exists, belt and braces)
  firewall_rule {
    action    = "drop"
    direction = "in"
    family    = "IPv6"
    comment   = "drop all IPv6"
  }

  # 2. ICMP echo (monitoring / diagnostics)
  firewall_rule {
    action    = "accept"
    direction = "in"
    family    = "IPv4"
    protocol  = "icmp"
    icmp_type = "8"
    comment   = "ICMP echo request"
  }

  # 3. Public services
  dynamic "firewall_rule" {
    for_each = local.rulesets[each.key]
    content {
      action                 = "accept"
      direction              = "in"
      family                 = "IPv4"
      protocol               = firewall_rule.value.protocol
      destination_port_start = firewall_rule.value.destination_port_start
      destination_port_end   = firewall_rule.value.destination_port_end
      comment                = firewall_rule.value.comment
    }
  }

  # 3b. Admin SSH (keys only) from the allowed sources, both servers (ADR-0026)
  dynamic "firewall_rule" {
    for_each = var.admin_ssh_cidrs
    content {
      action                 = "accept"
      direction              = "in"
      family                 = "IPv4"
      protocol               = "tcp"
      source_address_start   = cidrhost(firewall_rule.value, 0)
      source_address_end     = cidrhost(firewall_rule.value, -1)
      destination_port_start = "22"
      destination_port_end   = "22"
      comment                = "SSH from ${firewall_rule.value}"
    }
  }

  # 4. Return traffic for outbound connections (stateless firewall)
  dynamic "firewall_rule" {
    for_each = local.return_rules
    content {
      action            = "accept"
      direction         = "in"
      family            = "IPv4"
      protocol          = firewall_rule.value.protocol
      source_port_start = firewall_rule.value.source_port_start
      source_port_end   = firewall_rule.value.source_port_end
      comment           = firewall_rule.value.comment
    }
  }

  # 5. Private SDN network (Keycloak/FastAPI and Portainer Agent between A and B; DOCKER-USER narrows it)
  firewall_rule {
    action               = "accept"
    direction            = "in"
    family               = "IPv4"
    source_address_start = cidrhost(var.private_network_cidr, 0)
    source_address_end   = cidrhost(var.private_network_cidr, -1)
    comment              = "private SDN network"
  }

  # 6. Default: drop everything else inbound, allow outbound
  firewall_rule {
    action    = "drop"
    direction = "in"
    comment   = "default drop inbound"
  }
  firewall_rule {
    action    = "accept"
    direction = "out"
    comment   = "default accept outbound"
  }
}
