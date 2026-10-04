locals {
  api_hostname    = "${var.api_subdomain}.${var.domain}"
  health_hostname = "${var.health_subdomain}.${var.domain}"
  service_name    = "${var.environment}-quotes-app"
}

# --- Secrets ------------------------------------------------------------------

# DB password: generated in memory (ephemeral) and sent to Secret Manager
# through a write-only argument, so it is never stored in Terraform state.
# Bump db_password_version to write a new version (then rotate it in Postgres,
# see README).
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.environment}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret                 = google_secret_manager_secret.db_password.id
  secret_data_wo         = ephemeral.random_password.db.result
  secret_data_wo_version = var.db_password_version
}

# Origin header secret. Cloudflare has to be told the value, so unlike the DB
# password it does live in state (and in the Cloudflare ruleset).
resource "random_password" "origin_secret" {
  length  = 48
  special = false

  keepers = {
    version = var.origin_secret_version
  }
}

resource "google_secret_manager_secret" "origin_secret" {
  secret_id = "${var.environment}-cloudflare-origin-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "origin_secret" {
  secret                 = google_secret_manager_secret.origin_secret.id
  secret_data_wo         = random_password.origin_secret.result
  secret_data_wo_version = var.origin_secret_version
}

# --- Network + database ---------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  region      = var.region
  environment = var.environment
  subnet_cidr = var.subnet_cidr
}

module "database_vm" {
  source = "./modules/database-vm"

  project_id              = var.project_id
  region                  = var.region
  zone                    = var.zone
  environment             = var.environment
  machine_type            = var.vm_machine_type
  subnet_self_link        = module.networking.subnet_self_link
  network_tag             = module.networking.db_network_tag
  db_name                 = var.db_name
  db_user                 = var.db_user
  db_password_secret_id   = google_secret_manager_secret.db_password.id
  data_disk_size_gb       = var.db_disk_size_gb
  snapshot_retention_days = var.db_snapshot_retention_days
  deletion_protection     = var.deletion_protection

  # The VM reads the password on first boot
  depends_on = [google_secret_manager_secret_version.db_password]
}

# --- App ------------------------------------------------------------------------

module "artifact_registry" {
  source = "./modules/artifact-registry"

  region                   = var.region
  environment              = var.environment
  repository_name          = var.artifact_registry_repository
  deployer_service_account = var.deployer_service_account
}

module "cloud_run" {
  source = "./modules/cloud-run"

  region                   = var.region
  environment              = var.environment
  service_name             = local.service_name
  network_id               = module.networking.network_id
  subnet_id                = module.networking.subnet_id
  db_host                  = module.database_vm.internal_ip
  db_name                  = var.db_name
  db_user                  = var.db_user
  db_password_secret_id    = google_secret_manager_secret.db_password.id
  origin_secret_id         = google_secret_manager_secret.origin_secret.id
  min_instances            = var.cloud_run_min_instances
  max_instances            = var.cloud_run_max_instances
  cpu                      = var.cloud_run_cpu
  memory                   = var.cloud_run_memory
  concurrency              = var.cloud_run_concurrency
  request_timeout          = var.cloud_run_request_timeout
  deployer_service_account = var.deployer_service_account
  deletion_protection      = var.deletion_protection

  # Cloud Run resolves "latest" when a revision starts, so versions must exist
  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.origin_secret,
  ]
}

# --- Edge -----------------------------------------------------------------------

# Cloudflare's published edge ranges, used for the Cloud Armor allowlist
data "cloudflare_ip_ranges" "edge" {}

module "load_balancer" {
  source = "./modules/load-balancer"

  region                 = var.region
  environment            = var.environment
  cloud_run_service_name = module.cloud_run.service_name
  api_hostname           = local.api_hostname
  health_hostname        = local.health_hostname
  allowed_source_ranges  = concat(data.cloudflare_ip_ranges.edge.ipv4_cidrs, data.cloudflare_ip_ranges.edge.ipv6_cidrs)
}

module "cloudflare" {
  source = "./modules/cloudflare"

  domain                    = var.domain
  environment               = var.environment
  api_hostname              = local.api_hostname
  health_hostname           = local.health_hostname
  origin_ip                 = module.load_balancer.ip_address
  dns_authorization_records = module.load_balancer.dns_authorization_records
  origin_secret             = random_password.origin_secret.result
  allowed_countries         = var.allowed_countries
  rate_limit_requests       = var.rate_limit_requests
  rate_limit_period         = var.rate_limit_period
  enable_paid_waf           = var.cloudflare_paid_waf
  enable_bot_fight_mode     = var.cloudflare_bot_fight_mode
}

# --- Observability --------------------------------------------------------------

module "monitoring" {
  source = "./modules/monitoring"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  service_name        = module.cloud_run.service_name
  health_hostname     = local.health_hostname
  db_instance_name    = module.database_vm.instance_name
  db_zone             = var.zone
  notification_emails = var.alert_emails

  # The uptime check needs the DNS record
  depends_on = [module.cloudflare]
}
