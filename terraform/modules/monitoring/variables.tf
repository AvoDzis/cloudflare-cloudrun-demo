variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
}

variable "health_endpoint_host" {
  description = "Health endpoint hostname (without https://)"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name"
  type        = string
}
