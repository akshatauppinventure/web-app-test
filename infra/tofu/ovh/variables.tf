# Same contract as infra/tofu/upcloud (scripts/test/tofu-contract.sh): identical variable and output
# names, so one terraform.tfvars and the same downstream steps work on either provider (ADR-0025).

variable "zone" {
  description = "OVHcloud Public Cloud region (ADR-0002 §Alternatives: Vint Hill, VA = US-EAST-VA-1)"
  type        = string
  default     = "US-EAST-VA-1"
}

variable "template_name" {
  description = "Regex for the public OS image name (ADR-0004); OVH names images 'Ubuntu <version>'"
  type        = string
  default     = "^Ubuntu 26\\.04"
}

variable "edge_plan" {
  description = "Flavor for VPS-A edge (ADR-0002 §3: 2 vCPU / 4 GB): Discovery d2-4 or General Purpose b3-8"
  type        = string
  default     = "d2-4"
}

variable "core_plan" {
  description = "Flavor for VPS-B core (ADR-0002 §3: 4 vCPU / 8 GB): Discovery d2-8 or General Purpose b3-16"
  type        = string
  default     = "d2-8"
}

variable "admin_user" {
  description = "Admin login created by cloud-init (keys only). OVH images also create 'ubuntu' with the keypair; cloud-init from infra/host disables password login for every user."
  type        = string
  default     = "admin"
}

variable "admin_ssh_public_key" {
  description = "Admin SSH public key (P7 laptop); registered as the Nova keypair and injected by cloud-init"
  type        = string
  validation {
    condition     = can(regex("^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH public key line."
  }
}

variable "cloud_init_edge_path" {
  description = "Rendered cloud-init for edge (infra/host/scripts/render-cloud-init.sh edge ...; PUBLIC_IF=ens3 on OVH)"
  type        = string
}

variable "cloud_init_core_path" {
  description = "Rendered cloud-init for core (infra/host/scripts/render-cloud-init.sh core ...; PUBLIC_IF=ens3 on OVH)"
  type        = string
}

variable "private_network_cidr" {
  description = "vRack private network between A and B: Keycloak/FastAPI and the Portainer Agent (ADR-0026)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "edge_private_ip" {
  description = "Private-network address of edge; x.1 is the SDN gateway on UpCloud and refused for servers"
  type        = string
  default     = "10.0.0.11"
}

variable "core_private_ip" {
  type    = string
  default = "10.0.0.2"
}

variable "private_network_vlan_id" {
  description = "vRack VLAN id for the private network (1–4000, unique within the vRack)"
  type        = number
  default     = 42
  validation {
    condition     = var.private_network_vlan_id >= 1 && var.private_network_vlan_id <= 4000
    error_message = "private_network_vlan_id must be between 1 and 4000."
  }
}

variable "public_network_name" {
  description = "Name of the provider's public network (OVH: Ext-Net)"
  type        = string
  default     = "Ext-Net"
}

variable "admin_ssh_cidrs" {
  description = "IPv4 CIDRs allowed to reach SSH (TCP 22) on both servers (ADR-0026). Default: anywhere, keys only; narrow to the admin's address. Keep in sync with ADMIN_SSH_CIDRS in the cloud-init vars"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.admin_ssh_cidrs) >= 1 && length(var.admin_ssh_cidrs) <= 5 && alltrue([for c in var.admin_ssh_cidrs : can(cidrnetmask(c))])
    error_message = "admin_ssh_cidrs must hold 1-5 IPv4 CIDRs (a.b.c.d/n)."
  }
}

variable "hostname_prefix" {
  description = "Prefix for server hostnames (<prefix>-edge, <prefix>-core)"
  type        = string
  default     = "webapptest"
}

variable "labels" {
  description = "Applied as instance metadata and as key:value tags on every resource"
  type        = map(string)
  default = {
    project = "web-app-test"
    env     = "poc"
    managed = "opentofu"
  }
}
