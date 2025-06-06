#!/bin/bash
set -e

# Setup Workload Identity Federation for GitHub Actions
# This enables keyless authentication from GitHub to Google Cloud

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Configuration
PROJECT_ID="athena-finance-001"
GITHUB_REPO="joaomoreira/athena-001"  # Update with your GitHub repo
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"
SA_NAME="github-actions-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

print_color "$BLUE" "🔐 Setting up Workload Identity Federation for GitHub Actions"
print_color "$YELLOW" "Project: $PROJECT_ID"
print_color "$YELLOW" "Repository: $GITHUB_REPO"
echo ""

# Enable required APIs
print_color "$BLUE" "Enabling required APIs..."
gcloud services enable iamcredentials.googleapis.com --project=$PROJECT_ID
gcloud services enable iam.googleapis.com --project=$PROJECT_ID

# Create Workload Identity Pool
print_color "$BLUE" "Creating Workload Identity Pool..."
if gcloud iam workload-identity-pools describe $POOL_NAME \
    --location=global \
    --project=$PROJECT_ID &>/dev/null; then
    print_color "$GREEN" "✅ Workload Identity Pool already exists"
else
    gcloud iam workload-identity-pools create $POOL_NAME \
        --location=global \
        --display-name="GitHub Actions Pool" \
        --description="Pool for GitHub Actions authentication" \
        --project=$PROJECT_ID
    print_color "$GREEN" "✅ Workload Identity Pool created"
fi

# Create Workload Identity Provider
print_color "$BLUE" "Creating Workload Identity Provider..."
if gcloud iam workload-identity-pools providers describe $PROVIDER_NAME \
    --location=global \
    --workload-identity-pool=$POOL_NAME \
    --project=$PROJECT_ID &>/dev/null; then
    print_color "$GREEN" "✅ Workload Identity Provider already exists"
else
    gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
        --location=global \
        --workload-identity-pool=$POOL_NAME \
        --display-name="GitHub Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --project=$PROJECT_ID
    print_color "$GREEN" "✅ Workload Identity Provider created"
fi

# Create Service Account for GitHub Actions
print_color "$BLUE" "Creating Service Account for GitHub Actions..."
if gcloud iam service-accounts describe $SA_EMAIL \
    --project=$PROJECT_ID &>/dev/null; then
    print_color "$GREEN" "✅ Service Account already exists"
else
    gcloud iam service-accounts create $SA_NAME \
        --display-name="GitHub Actions Service Account" \
        --description="Service account for GitHub Actions CI/CD" \
        --project=$PROJECT_ID
    print_color "$GREEN" "✅ Service Account created"
fi

# Grant necessary permissions to the service account
print_color "$BLUE" "Granting permissions to Service Account..."

# Cloud Run permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/run.admin"

# Cloud Build permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/cloudbuild.builds.editor"

# Artifact Registry permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/artifactregistry.writer"

# Service Account User (to act as other service accounts)
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/iam.serviceAccountUser"

# Storage permissions (for Terraform state if using GCS backend)
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/storage.objectAdmin"

# Firestore permissions (for backups)
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/datastore.importExportAdmin"

print_color "$GREEN" "✅ Permissions granted"

# Allow impersonation from Workload Identity Pool
print_color "$BLUE" "Configuring Workload Identity binding..."
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --project=$PROJECT_ID \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/$POOL_NAME/attribute.repository/$GITHUB_REPO"

print_color "$GREEN" "✅ Workload Identity binding configured"

# Get Workload Identity Provider resource name
WIF_PROVIDER=$(gcloud iam workload-identity-pools providers describe $PROVIDER_NAME \
    --location=global \
    --workload-identity-pool=$POOL_NAME \
    --project=$PROJECT_ID \
    --format="value(name)")

# Output configuration for GitHub Actions
print_color "$BLUE" "\n📋 GitHub Actions Configuration"
print_color "$BLUE" "================================"
print_color "$YELLOW" "\nAdd these secrets to your GitHub repository:"
print_color "$GREEN" "  WIF_PROVIDER: $WIF_PROVIDER"
print_color "$GREEN" "  WIF_SERVICE_ACCOUNT: $SA_EMAIL"

print_color "$YELLOW" "\nFor production environment, create separate service account:"
print_color "$GREEN" "  WIF_PROVIDER_PROD: $WIF_PROVIDER"
print_color "$GREEN" "  WIF_SERVICE_ACCOUNT_PROD: github-actions-prod-sa@$PROJECT_ID.iam.gserviceaccount.com"

print_color "$BLUE" "\n📝 Example GitHub Actions workflow usage:"
cat << 'EOF'

      - id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}
      
      - uses: google-github-actions/setup-gcloud@v2
      
      - run: gcloud run services list --region=europe-west3
EOF

print_color "$GREEN" "\n✅ Workload Identity Federation setup complete!"