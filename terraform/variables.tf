variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "test-project-402414"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "domain" {
  description = "Root domain name"
  type        = string
  default     = "avodzis.online"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "you@example.com"
}

# Network configuration
variable "vpc_cidr" {
  description = "VPC CIDR range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
  default     = "10.0.1.0/24"
}

# Database configuration
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "labdb"
}

variable "db_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "labuser"
}

# Compute configuration
variable "vm_machine_type" {
  description = "VM machine type"
  type        = string
  default     = "e2-micro"
}

# Cloud Run configuration
variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 1
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "cloud_run_cpu" {
  description = "Cloud Run CPU allocation"
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Cloud Run memory allocation"
  type        = string
  default     = "512Mi"
}

variable "cloud_run_concurrency" {
  description = "Cloud Run concurrency limit"
  type        = number
  default     = 80
}

# Artifact Registry
variable "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "lab-repo"
}

# Cloud Run Service Name (deployed via Skaffold)
variable "cloud_run_service_name" {
  description = "Cloud Run service name (must match service deployed by Skaffold)"
  type        = string
  default     = "prod-lab-app"
}
