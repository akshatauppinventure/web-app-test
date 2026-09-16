terraform {
  required_version = ">= 1.12.0"
  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "5.44.1"
    }
  }
}
