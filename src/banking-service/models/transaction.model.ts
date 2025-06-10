export interface Transaction {
  // Core fields
  id: string;
  userId: string;
  accountId: string;
  externalTransactionId: string;
  
  // Amount and dates
  amount: number;
  currency: string;
  date: Date;                          // bookingDate
  valueDate?: Date;
  
  // Merchant info
  merchantName?: string;
  merchantId?: string;                 // For subscription tracking
  description: string;
  
  // Intelligent categorization (PRD requirement)
  category: string;
  subcategory?: string;
  confidence: number;                  // 0-1 confidence score
  isBusinessExpense: boolean;
  businessJustification?: string;
  
  // Document linking (PRD: invoice extraction)
  invoiceId?: string;
  receiptUrl?: string;
  hasRequiredInvoice: boolean;
  
  // Calendar integration (PRD: link to events)
  calendarEventId?: string;
  projectId?: string;
  
  // Subscription tracking (PRD requirement)
  isRecurring: boolean;
  subscriptionId?: string;
  recurringPattern?: {
    frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
    nextExpected: Date;
  };
  
  // ML feedback tracking
  feedbackHistory: {
    timestamp: Date;
    originalCategory: string;
    correctedCategory: string;
    correctedBy: 'user' | 'system';
  }[];
  
  // Metadata
  metadata: {
    counterpartyName?: string;
    counterpartyAccount?: string;
    reference?: string;
    bankCategory?: string;
    tags?: string[];
  };
  
  // Timestamps
  createdAt: Date;
  syncedAt: Date;
  lastModified: Date;
  categorizedAt?: Date;
  categorizedBy?: 'auto' | 'user' | 'ml';
}

// Computed properties helper functions
export function isExpense(transaction: Transaction): boolean {
  return transaction.amount < 0;
}

export function needsInvoice(transaction: Transaction): boolean {
  return transaction.isBusinessExpense && 
         transaction.amount < -50 && 
         !transaction.invoiceId;
}

// GoCardless transaction structure
export interface GoCardlessTransaction {
  transactionId?: string;              // Unique ID (not always provided)
  bookingDate: string;                 // YYYY-MM-DD
  valueDate?: string;                  // YYYY-MM-DD
  transactionAmount: {
    amount: string;                    // Decimal string
    currency: string;                  // ISO 4217
  };
  creditorName?: string;               // Merchant/payee name
  creditorAccount?: {
    iban?: string;
  };
  debtorName?: string;                 // Payer name
  debtorAccount?: {
    iban?: string;
  };
  remittanceInformationUnstructured?: string;  // Transaction description
  remittanceInformationStructured?: string;    // Reference number
  additionalInformation?: string;              // Extra details
  proprietaryBankTransactionCode?: string;     // Bank's category
}

// Filter and result interfaces
export interface TransactionFilter {
  accountId?: string;
  from?: Date;
  to?: Date;
  category?: string;
  isBusinessExpense?: boolean;
  needsInvoice?: boolean;
  minAmount?: number;
  merchantName?: string;
  limit?: number;
  offset?: number;
}

export interface SyncResult {
  accountId: string;
  transactionsSynced: number;
  lastSyncedAt: Date;
  errors?: string[];
}

export interface Categorization {
  category: string;
  subcategory?: string;
  isBusinessExpense?: boolean;
  confidence?: number;
}

export interface BulkCategorization {
  transactions: {
    id: string;
    category: string;
    subcategory?: string;
    isBusinessExpense?: boolean;
  }[];
  applyToSimilar?: boolean;
}

// Subscription model for recurring transaction tracking
export interface Subscription {
  id: string;
  userId: string;
  merchantName: string;
  merchantId?: string;
  amount: number;
  currency: string;
  frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
  nextExpected: Date;
  lastCharged?: Date;
  confidence: number;
  transactionIds: string[];
  status: 'active' | 'paused' | 'cancelled';
  createdAt: Date;
  updatedAt: Date;
}