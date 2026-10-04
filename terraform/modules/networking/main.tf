resource "google_compute_network" "vpc" {
  name                    = "${var.environment}-cloud-run-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Shared by the database VM and Cloud Run Direct VPC egress
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-cloud-run-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id

  # Reach Google APIs (Secret Manager, Artifact Registry) without public IPs
  private_ip_google_access = true
}

# IAP TCP forwarding: SSH and `gcloud compute start-iap-tunnel ... 5432`
resource "google_compute_firewall" "allow_iap" {
  name    = "${var.environment}-allow-iap"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", tostring(var.db_port)]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.db_network_tag]
  description   = "SSH and Postgres through Identity-Aware Proxy"
}

# Cloud Run instances get addresses from the subnet (Direct VPC egress)
resource "google_compute_firewall" "allow_subnet_to_db" {
  name    = "${var.environment}-allow-subnet-to-postgres"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.db_port)]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = [var.db_network_tag]
  description   = "Cloud Run (Direct VPC egress) to Postgres"
}

# GCP already denies ingress implicitly; an explicit rule makes it visible and logged
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.environment}-deny-all-ingress"
  network  = google_compute_network.vpc.name
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  description   = "Default deny all ingress traffic"

  log_config {
    metadata = "EXCLUDE_ALL_METADATA"
  }
}

# Outbound internet for the VM (apt packages, container image pulls).
# The VM has no external IP; Cloud Run egress stays private-ranges-only.
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
