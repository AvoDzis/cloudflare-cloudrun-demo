# GitHub Actions

Status: linted with actionlint 1.7.12. The workflows haven't run on GitHub yet. Every job that needs GCP has `if: vars.GCP_WIF_PROVIDER != ''`, so it skips cleanly until the repository is configured (see the main README, "Deploy").

| Workflow | Trigger | What it does | Cloud identity |
|----------|---------|--------------|----------------|
| `ci.yml` | PRs, pushes to `main` | App: `npm ci`, `npm test`, `npm audit`, `docker build`. Terraform, per root: `fmt -check`, `validate`, `terraform test` (mocked). Scans: gitleaks (full history), Trivy fs (HIGH/CRITICAL deps + secrets, blocking), Trivy config (IaC, to code scanning), actionlint | none |
| `codeql.yml` | PRs, `main`, weekly | CodeQL for JavaScript and for the workflows themselves | none |
| `terraform-plan.yml` | PRs touching `terraform/` | Matrix over `main` and `bootstrap`. Runs `plan -detailed-exitcode` (0 no changes, 2 changes, 1 fails the job) and keeps **one** PR comment per root up to date | plan (read-only) |
| `terraform-apply.yml` | `main` (main stack), manual | Plan, then encrypt the saved plan and upload it as an artifact (1 day). After approval on the `prod` environment, apply **that** plan file | plan, then apply |
| `deploy-app.yml` | `main` (`app/`), manual | Test, build, push `…/quotes-app:<sha>`, `gcloud run deploy --image`, smoke test via the health hostname | deploy (`prod` env) |
| `terraform-destroy.yml` | manual, input `destroy prod` | Turn off deletion protection on the 2 protected resources, then `terraform destroy` (`prod` env approval) | apply |
| `cloudflare-token-check.yml` | weekly, manual | Calls Cloudflare's token-verify API; fails if the token is inactive or expires within 21 days | none |

## Trust model (Workload Identity Federation, no keys)

- The provider in `terraform/bootstrap` accepts GitHub OIDC tokens only when `repository_id` matches this repository. On top of that, the job must either run on `refs/heads/main` (not a PR event) or be a `pull_request` job outside any environment (subject `repo:<owner>/<repo>:pull_request`).
- `gh-terraform-plan` can be used by any job of the repo (including same-repo PRs). Its roles: `viewer`, `iam.securityReviewer`, `secretmanager.secretAccessor`, plus state-bucket object access.
- `gh-terraform-apply` and `gh-app-deploy` can only be used by jobs whose subject is `repo:<owner>/<repo>:environment:prod`. Configure that environment with required reviewers and a `main`-only branch policy.
- Pull requests from forks get no OIDC token and no secrets. Only `ci.yml` and `codeql.yml` run for them.

## Hardening

Following GitHub's [security hardening guide](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions) and the OpenSSF [Scorecard](https://github.com/ossf/scorecard) checks:

- **Pinning:** every third-party action is pinned to a full commit SHA, with the version in a comment. SHAs were resolved from the release tags on 2026-10-04, and Dependabot keeps them (and npm, Terraform providers and the Docker base image) current. actionlint runs from an image pinned by digest.
- **Token permissions:** `permissions: {}` at workflow level; each job asks only for what it needs (`contents: read`, plus `id-token: write` / `pull-requests: write` / `security-events: write` where used).
- **Checkouts:** `actions/checkout` runs with `persist-credentials: false`.
- **Concurrency:** CI runs cancel superseded runs. Terraform apply/destroy and app deploys queue instead (`cancel-in-progress: false`).
- **No injection paths:** untrusted values are never put inside `run:` scripts; they go through `env:`.
- **Saved plans are encrypted:** artifacts of public repositories can be downloaded by any signed-in user, and a plan file contains state values. The key is the `TF_PLAN_ENCRYPTION_KEY` secret.
- **CODEOWNERS** covers `.github/` and `terraform/bootstrap/`. It takes effect once branch protection requires code-owner review.

## Repository settings this expects

Variables:

- `GCP_PROJECT_ID`
- `GCP_WIF_PROVIDER`
- `GCP_PLAN_SA`, `GCP_APPLY_SA`, `GCP_DEPLOY_SA`
- `TF_STATE_BUCKET`
- `DOMAIN`
- `ALERT_EMAILS`, a JSON list
- optional: `GCP_REGION`, `CLOUD_RUN_SERVICE`, `ARTIFACT_REPOSITORY`

Secrets:

- `CLOUDFLARE_API_TOKEN`
- `TF_PLAN_ENCRYPTION_KEY`

Environment:

- `prod`, with reviewers and a `main`-only branch policy

Branch protection on `main`:

- PRs required
- status checks `CI` and `Terraform plan` must pass
- code-owner review
