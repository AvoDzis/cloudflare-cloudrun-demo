# Terraform Infrastructure

This directory contains Terraform configuration for deploying the Cloud Run + Cloudflare infrastructure.

## Prerequisites

1. **GCP Project**: `test-project-402414`
2. **Cloudflare Account** with domain `avodzis.online`
3. **Terraform** >= 1.6.0
4. **gcloud CLI** installed and authenticated

## Setup

### 1. Create GCS Backend Bucket

```bash
export PROJECT_ID=test-project-402414

# Create bucket for Terraform state
gsutil mb gs://cloudrun-cloudflare-test

# Enable versioning
gsutil versioning set on gs://cloudrun-cloudflare-test
```

### 2. Enable Required APIs

```bash
gcloud services enable \
  run.googleapis.com \
  compute.googleapis.com \
  vpcaccess.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  iamcredentials.googleapis.com \
  --project=$PROJECT_ID
```

### 3. Set Cloudflare API Token

```bash
# Set as environment variable (recommended)
export TF_VAR_cloudflare_api_token="your-cloudflare-api-token"
```

**Creating Cloudflare API Token:**
1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token" → "Create Custom Token"
3. Set permissions:
   - Zone.DNS - Edit
   - Zone.Zone Settings - Read
   - Zone.WAF - Edit
   - Zone.Cache Purge - Purge
   - Account.Account Settings - Read
4. Zone Resources: Include → Specific zone → avodzis.online
5. Account Resources: Include → Your account

## Deployment

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Plan Infrastructure

```bash
terraform plan
```

### Apply Infrastructure

```bash
terraform apply
```

Review the plan and type `yes` to confirm.

## Outputs

After successful deployment, you'll see:

```
vpc_network_name              = "prod-cloud-run-vpc"
vm_internal_ip                = "10.0.1.x"
cloud_run_service_url         = "https://prod-lab-app-xxx.a.run.app"
cloudflare_proxied_domain     = "https://api.avodzis.online"
cloudflare_direct_domain      = "https://health.api.avodzis.online"
artifact_registry_repository_url = "us-central1-docker.pkg.dev/test-project-402414/lab-repo"
```

## Accessing Resources

### Connect to PostgreSQL via IAP Tunnel

```bash
# Get VM name from outputs
VM_NAME=$(terraform output -raw vm_instance_name)

# Start IAP tunnel
gcloud compute start-iap-tunnel $VM_NAME 5432 \
  --local-host-port=localhost:5432 \
  --zone=us-central1-a

# In another terminal, connect with psql
psql -h localhost -p 5432 -U labuser -d labdb
# Password is auto-generated and stored in Secret Manager
```

### View Secrets

```bash
# Database password
gcloud secrets versions access latest --secret="prod-db-password"

# Cloudflare validation secret
gcloud secrets versions access latest --secret="prod-cloudflare-secret"
```

### View Cloud Run Logs

```bash
gcloud run services logs read prod-lab-app --region=us-central1
```

## Module Structure

```
modules/
├── networking/          # VPC, subnet, firewall rules
├── compute/             # VM with PostgreSQL
├── cloud-run/           # Cloud Run service with Direct VPC Egress
├── artifact-registry/   # Docker image repository
├── cloudflare/          # DNS, WAF, cache rules
└── monitoring/          # Uptime checks, alert policies
```

## Destroy Infrastructure

```bash
terraform destroy
```

Type `yes` to confirm deletion of all resources.

## Notes

- **Database Password**: Auto-generated 32-character password stored in Secret Manager
- **Cloudflare Secret**: Auto-generated 64-character string for header validation
- **VM has no external IP**: Access only via IAP tunnel
- **Cloud Run uses Direct VPC Egress**: Connects directly to PostgreSQL without NAT
- **Min 1 instance**: No cold starts

## Troubleshooting

### Error: Backend bucket doesn't exist
```bash
gsutil mb gs://cloudrun-cloudflare-test
```

### Error: API not enabled
```bash
# Enable the specific API mentioned in the error
gcloud services enable <api-name> --project=$PROJECT_ID
```

### Error: Insufficient permissions
Ensure your gcloud user has the following roles:
- `roles/owner` or
- `roles/editor` + `roles/secretmanager.admin`
