import { Firestore } from '@google-cloud/firestore';
import { Storage } from '@google-cloud/storage';
import { MonitoringHelper } from '../monitoring';
import winston from 'winston';
import * as crypto from 'crypto';
import archiver from 'archiver';

export interface GDPRRequest {
  id: string;
  userId: string;
  type: 'export' | 'delete' | 'access';
  status: 'pending' | 'processing' | 'completed' | 'failed';
  requestedAt: Date;
  completedAt?: Date;
  downloadUrl?: string;
  error?: string;
}

export interface UserConsent {
  userId: string;
  dataProcessing: boolean;
  marketing: boolean;
  analytics: boolean;
  consentedAt: Date;
  ipAddress?: string | undefined;
}

export class GDPRService {
  private firestore: Firestore;
  private storage: Storage;
  private bucketName: string;
  private logger: winston.Logger;
  private monitoring: MonitoringHelper;

  constructor() {
    this.firestore = new Firestore();
    this.storage = new Storage();
    this.bucketName = `${process.env.PROJECT_ID || 'athena-001'}-gdpr-exports`;
    
    // Setup logging
    this.logger = winston.createLogger({
      level: 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      defaultMeta: { service: 'gdpr-service' },
      transports: [new winston.transports.Console()]
    });
    
    this.monitoring = new MonitoringHelper(this.logger);
  }

  async exportUserData(userId: string): Promise<GDPRRequest> {
    const requestId = crypto.randomUUID();
    const request: GDPRRequest = {
      id: requestId,
      userId,
      type: 'export',
      status: 'pending',
      requestedAt: new Date(),
    };

    await this.firestore.collection('gdpr_requests').doc(requestId).set(request);
    this.logger.info('GDPR export request created', { requestId, userId });
    
    this.processExportAsync(requestId, userId);
    
    return request;
  }

  private async processExportAsync(requestId: string, userId: string): Promise<void> {
    try {
      await this.updateRequestStatus(requestId, 'processing');

      const userData = await this.collectUserData(userId);
      const exportUrl = await this.createDataExport(userId, userData);

      await this.updateRequestStatus(requestId, 'completed', { downloadUrl: exportUrl });
      
      this.monitoring.trackBusinessEvent('gdpr_export', 'success', { userId });
    } catch (error) {
      this.logger.error('GDPR export failed', { requestId, error });
      await this.updateRequestStatus(requestId, 'failed', { error: (error as Error).message });
      this.monitoring.trackBusinessEvent('gdpr_export', 'failure', { userId });
    }
  }

  private async collectUserData(userId: string): Promise<any> {
    const collections = [
      'users',
      'accounts',
      'transactions', 
      'documents',
      'insights',
      'audit_logs',
      'user_consents'
    ];

    const userData: any = {};

    for (const collection of collections) {
      try {
        const snapshot = await this.firestore
          .collection(collection)
          .where('userId', '==', userId)
          .get();

        userData[collection] = snapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
          _exportedAt: new Date().toISOString()
        }));
      } catch (error) {
        this.logger.warn(`Failed to export ${collection}`, { userId, error });
      }
    }

    const userDoc = await this.firestore.collection('users').doc(userId).get();
    if (userDoc.exists) {
      userData.profile = {
        ...userDoc.data(),
        _exportedAt: new Date().toISOString()
      };
    }

    return userData;
  }

  private async createDataExport(userId: string, data: any): Promise<string> {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const fileName = `gdpr-export-${userId}-${timestamp}.zip`;
    const file = this.storage.bucket(this.bucketName).file(fileName);

    const stream = file.createWriteStream({
      metadata: {
        contentType: 'application/zip',
        metadata: {
          userId,
          exportedAt: new Date().toISOString()
        }
      }
    });

    const archive = archiver.create('zip', { zlib: { level: 9 } });
    archive.pipe(stream);

    archive.append(JSON.stringify(data, null, 2), { name: 'user-data.json' });
    
    archive.append(this.generateReadme(userId), { name: 'README.txt' });

    await archive.finalize();

    const [signedUrl] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000 // 7 days
    });

    return signedUrl;
  }

  private generateReadme(userId: string): string {
    return `GDPR Data Export
================

User ID: ${userId}
Export Date: ${new Date().toISOString()}

This archive contains all personal data associated with your account.

Contents:
- user-data.json: Complete export of all your data

Data Categories:
- Profile information
- Account details
- Transaction history
- Uploaded documents
- Generated insights
- Audit logs
- Consent records

This export link will expire in 7 days.

For questions, contact: privacy@athena-finance.com`;
  }

  async deleteUserData(userId: string): Promise<GDPRRequest> {
    const requestId = crypto.randomUUID();
    const request: GDPRRequest = {
      id: requestId,
      userId,
      type: 'delete',
      status: 'pending',
      requestedAt: new Date(),
    };

    await this.firestore.collection('gdpr_requests').doc(requestId).set(request);
    this.logger.info('GDPR deletion request created', { requestId, userId });
    
    this.processDeleteAsync(requestId, userId);
    
    return request;
  }

  private async processDeleteAsync(requestId: string, userId: string): Promise<void> {
    try {
      await this.updateRequestStatus(requestId, 'processing');

      await this.anonymizeUser(userId);

      const collectionsToClean = [
        'accounts',
        'transactions',
        'documents', 
        'insights'
      ];

      for (const collection of collectionsToClean) {
        await this.deleteCollectionData(collection, userId);
      }

      await this.anonymizeAuditLogs(userId);

      await this.updateRequestStatus(requestId, 'completed');
      
      this.monitoring.trackBusinessEvent('gdpr_deletion', 'success', { userId });
    } catch (error) {
      this.logger.error('GDPR deletion failed', { requestId, error });
      await this.updateRequestStatus(requestId, 'failed', { error: (error as Error).message });
      this.monitoring.trackBusinessEvent('gdpr_deletion', 'failure', { userId });
    }
  }

  private async anonymizeUser(userId: string): Promise<void> {
    const userRef = this.firestore.collection('users').doc(userId);
    
    await userRef.update({
      email: `deleted-${userId}@anonymized.local`,
      firstName: 'DELETED',
      lastName: 'USER',
      passwordHash: 'DELETED',
      isDeleted: true,
      deletedAt: new Date(),
      personalDataRemoved: true
    });
  }

  private async deleteCollectionData(collection: string, userId: string): Promise<void> {
    const batch = this.firestore.batch();
    const snapshot = await this.firestore
      .collection(collection)
      .where('userId', '==', userId)
      .get();

    snapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    this.logger.info(`Deleted ${snapshot.size} documents from ${collection}`, { userId });
  }

  private async anonymizeAuditLogs(userId: string): Promise<void> {
    const batch = this.firestore.batch();
    const snapshot = await this.firestore
      .collection('audit_logs')
      .where('userId', '==', userId)
      .get();

    snapshot.docs.forEach(doc => {
      batch.update(doc.ref, {
        userId: 'ANONYMIZED',
        userEmail: 'anonymized@deleted.local',
        personalDataRemoved: true
      });
    });

    await batch.commit();
  }

  async recordConsent(userId: string, consent: Partial<UserConsent>): Promise<void> {
    const consentRecord: UserConsent = {
      userId,
      dataProcessing: consent.dataProcessing ?? false,
      marketing: consent.marketing ?? false,
      analytics: consent.analytics ?? false,
      consentedAt: new Date(),
      ipAddress: consent.ipAddress
    };

    await this.firestore
      .collection('user_consents')
      .doc(`${userId}-${Date.now()}`)
      .set(consentRecord);

    await this.firestore
      .collection('users')
      .doc(userId)
      .update({
        currentConsent: consentRecord,
        consentUpdatedAt: new Date()
      });

    this.logger.info('User consent recorded', { userId, consent: consentRecord });
    this.monitoring.trackBusinessEvent('consent_updated', 'success', { userId });
  }

  async getConsentHistory(userId: string): Promise<UserConsent[]> {
    const snapshot = await this.firestore
      .collection('user_consents')
      .where('userId', '==', userId)
      .orderBy('consentedAt', 'desc')
      .get();

    return snapshot.docs.map(doc => doc.data() as UserConsent);
  }

  async getGDPRRequests(userId: string): Promise<GDPRRequest[]> {
    const snapshot = await this.firestore
      .collection('gdpr_requests')
      .where('userId', '==', userId)
      .orderBy('requestedAt', 'desc')
      .get();

    return snapshot.docs.map(doc => doc.data() as GDPRRequest);
  }

  private async updateRequestStatus(
    requestId: string, 
    status: GDPRRequest['status'],
    additionalData?: Partial<GDPRRequest>
  ): Promise<void> {
    const update: Partial<GDPRRequest> = {
      status,
      ...additionalData
    };

    if (status === 'completed' || status === 'failed') {
      update.completedAt = new Date();
    }

    await this.firestore
      .collection('gdpr_requests')
      .doc(requestId)
      .update(update);
  }
}