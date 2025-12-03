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

variable "repository_name" {
  description = "Artifact Registry repository name"
  type        = string
}

variable "cloud_run_service_account" {
  description = "Cloud Run service account email"
  type        = string
}
