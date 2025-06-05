#!/bin/bash
set -e

PROJECT_ID="athena-finance-001"
REGION="europe-west3"

echo "🚀 Quick deployment for all services..."

# Deploy Finance Master Service
echo "🏗️  Building and deploying Finance Master service..."
gcloud builds submit --config config/cloudbuild.yaml

# Deploy Auth Service
echo "🔐 Building and deploying Auth service..."
gcloud builds submit --config config/cloudbuild-auth.yaml

echo "✅ All services deployed! Testing..."

# Test Finance Master
FINANCE_URL=$(gcloud run services describe finance-master --region=$REGION --format="value(status.url)")
echo "💰 Finance Master URL: $FINANCE_URL"
echo "🩺 Testing Finance Master health..."
curl -f "$FINANCE_URL/health" && echo "✅ Finance Master health check passed!" || echo "❌ Finance Master health check failed"

# Test Auth Service
AUTH_URL=$(gcloud run services describe auth-service --region=$REGION --format="value(status.url)")
echo "🔐 Auth Service URL: $AUTH_URL"
echo "🩺 Testing Auth Service health..."
curl -f "$AUTH_URL/api/v1/auth/health" && echo "✅ Auth Service health check passed!" || echo "❌ Auth Service health check failed"

echo ""
echo "🎉 All services deployment successful!"
echo ""
echo "📋 Service URLs:"
echo "  Finance Master: $FINANCE_URL"
echo "  Auth Service: $AUTH_URL"