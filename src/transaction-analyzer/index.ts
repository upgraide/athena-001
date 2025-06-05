import { SecureMicroservice } from '../../services/shared/secure-base';
import cors from 'cors';
import compression from 'compression';

class TransactionAnalyzerAPI extends SecureMicroservice {
  constructor() {
    super('transaction-analyzer');
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

    // Enable compression
    this.app.use(compression());
  }

  private setupRoutes() {
    // Analyze transaction endpoint
    this.app.post('/api/v1/analyze', async (req: any, res: any) => {
      try {
        const { transactions } = req.body;
        if (!transactions || !Array.isArray(transactions)) {
          return res.status(400).json({ error: 'Transactions array required' });
        }

        // Placeholder for transaction analysis logic
        const analysis = transactions.map((tx: any) => ({
          transactionId: tx.id,
          category: 'General',
          merchant: tx.description,
          amount: tx.amount,
          confidence: 0.85
        }));

        res.json({
          analyzed: analysis,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Transaction analysis failed', { error });
        res.status(500).json({ error: 'Transaction analysis failed' });
      }
    });

    // Pattern detection endpoint
    this.app.post('/api/v1/patterns', async (req: any, res: any) => {
      try {
        const { userId, dateRange } = req.body;
        if (!userId) {
          return res.status(400).json({ error: 'userId required' });
        }

        // Placeholder for pattern detection logic
        res.json({
          userId,
          patterns: [
            { type: 'recurring', description: 'Monthly subscription detected', count: 5 },
            { type: 'unusual', description: 'Large transaction detected', count: 1 }
          ],
          dateRange,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Pattern detection failed', { error });
        res.status(500).json({ error: 'Pattern detection failed' });
      }
    });

    // Anomaly detection endpoint
    this.app.post('/api/v1/anomalies', async (req: any, res: any) => {
      try {
        const { userId, transactions } = req.body;
        if (!userId || !transactions) {
          return res.status(400).json({ error: 'userId and transactions required' });
        }

        // Placeholder for anomaly detection logic
        res.json({
          userId,
          anomalies: [],
          riskScore: 0.2,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Anomaly detection failed', { error });
        res.status(500).json({ error: 'Anomaly detection failed' });
      }
    });
  }

  async gracefulShutdown() {
    this.logger.info('Transaction Analyzer Service shutting down gracefully');
    await this.firestore.terminate();
    process.exit(0);
  }
}

// Handle graceful shutdown
process.on('SIGTERM', async () => {
  if (service) {
    await service.gracefulShutdown();
  }
});

process.on('SIGINT', async () => {
  if (service) {
    await service.gracefulShutdown();
  }
});

// Start the service
const service = new TransactionAnalyzerAPI();
const port = parseInt(process.env.PORT || process.env.API_PORT || '8080');
service.start(port);

export { TransactionAnalyzerAPI };