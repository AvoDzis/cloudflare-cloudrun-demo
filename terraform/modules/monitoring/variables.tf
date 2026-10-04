variable "project_id" {
  description = "GCP project ID (uptime check resource, console links)"
  type        = string
}

variable "region" {
  description = "Region of the Cloud Run service (console links)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_name" {
  description = "Cloud Run service name"
  type        = string
}

variable "health_hostname" {
  description = "DNS-only hostname that serves /health"
  type        = string
}

variable "db_instance_name" {
  description = "Database VM name (runbook commands)"
  type        = string
}

variable "db_zone" {
  description = "Database VM zone (runbook commands)"
  type        = string
}

variable "notification_emails" {
  description = "Email addresses that receive alerts"
  type        = list(string)

  validation {
    condition     = length(var.notification_emails) > 0 && alltrue([for e in var.notification_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Give at least one valid email address."
  }
}

variable "db_failure_message" {
  description = "Log message the app writes when /health cannot reach the database"
  type        = string
  default     = "Health check failed - database connection error"
}

variable "error_log_threshold" {
  description = "ERROR log entries per 5 minutes that trigger an alert"
  type        = number
  default     = 5
}

variable "error_rate_percent" {
  description = "Percentage of 5xx responses that triggers an alert"
  type        = number
  default     = 5
}

variable "latency_threshold_ms" {
  description = "p95 latency (ms) that triggers an alert"
  type        = number
  default     = 1000
}
