output "app_url" {
  description = "Public URL (through Cloudflare)"
  value       = module.cloudflare.api_url
}

output "health_url" {
  description = "Direct health URL (DNS-only)"
  value       = module.cloudflare.health_url
}

output "load_balancer_ip" {
  description = "Load balancer IPv4 address"
  value       = module.load_balancer.ip_address
}

output "cloud_run_service" {
  description = "Cloud Run service name (deploy-app.yml deploys to it)"
  value       = module.cloud_run.service_name
}

output "artifact_registry_repository_url" {
  description = "Docker repository for app images"
  value       = module.artifact_registry.repository_url
}

output "database_vm" {
  description = "Database VM name"
  value       = module.database_vm.instance_name
}

output "db_tunnel_command" {
  description = "Forward Postgres to localhost:5432 through IAP"
  value       = "gcloud compute start-iap-tunnel ${module.database_vm.instance_name} 5432 --local-host-port=localhost:5432 --zone=${var.zone}"
}

output "db_password_command" {
  description = "Print the DB password (needs secretAccessor)"
  value       = "gcloud secrets versions access latest --secret=${google_secret_manager_secret.db_password.secret_id}"
}
