resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.repository_name
  description   = "App images for the ${var.environment} environment"
  format        = "DOCKER"

  # CD tags images with the commit SHA; a tag can never be moved to other bytes
  docker_config {
    immutable_tags = true
  }

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_recent_images
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "${var.delete_after_days * 86400}s"
    }
  }

  labels = {
    environment = var.environment
  }
}

# CD pushes images here
resource "google_artifact_registry_repository_iam_member" "deployer" {
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.deployer_service_account}"
}
