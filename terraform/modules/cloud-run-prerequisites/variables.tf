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

variable "network_name" {
  description = "VPC network name"
  type        = string
}

# variable "vpc_connector_cidr" {
#   description = "CIDR range for VPC connector"
#   type        = string
#   default     = "10.8.0.0/28"
# }
