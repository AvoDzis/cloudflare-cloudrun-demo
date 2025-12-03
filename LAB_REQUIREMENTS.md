# Cloud Run + Cloudflare Production Infrastructure Lab

## Overview

Build a production-grade infrastructure combining GCP Cloud Run, Cloudflare edge security, and private database connectivity using Infrastructure as Code.

---

## Deliverables

### Required Outputs
- [ ] Public GitHub repository
- [ ] Complete Terraform configuration
- [ ] GitHub Actions workflows (plan, apply, destroy)
- [ ] README.md with:
  - Architecture diagram
  - Design decisions
  - Deployment instructions
  - Cleanup/destroy instructions
- [ ] All resources deployable and destroyable via automation

---

## Architecture Overview

```
Internet Users (ES + AM only)
        ↓
Cloudflare Edge

  - Orange Cloud (api.avodzis.online) → Proxied
  - Gray Cloud (health.api.avodzis.online) → Direct DNS
  - WAF Rules (Geo, Rate Limit, SQL Injection, Bot)
  - Cache Rules (Static: 1h, API: 5m, Health: no-cache)
        ↓
Cloud Run Service (us-central1)
  - Gen2, Min 1 instance
  - Direct VPC Egress
  - Internal + LB Ingress
        ↓
VPC Network (10.0.0.0/16)
        ↓
Compute Engine e2-micro (Internal IP only)
  - PostgreSQL in Docker
  - Port 5432
        ↓
Cloud Monitoring
  - Uptime check on gray cloud endpoint
  - Alert: 5xx > 5%
  - Alert: p95 latency > 1000ms
```

---

## Part 1: Infrastructure Setup

### 1.1 VPC Networking

**Tasks:**
- [ ] Create custom VPC network (`10.0.0.0/16`)
- [ ] Create subnet in us-central1 (`10.0.1.0/24`)
- [ ] Enable Private Google Access on subnet
- [ ] Configure firewall rules:
  - Allow IAP tunneling (35.235.240.0/20) to port 22
  - Allow Cloud Run to PostgreSQL (port 5432) within VPC
  - Default deny all other ingress

**Terraform Module:** `modules/networking/`

**Acceptance Criteria:**
- VPC created with custom mode
- Private Google Access enabled
- Least-privilege firewall rules

---

### 1.2 Compute Engine with PostgreSQL

**Tasks:**
- [ ] Provision e2-micro VM in us-central1 (Always Free tier)
- [ ] **Internal IP only** - no external IP address
- [ ] Use Container-Optimized OS or Ubuntu 22.04
- [ ] Create minimal service account with:
  - `roles/logging.logWriter`
  - `roles/monitoring.metricWriter`
- [ ] Write startup script to install Docker
- [ ] Create Ansible playbook to:
  - Deploy PostgreSQL container (port 5432)
  - Initialize database `labdb`
  - Create table `quotes` with sample data
  - Configure PostgreSQL to accept VPC connections

**Database Schema:**
```sql
CREATE TABLE quotes (
  id SERIAL PRIMARY KEY,
  quote TEXT NOT NULL,
  author VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Developer Access Method:**
Document how developers connect from laptop:
```bash
# IAP tunnel to access PostgreSQL
gcloud compute start-iap-tunnel [VM-NAME] 5432 \
  --local-host-port=localhost:5432 \
  --zone=us-central1-a

# Then connect with psql
psql -h localhost -p 5432 -U labuser -d labdb
```

**Terraform Module:** `modules/compute/`  
**Ansible:** `ansible/playbooks/setup-postgres.yml`

**Acceptance Criteria:**
- VM has no external IP
- PostgreSQL running in Docker
- Database initialized with sample quotes
- IAP tunnel access documented

---

### 1.3 Secret Manager

**Tasks:**
- [ ] Create secrets:
  - `db-user` (PostgreSQL username)
  - `db-password` (PostgreSQL password)
  - `cloudflare-secret` (for header validation)
- [ ] Grant Cloud Run service account `roles/secretmanager.secretAccessor`

**Acceptance Criteria:**
- Secrets stored securely
- Service account has access

---

## Part 2: Application Development

### 2.1 Application Code

**Requirements:**
Build HTTP service (Node.js, Python, or Go) with these endpoints:

**Endpoint 1: `GET /` (Main - Proxied via Cloudflare)**
- Query random quote from PostgreSQL
- Return HTML page with quote
- Set `Cache-Control: public, max-age=300`
- Validate `X-Cloudflare-Secret` header

**Endpoint 2: `GET /health` (Health Check - Direct DNS)**
- Return JSON: `{"status": "healthy", "timestamp": "..."}`
- Check database connectivity
- Set `Cache-Control: no-cache`
- No Cloudflare validation (gray cloud endpoint)

**Endpoint 3: `GET /api/quote` (API - Proxied)**
- Return random quote as JSON
- Set `Cache-Control: public, max-age=300`
- Validate `X-Cloudflare-Secret` header

**Endpoint 4: `GET /static/*` (Static files - Proxied)**
- Serve static assets
- Set `Cache-Control: public, max-age=3600`

**Application Requirements:**
- [ ] Connection pooling for PostgreSQL
- [ ] Load database credentials from environment variables
- [ ] Structured logging (JSON format)
- [ ] Graceful shutdown handling
- [ ] Security header validation for proxied endpoints

**Acceptance Criteria:**
- All endpoints functional
- Database connection works
- Security headers validated
- Proper cache headers set

---

### 2.2 Container Build

**Tasks:**
- [ ] Create Dockerfile:
  - Multi-stage build
  - Run as non-root user
  - Include health check
  - Minimize image size
- [ ] Build and push to Artifact Registry or GHCR
- [ ] Tag with commit SHA and `latest`

**Acceptance Criteria:**
- Image builds successfully
- Runs as non-root
- Health check functional
- Stored in registry

---

### 2.3 Cloud Run Deployment

**Configuration Requirements:**

**Execution Environment:**
- [ ] Generation 2 (Gen2)

**Networking:**
- [ ] Direct VPC Egress enabled
- [ ] Connect to VPC and subnet
- [ ] Egress: `PRIVATE_RANGES_ONLY`
- [ ] Ingress: `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER`

**Scaling:**
- [ ] Min instances: 1 (no cold starts)
- [ ] Max instances: 10
- [ ] Concurrency: 80

**Resources:**
- [ ] CPU: 1
- [ ] Memory: 512Mi
- [ ] CPU idle: true
- [ ] Startup CPU boost: true

**Environment Variables (from Secret Manager):**
- [ ] `DB_HOST` (internal IP of VM)
- [ ] `DB_USER` (from secret)
- [ ] `DB_PASSWORD` (from secret)
- [ ] `CLOUDFLARE_SECRET` (from secret)

**IAM:**
- [ ] Service account with:
  - `roles/secretmanager.secretAccessor`
  - `roles/logging.logWriter`
  - `roles/monitoring.metricWriter`

**Terraform Module:** `modules/cloud-run/`

**Acceptance Criteria:**
- Service deployed with Gen2
- Min 1 instance running
- Can connect to PostgreSQL
- Secrets injected properly
- Internal ingress configured

---

## Part 3: Cloudflare Configuration

### 3.1 DNS Records

**Tasks:**
- [ ] Configure DNS records via Cloudflare API:

**Record 1: Proxied (Orange Cloud)**
```
Type: CNAME
Name: api
Target: [cloud-run-url]
Proxied: true (orange cloud)
TTL: Auto
```

**Record 2: DNS-only (Gray Cloud)**
```
Type: CNAME
Name: health.api
Target: [cloud-run-url]
Proxied: false (gray cloud)
TTL: Auto
```

**Implementation:**
- [ ] Use Cloudflare Terraform provider OR
- [ ] Script using Cloudflare API with token
- [ ] Store API token as GitHub secret

**Terraform Module:** `modules/cloudflare/`

**Acceptance Criteria:**
- api.avodzis.online → proxied through Cloudflare
- health.api.avodzis.online → direct to Cloud Run
- DNS propagated and working

---

### 3.2 WAF Security Rules

**Tasks:**
Create WAF rules in Cloudflare:

**Rule 1: Geo-Restriction**
- [ ] Allow only Spain (ES) and Armenia (AM)
- [ ] Block all other countries
- [ ] Apply to `api.avodzis.online`

**Expression:**
```
(http.host eq "api.avodzis.online" and ip.geoip.country ne "ES" and ip.geoip.country ne "AM")
```
**Action:** Block

**Rule 2: Rate Limiting**
- [ ] Limit: 100 requests per minute per IP
- [ ] Apply to all paths
- [ ] Action: Block with 429 status

**Rule 3: SQL Injection Protection**
- [ ] Enable Cloudflare OWASP Core Ruleset
- [ ] Action: Block

**Rule 4: Bot Protection**
- [ ] Challenge requests with bot score < 30
- [ ] Action: Managed Challenge

**Acceptance Criteria:**
- Geo-restriction enforced
- Rate limiting active
- SQL injection patterns blocked
- Bot protection enabled

---

### 3.3 Cache Rules

**Tasks:**
Configure caching via Cloudflare:

**Rule 1: Static Assets**
- [ ] Match: `http.request.uri.path matches "^/static/.*"`
- [ ] Cache TTL: 3600 seconds (1 hour)
- [ ] Browser TTL: 1800 seconds
- [ ] Cache everything

**Rule 2: API Responses (Cache-Control)**
- [ ] Match: `http.request.uri.path starts_with "/api/"`
- [ ] Respect Cache-Control headers from origin
- [ ] Edge Cache TTL: 300 seconds (5 minutes)

**Rule 3: Health Endpoint (No Cache)**
- [ ] Match: `http.request.uri.path eq "/health"`
- [ ] Cache: Bypass
- [ ] Set `Cache-Control: no-cache`

**Acceptance Criteria:**
- Static files cached for 1 hour
- API responses cached for 5 minutes
- Health endpoint never cached
- Cache headers properly set

---

## Part 4: CI/CD Pipeline

### 4.1 Cloud Run Service Manifests

**Tasks:**
Create Cloud Run service YAML files for each environment:

**File: `resources/dev/service.dev.yaml`**
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: lab-app-dev
  annotations:
    run.googleapis.com/ingress: internal-and-cloud-load-balancer
spec:
  template:
    metadata:
      annotations:
        run.googleapis.com/execution-environment: gen2
        autoscaling.knative.dev/minScale: '1'
        autoscaling.knative.dev/maxScale: '10'
    spec:
      serviceAccountName: SERVICE_ACCOUNT_EMAIL
      containerConcurrency: 80
      containers:
        - image: IMAGE_PLACEHOLDER
          ports:
            - containerPort: 8080
          env:
            - name: DB_HOST
              value: "10.0.1.10"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-user
                  key: latest
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-password
                  key: latest
            - name: CLOUDFLARE_SECRET
              valueFrom:
                secretKeyRef:
                  name: cloudflare-secret
                  key: latest
          resources:
            limits:
              cpu: '1'
              memory: 512Mi
      vpcAccess:
        egress: PRIVATE_RANGES_ONLY
        networkInterfaces:
          - network: projects/PROJECT_ID/global/networks/cloud-run-vpc
            subnetwork: projects/PROJECT_ID/regions/us-central1/subnetworks/cloud-run-subnet
```

**File: `resources/prod/service.prod.yaml`**
- [ ] Same structure as dev
- [ ] Update service name to `lab-app-prod`
- [ ] Adjust scaling parameters if needed
- [ ] Use production secrets

**Acceptance Criteria:**
- Cloud Run YAML files created for dev and prod
- Valid Knative Service specification
- VPC networking configured
- Secrets referenced correctly
- Min instances set to 1

---

### 4.2 Skaffold Configuration

**Tasks:**
Create `skaffold.yaml` with profiles and Cloud Run manifests:

**skaffold.yaml Structure:**
```yaml
apiVersion: skaffold/v4beta9
kind: Config
metadata:
  name: cloud-run-lab

build:
  artifacts:
    - image: IMAGE_PLACEHOLDER
      context: ./app
      docker:
        dockerfile: Dockerfile

profiles:
  - name: dev
    build:
      artifacts:
        - image: us-central1-docker.pkg.dev/PROJECT_ID/lab-repo/app-dev
          context: ./app
          docker:
            dockerfile: Dockerfile
      googleCloudBuild:
        projectId: PROJECT_ID
    manifests:
      rawYaml:
        - resources/dev/service.dev.yaml
    deploy:
      cloudrun:
        projectid: PROJECT_ID
        region: us-central1

  - name: prod
    build:
      artifacts:
        - image: us-central1-docker.pkg.dev/PROJECT_ID/lab-repo/app-prod
          context: ./app
          docker:
            dockerfile: Dockerfile
      googleCloudBuild:
        projectId: PROJECT_ID
    manifests:
      rawYaml:
        - resources/prod/service.prod.yaml
    deploy:
      cloudrun:
        projectid: PROJECT_ID
        region: us-central1
```

**Key Configuration:**
- [ ] `IMAGE_PLACEHOLDER` in Cloud Run YAML gets replaced by Skaffold
- [ ] `manifests.rawYaml` points to Cloud Run service YAML
- [ ] `deploy.cloudrun` handles deployment to Cloud Run
- [ ] Separate profiles for dev and prod
- [ ] Uses Google Cloud Build for building images

**Acceptance Criteria:**
- Skaffold config valid (`skaffold validate`)
- Image placeholder correctly replaced
- Cloud Run YAML properly referenced
- Profiles work independently

---

### 4.3 GitHub Actions Workflow

**Tasks:**
Create GitHub Actions workflow for automated deployments:

**File: `.github/workflows/deploy.yml`**
```yaml
name: Deploy to Cloud Run

on:
  push:
    branches:
      - develop
      - main
    paths:
      - 'app/**'
      - 'terraform/**'
      - 'resources/**'
      - 'skaffold.yaml'

jobs:
  deploy:
    permissions:
      contents: 'read'
      id-token: 'write'
      pull-requests: write
    runs-on: ubuntu-latest
    environment: ${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: 'google-github-actions/auth@v2'
        with:
          project_id: ${{ secrets.PROJECT_ID }}
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: 'google-github-actions/setup-gcloud@v2'
        with:
          version: '>= 500.0.0'

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: Deploy Infrastructure
        run: |
          cd terraform
          terraform init
          terraform apply -auto-approve -var-file=environments/${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}.tfvars

      - name: Install Skaffold
        run: |
          curl -L -o skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
          chmod +x ./skaffold
          sudo mv ./skaffold /usr/local/bin/skaffold

      - name: Deploy Application
        run: |
          skaffold run -p ${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}

      - name: Update Cloudflare DNS
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ZONE_ID: ${{ secrets.CLOUDFLARE_ZONE_ID }}
        run: |
          # Get Cloud Run URL
          SERVICE_URL=$(gcloud run services describe lab-app-${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }} \
            --region=us-central1 \
            --format='value(status.url)' | sed 's|https://||')
          
          # Update Cloudflare DNS via API
          curl -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${{ secrets.DNS_RECORD_ID }}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"CNAME\",\"name\":\"api\",\"content\":\"${SERVICE_URL}\",\"proxied\":true}"

      - name: Run Integration Tests
        run: |
          # Add integration tests here
          echo "Running integration tests..."
```

**Required GitHub Secrets:**
- [ ] `PROJECT_ID` - GCP Project ID
- [ ] `WIF_PROVIDER` - Workload Identity Federation provider
- [ ] `SERVICE_ACCOUNT` - Service account email for deployment
- [ ] `CLOUDFLARE_API_TOKEN` - Cloudflare API token
- [ ] `CLOUDFLARE_ZONE_ID` - Cloudflare zone ID
- [ ] `DNS_RECORD_ID` - Cloudflare DNS record ID

**GitHub Environments:**
- [ ] `dev` environment (for develop branch)
- [ ] `prod` environment (for main branch)

**Acceptance Criteria:**
- Workflow triggers on push to develop/main
- Uses correct profile based on branch
- Terraform runs before Skaffold
- Skaffold deploys using Cloud Run YAML
- Cloudflare DNS updated automatically
- Separate dev and prod deployments

---

### 4.4 Pull Request Validation

**Tasks:**
Create PR validation workflow:

**File: `.github/workflows/pr-check.yml`**
```yaml
name: PR Validation

on:
  pull_request:
    branches:
      - develop
      - main

jobs:
  validate:
    permissions:
      contents: 'read'
      id-token: 'write'
      pull-requests: write
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: 'google-github-actions/auth@v2'
        with:
          project_id: ${{ secrets.PROJECT_ID }}
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: 'google-github-actions/setup-gcloud@v2'

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Validate
        run: |
          cd terraform
          terraform init
          terraform validate
          terraform plan

      - name: Install Skaffold
        run: |
          curl -L -o skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
          chmod +x ./skaffold
          sudo mv ./skaffold /usr/local/bin/skaffold

      - name: Skaffold Build (no deploy)
        run: |
          skaffold build -p dev

      - name: Validate Cloud Run YAML
        run: |
          # Validate YAML syntax
          for file in resources/*/*.yaml; do
            echo "Validating $file"
            gcloud run services replace $file --dry-run || exit 1
          done
```

**Acceptance Criteria:**
- Runs on every PR
- Validates Terraform
- Builds Docker image (no deploy)
- Validates Cloud Run YAML files
- Comments results on PR

---

### 4.5 Local Development with Skaffold

**Tasks:**
Set up local development workflow:

**Command: `skaffold dev`**
```bash
# Start local development mode with hot reload
skaffold dev -p dev

# Skaffold will:
# 1. Build Docker image
# 2. Push to Artifact Registry
# 3. Deploy to Cloud Run using dev YAML
# 4. Stream logs
# 5. Watch for file changes
# 6. Auto-rebuild and redeploy on changes
```

**Command: `skaffold run`**
```bash
# One-time deployment to dev
skaffold run -p dev

# Deploy to production
skaffold run -p prod
```

**Command: `skaffold build`**
```bash
# Build only (no deploy)
skaffold build -p dev
```

**Command: `skaffold delete`**
```bash
# Clean up deployed resources
skaffold delete -p dev
```

**Developer Workflow:**
1. Make code changes in `app/`
2. Skaffold auto-detects changes
3. Rebuilds container
4. Updates Cloud Run service using YAML manifest
5. Shows logs in terminal
6. Repeat

**Acceptance Criteria:**
- `skaffold dev` works locally
- Hot reload functional
- Logs streaming correctly
- Can deploy with `skaffold run`
- Uses Cloud Run YAML manifests

---

### 4.2 Terraform Backend

**Tasks:**
- [ ] Create GCS bucket for Terraform state
- [ ] Enable versioning on bucket
- [ ] Configure backend in `versions.tf`:
```hcl
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "cloud-run-lab"
  }
}
```
- [ ] Add state locking

**Acceptance Criteria:**
- State stored in GCS
- Versioning enabled
- State locking configured

---

## Part 5: Observability

### 5.1 Cloud Monitoring Uptime Check

**Tasks:**
- [ ] Create uptime check monitoring `health.api.avodzis.online/health`
- [ ] Check interval: 1 minute
- [ ] Check from multiple regions
- [ ] Expect: HTTP 200 status

**Terraform Module:** `modules/monitoring/`

**Acceptance Criteria:**
- Uptime check configured
- Monitoring gray cloud endpoint (direct)
- Not proxied through Cloudflare

---

### 5.2 Alert Policies

**Tasks:**
Create two alert policies:

**Alert 1: High Error Rate**
- [ ] Metric: `run.googleapis.com/request_count` with `response_code_class=5xx`
- [ ] Condition: Error rate > 5% for 5 minutes
- [ ] Notification: Email
- [ ] Documentation: Link to runbook

**Alert 2: High Latency**
- [ ] Metric: `run.googleapis.com/request_latencies` (p95)
- [ ] Condition: p95 latency > 1000ms for 5 minutes
- [ ] Notification: Email
- [ ] Documentation: Link to runbook

**Thresholds:**
- **5xx Error Rate:** > 5%
- **p95 Latency:** > 1000ms

**Acceptance Criteria:**
- Both alerts configured
- Notifications working
- Documented in README.md

---

### 5.3 Structured Logging

**Tasks:**
- [ ] Application logs in JSON format
- [ ] Include fields:
  - timestamp
  - severity
  - request_id
  - user_ip
  - endpoint
  - latency
  - status_code
- [ ] Log to stdout (Cloud Run captures automatically)
- [ ] Use appropriate log levels (INFO, WARN, ERROR)

**Acceptance Criteria:**
- Logs in JSON format
- All required fields present
- Viewable in Cloud Logging

---

## Part 6: Security & Best Practices

### 6.1 IAM & Least Privilege

**Requirements:**
- [ ] Each service has dedicated service account
- [ ] Minimal permissions per service account:
  - Cloud Run SA: Secret Manager accessor only
  - Compute Engine SA: Logging + Monitoring only
  - GitHub Actions SA: Deployment permissions only
- [ ] No default service accounts used
- [ ] Document all IAM roles in README

**Acceptance Criteria:**
- Least-privilege principle followed
- Service accounts documented
- No overly permissive roles

---

### 6.2 Secret Management

**Requirements:**
- [ ] All secrets in Secret Manager (no hardcoded values)
- [ ] Secrets versioned
- [ ] Secrets rotated regularly (document rotation process)
- [ ] Access logged via Cloud Audit Logs

**Acceptance Criteria:**
- No secrets in code or Terraform state
- Rotation process documented
- Access auditable

---

### 6.3 Network Security

**Requirements:**
- [ ] Database has no public IP
- [ ] Cloud Run uses internal ingress
- [ ] VPC firewall rules deny-by-default
- [ ] Only necessary ports open (22 for IAP, 5432 for PostgreSQL)

**Acceptance Criteria:**
- Database not accessible from internet
- Firewall rules minimal
- Network diagram in README

---

## Part 7: Documentation & Cleanup

### 7.1 README.md Requirements

**Must Include:**
- [ ] Architecture diagram (ASCII art or image)
- [ ] Component descriptions
- [ ] Design decisions:
  - Why Direct VPC Egress?
  - Why gray cloud for health checks?
  - Why min 1 instance?
- [ ] Prerequisites (GCP project, Cloudflare account, domain)
- [ ] Deployment instructions:
  ```bash
  # Clone repo
  git clone https://github.com/yourusername/cloud-run-cloudflare-lab
  cd cloud-run-cloudflare-lab
  
  # Set GCP project
  export PROJECT_ID=your-project-id
  gcloud config set project $PROJECT_ID
  
  # Enable required APIs
  gcloud services enable run.googleapis.com \
    cloudbuild.googleapis.com \
    compute.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    iamcredentials.googleapis.com
  
  # Set up Workload Identity Federation for GitHub Actions
  # Follow: https://github.com/google-github-actions/auth#setup
  
  # Set up Terraform backend
  gsutil mb gs://${PROJECT_ID}-terraform-state
  gsutil versioning set on gs://${PROJECT_ID}-terraform-state
  
  # Configure GitHub secrets
  # - PROJECT_ID
  # - WIF_PROVIDER
  # - SERVICE_ACCOUNT
  # - CLOUDFLARE_API_TOKEN
  # - CLOUDFLARE_ZONE_ID
  # - DNS_RECORD_ID
  
  # Deploy via GitHub Actions
  # Push to develop branch for dev deployment
  git checkout -b develop
  git push origin develop
  
  # Or deploy manually with Skaffold
  skaffold run -p dev
  ```
- [ ] Access instructions:
  - How to access application
  - How to connect to database
  - How to view logs
- [ ] Destroy instructions:
  ```bash
  terraform destroy -auto-approve
  ```
- [ ] Cost estimation (Always Free tier usage)
- [ ] Rollback procedures

**Acceptance Criteria:**
- Complete documentation
- Clear instructions
- Diagrams included

---

### 7.2 Cleanup & Destroy

**Tasks:**
- [ ] Document all resources created
- [ ] Provide `terraform destroy` command
- [ ] Create cleanup script for non-Terraform resources
- [ ] Verify all resources deleted after destroy
- [ ] Document costs if resources left running

**Destroy Checklist:**
```bash
# 1. Terraform destroy
cd terraform/
terraform destroy -auto-approve

# 2. Manual cleanup (if any)
# - Delete Artifact Registry images
# - Delete Secret Manager secrets (if not in Terraform)
# - Delete logs (if needed)

# 3. Verify cleanup
gcloud projects get-iam-policy $PROJECT_ID
gcloud compute instances list
gcloud run services list
```

**Acceptance Criteria:**
- All resources cleanly destroyed
- No orphaned resources
- Cleanup documented

---

## Project Structure

```
cloud-run-cloudflare-lab/
├── README.md
├── .gitignore
├── skaffold.yaml                    # Skaffold configuration with profiles
│
├── .github/
│   └── workflows/
│       ├── deploy.yml               # Main deployment workflow
│       └── pr-check.yml             # PR validation workflow
│
├── resources/
│   ├── dev/
│   │   └── service.dev.yaml         # Cloud Run service manifest (dev)
│   └── prod/
│       └── service.prod.yaml        # Cloud Run service manifest (prod)
│
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   ├── provider.tf
│   │
│   ├── modules/
│   │   ├── networking/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── compute/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── files/
│   │   │       └── startup-script.sh
│   │   │
│   │   ├── artifact-registry/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── cloudflare/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   └── monitoring/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │
│   └── environments/
│       ├── dev.tfvars
│       └── prod.tfvars
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── gcp.yml
│   └── playbooks/
│       └── setup-postgres.yml
│
├── app/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── package.json (or requirements.txt, go.mod)
│   ├── server.js (or main.py, main.go)
│   ├── static/
│   │   ├── style.css
│   │   └── app.js
│   └── views/
│       └── index.html
│
│
└── docs/
    ├── ARCHITECTURE.md
    ├── DECISIONS.md
    ├── SKAFFOLD.md
    └── RUNBOOK.md
```

---

## Validation Checklist

### Infrastructure
- [ ] VPC and subnet created
- [ ] VM provisioned with internal IP only
- [ ] PostgreSQL running and accessible via IAP
- [ ] Cloud Run deployed and running
- [ ] Direct VPC Egress working
- [ ] Cloud Run can connect to PostgreSQL

### Cloudflare
- [ ] DNS records created (orange + gray cloud)
- [ ] WAF rules active and tested
- [ ] Geo-restriction working
- [ ] Rate limiting functional
- [ ] Caching rules working correctly

### Application
- [ ] All endpoints responding
- [ ] Database queries working
- [ ] Security headers validated
- [ ] Cache headers set correctly
- [ ] Structured logging working

### CI/CD
- [ ] Cloud Run YAML manifests created (dev/prod)
- [ ] Skaffold.yaml configured with rawYaml manifests
- [ ] GitHub Actions workflows set up
- [ ] Workload Identity Federation configured
- [ ] Terraform runs in workflow
- [ ] Skaffold deploys using Cloud Run YAML
- [ ] Cloudflare API calls successful
- [ ] `skaffold dev` works locally
- [ ] `skaffold run -p dev` deploys successfully
- [ ] `skaffold run -p prod` deploys successfully

### Monitoring
- [ ] Uptime check configured
- [ ] 5xx alert policy active
- [ ] Latency alert policy active
- [ ] Logs visible in Cloud Logging

### Security
- [ ] IAM roles minimal and documented
- [ ] Secrets in Secret Manager
- [ ] No hardcoded credentials
- [ ] Firewall rules deny-by-default

### Documentation
- [ ] README.md complete
- [ ] Architecture diagram included
- [ ] Deployment steps clear
- [ ] Cleanup instructions provided

---

## Testing Procedures

### Test 1: Application Functionality
```bash
# Test proxied endpoint
curl https://api.avodzis.online/

# Test health check (direct)
curl https://health.api.avodzis.online/health

# Test API endpoint
curl https://api.avodzis.online/api/quote

# Verify caching
curl -I https://api.avodzis.online/api/quote | grep -i cache
```

### Test 2: Geo-Restriction
```bash
# Use VPN to test from blocked country
# Should receive 403 Forbidden

# Test from Spain or Armenia
# Should receive 200 OK
```

### Test 3: Rate Limiting
```bash
# Send 101 requests in 1 minute
for i in {1..101}; do curl https://api.avodzis.online/; done

# Request 101 should return 429
```

### Test 4: Database Connectivity
```bash
# Connect via IAP tunnel
gcloud compute start-iap-tunnel postgres-vm 5432 \
  --local-host-port=localhost:5432 \
  --zone=us-central1-a

# Query database
psql -h localhost -p 5432 -U labuser -d labdb -c "SELECT * FROM quotes;"
```

### Test 5: Security Headers
```bash
# Attempt to access without secret header
curl https://api.avodzis.online/ \
  -H "X-Cloudflare-Secret: wrong-secret"

# Should return 403
```

---

## Estimated Costs

**Always Free Tier (Monthly):**
- Compute Engine e2-micro: $0 (Always Free in us-central1)
- Cloud Run: $0 (2 million requests free)
- Cloud Monitoring: $0 (within free tier)
- Secret Manager: $0 (6 secrets < free tier)
- Cloudflare Free: $0

**Potential Charges:**
- Artifact Registry storage: ~$0.10/GB/month
- Cloud Run egress (if high traffic): Variable
- GCS Terraform state: ~$0.02/month

**Total Estimated Monthly Cost: < $1**

---

## Success Criteria

You have successfully completed this lab when:

1. ✅ All infrastructure deployed via Terraform
2. ✅ Application accessible via custom domain
3. ✅ Cloudflare proxying and security working
4. ✅ Database connectivity functional
5. ✅ Monitoring and alerts configured
6. ✅ CI/CD pipeline operational
7. ✅ All security best practices implemented
8. ✅ Complete documentation provided
9. ✅ Clean destroy process works

---

## Bonus Challenges (Optional)

### Bonus 1: Multi-Region Deployment
- [ ] Deploy Cloud Run to 3 regions
- [ ] Use Global Load Balancer
- [ ] Test failover

### Bonus 2: Terraform Modules
- [ ] Publish modules to Terraform Registry
- [ ] Version modules
- [ ] Use in multiple environments

### Bonus 3: Advanced Monitoring
- [ ] Set up Cloud Trace
- [ ] Create custom dashboards
- [ ] Implement SLO monitoring

### Bonus 4: Blue/Green Deployment
- [ ] Implement traffic splitting
- [ ] Automated rollback on errors
- [ ] Canary deployments

---

## Resources

### Documentation
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Cloudflare Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)

### Tutorials
- [Cloud Run VPC Access](https://cloud.google.com/run/docs/configuring/vpc-direct-vpc)
- [Cloudflare Security Rules](https://developers.cloudflare.com/waf/)
- [GitHub Actions with GCP](https://cloud.google.com/blog/products/devops-sre/deploy-to-cloud-run-with-github-actions)

---

## Submission

When complete, provide:
1. GitHub repository URL
2. Live application URL
3. Screenshots of:
   - Application running
   - Cloudflare dashboard (DNS, WAF, Cache)
   - Cloud Monitoring (uptime check, alerts)
   - Successful Terraform apply
4. Brief write-up (500 words) on challenges faced and solutions

---

**Good luck! 🚀**