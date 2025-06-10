# GoCardless Bank Account Data Setup Guide

This guide will help you set up GoCardless Bank Account Data API to connect your real bank accounts.

## Prerequisites

1. A GoCardless account (sign up at https://gocardless.com/bank-account-data/)
2. Access to the GoCardless dashboard
3. Your bank accounts ready to connect

## Step 1: Get GoCardless Credentials

1. **Sign up for GoCardless Bank Account Data**
   - Go to https://gocardless.com/bank-account-data/
   - Click "Get started" or "Start free trial"
   - Complete the registration process

2. **Access the Dashboard**
   - Log in to your GoCardless dashboard
   - Navigate to the "Bank Account Data" section

3. **Get your API credentials**
   - Go to "User Secrets" section
   - Create a new secret if you don't have one
   - Copy your `secret_id` and `secret_key`

## Step 2: Configure Local Environment

1. **Create a `.env` file in the banking service directory**:
   ```bash
   cd src/banking-service
   cp .env.example .env
   ```

2. **Add your GoCardless credentials**:
   ```env
   # Use 'sandbox' for testing, 'production' for real accounts
   GOCARDLESS_ENV=production
   GOCARDLESS_SECRET_ID=your-actual-secret-id
   GOCARDLESS_SECRET_KEY=your-actual-secret-key
   ```

## Step 3: Test with Sandbox (Optional)

Before connecting real accounts, you can test with sandbox:

1. **Use sandbox credentials**:
   ```env
   GOCARDLESS_ENV=sandbox
   # Sandbox credentials from GoCardless dashboard
   GOCARDLESS_SECRET_ID=your-sandbox-secret-id
   GOCARDLESS_SECRET_KEY=your-sandbox-secret-key
   ```

2. **Test with Sandbox Finance**:
   - Institution ID: `SANDBOXFINANCE_SFIN0000`
   - This provides mock data for testing

## Step 4: Connect Real Bank Accounts

1. **Start the services**:
   ```bash
   # Terminal 1: Start auth service
   cd src/auth-service
   npm run dev

   # Terminal 2: Start banking service
   cd src/banking-service
   npm run dev
   ```

2. **Run the banking test script**:
   ```bash
   ./scripts/testing/test-banking.sh
   ```

3. **Follow the connection flow**:
   - The script will create a connection and provide an auth URL
   - Visit the auth URL in your browser
   - Select your bank and authenticate
   - Complete the authorization
   - You'll be redirected back to complete the connection

## Step 5: Available Banks

With production credentials, you can connect to:

### UK Banks
- Revolut (`REVOLUT_REVOGB21`)
- Monzo (`MONZO_MONZGB2L`)
- Barclays (`BARCLAYS_BARCGB22`)
- HSBC (`HSBC_HBUKGB4B`)
- Lloyds (`LLOYDS_LOYDGB2L`)
- NatWest (`NATWEST_NWBKGB2L`)
- Santander (`SANTANDER_ABBYGB2L`)
- And 500+ more UK banks

### European Banks
- N26 (`N26_NTSBDEB1`)
- Wise (`WISE_WISETRIS`)
- Deutsche Bank (`DEUTSCHEBANK_DEUTDEFF`)
- ING (`ING_INGDDEFF`)
- And 2000+ more European banks

## Step 6: Production Deployment

For production deployment on Google Cloud:

1. **Add secrets to Google Secret Manager**:
   ```bash
   # Create the secrets
   echo -n "your-production-secret-id" | gcloud secrets create gocardless-secret-id --data-file=-
   echo -n "your-production-secret-key" | gcloud secrets create gocardless-secret-key --data-file=-
   ```

2. **Deploy the service**:
   ```bash
   ./scripts/deployment/deploy-services.sh production
   ```

## Important Notes

1. **Rate Limits**: GoCardless enforces 10 API calls per day per endpoint per account
2. **Data Access**: You get 24 months of transaction history
3. **Session Duration**: Connections last 90 days before re-authentication is needed
4. **Security**: All account IDs and requisition IDs are encrypted with Google Cloud KMS
5. **Compliance**: GoCardless is PSD2 compliant and regulated as an AISP

## Troubleshooting

### "Institution not found" error
- Ensure you're using the correct country code
- Check that the institution ID is valid
- Verify you're using production credentials for real banks

### Authentication fails
- Check your credentials are correct
- Ensure you're using the right environment (sandbox/production)
- Verify the redirect URL matches your configuration

### No transactions returned
- Some banks may have delays in providing transaction data
- Check the date range you're requesting
- Ensure the account has transactions in the requested period

## Support

- GoCardless Documentation: https://developer.gocardless.com/bank-account-data/
- GoCardless Support: support@gocardless.com
- API Status: https://www.gocardless-status.com/