# vRack private network + subnet (ADR-0002 §2, ADR-0025): carries only the WireGuard tunnel between A
# and B. No gateway on the subnet, so the public interface stays the default route (same intent as
# UpCloud's dhcp_default_route = false). OVH requires the vrack network type and a VLAN id; new Public
# Cloud projects come with a vRack, older ones must activate it once in the control panel (P15).
resource "openstack_networking_network_v2" "private" {
  region         = var.zone
  name           = "${var.hostname_prefix}-private"
  admin_state_up = true
  tags           = local.tags

  value_specs = {
    "provider:network_type"    = "vrack"
    "provider:segmentation_id" = tostring(var.private_network_vlan_id)
  }
}

resource "openstack_networking_subnet_v2" "private" {
  region      = var.zone
  name        = "${var.hostname_prefix}-private"
  network_id  = openstack_networking_network_v2.private.id
  cidr        = var.private_network_cidr
  ip_version  = 4
  enable_dhcp = true
  no_gateway  = true
  tags        = local.tags

  # Fixed server addresses (.1/.2) sit outside the DHCP pool.
  allocation_pool {
    start = cidrhost(var.private_network_cidr, 10)
    end   = cidrhost(var.private_network_cidr, -2)
  }
}
