output "repository_id" {
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.repo.repository_id
}

output "repository_url" {
  description = "Docker repository URL (<region>-docker.pkg.dev/<project>/<repo>)"
  value       = google_artifact_registry_repository.repo.registry_uri
}
