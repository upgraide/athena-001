#!/bin/bash

# Athena Finance - Microservices Deployment Script
# This script handles the deployment of all microservices to Google Cloud Run

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${PROJECT_ID:-athena-finance-001}"
REGION="${REGION:-europe-west3}"
ARTIFACT_REGISTRY="europe-west3-docker.pkg.dev"
REPOSITORY="finance-containers"
SERVICES=("auth-service" "finance-master" "document-ai" "transaction-analyzer" "insight-generator")

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if required tools are installed
check_prerequisites() {
    print_color "$BLUE" "🔍 Checking prerequisites..."
    
    local missing_tools=()
    
    # Check for gcloud
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    # Check for docker
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    # Check for npm
    if ! command -v npm &> /dev/null; then
        missing_tools+=("npm")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_color "$RED" "❌ Missing required tools: ${missing_tools[*]}"
        print_color "$YELLOW" "Please install the missing tools and try again."
        exit 1
    fi
    
    print_color "$GREEN" "✅ All prerequisites installed"
}

# Function to authenticate with Google Cloud
authenticate() {
    print_color "$BLUE" "🔐 Authenticating with Google Cloud..."
    
    # Check if already authenticated
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_color "$GREEN" "✅ Already authenticated"
    else
        gcloud auth login
        print_color "$GREEN" "✅ Authentication successful"
    fi
    
    # Set project
    gcloud config set project "$PROJECT_ID"
    print_color "$GREEN" "✅ Project set to: $PROJECT_ID"
}

# Function to configure Docker for Artifact Registry
configure_docker() {
    print_color "$BLUE" "🐳 Configuring Docker for Artifact Registry..."
    
    gcloud auth configure-docker "$ARTIFACT_REGISTRY" --quiet
    print_color "$GREEN" "✅ Docker configured for Artifact Registry"
}

# Function to create Artifact Registry repository if it doesn't exist
create_repository() {
    print_color "$BLUE" "📦 Checking Artifact Registry repository..."
    
    if gcloud artifacts repositories describe "$REPOSITORY" \
        --location="$REGION" &> /dev/null; then
        print_color "$GREEN" "✅ Repository '$REPOSITORY' already exists"
    else
        print_color "$YELLOW" "Creating repository '$REPOSITORY'..."
        gcloud artifacts repositories create "$REPOSITORY" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Athena Finance microservices container repository"
        print_color "$GREEN" "✅ Repository created successfully"
    fi
}

# Function to build TypeScript code
build_typescript() {
    print_color "$BLUE" "🔨 Building TypeScript code..."
    
    # Navigate to project root
    cd "$(dirname "$0")/.."
    
    # Install dependencies
    print_color "$YELLOW" "Installing dependencies..."
    npm ci
    
    # Build TypeScript
    print_color "$YELLOW" "Compiling TypeScript..."
    npm run build
    
    print_color "$GREEN" "✅ TypeScript build completed"
}

# Function to build and push a service container
build_and_push_service() {
    local service=$1
    local image_url="${ARTIFACT_REGISTRY}/${PROJECT_ID}/${REPOSITORY}/${service}"
    
    print_color "$BLUE" "🏗️  Building ${service}..."
    
    # Build with Docker
    docker build \
        --build-arg SERVICE_NAME="$service" \
        --tag "${image_url}:latest" \
        --tag "${image_url}:$(git rev-parse --short HEAD)" \
        --platform linux/amd64 \
        --file Dockerfile \
        .
    
    # Push to Artifact Registry
    print_color "$YELLOW" "📤 Pushing ${service} to Artifact Registry..."
    docker push "${image_url}:latest"
    docker push "${image_url}:$(git rev-parse --short HEAD)"
    
    print_color "$GREEN" "✅ ${service} built and pushed successfully"
}

# Function to deploy a service to Cloud Run
deploy_service() {
    local service=$1
    local image_url="${ARTIFACT_REGISTRY}/${PROJECT_ID}/${REPOSITORY}/${service}:latest"
    
    print_color "$BLUE" "🚀 Deploying ${service} to Cloud Run..."
    
    # Service-specific configurations
    local cpu="1"
    local memory="512Mi"
    local min_instances="0"
    local max_instances="10"
    local concurrency="100"
    
    case $service in
        "document-ai")
            cpu="2"
            memory="1Gi"
            max_instances="5"
            concurrency="50"
            ;;
        "insight-generator")
            cpu="2"
            memory="1Gi"
            max_instances="5"
            concurrency="40"
            ;;
        "transaction-analyzer")
            max_instances="8"
            concurrency="80"
            ;;
        "finance-master")
            min_instances="1"
            ;;
    esac
    
    # Deploy to Cloud Run
    gcloud run deploy "$service" \
        --image="$image_url" \
        --region="$REGION" \
        --platform=managed \
        --allow-unauthenticated \
        --port=8080 \
        --cpu="$cpu" \
        --memory="$memory" \
        --min-instances="$min_instances" \
        --max-instances="$max_instances" \
        --concurrency="$concurrency" \
        --service-account="${service}-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="NODE_ENV=production,PROJECT_ID=${PROJECT_ID},SERVICE_NAME=${service}" \
        --set-secrets="KMS_KEY=athena-kms-key:latest" \
        --cpu-boost \
        --execution-environment=gen2 \
        --quiet
    
    # Get service URL
    local service_url=$(gcloud run services describe "$service" \
        --region="$REGION" \
        --format='value(status.url)')
    
    print_color "$GREEN" "✅ ${service} deployed successfully"
    print_color "$YELLOW" "   URL: ${service_url}"
}

# Function to verify service health
verify_service_health() {
    local service=$1
    local service_url=$(gcloud run services describe "$service" \
        --region="$REGION" \
        --format='value(status.url)')
    
    print_color "$BLUE" "🏥 Checking health of ${service}..."
    
    if curl -f -s "${service_url}/health" > /dev/null; then
        print_color "$GREEN" "✅ ${service} is healthy"
        return 0
    else
        print_color "$RED" "❌ ${service} health check failed"
        return 1
    fi
}

# Function to create service accounts if they don't exist
create_service_accounts() {
    print_color "$BLUE" "👤 Creating service accounts..."
    
    for service in "${SERVICES[@]}"; do
        local sa_name="${service}-sa"
        local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
            print_color "$GREEN" "✅ Service account for ${service} already exists"
        else
            print_color "$YELLOW" "Creating service account for ${service}..."
            gcloud iam service-accounts create "$sa_name" \
                --display-name="Service account for ${service}" \
                --description="Service account for the ${service} microservice"
            
            # Grant necessary permissions
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${sa_email}" \
                --role="roles/datastore.user"
            
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${sa_email}" \
                --role="roles/secretmanager.secretAccessor"
            
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${sa_email}" \
                --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
            
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${sa_email}" \
                --role="roles/logging.logWriter"
            
            print_color "$GREEN" "✅ Service account for ${service} created"
        fi
    done
}

# Function to create KMS key if it doesn't exist
create_kms_key() {
    print_color "$BLUE" "🔐 Setting up KMS encryption key..."
    
    local keyring_name="athena-security-keyring"
    local key_name="data-encryption-key"
    
    # Create keyring if it doesn't exist
    if gcloud kms keyrings describe "$keyring_name" \
        --location="$REGION" &> /dev/null; then
        print_color "$GREEN" "✅ KMS keyring already exists"
    else
        print_color "$YELLOW" "Creating KMS keyring..."
        gcloud kms keyrings create "$keyring_name" \
            --location="$REGION"
        print_color "$GREEN" "✅ KMS keyring created"
    fi
    
    # Create key if it doesn't exist
    if gcloud kms keys describe "$key_name" \
        --keyring="$keyring_name" \
        --location="$REGION" &> /dev/null; then
        print_color "$GREEN" "✅ KMS key already exists"
    else
        print_color "$YELLOW" "Creating KMS key..."
        # Calculate next rotation time (30 days from now)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS date command
            NEXT_ROTATION=$(date -u -v+30d "+%Y-%m-%dT%H:%M:%SZ")
        else
            # Linux date command
            NEXT_ROTATION=$(date -u -d '+30 days' '+%Y-%m-%dT%H:%M:%SZ')
        fi
        
        gcloud kms keys create "$key_name" \
            --keyring="$keyring_name" \
            --location="$REGION" \
            --purpose="encryption" \
            --rotation-period="30d" \
            --next-rotation-time="$NEXT_ROTATION"
        print_color "$GREEN" "✅ KMS key created"
    fi
}

# Function to create a test secret
create_test_secret() {
    print_color "$BLUE" "🔒 Creating test secret..."
    
    local secret_name="athena-kms-key"
    
    if gcloud secrets describe "$secret_name" &> /dev/null; then
        print_color "$GREEN" "✅ Test secret already exists"
    else
        print_color "$YELLOW" "Creating test secret..."
        echo -n "test-kms-key-value" | gcloud secrets create "$secret_name" \
            --data-file=- \
            --replication-policy="user-managed" \
            --locations="$REGION"
        print_color "$GREEN" "✅ Test secret created"
    fi
}

# Main deployment function
main() {
    print_color "$BLUE" "🚀 Starting Athena Finance microservices deployment"
    print_color "$YELLOW" "Project: $PROJECT_ID"
    print_color "$YELLOW" "Region: $REGION"
    echo ""
    
    # Run prerequisite checks
    check_prerequisites
    
    # Authenticate
    authenticate
    
    # Set up infrastructure
    create_repository
    configure_docker
    create_service_accounts
    create_kms_key
    create_test_secret
    
    # Build TypeScript
    build_typescript
    
    # Build and deploy services
    local failed_services=()
    
    for service in "${SERVICES[@]}"; do
        print_color "$BLUE" "\n📦 Processing ${service}..."
        
        if build_and_push_service "$service" && deploy_service "$service"; then
            if ! verify_service_health "$service"; then
                failed_services+=("$service")
            fi
        else
            failed_services+=("$service")
        fi
    done
    
    # Summary
    echo ""
    print_color "$BLUE" "📊 Deployment Summary"
    print_color "$BLUE" "===================="
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        print_color "$GREEN" "✅ All services deployed successfully!"
        
        # Display service URLs
        echo ""
        print_color "$BLUE" "🌐 Service URLs:"
        for service in "${SERVICES[@]}"; do
            local service_url=$(gcloud run services describe "$service" \
                --region="$REGION" \
                --format='value(status.url)')
            print_color "$GREEN" "   ${service}: ${service_url}"
        done
    else
        print_color "$RED" "❌ Failed services: ${failed_services[*]}"
        print_color "$YELLOW" "Please check the logs for more information."
        exit 1
    fi
    
    echo ""
    print_color "$GREEN" "🎉 Deployment complete!"
}

# Run main function
main "$@"