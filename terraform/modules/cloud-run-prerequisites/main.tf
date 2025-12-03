# Service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.environment}-cloud-run-sa"
  display_name = "Service Account for Cloud Run"
  project      = var.project_id
}

# IAM roles for Cloud Run service account
resource "google_project_iam_member" "cloud_run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# VPC Connector for Direct VPC Egress
# resource "google_vpc_access_connector" "connector" {
#   name          = "${var.environment}-vpc-connector"
#   project       = var.project_id
#   region        = var.region
#   ip_cidr_range = var.vpc_connector_cidr
#   network       = var.network_name

#   # e2-micro equivalent for connector
#   machine_type  = "e2-micro"
#   min_instances = 2
#   max_instances = 3
# }
