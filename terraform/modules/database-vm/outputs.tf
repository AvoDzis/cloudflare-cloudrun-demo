output "internal_ip" {
  description = "VM internal IP address (DB_HOST for Cloud Run)"
  value       = google_compute_instance.postgres.network_interface[0].network_ip
}

output "instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.postgres.name
}

output "zone" {
  description = "VM zone"
  value       = google_compute_instance.postgres.zone
}

output "service_account_email" {
  description = "VM service account"
  value       = google_service_account.vm.email
}
