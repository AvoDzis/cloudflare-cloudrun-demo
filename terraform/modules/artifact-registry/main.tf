# Artifact Registry repository
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.repository_name
  description   = "Docker repository for ${var.environment} environment"
  format        = "DOCKER"
  project       = var.project_id

  labels = {
    environment = var.environment
  }
}

# IAM: Allow Cloud Run service account to pull images
resource "google_artifact_registry_repository_iam_member" "cloud_run_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.cloud_run_service_account}"
}
