# Provider firewall (ADR-0014 layer 1). OpenStack security groups are stateful, so unlike UpCloud's
# classic firewall no return-traffic rules are needed. The host nftables ruleset (infra/host/nftables)
# remains the source of truth; this is the outer layer. Default rules are deleted so nothing allows
# IPv6 or unrestricted ingress; egress IPv4 is allowed explicitly.

locals {
  service_rules = {
    edge = [
      { name = "http", comment = "HTTP to Traefik (ACME + redirect)", protocol = "tcp", port = 80 },
      { name = "https", comment = "HTTPS to Traefik", protocol = "tcp", port = 443 },
      { name = "wireguard", comment = "WireGuard", protocol = "udp", port = var.wireguard_port },
    ]
    core = [
      { name = "wireguard", comment = "WireGuard", protocol = "udp", port = var.wireguard_port },
    ]
  }

  common_rules = [
    { name = "icmp-echo", comment = "ICMP echo request", direction = "ingress", protocol = "icmp", port = 8, remote = "0.0.0.0/0" },
    { name = "private", comment = "private vRack network", direction = "ingress", protocol = null, port = null, remote = var.private_network_cidr },
    { name = "egress", comment = "default accept outbound IPv4", direction = "egress", protocol = null, port = null, remote = "0.0.0.0/0" },
  ]

  rules = merge([
    for role in keys(local.service_rules) : merge(
      { for r in local.service_rules[role] : "${role}-${r.name}" => {
        role = role, comment = r.comment, direction = "ingress", protocol = r.protocol, port = r.port, remote = "0.0.0.0/0"
      } },
      { for r in local.common_rules : "${role}-${r.name}" => merge(r, { role = role }) },
    )
  ]...)
}

resource "openstack_networking_secgroup_v2" "this" {
  for_each = local.service_rules

  region               = var.zone
  name                 = "${var.hostname_prefix}-${each.key}"
  description          = "ADR-0014 layer 1 for ${each.key}; nftables on the host is the source of truth"
  delete_default_rules = true
  tags                 = local.tags
}

resource "openstack_networking_secgroup_rule_v2" "this" {
  for_each = local.rules

  region            = var.zone
  security_group_id = openstack_networking_secgroup_v2.this[each.value.role].id
  description       = each.value.comment
  direction         = each.value.direction
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  # ICMP: port_range_min is the ICMP type (8 = echo request), port_range_max the code (0).
  port_range_min   = each.value.port
  port_range_max   = each.value.protocol == "icmp" ? 0 : each.value.port
  remote_ip_prefix = each.value.remote
}
