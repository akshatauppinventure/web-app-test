output "public_ipv4" {
  description = "Public IPv4 per server (edge -> DuckDNS record P8; both -> admin WireGuard endpoints)"
  value = {
    for k, s in openstack_compute_instance_v2.this : k => one([
      for n in s.network : n.fixed_ip_v4 if n.uuid == data.openstack_networking_network_v2.public.id
    ])
  }
}

output "private_ipv4" {
  description = "vRack private IPv4 per server (A<->B WireGuard endpoints, infra/host/wireguard/peers.yaml)"
  value = {
    for k, s in openstack_compute_instance_v2.this : k => one([
      for n in s.network : n.fixed_ip_v4 if n.uuid == openstack_networking_network_v2.private.id
    ])
  }
}

output "server_ids" {
  value = { for k, s in openstack_compute_instance_v2.this : k => s.id }
}

output "firewall_rule_counts" {
  description = "Security-group rules per server (edge 6, core 4); kept small on purpose (ADR-0014 layer 1)"
  value = {
    for role in keys(local.service_rules) : role => length([for k, r in local.rules : k if r.role == role])
  }
}
