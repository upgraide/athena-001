#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT=${1:-staging}
PROJECT_ID="athena-finance-001"
REGION="europe-west3"
ARTIFACT_REGISTRY="$REGION-docker.pkg.dev/$PROJECT_ID/athena-finance"

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_color "$BLUE" "🚀 Deploying Athena Finance services to $ENVIRONMENT"

# Services configuration
declare -A SERVICE_CONFIG
SERVICE_CONFIG=(
    ["auth-service"]="PORT=8080,MEMORY=512Mi,CPU=1"
    ["finance-master"]="PORT=8080,MEMORY=768Mi,CPU=1"
    ["document-ai"]="PORT=8080,MEMORY=1Gi,CPU=2"
    ["transaction-analyzer"]="PORT=8080,MEMORY=512Mi,CPU=1"
    ["insight-generator"]="PORT=8080,MEMORY=512Mi,CPU=1"
)

# Environment-specific settings
if [ "$ENVIRONMENT" == "production" ]; then
    MIN_INSTANCES=2
    MAX_INSTANCES=10
    MEMORY_MULTIPLIER=2
    SERVICE_SUFFIX=""
else
    MIN_INSTANCES=0
    MAX_INSTANCES=5
    MEMORY_MULTIPLIER=1
    SERVICE_SUFFIX="-$ENVIRONMENT"
fi

# Get latest commit SHA or use provided version
VERSION=${2:-$(git rev-parse HEAD)}

# Deploy each service
for service in "${!SERVICE_CONFIG[@]}"; do
    print_color "$BLUE" "Deploying $service..."
    
    # Parse service config
    IFS=',' read -ra CONFIG <<< "${SERVICE_CONFIG[$service]}"
    PORT=""
    MEMORY=""
    CPU=""
    
    for config in "${CONFIG[@]}"; do
        key="${config%%=*}"
        value="${config#*=}"
        case $key in
            PORT) PORT=$value ;;
            MEMORY) MEMORY=$value ;;
            CPU) CPU=$value ;;
        esac
    done
    
    # Adjust memory for production
    if [ "$ENVIRONMENT" == "production" ] && [ "$MEMORY" != "1Gi" ]; then
        MEMORY="1Gi"
    fi
    
    # Build Cloud Run deploy command
    deploy_cmd="gcloud run deploy ${service}${SERVICE_SUFFIX} \
        --image=$ARTIFACT_REGISTRY/$service:$VERSION \
        --region=$REGION \
        --platform=managed \
        --port=$PORT \
        --memory=$MEMORY \
        --cpu=$CPU \
        --timeout=300 \
        --concurrency=100 \
        --min-instances=$MIN_INSTANCES \
        --max-instances=$MAX_INSTANCES \
        --service-account=microservice-sa@$PROJECT_ID.iam.gserviceaccount.com \
        --vpc-connector=athena-vpc-connector \
        --set-env-vars=NODE_ENV=$ENVIRONMENT,SERVICE_VERSION=$VERSION"
    
    # Add secrets for auth service
    if [ "$service" == "auth-service" ]; then
        deploy_cmd="$deploy_cmd \
            --set-secrets=JWT_ACCESS_SECRET=jwt-access-secret:latest,JWT_REFRESH_SECRET=jwt-refresh-secret:latest"
    fi
    
    # Add environment labels
    deploy_cmd="$deploy_cmd --labels=environment=$ENVIRONMENT,version=$VERSION,service=$service"
    
    # Execute deployment
    if eval $deploy_cmd; then
        print_color "$GREEN" "✅ $service deployed successfully"
        
        # Get service URL
        SERVICE_URL=$(gcloud run services describe ${service}${SERVICE_SUFFIX} \
            --region=$REGION \
            --format="value(status.url)")
        
        # Health check
        print_color "$BLUE" "Checking $service health..."
        sleep 10 # Give service time to start
        
        if curl -s -f "$SERVICE_URL/health" > /dev/null; then
            print_color "$GREEN" "✅ $service is healthy at $SERVICE_URL"
        else
            print_color "$RED" "❌ $service health check failed"
            exit 1
        fi
    else
        print_color "$RED" "❌ Failed to deploy $service"
        exit 1
    fi
done

# Update traffic if doing canary deployment
if [ "$3" == "canary" ]; then
    CANARY_PERCENTAGE=${4:-10}
    print_color "$BLUE" "Setting up canary deployment with $CANARY_PERCENTAGE% traffic"
    
    for service in "${!SERVICE_CONFIG[@]}"; do
        gcloud run services update-traffic ${service}${SERVICE_SUFFIX} \
            --region=$REGION \
            --to-tags=$VERSION=$CANARY_PERCENTAGE
    done
fi

print_color "$GREEN" "🎉 All services deployed successfully to $ENVIRONMENT!"

# Run post-deployment validation
print_color "$BLUE" "Running post-deployment validation..."
$(dirname "$0")/../testing/validate-deployment.sh $ENVIRONMENT

# Send deployment metrics
if [ "$ENVIRONMENT" == "production" ]; then
    # Track deployment event
    curl -X POST "https://finance-master.run.app/metrics" \
        -H "Content-Type: application/json" \
        -d '{
            "event": "deployment_completed",
            "environment": "'$ENVIRONMENT'",
            "version": "'$VERSION'",
            "services": ["auth-service", "finance-master", "document-ai", "transaction-analyzer", "insight-generator"],
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
        }'
fi

print_color "$GREEN" "✅ Deployment validation passed!"