import { Firestore } from '@google-cloud/firestore';
import winston from 'winston';
import crypto from 'crypto';
import { GoCardlessService } from './gocardless.service';
import { AccountService } from './account.service';
import { ConnectionService } from './connection.service';
import { MLCategorizationService } from './ml-categorization.service';
import { SubscriptionDetectorService } from './subscription-detector.service';
import { 
  Transaction, 
  GoCardlessTransaction, 
  TransactionFilter, 
  SyncResult, 
  Categorization,
  BulkCategorization,
  isExpense,
  needsInvoice
} from '../models/transaction.model';
// import { differenceInDays } from 'date-fns'; // Reserved for future use

export class TransactionService {
  private goCardlessService!: GoCardlessService;
  private accountService!: AccountService;
  private mlCategorizationService: MLCategorizationService;
  private subscriptionDetectorService: SubscriptionDetectorService;

  constructor(
    private firestore: Firestore,
    private logger: winston.Logger
  ) {
    // Initialize ML and subscription services
    this.mlCategorizationService = new MLCategorizationService(
      this.logger,
      process.env.GCP_PROJECT_ID || process.env.PROJECT_ID || 'athena-001'
    );
    this.subscriptionDetectorService = new SubscriptionDetectorService(this.firestore, this.logger);
  }

  // Inject dependencies after construction to avoid circular dependencies
  setDependencies(goCardlessService: GoCardlessService, accountService: AccountService) {
    this.goCardlessService = goCardlessService;
    this.accountService = accountService;
  }

  async createOrUpdateTransaction(data: Partial<Transaction> & { externalTransactionId: string; accountId: string; userId: string }): Promise<Transaction> {
    try {
      // Check if transaction already exists
      const existingSnapshot = await this.firestore
        .collection('transactions')
        .where('externalTransactionId', '==', data.externalTransactionId)
        .where('accountId', '==', data.accountId)
        .limit(1)
        .get();

      if (!existingSnapshot.empty) {
        // Update existing transaction
        const doc = existingSnapshot.docs[0];
        const existingData = doc.data() as Transaction;
        
        // Preserve categorization if already done by user
        const updateData = {
          ...data,
          syncedAt: new Date(),
          lastModified: new Date()
        };
        
        if (existingData.categorizedBy === 'user') {
          delete updateData.category;
          delete updateData.subcategory;
          delete updateData.isBusinessExpense;
        }
        
        await doc.ref.update(updateData);

        return {
          ...existingData,
          ...updateData,
          id: doc.id
        } as Transaction;
      }

      // Create new transaction with defaults
      const transactionRef = this.firestore.collection('transactions').doc();
      const transaction: Transaction = {
        // Defaults
        category: 'uncategorized',
        confidence: 0,
        isBusinessExpense: false,
        hasRequiredInvoice: false,
        isRecurring: false,
        feedbackHistory: [],
        metadata: {},
        // Override with provided data
        ...data,
        id: transactionRef.id,
        createdAt: new Date(),
        lastModified: new Date()
      } as Transaction;

      await transactionRef.set(transaction);

      this.logger.info('Transaction created', {
        transactionId: transaction.id,
        amount: transaction.amount,
        currency: transaction.currency,
        merchantName: transaction.merchantName
      });

      return transaction;
    } catch (error) {
      this.logger.error('Failed to create/update transaction', { error });
      throw error;
    }
  }

  async syncTransactions(userId: string, accountId: string): Promise<SyncResult> {
    const result: SyncResult = {
      accountId,
      transactionsSynced: 0,
      lastSyncedAt: new Date(),
      errors: []
    };

    try {
      // Get account details
      const account = await this.accountService.getAccount(accountId, userId);
      if (!account) {
        throw new Error('Account not found');
      }

      // Decrypt external account ID
      const kms = (this.accountService as any).kms;
      let externalAccountId: string;
      
      if (kms) {
        // Decrypt if KMS is available
        const connectionService = new ConnectionService(this.firestore, this.logger, this.goCardlessService, kms);
        externalAccountId = await (connectionService as any).decrypt(account.externalAccountId);
      } else {
        // Use as-is for testing
        externalAccountId = account.externalAccountId;
      }

      // Determine date range for sync
      const lastSync = account.lastSyncedAt || new Date(Date.now() - 90 * 24 * 60 * 60 * 1000); // 90 days default
      const dateFrom = lastSync.toISOString().split('T')[0];
      const dateTo = new Date().toISOString().split('T')[0];

      // Fetch transactions from GoCardless
      const response = await this.goCardlessService.getTransactions(
        externalAccountId,
        dateFrom,
        dateTo
      );

      // Process booked transactions
      for (const tx of response.transactions.booked) {
        try {
          const transformedData = this.transformTransaction(tx, accountId, userId);
          const transaction = await this.createOrUpdateTransaction(transformedData);

          result.transactionsSynced++;

          // Auto-categorize if not already categorized
          if (!transaction.category) {
            await this.autoCategorize(transaction);
          }
        } catch (error) {
          this.logger.error('Failed to process transaction', { tx, error });
          result.errors?.push(`Failed to process transaction: ${(error as Error).message}`);
        }
      }

      // Update account balance
      const balances = await this.goCardlessService.getAccountBalance(externalAccountId);
      if (balances.length > 0) {
        const currentBalance = balances.find(b => b.balanceType === 'expected') || balances[0];
        await this.accountService.updateAccountBalance(accountId, {
          amount: parseFloat(currentBalance.balanceAmount.amount),
          currency: currentBalance.balanceAmount.currency
        });
      }

      // Update last sync timestamp
      await this.accountService.updateLastSync(accountId);

      this.logger.info('Transactions synced', {
        accountId,
        userId,
        transactionsSynced: result.transactionsSynced,
        dateRange: { from: dateFrom, to: dateTo }
      });

      return result;
    } catch (error) {
      this.logger.error('Failed to sync transactions', { accountId, error });
      result.errors?.push(`Sync failed: ${(error as Error).message}`);
      throw error;
    }
  }

  async syncAllAccounts(userId: string): Promise<SyncResult[]> {
    try {
      const accounts = await this.accountService.getUserAccounts(userId);
      const results: SyncResult[] = [];

      for (const account of accounts) {
        try {
          const result = await this.syncTransactions(userId, account.id);
          results.push(result);
        } catch (error) {
          this.logger.error('Failed to sync account', { 
            accountId: account.id, 
            error 
          });
          results.push({
            accountId: account.id,
            transactionsSynced: 0,
            lastSyncedAt: new Date(),
            errors: [`Sync failed: ${(error as Error).message}`]
          });
        }
      }

      return results;
    } catch (error) {
      this.logger.error('Failed to sync all accounts', { userId, error });
      throw error;
    }
  }

  async getTransactions(
    userId: string,
    filter: TransactionFilter
  ): Promise<{ transactions: Transaction[]; total: number }> {
    try {
      let query = this.firestore
        .collection('transactions')
        .where('userId', '==', userId) as any;

      if (filter.accountId) {
        query = query.where('accountId', '==', filter.accountId);
      }

      if (filter.from) {
        query = query.where('date', '>=', filter.from);
      }

      if (filter.to) {
        query = query.where('date', '<=', filter.to);
      }

      if (filter.category) {
        query = query.where('category', '==', filter.category);
      }

      if (filter.isBusinessExpense !== undefined) {
        query = query.where('isBusinessExpense', '==', filter.isBusinessExpense);
      }

      // Get all transactions for client-side filtering
      const snapshot = await query.get();
      let transactions = snapshot.docs.map((doc: any) => ({
        ...doc.data(),
        id: doc.id
      })) as Transaction[];

      // Apply additional filters that Firestore can't handle
      if (filter.needsInvoice !== undefined) {
        transactions = transactions.filter(tx => needsInvoice(tx) === filter.needsInvoice);
      }

      if (filter.minAmount !== undefined) {
        transactions = transactions.filter(tx => Math.abs(tx.amount) >= filter.minAmount!);
      }

      if (filter.merchantName) {
        const searchTerm = filter.merchantName.toLowerCase();
        transactions = transactions.filter(tx => 
          tx.merchantName?.toLowerCase().includes(searchTerm)
        );
      }

      const total = transactions.length;

      // Sort by date descending
      transactions.sort((a, b) => b.date.getTime() - a.date.getTime());

      // Apply pagination
      if (filter.offset) {
        transactions = transactions.slice(filter.offset);
      }

      if (filter.limit) {
        transactions = transactions.slice(0, filter.limit);
      }

      return { transactions, total };
    } catch (error) {
      this.logger.error('Failed to get transactions', { userId, filter, error });
      throw error;
    }
  }

  async getTransaction(transactionId: string, userId: string): Promise<Transaction | null> {
    try {
      const doc = await this.firestore
        .collection('transactions')
        .doc(transactionId)
        .get();

      if (!doc.exists) {
        return null;
      }

      const transaction = doc.data() as Transaction;
      
      // Verify ownership
      if (transaction.userId !== userId) {
        throw new Error('Unauthorized access to transaction');
      }

      return {
        ...transaction,
        id: doc.id
      };
    } catch (error) {
      this.logger.error('Failed to get transaction', { transactionId, userId, error });
      throw error;
    }
  }

  async categorizeTransaction(
    transactionId: string,
    userId: string,
    categorization: Categorization
  ): Promise<Transaction> {
    try {
      const transaction = await this.getTransaction(transactionId, userId);
      if (!transaction) {
        throw new Error('Transaction not found');
      }

      await this.firestore
        .collection('transactions')
        .doc(transactionId)
        .update({
          category: categorization.category,
          subcategory: categorization.subcategory,
          isBusinessExpense: categorization.isBusinessExpense,
          categorizedAt: new Date(),
          categorizedBy: 'user'
        });

      // Store feedback for ML training
      await this.storeCategoryFeedback(transaction, categorization);

      this.logger.info('Transaction categorized', {
        transactionId,
        category: categorization.category,
        subcategory: categorization.subcategory
      });

      return {
        ...transaction,
        ...categorization
      };
    } catch (error) {
      this.logger.error('Failed to categorize transaction', { transactionId, error });
      throw error;
    }
  }

  private async autoCategorize(transaction: Transaction, forceML: boolean = false): Promise<void> {
    try {
      // Try ML categorization if enabled
      if (forceML || process.env.ENABLE_ML_CATEGORIZATION === 'true') {
        try {
          // Get user's transaction history for context
          const userHistory = await this.getUserTransactionHistory(transaction.userId, 100);
          
          const mlResult = await this.mlCategorizationService.categorizeTransaction(
            transaction,
            userHistory
          );
          
          if (mlResult.confidence >= 0.7) {
            await this.firestore
              .collection('transactions')
              .doc(transaction.id)
              .update({
                category: mlResult.category,
                subcategory: mlResult.subcategory,
                isBusinessExpense: mlResult.isBusinessExpense,
                isRecurring: mlResult.isRecurring,
                confidence: mlResult.confidence,
                categorizedAt: new Date(),
                categorizedBy: 'ml'
              });
            
            this.logger.info('Transaction ML-categorized', {
              transactionId: transaction.id,
              category: mlResult.category,
              confidence: mlResult.confidence
            });
            
            return;
          }
        } catch (mlError) {
          this.logger.warn('ML categorization failed, falling back to rules', { 
            transactionId: transaction.id,
            error: mlError 
          });
        }
      }
      
      // Fallback to rule-based categorization
      const merchantName = (transaction.merchantName || '').toLowerCase();
      const description = (transaction.description || '').toLowerCase();
      const combined = `${merchantName} ${description}`;

      let category = 'other';
      let subcategory: string | undefined = undefined;
      let isBusinessExpense = false;

      // Food & Dining
      if (combined.match(/restaurant|cafe|coffee|food|eat|dine|lunch|dinner|breakfast/)) {
        category = 'food';
        subcategory = 'restaurants';
      }
      // Transportation
      else if (combined.match(/uber|lyft|taxi|transport|fuel|petrol|gas|parking/)) {
        category = 'transportation';
        subcategory = combined.includes('fuel') ? 'fuel' : 'rideshare';
      }
      // Shopping
      else if (combined.match(/amazon|store|shop|mart|retail/)) {
        category = 'shopping';
        subcategory = 'general';
      }
      // Utilities
      else if (combined.match(/electric|water|gas|internet|phone|mobile/)) {
        category = 'utilities';
        isBusinessExpense = true;
      }
      // Entertainment
      else if (combined.match(/netflix|spotify|cinema|movie|music|game/)) {
        category = 'entertainment';
        subcategory = 'subscriptions';
      }
      // Health & Fitness
      else if (combined.match(/gym|fitness|health|doctor|pharmacy|medical/)) {
        category = 'health';
        subcategory = combined.includes('gym') ? 'fitness' : 'medical';
      }

      await this.firestore
        .collection('transactions')
        .doc(transaction.id)
        .update({
          category,
          subcategory,
          isBusinessExpense,
          categorizedAt: new Date(),
          categorizedBy: 'auto',
          confidence: 0.7 // Default confidence for rule-based
        });

      this.logger.info('Transaction auto-categorized', {
        transactionId: transaction.id,
        category,
        subcategory
      });
    } catch (error) {
      this.logger.error('Failed to auto-categorize transaction', { 
        transactionId: transaction.id, 
        error 
      });
    }
  }

  private async getUserTransactionHistory(userId: string, limit: number): Promise<Transaction[]> {
    // Firestore doesn't support 'in' with orderBy, so we'll get all user transactions
    // and filter in memory
    const snapshot = await this.firestore
      .collection('transactions')
      .where('userId', '==', userId)
      .orderBy('date', 'desc')
      .limit(limit * 2) // Get more to account for filtering
      .get();
    
    const transactions = snapshot.docs.map(doc => ({
      ...doc.data(),
      id: doc.id,
      date: doc.data().date.toDate()
    })) as Transaction[];
    
    // Filter for categorized transactions
    return transactions
      .filter(t => t.categorizedBy === 'user' || t.categorizedBy === 'ml')
      .slice(0, limit);
  }

  private async storeCategoryFeedback(
    transaction: Transaction,
    categorization: Categorization
  ): Promise<void> {
    try {
      await this.firestore.collection('category_feedback').add({
        transactionId: transaction.id,
        userId: transaction.userId,
        originalCategory: transaction.category,
        originalSubcategory: transaction.subcategory,
        correctedCategory: categorization.category,
        correctedSubcategory: categorization.subcategory,
        merchantName: transaction.merchantName,
        description: transaction.description,
        amount: transaction.amount,
        feedbackTimestamp: new Date()
      });
    } catch (error) {
      this.logger.error('Failed to store category feedback', { error });
    }
  }

  async getTransactionInsights(userId: string): Promise<any> {
    try {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

      const { transactions } = await this.getTransactions(userId, {
        from: thirtyDaysAgo,
        to: new Date()
      });

      // Calculate spending by category
      const spendingByCategory: { [key: string]: number } = {};
      const transactionsByCategory: { [key: string]: number } = {};
      let totalSpending = 0;

      transactions.forEach(tx => {
        if (tx.amount < 0) { // Only count outgoing transactions
          const amount = Math.abs(tx.amount);
          const category = tx.category || 'uncategorized';
          
          spendingByCategory[category] = (spendingByCategory[category] || 0) + amount;
          transactionsByCategory[category] = (transactionsByCategory[category] || 0) + 1;
          totalSpending += amount;
        }
      });

      // Find top merchants
      const merchantSpending: { [key: string]: { amount: number; count: number } } = {};
      transactions.forEach(tx => {
        if (tx.amount < 0 && tx.merchantName) {
          const amount = Math.abs(tx.amount);
          if (!merchantSpending[tx.merchantName]) {
            merchantSpending[tx.merchantName] = { amount: 0, count: 0 };
          }
          merchantSpending[tx.merchantName].amount += amount;
          merchantSpending[tx.merchantName].count += 1;
        }
      });

      const topMerchants = Object.entries(merchantSpending)
        .sort(([, a], [, b]) => b.amount - a.amount)
        .slice(0, 10)
        .map(([merchant, data]) => ({ merchant, ...data }));

      return {
        period: {
          from: thirtyDaysAgo,
          to: new Date()
        },
        totalSpending,
        spendingByCategory,
        transactionsByCategory,
        topMerchants,
        averageTransactionAmount: totalSpending / transactions.filter(tx => tx.amount < 0).length,
        transactionCount: transactions.length
      };
    } catch (error) {
      this.logger.error('Failed to generate transaction insights', { userId, error });
      throw error;
    }
  }

  private transformTransaction(
    goCardlessTxn: GoCardlessTransaction,
    accountId: string,
    userId: string
  ): Partial<Transaction> & { externalTransactionId: string; accountId: string; userId: string } {
    const amount = parseFloat(goCardlessTxn.transactionAmount.amount);
    
    return {
      userId,
      accountId,
      externalTransactionId: this.generateTransactionId(goCardlessTxn),
      
      // Amounts
      amount: Math.abs(amount),
      currency: goCardlessTxn.transactionAmount.currency,
      
      // Dates
      date: new Date(goCardlessTxn.bookingDate),
      valueDate: goCardlessTxn.valueDate ? new Date(goCardlessTxn.valueDate) : undefined,
      
      // Merchant extraction (intelligent)
      merchantName: this.extractMerchantName(goCardlessTxn),
      description: this.buildDescription(goCardlessTxn),
      
      // Initial categorization
      confidence: 0,
      isBusinessExpense: false,
      hasRequiredInvoice: false,
      isRecurring: false,
      
      // Metadata
      metadata: {
        counterpartyName: goCardlessTxn.creditorName || goCardlessTxn.debtorName,
        counterpartyAccount: goCardlessTxn.creditorAccount?.iban || goCardlessTxn.debtorAccount?.iban,
        reference: goCardlessTxn.remittanceInformationStructured,
        bankCategory: goCardlessTxn.proprietaryBankTransactionCode,
        tags: []
      },
      
      // Timestamps
      syncedAt: new Date(),
      createdAt: new Date(),
      lastModified: new Date(),
      feedbackHistory: []
    };
  }

  private extractMerchantName(txn: GoCardlessTransaction): string {
    // Smart merchant extraction
    const creditor = txn.creditorName || '';
    const description = txn.remittanceInformationUnstructured || '';
    
    // Clean up common patterns
    const cleaned = creditor
      .replace(/\*\d+/, '')  // Remove *1234 patterns
      .replace(/\s+/g, ' ')  // Normalize spaces
      .trim();
    
    // If no creditor, try to extract from description
    if (!cleaned && description) {
      const match = description.match(/^([A-Z][A-Z\s&]+?)(?:\s+\d|$)/);
      return match ? match[1].trim() : description.split(' ')[0];
    }
    
    return cleaned;
  }

  private generateTransactionId(txn: GoCardlessTransaction): string {
    if (txn.transactionId) return txn.transactionId;
    
    // Generate deterministic ID for deduplication
    const data = `${txn.bookingDate}_${txn.transactionAmount.amount}_${txn.transactionAmount.currency}_${txn.creditorName || txn.debtorName}`;
    return crypto.createHash('sha256').update(data).digest('hex').substring(0, 16);
  }

  private buildDescription(txn: GoCardlessTransaction): string {
    // Build comprehensive description from available fields
    const parts = [
      txn.remittanceInformationUnstructured,
      txn.additionalInformation,
      txn.remittanceInformationStructured
    ].filter(Boolean);
    
    return parts.join(' - ') || 'Transaction';
  }

  async bulkCategorize(
    userId: string,
    bulkData: BulkCategorization
  ): Promise<{ success: number; failed: number }> {
    let success = 0;
    let failed = 0;
    
    try {
      const batch = this.firestore.batch();
      
      for (const item of bulkData.transactions) {
        try {
          // Verify transaction ownership
          const txRef = this.firestore.collection('transactions').doc(item.id);
          const txDoc = await txRef.get();
          
          if (!txDoc.exists || txDoc.data()?.userId !== userId) {
            failed++;
            continue;
          }
          
          batch.update(txRef, {
            category: item.category,
            subcategory: item.subcategory,
            isBusinessExpense: item.isBusinessExpense,
            categorizedAt: new Date(),
            categorizedBy: 'user',
            lastModified: new Date()
          });
          
          success++;
        } catch (error) {
          this.logger.error('Failed to categorize transaction in bulk', { 
            transactionId: item.id, 
            error 
          });
          failed++;
        }
      }
      
      await batch.commit();
      
      // Apply to similar transactions if requested
      if (bulkData.applyToSimilar) {
        await this.applyCategorizationToSimilar(userId, bulkData.transactions);
      }
      
      this.logger.info('Bulk categorization completed', {
        userId,
        success,
        failed
      });
      
      return { success, failed };
    } catch (error) {
      this.logger.error('Bulk categorization failed', { userId, error });
      throw error;
    }
  }

  private async applyCategorizationToSimilar(
    userId: string,
    categorizedTransactions: Array<{
      id: string;
      category: string;
      subcategory?: string;
      isBusinessExpense?: boolean;
    }>
  ): Promise<void> {
    for (const catTx of categorizedTransactions) {
      try {
        // Get the original transaction
        const originalDoc = await this.firestore
          .collection('transactions')
          .doc(catTx.id)
          .get();
        
        if (!originalDoc.exists) continue;
        
        const original = originalDoc.data() as Transaction;
        
        // Find similar uncategorized transactions
        const similarSnapshot = await this.firestore
          .collection('transactions')
          .where('userId', '==', userId)
          .where('merchantName', '==', original.merchantName)
          .where('category', '==', 'uncategorized')
          .limit(50)
          .get();
        
        const batch = this.firestore.batch();
        
        similarSnapshot.docs.forEach(doc => {
          batch.update(doc.ref, {
            category: catTx.category,
            subcategory: catTx.subcategory,
            isBusinessExpense: catTx.isBusinessExpense,
            categorizedAt: new Date(),
            categorizedBy: 'auto',
            confidence: 0.85,
            lastModified: new Date()
          });
        });
        
        await batch.commit();
        
        this.logger.info('Applied categorization to similar transactions', {
          originalTransactionId: catTx.id,
          similarCount: similarSnapshot.size
        });
      } catch (error) {
        this.logger.error('Failed to apply categorization to similar', { 
          transactionId: catTx.id, 
          error 
        });
      }
    }
  }

  async linkInvoice(
    transactionId: string,
    userId: string,
    invoiceData: { invoiceId: string; invoiceUrl?: string }
  ): Promise<Transaction> {
    try {
      const transaction = await this.getTransaction(transactionId, userId);
      if (!transaction) {
        throw new Error('Transaction not found');
      }
      
      await this.firestore
        .collection('transactions')
        .doc(transactionId)
        .update({
          invoiceId: invoiceData.invoiceId,
          receiptUrl: invoiceData.invoiceUrl,
          hasRequiredInvoice: true,
          lastModified: new Date()
        });
      
      this.logger.info('Invoice linked to transaction', {
        transactionId,
        invoiceId: invoiceData.invoiceId
      });
      
      return {
        ...transaction,
        invoiceId: invoiceData.invoiceId,
        receiptUrl: invoiceData.invoiceUrl,
        hasRequiredInvoice: true
      };
    } catch (error) {
      this.logger.error('Failed to link invoice', { transactionId, error });
      throw error;
    }
  }

  async detectAndUpdateSubscriptions(userId: string): Promise<void> {
    try {
      await this.subscriptionDetectorService.detectSubscriptions(userId);
      
      this.logger.info('Subscription detection completed', { userId });
    } catch (error) {
      this.logger.error('Failed to detect subscriptions', { userId, error });
      throw error;
    }
  }

  async getSubscriptions(userId: string) {
    return this.subscriptionDetectorService.getSubscriptions(userId);
  }
}