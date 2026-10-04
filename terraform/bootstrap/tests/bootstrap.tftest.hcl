# Offline tests for the bootstrap stack (mocked provider, plan only: the state
# bucket has prevent_destroy, so nothing is "applied" even against mocks).

mock_provider "google" {
  override_during = plan

  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }

  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/123456789012/locations/global/workloadIdentityPools/github"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      email  = "mock-sa@test-project.iam.gserviceaccount.com"
      member = "serviceAccount:mock-sa@test-project.iam.gserviceaccount.com"
      name   = "projects/test-project/serviceAccounts/mock-sa@test-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id           = "test-project"
  state_bucket_name    = "test-project-tfstate"
  github_repository    = "octo-org/cloudflare-cloudrun-demo"
  github_repository_id = "123456"
}

run "bootstrap" {
  command = plan

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "assertion.repository_id == \"123456\"")
    error_message = "Tokens must be limited to this repository (by numeric ID)."
  }

  assert {
    condition     = strcontains(google_iam_workload_identity_pool_provider.github.attribute_condition, "assertion.ref == \"refs/heads/main\"")
    error_message = "Non-PR tokens must come from main."
  }

  assert {
    condition     = google_service_account_iam_member.apply_wif.member == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github/subject/repo:octo-org/cloudflare-cloudrun-demo:environment:prod"
    error_message = "Only jobs in the prod environment may impersonate the apply service account."
  }

  assert {
    condition     = google_service_account_iam_member.plan_wif.member == "principalSet://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github/attribute.repository_id/123456"
    error_message = "Plan identity is for the whole repository (incl. pull requests)."
  }

  assert {
    condition     = alltrue([for role in keys(google_project_iam_member.tf_plan) : !strcontains(role, "admin")])
    error_message = "The plan identity must not get admin roles."
  }

  assert {
    condition     = google_storage_bucket.tf_state.public_access_prevention == "enforced" && google_storage_bucket.tf_state.versioning[0].enabled
    error_message = "State bucket must be private and versioned."
  }
}

run "rejects_malformed_repository" {
  command = plan

  variables {
    github_repository = "not a repo"
  }

  expect_failures = [var.github_repository]
}
