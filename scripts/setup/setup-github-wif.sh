#!/bin/bash
set -e

# Setup Workload Identity Federation for GitHub Actions using Terraform
# This ensures consistent infrastructure management

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
GITHUB_REPO="${1:-upgraide/athena-001}"
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/infrastructure/terraform"

print_color "$BLUE" "🔐 Setting up Workload Identity Federation for GitHub Actions"
print_color "$YELLOW" "Project: $PROJECT_ID"
print_color "$YELLOW" "Repository: $GITHUB_REPO"
print_color "$YELLOW" "Using Terraform for consistent infrastructure management"
echo ""

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    print_color "$RED" "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Navigate to Terraform directory
cd "$TERRAFORM_DIR"

# Initialize Terraform
print_color "$BLUE" "Initializing Terraform..."
terraform init -upgrade

# Set the GitHub repository variable
print_color "$BLUE" "Configuring GitHub repository..."
cat > github.auto.tfvars <<EOF
github_repository = "$GITHUB_REPO"
EOF

# Plan the changes
print_color "$BLUE" "Planning Terraform changes..."
terraform plan -target=google_iam_workload_identity_pool.github \
               -target=google_iam_workload_identity_pool_provider.github \
               -target=google_service_account.github_actions \
               -target=google_service_account.github_actions_prod \
               -target=google_project_iam_member.github_actions_permissions \
               -target=google_project_iam_member.github_actions_prod_permissions \
               -target=google_service_account_iam_member.github_actions_workload_identity \
               -target=google_service_account_iam_member.github_actions_prod_workload_identity \
               -target=local_file.github_secrets

# Apply the changes
print_color "$YELLOW" "Do you want to apply these changes? (yes/no)"
read -r response
if [[ "$response" =~ ^[Yy][Ee][Ss]|[Yy]$ ]]; then
    terraform apply -auto-approve \
                    -target=google_iam_workload_identity_pool.github \
                    -target=google_iam_workload_identity_pool_provider.github \
                    -target=google_service_account.github_actions \
                    -target=google_service_account.github_actions_prod \
                    -target=google_project_iam_member.github_actions_permissions \
                    -target=google_project_iam_member.github_actions_prod_permissions \
                    -target=google_service_account_iam_member.github_actions_workload_identity \
                    -target=google_service_account_iam_member.github_actions_prod_workload_identity \
                    -target=local_file.github_secrets
else
    print_color "$RED" "❌ Terraform apply cancelled"
    exit 1
fi

# Get outputs
WIF_PROVIDER=$(terraform output -raw github_wif_provider)
SERVICE_ACCOUNT=$(terraform output -raw github_service_account)
SERVICE_ACCOUNT_PROD=$(terraform output -raw github_service_account_prod)

# Display configuration
print_color "$BLUE" "\n📋 GitHub Actions Configuration"
print_color "$BLUE" "================================"
print_color "$YELLOW" "\nAdd these secrets to your GitHub repository:"
print_color "$GREEN" "  WIF_PROVIDER: $WIF_PROVIDER"
print_color "$GREEN" "  WIF_SERVICE_ACCOUNT: $SERVICE_ACCOUNT"
print_color "$GREEN" "  WIF_SERVICE_ACCOUNT_PROD: $SERVICE_ACCOUNT_PROD"
print_color "$GREEN" "  GCP_PROJECT_ID: $PROJECT_ID"

print_color "$YELLOW" "\nThe secrets have also been saved to:"
print_color "$GREEN" "  $TERRAFORM_DIR/.github-secrets"

print_color "$BLUE" "\n📝 To add secrets using GitHub CLI:"
cat << EOF

cd $TERRAFORM_DIR
gh secret set WIF_PROVIDER --repo=$GITHUB_REPO < <(terraform output -raw github_wif_provider)
gh secret set WIF_SERVICE_ACCOUNT --repo=$GITHUB_REPO < <(terraform output -raw github_service_account)
gh secret set WIF_SERVICE_ACCOUNT_PROD --repo=$GITHUB_REPO < <(terraform output -raw github_service_account_prod)
gh secret set GCP_PROJECT_ID --repo=$GITHUB_REPO --body="$PROJECT_ID"
EOF

print_color "$GREEN" "\n✅ Workload Identity Federation setup complete!"
print_color "$YELLOW" "\n📌 Next steps:"
print_color "$YELLOW" "1. Add the secrets to your GitHub repository"
print_color "$YELLOW" "2. Push your code to trigger the CI/CD pipeline"
print_color "$YELLOW" "3. Monitor the Actions tab in your repository"