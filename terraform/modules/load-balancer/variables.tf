variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "domain" {
  description = "Root domain name"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name (must be deployed before this module)"
  type        = string
}
