output "uptime_check_id" {
  description = "Uptime check ID"
  value       = google_monitoring_uptime_check_config.health_check.uptime_check_id
}

output "notification_channel_id" {
  description = "Email notification channel ID"
  value       = google_monitoring_notification_channel.email.id
}

output "alert_policy_ids" {
  description = "Alert policy IDs"
  value = {
    high_error_rate       = google_monitoring_alert_policy.high_error_rate.id
    high_latency          = google_monitoring_alert_policy.high_latency.id
    uptime_check_failure  = google_monitoring_alert_policy.uptime_check_failure.id
  }
}
