# Terraform

Two roots, both pinned (`required_version >= 1.11.0`, provider `~>` constraints, committed `.terraform.lock.hcl` with hashes for Linux, macOS and Windows):

| Root | Applied by | State |
|------|-----------|-------|
| `bootstrap/` | a project owner, once, from a laptop | GCS, prefix `bootstrap` (local for the very first run) |
| `.` (main stack) | GitHub Actions (`terraform-apply.yml`), or locally | GCS, prefix `main` |

Status: **validated + `terraform test` with mocks, not applied.** See the [main README](../README.md#status).

## Main stack modules

| Module | Creates |
|--------|---------|
| `networking` | VPC, subnet with Private Google Access, firewall (IAP → 22/5432, subnet → 5432, explicit deny-all with logging), Cloud Router + NAT |
| `database-vm` | Shielded e2-micro Ubuntu 24.04 VM without external IP, separate data disk, daily snapshot schedule (kept after disk deletion), VM service account with access to the one DB secret, startup script that runs Postgres |
| `cloud-run` | Runtime service account (secret access only), Cloud Run v2 service (ingress internal + LB, gen2, probes, Direct VPC egress, secrets from Secret Manager, image ignored after create), public invoker binding, deployer bindings |
| `artifact-registry` | Docker repo with immutable tags and a cleanup policy, writer binding for the deployer |
| `load-balancer` | Global IP, serverless NEG, backend service with Cloud Armor (Cloudflare ranges, host guard, health exception, default deny), Certificate Manager DNS authorizations + managed cert + map, TLS 1.2 policy, HTTPS proxy, forwarding rule |
| `cloudflare` | A records (api proxied, health DNS-only), certificate validation CNAMEs, zone TLS settings, rulesets: custom firewall (scanner UAs, probe paths, geo), rate limit, optional managed WAF, cache, origin header; optional Bot Fight Mode |
| `monitoring` | Email channels, uptime check (needs `"database":"connected"`), two log-based metrics, five alert policies with runbooks and Logs Explorer links |

The root module also creates the two Secret Manager secrets. The DB password comes from an ephemeral `random_password` written through `secret_data_wo`; the origin secret comes from a regular `random_password`, since Cloudflare needs the value.

## Inputs

Required: `project_id`, `domain`, `alert_emails`, `deployer_service_account` (bootstrap output) and `cloudflare_api_token` (as `TF_VAR_cloudflare_api_token`). Everything else has a default; see `variables.tf` and `terraform.tfvars.example`. Useful switches:

| Variable | Default | Effect |
|----------|---------|--------|
| `deletion_protection` | `true` | Protects the Cloud Run service and the VM |
| `allowed_countries` | `["ES", "AM"]` | Geo rule on the app hostname |
| `rate_limit_requests` / `rate_limit_period` | `20` / `10` | Per-IP limit (Free plan: 10 s period only) |
| `cloudflare_paid_waf` | `false` | Cloudflare Managed + OWASP rulesets (Pro+) |
| `cloudflare_bot_fight_mode` | `false` | Bot Fight Mode (can challenge API clients) |
| `db_password_version` / `origin_secret_version` | `1` | Bump to rotate |

## Commands

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
terraform test                       # mocked providers: offline, creates nothing

terraform init -backend-config="bucket=<state bucket>"
terraform plan -var-file=prod.tfvars
```

`tests/main.tftest.hcl` covers:

- the whole stack wired together
- Cloud Run: ingress, scaling, timeout, probes, secret env vars, deletion protection
- Cloud Armor: rule chunking and default deny
- Cloudflare: proxied vs DNS-only records, Full (strict), geo expression, Free-plan defaults, input validation
- database VM: no external IP, Shielded VM, password from Secret Manager, snapshot retention

`bootstrap/tests/` checks the WIF trust conditions, the read-only plan roles and the state-bucket settings.
