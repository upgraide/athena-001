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

# Configuration
PROJECT_ID="${PROJECT_ID:-athena-finance-001}"
REGION="${REGION:-europe-west3}"
ALERT_EMAIL="${ALERT_EMAIL:-alerts@athena-finance.com}"

print_color "$BLUE" "🔍 Deploying Monitoring and Alerting Infrastructure"
print_color "$YELLOW" "Project: $PROJECT_ID"
print_color "$YELLOW" "Region: $REGION"
print_color "$YELLOW" "Alert Email: $ALERT_EMAIL"
echo ""

# Enable required APIs
print_color "$BLUE" "🔌 Enabling required APIs..."
gcloud services enable monitoring.googleapis.com \
    cloudresourcemanager.googleapis.com \
    logging.googleapis.com \
    billingbudgets.googleapis.com \
    --project="$PROJECT_ID"

# Apply Terraform monitoring configuration
print_color "$BLUE" "🏗️  Applying monitoring infrastructure..."
cd "$(dirname "$0")/../../infrastructure/terraform"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    print_color "$YELLOW" "Initializing Terraform..."
    terraform init
fi

# Plan monitoring changes
print_color "$BLUE" "📋 Planning monitoring infrastructure..."
terraform plan -target=module.monitoring -var="alert_email=$ALERT_EMAIL" -out=monitoring.tfplan

# Apply monitoring infrastructure
print_color "$BLUE" "🚀 Applying monitoring infrastructure..."
terraform apply monitoring.tfplan

# Get service URLs for uptime checks
print_color "$BLUE" "🔍 Configuring uptime checks..."
AUTH_URL=$(gcloud run services describe auth-service --region="$REGION" --format="value(status.url)" 2>/dev/null || echo "")
FINANCE_URL=$(gcloud run services describe finance-master --region="$REGION" --format="value(status.url)" 2>/dev/null || echo "")

if [ -z "$AUTH_URL" ] || [ -z "$FINANCE_URL" ]; then
    print_color "$YELLOW" "⚠️  Services not deployed yet. Uptime checks will be configured after service deployment."
else
    print_color "$GREEN" "✅ Service URLs found:"
    print_color "$GREEN" "   Auth Service: $AUTH_URL"
    print_color "$GREEN" "   Finance Master: $FINANCE_URL"
fi

# Create custom log-based metrics
print_color "$BLUE" "📊 Creating custom log-based metrics..."

# Authentication failure metric
gcloud logging metrics create auth_failures \
    --description="Count of authentication failures" \
    --log-filter='resource.type="cloud_run_revision" 
    AND severity=ERROR 
    AND jsonPayload.event="LOGIN_FAILED"' \
    --project="$PROJECT_ID" || print_color "$YELLOW" "Metric auth_failures already exists"

# High latency requests metric
gcloud logging metrics create high_latency_requests \
    --description="Requests with latency > 2 seconds" \
    --log-filter='resource.type="cloud_run_revision" 
    AND httpRequest.latency>"2s"' \
    --project="$PROJECT_ID" || print_color "$YELLOW" "Metric high_latency_requests already exists"

# Error rate metric
gcloud logging metrics create error_responses \
    --description="HTTP 5xx responses" \
    --log-filter='resource.type="cloud_run_revision" 
    AND httpRequest.status>=500' \
    --project="$PROJECT_ID" || print_color "$YELLOW" "Metric error_responses already exists"

# Create notification channels
print_color "$BLUE" "📧 Setting up notification channels..."

# Create email notification channel
CHANNEL_ID=$(gcloud alpha monitoring channels create \
    --display-name="Athena Finance Alerts" \
    --type=email \
    --channel-labels="email_address=$ALERT_EMAIL" \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null || echo "")

if [ -n "$CHANNEL_ID" ]; then
    print_color "$GREEN" "✅ Notification channel created: $CHANNEL_ID"
else
    print_color "$YELLOW" "⚠️  Notification channel might already exist"
fi

# Create basic alert policies using gcloud
print_color "$BLUE" "🚨 Creating alert policies..."

# High error rate alert
gcloud alpha monitoring policies create \
    --notification-channels="$CHANNEL_ID" \
    --display-name="High Error Rate Alert" \
    --condition-display-name="Error rate > 5%" \
    --condition="threshold" \
    --duration="300s" \
    --comparison="COMPARISON_GT" \
    --threshold-value="0.05" \
    --aggregation='{
        "alignmentPeriod": "60s",
        "perSeriesAligner": "ALIGN_RATE"
    }' \
    --filter='metric.type="run.googleapis.com/request_count" 
    AND resource.type="cloud_run_revision" 
    AND metric.label.response_code_class!="2xx"' \
    --project="$PROJECT_ID" || print_color "$YELLOW" "Alert policy might already exist"

# Create dashboard
print_color "$BLUE" "📊 Creating monitoring dashboard..."

# Dashboard JSON
cat > dashboard.json << 'EOF'
{
  "displayName": "Athena Finance Dashboard",
  "gridLayout": {
    "columns": 12,
    "widgets": [
      {
        "title": "Service Health",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_RATE",
                  "groupByFields": ["resource.service_name"]
                }
              }
            }
          }]
        }
      },
      {
        "title": "Request Latency P95",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"run.googleapis.com/request_latencies\" AND resource.type=\"cloud_run_revision\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_PERCENTILE_95",
                  "groupByFields": ["resource.service_name"]
                }
              }
            }
          }]
        }
      },
      {
        "title": "Error Rate",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/error_responses\" AND resource.type=\"cloud_run_revision\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            }
          }]
        }
      },
      {
        "title": "Memory Usage",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"run.googleapis.com/container/memory/utilizations\" AND resource.type=\"cloud_run_revision\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_MEAN",
                  "groupByFields": ["resource.service_name"]
                }
              }
            }
          }]
        }
      }
    ]
  }
}
EOF

# Create dashboard
DASHBOARD_ID=$(gcloud monitoring dashboards create --config-from-file=dashboard.json --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")

if [ -n "$DASHBOARD_ID" ]; then
    print_color "$GREEN" "✅ Dashboard created: $DASHBOARD_ID"
    print_color "$BLUE" "📊 View dashboard at: https://console.cloud.google.com/monitoring/dashboards/custom/${DASHBOARD_ID##*/}?project=$PROJECT_ID"
else
    print_color "$YELLOW" "⚠️  Dashboard might already exist"
fi

# Clean up
rm -f dashboard.json monitoring.tfplan

# Summary
print_color "$GREEN" "\n🎉 Monitoring infrastructure deployment complete!"
print_color "$BLUE" "📊 Next steps:"
print_color "$GREEN" "1. Deploy services if not already deployed"
print_color "$GREEN" "2. Verify alerts are working by visiting: https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
print_color "$GREEN" "3. Check dashboard at: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
print_color "$GREEN" "4. Configure budget alerts if needed"
print_color "$GREEN" "5. Test alert notifications"

# Test monitoring endpoints
if [ -n "$AUTH_URL" ] && [ -n "$FINANCE_URL" ]; then
    print_color "$BLUE" "\n🧪 Testing monitoring endpoints..."
    
    # Test metrics endpoint
    if curl -s "$AUTH_URL/metrics" | grep -q "http_requests_total"; then
        print_color "$GREEN" "✅ Metrics endpoint working on auth-service"
    else
        print_color "$YELLOW" "⚠️  Metrics endpoint not responding on auth-service"
    fi
    
    if curl -s "$FINANCE_URL/metrics" | grep -q "http_requests_total"; then
        print_color "$GREEN" "✅ Metrics endpoint working on finance-master"
    else
        print_color "$YELLOW" "⚠️  Metrics endpoint not responding on finance-master"
    fi
fi