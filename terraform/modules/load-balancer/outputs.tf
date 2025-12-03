output "load_balancer_ip" {
  description = "Load Balancer static IP address"
  value       = google_compute_address.lb_ip.address
}

output "ssl_certificate_id" {
  description = "SSL certificate ID"
  value       = google_compute_region_ssl_certificate.lb_cert.id
}

output "ssl_certificate_status" {
  description = "SSL certificate status"
  value       = google_compute_region_ssl_certificate.lb_cert.managed[0].status
}

output "backend_service_id" {
  description = "Backend service ID"
  value       = google_compute_region_backend_service.lb_backend.id
}

output "neg_id" {
  description = "Network Endpoint Group ID"
  value       = google_compute_region_network_endpoint_group.cloud_run_neg.id
}

output "forwarding_rule_id" {
  description = "Forwarding rule ID"
  value       = google_compute_forwarding_rule.lb_forwarding_rule.id
}
