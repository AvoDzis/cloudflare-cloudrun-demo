output "service_account_email" {
  description = "Cloud Run service account email"
  value       = google_service_account.cloud_run_sa.email
}

# output "vpc_connector_id" {
#   description = "VPC connector ID"
#   value       = google_vpc_access_connector.connector.id
# }

# output "vpc_connector_name" {
#   description = "VPC connector name"
#   value       = google_vpc_access_connector.connector.name
# }
