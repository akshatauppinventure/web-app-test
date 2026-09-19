variable "zone" {
  description = "UpCloud zone (ADR-0002)"
  type        = string
  default     = "us-nyc1"
}

variable "template_name" {
  description = "Public OS template name (ADR-0004); fallback 'Ubuntu Server 24.04 LTS (Noble Numbat)'"
  type        = string
  default     = "Ubuntu Server 26.04 LTS (Resolute Raccoon)"
}

variable "edge_plan" {
  description = "Plan for VPS-A edge (ADR-0002 §3: 2 vCPU / 4 GB)"
  type        = string
  default     = "2xCPU-4GB"
}

variable "core_plan" {
  description = "Plan for VPS-B core (ADR-0002 §3: 4 vCPU / 8 GB)"
  type        = string
  default     = "4xCPU-8GB"
}

variable "disk_size_gb" {
  description = "OS disk size in GB for both servers"
  type        = number
  default     = 40
}

variable "admin_user" {
  description = "Admin login created by cloud-init and UpCloud metadata (keys only)"
  type        = string
  default     = "admin"
}

variable "admin_ssh_public_key" {
  description = "Admin SSH public key (P7 laptop); injected via UpCloud login block and cloud-init"
  type        = string
  validation {
    condition     = can(regex("^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH public key line."
  }
}

variable "cloud_init_edge_path" {
  description = "Rendered cloud-init for edge (infra/host/scripts/render-cloud-init.sh edge ...)"
  type        = string
}

variable "cloud_init_core_path" {
  description = "Rendered cloud-init for core (infra/host/scripts/render-cloud-init.sh core ...)"
  type        = string
}

variable "private_network_cidr" {
  description = "SDN private network between A and B: Keycloak/FastAPI and the Portainer Agent (ADR-0026)"
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

variable "admin_ssh_cidrs" {
  description = "IPv4 CIDRs allowed to reach SSH (TCP 22) on both servers (ADR-0026). Default: anywhere, keys only; narrow to the admin's address. Keep in sync with ADMIN_SSH_CIDRS in the cloud-init vars"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.admin_ssh_cidrs) >= 1 && length(var.admin_ssh_cidrs) <= 5 && alltrue([for c in var.admin_ssh_cidrs : can(cidrnetmask(c))])
    error_message = "admin_ssh_cidrs must hold 1-5 IPv4 CIDRs (a.b.c.d/n)."
  }
}

variable "manage_provider_firewall" {
  description = "Create the per-server firewall rulesets (ADR-0014 layer 1). false on a trial account: its firewall is fixed (TRIAL_FIREWALL) and cannot be modified"
  type        = bool
  default     = true
}

variable "hostname_prefix" {
  description = "Prefix for server hostnames (<prefix>-edge, <prefix>-core)"
  type        = string
  default     = "webapptest"
}

variable "labels" {
  description = "Labels applied to every resource"
  type        = map(string)
  default = {
    project = "web-app-test"
    env     = "poc"
    managed = "opentofu"
  }
}
