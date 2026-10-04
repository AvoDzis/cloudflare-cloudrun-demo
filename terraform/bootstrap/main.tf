# One-time setup, applied locally by a project owner. Creates what CI needs
# before it can run the main stack: APIs, the state bucket, keyless GitHub
# authentication (Workload Identity Federation) and the CI service accounts.

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  apis = toset([
    "artifactregistry.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ])

  pool_name = google_iam_workload_identity_pool.github.name

  # Subject GitHub puts in the OIDC token of jobs that run in the environment
  environment_subject = "repo:${var.github_repository}:environment:${var.github_environment}"

  # Roles the apply identity needs to manage everything in ../ (main stack)
  apply_roles = toset([
    "roles/artifactregistry.admin",
    "roles/certificatemanager.owner",
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/logging.configWriter",
    "roles/monitoring.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/run.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageConsumer",
  ])

  # Read-only roles for plans on pull requests. Refreshing secret versions can
  # read their payloads, hence secretAccessor (see README, "Known trade-offs").
  plan_roles = toset([
    "roles/iam.securityReviewer",
    "roles/secretmanager.secretAccessor",
    "roles/viewer",
  ])
}

resource "google_project_service" "apis" {
  for_each = local.apis

  service            = each.key
  disable_on_destroy = false
}

# --- Terraform state ---------------------------------------------------------

resource "google_storage_bucket" "tf_state" {
  name     = var.state_bucket_name
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Keep the last 10 versions of each state file
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.apis]
}

# --- GitHub Actions authentication (no service-account keys) ----------------

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "OIDC tokens from GitHub Actions for ${var.github_repository}"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
    "attribute.event_name"    = "assertion.event_name"
  }

  # Only this repository, and only (a) jobs on the main branch that are not
  # pull_request events or (b) pull_request jobs that run outside any
  # environment. A PR job that asks for the prod environment gets a different
  # subject and is rejected here.
  attribute_condition = <<-EOT
    assertion.repository_id == "${var.github_repository_id}" && (
      (assertion.ref == "refs/heads/main" && assertion.event_name != "pull_request") ||
      assertion.sub == "repo:${var.github_repository}:pull_request"
    )
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- CI service accounts ----------------------------------------------------

resource "google_service_account" "tf_plan" {
  account_id   = "gh-terraform-plan"
  display_name = "GitHub Actions: terraform plan (read-only)"
}

resource "google_service_account" "tf_apply" {
  account_id   = "gh-terraform-apply"
  display_name = "GitHub Actions: terraform apply/destroy (environment ${var.github_environment})"
}

resource "google_service_account" "app_deploy" {
  account_id   = "gh-app-deploy"
  display_name = "GitHub Actions: push image + deploy Cloud Run (environment ${var.github_environment})"
  # Its permissions on the Artifact Registry repo, the Cloud Run service and the
  # runtime service account are granted by the main stack (deployer_service_account).
}

resource "google_project_iam_member" "tf_plan" {
  for_each = local.plan_roles

  project = var.project_id
  role    = each.key
  member  = google_service_account.tf_plan.member
}

resource "google_project_iam_member" "tf_apply" {
  for_each = local.apply_roles

  project = var.project_id
  role    = each.key
  member  = google_service_account.tf_apply.member
}

# Both Terraform identities read the state and write its lock file
resource "google_storage_bucket_iam_member" "state_users" {
  for_each = {
    plan  = google_service_account.tf_plan.member
    apply = google_service_account.tf_apply.member
  }

  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectUser"
  member = each.value
}

# Who may impersonate which service account
resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.repository_id/${var.github_repository_id}"
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool_name}/subject/${local.environment_subject}"
}

resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.app_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${local.pool_name}/subject/${local.environment_subject}"
}
