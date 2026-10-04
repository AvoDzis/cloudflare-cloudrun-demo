terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.5"
    }
  }

  # The state bucket is created by this stack, so the first apply uses local
  # state (see backend_override.tf.example) and is migrated here afterwards:
  #   terraform init -migrate-state -backend-config="bucket=<state bucket>"
  backend "gcs" {
    prefix = "bootstrap"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
