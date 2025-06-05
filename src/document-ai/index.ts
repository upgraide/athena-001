import { SecureMicroservice } from '../../services/shared/secure-base';
import cors from 'cors';
import compression from 'compression';

class DocumentAIAPI extends SecureMicroservice {
  constructor() {
    super('document-ai');
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
    // Document processing endpoint
    this.app.post('/api/v1/process', async (req: any, res: any) => {
      try {
        const { document } = req.body;
        if (!document) {
          return res.status(400).json({ error: 'Document required' });
        }

        // Placeholder for document processing logic
        res.json({
          message: 'Document processing initiated',
          documentId: document.id,
          status: 'processing'
        });
      } catch (error) {
        this.logger.error('Document processing failed', { error });
        res.status(500).json({ error: 'Document processing failed' });
      }
    });

    // OCR endpoint
    this.app.post('/api/v1/ocr', async (req: any, res: any) => {
      try {
        const { imageUrl } = req.body;
        if (!imageUrl) {
          return res.status(400).json({ error: 'Image URL required' });
        }

        // Placeholder for OCR logic
        res.json({
          text: 'Placeholder OCR result',
          confidence: 0.95
        });
      } catch (error) {
        this.logger.error('OCR processing failed', { error });
        res.status(500).json({ error: 'OCR processing failed' });
      }
    });
  }

  async gracefulShutdown() {
    this.logger.info('Document AI Service shutting down gracefully');
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
const service = new DocumentAIAPI();
const port = parseInt(process.env.PORT || process.env.API_PORT || '8080');
service.start(port);

export { DocumentAIAPI };