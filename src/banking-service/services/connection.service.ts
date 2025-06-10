import { Firestore } from '@google-cloud/firestore';
import { KeyManagementServiceClient } from '@google-cloud/kms';
import winston from 'winston';
import { GoCardlessService } from './gocardless.service';
import { v4 as uuidv4 } from 'uuid';

export interface BankConnection {
  id: string;
  userId: string;
  requisitionId: string;
  institutionId: string;
  institutionName: string;
  accountType: 'personal' | 'business' | 'savings' | 'credit';
  status: 'pending' | 'linked' | 'expired' | 'error';
  createdAt: Date;
  expiresAt: Date;
  lastSyncedAt?: Date;
  error?: string;
  metadata?: {
    country: string;
    logo?: string;
  };
}

export interface ConnectionResponse {
  connectionId: string;
  authUrl: string;
  expiresIn: number;
}

export class ConnectionService {
  constructor(
    private firestore: Firestore,
    private logger: winston.Logger,
    private goCardlessService: GoCardlessService,
    private kms: KeyManagementServiceClient
  ) {}

  private async encrypt(data: string): Promise<string> {
    try {
      const projectId = process.env.PROJECT_ID;
      const locationId = 'europe';
      const keyRingId = 'athena-security-keyring';
      const cryptoKeyId = 'banking-data-key';
      
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

  private async decrypt(encryptedData: string): Promise<string> {
    try {
      const projectId = process.env.PROJECT_ID;
      const locationId = 'europe';
      const keyRingId = 'athena-security-keyring';
      const cryptoKeyId = 'banking-data-key';
      
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

  async initiateConnection(
    userId: string,
    institutionId: string,
    accountType: string
  ): Promise<ConnectionResponse> {
    try {
      // Get institution details
      const institutions = await this.goCardlessService.searchInstitutions(
        institutionId,
        'GB' // Default to GB, could be made dynamic
      );
      
      const institution = institutions.find(i => i.id === institutionId);
      if (!institution) {
        throw new Error('Institution not found');
      }

      // Create requisition with GoCardless
      const redirectUrl = `${process.env.APP_URL || 'http://localhost:8084'}/api/v1/banking/callback`;
      const reference = uuidv4();
      const requisition = await this.goCardlessService.createRequisition(
        institutionId,
        redirectUrl,
        reference
      );

      // Encrypt requisition ID before storing
      const encryptedRequisitionId = await this.encrypt(requisition.id);

      // Store connection in database
      const connectionRef = this.firestore.collection('bank_connections').doc();
      const connection: BankConnection = {
        id: connectionRef.id,
        userId,
        requisitionId: encryptedRequisitionId,
        institutionId,
        institutionName: institution.name,
        accountType: accountType as BankConnection['accountType'],
        status: 'pending',
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000), // 90 days
        metadata: {
          country: institution.countries[0],
          logo: institution.logo
        }
      };

      await connectionRef.set(connection);

      this.logger.info('Bank connection initiated', {
        connectionId: connection.id,
        userId,
        institutionId,
        institutionName: institution.name
      });

      return {
        connectionId: connection.id,
        authUrl: requisition.link,
        expiresIn: 300 // 5 minutes
      };
    } catch (error) {
      this.logger.error('Failed to initiate connection', {
        userId,
        institutionId,
        error
      });
      throw error;
    }
  }

  async handleCallback(reference: string): Promise<void> {
    try {
      // Find connection by reference
      const connectionsSnapshot = await this.firestore
        .collection('bank_connections')
        .where('status', '==', 'pending')
        .get();

      let connection: BankConnection | null = null;
      let connectionDoc: any = null;

      for (const doc of connectionsSnapshot.docs) {
        const data = doc.data() as BankConnection;
        try {
          const decryptedRequisitionId = await this.decrypt(data.requisitionId);
          const requisition = await this.goCardlessService.getRequisition(decryptedRequisitionId);
          
          if (requisition.reference === reference) {
            connection = data;
            connectionDoc = doc;
            break;
          }
        } catch (err) {
          // Continue searching if decryption fails
          continue;
        }
      }

      if (!connection || !connectionDoc) {
        throw new Error('Connection not found for reference');
      }

      // Get requisition details
      const requisitionId = await this.decrypt(connection.requisitionId);
      const requisition = await this.goCardlessService.getRequisition(requisitionId);

      if (requisition.status === 'LN') { // Linked successfully
        // Update connection status
        await connectionDoc.ref.update({
          status: 'linked',
          lastSyncedAt: new Date()
        });

        // Process accounts
        for (const accountId of requisition.accounts) {
          await this.processAccount(connection, accountId);
        }

        this.logger.info('Bank connection completed', {
          connectionId: connection.id,
          userId: connection.userId,
          accountsLinked: requisition.accounts.length
        });
      } else {
        // Handle error status
        await connectionDoc.ref.update({
          status: 'error',
          error: `Connection failed with status: ${requisition.status}`
        });
      }
    } catch (error) {
      this.logger.error('Failed to handle callback', { reference, error });
      throw error;
    }
  }

  private async processAccount(connection: BankConnection, externalAccountId: string): Promise<void> {
    try {
      // Get account details from GoCardless
      const accountDetails = await this.goCardlessService.getAccountDetails(externalAccountId);
      const balances = await this.goCardlessService.getAccountBalance(externalAccountId);

      // Find the current balance
      const currentBalance = balances.find(b => b.balanceType === 'expected') || balances[0];

      // Store account in database
      const accountRef = this.firestore.collection('bank_accounts').doc();
      await accountRef.set({
        id: accountRef.id,
        userId: connection.userId,
        connectionId: connection.id,
        externalAccountId: await this.encrypt(externalAccountId),
        accountNumber: accountDetails.resourceId,
        iban: accountDetails.iban,
        currency: accountDetails.currency,
        accountType: connection.accountType,
        balance: currentBalance ? {
          amount: parseFloat(currentBalance.balanceAmount.amount),
          currency: currentBalance.balanceAmount.currency,
          lastUpdated: new Date()
        } : null,
        institutionName: connection.institutionName,
        isActive: true,
        createdAt: new Date()
      });

      this.logger.info('Account processed', {
        accountId: accountRef.id,
        connectionId: connection.id,
        currency: accountDetails.currency
      });
    } catch (error) {
      this.logger.error('Failed to process account', {
        connectionId: connection.id,
        externalAccountId,
        error
      });
      throw error;
    }
  }

  async getUserConnections(userId: string): Promise<BankConnection[]> {
    try {
      const snapshot = await this.firestore
        .collection('bank_connections')
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc')
        .get();

      const connections = snapshot.docs.map(doc => ({
        ...doc.data(),
        id: doc.id
      })) as BankConnection[];

      // Decrypt requisition IDs for display (optional)
      // Note: In production, you might not want to expose these
      
      return connections;
    } catch (error) {
      this.logger.error('Failed to get user connections', { userId, error });
      throw error;
    }
  }

  async getConnection(connectionId: string, userId: string): Promise<BankConnection | null> {
    try {
      const doc = await this.firestore
        .collection('bank_connections')
        .doc(connectionId)
        .get();

      if (!doc.exists) {
        return null;
      }

      const connection = doc.data() as BankConnection;
      
      // Verify ownership
      if (connection.userId !== userId) {
        throw new Error('Unauthorized access to connection');
      }

      return {
        ...connection,
        id: doc.id
      };
    } catch (error) {
      this.logger.error('Failed to get connection', { connectionId, userId, error });
      throw error;
    }
  }

  async refreshConnection(connectionId: string, userId: string): Promise<any> {
    try {
      const connection = await this.getConnection(connectionId, userId);
      if (!connection) {
        throw new Error('Connection not found');
      }

      // Check if connection is expired
      if (new Date() > connection.expiresAt) {
        throw new Error('Connection has expired. Please re-authenticate.');
      }

      // Trigger sync for all accounts in this connection
      const accountsSnapshot = await this.firestore
        .collection('bank_accounts')
        .where('connectionId', '==', connectionId)
        .get();

      const syncResults: Array<{ accountId: string; status: string }> = [];
      for (const doc of accountsSnapshot.docs) {
        // const account = doc.data(); // Not needed, just counting
        // Sync will be handled by transaction service
        syncResults.push({
          accountId: doc.id,
          status: 'queued'
        });
      }

      // Update last synced timestamp
      await this.firestore
        .collection('bank_connections')
        .doc(connectionId)
        .update({
          lastSyncedAt: new Date()
        });

      return {
        connectionId,
        accountsSynced: syncResults.length,
        results: syncResults
      };
    } catch (error) {
      this.logger.error('Failed to refresh connection', { connectionId, error });
      throw error;
    }
  }

  async deleteConnection(connectionId: string, userId: string): Promise<void> {
    try {
      const connection = await this.getConnection(connectionId, userId);
      if (!connection) {
        throw new Error('Connection not found');
      }

      // Delete from GoCardless
      try {
        const requisitionId = await this.decrypt(connection.requisitionId);
        await this.goCardlessService.deleteRequisition(requisitionId);
      } catch (error) {
        this.logger.warn('Failed to delete requisition from GoCardless', { error });
      }

      // Delete all associated accounts
      const accountsSnapshot = await this.firestore
        .collection('bank_accounts')
        .where('connectionId', '==', connectionId)
        .get();

      const batch = this.firestore.batch();
      accountsSnapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
      });

      // Delete connection
      batch.delete(this.firestore.collection('bank_connections').doc(connectionId));
      
      await batch.commit();

      this.logger.info('Connection deleted', {
        connectionId,
        userId,
        accountsDeleted: accountsSnapshot.size
      });
    } catch (error) {
      this.logger.error('Failed to delete connection', { connectionId, error });
      throw error;
    }
  }
}