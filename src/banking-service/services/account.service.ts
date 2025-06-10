import { Firestore } from '@google-cloud/firestore';
import winston from 'winston';

export interface BankAccount {
  id: string;
  userId: string;
  connectionId: string;
  externalAccountId: string;
  accountNumber?: string;
  iban?: string;
  currency: string;
  accountType: 'personal' | 'business' | 'savings' | 'credit';
  balance?: {
    amount: number;
    currency: string;
    lastUpdated: Date;
  };
  institutionName: string;
  isActive: boolean;
  createdAt: Date;
  lastSyncedAt?: Date;
}

export interface AccountSummary {
  totalBalance: {
    [currency: string]: number;
  };
  accountsByType: {
    [type: string]: number;
  };
  accountsByInstitution: {
    [institution: string]: number;
  };
  totalAccounts: number;
  lastUpdated: Date;
}

export class AccountService {
  constructor(
    private firestore: Firestore,
    private logger: winston.Logger
  ) {}

  async createAccount(data: Omit<BankAccount, 'id' | 'createdAt'>): Promise<BankAccount> {
    try {
      const accountRef = this.firestore.collection('bank_accounts').doc();
      const account: BankAccount = {
        ...data,
        id: accountRef.id,
        createdAt: new Date()
      };

      await accountRef.set(account);

      this.logger.info('Account created', {
        accountId: account.id,
        userId: account.userId,
        institutionName: account.institutionName,
        currency: account.currency
      });

      return account;
    } catch (error) {
      this.logger.error('Failed to create account', { error });
      throw error;
    }
  }

  async getUserAccounts(userId: string): Promise<BankAccount[]> {
    try {
      const snapshot = await this.firestore
        .collection('bank_accounts')
        .where('userId', '==', userId)
        .where('isActive', '==', true)
        .orderBy('createdAt', 'desc')
        .get();

      const accounts = snapshot.docs.map(doc => ({
        ...doc.data(),
        id: doc.id
      })) as BankAccount[];

      return accounts;
    } catch (error) {
      this.logger.error('Failed to get user accounts', { userId, error });
      throw error;
    }
  }

  async getAccount(accountId: string, userId: string): Promise<BankAccount | null> {
    try {
      const doc = await this.firestore
        .collection('bank_accounts')
        .doc(accountId)
        .get();

      if (!doc.exists) {
        return null;
      }

      const account = doc.data() as BankAccount;
      
      // Verify ownership
      if (account.userId !== userId) {
        throw new Error('Unauthorized access to account');
      }

      return {
        ...account,
        id: doc.id
      };
    } catch (error) {
      this.logger.error('Failed to get account', { accountId, userId, error });
      throw error;
    }
  }

  async getAccountByExternalId(externalAccountId: string): Promise<BankAccount | null> {
    try {
      const snapshot = await this.firestore
        .collection('bank_accounts')
        .where('externalAccountId', '==', externalAccountId)
        .limit(1)
        .get();

      if (snapshot.empty) {
        return null;
      }

      const doc = snapshot.docs[0];
      return {
        ...doc.data(),
        id: doc.id
      } as BankAccount;
    } catch (error) {
      this.logger.error('Failed to get account by external ID', { externalAccountId, error });
      throw error;
    }
  }

  async updateAccountBalance(
    accountId: string,
    balance: { amount: number; currency: string }
  ): Promise<void> {
    try {
      await this.firestore
        .collection('bank_accounts')
        .doc(accountId)
        .update({
          balance: {
            ...balance,
            lastUpdated: new Date()
          }
        });

      this.logger.info('Account balance updated', {
        accountId,
        amount: balance.amount,
        currency: balance.currency
      });
    } catch (error) {
      this.logger.error('Failed to update account balance', { accountId, error });
      throw error;
    }
  }

  async getAccountBalance(accountId: string, userId: string): Promise<any> {
    try {
      const account = await this.getAccount(accountId, userId);
      if (!account) {
        throw new Error('Account not found');
      }

      if (!account.balance) {
        return {
          amount: 0,
          currency: account.currency,
          lastUpdated: null,
          message: 'Balance not yet synced'
        };
      }

      return {
        ...account.balance,
        accountName: account.iban || account.accountNumber,
        institutionName: account.institutionName
      };
    } catch (error) {
      this.logger.error('Failed to get account balance', { accountId, error });
      throw error;
    }
  }

  async updateLastSync(accountId: string): Promise<void> {
    try {
      await this.firestore
        .collection('bank_accounts')
        .doc(accountId)
        .update({
          lastSyncedAt: new Date()
        });

      this.logger.info('Account last sync updated', { accountId });
    } catch (error) {
      this.logger.error('Failed to update last sync', { accountId, error });
      throw error;
    }
  }

  async getAccountsSummary(userId: string): Promise<AccountSummary> {
    try {
      const accounts = await this.getUserAccounts(userId);

      const summary: AccountSummary = {
        totalBalance: {},
        accountsByType: {},
        accountsByInstitution: {},
        totalAccounts: accounts.length,
        lastUpdated: new Date()
      };

      for (const account of accounts) {
        // Aggregate balances by currency
        if (account.balance) {
          const currency = account.balance.currency;
          summary.totalBalance[currency] = 
            (summary.totalBalance[currency] || 0) + account.balance.amount;
        }

        // Count by type
        summary.accountsByType[account.accountType] = 
          (summary.accountsByType[account.accountType] || 0) + 1;

        // Count by institution
        summary.accountsByInstitution[account.institutionName] = 
          (summary.accountsByInstitution[account.institutionName] || 0) + 1;
      }

      this.logger.info('Generated accounts summary', {
        userId,
        totalAccounts: summary.totalAccounts,
        currencies: Object.keys(summary.totalBalance)
      });

      return summary;
    } catch (error) {
      this.logger.error('Failed to get accounts summary', { userId, error });
      throw error;
    }
  }

  async deactivateAccount(accountId: string, userId: string): Promise<void> {
    try {
      const account = await this.getAccount(accountId, userId);
      if (!account) {
        throw new Error('Account not found');
      }

      await this.firestore
        .collection('bank_accounts')
        .doc(accountId)
        .update({
          isActive: false,
          deactivatedAt: new Date()
        });

      this.logger.info('Account deactivated', { accountId, userId });
    } catch (error) {
      this.logger.error('Failed to deactivate account', { accountId, error });
      throw error;
    }
  }
}