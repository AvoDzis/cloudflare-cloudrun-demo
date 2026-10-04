# Cloud Run + Cloudflare demo

A small Node.js "quote of the moment" app on Google Cloud Run with a Cloudflare edge in front. The app reads from PostgreSQL on a private VM over Direct VPC egress. Everything (network, database VM, Cloud Run service, load balancer, TLS, Cloudflare DNS/WAF/cache, monitoring, and the CI identities) is Terraform. GitHub Actions run plan, apply, deploy and destroy without stored cloud keys.

The original brief is [LAB_REQUIREMENTS.md](LAB_REQUIREMENTS.md).

## Status

What ran and what didn't:

| Part | State |
|------|-------|
| **Dec 2025, first version** | **Applied.** The original layout created the VPC, firewall rules, an e2-micro VM, the Secret Manager DB password and Artifact Registry in a personal GCP project. The app was deployed to Cloud Run with Skaffold. By the end the VM no longer started Postgres automatically. The load balancer / Cloudflare part was a draft that failed `terraform validate` and was never applied. That code is in the git history. |
| **Oct 2026 rework (this version)** | **Validated + `terraform test` with mocks, not applied.** Both Terraform roots pass `terraform fmt -check`, `terraform validate` and `terraform test` with mocked providers. No `terraform apply` has been run, no GCP or Cloudflare resources exist for it, and the cloud-facing behaviour (certificate issuance, Cloud Armor and Cloudflare rules on a real zone) is untested. |
| App | Unit tests with `node:test` (14 tests), `npm audit` clean, smoke-tested locally against a stubbed database. The container image wasn't built locally. |
| GitHub Actions | Linted with actionlint. They haven't run on GitHub yet. The cloud jobs skip themselves until the repository variables below are set. |

## Architecture

```
                    Users (allowed countries only)
                                 │ HTTPS
              ┌──────────────────▼────────────────────┐
              │ Cloudflare (proxied: api.<domain>)    │  WAF custom rules: scanners, probe paths, geo
              │                                       │  rate limit per IP, cache rules, Full (strict) TLS
              │                                       │  adds X-Cloudflare-Secret header
              └──────────────────┬────────────────────┘
 uptime checks ── health.api.<domain> (DNS only) ──┐
                                 │                 │
              ┌──────────────────▼─────────────────▼───┐
              │ Global external Application LB         │  static IP, Certificate Manager cert (DNS auth)
              │ Cloud Armor: Cloudflare IPs only,      │  TLS 1.2+ policy
              │ host-header guard, /health exception   │
              └──────────────────┬─────────────────────┘
                                 │ serverless NEG
              ┌──────────────────▼─────────────────────┐
              │ Cloud Run "prod-quotes-app"            │  ingress: internal + load balancer
              │ gen2, min 1 / max 10, 30 s timeout     │  secrets from Secret Manager
              │ startup probe /health, liveness /livez │  JSON logs → Cloud Logging
              └──────────────────┬─────────────────────┘
                                 │ Direct VPC egress (private ranges only)
              ┌──────────────────▼─────────────────────┐
              │ VPC 10.0.1.0/24                        │  firewall: 5432 from subnet, IAP for SSH/5432
              │ e2-micro VM, no external IP            │  Cloud NAT for package/image pulls
              │ Postgres 16 in Docker on a data disk   │  daily snapshots, 7-day retention
              └────────────────────────────────────────┘

 GitHub Actions ──OIDC──► Workload Identity Federation ──► plan / apply / deploy service accounts
```

## Design decisions

- **Global external Application Load Balancer, not the brief's regional one.** A regional external ALB also needs a proxy-only subnet, and Google-managed certificates for regional load balancers come only through Certificate Manager. The global ALB with a serverless NEG is Google's documented Cloud Run pattern, and it takes a Certificate Manager map directly ([docs](https://cloud.google.com/load-balancing/docs/https/setting-up-https-serverless)).
- **Certificate Manager with DNS authorization.** Cloudflare proxies the hostname, so Google can't validate the domain over HTTP. Validation uses a CNAME instead, which Terraform creates in Cloudflare ([docs](https://cloud.google.com/certificate-manager/docs/dns-authorizations)).
- **Defence in depth on the origin.** Three layers keep traffic from bypassing Cloudflare's WAF:
  - Cloud Run ingress is `internal-and-cloud-load-balancing`, so the `*.run.app` URL refuses internet traffic.
  - Cloud Armor admits only [Cloudflare's published IP ranges](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/) and only our hostnames.
  - The app rejects requests without the `X-Cloudflare-Secret` header, which a Cloudflare [request-header transform rule](https://developers.cloudflare.com/rules/transform/request-header-modification/) adds. This stops other Cloudflare customers who point their own zone at the load balancer IP.
- **Gray-cloud health hostname.** `health.api.<domain>` is DNS-only. Uptime checks hit the load balancer directly, so a Cloudflare problem and an origin problem show up differently. Cloud Armor lets this one host + path through.
- **Terraform owns the Cloud Run service; CD only swaps the image.** All settings live in `modules/cloud-run`. `deploy-app.yml` runs `gcloud run deploy --image`, and Terraform ignores `image`, `client` and `client_version`, so a deploy doesn't make the next plan dirty. The first version deployed a Knative YAML with Skaffold; that duplicated the config and is gone.
- **Probes.** The startup probe calls `/health`, which queries Postgres, so a revision that can't reach the database never takes traffic. The liveness probe calls `/livez`, which doesn't touch the database, so a DB outage doesn't restart every instance ([docs](https://cloud.google.com/run/docs/configuring/healthchecks)).
- **Direct VPC egress, private ranges only.** No Serverless VPC Access connector VMs. Only 10.x traffic goes through the VPC ([docs](https://cloud.google.com/run/docs/configuring/vpc-direct-vpc)).
- **Postgres on a VM, as in the brief.** A startup script installs Docker and mounts a separate data disk. It reads the password from Secret Manager with the VM's own identity, then runs `postgres:16-alpine`; the schema and seed data load on first start. Cloud SQL would be the production choice (HA, PITR, TLS); the VM keeps the lab cheap and was part of the brief.
- **Secrets never in Terraform state where avoidable.** The DB password is an [ephemeral](https://developer.hashicorp.com/terraform/language/resources/ephemeral) `random_password`, written to Secret Manager through a [write-only argument](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only) (`secret_data_wo`). **This needs Terraform 1.11 or newer.** The Cloudflare origin secret has to be sent to Cloudflare, so it is in state. The state bucket is private and versioned.
- **Keyless CI with three identities** ([GitHub OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-google-cloud-platform), [WIF for pipelines](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)):
  - The WIF provider accepts tokens only from this repository's numeric ID, and only from `main` or from `pull_request` jobs outside any environment.
  - Plan (read-only) works for the whole repo.
  - Apply and app-deploy only for jobs in the `prod` environment.
- **One Cloudflare ruleset per phase.** Cloudflare allows one zone entry-point ruleset per [phase](https://developers.cloudflare.com/ruleset-engine/about/phases/). Custom firewall rules, rate limit, cache rules and the origin header are one ruleset each.

## Repository layout

| Path | What it is |
|------|------------|
| `app/` | Express app, `node:test` tests, Dockerfile (multi-stage, non-root, read-only app files) |
| `terraform/` | Main stack and its modules: `networking`, `database-vm`, `cloud-run`, `artifact-registry`, `load-balancer`, `cloudflare`, `monitoring`. `tests/` holds the mocked `terraform test` suite. See [terraform/README.md](terraform/README.md) |
| `terraform/bootstrap/` | One-time stack: state bucket, APIs, Workload Identity Federation, CI service accounts |
| `.github/` | Workflows, Dependabot, CODEOWNERS. See [.github/README.md](.github/README.md) |
| `LAB_REQUIREMENTS.md` | The original brief |

## The app

| Endpoint | Returns | Cache-Control | Needs `X-Cloudflare-Secret` |
|----------|---------|---------------|-----------------------------|
| `GET /` | HTML page with a random quote | `public, max-age=300` | yes |
| `GET /api/quote` | the quote as JSON | `public, max-age=300` | yes |
| `GET /static/*` | CSS/JS | `public, max-age=3600` | yes |
| `GET /health` | DB check; 200 or 503, never error details | `no-cache` | no |
| `GET /livez` | process is up | `no-cache` | no |

It also does the following:

- **Security headers:** a strict CSP (no inline script), HSTS, `nosniff`, `X-Frame-Options: DENY`, no `X-Powered-By`.
- **Escaped output:** quote text is HTML-escaped.
- **Logs:** one JSON line per request with `severity`, `message`, `request_id`, `user_ip` (from `CF-Connecting-IP`) and `latency_ms`, in the format [Cloud Logging reads](https://cloud.google.com/logging/docs/structured-logging).
- **Database outages:** the app starts even when the DB is down; `/health` reports it.
- **Shutdown:** on SIGTERM it closes the server and the pool.

Run locally:

```bash
docker run -d --name quotes-db -p 5432:5432 \
  -e POSTGRES_DB=labdb -e POSTGRES_USER=labuser -e POSTGRES_PASSWORD=change-me postgres:16-alpine
sleep 5
docker exec -i quotes-db psql -U labuser -d labdb <<'SQL'
CREATE TABLE quotes (id SERIAL PRIMARY KEY, quote TEXT NOT NULL, author VARCHAR(100),
                     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
INSERT INTO quotes (quote, author) VALUES ('In the middle of difficulty lies opportunity.', 'Albert Einstein');
SQL

cd app && cp .env.example .env && npm ci && npm test && npm run dev   # http://localhost:8080
```

## Deploy

You need a GCP project with billing, a domain on Cloudflare, `gcloud`, and Terraform **1.11 or newer** (CI uses 1.14.7).

1. **Bootstrap (once, as a project owner, from your laptop).** It creates the state bucket, so the first apply keeps state locally:

   ```bash
   cd terraform/bootstrap
   cp terraform.tfvars.example terraform.tfvars          # project, bucket name, owner/repo, repo ID
   cp backend_override.tf.example backend_override.tf   # local state for the first run
   terraform init && terraform apply
   rm backend_override.tf
   terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket)"
   ```

2. **GitHub settings** (Settings → Secrets and variables → Actions, and Settings → Environments):
   - Variables: `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_PLAN_SA`, `GCP_APPLY_SA`, `GCP_DEPLOY_SA`, `TF_STATE_BUCKET` (all from `terraform output`), `DOMAIN`, `ALERT_EMAILS` (JSON list, e.g. `["alerts@example.com"]`). Optional: `GCP_REGION`, `CLOUD_RUN_SERVICE`, `ARTIFACT_REPOSITORY`.
   - Secrets: `CLOUDFLARE_API_TOKEN`, and `TF_PLAN_ENCRYPTION_KEY` (any long random string; it encrypts saved plans).
   - Environment `prod`: add required reviewers, and limit deployment branches to `main`.

3. **Cloudflare API token**, scoped to the one zone:
   - Zone: Read
   - DNS: Edit
   - Zone Settings: Edit
   - Zone WAF: Edit
   - Cache Rules: Edit
   - Transform Rules: Edit
   - Bot Management: Edit, only if you enable Bot Fight Mode

   These are the permission names from the dashboard's token editor; if the API reports a missing permission, add it there. Give the token an expiry date; `cloudflare-token-check.yml` warns 21 days before it expires.

4. **Infrastructure.** Merge to `main` and approve the `prod` environment in the *Terraform apply* run. Locally, the equivalent is `terraform init -backend-config="bucket=<bucket>" && terraform apply -var-file=prod.tfvars`, starting from `terraform/terraform.tfvars.example`. The first apply deploys a placeholder image. Certificate issuance can take a while after the DNS records exist.

5. **App.** Any change under `app/` on `main` (or a manual run) triggers *Deploy app*. It builds the image, pushes it as `…/quotes-app:<sha>`, runs `gcloud run deploy --image`, and smoke-tests `https://health.api.<domain>/health`.

**Destroy:** run *Terraform destroy* with the input `destroy prod`, then approve. It turns off deletion protection on the Cloud Run service and the VM, then destroys the main stack. Data-disk snapshots are kept, and the bootstrap stack is left alone.

## Operations

- **Alerts** (`modules/monitoring`) go to the email channels in `alert_emails`:
  - health check failing from 2+ regions (app or database down)
  - app cannot reach Postgres (log-based metric)
  - ERROR logs above a threshold (log-based metric, catches unhandled errors)
  - 5xx rate > 5%
  - p95 latency > 1 s

  Each alert carries a short runbook and links to the matching Logs Explorer query.
- **Roll back:** `gcloud run services update-traffic prod-quotes-app --region us-central1 --to-revisions <previous>=100`.
- **Database password rotation:**
  1. Bump `db_password_version` and apply. A new secret version is written.
  2. Right away, set it in Postgres: `ALTER USER labuser PASSWORD '…'` over IAP SSH. Until you do, newly started instances can't connect.
  3. Redeploy so all instances use it.
- **Origin secret rotation:** bump `origin_secret_version` and apply (Cloudflare starts sending the new value), then redeploy. There is a short window of 403s until new instances pick up the secret.
- **Backups:** daily snapshots of the data disk, kept 7 days and kept even if the disk is deleted. To restore, create a disk from a snapshot, attach it as `pgdata`, and re-run the startup script.

## Rough cost

These are list prices from memory, not a bill; check the Google Cloud pricing calculator. The main fixed costs per month are:

- the load balancer forwarding rule (≈ $18)
- Cloud Armor, one policy + 6 rules (≈ $11)
- one always-on Cloud Run instance (a few dollars, since CPU is only allocated during requests)
- Cloud NAT (≈ $1 plus data)

The e2-micro VM and up to 30 GB of standard disk fit the free tier in us-central1. Expect roughly **$35–45/month** before traffic. Cloudflare's Free plan covers everything enabled by default.

## Known trade-offs

- **Not applied yet.** Expect first-apply fixes: GCP/Cloudflare API rules that mocks can't catch, existing Cloudflare entry-point rulesets on the zone (those need importing), and certificate timing.
- **Single database VM.** No HA, plain TCP inside the VPC (no TLS to Postgres), and crash-consistent snapshots as the only backups. Use Cloud SQL for real workloads.
- **Plan identity can read secrets.** It has `secretmanager.secretAccessor` because refreshing secret versions can read payloads. PR plans only run for branches in this repo; forks get no OIDC token.
- **Apply identity can grant IAM roles.** It holds `resourcemanager.projectIamAdmin`, which it needs to grant the runtime roles. It's guarded by the `prod` environment approval and the main-only token condition.
- **Trivy IaC findings don't block CI.** They go to code scanning as reports. Trivy isn't run locally, so its first findings haven't been reviewed yet. Dependency and secret scans do fail the build.
- **Cloudflare plan limits.** On the Free plan the rate limit uses a 10-second window ([limits](https://developers.cloudflare.com/waf/rate-limiting-rules/)). The Managed and OWASP rulesets need Pro, and bot-score rules need Enterprise ([managed rules](https://developers.cloudflare.com/waf/managed-rules/)). They are behind `cloudflare_paid_waf` / `bot_score_threshold`. Zone TLS settings (Full strict, Always HTTPS, TLS 1.2) apply to the whole zone.
- **Inactive public repos.** GitHub pauses scheduled workflows (the token check, weekly CodeQL) after 60 days without activity.
- **Brief items not built:**
  - a separate dev environment (the stack takes an `environment` variable and a state prefix, but there's no dev workflow)
  - Ansible (replaced by the startup script)
  - Skaffold (removed, see above)

## References

- HashiCorp, [Running Terraform in automation](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform) (saved plans, `-detailed-exitcode`) and [test mocking](https://developer.hashicorp.com/terraform/language/tests/mocking)
- GitHub, [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions); OpenSSF [Scorecard](https://github.com/ossf/scorecard) checks (pinned dependencies, token permissions)
- Google Cloud: [Cloud Run ingress](https://cloud.google.com/run/docs/securing/ingress), [Cloud Armor](https://cloud.google.com/armor/docs/security-policy-overview), [scheduled snapshots](https://cloud.google.com/compute/docs/disks/scheduled-snapshots)
- Cloudflare: [Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/), [IP ranges](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/)
