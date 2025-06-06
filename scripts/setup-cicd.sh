#!/bin/bash
set -e

# Complete CI/CD Setup Script for Athena Finance
# This script sets up everything needed for GitHub Actions CI/CD

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Configuration
PROJECT_ID="athena-finance-001"
GITHUB_REPO="${1:-upgraide/athena-001}"
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/infrastructure/terraform"

echo -e "${BLUE}🚀 Athena Finance CI/CD Setup${NC}"
echo -e "${BLUE}=============================${NC}"
echo ""

# Step 1: Check prerequisites
print_step "Checking prerequisites..."

# Check if required tools are installed
MISSING_TOOLS=()
for tool in gcloud terraform gh git; do
    if ! command -v $tool &> /dev/null; then
        MISSING_TOOLS+=($tool)
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    print_error "Missing required tools: ${MISSING_TOOLS[*]}"
    print_warning "Please install missing tools and run again."
    exit 1
fi
print_success "All required tools installed"

# Check GitHub CLI authentication
if ! gh auth status &>/dev/null; then
    print_error "GitHub CLI is not authenticated"
    print_warning "Please run: gh auth login"
    exit 1
fi
print_success "GitHub CLI authenticated"

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    print_error "gcloud is not authenticated"
    print_warning "Please run: gcloud auth login"
    exit 1
fi
print_success "gcloud authenticated"

# Step 2: Set up Terraform infrastructure
print_step "Setting up infrastructure with Terraform..."
cd "$TERRAFORM_DIR"

# Initialize Terraform
print_step "Initializing Terraform..."
terraform init -upgrade >/dev/null 2>&1
print_success "Terraform initialized"

# Create GitHub repository tfvars
cat > github.auto.tfvars <<EOF
github_repository = "$GITHUB_REPO"
EOF
print_success "Created github.auto.tfvars"

# Import existing resources if they exist
print_step "Checking for existing resources..."

# Check and import WIF pool
if gcloud iam workload-identity-pools describe github-pool \
    --location=global \
    --project=$PROJECT_ID &>/dev/null; then
    print_warning "Workload Identity Pool exists, importing..."
    terraform import -input=false google_iam_workload_identity_pool.github \
        projects/$PROJECT_ID/locations/global/workloadIdentityPools/github-pool &>/dev/null || true
fi

# Check and import WIF provider
if gcloud iam workload-identity-pools providers describe github-provider \
    --location=global \
    --workload-identity-pool=github-pool \
    --project=$PROJECT_ID &>/dev/null; then
    print_warning "Workload Identity Provider exists, importing..."
    terraform import -input=false google_iam_workload_identity_pool_provider.github \
        projects/$PROJECT_ID/locations/global/workloadIdentityPools/github-pool/providers/github-provider &>/dev/null || true
fi

# Check and import service accounts
for sa in github-actions-sa github-actions-prod-sa; do
    if gcloud iam service-accounts describe $sa@$PROJECT_ID.iam.gserviceaccount.com \
        --project=$PROJECT_ID &>/dev/null; then
        print_warning "Service account $sa exists, importing..."
        if [ "$sa" = "github-actions-sa" ]; then
            terraform import -input=false google_service_account.github_actions \
                projects/$PROJECT_ID/serviceAccounts/$sa@$PROJECT_ID.iam.gserviceaccount.com &>/dev/null || true
        else
            terraform import -input=false google_service_account.github_actions_prod \
                projects/$PROJECT_ID/serviceAccounts/$sa@$PROJECT_ID.iam.gserviceaccount.com &>/dev/null || true
        fi
    fi
done

# Apply Terraform configuration
print_step "Applying Terraform configuration..."
terraform apply -auto-approve \
    -target=google_iam_workload_identity_pool.github \
    -target=google_iam_workload_identity_pool_provider.github \
    -target=google_service_account.github_actions \
    -target=google_service_account.github_actions_prod \
    -target=google_project_iam_member.github_actions_permissions \
    -target=google_project_iam_member.github_actions_prod_permissions \
    -target=google_service_account_iam_member.github_actions_workload_identity \
    -target=google_service_account_iam_member.github_actions_prod_workload_identity \
    -target=local_file.github_secrets >/dev/null 2>&1

print_success "Infrastructure created/updated"

# Get outputs
WIF_PROVIDER=$(terraform output -raw github_wif_provider 2>/dev/null)
SERVICE_ACCOUNT=$(terraform output -raw github_service_account 2>/dev/null)
SERVICE_ACCOUNT_PROD=$(terraform output -raw github_service_account_prod 2>/dev/null)

# Step 3: Set up GitHub secrets
print_step "Setting up GitHub secrets..."

# Check if repository exists
if ! gh repo view $GITHUB_REPO &>/dev/null; then
    print_error "GitHub repository $GITHUB_REPO not found"
    print_warning "Please create the repository first or check the name"
    exit 1
fi

# Set secrets
SECRETS_SET=0
for secret_name in WIF_PROVIDER WIF_SERVICE_ACCOUNT WIF_SERVICE_ACCOUNT_PROD GCP_PROJECT_ID; do
    case $secret_name in
        WIF_PROVIDER)
            secret_value="$WIF_PROVIDER"
            ;;
        WIF_SERVICE_ACCOUNT)
            secret_value="$SERVICE_ACCOUNT"
            ;;
        WIF_SERVICE_ACCOUNT_PROD)
            secret_value="$SERVICE_ACCOUNT_PROD"
            ;;
        GCP_PROJECT_ID)
            secret_value="$PROJECT_ID"
            ;;
    esac
    
    if gh secret set $secret_name --repo=$GITHUB_REPO --body="$secret_value" 2>/dev/null; then
        print_success "Set $secret_name"
        ((SECRETS_SET++))
    else
        print_error "Failed to set $secret_name"
    fi
done

if [ $SECRETS_SET -eq 4 ]; then
    print_success "All GitHub secrets configured"
else
    print_warning "Some secrets failed to set. Please check and retry."
fi

# Step 4: Verify setup
print_step "Verifying setup..."

# Check GitHub secrets
CONFIGURED_SECRETS=$(gh secret list --repo=$GITHUB_REPO 2>/dev/null | wc -l)
if [ $CONFIGURED_SECRETS -ge 4 ]; then
    print_success "GitHub secrets verified"
else
    print_warning "Expected 4+ secrets, found $CONFIGURED_SECRETS"
fi

# Check workflows
if [ -f "../../.github/workflows/ci.yml" ] && [ -f "../../.github/workflows/cd.yml" ]; then
    print_success "GitHub Actions workflows found"
else
    print_warning "GitHub Actions workflows not found in .github/workflows/"
fi

# Step 5: Display summary
echo ""
echo -e "${BLUE}📋 Setup Summary${NC}"
echo -e "${BLUE}================${NC}"
echo ""
echo -e "${GREEN}✅ Infrastructure:${NC}"
echo "   • Workload Identity Pool: github-pool"
echo "   • WIF Provider: $WIF_PROVIDER"
echo "   • Service Account: $SERVICE_ACCOUNT"
echo "   • Prod Service Account: $SERVICE_ACCOUNT_PROD"
echo ""
echo -e "${GREEN}✅ GitHub Secrets:${NC}"
echo "   • WIF_PROVIDER"
echo "   • WIF_SERVICE_ACCOUNT"
echo "   • WIF_SERVICE_ACCOUNT_PROD"
echo "   • GCP_PROJECT_ID"
echo ""
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Commit and push your changes:"
echo "   git add ."
echo "   git commit -m 'feat: add CI/CD infrastructure'"
echo "   git push origin main"
echo ""
echo "2. Check GitHub Actions:"
echo "   https://github.com/$GITHUB_REPO/actions"
echo ""
echo "3. The CI pipeline will run automatically on push"
echo "4. The CD pipeline will deploy to staging after CI passes"
echo ""
print_success "CI/CD setup complete! 🎉"