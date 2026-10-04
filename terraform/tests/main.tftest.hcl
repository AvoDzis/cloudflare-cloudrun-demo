# Offline tests: `terraform test` from terraform/. Providers are mocked, so no
# credentials are needed and nothing is created. They check the wiring and the
# security-relevant settings, not GCP/Cloudflare API behaviour.

mock_provider "google" {
  mock_resource "google_certificate_manager_dns_authorization" {
    defaults = {
      dns_resource_record = [{
        name = "_acme-challenge.api.example.com."
        type = "CNAME"
        data = "0123abcd.4.authorize.certificatemanager.goog."
      }]
    }
  }

  mock_resource "google_compute_global_address" {
    defaults = {
      address = "203.0.113.10"
    }
  }

  # Computed IDs that other resources validate, so random mock strings won't do
  mock_resource "google_service_account" {
    defaults = {
      email  = "mock-sa@test-project.iam.gserviceaccount.com"
      member = "serviceAccount:mock-sa@test-project.iam.gserviceaccount.com"
      name   = "projects/test-project/serviceAccounts/mock-sa@test-project.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_secret_manager_secret" {
    defaults = {
      id = "projects/test-project/secrets/mock-secret"
    }
  }
}

mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = {
      zone_id = "023e105f4ecef8ad9ca31a8372d0c353"
    }
  }

  # 15 IPv4 + 7 IPv6 ranges, like Cloudflare's published list
  mock_data "cloudflare_ip_ranges" {
    defaults = {
      ipv4_cidrs = ["198.51.0.0/24", "198.51.1.0/24", "198.51.2.0/24", "198.51.3.0/24", "198.51.4.0/24", "198.51.5.0/24", "198.51.6.0/24", "198.51.7.0/24", "198.51.8.0/24", "198.51.9.0/24", "198.51.10.0/24", "198.51.11.0/24", "198.51.12.0/24", "198.51.13.0/24", "198.51.14.0/24"]
      ipv6_cidrs = ["2001:db8:0::/48", "2001:db8:1::/48", "2001:db8:2::/48", "2001:db8:3::/48", "2001:db8:4::/48", "2001:db8:5::/48", "2001:db8:6::/48"]
    }
  }
}

variables {
  project_id               = "test-project"
  domain                   = "example.com"
  alert_emails             = ["alerts@example.com"]
  deployer_service_account = "gh-app-deploy@test-project.iam.gserviceaccount.com"
  cloudflare_api_token     = "test-token"
}

run "whole_stack" {
  command = apply

  assert {
    condition     = module.cloud_run.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    error_message = "Cloud Run must only accept traffic from the load balancer / VPC."
  }

  assert {
    condition     = google_secret_manager_secret_version.db_password.secret_data == null
    error_message = "The DB password must be written through secret_data_wo, never stored in state."
  }

  assert {
    condition     = google_secret_manager_secret_version.origin_secret.secret_data == null
    error_message = "The origin secret version must use secret_data_wo."
  }

  assert {
    condition     = output.app_url == "https://api.example.com"
    error_message = "App URL should be the proxied api hostname."
  }

  assert {
    condition     = output.health_url == "https://health.api.example.com/health"
    error_message = "Health URL should be the DNS-only hostname."
  }
}

run "cloud_run_module" {
  command = apply

  module {
    source = "./modules/cloud-run"
  }

  providers = {
    google = google
  }

  variables {
    region                = "us-central1"
    environment           = "prod"
    service_name          = "prod-quotes-app"
    network_id            = "projects/test-project/global/networks/prod-cloud-run-vpc"
    subnet_id             = "projects/test-project/regions/us-central1/subnetworks/prod-cloud-run-subnet"
    db_host               = "10.0.1.2"
    db_name               = "labdb"
    db_user               = "labuser"
    db_password_secret_id = "projects/test-project/secrets/prod-db-password"
    origin_secret_id      = "projects/test-project/secrets/prod-cloudflare-origin-secret"
  }

  assert {
    condition     = google_cloud_run_v2_service.app.template[0].scaling[0].min_instance_count == 1
    error_message = "One warm instance by default."
  }

  assert {
    condition     = google_cloud_run_v2_service.app.template[0].timeout == "30s"
    error_message = "Request timeout should be explicit."
  }

  assert {
    condition     = google_cloud_run_v2_service.app.template[0].vpc_access[0].egress == "PRIVATE_RANGES_ONLY"
    error_message = "Only private ranges should go through the VPC."
  }

  assert {
    condition     = google_cloud_run_v2_service.app.template[0].containers[0].startup_probe[0].http_get[0].path == "/health"
    error_message = "Startup probe should gate on database connectivity."
  }

  assert {
    condition     = google_cloud_run_v2_service.app.template[0].containers[0].liveness_probe[0].http_get[0].path == "/livez"
    error_message = "Liveness must not depend on the database."
  }

  assert {
    condition = alltrue([
      for e in google_cloud_run_v2_service.app.template[0].containers[0].env :
      length(e.value_source) == 1 if contains(["DB_PASSWORD", "CLOUDFLARE_SECRET"], e.name)
    ])
    error_message = "Secrets must come from Secret Manager, not plain env values."
  }

  assert {
    condition     = google_cloud_run_v2_service.app.deletion_protection
    error_message = "Deletion protection is on by default."
  }
}

run "load_balancer_module" {
  command = apply

  module {
    source = "./modules/load-balancer"
  }

  providers = {
    google = google
  }

  variables {
    region                 = "us-central1"
    environment            = "prod"
    cloud_run_service_name = "prod-quotes-app"
    api_hostname           = "api.example.com"
    health_hostname        = "health.api.example.com"
    allowed_source_ranges  = [for i in range(22) : "198.51.${i}.0/24"]
  }

  assert {
    # host guard + health exception + ceil(22 / 10) allow rules + default deny
    condition     = length(google_compute_security_policy.edge_only.rule) == 6
    error_message = "Expected 6 Cloud Armor rules."
  }

  assert {
    condition = anytrue([
      for r in google_compute_security_policy.edge_only.rule :
      r.priority == 2147483647 && r.action == "deny(403)"
    ])
    error_message = "The default rule must deny."
  }

  assert {
    condition = alltrue([
      for r in google_compute_security_policy.edge_only.rule :
      length(r.match[0].config) == 0 || length(r.match[0].config[0].src_ip_ranges) <= 10
    ])
    error_message = "Cloud Armor allows at most 10 ranges per rule."
  }

  assert {
    condition     = google_compute_global_forwarding_rule.https.port_range == "443"
    error_message = "HTTPS only."
  }

  assert {
    condition     = google_compute_ssl_policy.modern.min_tls_version == "TLS_1_2"
    error_message = "TLS 1.2 minimum."
  }
}

run "cloudflare_module" {
  command = apply

  module {
    source = "./modules/cloudflare"
  }

  providers = {
    cloudflare = cloudflare
  }

  variables {
    environment     = "prod"
    api_hostname    = "api.example.com"
    health_hostname = "health.api.example.com"
    origin_ip       = "203.0.113.10"
    origin_secret   = "test-origin-secret"
    dns_authorization_records = {
      "api.example.com" = {
        name = "_acme-challenge.api.example.com."
        type = "CNAME"
        data = "0123abcd.4.authorize.certificatemanager.goog."
      }
    }
  }

  assert {
    condition     = cloudflare_dns_record.api.proxied && !cloudflare_dns_record.health.proxied
    error_message = "api is proxied (orange), health is DNS-only (gray)."
  }

  assert {
    condition     = !cloudflare_dns_record.cert_validation["api.example.com"].proxied && cloudflare_dns_record.cert_validation["api.example.com"].content == "0123abcd.4.authorize.certificatemanager.goog"
    error_message = "Certificate validation CNAME must be DNS-only, without the trailing dot."
  }

  assert {
    condition     = cloudflare_zone_setting.this["ssl"].value == "strict"
    error_message = "Cloudflare must verify the origin certificate (Full strict)."
  }

  assert {
    condition     = strcontains(cloudflare_ruleset.firewall_custom.rules[2].expression, "not ip.src.country in {\"ES\" \"AM\"}")
    error_message = "Geo rule should allow only ES and AM."
  }

  assert {
    condition     = cloudflare_ruleset.rate_limit.rules[0].ratelimit.period == 10
    error_message = "Default rate-limit period must fit the Free plan."
  }

  assert {
    condition     = length(cloudflare_ruleset.managed_waf) == 0 && length(cloudflare_bot_management.this) == 0
    error_message = "Paid-plan features are off by default."
  }

  assert {
    condition     = length(cloudflare_ruleset.cache.rules) == 3
    error_message = "One cache-settings ruleset with three rules."
  }
}

run "cloudflare_rejects_bad_country_codes" {
  command = plan

  module {
    source = "./modules/cloudflare"
  }

  providers = {
    cloudflare = cloudflare
  }

  variables {
    environment               = "prod"
    api_hostname              = "api.example.com"
    health_hostname           = "health.api.example.com"
    origin_ip                 = "203.0.113.10"
    origin_secret             = "test-origin-secret"
    dns_authorization_records = {}
    allowed_countries         = ["Spain"]
  }

  expect_failures = [var.allowed_countries]
}

run "database_vm_module" {
  command = apply

  module {
    source = "./modules/database-vm"
  }

  providers = {
    google = google
  }

  variables {
    project_id            = "test-project"
    region                = "us-central1"
    zone                  = "us-central1-a"
    environment           = "prod"
    subnet_self_link      = "projects/test-project/regions/us-central1/subnetworks/prod-cloud-run-subnet"
    network_tag           = "postgres-server"
    db_name               = "labdb"
    db_user               = "labuser"
    db_password_secret_id = "projects/test-project/secrets/prod-db-password"
  }

  assert {
    condition     = length(google_compute_instance.postgres.network_interface[0].access_config) == 0
    error_message = "The database VM must not have an external IP."
  }

  assert {
    condition     = google_compute_instance.postgres.shielded_instance_config[0].enable_secure_boot
    error_message = "Shielded VM secure boot should be on."
  }

  assert {
    condition = (
      strcontains(google_compute_instance.postgres.metadata["startup-script"], "PASSWORD_SECRET=\"projects/test-project/secrets/prod-db-password\"") &&
      strcontains(google_compute_instance.postgres.metadata["startup-script"], "https://secretmanager.googleapis.com/v1/$PASSWORD_SECRET/versions/latest:access")
    )
    error_message = "The startup script should read the password from Secret Manager."
  }

  assert {
    condition     = google_compute_resource_policy.snapshots.snapshot_schedule_policy[0].retention_policy[0].on_source_disk_delete == "KEEP_AUTO_SNAPSHOTS"
    error_message = "Snapshots must survive deleting the disk."
  }
}
