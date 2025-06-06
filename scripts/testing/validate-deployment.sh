#!/bin/bash
# Don't use set -e to allow graceful error handling

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_color "$BLUE" "🔍 Validating Athena Finance Deployment"
echo ""

# Check all services
print_color "$BLUE" "1️⃣ Checking Service Health..."
SERVICES=("auth-service" "finance-master" "document-ai" "transaction-analyzer" "insight-generator")
ALL_HEALTHY=true

for service in "${SERVICES[@]}"; do
    URL=$(gcloud run services describe $service --region=europe-west3 --format="value(status.url)" 2>/dev/null)
    if [ -n "$URL" ]; then
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" $URL/health)
        if [ "$STATUS" = "200" ]; then
            print_color "$GREEN" "✅ $service is healthy"
        else
            print_color "$RED" "❌ $service returned status $STATUS"
            ALL_HEALTHY=false
        fi
    else
        print_color "$RED" "❌ $service not found"
        ALL_HEALTHY=false
    fi
done

# Check authentication
print_color "$BLUE" "\n2️⃣ Testing Authentication..."
AUTH_URL=$(gcloud run services describe auth-service --region=europe-west3 --format="value(status.url)")
TEST_EMAIL="test$(date +%s)@example.com"

# Test registration
REGISTER_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"Test123!@#\",
        \"firstName\": \"Test\",
        \"lastName\": \"User\"
    }")

if echo "$REGISTER_RESPONSE" | grep -q "Registration successful"; then
    print_color "$GREEN" "✅ Authentication working"
else
    print_color "$RED" "❌ Authentication failed"
    ALL_HEALTHY=false
fi

# Check monitoring
print_color "$BLUE" "\n3️⃣ Checking Monitoring..."

# Check metrics endpoints
AUTH_METRICS=$(curl -s "$AUTH_URL/metrics" | grep -c "http_requests_total" || echo 0)
if [ "$AUTH_METRICS" -gt 0 ]; then
    print_color "$GREEN" "✅ Metrics endpoints working"
else
    print_color "$RED" "❌ Metrics endpoints not working"
    ALL_HEALTHY=false
fi

# Check budget (skip if no billing permissions)
if gcloud billing budgets list --billing-account=01374E-678A2C-27DDFE --limit=1 >/dev/null 2>&1; then
    BUDGET_COUNT=$(gcloud billing budgets list --billing-account=01374E-678A2C-27DDFE --filter="displayName:'Athena Finance Monthly Budget'" --format="value(name)" | wc -l)
    if [ "$BUDGET_COUNT" -gt 0 ]; then
        print_color "$GREEN" "✅ Budget alerts configured"
    else
        print_color "$YELLOW" "⚠️  Budget alerts not found (but billing access granted)"
    fi
else
    print_color "$YELLOW" "⚠️  Skipping budget check (no billing permissions)"
fi

# Skip Terraform state check in CI/CD (requires local state/credentials)
if [ -n "$CI" ]; then
    print_color "$BLUE" "\n4️⃣ Skipping Infrastructure State Check (CI environment)..."
else
    print_color "$BLUE" "\n4️⃣ Checking Infrastructure State..."
    cd "$(dirname "$0")/../../infrastructure/terraform"
    
    # Check if terraform is initialized
    if [ -d ".terraform" ]; then
        # Run terraform plan and capture exit code
        terraform plan -detailed-exitcode >/dev/null 2>&1
        TERRAFORM_EXIT_CODE=$?
        
        if [ "$TERRAFORM_EXIT_CODE" = "0" ]; then
            print_color "$GREEN" "✅ Terraform state is clean (no changes needed)"
        elif [ "$TERRAFORM_EXIT_CODE" = "2" ]; then
            print_color "$YELLOW" "⚠️  Terraform has pending changes"
            ALL_HEALTHY=false
        else
            print_color "$RED" "❌ Terraform plan failed (exit code: $TERRAFORM_EXIT_CODE)"
            ALL_HEALTHY=false
        fi
    else
        print_color "$YELLOW" "⚠️  Terraform not initialized, skipping state check"
    fi
fi

# Check logs for errors
print_color "$BLUE" "\n5️⃣ Checking Recent Logs for Errors..."
# Use a more portable date format
TEN_MINUTES_AGO=$(date -u -d "10 minutes ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2024-01-01T00:00:00Z")
ERROR_COUNT=$(gcloud logging read "severity>=ERROR AND timestamp>=\"$TEN_MINUTES_AGO\"" \
    --limit=10 \
    --format="value(timestamp)" \
    --project=athena-finance-001 2>/dev/null | wc -l)

if [ "$ERROR_COUNT" -eq 0 ]; then
    print_color "$GREEN" "✅ No errors in last 10 minutes"
else
    print_color "$YELLOW" "⚠️  Found $ERROR_COUNT errors in last 10 minutes"
fi

# Summary
echo ""
if [ "$ALL_HEALTHY" = true ]; then
    print_color "$GREEN" "🎉 All validation checks passed!"
    print_color "$BLUE" "\n📊 Key Resources:"
    print_color "$GREEN" "• Dashboard: https://console.cloud.google.com/monitoring/dashboards"
    print_color "$GREEN" "• Alerts: https://console.cloud.google.com/monitoring/alerting"
    print_color "$GREEN" "• Budget: 100 EUR/month with alerts at 50%, 80%, 100%, 120%"
    print_color "$GREEN" "• Alert Email: joao@upgraide.ai"
    exit 0
else
    print_color "$RED" "❌ Some validation checks failed"
    print_color "$YELLOW" "Please review the errors above and fix them before committing"
    exit 1
fi