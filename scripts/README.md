# Athena Finance Scripts

This directory contains automation scripts for setup, deployment, and testing.

## Directory Structure

```
scripts/
├── setup.sh                 # Initial project setup
├── setup-cicd.sh           # Configure CI/CD pipeline
├── setup-banking-secrets.sh # Setup GoCardless credentials
├── deployment/             # Deployment automation
├── setup/                  # Setup utilities
└── testing/                # Test suites
```

## Quick Start

### 1. Initial Setup
```bash
./setup.sh
```

### 2. Configure Banking
```bash
./setup-banking-secrets.sh
```

### 3. Deploy Services
```bash
# Full deployment (infrastructure + services)
../deploy.sh

# Quick deployment (services only)
../deploy.sh quick
```

### 4. Run Tests
```bash
# Test local services
./testing/test-banking.sh

# Test deployed services
./testing/test-banking-deployed.sh <BANKING_URL>
```

## Script Categories

### Setup Scripts
- `setup.sh` - Install dependencies, configure project
- `setup-cicd.sh` - Configure GitHub Actions and Cloud Build
- `setup-banking-secrets.sh` - Add GoCardless API credentials

### Deployment Scripts
- `deployment/deploy-complete.sh` - Deploy infrastructure + services
- `deployment/deploy-services.sh` - Deploy services only
- `deployment/deploy-monitoring.sh` - Setup monitoring
- `deployment/quick-deploy.sh` - Fast service deployment
- `deployment/rollback.sh` - Rollback to previous version

### Testing Scripts
- `testing/test-auth.sh` - Authentication service tests
- `testing/test-banking.sh` - Banking service tests (local)
- `testing/test-banking-deployed.sh` - Banking service tests (production)
- `testing/test-banking-connection.sh` - Bank connection flow
- `testing/test-gdpr.sh` - GDPR compliance tests
- `testing/test-monitoring.sh` - Monitoring and alerts
- `testing/validate-deployment.sh` - Full deployment validation
- `testing/verify-security.sh` - Security configuration

### Setup Utilities
- `setup/setup-github-wif.sh` - Configure Workload Identity
- `setup/setup-github-secrets.sh` - Add GitHub secrets

## Usage Examples

### Deploy to Production
```bash
# From project root
./deploy.sh

# Or directly
cd scripts/deployment
./deploy-complete.sh
```

### Test Banking Features
```bash
# Start local services
npm run dev:auth &
npm run dev:banking &

# Run tests
./testing/test-banking.sh

# Test production
./testing/test-banking-deployed.sh https://banking-service-xyz.run.app
```

### Rollback Deployment
```bash
./deployment/rollback.sh banking-service
```

## Environment Variables

### Required for Banking Service
- `GOCARDLESS_SECRET_ID` - GoCardless API secret ID
- `GOCARDLESS_SECRET_KEY` - GoCardless API secret key
- `JWT_ACCESS_SECRET` - JWT access token secret
- `JWT_REFRESH_SECRET` - JWT refresh token secret

### ML Categorization
- `ENABLE_ML_CATEGORIZATION` - Enable ML features (true/false)
- `GCP_PROJECT_ID` - GCP project ID
- `VERTEX_AI_LOCATION` - Vertex AI region

## Best Practices

1. Always run `setup.sh` first on a new machine
2. Use `deploy.sh` from root for orchestrated deployments
3. Run tests after each deployment
4. Keep secrets in Secret Manager, never in code
5. Use rollback.sh if deployment issues occur

## Troubleshooting

### Banking Service Issues
- Check logs: `gcloud run logs read --service=banking-service`
- Verify GoCardless credentials in Secret Manager
- Ensure Firestore indexes are created

### Authentication Errors
- Verify JWT secrets match between services
- Check CORS configuration
- Ensure auth service is deployed

### ML Categorization Not Working
- Check Vertex AI API is enabled
- Verify service account has aiplatform.user role
- Check logs for Vertex AI errors