variable "region" {
  description = "Region of the Cloud Run service"
  type        = string
}

variable "environment" {
  description = "Environment name, used as a resource name prefix"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Cloud Run service behind the serverless NEG"
  type        = string
}

variable "api_hostname" {
  description = "Public hostname, proxied by Cloudflare (e.g. api.example.com)"
  type        = string
}

variable "health_hostname" {
  description = "DNS-only hostname used by uptime checks (e.g. health.api.example.com)"
  type        = string
}

variable "allowed_source_ranges" {
  description = "CIDRs allowed to reach the load balancer (Cloudflare's published ranges)"
  type        = list(string)

  validation {
    condition     = length(var.allowed_source_ranges) > 0
    error_message = "At least one source range is required, otherwise only the health check gets through."
  }
}
