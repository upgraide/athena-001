# Athena Finance - Secure AI-Powered Finance Automation

A secure, GDPR-compliant microservices architecture for AI-powered finance automation, built on Google Cloud Platform.

## 🎯 Project Status: Phase 1 Complete ✅

### ✅ Completed Features
- **Secure Infrastructure**: KMS encryption, VPC networking, service accounts
- **Microservice Framework**: SecureMicroservice base class with encryption
- **Container Architecture**: Docker with linux/amd64 platform compatibility
- **Cloud Deployment**: Automated deployment to Google Cloud Run
- **Security Headers**: CSP, HSTS, and comprehensive security headers
- **Health Monitoring**: Health check endpoints and verification scripts
- **JWT Authentication**: Complete auth system with registration, login, and protected endpoints
- **Secret Management**: JWT secrets stored in Google Secret Manager
- **Monitoring & Alerts**: Prometheus metrics, Cloud Monitoring dashboards, and alert policies
- **Custom Metrics**: Business event tracking and performance monitoring
- **Log-based Alerts**: Authentication failures and error tracking

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Auth Service  │    │ Finance Master  │    │ Document AI     │
│  (JWT/OAuth)    │    │  Microservice   │    │ Microservice    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
         ┌─────────────────┐    │    ┌─────────────────┐
         │ Transaction     │    │    │ Secure Base     │
         │ Analyzer        │    │    │ Framework       │
         └─────────────────┘    │    └─────────────────┘
                                │
    ┌─────────────────────────────────────────────────────┐
    │            Secure Infrastructure                    │
    │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │
    │  │   KMS   │ │   VPC   │ │ Secret  │ │Firestore│  │
    │  │Encryption│ │Network  │ │Manager  │ │Database │  │
    │  └─────────┘ └─────────┘ └─────────┘ └─────────┘  │
    └─────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Google Cloud CLI (`gcloud`) configured
- Docker installed
- Node.js 18+ and npm
- Terraform 1.5+

### Deployment

```bash
# Full deployment (infrastructure + services)
./deploy.sh

# Quick service deployment only
./deploy.sh quick

# Verify deployment
./deploy.sh verify
```

## 📁 Project Structure

```
athena-001/
├── src/                          # Source code
│   ├── auth-service/             # Authentication service
│   ├── finance-master/           # Main finance service
│   ├── document-ai/              # Document processing
│   ├── transaction-analyzer/     # Transaction analysis
│   └── insight-generator/        # Financial insights
├── services/shared/              # Shared utilities
│   ├── secure-base.ts           # Security framework
│   ├── auth/                    # JWT, middleware, password utils
│   └── models/                  # Data models
├── infrastructure/terraform/     # Infrastructure as Code
│   ├── security.tf              # Security resources
│   └── backend.tf               # Terraform backend
├── scripts/
│   ├── deployment/              # Deployment scripts
│   └── testing/                 # Testing & verification
├── config/                      # Configuration files
├── docs/                        # Documentation
└── deploy.sh                    # Main deployment script
```

## 🔐 Security Features

- **Encryption at Rest**: All data encrypted with Google Cloud KMS
- **Network Security**: Private VPC with controlled egress
- **Identity & Access**: Service accounts with minimal permissions
- **Security Headers**: Comprehensive HTTP security headers
- **Audit Logging**: All operations logged for compliance
- **Container Security**: Non-root user, minimal attack surface
- **JWT Authentication**: Secure token-based authentication
- **Password Security**: Bcrypt hashing with strong requirements
- **Rate Limiting**: IP-based rate limiting on all endpoints
- **Security Monitoring**: Real-time alerts for authentication failures and suspicious activity

## 🌍 GDPR Compliance

- **Data Residency**: All data stored in EU regions (europe-west3)
- **Encryption**: End-to-end encryption with key rotation
- **Access Controls**: Role-based access with audit trails
- **Data Protection**: Point-in-time recovery enabled

## 📊 Service Endpoints

### Authentication Service
- **Register**: `POST /api/v1/auth/register`
- **Login**: `POST /api/v1/auth/login`
- **Refresh Token**: `POST /api/v1/auth/refresh`
- **Get Profile**: `GET /api/v1/auth/me` (protected)
- **Update Profile**: `PATCH /api/v1/auth/profile` (protected)
- **Logout**: `POST /api/v1/auth/logout` (protected)

### Finance Master Service (All Protected)
- **Health Check**: `GET /health`
- **Account Management**: `POST /api/v1/accounts`
- **Transaction Processing**: `POST /api/v1/transactions/categorize`
- **Document Processing**: `POST /api/v1/documents/process`
- **Insights Generation**: `GET /api/v1/insights`

## 🛠️ Development

### Local Development
```bash
npm install
npm run build
npm run dev
```

### Testing
```bash
# Run verification
./scripts/testing/verify-security.sh

# Test authentication
./scripts/testing/test-auth.sh

# Test monitoring and alerts
./scripts/testing/test-monitoring.sh

# Test deployment locally
./scripts/testing/test-deployment.sh
```

### Infrastructure Management
```bash
cd infrastructure/terraform
terraform plan
terraform apply
```

## 📋 Next Development Steps

1. ~~**Authentication System**: Implement OAuth 2.0 / JWT authentication~~ ✅ COMPLETE
2. ~~**Monitoring & Alerts**: Set up Cloud Monitoring and alerting~~ ✅ COMPLETE
3. **CI/CD Pipeline**: Implement automated testing and deployment
4. **Load Testing**: Configure for 1000 RPS target
5. **Security Scanning**: Implement automated security scans
6. **Google OAuth**: Add Google OAuth integration
7. **Email Verification**: Implement email verification flow

## 🔧 Configuration

Key configuration files:
- `config/cloudbuild.yaml`: Cloud Build configuration
- `infrastructure/terraform/`: Infrastructure definitions
- `package.json`: Dependencies and scripts
- `.env.example`: Environment variables template

## 📖 Documentation

- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)
- [Product Requirements](docs/PRD.md)
- [Development Notes](docs/planAgentX.md)

## 🤝 Contributing

This project follows secure development practices:
1. All code changes require security review
2. Infrastructure changes must be tested
3. Follow the established patterns in SecureMicroservice base class

## 📄 License

Private - Athena Finance Team

---

**Built with security and compliance at the core** 🔒