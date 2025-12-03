output "vpc_network_name" {
  description = "VPC network name"
  value       = module.networking.network_name
}

output "vpc_subnet_name" {
  description = "VPC subnet name"
  value       = module.networking.subnet_name
}

output "vm_internal_ip" {
  description = "PostgreSQL VM internal IP address"
  value       = module.compute.vm_internal_ip
}

output "vm_instance_name" {
  description = "PostgreSQL VM instance name"
  value       = module.compute.vm_instance_name
}

output "cloud_run_service_account" {
  description = "Cloud Run service account email (use in Cloud Run YAML)"
  value       = module.cloud_run_prerequisites.service_account_email
}

# output "vpc_connector_id" {
#   description = "VPC connector ID (use in Cloud Run YAML)"
#   value       = module.cloud_run_prerequisites.vpc_connector_id
# }

output "artifact_registry_repository_url" {
  description = "Artifact Registry repository URL"
  value       = module.artifact_registry.repository_url
}

# output "load_balancer_ip" {
#   description = "Load Balancer static IP address"
#   value       = module.load_balancer.load_balancer_ip
# }

# output "ssl_certificate_status" {
#   description = "SSL certificate provisioning status"
#   value       = module.load_balancer.ssl_certificate_status
# }

# output "api_domain" {
#   description = "API domain URL"
#   value       = module.cloudflare.api_domain
# }

# output "health_api_domain" {
#   description = "Health API domain URL"
#   value       = module.cloudflare.health_api_domain
# }

output "db_connection_command" {
  description = "Command to connect to database via IAP tunnel"
  value       = "gcloud compute start-iap-tunnel ${module.compute.vm_instance_name} 5432 --local-host-port=localhost:5432 --zone=${var.zone} && psql -h localhost -p 5432 -U labuser -d ${var.db_name}"
}

output "secret_names" {
  description = "Secret Manager secret names"
  value = {
    db_password = google_secret_manager_secret.db_password.secret_id
  }
}

output "db_password" {
  description = "Database password (sensitive)"
  value       = random_password.db_password.result
  sensitive   = true
}
