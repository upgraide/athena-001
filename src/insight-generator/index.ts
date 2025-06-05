import { SecureMicroservice } from '../../services/shared/secure-base';
import cors from 'cors';
import compression from 'compression';

class InsightGeneratorAPI extends SecureMicroservice {
  constructor() {
    super('insight-generator');
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
    // Generate insights endpoint
    this.app.post('/api/v1/generate', async (req: any, res: any) => {
      try {
        const { userId, timeframe = '30d' } = req.body;
        if (!userId) {
          return res.status(400).json({ error: 'userId required' });
        }

        // Placeholder for insight generation logic
        const insights = {
          spending: {
            total: 2450.75,
            categories: [
              { name: 'Food & Dining', amount: 650.25, percentage: 26.5 },
              { name: 'Transportation', amount: 450.00, percentage: 18.4 },
              { name: 'Entertainment', amount: 320.50, percentage: 13.1 }
            ]
          },
          trends: [
            'Spending on dining has increased by 15% compared to last month',
            'Transportation costs are consistent with historical patterns'
          ],
          recommendations: [
            'Consider reducing dining expenses by cooking more meals at home',
            'Look for subscription services you might not be using'
          ]
        };

        res.json({
          userId,
          timeframe,
          insights,
          generatedAt: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Insight generation failed', { error });
        res.status(500).json({ error: 'Insight generation failed' });
      }
    });

    // Budget tracking endpoint
    this.app.post('/api/v1/budget', async (req: any, res: any) => {
      try {
        const { userId, budgets } = req.body;
        if (!userId || !budgets) {
          return res.status(400).json({ error: 'userId and budgets required' });
        }

        // Placeholder for budget analysis logic
        res.json({
          userId,
          budgetStatus: 'on_track',
          alerts: [],
          recommendations: ['You are on track with your monthly budget'],
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Budget analysis failed', { error });
        res.status(500).json({ error: 'Budget analysis failed' });
      }
    });

    // Financial health score endpoint
    this.app.get('/api/v1/health-score/:userId', async (req: any, res: any) => {
      try {
        const { userId } = req.params;
        if (!userId) {
          return res.status(400).json({ error: 'userId required' });
        }

        // Placeholder for financial health calculation
        res.json({
          userId,
          healthScore: 7.5,
          factors: {
            savings: 8,
            spending: 7,
            debt: 6,
            investments: 8
          },
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Health score calculation failed', { error });
        res.status(500).json({ error: 'Health score calculation failed' });
      }
    });

    // Goal tracking endpoint
    this.app.post('/api/v1/goals', async (req: any, res: any) => {
      try {
        const { userId, goals } = req.body;
        if (!userId) {
          return res.status(400).json({ error: 'userId required' });
        }

        // Placeholder for goal tracking logic
        res.json({
          userId,
          goals: goals || [],
          progress: 'on_track',
          recommendations: ['Continue current savings rate to meet your goals'],
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        this.logger.error('Goal tracking failed', { error });
        res.status(500).json({ error: 'Goal tracking failed' });
      }
    });
  }

  async gracefulShutdown() {
    this.logger.info('Insight Generator Service shutting down gracefully');
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
const service = new InsightGeneratorAPI();
const port = parseInt(process.env.PORT || process.env.API_PORT || '8080');
service.start(port);

export { InsightGeneratorAPI };