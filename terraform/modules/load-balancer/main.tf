# Reserve Static Regional IP Address for Load Balancer
resource "google_compute_address" "lb_ip" {
  name         = "${var.environment}-lb-ip"
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  description  = "Static IP for Regional Load Balancer"
}

# Google-Managed SSL Certificate
resource "google_compute_region_ssl_certificate" "lb_cert" {
  name_prefix = "${var.environment}-lb-cert-"
  project     = var.project_id
  region      = var.region

  managed {
    domains = [
      "api.${var.domain}",
      "health.api.${var.domain}"
    ]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Serverless Network Endpoint Group (NEG) for Cloud Run
resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  name                  = "${var.environment}-cloud-run-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = var.cloud_run_service_name
  }
}

# Backend Service
resource "google_compute_region_backend_service" "lb_backend" {
  name                  = "${var.environment}-lb-backend"
  project               = var.project_id
  region                = var.region
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30

  backend {
    group           = google_compute_region_network_endpoint_group.cloud_run_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# URL Map
resource "google_compute_region_url_map" "lb_url_map" {
  name            = "${var.environment}-lb-url-map"
  project         = var.project_id
  region          = var.region
  default_service = google_compute_region_backend_service.lb_backend.id

  host_rule {
    hosts        = ["api.${var.domain}"]
    path_matcher = "allpaths"
  }

  host_rule {
    hosts        = ["health.api.${var.domain}"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_region_backend_service.lb_backend.id

    path_rule {
      paths   = ["/*"]
      service = google_compute_region_backend_service.lb_backend.id
    }
  }
}

# Target HTTPS Proxy
resource "google_compute_region_target_https_proxy" "lb_https_proxy" {
  name             = "${var.environment}-lb-https-proxy"
  project          = var.project_id
  region           = var.region
  url_map          = google_compute_region_url_map.lb_url_map.id
  ssl_certificates = [google_compute_region_ssl_certificate.lb_cert.id]
}

# Forwarding Rule (Regional External Load Balancer)
resource "google_compute_forwarding_rule" "lb_forwarding_rule" {
  name                  = "${var.environment}-lb-forwarding-rule"
  project               = var.project_id
  region                = var.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_region_target_https_proxy.lb_https_proxy.id
  ip_address            = google_compute_address.lb_ip.id
  network_tier          = "PREMIUM"
}
