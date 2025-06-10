# GoCardless Open Banking Integration Plan

## Overview

This document outlines the integration plan for implementing GoCardless Bank Account Data API to connect with Revolut and other banking institutions. This approach allows users to securely connect any of their bank accounts from 2,500+ banks across UK and Europe.

## Key Benefits of GoCardless

1. **Wide Coverage**: 2,500+ banks including Revolut, major UK banks, and European institutions
2. **PSD2 Compliant**: Licensed AISP with GDPR compliance and ISO 27001 certification
3. **24 Months History**: Access up to 24 months of transaction history
4. **90 Days Access**: Continuous access to account information for 90 days per authentication
5. **Unified API**: Single integration for all banks

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Athena Finance │────▶│  Banking Service │────▶│   GoCardless    │
│   Frontend      │     │   (New Service)  │     │      API        │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                │                          │
                                ▼                          ▼
                        ┌──────────────┐          ┌─────────────────┐
                        │  Firestore   │          │  Bank APIs      │
                        │  Database    │          │ (Revolut, etc)  │
                        └──────────────┘          └─────────────────┘
```

## Implementation Plan

### Phase 1: Banking Service Setup (Day 1-2)

#### 1. Create Banking Service
```typescript
// services/banking-service/index.ts
import { SecureMicroservice } from '../shared/secure-base';
import { BankingController } from './controllers/banking.controller';
import { GoCardlessService } from './services/gocardless.service';
import { AccountService } from './services/account.service';
import { TransactionService } from './services/transaction.service';

class BankingService extends SecureMicroservice {
  private goCardlessService: GoCardlessService;
  private accountService: AccountService;
  private transactionService: TransactionService;

  constructor() {
    super('banking-service');
    this.setupServices();
    this.setupRoutes();
  }

  private setupServices() {
    this.goCardlessService = new GoCardlessService(this.logger);
    this.accountService = new AccountService(this.firestore, this.logger);
    this.transactionService = new TransactionService(this.firestore, this.logger);
  }
}
```

#### 2. GoCardless Service Implementation
```typescript
// services/banking-service/services/gocardless.service.ts
export class GoCardlessService {
  private readonly baseUrl = 'https://bankaccountdata.gocardless.com/api/v2';
  private accessToken: string;
  private tokenExpiry: Date;

  constructor(private logger: winston.Logger) {}

  async authenticate(): Promise<void> {
    const secretId = await this.getSecret('gocardless-secret-id');
    const secretKey = await this.getSecret('gocardless-secret-key');

    const response = await fetch(`${this.baseUrl}/token/new/`, {
      method: 'POST',
      headers: {
        'accept': 'application/json',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ secret_id: secretId, secret_key: secretKey })
    });

    const data = await response.json();
    this.accessToken = data.access;
    this.tokenExpiry = new Date(Date.now() + data.access_expires * 1000);
  }

  async listInstitutions(country: string): Promise<Institution[]> {
    await this.ensureAuthenticated();
    
    const response = await fetch(`${this.baseUrl}/institutions/?country=${country}`, {
      headers: {
        'accept': 'application/json',
        'Authorization': `Bearer ${this.accessToken}`
      }
    });

    return await response.json();
  }

  async createRequisition(institutionId: string, redirectUrl: string): Promise<Requisition> {
    await this.ensureAuthenticated();
    
    const response = await fetch(`${this.baseUrl}/requisitions/`, {
      method: 'POST',
      headers: {
        'accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.accessToken}`
      },
      body: JSON.stringify({
        redirect: redirectUrl,
        institution_id: institutionId,
        reference: crypto.randomUUID(),
        user_language: 'EN'
      })
    });

    return await response.json();
  }
}
```

### Phase 2: Database Schema (Day 2)

```typescript
// Database Collections

// Bank Connections
interface BankConnection {
  id: string;
  userId: string;
  requisitionId: string;
  institutionId: string;
  institutionName: string;
  status: 'pending' | 'linked' | 'expired' | 'error';
  createdAt: Date;
  expiresAt: Date; // 90 days from creation
  lastSyncedAt?: Date;
  metadata?: {
    country: string;
    logo?: string;
  };
}

// Bank Accounts
interface BankAccount {
  id: string;
  userId: string;
  connectionId: string;
  externalAccountId: string; // GoCardless account ID
  accountNumber?: string;
  iban?: string;
  currency: string;
  accountType: 'personal' | 'business' | 'savings' | 'credit';
  balance?: {
    amount: number;
    currency: string;
    lastUpdated: Date;
  };
  institutionName: string;
  isActive: boolean;
}

// Transactions
interface Transaction {
  id: string;
  userId: string;
  accountId: string;
  externalTransactionId: string;
  amount: number;
  currency: string;
  date: Date;
  merchantName?: string;
  description: string;
  category?: string;
  subcategory?: string;
  isBusinessExpense?: boolean;
  metadata?: {
    counterpartyName?: string;
    reference?: string;
    bankCategory?: string;
  };
  syncedAt: Date;
}
```

### Phase 3: API Endpoints (Day 3)

#### Banking Service Endpoints
```typescript
// Protected endpoints (require authentication)

// Institution Management
GET    /api/v1/banking/institutions?country=GB
GET    /api/v1/banking/institutions/search?q=revolut

// Connection Management
POST   /api/v1/banking/connections/initiate
{
  "institutionId": "REVOLUT_REVOGB21",
  "accountType": "personal" // or "business"
}

GET    /api/v1/banking/connections
GET    /api/v1/banking/connections/:id
DELETE /api/v1/banking/connections/:id
POST   /api/v1/banking/connections/:id/refresh

// Account Management
GET    /api/v1/banking/accounts
GET    /api/v1/banking/accounts/:id
GET    /api/v1/banking/accounts/:id/balance
POST   /api/v1/banking/accounts/:id/sync

// Transaction Management
GET    /api/v1/banking/transactions?accountId=xxx&from=2024-01-01&to=2024-12-31
GET    /api/v1/banking/transactions/:id
POST   /api/v1/banking/transactions/sync
POST   /api/v1/banking/transactions/:id/categorize
{
  "category": "food",
  "subcategory": "restaurants",
  "isBusinessExpense": false
}

// Aggregated Views
GET    /api/v1/banking/summary // Total balance across all accounts
GET    /api/v1/banking/insights // AI-generated insights
```

### Phase 4: Connection Flow Implementation (Day 4)

#### 1. Initiate Connection
```typescript
async initiateConnection(userId: string, institutionId: string): Promise<ConnectionResponse> {
  // Create requisition with GoCardless
  const requisition = await this.goCardlessService.createRequisition(
    institutionId,
    `${process.env.APP_URL}/banking/callback`
  );

  // Store connection in database
  const connection = await this.firestore.collection('bank_connections').add({
    userId,
    requisitionId: requisition.id,
    institutionId,
    institutionName: await this.getInstitutionName(institutionId),
    status: 'pending',
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000) // 90 days
  });

  return {
    connectionId: connection.id,
    authUrl: requisition.link, // User needs to visit this URL
    expiresIn: 300 // 5 minutes to complete auth
  };
}
```

#### 2. Handle Callback
```typescript
async handleCallback(requisitionId: string): Promise<void> {
  // Get requisition details
  const requisition = await this.goCardlessService.getRequisition(requisitionId);
  
  if (requisition.status === 'LN') { // Linked successfully
    // Get accounts from requisition
    for (const accountId of requisition.accounts) {
      const accountDetails = await this.goCardlessService.getAccountDetails(accountId);
      const accountBalance = await this.goCardlessService.getAccountBalance(accountId);
      
      // Store account in database
      await this.accountService.createAccount({
        userId: connection.userId,
        connectionId: connection.id,
        externalAccountId: accountId,
        ...accountDetails,
        balance: accountBalance
      });
    }
    
    // Update connection status
    await this.updateConnectionStatus(connection.id, 'linked');
    
    // Trigger initial transaction sync
    await this.syncTransactions(connection.userId, connection.id);
  }
}
```

### Phase 5: Transaction Sync (Day 5)

```typescript
async syncTransactions(userId: string, accountId: string): Promise<SyncResult> {
  const account = await this.accountService.getAccount(accountId);
  const lastSync = account.lastSyncedAt || new Date(Date.now() - 24 * 30 * 60 * 60 * 1000); // 24 months default
  
  // Fetch transactions from GoCardless
  const transactions = await this.goCardlessService.getTransactions(
    account.externalAccountId,
    lastSync.toISOString()
  );
  
  // Process and store transactions
  const processed = [];
  for (const tx of transactions.transactions.booked) {
    const transaction = await this.transactionService.createOrUpdate({
      userId,
      accountId,
      externalTransactionId: tx.transactionId || crypto.randomUUID(),
      amount: parseFloat(tx.transactionAmount.amount),
      currency: tx.transactionAmount.currency,
      date: new Date(tx.bookingDate),
      merchantName: tx.creditorName || tx.debtorName,
      description: tx.remittanceInformationUnstructured || tx.additionalInformation,
      metadata: {
        counterpartyName: tx.creditorName || tx.debtorName,
        reference: tx.remittanceInformationStructured,
        bankCategory: tx.proprietaryBankTransactionCode
      }
    });
    
    // Auto-categorize using AI
    const category = await this.categorizationService.categorize(transaction);
    if (category.confidence > 0.8) {
      await this.transactionService.updateCategory(transaction.id, category);
    }
    
    processed.push(transaction);
  }
  
  // Update last sync timestamp
  await this.accountService.updateLastSync(accountId);
  
  return {
    accountId,
    transactionsSynced: processed.length,
    lastSyncedAt: new Date()
  };
}
```

### Phase 6: Security & Rate Limiting (Day 6)

#### 1. Encryption for Sensitive Data
```typescript
// Store encrypted requisition IDs
async storeConnection(data: BankConnection): Promise<void> {
  const encrypted = {
    ...data,
    requisitionId: await this.encrypt(data.requisitionId)
  };
  await this.firestore.collection('bank_connections').add(encrypted);
}
```

#### 2. Rate Limiting Implementation
```typescript
class RateLimiter {
  private limits = {
    details: { calls: 10, window: 24 * 60 * 60 * 1000 }, // 10 per day
    balances: { calls: 10, window: 24 * 60 * 60 * 1000 },
    transactions: { calls: 10, window: 24 * 60 * 60 * 1000 },
    global: { calls: 1000, window: 60 * 1000 } // 1000 per minute
  };

  async checkLimit(accountId: string, endpoint: string): Promise<boolean> {
    const key = `${accountId}:${endpoint}`;
    const count = await this.redis.incr(key);
    
    if (count === 1) {
      await this.redis.expire(key, this.limits[endpoint].window / 1000);
    }
    
    return count <= this.limits[endpoint].calls;
  }
}
```

### Phase 7: Monitoring & Alerts (Day 7)

```typescript
// Monitor sync health
class BankingSyncMonitor {
  async checkConnectionHealth(): Promise<void> {
    const connections = await this.getActiveConnections();
    
    for (const connection of connections) {
      // Check if connection is about to expire
      const daysUntilExpiry = differenceInDays(connection.expiresAt, new Date());
      if (daysUntilExpiry <= 7) {
        await this.notifyUserConnectionExpiring(connection);
      }
      
      // Check if sync is failing
      const lastSync = connection.lastSyncedAt;
      if (lastSync && differenceInHours(new Date(), lastSync) > 24) {
        await this.alertSyncFailure(connection);
      }
    }
  }
}
```

## Testing Strategy

### 1. Integration Tests
```typescript
describe('Banking Service', () => {
  it('should list available institutions', async () => {
    const institutions = await bankingService.listInstitutions('GB');
    expect(institutions).toContainEqual(
      expect.objectContaining({
        id: 'REVOLUT_REVOGB21',
        name: expect.stringContaining('Revolut')
      })
    );
  });

  it('should create bank connection', async () => {
    const connection = await bankingService.initiateConnection(
      userId,
      'REVOLUT_REVOGB21'
    );
    expect(connection.authUrl).toMatch(/^https:\/\/.*gocardless\.com/);
  });
});
```

### 2. Sandbox Testing
- Use GoCardless sandbox environment for development
- Test with mock bank accounts
- Simulate various error scenarios

## Deployment Configuration

### Environment Variables
```bash
# GoCardless Configuration
GOCARDLESS_SECRET_ID=<stored-in-secret-manager>
GOCARDLESS_SECRET_KEY=<stored-in-secret-manager>
GOCARDLESS_ENV=production # or sandbox

# Service Configuration
BANKING_SERVICE_PORT=8084
BANKING_SYNC_INTERVAL=3600000 # 1 hour

# Security
ENCRYPTION_KEY_NAME=banking-data-key
```

### Terraform Resources
```hcl
# Cloud Run Service
resource "google_cloud_run_service" "banking_service" {
  name     = "banking-service"
  location = var.region

  template {
    spec {
      containers {
        image = "gcr.io/${var.project_id}/banking-service:latest"
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        resources {
          limits = {
            cpu    = "2"
            memory = "1Gi"
          }
        }
      }
    }
  }
}

# Firestore Indexes
resource "google_firestore_index" "transactions_by_user" {
  collection = "transactions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "date"
    order      = "DESCENDING"
  }
}
```

## Timeline Summary

- **Day 1-2**: Banking service setup and GoCardless integration
- **Day 3**: API endpoints implementation
- **Day 4**: Connection flow and authentication
- **Day 5**: Transaction sync mechanism
- **Day 6**: Security and rate limiting
- **Day 7**: Monitoring and deployment

## Next Steps

1. Register for GoCardless Bank Account Data API
2. Set up development/sandbox environment
3. Create banking service structure
4. Implement core GoCardless integration
5. Build connection and sync flows
6. Add AI categorization
7. Deploy and test with real accounts

## Key Considerations

1. **Rate Limits**: Respect GoCardless limits (10 calls/day per endpoint per account)
2. **Data Freshness**: Implement smart caching to minimize API calls
3. **Re-authentication**: Notify users before 90-day expiry
4. **Multi-bank Support**: Design for multiple simultaneous connections
5. **Error Handling**: Graceful handling of bank API failures
6. **GDPR Compliance**: Ensure proper data deletion on user request