output "vm_instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.postgres_vm.name
}

output "vm_internal_ip" {
  description = "VM internal IP address"
  value       = google_compute_instance.postgres_vm.network_interface[0].network_ip
}

output "vm_zone" {
  description = "VM zone"
  value       = google_compute_instance.postgres_vm.zone
}

output "vm_self_link" {
  description = "VM self link"
  value       = google_compute_instance.postgres_vm.self_link
}

output "service_account_email" {
  description = "VM service account email"
  value       = google_service_account.vm_sa.email
}
