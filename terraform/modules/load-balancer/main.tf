# Global external Application Load Balancer in front of Cloud Run:
# Cloudflare -> static IP -> HTTPS proxy (Certificate Manager cert) ->
# backend service (Cloud Armor) -> serverless NEG -> Cloud Run

locals {
  hostnames = [var.api_hostname, var.health_hostname]

  # Cloud Armor allows at most 10 source ranges per rule
  source_range_chunks = chunklist(var.allowed_source_ranges, 10)

  # CEL: request is for one of our hostnames
  host_is_ours = join(" || ", [for h in local.hostnames : "request.headers['host'] == '${h}'"])
}

resource "google_compute_global_address" "lb" {
  name       = "${var.environment}-lb-ip"
  ip_version = "IPV4"
}

resource "google_compute_region_network_endpoint_group" "cloud_run" {
  name                  = "${var.environment}-cloud-run-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service_name
  }
}

# --- Cloud Armor: only Cloudflare may talk to the origin --------------------

resource "google_compute_security_policy" "edge_only" {
  name        = "${var.environment}-cloudflare-only"
  description = "Allow Cloudflare edge IPs and the direct health check; deny everything else"
  type        = "CLOUD_ARMOR"

  # Host-header guard: unknown hostnames (e.g. requests to the bare IP) are refused
  rule {
    action      = "deny(403)"
    priority    = 100
    description = "Unknown Host header"
    match {
      expr {
        expression = "!(${local.host_is_ours})"
      }
    }
  }

  # The DNS-only health hostname is called directly by uptime checks
  rule {
    action      = "allow"
    priority    = 200
    description = "Direct health check"
    match {
      expr {
        expression = "request.headers['host'] == '${var.health_hostname}' && request.path == '/health'"
      }
    }
  }

  dynamic "rule" {
    for_each = local.source_range_chunks
    content {
      action      = "allow"
      priority    = 1000 + rule.key
      description = "Cloudflare edge ranges (${rule.key + 1}/${length(local.source_range_chunks)})"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = rule.value
        }
      }
    }
  }

  rule {
    action      = "deny(403)"
    priority    = 2147483647
    description = "Default deny"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

resource "google_compute_backend_service" "app" {
  name                  = "${var.environment}-cloud-run-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"
  security_policy       = google_compute_security_policy.edge_only.id

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "app" {
  name            = "${var.environment}-url-map"
  default_service = google_compute_backend_service.app.id
}

# --- TLS: Google-managed certificate, validated through DNS -----------------
# DNS authorization works while Cloudflare proxies the hostname, because Google
# checks a CNAME record instead of fetching a token over HTTP.

resource "google_certificate_manager_dns_authorization" "this" {
  for_each = toset(local.hostnames)

  name   = "${var.environment}-${replace(each.key, ".", "-")}"
  domain = each.key
}

resource "google_certificate_manager_certificate" "app" {
  name = "${var.environment}-app-cert"

  managed {
    domains            = local.hostnames
    dns_authorizations = [for a in google_certificate_manager_dns_authorization.this : a.id]
  }
}

resource "google_certificate_manager_certificate_map" "app" {
  name = "${var.environment}-cert-map"
}

resource "google_certificate_manager_certificate_map_entry" "app" {
  name         = "${var.environment}-default"
  map          = google_certificate_manager_certificate_map.app.name
  certificates = [google_certificate_manager_certificate.app.id]
  matcher      = "PRIMARY"
}

resource "google_compute_ssl_policy" "modern" {
  name            = "${var.environment}-tls12-modern"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

resource "google_compute_target_https_proxy" "app" {
  name            = "${var.environment}-https-proxy"
  url_map         = google_compute_url_map.app.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.app.id}"
  ssl_policy      = google_compute_ssl_policy.modern.id
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${var.environment}-https"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  ip_address            = google_compute_global_address.lb.id
  target                = google_compute_target_https_proxy.app.id
}
