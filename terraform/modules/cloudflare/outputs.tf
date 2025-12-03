output "zone_id" {
  description = "Cloudflare Zone ID"
  value       = data.cloudflare_zone.domain.id
}

output "zone_name" {
  description = "Cloudflare Zone name"
  value       = data.cloudflare_zone.domain.name
}

output "api_domain" {
  description = "API domain (proxied through Cloudflare)"
  value       = "https://${cloudflare_record.api.hostname}"
}

output "health_api_domain" {
  description = "Health API domain (proxied through Cloudflare)"
  value       = "https://${cloudflare_record.health_api.hostname}"
}

output "api_record_id" {
  description = "API DNS record ID"
  value       = cloudflare_record.api.id
}

output "health_record_id" {
  description = "Health API DNS record ID"
  value       = cloudflare_record.health_api.id
}
