output "ip_address" {
  description = "Load balancer IPv4 address (origin for the Cloudflare A records)"
  value       = google_compute_global_address.lb.address
}

output "dns_authorization_records" {
  description = "CNAME records Certificate Manager needs, keyed by hostname"
  value       = { for host, auth in google_certificate_manager_dns_authorization.this : host => auth.dns_resource_record[0] }
}

output "security_policy_name" {
  description = "Cloud Armor policy name"
  value       = google_compute_security_policy.edge_only.name
}

output "backend_service_name" {
  description = "Backend service name"
  value       = google_compute_backend_service.app.name
}
