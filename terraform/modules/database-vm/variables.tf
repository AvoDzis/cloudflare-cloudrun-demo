variable "project_id" {
  description = "GCP project ID (for project-level IAM)"
  type        = string
}

variable "region" {
  description = "GCP region (snapshot schedule)"
  type        = string
}

variable "zone" {
  description = "GCP zone for the VM and its data disk"
  type        = string
}

variable "environment" {
  description = "Environment name, used as a resource name prefix"
  type        = string
}

variable "machine_type" {
  description = "VM machine type"
  type        = string
  default     = "e2-micro"
}

variable "subnet_self_link" {
  description = "Subnet for the VM's only (internal) network interface"
  type        = string
}

variable "network_tag" {
  description = "Network tag the firewall rules target"
  type        = string
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
  description = "Secret Manager secret holding the DB password, as projects/<project>/secrets/<name>"
  type        = string
}

variable "postgres_image" {
  description = "Postgres container image"
  type        = string
  default     = "postgres:16-alpine"
}

variable "data_disk_size_gb" {
  description = "Size of the Postgres data disk"
  type        = number
  default     = 10
}

variable "snapshot_retention_days" {
  description = "How long daily data-disk snapshots are kept"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Protect the VM from deletion"
  type        = bool
  default     = true
}
