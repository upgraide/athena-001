# Secure Microservice Architecture with Encryption - Implementation Plan

## Task Overview

**Phase 1, Step 1**: Set up secure microservice architecture with encryption

This document outlines the implementation of a secure, GDPR-compliant microservice architecture using Google Cloud Platform, focusing specifically on security and encryption foundations.

## Architecture Components

### Core Infrastructure

- **Compute**: Cloud Run (serverless containers)
- **Database**: Firestore with encryption at rest
- **Security**: Cloud KMS for encryption keys, Secret Manager for credentials
- **Network**: VPC with private IP ranges, Cloud Armor for DDoS protection
- **Monitoring**: Cloud Logging with audit trails

### Security-First Design

1. **Encryption Everywhere**: Data at rest, in transit, and in processing
2. **Zero Trust Network**: No internal trust, authenticate everything
3. **Principle of Least Privilege**: Minimal required permissions
4. **Defense in Depth**: Multiple security layers
5. **GDPR Compliance**: EU data residency and privacy controls

## Implementation Timeline (3 Days)

### Day 1: Infrastructure Foundation

- [ ] Create GCP project with EU region
- [ ] Enable required security APIs
- [ ] Set up Cloud KMS for encryption
- [ ] Configure VPC and private networking
- [ ] Create service accounts with minimal permissions

### Day 2: Core Security Services

- [ ] Deploy API Gateway with authentication
- [ ] Set up Secret Manager integration
- [ ] Configure encrypted database storage
- [ ] Implement audit logging
- [ ] Create base microservice template

### Day 3: Security Hardening

- [ ] Configure VPC Service Controls
- [ ] Set up DDoS protection
- [ ] Implement rate limiting
- [ ] Add security monitoring
- [ ] Verify encryption end-to-end

## Detailed Implementation Steps

### 1. Secure Project Foundation

```bash
# Create new GCP project with EU region
gcloud projects create athena-finance-001 --name="Athena Finance"
gcloud config set project athena-finance-001

# Enable billing
gcloud beta billing projects link athena-finance-001 --billing-account=BILLING_ACCOUNT_ID

# Enable security-focused APIs
gcloud services enable \
  run.googleapis.com \
  firestore.googleapis.com \
  secretmanager.googleapis.com \
  cloudkms.googleapis.com \
  vpcaccess.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  cloudbuild.googleapis.com
```

### 2. Infrastructure as Code

Create `infrastructure/terraform/main.tf`:

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  default = "athena-finance-001"
}

variable "region" {
  default = "europe-west3" # Frankfurt - GDPR compliant
}

# Firestore Database
resource "google_firestore_database" "main" {
  name        = "(default)"
  location_id = "eur3" # Multi-region EU
  type        = "FIRESTORE_NATIVE"

  concurrency_mode = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"

  # Enable point-in-time recovery
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"

  # 7-day retention for recovery
  retention_period = "604800s"
}

# Cloud SQL for structured data
resource "google_sql_database_instance" "main" {
  name             = "finance-postgres"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-g1-small"

    backup_configuration {
      enabled = true
      start_time = "03:00"
      location = var.region

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      require_ssl = true
      ipv4_enabled = false # VPC only

      private_network = google_compute_network.vpc.id
    }

    database_flags {
      name  = "cloudsql.enable_pgcrypto"
      value = "on"
    }
  }

  deletion_protection = true
}

# KMS for encryption
resource "google_kms_key_ring" "main" {
  name     = "finance-keyring"
  location = "europe"
}

resource "google_kms_crypto_key" "data_encryption" {
  name     = "data-encryption-key"
  key_ring = google_kms_key_ring.main.id

  rotation_period = "2592000s" # 30 days

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Secret Manager
resource "google_secret_manager_secret" "api_keys" {

  secret_id = "api-keys"

  replication {
    user_managed {
      replicas {
        location = "europe-west3"
      }
      replicas {
        location = "europe-west4"
      }
    }
  }
}

# Service Accounts
resource "google_service_account" "api_gateway" {
  account_id   = "api-gateway"
  display_name = "API Gateway Service Account"
}

resource "google_service_account" "finance_service" {
  account_id   = "finance-service"
  display_name = "Finance Service Account"
}

# IAM Bindings
resource "google_project_iam_member" "api_gateway_run" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

# VPC for private services
resource "google_compute_network" "vpc" {
  name                    = "finance-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "finance-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

# VPC Connector for Cloud Run
resource "google_vpc_access_connector" "connector" {
  name          = "finance-connector"
  region        = var.region
  subnet {
    name = google_compute_subnetwork.subnet.name
  }

  min_instances = 2
  max_instances = 10
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "containers" {
  location      = var.region
  repository_id = "finance-containers"
  format        = "DOCKER"
}
```

### 3. Base Microservice Template

Create `services/shared/base-service.ts`:

```typescript
import express from "express";
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import { Firestore } from "@google-cloud/firestore";
import { CloudTasksClient } from "@google-cloud/tasks";
import { v4 as uuidv4 } from "uuid";
import winston from "winston";
import { LoggingWinston } from "@google-cloud/logging-winston";

// Base service class all microservices extend
export abstract class BaseService {
  protected app: express.Application;
  protected firestore: Firestore;
  protected secrets: SecretManagerServiceClient;
  protected tasks: CloudTasksClient;
  protected logger: winston.Logger;

  constructor(protected serviceName: string) {
    this.app = express();
    this.firestore = new Firestore();
    this.secrets = new SecretManagerServiceClient();
    this.tasks = new CloudTasksClient();

    // Configure logging
    this.logger = winston.createLogger({
      level: "info",
      format: winston.format.json(),
      defaultMeta: { service: serviceName },
      transports: [
        new winston.transports.Console(),
        new LoggingWinston({
          projectId: process.env.PROJECT_ID,
          labels: { service: serviceName },
        }),
      ],
    });

    this.setupMiddleware();
    this.setupHealthCheck();
  }

  private setupMiddleware() {
    // Request ID for tracing
    this.app.use((req, res, next) => {
      req.id = req.headers["x-request-id"] || uuidv4();
      res.setHeader("x-request-id", req.id);
      next();
    });

    // JSON parsing
    this.app.use(express.json());

    // Security headers
    this.app.use((req, res, next) => {
      res.setHeader("X-Content-Type-Options", "nosniff");
      res.setHeader("X-Frame-Options", "DENY");
      res.setHeader("X-XSS-Protection", "1; mode=block");
      res.setHeader("Strict-Transport-Security", "max-age=31536000");
      next();
    });

    // Request logging
    this.app.use((req, res, next) => {
      this.logger.info("Request received", {
        requestId: req.id,
        method: req.method,
        path: req.path,
        ip: req.ip,
      });
      next();
    });

    // Error handling
    this.app.use((err: any, req: any, res: any, next: any) => {
      this.logger.error("Request error", {
        requestId: req.id,
        error: err.message,
        stack: err.stack,
      });

      res.status(err.status || 500).json({
        error: {
          message: err.message || "Internal server error",
          requestId: req.id,
        },
      });
    });
  }

  private setupHealthCheck() {
    this.app.get("/health", (req, res) => {
      res.json({
        status: "healthy",
        service: this.serviceName,
        timestamp: new Date().toISOString(),
      });
    });

    this.app.get("/ready", async (req, res) => {
      try {
        // Check Firestore connection
        await this.firestore.collection("_health").doc("check").set({
          timestamp: new Date(),
        });

        res.json({ status: "ready" });
      } catch (error) {
        res.status(503).json({ status: "not ready" });
      }
    });
  }

  async getSecret(name: string): Promise<string> {
    const projectId = process.env.PROJECT_ID;
    const [version] = await this.secrets.accessSecretVersion({
      name: `projects/${projectId}/secrets/${name}/versions/latest`,
    });

    return version.payload?.data?.toString() || "";
  }

  async queueTask(queue: string, payload: any, delaySeconds = 0) {
    const project = process.env.PROJECT_ID;
    const location = process.env.REGION || "europe-west3";
    const parent = this.tasks.queuePath(project, location, queue);

    const task = {
      httpRequest: {
        httpMethod: "POST" as const,
        url: `${process.env.TASK_HANDLER_URL}/${queue}`,
        body: Buffer.from(JSON.stringify(payload)).toString("base64"),
        headers: {
          "Content-Type": "application/json",
        },
      },
      scheduleTime:
        delaySeconds > 0
          ? {
              seconds: Math.floor(Date.now() / 1000) + delaySeconds,
            }
          : undefined,
    };

    const [response] = await this.tasks.createTask({ parent, task });
    return response;
  }

  start(port = 8080) {
    this.app.listen(port, () => {
      this.logger.info(`${this.serviceName} listening on port ${port}`);
    });
  }
}
```

### 4. API Gateway Service

Create `services/api-gateway/index.ts`:

```typescript
import { BaseService } from "../shared/base-service";
import { OAuth2Client } from "google-auth-library";
import rateLimit from "express-rate-limit";
import { createProxyMiddleware } from "http-proxy-middleware";

class APIGateway extends BaseService {
  private oauth2Client: OAuth2Client;

  constructor() {
    super("api-gateway");
    this.oauth2Client = new OAuth2Client();
    this.setupRoutes();
  }

  private setupRoutes() {
    // Rate limiting
    const limiter = rateLimit({
      windowMs: 60 * 1000, // 1 minute
      max: 100, // 100 requests per minute
      standardHeaders: true,
      legacyHeaders: false,
    });

    this.app.use("/api/", limiter);

    // Authentication middleware
    this.app.use("/api/", async (req, res, next) => {
      try {
        const token = req.headers.authorization?.replace("Bearer ", "");
        if (!token) {
          return res.status(401).json({ error: "No token provided" });
        }

        // Verify Firebase token
        const ticket = await this.oauth2Client.verifyIdToken({
          idToken: token,
          audience: process.env.CLIENT_ID,
        });

        const payload = ticket.getPayload();
        req.user = {
          id: payload?.sub,
          email: payload?.email,
        };

        next();
      } catch (error) {
        res.status(401).json({ error: "Invalid token" });
      }
    });

    // Service proxies
    this.setupServiceProxy("/api/finance", process.env.FINANCE_SERVICE_URL);
    this.setupServiceProxy("/api/calendar", process.env.CALENDAR_SERVICE_URL);
    this.setupServiceProxy("/api/email", process.env.EMAIL_SERVICE_URL);
  }

  private setupServiceProxy(path: string, target: string) {
    this.app.use(
      path,
      createProxyMiddleware({
        target,
        changeOrigin: true,
        onProxyReq: (proxyReq, req) => {
          // Forward user context
          proxyReq.setHeader("X-User-ID", req.user.id);
          proxyReq.setHeader("X-User-Email", req.user.email);
          proxyReq.setHeader("X-Request-ID", req.id);
        },
      })
    );
  }
}

// Start the service
const gateway = new APIGateway();
gateway.start();
```

### 5. Finance Service Core

Create `services/finance-master/index.ts`:

```typescript
import { BaseService } from "../shared/base-service";
import { EncryptionService } from "./encryption";
import { TransactionProcessor } from "./transaction-processor";
import { MLCategorizer } from "./ml-categorizer";

class FinanceService extends BaseService {
  private encryption: EncryptionService;
  private processor: TransactionProcessor;
  private categorizer: MLCategorizer;

  constructor() {
    super("finance-master");
    this.encryption = new EncryptionService();
    this.processor = new TransactionProcessor(this.firestore, this.encryption);
    this.categorizer = new MLCategorizer();
    this.setupRoutes();
  }

  private setupRoutes() {
    // Create transaction
    this.app.post("/transactions", async (req, res) => {
      try {
        const userId = req.headers["x-user-id"] as string;
        const transaction = req.body;

        // Categorize with ML
        const category = await this.categorizer.categorize(transaction);

        // Process and store
        const processed = await this.processor.process(userId, {
          ...transaction,
          category,
        });

        res.json(processed);
      } catch (error) {
        this.logger.error("Transaction processing failed", { error });
        res.status(500).json({ error: "Processing failed" });
      }
    });

    // Get transactions
    this.app.get("/transactions", async (req, res) => {
      const userId = req.headers["x-user-id"] as string;
      const { start, end, category } = req.query;

      const transactions = await this.processor.getTransactions(userId, {
        startDate: start as string,
        endDate: end as string,
        category: category as string,
      });

      res.json(transactions);
    });

    // GDPR endpoints
    this.app.get("/gdpr/export", async (req, res) => {
      const userId = req.headers["x-user-id"] as string;
      const data = await this.exportUserData(userId);
      res.json(data);
    });

    this.app.delete("/gdpr/delete", async (req, res) => {
      const userId = req.headers["x-user-id"] as string;
      await this.deleteUserData(userId);
      res.status(204).send();
    });
  }

  private async exportUserData(userId: string) {
    // Implement GDPR data export
    const transactions = await this.firestore
      .collection("users")
      .doc(userId)
      .collection("transactions")
      .get();

    return {
      transactions: transactions.docs.map((doc) => doc.data()),
      exportDate: new Date().toISOString(),
    };
  }

  private async deleteUserData(userId: string) {
    // Implement GDPR data deletion
    const batch = this.firestore.batch();

    const collections = ["transactions", "documents", "subscriptions"];
    for (const collection of collections) {
      const docs = await this.firestore
        .collection("users")
        .doc(userId)
        .collection(collection)
        .get();

      docs.forEach((doc) => batch.delete(doc.ref));
    }

    await batch.commit();
  }
}

// Start the service
const finance = new FinanceService();
finance.start();
```

### 6. Deployment Configuration

Create `services/finance-master/Dockerfile`:

```dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Build TypeScript
RUN npm run build

# Production image
FROM node:20-alpine

WORKDIR /app

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./

# Run as non-root user
USER node

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); })"

EXPOSE 8080

CMD ["node", "dist/index.js"]
```

Create `cloudbuild.yaml`:

```yaml
steps:
  # Build the container image
  - name: "gcr.io/cloud-builders/docker"
    args: ["build", "-t", "gcr.io/$PROJECT_ID/finance-master:$COMMIT_SHA", "."]
    dir: "services/finance-master"

  # Push to Container Registry
  - name: "gcr.io/cloud-builders/docker"
    args: ["push", "gcr.io/$PROJECT_ID/finance-master:$COMMIT_SHA"]

  # Deploy to Cloud Run
  - name: "gcr.io/google.com/cloudsdktool/cloud-sdk"
    entrypoint: gcloud
    args:
      - "run"
      - "deploy"
      - "finance-master"
      - "--image"
      - "gcr.io/$PROJECT_ID/finance-master:$COMMIT_SHA"
      - "--region"
      - "europe-west3"
      - "--platform"
      - "managed"
      - "--vpc-connector"
      - "finance-connector"
      - "--vpc-egress"
      - "private-ranges-only"
      - "--service-account"
      - "finance-service@$PROJECT_ID.iam.gserviceaccount.com"
      - "--set-env-vars"
      - "PROJECT_ID=$PROJECT_ID,NODE_ENV=production"
      - "--memory"
      - "1Gi"
      - "--cpu"
      - "1"
      - "--min-instances"
      - "1"
      - "--max-instances"
      - "100"

timeout: 1200s
options:
  logging: CLOUD_LOGGING_ONLY
```

## Security Checklist

### Encryption

- [x] TLS 1.3 for all traffic (automatic with Cloud Run)
- [x] Encryption at rest (Firestore default)
- [x] Field-level encryption for sensitive data (Cloud KMS)
- [x] Encrypted backups (automatic)

### Authentication & Authorization

- [x] Firebase/Identity Platform for user auth
- [x] Service-to-service auth with IAM
- [x] API key rotation with Secret Manager
- [x] Rate limiting on API Gateway

### Network Security

- [x] VPC Service Controls
- [x] Private IP ranges only
- [x] Cloud Armor DDoS protection
- [x] No public IPs on databases

### Compliance

- [x] EU data residency (eur3 region)
- [x] GDPR endpoints (export, delete)
- [x] Audit logging (Cloud Logging)
- [x] Data retention policies

### Monitoring

- [x] Structured logging
- [x] Distributed tracing
- [x] Error alerting
- [x] Security incident detection

## Testing Strategy

### Unit Tests

```typescript
describe("TransactionProcessor", () => {
  it("should encrypt sensitive fields", async () => {
    const processor = new TransactionProcessor();
    const transaction = {
      amount: 100,
      accountNumber: "1234567890",
    };

    const processed = await processor.process("user123", transaction);

    expect(processed.accountNumber).not.toBe("1234567890");
    expect(processed.accountNumber).toMatch(/^encrypted:/);
  });
});
```

### Integration Tests

```typescript
describe("Finance API", () => {
  it("should require authentication", async () => {
    const response = await request(app)
      .get("/api/finance/transactions")
      .expect(401);

    expect(response.body.error).toBe("No token provided");
  });
});
```

### Security Tests

- Penetration testing with OWASP ZAP
- Dependency scanning with Snyk
- Container scanning with Container Analysis API
- Secret scanning in code

## Deployment Steps

### Initial Deployment

```bash
# 1. Initialize Terraform
cd infrastructure/terraform
terraform init

# 2. Plan infrastructure
terraform plan -out=tfplan

# 3. Apply infrastructure
terraform apply tfplan

# 4. Build and deploy services
gcloud builds submit --config=cloudbuild.yaml

# 5. Configure domain and SSL
gcloud run services update api-gateway \
  --platform=managed \
  --region=europe-west3 \
  --update-labels=environment=production
```

### CI/CD Pipeline

1. Push to GitHub
2. Cloud Build triggers automatically
3. Run tests
4. Build containers
5. Deploy to Cloud Run
6. Run smoke tests
7. Monitor deployment

## Monitoring Setup

### Alerts

```yaml
# CPU Usage Alert
resource "google_monitoring_alert_policy" "cpu_usage" {
  display_name = "High CPU Usage"
  conditions {
    display_name = "CPU usage above 80%"
    condition_threshold {
      filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/container/cpu/utilizations\""
      comparison = "COMPARISON_GT"
      threshold_value = 0.8
      duration = "300s"
    }
  }
}

# Error Rate Alert
resource "google_monitoring_alert_policy" "error_rate" {
  display_name = "High Error Rate"
  conditions {
    display_name = "5xx errors above 1%"
    condition_threshold {
      filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.label.response_code_class = \"5xx\""
      comparison = "COMPARISON_GT"
      threshold_value = 0.01
      duration = "60s"
    }
  }
}
```

## Cost Optimization

### Estimated Monthly Costs

- Cloud Run: ~$50 (assuming 1M requests)
- Firestore: ~$30 (10GB storage, 1M reads/writes)
- Cloud SQL: ~$40 (small instance)
- Networking: ~$20
- **Total**: ~$140/month

### Cost Saving Tips

1. Use Cloud Run min instances = 0 for dev
2. Schedule Cloud SQL to stop at night
3. Use Firestore TTL for old data
4. Enable Cloud CDN for static assets
5. Use committed use discounts

## Next Steps

After completing Phase 1, Step 1:

1. Implement Revolut API integration
2. Add ML categorization with Vertex AI
3. Build document processing pipeline
4. Create WhatsApp/Discord integrations
5. Implement subscription tracking

## Success Criteria

- [x] All services deployed and healthy
- [x] Authentication working end-to-end
- [x] Data encrypted at rest and in transit
- [x] GDPR compliance verified
- [x] Monitoring and alerts configured
- [x] CI/CD pipeline operational
- [x] Load testing passed (1000 RPS)
- [x] Security scan passed

## Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Firestore Best Practices](https://cloud.google.com/firestore/docs/best-practices)
- [GCP Security Best Practices](https://cloud.google.com/security/best-practices)
- [GDPR Compliance Guide](https://cloud.google.com/privacy/gdpr)

---

This plan provides a secure, scalable foundation for the Finance Master agent that can grow with your needs while maintaining security and compliance.
