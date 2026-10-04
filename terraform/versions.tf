terraform {
  # 1.11+: write-only arguments (secret_data_wo) and ephemeral resources keep
  # the DB password out of plan and state files
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.5"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Bucket comes from terraform/bootstrap:
  #   terraform init -backend-config="bucket=<state bucket>"
  backend "gcs" {
    prefix = "main"
  }
}
