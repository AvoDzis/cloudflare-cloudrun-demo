# --- Runtime identity: reads its two secrets, nothing else ------------------

resource "google_service_account" "runtime" {
  account_id   = "${var.environment}-cloud-run"
  display_name = "Cloud Run runtime (${var.environment})"
}

resource "google_secret_manager_secret_iam_member" "runtime" {
  for_each = {
    db_password   = var.db_password_secret_id
    origin_secret = var.origin_secret_id
  }

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.runtime.member
}

# --- Service ----------------------------------------------------------------

resource "google_cloud_run_v2_service" "app" {
  name     = var.service_name
  location = var.region

  # Reachable only through the external Application Load Balancer (and from
  # inside the VPC); the *.run.app URL refuses internet traffic.
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = var.deletion_protection

  template {
    service_account                  = google_service_account.runtime.email
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2"
    timeout                          = var.request_timeout
    max_instance_request_concurrency = var.concurrency

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Direct VPC egress (no Serverless VPC Access connector); only private
    # ranges go through the VPC, so the DB is reachable on its internal IP.
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnet_id
      }
    }

    containers {
      # Placeholder for the first apply. CD deploys real images with
      # `gcloud run deploy --image`, and Terraform ignores the field afterwards.
      image = var.initial_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = {
          DB_HOST     = var.db_host
          DB_PORT     = tostring(var.db_port)
          DB_NAME     = var.db_name
          DB_USER     = var.db_user
          ENVIRONMENT = var.environment
          LOG_LEVEL   = var.log_level
        }
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = var.db_password_secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "CLOUDFLARE_SECRET"
        value_source {
          secret_key_ref {
            secret  = var.origin_secret_id
            version = "latest"
          }
        }
      }

      # A new revision only takes traffic once it can reach the database
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        period_seconds    = 5
        timeout_seconds   = 3
        failure_threshold = 12
      }

      # Restarts a hung process; does not depend on the database
      liveness_probe {
        http_get {
          path = "/livez"
          port = 8080
        }
        period_seconds    = 30
        timeout_seconds   = 3
        failure_threshold = 3
      }
    }
  }

  lifecycle {
    # Owned by CD (deploy-app.yml), so plans stay clean after every deploy
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [google_secret_manager_secret_iam_member.runtime]
}

# Public website: the load balancer forwards anonymous requests. Ingress, Cloud
# Armor and the Cloudflare origin header limit who can actually reach it.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- CD identity: may roll out new revisions running as the runtime SA ------

resource "google_cloud_run_v2_service_iam_member" "deployer" {
  name     = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.developer"
  member   = "serviceAccount:${var.deployer_service_account}"
}

resource "google_service_account_iam_member" "deployer_acts_as_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deployer_service_account}"
}
