import { SecureMicroservice } from '../../services/shared/secure-base';
import { FinanceMasterService } from './service';
import cors from 'cors';
import compression from 'compression';

class FinanceMasterAPI extends SecureMicroservice {
  private financeService: FinanceMasterService;

  constructor() {
    super('finance-master');
    this.financeService = new FinanceMasterService(this.firestore, this.logger);
    this.setupMiddleware();
    this.setupRoutes();
  }

  private setupMiddleware() {
    // Enable CORS for API access
    const corsOptions = {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
      credentials: true,
      optionsSuccessStatus: 200
    };
    this.app.use(cors(corsOptions));

    // Enable compression for better performance
    this.app.use(compression());

    // Request timeout middleware
    this.app.use((req: any, res: any, next: any) => {
      res.setTimeout(30000, () => {
        this.logger.error('Request timeout', { 
          requestId: req.id,
          path: req.path,
          method: req.method 
        });
        res.status(408).json({ error: 'Request timeout' });
      });
      next();
    });
  }

  private setupRoutes() {
    // Health check routes are already set up in base class

    // Initialize the service on startup
    this.app.post('/api/v1/initialize', async (req: any, res: any) => {
      try {
        await this.financeService.initialize();
        res.json({ 
          message: 'Finance Master Service initialized successfully',
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Service initialization failed', { error });
        res.status(500).json({ error: 'Service initialization failed' });
      }
    });

    // Account management endpoints
    this.app.post('/api/v1/accounts', async (req: any, res: any) => {
      try {
        const { userId, accountData } = req.body;
        if (!userId || !accountData) {
          return res.status(400).json({ error: 'userId and accountData required' });
        }

        // Encrypt sensitive account data
        const encryptedData = await this.encrypt(JSON.stringify(accountData));
        
        // Store account
        const accountRef = await this.firestore.collection('accounts').add({
          userId,
          encryptedData,
          createdAt: new Date(),
          updatedAt: new Date(),
          status: 'active'
        });

        // Audit log
        await this.auditLog('account_created', {
          userId,
          accountId: accountRef.id,
          accountType: accountData.type
        }, 'low');

        res.status(201).json({ 
          accountId: accountRef.id,
          message: 'Account created successfully' 
        });
      } catch (error) {
        this.logger.error('Account creation failed', { error });
        res.status(500).json({ error: 'Account creation failed' });
      }
    });

    // Transaction categorization endpoint
    this.app.post('/api/v1/transactions/categorize', async (req: any, res: any) => {
      try {
        const { transaction } = req.body;
        if (!transaction) {
          return res.status(400).json({ error: 'Transaction data required' });
        }

        const result = await this.financeService.categorizeTransaction(transaction);
        
        res.json({
          transactionId: transaction.id,
          category: result.category,
          confidence: result.confidence,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Transaction categorization failed', { error });
        res.status(500).json({ error: 'Transaction categorization failed' });
      }
    });

    // Document processing endpoint
    this.app.post('/api/v1/documents/process', async (req: any, res: any) => {
      try {
        const { document } = req.body;
        if (!document) {
          return res.status(400).json({ error: 'Document data required' });
        }

        const result = await this.financeService.processDocument(document);
        
        // Audit sensitive document processing
        await this.auditLog('document_processed', {
          documentId: document.id,
          documentType: document.type,
          processingResult: result.confidence > 0.8 ? 'high_confidence' : 'low_confidence'
        }, document.type === 'tax' ? 'high' : 'medium');

        res.json({
          documentId: document.id,
          extracted: result.extracted,
          confidence: result.confidence,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Document processing failed', { error });
        res.status(500).json({ error: 'Document processing failed' });
      }
    });

    // Insights generation endpoint
    this.app.get('/api/v1/insights/:userId', async (req: any, res: any) => {
      try {
        const { userId } = req.params;
        if (!userId) {
          return res.status(400).json({ error: 'userId required' });
        }

        const insights = await this.financeService.generateInsights(userId);
        
        res.json({
          userId,
          insights: insights.insights,
          trends: insights.trends,
          generatedAt: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Insights generation failed', { error });
        res.status(500).json({ error: 'Insights generation failed' });
      }
    });

    // Test endpoints (only in development)
    if (process.env.NODE_ENV !== 'production') {
      this.setupTestEndpoints();
    }

    // 404 handler
    this.app.use((req: any, res: any) => {
      res.status(404).json({ 
        error: 'Endpoint not found',
        path: req.path,
        method: req.method
      });
    });
  }

  private setupTestEndpoints() {
    // Encryption test endpoint
    this.app.post('/test/encrypt', async (req: any, res: any) => {
      try {
        const { data } = req.body;
        if (!data) {
          return res.status(400).json({ error: 'Data required' });
        }

        const encrypted = await this.encrypt(data);
        const decrypted = await this.decrypt(encrypted);

        res.json({
          original: data,
          encrypted: encrypted,
          decrypted: decrypted,
          success: data === decrypted
        });
      } catch (error) {
        this.logger.error('Encryption test failed', { error });
        res.status(500).json({ error: 'Encryption test failed' });
      }
    });

    // Database connection test
    this.app.get('/test/database', async (_req: any, res: any) => {
      try {
        await this.firestore.collection('test').doc('connection').set({
          timestamp: new Date(),
          service: 'finance-master',
          status: 'connected'
        });

        res.json({ message: 'Database connection successful' });
      } catch (error) {
        this.logger.error('Database test failed', { error });
        res.status(500).json({ error: 'Database connection failed' });
      }
    });
  }

  async gracefulShutdown() {
    this.logger.info('Graceful shutdown initiated');
    
    // Close database connections
    await this.firestore.terminate();
    
    // Log shutdown
    this.logger.info('Finance Master Service shut down successfully');
    
    process.exit(0);
  }
}

// Handle graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  if (service) {
    await service.gracefulShutdown();
  }
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, shutting down gracefully');
  if (service) {
    await service.gracefulShutdown();
  }
});

// Start the service
const service = new FinanceMasterAPI();
const port = parseInt(process.env.PORT || process.env.API_PORT || '8080');
service.start(port);

export { FinanceMasterAPI };