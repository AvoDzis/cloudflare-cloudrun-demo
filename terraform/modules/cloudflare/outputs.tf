output "zone_id" {
  description = "Cloudflare zone ID"
  value       = local.zone_id
}

output "api_url" {
  description = "Public app URL"
  value       = "https://${cloudflare_dns_record.api.name}"
}

output "health_url" {
  description = "Direct health URL"
  value       = "https://${cloudflare_dns_record.health.name}/health"
}
