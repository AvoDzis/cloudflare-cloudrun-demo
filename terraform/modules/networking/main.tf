# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-cloud-run-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-cloud-run-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  # Enable Private Google Access for accessing Google APIs without external IP
  private_ip_google_access = true
}

# Firewall rule: Allow IAP tunneling for SSH access
resource "google_compute_firewall" "allow_iap" {
  name    = "${var.environment}-allow-iap-ssh"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range
  source_ranges = ["35.235.240.0/20"]

  target_tags = ["allow-iap-ssh"]

  description = "Allow SSH access via Identity-Aware Proxy"
}

# Firewall rule: Allow Cloud Run to PostgreSQL
resource "google_compute_firewall" "allow_cloud_run_to_db" {
  name    = "${var.environment}-allow-cloud-run-to-postgres"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Allow from entire subnet (Cloud Run will be in this subnet)
  source_ranges = [var.subnet_cidr]

  target_tags = ["postgres-server"]

  description = "Allow Cloud Run to connect to PostgreSQL"
}

# Firewall rule: Default deny all other ingress
# Note: Google Cloud has an implicit deny all rule, but we make it explicit
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.environment}-deny-all-ingress"
  network  = google_compute_network.vpc.name
  project  = var.project_id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  description = "Default deny all ingress traffic"
}
