# OVHcloud Public Cloud is OpenStack, so the module needs only the OpenStack provider (ADR-0025).
# Credentials come only from the environment (ADR-0016 §4): source the project's openrc file (P15),
# which sets OS_AUTH_URL (https://auth.cloud.ovh.us/v3 for OVHcloud US), OS_IDENTITY_API_VERSION=3,
# OS_USER_DOMAIN_NAME=Default, OS_PROJECT_DOMAIN_NAME=Default, OS_TENANT_ID, OS_USERNAME, OS_PASSWORD,
# OS_REGION_NAME — or OS_APPLICATION_CREDENTIAL_ID / OS_APPLICATION_CREDENTIAL_SECRET for a service
# account. Nothing is read from files or variables.
provider "openstack" {
  region      = var.zone
  max_retries = 4
}
