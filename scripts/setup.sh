#!/bin/bash
set -e

PROJECT_ID="athena-finance-001"
REGION="europe-west3"
BILLING_ACCOUNT_ID="" # You'll need to provide this

echo "🚀 Setting up Athena Finance secure infrastructure..."

# 1. Authenticate with Google Cloud (if not already done)
echo "📋 Checking Google Cloud authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "❌ Not authenticated. Please run: gcloud auth login"
    exit 1
fi

# 2. Check if project exists, create if it doesn't
echo "🏗️ Checking/creating GCP project..."
if ! gcloud projects describe $PROJECT_ID >/dev/null 2>&1; then
    echo "Creating project $PROJECT_ID..."
    gcloud projects create $PROJECT_ID --name="Athena Finance"
    
    if [ -n "$BILLING_ACCOUNT_ID" ]; then
        echo "Linking billing account..."
        gcloud beta billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID
    else
        echo "⚠️ Warning: No billing account provided. You'll need to link one manually."
        echo "   Run: gcloud beta billing accounts list"
        echo "   Then: gcloud beta billing projects link $PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT_ID"
    fi
else
    echo "✅ Project $PROJECT_ID already exists"
fi

# 3. Set default project
gcloud config set project $PROJECT_ID

# 4. Enable required APIs
echo "🔧 Enabling required Google Cloud APIs..."
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  run.googleapis.com \
  firestore.googleapis.com \
  secretmanager.googleapis.com \
  cloudkms.googleapis.com \
  vpcaccess.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  servicenetworking.googleapis.com

echo "⏳ Waiting for APIs to be fully enabled (30 seconds)..."
sleep 30

# 5. Check if Terraform backend bucket exists
BUCKET_NAME="${PROJECT_ID}-terraform-state"
echo "📦 Setting up Terraform state bucket..."
if ! gsutil ls -b gs://$BUCKET_NAME >/dev/null 2>&1; then
    echo "Creating Terraform state bucket..."
    gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME
    gsutil versioning set on gs://$BUCKET_NAME
    gsutil lifecycle set - gs://$BUCKET_NAME <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 365,
          "isLive": false
        }
      }
    ]
  }
}
EOF
else
    echo "✅ Terraform state bucket already exists"
fi

# 6. Create service account for Terraform
SA_NAME="terraform-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "🔑 Setting up Terraform service account..."
if ! gcloud iam service-accounts describe $SA_EMAIL >/dev/null 2>&1; then
    echo "Creating Terraform service account..."
    gcloud iam service-accounts create $SA_NAME \
        --display-name="Terraform Service Account" \
        --description="Service account for Terraform infrastructure management"
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="roles/editor"
    
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="roles/cloudkms.admin"
    
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="roles/compute.networkAdmin"
else
    echo "✅ Terraform service account already exists"
fi

# 7. Create and download service account key
KEY_FILE="./keys/terraform-sa-key.json"
echo "🔐 Setting up service account key..."
mkdir -p ./keys
if [ ! -f "$KEY_FILE" ]; then
    echo "Creating service account key..."
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$SA_EMAIL
    chmod 600 $KEY_FILE
else
    echo "✅ Service account key already exists"
fi

# 8. Create Terraform backend configuration
echo "📝 Creating Terraform backend configuration..."
cat > infrastructure/terraform/backend.tf <<EOF
terraform {
  backend "gcs" {
    bucket  = "${BUCKET_NAME}"
    prefix  = "terraform/state"
  }
}
EOF

# 9. Create terraform.tfvars
echo "📝 Creating Terraform variables file..."
cat > infrastructure/terraform/terraform.tfvars <<EOF
project_id = "${PROJECT_ID}"
region     = "${REGION}"
EOF

echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review the generated files in infrastructure/terraform/"
echo "2. Run: cd infrastructure/terraform && terraform init"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply"
echo ""
echo "Environment variables to set:"
echo "export GOOGLE_APPLICATION_CREDENTIALS=\"$(pwd)/keys/terraform-sa-key.json\""
echo "export PROJECT_ID=\"$PROJECT_ID\""
echo "export TF_VAR_project_id=\"$PROJECT_ID\""
echo "export TF_VAR_region=\"$REGION\""