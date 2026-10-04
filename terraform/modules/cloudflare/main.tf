data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

locals {
  zone_id = data.cloudflare_zone.this.zone_id

  # Rules language set literal, e.g. {"ES" "AM"}
  allowed_countries = join(" ", [for c in var.allowed_countries : "\"${c}\""])

  scanner_user_agents = ["sqlmap", "nikto", "nmap", "masscan", "zgrab", "nuclei", "wpscan", "dirbuster", "gobuster", "acunetix", "netsparker"]
  scanner_expression  = join(" or ", [for ua in local.scanner_user_agents : "lower(http.user_agent) contains \"${ua}\""])

  # Probes for files and apps this site doesn't have
  probe_path_expression = join(" or ", [
    "starts_with(http.request.uri.path, \"/.env\")",
    "starts_with(http.request.uri.path, \"/.git\")",
    "starts_with(http.request.uri.path, \"/wp-\")",
    "http.request.uri.path contains \"phpmyadmin\"",
  ])

  on_api_host = "http.host eq \"${var.api_hostname}\""
}

# --- DNS ----------------------------------------------------------------------

# Proxied (orange cloud): all user traffic goes through Cloudflare's WAF and cache
resource "cloudflare_dns_record" "api" {
  zone_id = local.zone_id
  name    = var.api_hostname
  type    = "A"
  content = var.origin_ip
  proxied = true
  ttl     = 1 # "automatic"; required for proxied records
  comment = "Global external ALB (${var.environment})"
}

# DNS-only (gray cloud): uptime checks reach the origin directly, so a
# Cloudflare outage and an origin outage can be told apart
resource "cloudflare_dns_record" "health" {
  zone_id = local.zone_id
  name    = var.health_hostname
  type    = "A"
  content = var.origin_ip
  proxied = false
  ttl     = 300
  comment = "Direct health endpoint (${var.environment})"
}

# Certificate Manager DNS authorization (must not be proxied)
resource "cloudflare_dns_record" "cert_validation" {
  for_each = var.dns_authorization_records

  zone_id = local.zone_id
  name    = trimsuffix(each.value.name, ".")
  type    = each.value.type
  content = trimsuffix(each.value.data, ".")
  proxied = false
  ttl     = 300
  comment = "Google Certificate Manager DNS authorization for ${each.key}"
}

# --- Zone TLS settings (apply to the whole zone) -------------------------------

resource "cloudflare_zone_setting" "this" {
  for_each = {
    ssl              = "strict" # Full (strict): Cloudflare verifies the origin certificate
    always_use_https = "on"
    min_tls_version  = "1.2"
  }

  zone_id    = local.zone_id
  setting_id = each.key
  value      = each.value
}

# --- WAF custom rules (one entry-point ruleset per phase) --------------------

resource "cloudflare_ruleset" "firewall_custom" {
  zone_id     = local.zone_id
  name        = "${var.environment} custom firewall rules"
  description = "Scanner blocks and geo restriction"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = concat([
    {
      ref         = "block_scanners"
      description = "Block known vulnerability-scanner user agents and empty user agents"
      expression  = "(${local.scanner_expression}) or http.user_agent eq \"\""
      action      = "block"
    },
    {
      ref         = "block_probe_paths"
      description = "Block probes for files and apps this site does not have"
      expression  = "(${local.probe_path_expression})"
      action      = "block"
    },
    {
      ref         = "geo_restriction"
      description = "Allow ${join(", ", var.allowed_countries)} only"
      expression  = "(${local.on_api_host} and not ip.src.country in {${local.allowed_countries}})"
      action      = "block"
    },
    ], var.bot_score_threshold == null ? [] : [
    {
      ref         = "challenge_bots"
      description = "Challenge likely bots (needs Cloudflare Bot Management)"
      expression  = "(${local.on_api_host} and cf.bot_management.score lt ${var.bot_score_threshold} and not cf.bot_management.verified_bot)"
      action      = "managed_challenge"
    },
  ])
}

# Free plan limits: one rule, IP-based, 10-second period and timeout
resource "cloudflare_ruleset" "rate_limit" {
  zone_id     = local.zone_id
  name        = "${var.environment} rate limiting"
  description = "Per-IP rate limit on the API hostname"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "per_ip_limit"
      description = "${var.rate_limit_requests} requests per ${var.rate_limit_period}s per IP"
      expression  = "(${local.on_api_host})"
      action      = "block"
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = var.rate_limit_period
        requests_per_period = var.rate_limit_requests
        mitigation_timeout  = var.rate_limit_mitigation_timeout
      }
    },
  ]
}

# Paid plans (Pro and up): Cloudflare Managed Ruleset + OWASP Core Ruleset
resource "cloudflare_ruleset" "managed_waf" {
  count = var.enable_paid_waf ? 1 : 0

  zone_id     = local.zone_id
  name        = "${var.environment} managed WAF"
  description = "Cloudflare Managed Ruleset and OWASP Core Ruleset"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules = [
    {
      ref               = "cloudflare_managed"
      description       = "Cloudflare Managed Ruleset"
      expression        = "true"
      action            = "execute"
      action_parameters = { id = "efb7b8c949ac4650a09736fc376e9aee" }
    },
    {
      ref               = "owasp_core"
      description       = "Cloudflare OWASP Core Ruleset"
      expression        = "true"
      action            = "execute"
      action_parameters = { id = "4814384a9e5d4991b9815dcfc25d2f1f" }
    },
  ]
}

# Bot Fight Mode is the Free-plan bot protection. Off by default: it can
# challenge API clients such as curl.
resource "cloudflare_bot_management" "this" {
  count = var.enable_bot_fight_mode ? 1 : 0

  zone_id    = local.zone_id
  fight_mode = true
}

# --- Cache rules --------------------------------------------------------------

resource "cloudflare_ruleset" "cache" {
  zone_id     = local.zone_id
  name        = "${var.environment} cache rules"
  description = "Static: 1h at the edge, API: origin Cache-Control, health: never"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "cache_static"
      description = "Static assets: 1h at the edge, 30m in browsers"
      expression  = "(${local.on_api_host} and starts_with(http.request.uri.path, \"/static/\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache       = true
        edge_ttl    = { mode = "override_origin", default = 3600 }
        browser_ttl = { mode = "override_origin", default = 1800 }
      }
    },
    {
      ref         = "cache_api"
      description = "API: cache, honouring the origin's Cache-Control (300s)"
      expression  = "(${local.on_api_host} and starts_with(http.request.uri.path, \"/api/\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache    = true
        edge_ttl = { mode = "respect_origin" }
      }
    },
    {
      ref               = "bypass_health"
      description       = "Never cache health endpoints"
      expression        = "(http.request.uri.path in {\"/health\" \"/livez\"})"
      action            = "set_cache_settings"
      action_parameters = { cache = false }
    },
  ]
}

# --- Origin authentication header --------------------------------------------
# Cloudflare adds a secret header to every proxied API request; the app (and
# nothing else) knows the value, so requests that bypass this zone get 403.

resource "cloudflare_ruleset" "origin_header" {
  zone_id     = local.zone_id
  name        = "${var.environment} origin header"
  description = "Add the origin authentication header"
  kind        = "zone"
  phase       = "http_request_late_transform"

  rules = [
    {
      ref         = "set_origin_secret"
      description = "Set X-Cloudflare-Secret for the origin"
      expression  = "(${local.on_api_host})"
      action      = "rewrite"
      action_parameters = {
        headers = {
          "X-Cloudflare-Secret" = {
            operation = "set"
            value     = var.origin_secret
          }
        }
      }
    },
  ]
}
