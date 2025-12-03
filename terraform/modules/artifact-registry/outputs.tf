output "repository_id" {
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.repo.repository_id
}

output "repository_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
}

output "repository_location" {
  description = "Artifact Registry repository location"
  value       = google_artifact_registry_repository.repo.location
}
