# Notification Channel for Email
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.environment} Email Notification"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
  enabled = true
}

# Uptime Check for Health Endpoint (Gray Cloud - Direct)
resource "google_monitoring_uptime_check_config" "health_check" {
  project      = var.project_id
  display_name = "${var.environment}-health-check"
  timeout      = "10s"
  period       = "60s" # Check every 1 minute

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

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.health_endpoint_host
    }
  }

  # Monitor from multiple regions
  selected_regions = [
    "USA",
    "EUROPE",
    "ASIA_PACIFIC"
  ]
}

# Alert Policy 1: High Error Rate (5xx > 5%)
resource "google_monitoring_alert_policy" "high_error_rate" {
  project      = var.project_id
  display_name = "${var.environment} - High 5xx Error Rate"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "5xx error rate > 5%"

    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.cloud_run_service_name}\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\""
      duration        = "300s" # 5 minutes
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05 # 5%

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.service_name"]
      }

      # Calculate error rate as a fraction
      denominator_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.cloud_run_service_name}\" AND metric.type=\"run.googleapis.com/request_count\""

      denominator_aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.service_name"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "5xx error rate has exceeded 5% for more than 5 minutes. Check Cloud Run logs and application health."
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s" # Auto-close after 30 minutes
  }
}

# Alert Policy 2: High Latency (p95 > 1000ms)
resource "google_monitoring_alert_policy" "high_latency" {
  project      = var.project_id
  display_name = "${var.environment} - High p95 Latency"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "p95 latency > 1000ms"

    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.cloud_run_service_name}\" AND metric.type=\"run.googleapis.com/request_latencies\""
      duration        = "300s" # 5 minutes
      comparison      = "COMPARISON_GT"
      threshold_value = 1000 # 1000ms

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_95"
        group_by_fields      = ["resource.service_name"]
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "p95 request latency has exceeded 1000ms for more than 5 minutes. Check database connections and Cloud Run performance metrics."
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s" # Auto-close after 30 minutes
  }
}

# Alert Policy 3: Uptime Check Failure
resource "google_monitoring_alert_policy" "uptime_check_failure" {
  project      = var.project_id
  display_name = "${var.environment} - Health Check Failure"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Health endpoint is down"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.health_check.uptime_check_id}\""
      duration        = "180s" # 3 minutes
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content   = "Health check endpoint is failing. Service may be down or unreachable."
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "1800s"
  }
}
