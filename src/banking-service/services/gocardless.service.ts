import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import winston from 'winston';
import fetch from 'node-fetch';

export interface Institution {
  id: string;
  name: string;
  bic?: string;
  transaction_total_days: number;
  countries: string[];
  logo: string;
}

export interface Requisition {
  id: string;
  created: string;
  redirect: string;
  status: string;
  institution_id: string;
  agreement: string;
  reference: string;
  accounts: string[];
  user_language: string;
  link: string;
}

export interface AccountDetails {
  resourceId: string;
  iban?: string;
  currency: string;
  ownerName?: string;
  name?: string;
  product?: string;
  cashAccountType?: string;
}

export interface Balance {
  balanceAmount: {
    amount: string;
    currency: string;
  };
  balanceType: string;
  referenceDate: string;
}

export interface Transaction {
  transactionId?: string;
  bookingDate: string;
  valueDate?: string;
  transactionAmount: {
    amount: string;
    currency: string;
  };
  creditorName?: string;
  creditorAccount?: {
    iban?: string;
  };
  debtorName?: string;
  debtorAccount?: {
    iban?: string;
  };
  remittanceInformationUnstructured?: string;
  remittanceInformationStructured?: string;
  additionalInformation?: string;
  proprietaryBankTransactionCode?: string;
}

export interface TransactionsResponse {
  transactions: {
    booked: Transaction[];
    pending?: Transaction[];
  };
}

export class GoCardlessService {
  private readonly baseUrl = 'https://bankaccountdata.gocardless.com/api/v2';
  private readonly sandboxUrl = 'https://bankaccountdata-sandbox.gocardless.com/api/v2';
  private accessToken: string = '';
  private tokenExpiry: Date = new Date();
  // private refreshToken: string = ''; // Reserved for future use

  constructor(
    private logger: winston.Logger,
    private secrets: SecretManagerServiceClient
  ) {
    // Log which environment we're using
    this.logger.info('GoCardless service initialized', {
      environment: process.env.GOCARDLESS_ENV || 'production',
      apiUrl: this.apiUrl
    });
  }

  private get apiUrl(): string {
    return process.env.GOCARDLESS_ENV === 'sandbox' ? this.sandboxUrl : this.baseUrl;
  }

  private async getSecret(name: string): Promise<string> {
    // In development, use environment variables directly
    if (process.env.NODE_ENV === 'development') {
      const envVarName = name.toUpperCase().replace(/-/g, '_');
      const value = process.env[envVarName];
      if (!value) {
        throw new Error(`Environment variable ${envVarName} not set`);
      }
      return value;
    }

    // In production, use Google Secret Manager
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

  async authenticate(): Promise<void> {
    try {
      const secretId = await this.getSecret('gocardless-secret-id');
      const secretKey = await this.getSecret('gocardless-secret-key');

      const response = await fetch(`${this.apiUrl}/token/new/`, {
        method: 'POST',
        headers: {
          'accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ 
          secret_id: secretId, 
          secret_key: secretKey 
        })
      });

      if (!response.ok) {
        throw new Error(`Authentication failed: ${response.statusText}`);
      }

      const data: any = await response.json();
      this.accessToken = data.access;
      // this.refreshToken = data.refresh; // Reserved for future use
      this.tokenExpiry = new Date(Date.now() + data.access_expires * 1000);

      this.logger.info('GoCardless authentication successful', {
        expiresIn: data.access_expires
      });
    } catch (error) {
      this.logger.error('GoCardless authentication failed', { error });
      throw error;
    }
  }

  private async ensureAuthenticated(): Promise<void> {
    if (!this.accessToken || new Date() >= this.tokenExpiry) {
      await this.authenticate();
    }
  }

  private async makeRequest(
    path: string,
    options: any = {}
  ): Promise<any> {
    await this.ensureAuthenticated();

    const response = await fetch(`${this.apiUrl}${path}`, {
      method: options.method || 'GET',
      headers: {
        'accept': 'application/json',
        'Authorization': `Bearer ${this.accessToken}`,
        ...(options.headers || {})
      },
      body: options.body
    });

    if (!response.ok) {
      const error = await response.text();
      this.logger.error('GoCardless API error', {
        path,
        status: response.status,
        error
      });
      throw new Error(`GoCardless API error: ${response.statusText}`);
    }

    return await response.json();
  }

  async listInstitutions(country: string): Promise<Institution[]> {
    try {
      const institutions = await this.makeRequest(
        `/institutions/?country=${country}`
      );
      
      this.logger.info('Listed institutions', {
        country,
        count: institutions.length
      });

      return institutions;
    } catch (error) {
      this.logger.error('Failed to list institutions', { country, error });
      throw error;
    }
  }

  async searchInstitutions(query: string, country: string): Promise<Institution[]> {
    try {
      const institutions = await this.listInstitutions(country);
      
      const filtered = institutions.filter(inst =>
        inst.name.toLowerCase().includes(query.toLowerCase()) ||
        inst.id.toLowerCase().includes(query.toLowerCase())
      );

      return filtered;
    } catch (error) {
      this.logger.error('Failed to search institutions', { query, country, error });
      throw error;
    }
  }

  async createRequisition(
    institutionId: string,
    redirectUrl: string,
    reference?: string
  ): Promise<Requisition> {
    try {
      const requisition = await this.makeRequest('/requisitions/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          redirect: redirectUrl,
          institution_id: institutionId,
          reference: reference || crypto.randomUUID(),
          user_language: 'EN'
        })
      });

      this.logger.info('Created requisition', {
        requisitionId: requisition.id,
        institutionId
      });

      return requisition;
    } catch (error) {
      this.logger.error('Failed to create requisition', { institutionId, error });
      throw error;
    }
  }

  async getRequisition(requisitionId: string): Promise<Requisition> {
    try {
      const requisition = await this.makeRequest(`/requisitions/${requisitionId}/`);
      
      this.logger.info('Retrieved requisition', {
        requisitionId,
        status: requisition.status,
        accounts: requisition.accounts.length
      });

      return requisition;
    } catch (error) {
      this.logger.error('Failed to get requisition', { requisitionId, error });
      throw error;
    }
  }

  async deleteRequisition(requisitionId: string): Promise<void> {
    try {
      await this.makeRequest(`/requisitions/${requisitionId}/`, {
        method: 'DELETE'
      });

      this.logger.info('Deleted requisition', { requisitionId });
    } catch (error) {
      this.logger.error('Failed to delete requisition', { requisitionId, error });
      throw error;
    }
  }

  async getAccountDetails(accountId: string): Promise<AccountDetails> {
    try {
      const details = await this.makeRequest(`/accounts/${accountId}/details/`);
      
      return details.account;
    } catch (error) {
      this.logger.error('Failed to get account details', { accountId, error });
      throw error;
    }
  }

  async getAccountBalance(accountId: string): Promise<Balance[]> {
    try {
      const response = await this.makeRequest(`/accounts/${accountId}/balances/`);
      
      return response.balances;
    } catch (error) {
      this.logger.error('Failed to get account balance', { accountId, error });
      throw error;
    }
  }

  async getTransactions(
    accountId: string,
    dateFrom?: string,
    dateTo?: string
  ): Promise<TransactionsResponse> {
    try {
      let path = `/accounts/${accountId}/transactions/`;
      const params = new URLSearchParams();
      
      if (dateFrom) params.append('date_from', dateFrom);
      if (dateTo) params.append('date_to', dateTo);
      
      if (params.toString()) {
        path += `?${params.toString()}`;
      }

      const response = await this.makeRequest(path);
      
      this.logger.info('Retrieved transactions', {
        accountId,
        count: response.transactions.booked.length,
        dateFrom,
        dateTo
      });

      return response;
    } catch (error) {
      this.logger.error('Failed to get transactions', { accountId, error });
      throw error;
    }
  }
}