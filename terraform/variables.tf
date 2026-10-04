# --- Project ------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the database VM"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name, used as a resource name prefix"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,10}$", var.environment))
    error_message = "Lowercase letters, digits and dashes, at most 11 characters."
  }
}

variable "deletion_protection" {
  description = "Protect the Cloud Run service and the database VM from deletion (the destroy workflow turns it off first)"
  type        = bool
  default     = true
}

# --- Domain / Cloudflare -------------------------------------------------------

variable "domain" {
  description = "Cloudflare zone, e.g. example.com"
  type        = string
}

variable "api_subdomain" {
  description = "Proxied hostname label for the app"
  type        = string
  default     = "api"
}

variable "health_subdomain" {
  description = "DNS-only hostname label for health checks"
  type        = string
  default     = "health.api"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (set TF_VAR_cloudflare_api_token; see README for the permissions)"
  type        = string
  sensitive   = true
}

variable "allowed_countries" {
  description = "Countries allowed on the app hostname"
  type        = list(string)
  default     = ["ES", "AM"]
}

variable "rate_limit_requests" {
  description = "Requests per period per IP before Cloudflare blocks"
  type        = number
  default     = 20
}

variable "rate_limit_period" {
  description = "Rate-limit period in seconds (10 on the Free plan)"
  type        = number
  default     = 10
}

variable "cloudflare_paid_waf" {
  description = "Deploy Cloudflare's Managed + OWASP rulesets (needs Pro or higher)"
  type        = bool
  default     = false
}

variable "cloudflare_bot_fight_mode" {
  description = "Turn on Bot Fight Mode"
  type        = bool
  default     = false
}

# --- Network / database --------------------------------------------------------

variable "subnet_cidr" {
  description = "Subnet for the VM and Cloud Run Direct VPC egress"
  type        = string
  default     = "10.0.1.0/24"
}

variable "vm_machine_type" {
  description = "Database VM machine type"
  type        = string
  default     = "e2-micro"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "labdb"
}

variable "db_user" {
  description = "PostgreSQL user"
  type        = string
  default     = "labuser"
}

variable "db_password_version" {
  description = "Increment to generate and store a new DB password"
  type        = number
  default     = 1
}

variable "db_disk_size_gb" {
  description = "Postgres data disk size"
  type        = number
  default     = 10
}

variable "db_snapshot_retention_days" {
  description = "Days to keep daily data-disk snapshots"
  type        = number
  default     = 7
}

# --- Cloud Run ------------------------------------------------------------------

variable "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "lab-repo"
}

variable "deployer_service_account" {
  description = "CD service account email (bootstrap output deploy_service_account)"
  type        = string
}

variable "origin_secret_version" {
  description = "Increment to rotate the X-Cloudflare-Secret value"
  type        = number
  default     = 1
}

variable "cloud_run_min_instances" {
  description = "Minimum Cloud Run instances"
  type        = number
  default     = 1
}

variable "cloud_run_max_instances" {
  description = "Maximum Cloud Run instances"
  type        = number
  default     = 10
}

variable "cloud_run_cpu" {
  description = "CPU per instance"
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Memory per instance"
  type        = string
  default     = "512Mi"
}

variable "cloud_run_concurrency" {
  description = "Concurrent requests per instance"
  type        = number
  default     = 80
}

variable "cloud_run_request_timeout" {
  description = "Request timeout"
  type        = string
  default     = "30s"
}

# --- Monitoring -----------------------------------------------------------------

variable "alert_emails" {
  description = "Email addresses for alert notifications"
  type        = list(string)
}
