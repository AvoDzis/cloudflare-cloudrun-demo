# Data sources to retrieve Cloudflare zone and account info
data "cloudflare_zone" "domain" {
  name = var.domain
}

# DNS Record 1: Proxied (Orange Cloud) for main API
resource "cloudflare_record" "api" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "api"
  content = var.load_balancer_ip
  type    = "A"
  proxied = true
  ttl     = 1 # Auto when proxied
  comment = "Points to Load Balancer - Proxied through Cloudflare"
}

# DNS Record 2: Proxied (Orange Cloud) for health endpoint
resource "cloudflare_record" "health_api" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "health.api"
  content = var.load_balancer_ip
  type    = "A"
  proxied = true
  ttl     = 1 # Auto when proxied
  comment = "Points to Load Balancer - Proxied through Cloudflare"
}

# WAF Rule 1: Geo-Restriction (Allow only Spain and Armenia)
resource "cloudflare_ruleset" "geo_restriction" {
  zone_id     = data.cloudflare_zone.domain.id
  name        = "${var.environment}-geo-restriction"
  description = "Block all traffic except from Spain (ES) and Armenia (AM)"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "block"
    expression  = "(http.host eq \"api.${var.domain}\" and ip.geoip.country ne \"ES\" and ip.geoip.country ne \"AM\")"
    description = "Block traffic from countries other than ES and AM"
    enabled     = true
  }
}

# WAF Rule 2: Rate Limiting (100 requests per minute per IP)
resource "cloudflare_rate_limit" "api_rate_limit" {
  zone_id   = data.cloudflare_zone.domain.id
  threshold = 100
  period    = 60
  match {
    request {
      url_pattern = "api.${var.domain}/*"
    }
  }
  action {
    mode    = "block"
    timeout = 60
    response {
      content_type = "application/json"
      body         = jsonencode({ error = "Rate limit exceeded" })
    }
  }
  description = "Limit requests to 100 per minute per IP"
}

# WAF Rule 3: OWASP Core Ruleset for SQL Injection Protection
resource "cloudflare_ruleset" "owasp_protection" {
  zone_id     = data.cloudflare_zone.domain.id
  name        = "${var.environment}-owasp-protection"
  description = "Enable OWASP protection including SQL injection"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee" # Cloudflare OWASP Core Ruleset
    }
    expression  = "true"
    description = "Execute Cloudflare OWASP Core Ruleset"
    enabled     = true
  }
}

# WAF Rule 4: Bot Protection (Challenge bots with score < 30)
resource "cloudflare_ruleset" "bot_protection" {
  zone_id     = data.cloudflare_zone.domain.id
  name        = "${var.environment}-bot-protection"
  description = "Challenge requests with low bot score"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "managed_challenge"
    expression  = "(cf.bot_management.score lt 30)"
    description = "Challenge bots with score less than 30"
    enabled     = true
  }
}

# Cache Rule 1: Static Assets (1 hour cache)
resource "cloudflare_ruleset" "cache_static" {
  zone_id     = data.cloudflare_zone.domain.id
  name        = "${var.environment}-cache-static"
  description = "Cache static assets for 1 hour"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = true
      edge_ttl {
        mode    = "override_origin"
        default = 3600 # 1 hour
      }
      browser_ttl {
        mode    = "override_origin"
        default = 1800 # 30 minutes
      }
    }
    expression  = "(http.request.uri.path matches \"^/static/.*\")"
    description = "Cache static assets"
    enabled     = true
  }
}

# Cache Rule 2: API Responses (5 minutes cache, respect Cache-Control)
resource "cloudflare_ruleset" "cache_api" {
  zone_id     = data.cloudflare_zone.domain.id
  name        = "${var.environment}-cache-api"
  description = "Cache API responses for 5 minutes"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = true
      edge_ttl {
        mode    = "respect_origin"
        default = 300 # 5 minutes fallback
      }
    }
    expression  = "(http.request.uri.path starts_with \"/api/\")"
    description = "Cache API responses respecting origin Cache-Control"
    enabled     = true
  }
}

# Cache Rule 3: Health Endpoint (No cache)
resource "cloudflare_ruleset" "cache_health" {
  zone_id     = data.cloudflare_zone.domain.id
  name        = "${var.environment}-cache-health"
  description = "Bypass cache for health endpoint"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    action = "set_cache_settings"
    action_parameters {
      cache = false
    }
    expression  = "(http.request.uri.path eq \"/health\")"
    description = "Never cache health endpoint"
    enabled     = true
  }
}
