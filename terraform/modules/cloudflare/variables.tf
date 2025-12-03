variable "domain" {
  description = "Root domain name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "load_balancer_ip" {
  description = "Load Balancer static IP address"
  type        = string
}
