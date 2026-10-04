variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name, used as a resource name prefix"
  type        = string
}

variable "service_name" {
  description = "Cloud Run service name"
  type        = string
}

variable "initial_image" {
  description = "Image for the first deploy only; later images come from CD"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "network_id" {
  description = "VPC network for Direct VPC egress"
  type        = string
}

variable "subnet_id" {
  description = "Subnet for Direct VPC egress"
  type        = string
}

variable "db_host" {
  description = "Internal IP of the database VM"
  type        = string
}

variable "db_port" {
  description = "Postgres port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_user" {
  description = "PostgreSQL user"
  type        = string
}

variable "db_password_secret_id" {
  description = "Secret Manager secret with the DB password (projects/<p>/secrets/<name>)"
  type        = string
}

variable "origin_secret_id" {
  description = "Secret Manager secret with the X-Cloudflare-Secret value"
  type        = string
}

variable "log_level" {
  description = "App log level"
  type        = string
  default     = "info"
}

variable "min_instances" {
  description = "Minimum instances (1 avoids cold starts)"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum instances"
  type        = number
  default     = 10
}

variable "cpu" {
  description = "CPU limit per instance"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit per instance"
  type        = string
  default     = "512Mi"
}

variable "concurrency" {
  description = "Maximum concurrent requests per instance"
  type        = number
  default     = 80
}

variable "request_timeout" {
  description = "Request timeout (Cloud Run duration string)"
  type        = string
  default     = "30s"
}

variable "deployer_service_account" {
  description = "Email of the CD service account allowed to deploy new revisions"
  type        = string
}

variable "deletion_protection" {
  description = "Protect the service from terraform destroy"
  type        = bool
  default     = true
}
