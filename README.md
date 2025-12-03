# Cloud Run + Load Balancer + Cloudflare Deployment Guide

## Architecture Overview

```
Internet Users (ES + AM only)
        ↓
Cloudflare Edge (Proxied)
  - WAF Rules
  - Cache Rules
  - Geo-restriction
        ↓
Regional Load Balancer (us-central1)
  - Static IP
  - Google-managed SSL cert
  - HTTPS (443)
        ↓
Cloud Run (Internal Ingress Only)
  - Gen2, Min 1 instance
  - VPC Direct Egress
        ↓
PostgreSQL VM (Internal IP only)
```

## Prerequisites

1. **GCP Project**: `test-project-402414`
2. **Domain**: `avodzis.online` configured in Cloudflare
3. **Tools**:
   - gcloud CLI (authenticated)
   - Terraform >= 1.6.0
   - Skaffold
   - kubectl (optional)

## Step-by-Step Deployment

### Phase 1: Initial Infrastructure Setup

#### 1.1 Create GCS Backend for Terraform State

```bash
export PROJECT_ID=test-project-402414

# Create bucket
gsutil mb gs://cloudrun-cloudflare-test

# Enable versioning
gsutil versioning set on gs://cloudrun-cloudflare-test
```

#### 1.2 Enable Required GCP APIs

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

#### 1.3 Create Cloudflare API Token

1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token" → "Create Custom Token"
3. Set permissions:
   - Zone.DNS - Edit
   - Zone.Zone Settings - Read
   - Zone.WAF - Edit
   - Zone.Cache Purge - Purge
   - Account.Account Settings - Read
4. Zone Resources: Include → Specific zone → `avodzis.online`
5. Save the token

#### 1.4 Set Environment Variables

```bash
export TF_VAR_cloudflare_api_token="your-cloudflare-api-token"
```

### Phase 2: Deploy Base Infrastructure (Without Load Balancer)

**Important**: We deploy in stages because Load Balancer needs Cloud Run service to exist first.

#### 2.1 Comment Out Load Balancer Module

Edit `terraform/main.tf` and **comment out** the Load Balancer module:

```hcl
# # Load Balancer Module
# # Note: Deploy this AFTER Cloud Run service is deployed via Skaffold
# module "load_balancer" {
#   source = "./modules/load-balancer"
#   ...
# }
```

Also comment out Cloudflare and Monitoring modules (they depend on LB).

#### 2.2 Deploy Base Infrastructure

```bash
cd terraform

terraform init

terraform plan -var-file="prod.tfvars"

terraform apply -var-file="prod.tfvars"
```

#### 2.3 Note Important Outputs

```bash
# Get VM internal IP (needed for Cloud Run YAML)
VM_IP=$(terraform output -raw vm_internal_ip)
echo "VM Internal IP: $VM_IP"

# Get service account email
SA_EMAIL=$(terraform output -raw cloud_run_service_account)
echo "Service Account: $SA_EMAIL"

# Get artifact registry URL
ARTIFACT_REGISTRY=$(terraform output -raw artifact_registry_repository_url)
echo "Artifact Registry: $ARTIFACT_REGISTRY"
```

### Phase 3: Update Cloud Run YAML with Terraform Outputs

#### 3.1 Edit Cloud Run Service YAML

Edit `resources/prod/service.prod.yaml`:

```yaml
spec:
  template:
    spec:
      serviceAccountName: prod-cloud-run-sa  # Should match $SA_EMAIL
      containers:
        - env:
            - name: DB_HOST
              value: "10.0.1.x"  # Replace with $VM_IP
```

Replace `"REPLACE_WITH_VM_INTERNAL_IP"` with the actual VM internal IP from Terraform output.

### Phase 4: Deploy Application with Skaffold

#### 4.1 Deploy Cloud Run Service

```bash
# From project root
skaffold run -p prod
```

This will:
- Build Docker image using Cloud Build
- Push to Artifact Registry
- Deploy to Cloud Run using the YAML manifest

#### 4.2 Verify Cloud Run Deployment

```bash
gcloud run services list --region=us-central1

# Get Cloud Run service details
gcloud run services describe prod-lab-app \
  --region=us-central1 \
  --format="value(status.url)"
```

**Note**: The Cloud Run URL will NOT be publicly accessible (internal ingress only). This is expected!

### Phase 5: Deploy Load Balancer and Complete Setup

#### 5.1 Uncomment Load Balancer Module

Edit `terraform/main.tf` and **uncomment** the Load Balancer, Cloudflare, and Monitoring modules:

```hcl
# Load Balancer Module
module "load_balancer" {
  source = "./modules/load-balancer"
  ...
}

# Cloudflare Module
module "cloudflare" {
  ...
}

# Monitoring Module
module "monitoring" {
  ...
}
```

#### 5.2 Apply Terraform with Load Balancer

```bash
cd terraform

terraform apply -var-file="prod.tfvars"
```

This will create:
- Regional Load Balancer
- Static IP
- Google-managed SSL certificate
- Serverless NEG pointing to Cloud Run
- Cloudflare DNS A records
- Monitoring alerts

#### 5.3 Get Load Balancer IP

```bash
LB_IP=$(terraform output -raw load_balancer_ip)
echo "Load Balancer IP: $LB_IP"
```

### Phase 6: Verify SSL Certificate

The SSL certificate may take 10-15 minutes to provision via DNS validation.

```bash
# Check SSL certificate status
watch gcloud compute ssl-certificates describe prod-lb-cert \
  --region=us-central1 \
  --format="get(managed.status)"
```

Wait until status shows `ACTIVE`.

### Phase 7: Test Deployment

#### 7.1 Test via Load Balancer IP (Direct)

```bash
# Test health endpoint
curl -H "Host: health.api.avodzis.online" http://$LB_IP/health

# Test main page
curl -H "Host: api.avodzis.online" http://$LB_IP/
```

#### 7.2 Test via Cloudflare DNS

Once SSL cert is ACTIVE:

```bash
# Test main page
curl https://api.avodzis.online/

# Test health endpoint
curl https://health.api.avodzis.online/health

# Test API endpoint
curl https://api.avodzis.online/api/quote

# Test static files
curl https://api.avodzis.online/static/style.css
```

#### 7.3 Verify Cache Headers

```bash
curl -I https://api.avodzis.online/static/style.css | grep -i cache
# Should see: cache-control: public, max-age=3600

curl -I https://api.avodzis.online/api/quote | grep -i cache
# Should see: cache-control: public, max-age=300

curl -I https://health.api.avodzis.online/health | grep -i cache
# Should see: cache-control: no-cache
```

#### 7.4 Verify Cloud Run is Internal-Only

```bash
# This should FAIL (403 or timeout) - proving it's internal-only
CLOUD_RUN_URL=$(gcloud run services describe prod-lab-app \
  --region=us-central1 --format='value(status.url)')

curl $CLOUD_RUN_URL
# Expected: 403 Forbidden or timeout
```

### Phase 8: Connect to Database

#### 8.1 Via IAP Tunnel

```bash
# Start IAP tunnel
gcloud compute start-iap-tunnel prod-postgres-vm 5432 \
  --local-host-port=localhost:5432 \
  --zone=us-central1-a

# In another terminal, get DB password
gcloud secrets versions access latest --secret="prod-db-password"

# Connect with psql
psql -h localhost -p 5432 -U labuser -d labdb

# Query quotes
SELECT * FROM quotes;
```

## Architecture Highlights

### Security Features

1. **Cloud Run Internal Ingress**: Not accessible from internet
2. **Load Balancer**: Single entry point with static IP
3. **Cloudflare WAF**: Geo-restriction (ES/AM only), rate limiting, OWASP rules
4. **PostgreSQL**: Internal IP only, IAP tunnel access
5. **Secrets**: Stored in Secret Manager, not hardcoded

### Cost Optimization

- **e2-micro VM**: Always Free tier
- **Cloud Run**: Pay per use, min 1 instance
- **Regional Load Balancer**: ~$14-17/month
- **Cloudflare**: Free tier
- **Total**: ~$15-20/month

### Performance Features

1. **Min 1 Instance**: No cold starts
2. **VPC Direct Egress**: Fast database access
3. **Cloudflare Caching**: Static (1h), API (5m), Health (no-cache)
4. **Connection Pooling**: PostgreSQL connection pool (max 10)

## Monitoring

### View Logs

```bash
# Cloud Run logs
gcloud run services logs read prod-lab-app --region=us-central1 --limit=50

# VM logs
gcloud compute instances get-serial-port-output prod-postgres-vm \
  --zone=us-central1-a
```

### View Metrics

Go to GCP Console → Cloud Run → prod-lab-app → Metrics

Or use:

```bash
gcloud monitoring dashboards list
```

### Check Alerts

```bash
gcloud alpha monitoring policies list
```

## Cleanup

To destroy all resources:

```bash
cd terraform

terraform destroy -var-file="prod.tfvars"
```

This will remove:
- Load Balancer
- Cloud Run service (if managed by Terraform)
- PostgreSQL VM
- VPC and networking
- Secrets
- Artifact Registry
- Cloudflare DNS records

**Note**: Cloud Run service deployed via Skaffold must be deleted manually:

```bash
gcloud run services delete prod-lab-app --region=us-central1
```

## Troubleshooting

### SSL Certificate Not Provisioning

- Verify DNS records are created: `dig api.avodzis.online`
- Check Cloudflare proxy is enabled (orange cloud)
- Wait up to 15 minutes for DNS propagation

### Cloud Run Can't Connect to Database

- Verify VM internal IP in Cloud Run YAML matches Terraform output
- Check firewall rules allow Cloud Run subnet to PostgreSQL port 5432
- Verify VPC Direct Egress is configured in Cloud Run YAML

### 403 Errors from Cloudflare

- Check geo-restriction WAF rule
- Verify you're accessing from ES or AM
- Check rate limiting (max 100 req/min)

### Skaffold Build Fails

```bash
# Enable Cloud Build API
gcloud services enable cloudbuild.googleapis.com

# Check service account permissions
gcloud projects get-iam-policy $PROJECT_ID
```

## Next Steps

1. Set up GitHub Actions for CI/CD
2. Add custom domain SSL certificate
3. Implement blue/green deployments
4. Add more monitoring dashboards
5. Set up log-based metrics

## Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Regional Load Balancer](https://cloud.google.com/load-balancing/docs/https)
- [Cloudflare API](https://developers.cloudflare.com/api/)
- [Skaffold Documentation](https://skaffold.dev/docs/)
