output "uptime_check_id" {
  description = "Uptime check ID"
  value       = google_monitoring_uptime_check_config.health.uptime_check_id
}

output "alert_policy_ids" {
  description = "Alert policy IDs"
  value = {
    uptime         = google_monitoring_alert_policy.uptime.id
    db_unreachable = google_monitoring_alert_policy.db_unreachable.id
    app_errors     = google_monitoring_alert_policy.app_errors.id
    error_rate     = google_monitoring_alert_policy.error_rate.id
    latency        = google_monitoring_alert_policy.latency.id
  }
}
