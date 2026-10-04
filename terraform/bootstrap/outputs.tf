# Copy these into the GitHub repository variables (Settings > Secrets and variables > Actions > Variables)

output "state_bucket" {
  description = "TF_STATE_BUCKET"
  value       = google_storage_bucket.tf_state.name
}

output "workload_identity_provider" {
  description = "GCP_WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "plan_service_account" {
  description = "GCP_PLAN_SA"
  value       = google_service_account.tf_plan.email
}

output "apply_service_account" {
  description = "GCP_APPLY_SA"
  value       = google_service_account.tf_apply.email
}

output "deploy_service_account" {
  description = "GCP_DEPLOY_SA (also the main stack's deployer_service_account input)"
  value       = google_service_account.app_deploy.email
}

output "project_number" {
  description = "Project number, for reference"
  value       = data.google_project.this.number
}
