# Athena Finance - Project Structure

## Overview
Clean, organized structure for the Athena Finance platform with enhanced banking features.

## Directory Structure

```
athena-001/
├── README.md                    # Main project documentation
├── CLAUDE.md                    # AI assistant instructions
├── deploy.sh                    # Main deployment orchestrator
├── package.json                 # Node.js dependencies
├── tsconfig.json               # TypeScript configuration
├── jest.config.js              # Jest testing configuration
│
├── docs/                       # Documentation
│   ├── PRD.md                  # Product Requirements Document
│   ├── IMPLEMENTATION_PLAN.md  # Technical implementation guide
│   ├── OPEN_BANKING_PLAN.md   # Open banking integration plan
│   ├── CICD.md                 # CI/CD documentation
│   └── planAgentX.md           # Agent architecture plan
│
├── infrastructure/             # Terraform infrastructure
│   └── terraform/
│       ├── backend.tf          # Terraform backend config
│       ├── apis.tf             # API enablement
│       ├── banking-service.tf  # Banking service resources
│       ├── security.tf         # Security policies
│       ├── monitoring.tf       # Monitoring setup
│       ├── gdpr-storage.tf     # GDPR compliance storage
│       ├── github-wif.tf       # GitHub Workload Identity
│       └── cloudbuild-bucket.tf # Cloud Build configuration
│
├── src/                        # Source code
│   ├── auth-service/           # Authentication service
│   ├── banking-service/        # Enhanced banking service
│   ├── finance-master/         # Financial orchestration
│   ├── transaction-analyzer/   # Transaction analysis
│   ├── insight-generator/      # Financial insights
│   └── document-ai/            # Document processing
│
├── services/                   # Shared service code
│   └── shared/
│       ├── auth/               # Auth utilities
│       ├── gdpr/               # GDPR compliance
│       ├── models/             # Data models
│       └── monitoring.ts       # Monitoring utilities
│
├── scripts/                    # Automation scripts
│   ├── setup.sh               # Initial setup
│   ├── setup-cicd.sh          # CI/CD setup
│   ├── setup-banking-secrets.sh # Banking secrets setup
│   ├── deployment/            # Deployment scripts
│   │   ├── deploy-complete.sh
│   │   ├── deploy-monitoring.sh
│   │   ├── deploy-services.sh
│   │   ├── quick-deploy.sh
│   │   └── rollback.sh
│   ├── setup/                 # Setup utilities
│   │   ├── setup-github-wif.sh
│   │   └── setup-github-secrets.sh
│   └── testing/               # Test scripts
│       ├── test-auth.sh
│       ├── test-banking.sh
│       ├── test-banking-deployed.sh
│       ├── test-banking-connection.sh
│       ├── test-deployment.sh
│       ├── test-finance-with-auth.sh
│       ├── test-gdpr.sh
│       ├── test-monitoring.sh
│       ├── test-real-bank-connection.sh
│       ├── validate-deployment.sh
│       └── verify-security.sh
│
├── config/                    # Configuration files
│   ├── docker-compose.yml     # Local development
│   ├── cloudbuild.yaml        # Cloud Build config
│   ├── cloudbuild-auth.yaml   # Auth service build
│   └── cloudbuild-generic.yaml # Generic service build
│
├── keys/                      # Local keys (gitignored)
├── node_modules/             # Dependencies (gitignored)
├── GITHUB_SETUP.md           # GitHub setup instructions
└── GOCARDLESS_SETUP.md       # GoCardless setup guide
```

## Key Services

### 1. Banking Service (Enhanced)
- ML-powered transaction categorization
- Subscription detection
- Business expense tracking
- Invoice linking
- GoCardless integration

### 2. Authentication Service
- JWT-based authentication
- OAuth ready structure
- GDPR compliant

### 3. Finance Master
- Account management
- Transaction orchestration
- Financial insights

## Scripts Organization

### Setup Scripts
- `setup.sh` - Initial project setup
- `setup-cicd.sh` - Configure CI/CD
- `setup-banking-secrets.sh` - Banking API credentials

### Deployment Scripts
- `deploy.sh` - Main orchestrator
- `deployment/deploy-complete.sh` - Full deployment
- `deployment/quick-deploy.sh` - Services only
- `deployment/rollback.sh` - Rollback mechanism

### Testing Scripts
- `test-banking.sh` - Local banking tests
- `test-banking-deployed.sh` - Production tests
- `test-auth.sh` - Authentication tests
- `validate-deployment.sh` - Full validation

## Clean Code Practices

1. **No Duplicate Files** - Each script has a specific purpose
2. **Clear Naming** - Self-documenting file names
3. **Organized Structure** - Logical grouping by function
4. **Documentation** - Key docs in docs/ folder
5. **Separation of Concerns** - Infrastructure, code, and scripts separated

## Next Steps

1. Add GoCardless credentials:
   ```bash
   ./scripts/setup-banking-secrets.sh
   ```

2. Deploy to production:
   ```bash
   ./deploy.sh
   ```

3. Run tests:
   ```bash
   ./scripts/testing/test-banking-deployed.sh
   ```