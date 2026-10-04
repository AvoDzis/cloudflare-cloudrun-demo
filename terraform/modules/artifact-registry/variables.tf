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

variable "deployer_service_account" {
  description = "Email of the CD service account that pushes images"
  type        = string
}

variable "keep_recent_images" {
  description = "Always keep this many most recent image versions"
  type        = number
  default     = 10
}

variable "delete_after_days" {
  description = "Delete image versions older than this (except the kept recent ones)"
  type        = number
  default     = 30
}
