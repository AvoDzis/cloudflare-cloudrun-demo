# Service account for Compute Engine VM
resource "google_service_account" "vm_sa" {
  account_id   = "${var.environment}-postgres-vm-sa"
  display_name = "Service Account for PostgreSQL VM"
  project      = var.project_id
}

# IAM roles for VM service account
resource "google_project_iam_member" "vm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

resource "google_project_iam_member" "vm_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Compute Engine instance for PostgreSQL
resource "google_compute_instance" "postgres_vm" {
  name         = "${var.environment}-postgres-vm"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  tags = ["postgres-server", "allow-iap-ssh"]

  boot_disk {
    initialize_params {
      # Use Container-Optimized OS or Ubuntu
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnet_self_link

    # No external IP - internal only
    # access_config block is intentionally omitted
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/files/startup-script.sh", {
    DB_NAME     = var.db_name
    DB_USER     = var.db_user
    DB_PASSWORD = var.db_password
  })

  # Allow stopping for updates
  allow_stopping_for_update = true

  labels = {
    environment = var.environment
    app         = "postgres"
  }
}
