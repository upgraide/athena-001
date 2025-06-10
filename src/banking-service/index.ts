import { SecureMicroservice } from './shared/secure-base';
import { authenticateToken, AuthRequest } from './middleware/auth';
import { MonitoringHelper } from './shared/monitoring';
import { GoCardlessService } from './services/gocardless.service';
import { AccountService } from './services/account.service';
import { TransactionService } from './services/transaction.service';
import { ConnectionService } from './services/connection.service';
import { SyncResult } from './models/transaction.model';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';

class BankingService extends SecureMicroservice {
  private monitoring: MonitoringHelper;
  private goCardlessService!: GoCardlessService;
  private accountService!: AccountService;
  private transactionService!: TransactionService;
  private connectionService!: ConnectionService;

  constructor() {
    super('banking-service');
    this.monitoring = new MonitoringHelper(this.logger);
    this.setupServices();
    this.setupMiddleware();
    this.setupRoutes();
  }

  private setupServices() {
    this.goCardlessService = new GoCardlessService(this.logger, this.secrets);
    this.accountService = new AccountService(this.firestore, this.logger);
    this.transactionService = new TransactionService(this.firestore, this.logger);
    this.connectionService = new ConnectionService(
      this.firestore, 
      this.logger, 
      this.goCardlessService,
      this.kms
    );
    
    // Inject dependencies to avoid circular dependencies
    this.transactionService.setDependencies(this.goCardlessService, this.accountService);
  }

  private setupMiddleware() {
    // Enable CORS for API access
    const corsOptions = {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
      credentials: true,
      optionsSuccessStatus: 200
    };
    this.app.use(cors(corsOptions));
    this.app.use(compression());
  }

  private setupRoutes() {
    // Institution endpoints
    this.app.get('/api/v1/banking/institutions', authenticateToken as any, async (req: AuthRequest, res: any) => {
      try {
        const { country = 'GB' } = req.query;
        
        const institutions = await this.goCardlessService.listInstitutions(country as string);
        
        res.json({
          institutions,
          count: institutions.length
        });
      } catch (error) {
        this.logger.error('Failed to list institutions', { error });
        res.status(500).json({ error: 'Failed to retrieve institutions' });
      }
    });

    this.app.get('/api/v1/banking/institutions/search', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        const { q, country = 'GB' } = req.query;
        
        if (!q) {
          return res.status(400).json({ error: 'Search query required' });
        }
        
        const institutions = await this.goCardlessService.searchInstitutions(
          q as string, 
          country as string
        );
        
        res.json({
          institutions,
          count: institutions.length
        });
      } catch (error) {
        this.logger.error('Failed to search institutions', { error });
        res.status(500).json({ error: 'Failed to search institutions' });
      }
    });

    // Connection management endpoints
    this.app.post('/api/v1/banking/connections/initiate', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { institutionId, accountType = 'personal' } = req.body;
        
        if (!institutionId) {
          return res.status(400).json({ error: 'Institution ID required' });
        }

        const connection = await this.connectionService.initiateConnection(
          req.user.userId,
          institutionId,
          accountType
        );

        await this.auditLog('bank_connection_initiated', {
          userId: req.user.userId,
          institutionId,
          connectionId: connection.connectionId
        }, 'medium');

        this.monitoring.trackBusinessEvent('bank_connection_initiated', 'success', {
          institutionId,
          accountType
        });

        res.json(connection);
      } catch (error) {
        this.logger.error('Failed to initiate connection', { error });
        res.status(500).json({ error: 'Failed to initiate bank connection' });
      }
    });

    this.app.get('/api/v1/banking/connections', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const connections = await this.connectionService.getUserConnections(req.user.userId);
        
        res.json({
          connections,
          count: connections.length
        });
      } catch (error) {
        this.logger.error('Failed to get connections', { error });
        res.status(500).json({ error: 'Failed to retrieve connections' });
      }
    });

    this.app.get('/api/v1/banking/connections/:id', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const connection = await this.connectionService.getConnection(
          req.params.id,
          req.user.userId
        );

        if (!connection) {
          return res.status(404).json({ error: 'Connection not found' });
        }

        res.json(connection);
      } catch (error) {
        this.logger.error('Failed to get connection', { error });
        res.status(500).json({ error: 'Failed to retrieve connection' });
      }
    });

    this.app.post('/api/v1/banking/connections/:id/refresh', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const result = await this.connectionService.refreshConnection(
          req.params.id,
          req.user.userId
        );

        this.monitoring.trackBusinessEvent('bank_connection_refreshed', 'success', {
          connectionId: req.params.id
        });

        res.json(result);
      } catch (error) {
        this.logger.error('Failed to refresh connection', { error });
        res.status(500).json({ error: 'Failed to refresh connection' });
      }
    });

    this.app.delete('/api/v1/banking/connections/:id', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        await this.connectionService.deleteConnection(
          req.params.id,
          req.user.userId
        );

        await this.auditLog('bank_connection_deleted', {
          userId: req.user.userId,
          connectionId: req.params.id
        }, 'medium');

        res.json({ message: 'Connection deleted successfully' });
      } catch (error) {
        this.logger.error('Failed to delete connection', { error });
        res.status(500).json({ error: 'Failed to delete connection' });
      }
    });

    // Account endpoints
    this.app.get('/api/v1/banking/accounts', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const accounts = await this.accountService.getUserAccounts(req.user.userId);
        
        res.json({
          accounts,
          count: accounts.length
        });
      } catch (error) {
        this.logger.error('Failed to get accounts', { error });
        res.status(500).json({ error: 'Failed to retrieve accounts' });
      }
    });

    this.app.get('/api/v1/banking/accounts/:id', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const account = await this.accountService.getAccount(
          req.params.id,
          req.user.userId
        );

        if (!account) {
          return res.status(404).json({ error: 'Account not found' });
        }

        res.json(account);
      } catch (error) {
        this.logger.error('Failed to get account', { error });
        res.status(500).json({ error: 'Failed to retrieve account' });
      }
    });

    this.app.get('/api/v1/banking/accounts/:id/balance', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const balance = await this.accountService.getAccountBalance(
          req.params.id,
          req.user.userId
        );

        res.json(balance);
      } catch (error) {
        this.logger.error('Failed to get balance', { error });
        res.status(500).json({ error: 'Failed to retrieve balance' });
      }
    });

    this.app.post('/api/v1/banking/accounts/:id/sync', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const result = await this.transactionService.syncTransactions(
          req.user.userId,
          req.params.id
        );

        this.monitoring.trackBusinessEvent('account_sync', 'success', {
          accountId: req.params.id,
          transactionsSynced: result.transactionsSynced
        });

        res.json(result);
      } catch (error) {
        this.logger.error('Failed to sync account', { error });
        res.status(500).json({ error: 'Failed to sync account' });
      }
    });

    // Transaction endpoints
    this.app.get('/api/v1/banking/transactions', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { 
          accountId, 
          from, 
          to, 
          category,
          isBusinessExpense,
          needsInvoice,
          minAmount,
          merchantName,
          limit = 100, 
          offset = 0 
        } = req.query;

        const transactions = await this.transactionService.getTransactions(
          req.user.userId,
          {
            accountId: accountId as string,
            from: from ? new Date(from as string) : undefined,
            to: to ? new Date(to as string) : undefined,
            category: category as string,
            isBusinessExpense: isBusinessExpense === 'true' ? true : isBusinessExpense === 'false' ? false : undefined,
            needsInvoice: needsInvoice === 'true' ? true : needsInvoice === 'false' ? false : undefined,
            minAmount: minAmount ? parseFloat(minAmount as string) : undefined,
            merchantName: merchantName as string,
            limit: parseInt(limit as string),
            offset: parseInt(offset as string)
          }
        );

        res.json(transactions);
      } catch (error) {
        this.logger.error('Failed to get transactions', { error });
        res.status(500).json({ error: 'Failed to retrieve transactions' });
      }
    });

    this.app.get('/api/v1/banking/transactions/:id', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const transaction = await this.transactionService.getTransaction(
          req.params.id,
          req.user.userId
        );

        if (!transaction) {
          return res.status(404).json({ error: 'Transaction not found' });
        }

        res.json(transaction);
      } catch (error) {
        this.logger.error('Failed to get transaction', { error });
        res.status(500).json({ error: 'Failed to retrieve transaction' });
      }
    });

    this.app.post('/api/v1/banking/transactions/:id/categorize', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { category, subcategory, isBusinessExpense } = req.body;

        if (!category) {
          return res.status(400).json({ error: 'Category required' });
        }

        const updated = await this.transactionService.categorizeTransaction(
          req.params.id,
          req.user.userId,
          { category, subcategory, isBusinessExpense }
        );

        this.monitoring.trackBusinessEvent('transaction_categorized', 'success', {
          transactionId: req.params.id,
          category
        });

        res.json(updated);
      } catch (error) {
        this.logger.error('Failed to categorize transaction', { error });
        res.status(500).json({ error: 'Failed to categorize transaction' });
      }
    });


    // Aggregated views
    this.app.get('/api/v1/banking/summary', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const summary = await this.accountService.getAccountsSummary(req.user.userId);
        
        res.json(summary);
      } catch (error) {
        this.logger.error('Failed to get summary', { error });
        res.status(500).json({ error: 'Failed to retrieve summary' });
      }
    });

    // Callback endpoint for GoCardless (public)
    this.app.get('/api/v1/banking/callback', async (req: any, res: any) => {
      try {
        const { ref, error, details } = req.query;
        
        // Handle error case
        if (error) {
          if (process.env.FRONTEND_URL) {
            return res.redirect(`${process.env.FRONTEND_URL}/banking/connected?error=true&details=${details}`);
          }
          return res.status(400).send(`
            <html>
              <body style="font-family: Arial; margin: 40px;">
                <h1 style="color: #d32f2f;">❌ Bank Connection Failed</h1>
                <p>Error: ${error}</p>
                <p>Details: ${details || 'None provided'}</p>
                <p>Please close this window and try again.</p>
              </body>
            </html>
          `);
        }
        
        if (!ref) {
          return res.status(400).json({ error: 'Reference required' });
        }

        await this.connectionService.handleCallback(ref as string);
        
        // Redirect to frontend if available, otherwise show success page
        if (process.env.FRONTEND_URL) {
          return res.redirect(`${process.env.FRONTEND_URL}/banking/connected?success=true`);
        }
        
        // Simple success page for testing
        res.send(`
          <html>
            <body style="font-family: Arial; margin: 40px;">
              <h1 style="color: #388e3c;">✅ Bank Connection Successful!</h1>
              <p>Your bank has been connected successfully.</p>
              <p>Requisition ID: <code style="background: #f5f5f5; padding: 4px;">${ref}</code></p>
              <p>You can now close this window and use the API to:</p>
              <ul>
                <li>Check connection status</li>
                <li>List your bank accounts</li>
                <li>Sync transactions</li>
              </ul>
            </body>
          </html>
        `);
      } catch (error) {
        this.logger.error('Failed to handle callback', { error });
        if (process.env.FRONTEND_URL) {
          return res.redirect(`${process.env.FRONTEND_URL}/banking/connected?error=true`);
        }
        res.status(500).send(`
          <html>
            <body style="font-family: Arial; margin: 40px;">
              <h1 style="color: #d32f2f;">❌ Connection Error</h1>
              <p>An error occurred while processing your bank connection.</p>
              <p>Please close this window and try again.</p>
            </body>
          </html>
        `);
      }
    });

    // Enhanced transaction endpoints
    this.app.post('/api/v1/banking/transactions/sync', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { accountId, forceML } = req.body;
        
        let results: SyncResult[];
        if (accountId) {
          const result = await this.transactionService.syncTransactions(
            req.user.userId,
            accountId
          );
          results = [result];
        } else {
          results = await this.transactionService.syncAllAccounts(req.user.userId);
        }

        // Run subscription detection after sync
        await this.transactionService.detectAndUpdateSubscriptions(req.user.userId);

        this.monitoring.trackBusinessEvent('transaction_sync', 'success', {
          accountsSynced: results.length,
          totalTransactions: results.reduce((sum: number, r: SyncResult) => sum + r.transactionsSynced, 0),
          forceML
        });

        res.json({
          results,
          summary: {
            accountsSynced: results.length,
            totalTransactions: results.reduce((sum: number, r: SyncResult) => sum + r.transactionsSynced, 0)
          }
        });
      } catch (error) {
        this.logger.error('Failed to sync transactions', { error });
        res.status(500).json({ error: 'Failed to sync transactions' });
      }
    });

    this.app.post('/api/v1/banking/transactions/categorize-bulk', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { transactions, applyToSimilar } = req.body;

        if (!transactions || !Array.isArray(transactions)) {
          return res.status(400).json({ error: 'Transactions array required' });
        }

        const result = await this.transactionService.bulkCategorize(req.user.userId, {
          transactions,
          applyToSimilar
        });

        this.monitoring.trackBusinessEvent('bulk_categorization', 'success', {
          success: result.success,
          failed: result.failed,
          applyToSimilar
        });

        res.json(result);
      } catch (error) {
        this.logger.error('Failed to bulk categorize', { error });
        res.status(500).json({ error: 'Failed to bulk categorize transactions' });
      }
    });

    this.app.post('/api/v1/banking/transactions/:id/link-invoice', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { invoiceId, invoiceUrl } = req.body;

        if (!invoiceId) {
          return res.status(400).json({ error: 'Invoice ID required' });
        }

        const updated = await this.transactionService.linkInvoice(
          req.params.id,
          req.user.userId,
          { invoiceId, invoiceUrl }
        );

        this.monitoring.trackBusinessEvent('invoice_linked', 'success', {
          transactionId: req.params.id,
          invoiceId
        });

        res.json(updated);
      } catch (error) {
        this.logger.error('Failed to link invoice', { error });
        res.status(500).json({ error: 'Failed to link invoice' });
      }
    });

    this.app.get('/api/v1/banking/subscriptions', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const subscriptions = await this.transactionService.getSubscriptions(req.user.userId);

        res.json(subscriptions);
      } catch (error) {
        this.logger.error('Failed to get subscriptions', { error });
        res.status(500).json({ error: 'Failed to retrieve subscriptions' });
      }
    });

    this.app.post('/api/v1/banking/subscriptions/detect', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        await this.transactionService.detectAndUpdateSubscriptions(req.user.userId);

        const subscriptions = await this.transactionService.getSubscriptions(req.user.userId);

        this.monitoring.trackBusinessEvent('subscription_detection', 'success', {
          subscriptionsFound: subscriptions.subscriptions.length
        });

        res.json(subscriptions);
      } catch (error) {
        this.logger.error('Failed to detect subscriptions', { error });
        res.status(500).json({ error: 'Failed to detect subscriptions' });
      }
    });

    this.app.get('/api/v1/banking/insights', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const insights = await this.transactionService.getTransactionInsights(req.user.userId);

        res.json(insights);
      } catch (error) {
        this.logger.error('Failed to get insights', { error });
        res.status(500).json({ error: 'Failed to retrieve insights' });
      }
    });

    // Health check for banking service
    this.app.get('/api/v1/banking/health', (_req: any, res: any) => {
      res.json({
        service: 'banking-service',
        status: 'healthy',
        timestamp: new Date().toISOString()
      });
    });
  }
}

// Start the service
const bankingService = new BankingService();
const port = parseInt(process.env.PORT || process.env.BANKING_SERVICE_PORT || '8084');
bankingService.start(port);

export { BankingService };