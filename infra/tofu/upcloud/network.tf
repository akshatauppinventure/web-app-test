# SDN private network + router (ADR-0002 §2): carries only the WireGuard tunnel between A and B.
# No DHCP default route, so the public interface stays the default gateway.
resource "upcloud_router" "private" {
  name   = "${var.hostname_prefix}-router"
  labels = var.labels
}

resource "upcloud_network" "private" {
  name   = "${var.hostname_prefix}-private"
  zone   = var.zone
  router = upcloud_router.private.id
  labels = var.labels

  ip_network {
    address            = var.private_network_cidr
    dhcp               = true
    dhcp_default_route = false
    family             = "IPv4"
  }
}
