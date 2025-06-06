#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT=${1:-staging}
PROJECT_ID="athena-finance-001"
REGION="europe-west3"

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_color "$YELLOW" "⚠️  Initiating rollback for $ENVIRONMENT environment"

# Services to rollback
SERVICES=("auth-service" "finance-master" "document-ai" "transaction-analyzer" "insight-generator")

# Function to get previous stable revision
get_previous_revision() {
    local service=$1
    # Get the second-to-last revision (previous stable version)
    gcloud run revisions list \
        --service=$service \
        --region=$REGION \
        --format="value(name)" \
        --limit=2 | tail -n 1
}

# Rollback each service
for service in "${SERVICES[@]}"; do
    print_color "$BLUE" "Rolling back $service..."
    
    # Get previous revision
    PREVIOUS_REVISION=$(get_previous_revision $service)
    
    if [ -z "$PREVIOUS_REVISION" ]; then
        print_color "$RED" "❌ No previous revision found for $service"
        continue
    fi
    
    print_color "$BLUE" "Found previous revision: $PREVIOUS_REVISION"
    
    # Rollback traffic to previous revision
    if gcloud run services update-traffic $service \
        --region=$REGION \
        --to-revisions=$PREVIOUS_REVISION=100; then
        
        print_color "$GREEN" "✅ Rolled back $service to $PREVIOUS_REVISION"
        
        # Verify service health after rollback
        SERVICE_URL=$(gcloud run services describe $service \
            --region=$REGION \
            --format="value(status.url)")
        
        sleep 5 # Give service time to stabilize
        
        # Check appropriate health endpoint
        if [ "$service" == "auth-service" ]; then
            HEALTH_URL="$SERVICE_URL/api/v1/auth/health"
        else
            HEALTH_URL="$SERVICE_URL/health"
        fi
        
        if curl -s -f "$HEALTH_URL" > /dev/null; then
            print_color "$GREEN" "✅ $service is healthy after rollback"
        else
            print_color "$RED" "❌ $service health check failed after rollback"
        fi
    else
        print_color "$RED" "❌ Failed to rollback $service"
    fi
done

# Restore Firestore if needed (production only)
if [ "$ENVIRONMENT" == "production" ] && [ "$2" == "--restore-data" ]; then
    print_color "$YELLOW" "Restoring Firestore data..."
    
    # Get latest backup
    LATEST_BACKUP=$(gsutil ls -l gs://$PROJECT_ID-backups/ | grep backup- | tail -n 1 | awk '{print $3}')
    
    if [ -n "$LATEST_BACKUP" ]; then
        print_color "$BLUE" "Found backup: $LATEST_BACKUP"
        
        # Initiate restore
        gcloud firestore import $LATEST_BACKUP
        
        print_color "$GREEN" "✅ Firestore restore initiated"
    else
        print_color "$RED" "❌ No Firestore backup found"
    fi
fi

# Update monitoring with rollback event
print_color "$BLUE" "Recording rollback event..."

# Track rollback in monitoring
curl -X POST "https://finance-master-$(gcloud run services describe finance-master --region=$REGION --format='value(status.url)' | cut -d'-' -f3-).run.app/metrics" \
    -H "Content-Type: application/json" \
    -d '{
        "event": "deployment_rollback",
        "environment": "'$ENVIRONMENT'",
        "reason": "'${ROLLBACK_REASON:-health_check_failure}'",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }' || true

# Send alert email via monitoring
gcloud logging write rollback-event \
    "Rollback executed for $ENVIRONMENT environment" \
    --severity=WARNING \
    --resource=global \
    --log-name=deployment-events

# Final validation
print_color "$BLUE" "Running post-rollback validation..."
if $(dirname "$0")/../testing/validate-deployment.sh $ENVIRONMENT; then
    print_color "$GREEN" "✅ Rollback completed successfully!"
    print_color "$BLUE" "All services are healthy and running previous stable versions"
else
    print_color "$RED" "❌ Post-rollback validation failed!"
    print_color "$YELLOW" "Manual intervention may be required"
    exit 1
fi