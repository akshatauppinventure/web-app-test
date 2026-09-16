# Credentials come only from the environment (ADR-0016 §4): UPCLOUD_TOKEN (API token, P6) or
# UPCLOUD_USERNAME/UPCLOUD_PASSWORD. Nothing is read from files or variables.
provider "upcloud" {
  request_timeout_sec = 120
  retry_max           = 4
}
