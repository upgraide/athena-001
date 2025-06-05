#!/bin/bash
set -e

PROJECT_ID="athena-finance-001"
REGION="europe-west3"

echo "🚀 Deploying secure microservice architecture..."

# 1. Initialize Terraform
cd infrastructure/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 2. Verify encryption setup
echo "🔐 Verifying encryption setup..."
gcloud kms keys list --location=europe --keyring=athena-security-keyring

# 3. Test VPC connectivity
echo "🌐 Testing VPC setup..."
gcloud compute networks describe athena-secure-vpc

# 4. Verify Firestore encryption
echo "🗄️ Verifying Firestore encryption..."
gcloud firestore databases describe --database="(default)"

# 5. Test Secret Manager
echo "🔑 Testing Secret Manager..."
echo "test-secret" | gcloud secrets create test-secret --data-file=-
gcloud secrets versions access latest --secret="test-secret"
gcloud secrets delete test-secret --quiet

echo "✅ Secure microservice architecture deployed successfully!"