# Two instances in the OVHcloud US region (ADR-0002, ADR-0003, ADR-0004, ADR-0025): public interface on
# Ext-Net, private vRack interface for WireGuard, cloud-init from infra/host, keys-only login, one
# security group per role (firewall.tf). Ext-Net also assigns IPv6; the security groups carry no IPv6
# rules, so IPv6 is dropped at the provider layer as on UpCloud (ADR-0014/0022).

data "openstack_images_image_v2" "template" {
  region      = var.zone
  name_regex  = var.template_name
  visibility  = "public"
  most_recent = true
}

data "openstack_networking_network_v2" "public" {
  region = var.zone
  name   = var.public_network_name
}

locals {
  tags = [for k, v in var.labels : "${k}:${v}"]
  servers = {
    edge = {
      plan       = var.edge_plan
      private_ip = var.edge_private_ip
      user_data  = file(var.cloud_init_edge_path)
    }
    core = {
      plan       = var.core_plan
      private_ip = var.core_private_ip
      user_data  = file(var.cloud_init_core_path)
    }
  }
}

resource "openstack_compute_keypair_v2" "admin" {
  region     = var.zone
  name       = "${var.hostname_prefix}-admin"
  public_key = var.admin_ssh_public_key
}

resource "openstack_compute_instance_v2" "this" {
  for_each = local.servers

  region          = var.zone
  name            = "${var.hostname_prefix}-${each.key}"
  image_id        = data.openstack_images_image_v2.template.id
  flavor_name     = each.value.plan
  key_pair        = openstack_compute_keypair_v2.admin.name
  security_groups = [openstack_networking_secgroup_v2.this[each.key].name]
  config_drive    = true # cloud-init reads user_data from the config drive, no metadata service dependency
  user_data       = each.value.user_data
  metadata        = merge(var.labels, { role = each.key, admin_user = var.admin_user })
  tags            = local.tags

  # Public IPv4 (Ext-Net). Listed first so it is the default route.
  network {
    uuid = data.openstack_networking_network_v2.public.id
  }

  # Private vRack network: WireGuard transport between A and B (fixed addresses as on UpCloud).
  network {
    uuid        = openstack_networking_network_v2.private.id
    fixed_ip_v4 = each.value.private_ip
  }

  lifecycle {
    ignore_changes = [user_data] # first boot only; host changes go through infra/host + re-provisioning
  }

  depends_on = [openstack_networking_subnet_v2.private]
}
