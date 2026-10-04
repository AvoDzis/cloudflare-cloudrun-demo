# Terraform

The root module creates the GCP side of the demo. The Cloud Run service itself is deployed by Skaffold (`../skaffold.yaml`), not by Terraform. See the [main README](../README.md) for the full deploy steps and what was actually applied.

## Modules

| Module | Creates | Status |
|--------|---------|--------|
| `networking` | Custom VPC, subnet (Private Google Access), firewall: IAP → 22, subnet → 5432, deny-all | applied |
| `compute` | e2-micro Ubuntu 22.04 VM, no external IP, OS Login, own SA (log + metric writer) | applied (the startup script doesn't start Postgres, see main README) |
| `cloud-run-prerequisites` | Cloud Run SA with secretAccessor, logWriter, metricWriter | applied |
| `artifact-registry` | Docker repo + reader binding for the Cloud Run SA | applied |
| `load-balancer` | Regional external HTTPS LB, serverless NEG, static IP, cert | draft, fails `terraform validate` |
| `cloudflare` | DNS records, WAF, rate limit, cache rules | draft, fails `terraform validate` |
| `monitoring` | Uptime check, 5xx / p95 latency / uptime alert policies | draft, never applied |

The root module also enables the needed APIs and generates the DB password (`random_password`), which it stores in Secret Manager as `<environment>-db-password`.

## Inputs

These are required. Copy `terraform.tfvars.example` to `prod.tfvars` (git-ignored) and fill them in:

| Variable | Notes |
|----------|-------|
| `project_id` | GCP project |
| `domain` | Cloudflare zone (stage 2 only) |
| `alert_email` | Alert notification email (stage 2 only) |
| `cloudflare_api_token` | Set as `TF_VAR_cloudflare_api_token`. It's required by the provider block but only used in stage 2 |

Everything else has a default (region `us-central1`, `10.0.0.0/16` / `10.0.1.0/24`, `labdb` / `labuser`, `e2-micro`).

## Commands

```bash
terraform init -backend-config="bucket=<your-state-bucket>"   # GCS backend, prefix terraform/state
terraform plan  -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars

terraform output vm_internal_ip            # goes into resources/prod/service.prod.yaml
terraform output db_connection_command     # IAP tunnel + psql
gcloud secrets versions access latest --secret=prod-db-password

terraform destroy -var-file=prod.tfvars
```

To try stage 2, uncomment the three modules at the bottom of `main.tf` and the matching outputs in `outputs.tf`. Fix the validation errors listed in the main README first.
