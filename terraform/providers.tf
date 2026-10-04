provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    app         = "quotes-demo"
    environment = var.environment
    managed_by  = "terraform"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
