# Cloud Run + Cloudflare demo

A GCP lab from December 2025: a small Node.js "quote of the moment" app runs on Cloud Run and reads from PostgreSQL on a private VM over Direct VPC egress. The infrastructure is Terraform, and Skaffold + Cloud Build handle deploys. An edge layer (regional HTTPS load balancer + Cloudflare DNS/WAF/cache + Cloud Monitoring) is drafted but was never applied.

The original brief is in [LAB_REQUIREMENTS.md](LAB_REQUIREMENTS.md). Not everything in it was built. The status section below says exactly what was.

## Status

**Stage 1: applied.** Terraform created these in a personal GCP project:

- a custom VPC + subnet with Private Google Access, and firewall rules (IAP SSH, Postgres only from the subnet, explicit deny-all)
- an e2-micro Ubuntu VM with no external IP and OS Login
- dedicated service accounts for the VM and Cloud Run
- an Artifact Registry repo
- a generated DB password in Secret Manager

The app was built with Cloud Build and deployed to Cloud Run with `skaffold run -p prod`.

- **Postgres is not automated any more.** Since the "compute engine script" commit (3 Dec 2025), the VM startup script only installs Docker and tries to mount a data disk (`google-postgres-data`) that Terraform never attaches, so it stops at that step. The earlier version of the script ran the Postgres container and created the `quotes` table. Ansible was planned for this but never written. On a fresh `terraform apply`, you start Postgres on the VM yourself (see [Deploy](#deploy-stage-1)).

**Stage 2: draft, never applied.** The `load_balancer`, `cloudflare` and `monitoring` modules are commented out in `terraform/main.tf`. With them enabled, `terraform validate` fails on three errors:

1. `google_compute_region_ssl_certificate` has no `managed` block. A Google-managed cert for a regional load balancer needs Certificate Manager instead.
2. `modules/cloudflare` doesn't declare `cloudflare/cloudflare` in `required_providers`, so Terraform looks for a non-existent `hashicorp/cloudflare`.
3. `cloudflare_rate_limit` uses `mode = "block"`, which isn't an allowed value. The resource is also deprecated in favour of a `cloudflare_ruleset` rate-limit rule.

Other known gaps in the draft:

- The Cloud Run service uses ingress `internal`. To sit behind an external load balancer it needs `internal-and-cloud-load-balancing`.
- Cloudflare allows one zone ruleset per phase, but the module defines two custom-firewall and three cache-settings rulesets.
- The bot-score rule needs Cloudflare Bot Management, and the OWASP managed ruleset needs a paid plan.
- The app does not implement the `X-Cloudflare-Secret` header check from the brief.

## Architecture (as designed)

```
Users (ES + AM only)
   │
Cloudflare: DNS, WAF, cache rules            ┐
   │                                          │ stage 2 (draft)
Regional external HTTPS load balancer         │
   │  serverless NEG                          ┘
Cloud Run "prod-lab-app" (gen2, min 1 instance, internal ingress)
   │  Direct VPC egress, private ranges only
VPC 10.0.0.0/16 → subnet 10.0.1.0/24
   │  tcp/5432 from the subnet only
e2-micro VM, no external IP, Postgres in Docker (access via IAP)
```

## Repository layout

| Path | What it is |
|------|------------|
| `app/` | Express app, Dockerfile (multi-stage, non-root, `HEALTHCHECK`) |
| `resources/prod/service.prod.yaml` | Cloud Run (Knative) service manifest used by Skaffold |
| `skaffold.yaml` | Build with Cloud Build, deploy the manifest to Cloud Run |
| `terraform/` | Root module + modules: `networking`, `compute`, `cloud-run-prerequisites`, `artifact-registry` (stage 1), and `load-balancer`, `cloudflare`, `monitoring` (stage 2 draft). See [terraform/README.md](terraform/README.md) |
| `.github/workflows/` | PR validation and a manual deploy workflow. See [.github/README.md](.github/README.md) |
| `LAB_REQUIREMENTS.md` | The original brief |

## The app

| Endpoint | Returns | Cache-Control |
|----------|---------|---------------|
| `GET /` | HTML page with a random quote from Postgres | `public, max-age=300` |
| `GET /api/quote` | the same quote as JSON | `public, max-age=300` |
| `GET /health` | `{"status": ...}`, checks the DB; 503 if the DB is down | `no-cache` |
| `GET /static/*` | CSS/JS | `public, max-age=3600` |

The app logs in JSON with a `severity` field that Cloud Logging understands (pino + pino-http). It uses a `pg` connection pool (max 10), closes the pool on SIGTERM, and reads all DB settings from environment variables (see [`app/.env.example`](app/.env.example)).

### Run locally

```bash
docker run -d --name quotes-db -p 5432:5432 \
  -e POSTGRES_DB=labdb -e POSTGRES_USER=labuser -e POSTGRES_PASSWORD=change-me \
  postgres:16-alpine
sleep 5   # give Postgres a moment to start
docker exec -i quotes-db psql -U labuser -d labdb <<'SQL'
CREATE TABLE quotes (
  id SERIAL PRIMARY KEY,
  quote TEXT NOT NULL,
  author VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO quotes (quote, author) VALUES
  ('In the middle of difficulty lies opportunity.', 'Albert Einstein');
SQL

cd app
cp .env.example .env
npm ci
node --env-file=.env server.js   # http://localhost:8080
```

## Deploy (stage 1)

You need a GCP project, `gcloud`, Terraform >= 1.6 and Skaffold.

```bash
export PROJECT_ID=your-project-id
export STATE_BUCKET=your-terraform-state-bucket

# 1. Terraform state bucket
gsutil mb -p $PROJECT_ID gs://$STATE_BUCKET
gsutil versioning set on gs://$STATE_BUCKET

# 2. Infrastructure
cd terraform
cp terraform.tfvars.example prod.tfvars                 # edit project_id, domain, alert_email
export TF_VAR_cloudflare_api_token=unused-in-stage-1    # required variable; only stage 2 uses it
terraform init -backend-config="bucket=$STATE_BUCKET"
terraform apply -var-file=prod.tfvars
cd ..

# 3. Put your project ID and the VM's IP into the manifests
sed -i.bak "s/YOUR_PROJECT_ID/$PROJECT_ID/g" skaffold.yaml resources/prod/service.prod.yaml
sed -i.bak "s/REPLACE_WITH_VM_INTERNAL_IP/$(terraform -chdir=terraform output -raw vm_internal_ip)/" \
  resources/prod/service.prod.yaml

# 4. Start Postgres on the VM (not automated, see Status)
gcloud compute ssh prod-postgres-vm --zone=us-central1-a --tunnel-through-iap
#   on the VM: docker run postgres with POSTGRES_DB=labdb, POSTGRES_USER=labuser and the password from
#   `gcloud secrets versions access latest --secret=prod-db-password`, publish 5432, allow 10.0.0.0/16
#   in pg_hba.conf, then create the quotes table as in "Run locally".

# 5. Build and deploy the app
skaffold run -p prod
```

The Cloud Run service has internal ingress, so its `*.run.app` URL is not reachable from the internet. That's on purpose. To reach the database from your laptop, open an IAP tunnel: `terraform -chdir=terraform output db_connection_command`.

**Clean up:**

```bash
gcloud run services delete prod-lab-app --region=us-central1   # Skaffold-managed, not in Terraform state
terraform -chdir=terraform destroy -var-file=prod.tfvars
```

## Design notes

- **Direct VPC egress, not a Serverless VPC Access connector.** There are no connector VMs to pay for or manage. The connector resource is still in `cloud-run-prerequisites`, commented out. Egress is `PRIVATE_RANGES_ONLY`, so only traffic to 10.x goes through the VPC.
- **Min 1 instance.** This avoids cold starts, at the cost of paying for an idle instance.
- **No public database.** The VM has no external IP. SSH works only from IAP's range (35.235.240.0/20), and port 5432 only from the subnet.
- **Secrets.** Terraform generates the DB password (`random_password`) and stores it in Secret Manager, and Cloud Run reads it through `secretKeyRef`. The password is also in Terraform state, so the state bucket must stay private.
- **Least privilege, mostly.** Each workload has its own service account with log/metric writer roles. The Cloud Run SA's `secretAccessor` role is project-wide. It could be scoped to the one secret.

## Changes made in the 2026 cleanup

- The HTML page escapes quote text, and error responses no longer include internal error messages.
- `package-lock.json` is now committed (it was git-ignored, so `npm ci` in the Dockerfile couldn't work). Dependencies are on current 4.x/8.x releases with `npm audit` clean, and the base image is `node:24-alpine`.
- The deploy workflow is manual-only, and workflow token permissions are cut to `contents: read`.
- The project ID, state bucket, VM IP and email are now placeholders or variables. The Terraform formatting was fixed.
