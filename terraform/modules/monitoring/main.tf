locals {
  run_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.service_name}\""

  # Logs Explorer deep links for the alert documentation
  logs_url = {
    for name, query in {
      errors = "${local.run_filter}\nseverity>=ERROR"
      db     = "${local.run_filter}\njsonPayload.message=\"${var.db_failure_message}\""
      all    = local.run_filter
    } : name => "https://console.cloud.google.com/logs/query;query=${urlencode(query)}?project=${var.project_id}"
  }

  service_url = "https://console.cloud.google.com/run/detail/${var.region}/${var.service_name}/metrics?project=${var.project_id}"
}

resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.notification_emails)

  display_name = "${var.environment} alerts: ${each.key}"
  type         = "email"
  labels = {
    email_address = each.key
  }
}

locals {
  channels = [for c in google_monitoring_notification_channel.email : c.id]
}

# --- Uptime check on the DNS-only health hostname -----------------------------
# /health returns 200 only when the app can query Postgres, so this check
# covers "app down" and "database down".

resource "google_monitoring_uptime_check_config" "health" {
  display_name = "${var.environment} health (app + database)"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/health"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  content_matchers {
    content = "\"database\":\"connected\""
    matcher = "CONTAINS_STRING"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.health_hostname
    }
  }

  selected_regions = ["USA", "EUROPE", "ASIA_PACIFIC"]
}

# --- Log-based metrics --------------------------------------------------------

resource "google_logging_metric" "app_errors" {
  name        = "${var.environment}-app-error-logs"
  description = "ERROR (or worse) log entries from the Cloud Run service, incl. unhandled exceptions"
  filter      = "${local.run_filter} AND severity>=ERROR"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_logging_metric" "db_unreachable" {
  name        = "${var.environment}-db-unreachable"
  description = "Health checks that could not reach Postgres"
  filter      = "${local.run_filter} AND jsonPayload.message=\"${var.db_failure_message}\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# --- Alert policies -------------------------------------------------------------

resource "google_monitoring_alert_policy" "uptime" {
  display_name          = "${var.environment} - health check failing (app or database down)"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "Uptime check failing from 2+ regions"
    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.health.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "120s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  documentation {
    subject   = "[${var.environment}] health check failing"
    mime_type = "text/markdown"
    content   = <<-EOT
      https://${var.health_hostname}/health is failing from two or more regions.

      Runbook:
      1. `curl -sS https://${var.health_hostname}/health` - 503 with `"database":"disconnected"` means Postgres is down; see the database alert runbook.
      2. No response or 5xx from the load balancer: check the Cloud Run service (link below) for failed revisions or crash loops.
      3. 403: Cloud Armor rejected the check. Make sure the health hostname is DNS-only (gray cloud) in Cloudflare.
      4. If the last deploy is the cause, roll back: `gcloud run services update-traffic ${var.service_name} --region ${var.region} --to-revisions <previous>=100`.
    EOT
    links {
      display_name = "Cloud Run service"
      url          = local.service_url
    }
    links {
      display_name = "Service logs"
      url          = local.logs_url.all
    }
  }
}

resource "google_monitoring_alert_policy" "db_unreachable" {
  display_name          = "${var.environment} - app cannot reach Postgres"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "DB connection failures in health checks"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.db_unreachable.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    subject   = "[${var.environment}] app cannot reach Postgres"
    mime_type = "text/markdown"
    content   = <<-EOT
      Cloud Run health checks are failing to query Postgres.

      Runbook:
      1. Is the VM running? `gcloud compute instances describe ${var.db_instance_name} --zone ${var.db_zone} --format='value(status)'`
      2. Is the container up? `gcloud compute ssh ${var.db_instance_name} --zone ${var.db_zone} --tunnel-through-iap -- sudo docker ps -a`
      3. Container stopped: `sudo docker logs --tail 100 quotes-db`, then `sudo docker start quotes-db`. Disk full: `df -h /mnt/disks/pgdata`.
      4. VM lost or disk damaged: restore the latest snapshot of the data disk (daily schedule), attach it and re-run the startup script (`sudo google_metadata_script_runner startup`).
    EOT
    links {
      display_name = "DB failure logs"
      url          = local.logs_url.db
    }
  }
}

resource "google_monitoring_alert_policy" "app_errors" {
  display_name          = "${var.environment} - application errors logged"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "ERROR log entries > ${var.error_log_threshold} in 5 min"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.app_errors.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_log_threshold
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    subject   = "[${var.environment}] application errors"
    mime_type = "text/markdown"
    content   = <<-EOT
      The app logged more than ${var.error_log_threshold} ERROR entries in 5 minutes (unhandled exceptions, failed queries, 5xx responses).

      Runbook:
      1. Open the error logs (link below) and group by `jsonPayload.message`.
      2. Started right after a deploy? Roll back to the previous revision (see the health-check runbook).
      3. Database errors: follow the "app cannot reach Postgres" runbook.
    EOT
    links {
      display_name = "Error logs"
      url          = local.logs_url.errors
    }
  }
}

resource "google_monitoring_alert_policy" "error_rate" {
  display_name          = "${var.environment} - 5xx rate above ${var.error_rate_percent}%"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "5xx / all requests > ${var.error_rate_percent}% for 5 min"
    condition_threshold {
      filter             = "${local.run_filter} AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\""
      denominator_filter = "${local.run_filter} AND metric.type=\"run.googleapis.com/request_count\""
      comparison         = "COMPARISON_GT"
      threshold_value    = var.error_rate_percent / 100
      duration           = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      denominator_aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    subject   = "[${var.environment}] high 5xx rate"
    mime_type = "text/markdown"
    content   = "More than ${var.error_rate_percent}% of requests return 5xx. Follow the application-errors runbook; check the health endpoint first."
    links {
      display_name = "Error logs"
      url          = local.logs_url.errors
    }
  }
}

resource "google_monitoring_alert_policy" "latency" {
  display_name          = "${var.environment} - p95 latency above ${var.latency_threshold_ms} ms"
  combiner              = "OR"
  notification_channels = local.channels

  conditions {
    display_name = "p95 request latency > ${var.latency_threshold_ms} ms for 5 min"
    condition_threshold {
      filter          = "${local.run_filter} AND metric.type=\"run.googleapis.com/request_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.latency_threshold_ms
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  documentation {
    subject   = "[${var.environment}] slow responses"
    mime_type = "text/markdown"
    content   = "p95 latency is above ${var.latency_threshold_ms} ms. Usual causes: the e2-micro database VM is CPU-starved, or the instance count hit max_instances. Check the Cloud Run metrics and the VM CPU graph."
    links {
      display_name = "Cloud Run metrics"
      url          = local.service_url
    }
  }
}
