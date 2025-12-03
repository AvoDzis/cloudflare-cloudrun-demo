# GitHub Actions CI/CD Setup

This directory contains GitHub Actions workflows for automated deployment and validation.

## Workflows

### 1. `deploy.yml` - Production Deployment

**Triggers:** Push to `main` branch

**What it does:**
- Detects changes to `app/`, `terraform/`, `resources/`, or `skaffold.yaml`
- Deploys Terraform infrastructure (if changed)
- Updates Cloud Run YAML with latest VM internal IP
- Deploys application via Skaffold (if changed)
- Verifies deployment and internal-only access
- Provides deployment summary

**Environment:** `prod`

### 2. `pr-validation.yml` - Pull Request Validation

**Triggers:** Pull request to `main` branch

**What it does:**
- Validates Terraform formatting and configuration
- Runs Terraform plan (dry-run)
- Validates Skaffold configuration
- Validates Cloud Run YAML files
- Builds Docker image (without pushing)
- Posts validation results to PR

## Required GitHub Secrets

Configure these secrets in your GitHub repository:

**Settings → Secrets and variables → Actions → New repository secret**

### GCP Authentication (Workload Identity Federation)

| Secret Name | Description | Example |
|------------|-------------|---------|
| `PROJECT_ID` | GCP Project ID | `test-project-402414` |
| `WIF_PROVIDER` | Workload Identity Provider | `projects/123/locations/global/workloadIdentityPools/github/providers/github-provider` |
| `SERVICE_ACCOUNT` | Service Account Email | `github-actions@test-project-402414.iam.gserviceaccount.com` |

### Cloudflare

| Secret Name | Description | How to get |
|------------|-------------|------------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | [Create Token](https://dash.cloudflare.com/profile/api-tokens) |

## Setting Up Workload Identity Federation

Workload Identity Federation allows GitHub Actions to authenticate to GCP without storing service account keys.

### Step 1: Enable Required APIs

```bash
gcloud services enable iamcredentials.googleapis.com \
  --project=test-project-402414
```

### Step 2: Create Workload Identity Pool

```bash
gcloud iam workload-identity-pools create github \
  --location=global \
  --display-name="GitHub Actions Pool" \
  --project=test-project-402414
```

### Step 3: Create Workload Identity Provider

```bash
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global \
  --workload-identity-pool=github \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --project=test-project-402414
```

### Step 4: Create Service Account for GitHub Actions

```bash
gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions Service Account" \
  --project=test-project-402414
```

### Step 5: Grant Required Permissions

```bash
PROJECT_ID="test-project-402414"
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"

# Cloud Run Admin
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/run.admin"

# Cloud Build Editor
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/cloudbuild.builds.editor"

# Artifact Registry Writer
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.writer"

# Service Account User
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountUser"

# Secret Manager Accessor
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"

# Compute Admin (for Terraform)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.admin"

# Storage Admin (for Terraform state)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.admin"
```

### Step 6: Bind Service Account to GitHub Repository

```bash
PROJECT_ID="test-project-402414"
REPO="your-github-username/cloudflare-cloudrun-task"  # Replace with your repo

gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')/locations/global/workloadIdentityPools/github/attribute.repository/${REPO}"
```

### Step 7: Get WIF Provider Name

```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github \
  --format='value(name)' \
  --project=test-project-402414
```

Copy the output (looks like: `projects/123456789/locations/global/workloadIdentityPools/github/providers/github-provider`) and add it as `WIF_PROVIDER` secret.

## Environment Configuration

### GitHub Environment: `prod`

**Settings → Environments → New environment → `prod`**

**Optional Protection Rules:**
- ✅ Required reviewers (1-2 people)
- ✅ Wait timer (e.g., 5 minutes)
- ✅ Branch protection (only from `main`)

## Testing the Workflow

### Test Infrastructure Deployment

```bash
# Make a change to Terraform
git checkout -b test-terraform
echo "# test" >> terraform/main.tf
git add terraform/main.tf
git commit -m "test: terraform change"
git push origin test-terraform

# Create PR and see validation run
# Merge to main and see deployment run
```

### Test Application Deployment

```bash
# Make a change to app
git checkout -b test-app
echo "// test" >> app/server.js
git add app/server.js
git commit -m "test: app change"
git push origin test-app

# Create PR and see validation run
# Merge to main and see deployment run
```

## Workflow Features

### Smart Change Detection

The workflow only deploys what changed:
- **Terraform changed** → Runs `terraform apply`
- **App changed** → Runs `skaffold run`
- **Both changed** → Runs both in sequence

### Security Validation

The workflow verifies:
- ✅ Cloud Run service is internal-only (public access should fail)
- ✅ Load Balancer health check responds
- ✅ Terraform plan is valid before apply

### Deployment Summary

After deployment, the workflow posts a summary with:
- Cloud Run service URL (internal)
- Public URLs (via Load Balancer)
- Verification commands

## Troubleshooting

### Workflow fails with "Permission denied"

Check that the service account has all required IAM roles (see Step 5 above).

### Workflow fails with "Workload Identity Federation not configured"

Verify the `WIF_PROVIDER` secret is correctly formatted and the binding in Step 6 was successful.

### Terraform state lock error

Another workflow or local Terraform might have the state locked. Wait a few minutes and retry.

### Skaffold build fails

Check that:
- Cloud Build API is enabled
- Service account has `cloudbuild.builds.editor` role
- Artifact Registry repository exists

## Best Practices

1. **Always create PRs**: Don't push directly to `main`
2. **Review Terraform plans**: Check the plan output in PR validation
3. **Monitor deployments**: Watch the Actions tab during deployment
4. **Test after deployment**: Run the verification commands from the summary

## Manual Deployment

If you need to deploy manually:

```bash
# Authenticate
gcloud auth login
gcloud config set project test-project-402414

# Deploy infrastructure
cd terraform
terraform apply -var-file=prod.tfvars

# Deploy application
skaffold run -p prod
```
