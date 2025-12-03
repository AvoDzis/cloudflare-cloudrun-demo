# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "iamcredentials.googleapis.com",
  ])

  project = var.project_id
  service = each.key

  disable_on_destroy = false
}

# Generate random database password
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Secret Manager: Database Password
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.environment}-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  subnet_cidr = var.subnet_cidr

  depends_on = [google_project_service.required_apis]
}

# Compute Module (PostgreSQL VM)
module "compute" {
  source = "./modules/compute"

  project_id         = var.project_id
  zone               = var.zone
  environment        = var.environment
  machine_type       = var.vm_machine_type
  network_self_link  = module.networking.network_self_link
  subnet_self_link   = module.networking.subnet_self_link
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = random_password.db_password.result

  depends_on = [module.networking]
}

# Cloud Run Prerequisites (Service Account, VPC Connector, IAM)
# Actual Cloud Run service will be deployed via Skaffold
module "cloud_run_prerequisites" {
  source = "./modules/cloud-run-prerequisites"

  project_id    = var.project_id
  region        = var.region
  environment   = var.environment
  network_name  = module.networking.network_name

  depends_on = [module.networking]
}

# Artifact Registry Module
module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id                 = var.project_id
  region                     = var.region
  environment                = var.environment
  repository_name            = var.artifact_registry_repository
  cloud_run_service_account  = module.cloud_run_prerequisites.service_account_email

  depends_on = [google_project_service.required_apis]
}

# Load Balancer Module
# Note: Deploy this AFTER Cloud Run service is deployed via Skaffold
# Uncomment this module after running: skaffold run -p prod
# module "load_balancer" {
#   source = "./modules/load-balancer"

#   project_id              = var.project_id
#   region                  = var.region
#   environment             = var.environment
#   domain                  = var.domain
#   cloud_run_service_name  = var.cloud_run_service_name

#   depends_on = [module.cloud_run_prerequisites]
# }

# # Cloudflare Module
# # Configures DNS, WAF, and cache rules
# module "cloudflare" {
#   source = "./modules/cloudflare"

#   domain            = var.domain
#   environment       = var.environment
#   load_balancer_ip  = module.load_balancer.load_balancer_ip

#   depends_on = [module.load_balancer]
# }

# # Monitoring Module
# module "monitoring" {
#   source = "./modules/monitoring"

#   project_id             = var.project_id
#   environment            = var.environment
#   alert_email            = var.alert_email
#   health_endpoint_host   = "health.api.${var.domain}"
#   cloud_run_service_name = var.cloud_run_service_name

#   depends_on = [module.cloudflare]
# }
