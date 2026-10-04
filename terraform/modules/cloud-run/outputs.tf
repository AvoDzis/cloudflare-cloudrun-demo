output "service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.app.name
}

output "service_uri" {
  description = "Default *.run.app URL (internal + load balancer ingress only)"
  value       = google_cloud_run_v2_service.app.uri
}

output "ingress" {
  description = "Ingress setting"
  value       = google_cloud_run_v2_service.app.ingress
}

output "runtime_service_account" {
  description = "Runtime service account email"
  value       = google_service_account.runtime.email
}
