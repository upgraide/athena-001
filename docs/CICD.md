# CI/CD Pipeline Documentation

## Overview

The Athena Finance platform uses GitHub Actions for continuous integration and deployment, with Google Cloud Build for container building and Cloud Run for hosting services.

## Architecture

### Pipeline Flow
1. **CI Pipeline** - Runs on every push and PR
   - Code quality checks (lint, format, typecheck)
   - Security scanning
   - Unit and integration tests
   - Docker image building
   - Terraform validation

2. **CD Pipeline** - Deploys to environments
   - Staging: Auto-deploy on merge to main
   - Production: Manual approval required
   - Canary deployments with gradual traffic rollout
   - Automated rollback on failure

## Setup Instructions

### 1. Enable Workload Identity Federation

Run the setup script to enable keyless authentication:

```bash
./scripts/setup/setup-github-wif.sh
```

This creates:
- Workload Identity Pool for GitHub
- Service Account with necessary permissions
- Identity binding for your repository

### 2. Configure GitHub Secrets

Add these secrets to your GitHub repository:

```
WIF_PROVIDER: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
WIF_SERVICE_ACCOUNT: github-actions-sa@athena-finance-001.iam.gserviceaccount.com
```

For production environment:
```
WIF_PROVIDER_PROD: (same as above)
WIF_SERVICE_ACCOUNT_PROD: github-actions-prod-sa@athena-finance-001.iam.gserviceaccount.com
```

### 3. Repository Structure

```
.github/workflows/
├── ci.yml              # Continuous Integration
└── cd.yml              # Continuous Deployment

config/
├── cloudbuild.yaml     # Cloud Build for services
└── cloudbuild-auth.yaml # Cloud Build for auth service

scripts/
├── deploy-services.sh   # Local deployment script
├── deployment/
│   ├── deploy-services.sh # Enhanced deployment
│   └── rollback.sh      # Rollback script
└── testing/
    ├── validate-deployment.sh # Health checks
    └── test-monitoring.sh    # Monitoring validation
```

## Workflows

### CI Pipeline (ci.yml)

Triggers on:
- Push to main, develop, staging branches
- Pull requests to main

Jobs:
1. **quality** - Linting, formatting, type checking
2. **test** - Unit tests with coverage
3. **build** - Docker image building and pushing
4. **terraform** - Infrastructure validation

### CD Pipeline (cd.yml)

Triggers on:
- Push to main (auto-deploy to staging)
- Manual workflow dispatch (for production)

Jobs:
1. **deploy-staging** - Automatic staging deployment
2. **deploy-production** - Manual production deployment with canary
3. **rollback** - Automatic rollback on failure

## Deployment Process

### Staging Deployment
1. Merge PR to main branch
2. CI pipeline builds and pushes images
3. CD pipeline deploys to staging automatically
4. Validation tests run
5. Monitoring alerts configured

### Production Deployment
1. Manual trigger from GitHub Actions
2. Creates Firestore backup
3. Deploys with 10% canary traffic
4. Monitors for 5 minutes
5. Gradual rollout to 100%
6. Full validation suite

### Rollback Process
1. Automatic trigger on deployment failure
2. Identifies previous stable revision
3. Routes 100% traffic to previous version
4. Validates service health
5. Sends monitoring alerts

## Service Configuration

Each service has specific resource allocations:

| Service | Memory | CPU | Min Instances | Max Instances |
|---------|--------|-----|---------------|---------------|
| auth-service | 512Mi | 1 | 0 | 10 |
| finance-master | 768Mi | 1 | 0 | 10 |
| document-ai | 1Gi | 2 | 0 | 5 |
| transaction-analyzer | 512Mi | 1 | 0 | 8 |
| insight-generator | 512Mi | 1 | 0 | 5 |

Production environments use:
- 2x memory allocation
- Minimum 2 instances
- VPC connector for security
- JWT secrets from Secret Manager

## Monitoring Integration

The CI/CD pipeline integrates with monitoring:

1. **Deployment Markers** - Tracked in dashboards
2. **Health Checks** - Validated after deployment
3. **Rollback Events** - Logged and alerted
4. **Performance Metrics** - Canary comparison

## Security Features

1. **Workload Identity** - No service account keys
2. **VPC Connectivity** - Private communication
3. **Secret Management** - Google Secret Manager
4. **Image Scanning** - Vulnerability detection
5. **Least Privilege** - Minimal IAM permissions

## Local Development

For local deployment:

```bash
# Deploy all services
./scripts/deploy-services.sh

# Deploy specific service
gcloud builds submit --config=config/cloudbuild.yaml \
  --substitutions=SERVICE_NAME=finance-master

# Validate deployment
./scripts/testing/validate-deployment.sh
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Verify WIF setup: `gcloud iam workload-identity-pools list`
   - Check service account permissions

2. **Build Failures**
   - Check Cloud Build logs: `gcloud builds list`
   - Verify Dockerfile syntax

3. **Deployment Failures**
   - Check Cloud Run logs: `gcloud run services logs SERVICE_NAME`
   - Verify health endpoints

4. **Rollback Issues**
   - Ensure previous revision exists
   - Check traffic allocation

### Debug Commands

```bash
# List current revisions
gcloud run revisions list --service=SERVICE_NAME --region=europe-west3

# Check traffic allocation
gcloud run services describe SERVICE_NAME --region=europe-west3

# View deployment logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50

# Test health endpoint
curl https://SERVICE_URL/health
```

## Best Practices

1. **Always test in staging first**
2. **Use canary deployments for production**
3. **Monitor metrics during deployment**
4. **Keep rollback scripts updated**
5. **Document deployment decisions**
6. **Review security permissions regularly**

## Future Enhancements

1. **Blue/Green Deployments** - Zero-downtime deployments
2. **Feature Flags** - Gradual feature rollout
3. **A/B Testing** - Traffic splitting for experiments
4. **Multi-Region** - Geographic redundancy
5. **GitOps** - Declarative deployments with ArgoCD