#!/bin/bash
set -e

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

# Get service URLs
AUTH_URL=$(gcloud run services describe auth-service --region=europe-west3 --format="value(status.url)")
FINANCE_URL=$(gcloud run services describe finance-master --region=europe-west3 --format="value(status.url)")

print_color "$BLUE" "🧪 Testing Monitoring and Alerting"
print_color "$BLUE" "Auth URL: $AUTH_URL"
print_color "$BLUE" "Finance URL: $FINANCE_URL"

# Test 1: Metrics endpoints
print_color "$BLUE" "\n1️⃣ Testing metrics endpoints..."

# Test auth service metrics
METRICS=$(curl -s "$AUTH_URL/metrics")
if echo "$METRICS" | grep -q "http_requests_total"; then
    print_color "$GREEN" "✅ Auth service metrics working"
    print_color "$YELLOW" "   Sample metrics:"
    echo "$METRICS" | grep -E "(http_requests_total|http_request_duration|auth_failures_total)" | head -5
else
    print_color "$RED" "❌ Auth service metrics not working"
fi

# Test finance service metrics
METRICS=$(curl -s "$FINANCE_URL/metrics")
if echo "$METRICS" | grep -q "http_requests_total"; then
    print_color "$GREEN" "✅ Finance service metrics working"
else
    print_color "$RED" "❌ Finance service metrics not working"
fi

# Test 2: Generate some traffic for metrics
print_color "$BLUE" "\n2️⃣ Generating traffic for metrics..."

# Make some successful requests
for i in {1..5}; do
    curl -s "$AUTH_URL/health" > /dev/null
    curl -s "$FINANCE_URL/health" > /dev/null
done
print_color "$GREEN" "✅ Generated 5 health check requests"

# Make some failed auth attempts to trigger alerts
print_color "$BLUE" "\n3️⃣ Testing authentication failure tracking..."
for i in {1..3}; do
    curl -s -X POST "$AUTH_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"test@example.com","password":"wrongpassword"}' > /dev/null
done
print_color "$GREEN" "✅ Generated 3 failed login attempts"

# Test 3: Check monitoring dashboard
print_color "$BLUE" "\n4️⃣ Checking monitoring setup..."

# Check if uptime checks exist
UPTIME_CHECKS=$(gcloud monitoring uptime list --format="value(name)" --project=athena-finance-001 2>/dev/null || echo "")
if [ -n "$UPTIME_CHECKS" ]; then
    print_color "$GREEN" "✅ Uptime checks configured"
else
    print_color "$YELLOW" "⚠️  No uptime checks found"
fi

# Check if alert policies exist
ALERT_POLICIES=$(gcloud alpha monitoring policies list --format="value(displayName)" --project=athena-finance-001 2>/dev/null || echo "")
if [ -n "$ALERT_POLICIES" ]; then
    print_color "$GREEN" "✅ Alert policies configured:"
    echo "$ALERT_POLICIES" | while read -r policy; do
        print_color "$YELLOW" "   - $policy"
    done
else
    print_color "$YELLOW" "⚠️  No alert policies found"
fi

# Test 4: Check logs
print_color "$BLUE" "\n5️⃣ Checking recent logs..."

# Check for authentication failures in logs
AUTH_FAILURES=$(gcloud logging read 'resource.type="cloud_run_revision" AND severity=ERROR AND jsonPayload.event="LOGIN_FAILED"' \
    --limit=5 \
    --format="value(timestamp,jsonPayload.email)" \
    --project=athena-finance-001 2>/dev/null || echo "")

if [ -n "$AUTH_FAILURES" ]; then
    print_color "$GREEN" "✅ Authentication failure logs found"
else
    print_color "$YELLOW" "⚠️  No authentication failure logs found"
fi

# Test 5: Generate high latency request
print_color "$BLUE" "\n6️⃣ Testing high latency detection..."

# Create a test endpoint that sleeps (if available)
TEST_TOKEN=$(curl -s -X POST "$AUTH_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"finance.test@example.com","password":"Test123!@#"}' | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)

if [ -n "$TEST_TOKEN" ]; then
    # Make a request that might take time
    curl -s -H "Authorization: Bearer $TEST_TOKEN" "$FINANCE_URL/api/v1/insights" > /dev/null
    print_color "$GREEN" "✅ Generated request for latency monitoring"
else
    print_color "$YELLOW" "⚠️  Could not get test token for latency test"
fi

# Summary
print_color "$GREEN" "\n🎉 Monitoring test completed!"
print_color "$BLUE" "📊 Check your monitoring dashboard at:"
print_color "$YELLOW" "   https://console.cloud.google.com/monitoring/dashboards?project=athena-finance-001"
print_color "$BLUE" "🚨 Check alerts at:"
print_color "$YELLOW" "   https://console.cloud.google.com/monitoring/alerting?project=athena-finance-001"
print_color "$BLUE" "📈 View metrics explorer at:"
print_color "$YELLOW" "   https://console.cloud.google.com/monitoring/metrics-explorer?project=athena-finance-001"

# Test custom metrics
print_color "$BLUE" "\n7️⃣ Checking custom metrics..."

# Wait a bit for metrics to propagate
sleep 5

# Check if our custom metrics are being collected
CUSTOM_METRICS=$(curl -s "$AUTH_URL/metrics" | grep -E "auth_failures_total|business_events_total" || echo "")
if [ -n "$CUSTOM_METRICS" ]; then
    print_color "$GREEN" "✅ Custom metrics are being collected:"
    echo "$CUSTOM_METRICS" | head -5
else
    print_color "$YELLOW" "⚠️  Custom metrics not found"
fi