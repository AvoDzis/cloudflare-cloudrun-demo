variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name, used as a resource name prefix"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR range (VM + Cloud Run Direct VPC egress addresses)"
  type        = string
}

variable "db_port" {
  description = "Postgres port opened to the subnet and IAP"
  type        = number
  default     = 5432
}

variable "db_network_tag" {
  description = "Network tag that marks the database VM"
  type        = string
  default     = "postgres-server"
}
