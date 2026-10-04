locals {
  data_device_name = "pgdata"
}

# --- Identity ---------------------------------------------------------------

resource "google_service_account" "vm" {
  account_id   = "${var.environment}-postgres-vm"
  display_name = "PostgreSQL VM (${var.environment})"
}

resource "google_project_iam_member" "vm" {
  for_each = toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"])

  project = var.project_id
  role    = each.key
  member  = google_service_account.vm.member
}

# Only this one secret, not project-wide access
resource "google_secret_manager_secret_iam_member" "db_password" {
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.vm.member
}

# --- Data disk + daily snapshots --------------------------------------------

resource "google_compute_disk" "data" {
  name = "${var.environment}-postgres-data"
  zone = var.zone
  type = "pd-standard"
  size = var.data_disk_size_gb

  labels = {
    environment = var.environment
    app         = "postgres"
  }
}

resource "google_compute_resource_policy" "snapshots" {
  name   = "${var.environment}-postgres-daily"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "03:00"
      }
    }

    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "snapshots" {
  name = google_compute_resource_policy.snapshots.name
  disk = google_compute_disk.data.name
  zone = var.zone
}

# --- VM ---------------------------------------------------------------------

resource "google_compute_instance" "postgres" {
  name         = "${var.environment}-postgres-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [var.network_tag]

  deletion_protection       = var.deletion_protection
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 10
      type  = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.data.id
    device_name = local.data_device_name
  }

  # No access_config block: the VM has no external IP
  network_interface {
    subnetwork = var.subnet_self_link
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"

    # In metadata (not metadata_startup_script) so edits update in place
    # instead of recreating the VM
    startup-script = templatefile("${path.module}/templates/startup.sh.tftpl", {
      db_name         = var.db_name
      db_user         = var.db_user
      password_secret = var.db_password_secret_id
      postgres_image  = var.postgres_image
      device_name     = local.data_device_name
    })
  }

  labels = {
    environment = var.environment
    app         = "postgres"
  }

  # The VM reads the secret at boot
  depends_on = [google_secret_manager_secret_iam_member.db_password]
}
