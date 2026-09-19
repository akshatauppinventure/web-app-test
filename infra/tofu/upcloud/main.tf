# Two servers in us-nyc1 (ADR-0002, ADR-0003, ADR-0004): public IPv4 only (no IPv6 interface,
# ADR-0014/0022), private SDN interface for A<->B traffic, cloud-init from infra/host, keys-only login,
# provider firewall enabled with the rules in firewall.tf.

data "upcloud_storage" "template" {
  type        = "template"
  name        = var.template_name
  most_recent = true
}

locals {
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

resource "upcloud_server" "this" {
  for_each = local.servers

  hostname = "${var.hostname_prefix}-${each.key}"
  title    = "${var.hostname_prefix}-${each.key}"
  zone     = var.zone
  plan     = each.value.plan
  timezone = "UTC"
  metadata = true # cloud-init reads user_data from the metadata service
  firewall = true # ADR-0014 layer 1
  labels   = merge(var.labels, { role = each.key })

  template {
    storage                  = data.upcloud_storage.template.id
    size                     = var.disk_size_gb
    title                    = "${var.hostname_prefix}-${each.key}-os"
    filesystem_autoresize    = true
    delete_autoresize_backup = true
  }

  # Public IPv4 only. Deliberately no IPv6 interface (no AAAA record in the POC).
  network_interface {
    type              = "public"
    ip_address_family = "IPv4"
  }

  network_interface {
    type              = "private"
    network           = upcloud_network.private.id
    ip_address        = each.value.private_ip
    ip_address_family = "IPv4"
  }

  login {
    user            = var.admin_user
    keys            = [var.admin_ssh_public_key]
    create_password = false
  }

  user_data = each.value.user_data

  lifecycle {
    ignore_changes = [user_data] # first boot only; host changes go through infra/host + re-provisioning
  }
}
