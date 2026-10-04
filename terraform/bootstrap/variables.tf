variable "project_id" {
  description = "GCP project that hosts the demo"
  type        = string
}

variable "region" {
  description = "Region for the state bucket"
  type        = string
  default     = "us-central1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate, as owner/name"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the owner/name form, e.g. octo-org/cloudflare-cloudrun-demo."
  }
}

variable "github_repository_id" {
  description = "Numeric GitHub repository ID (survives renames and transfers): gh api repos/OWNER/NAME --jq .id"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "The repository ID is a number."
  }
}

variable "github_environment" {
  description = "GitHub environment whose jobs may apply Terraform and deploy the app"
  type        = string
  default     = "prod"
}
