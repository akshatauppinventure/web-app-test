output "public_ipv4" {
  description = "Public IPv4 per server (edge -> DuckDNS record P8; both -> admin SSH, ~/.ssh/config)"
  value = {
    for k, s in upcloud_server.this : k => one([
      for nic in s.network_interface : nic.ip_address if nic.type == "public"
    ])
  }
}

output "private_ipv4" {
  description = "SDN private IPv4 per server (EDGE_PRIVATE_IP/CORE_PRIVATE_IP in the cloud-init vars)"
  value = {
    for k, s in upcloud_server.this : k => one([
      for nic in s.network_interface : nic.ip_address if nic.type == "private"
    ])
  }
}

output "server_ids" {
  value = { for k, s in upcloud_server.this : k => s.id }
}

output "firewall_rule_counts" {
  description = "Must stay under 20 per server (ADR-0014 layer 1, OVH portability); empty when manage_provider_firewall = false (trial account)"
  value       = { for k, f in upcloud_firewall_rules.this : k => length(f.firewall_rule) }
}
