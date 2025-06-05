import express from 'express';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { Firestore } from '@google-cloud/firestore';
import { KeyManagementServiceClient } from '@google-cloud/kms';
import { v4 as uuidv4 } from 'uuid';
import winston from 'winston';
import { LoggingWinston } from '@google-cloud/logging-winston';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';

// Secure base class for all microservices
export abstract class SecureMicroservice {
  protected app: express.Application;
  protected firestore: Firestore;
  protected secrets: SecretManagerServiceClient;
  protected kms: KeyManagementServiceClient;
  protected logger!: winston.Logger;
  
  constructor(protected serviceName: string) {
    this.app = express();
    this.firestore = new Firestore();
    this.secrets = new SecretManagerServiceClient();
    this.kms = new KeyManagementServiceClient();
    
    this.setupLogging();
    this.setupSecurity();
    this.setupHealthChecks();
  }
  
  private setupLogging() {
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      defaultMeta: { 
        service: this.serviceName,
        version: process.env.SERVICE_VERSION || '1.0.0'
      },
      transports: [
        new winston.transports.Console({
          format: winston.format.simple()
        }),
        new LoggingWinston({
          ...(process.env.PROJECT_ID && { projectId: process.env.PROJECT_ID }),
          ...(process.env.GOOGLE_APPLICATION_CREDENTIALS && { keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS }),
          labels: { 
            service: this.serviceName,
            environment: process.env.NODE_ENV || 'development'
          }
        })
      ]
    });
  }
  
  private setupSecurity() {
    // Helmet for security headers
    this.app.use(helmet({
      hsts: {
        maxAge: 31536000,
        includeSubDomains: true,
        preload: true
      },
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'", "'unsafe-inline'"],
          imgSrc: ["'self'", "data:", "https:"],
          connectSrc: ["'self'"],
          fontSrc: ["'self'"],
          objectSrc: ["'none'"],
          mediaSrc: ["'self'"],
          frameSrc: ["'none'"],
        },
      },
      referrerPolicy: { policy: 'strict-origin-when-cross-origin' }
    }));
    
    // Rate limiting
    const limiter = rateLimit({
      windowMs: 60 * 1000, // 1 minute
      max: 100, // 100 requests per minute per IP
      message: 'Too many requests from this IP',
      standardHeaders: true,
      legacyHeaders: false,
      skip: (req) => {
        // Skip rate limiting for health checks
        return req.path === '/health' || req.path === '/ready';
      }
    });
    this.app.use(limiter);
    
    // Request ID and logging
    this.app.use((req: any, res: any, next: any) => {
      req.id = req.headers['x-request-id'] as string || uuidv4();
      res.setHeader('x-request-id', req.id);
      
      this.logger.info('Request received', {
        requestId: req.id,
        method: req.method,
        path: req.path,
        userAgent: req.headers['user-agent'],
        ip: req.ip
      });
      
      next();
    });
    
    // JSON parsing with size limit
    this.app.use(express.json({ limit: '10mb' }));
    
    // Global error handler
    this.app.use((err: any, req: any, res: any, next: any) => {
      this.logger.error('Request error', {
        requestId: req.id,
        error: err.message,
        stack: err.stack,
        path: req.path,
        method: req.method
      });
      
      const statusCode = err.status || err.statusCode || 500;
      const message = process.env.NODE_ENV === 'production' 
        ? 'Internal server error' 
        : err.message;
      
      res.status(statusCode).json({
        error: {
          message,
          requestId: req.id,
          timestamp: new Date().toISOString()
        }
      });
    });
  }
  
  private setupHealthChecks() {
    this.app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        service: this.serviceName,
        timestamp: new Date().toISOString(),
        uptime: process.uptime()
      });
    });
    
    this.app.get('/ready', async (req, res) => {
      try {
        // Check Firestore connection
        await this.firestore.collection('_health').doc('check').set({
          timestamp: new Date(),
          service: this.serviceName
        });
        
        res.json({ 
          status: 'ready',
          checks: {
            firestore: 'ok'
          }
        });
      } catch (error: any) {
        this.logger.error('Readiness check failed', { error });
        res.status(503).json({ 
          status: 'not ready',
          error: error.message 
        });
      }
    });
  }
  
  // Secure secret retrieval with caching
  async getSecret(name: string): Promise<string> {
    try {
      const projectId = process.env.PROJECT_ID;
      const [version] = await this.secrets.accessSecretVersion({
        name: `projects/${projectId}/secrets/${name}/versions/latest`,
      });
      
      const payload = version.payload?.data?.toString();
      if (!payload) {
        throw new Error(`Secret ${name} not found or empty`);
      }
      
      return payload;
    } catch (error) {
      this.logger.error('Failed to retrieve secret', { secret: name, error });
      throw new Error(`Failed to retrieve secret: ${name}`);
    }
  }
  
  // Encrypt sensitive data with KMS
  async encrypt(data: string, keyName?: string): Promise<string> {
    try {
      const projectId = process.env.PROJECT_ID;
      const locationId = 'europe';
      const keyRingId = 'athena-security-keyring';
      const cryptoKeyId = keyName || 'data-encryption-key';
      
      const name = this.kms.cryptoKeyPath(projectId!, locationId, keyRingId, cryptoKeyId);
      
      const [result] = await this.kms.encrypt({
        name,
        plaintext: Buffer.from(data)
      });
      
      return Buffer.from(result.ciphertext as Uint8Array).toString('base64');
    } catch (error) {
      this.logger.error('Encryption failed', { error });
      throw new Error('Failed to encrypt data');
    }
  }
  
  // Decrypt sensitive data with KMS
  async decrypt(encryptedData: string, keyName?: string): Promise<string> {
    try {
      const projectId = process.env.PROJECT_ID;
      const locationId = 'europe';
      const keyRingId = 'athena-security-keyring';
      const cryptoKeyId = keyName || 'data-encryption-key';
      
      const name = this.kms.cryptoKeyPath(projectId!, locationId, keyRingId, cryptoKeyId);
      
      const [result] = await this.kms.decrypt({
        name,
        ciphertext: Buffer.from(encryptedData, 'base64'),
      });
      
      return Buffer.from(result.plaintext as Uint8Array).toString();
    } catch (error) {
      this.logger.error('Decryption failed', { error });
      throw new Error('Failed to decrypt data');
    }
  }
  
  // Audit log for security events
  async auditLog(action: string, details: any, riskScore = 'low') {
    await this.firestore.collection('audit_logs').add({
      timestamp: new Date(),
      service: this.serviceName,
      action,
      details,
      riskScore,
      environment: process.env.NODE_ENV
    });
  }
  
  start(port = 8080) {
    this.app.listen(port, () => {
      this.logger.info(`${this.serviceName} started securely`, { 
        port,
        environment: process.env.NODE_ENV,
        nodeVersion: process.version
      });
    });
  }
}