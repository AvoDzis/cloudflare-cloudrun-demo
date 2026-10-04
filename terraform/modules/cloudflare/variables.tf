variable "domain" {
  description = "Cloudflare zone name, e.g. example.com"
  type        = string
}

variable "environment" {
  description = "Environment name, used in rule names"
  type        = string
}

variable "api_hostname" {
  description = "Proxied hostname for the app"
  type        = string
}

variable "health_hostname" {
  description = "DNS-only hostname for direct health checks"
  type        = string
}

variable "origin_ip" {
  description = "Load balancer IPv4 address"
  type        = string
}

variable "dns_authorization_records" {
  description = "Certificate Manager DNS authorization records, keyed by hostname"
  type = map(object({
    name = string
    type = string
    data = string
  }))
}

variable "origin_secret" {
  description = "Value Cloudflare sends in X-Cloudflare-Secret"
  type        = string
  sensitive   = true
}

variable "allowed_countries" {
  description = "ISO country codes allowed on the API hostname"
  type        = list(string)
  default     = ["ES", "AM"]

  validation {
    condition     = alltrue([for c in var.allowed_countries : can(regex("^[A-Z]{2}$", c))])
    error_message = "Use two-letter uppercase ISO 3166-1 codes."
  }
}

variable "rate_limit_requests" {
  description = "Requests allowed per period per IP"
  type        = number
  default     = 20
}

variable "rate_limit_period" {
  description = "Rate-limit counting period in seconds (Free plan: 10 only)"
  type        = number
  default     = 10
}

variable "rate_limit_mitigation_timeout" {
  description = "How long an IP stays blocked, in seconds (Free plan: 10 only)"
  type        = number
  default     = 10
}

variable "enable_paid_waf" {
  description = "Deploy the Cloudflare Managed + OWASP Core rulesets (Pro plan or higher)"
  type        = bool
  default     = false
}

variable "enable_bot_fight_mode" {
  description = "Turn on Bot Fight Mode (Free plan bot protection)"
  type        = bool
  default     = false
}

variable "bot_score_threshold" {
  description = "Challenge requests with a bot score below this (Enterprise Bot Management only); null disables the rule"
  type        = number
  default     = null
}
