# GitHub Actions

## Workflows

### `pr-validation.yml` (pull requests to `main`)

1. `terraform fmt -check`, `init`, `validate`, `plan -var-file=prod.tfvars`
2. `npm ci` in `app/`
3. `skaffold validate`
4. `gcloud run services replace --dry-run` on `resources/prod/*.yaml`
5. `docker build` of the app (no push)

### `deploy.yml` (manual, `workflow_dispatch`)

1. `skaffold run -p prod`: build in Cloud Build, push to Artifact Registry, deploy the Cloud Run manifest
2. Check that the Cloud Run `*.run.app` URL is **not** publicly reachable. The job fails if it is.
3. Try the health endpoint through the load-balancer domain. This step is non-fatal, because the load balancer (stage 2) was never built.

Deploys used to run on pushes to `main` that touched the app, manifests or Skaffold config. They are now manual-only, so pushes never deploy anything.

## Secrets and variables

| Name | Kind | Used by |
|------|------|---------|
| `GCP_CREDENTIALS_JSON` | secret | Both workflows: service-account key JSON for `google-github-actions/auth` |
| `CLOUDFLARE_API_TOKEN` | secret | `pr-validation.yml` (passed to Terraform as `TF_VAR_cloudflare_api_token`) |
| `TF_STATE_BUCKET` | variable | `pr-validation.yml` (`terraform init -backend-config`) |

The deploying service account needs roughly: `run.admin`, `cloudbuild.builds.editor`, `artifactregistry.writer`, `iam.serviceAccountUser`, plus read access to the Terraform state bucket for the PR plan.

## Known gaps

- **Long-lived key.** Authentication uses a long-lived service-account key. The first version of the workflows used Workload Identity Federation (`workload_identity_provider` + `service_account`), which needs no stored key. It was switched to a key while getting the pipeline to run. WIF is the better option.
- **Plan needs a missing file.** The PR plan step reads `prod.tfvars`, which is git-ignored, so that step fails in CI unless the file is generated first (for example, from repository variables).
- **Unpinned Skaffold.** Skaffold is downloaded from `latest` instead of a pinned version.
