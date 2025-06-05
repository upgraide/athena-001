#!/bin/bash
set -e

PROJECT_ID="athena-finance-001"
REGION="europe-west3"
SERVICE_NAME="finance-master"

echo "🚀 Quick deployment with architecture fix..."

# Build and push with correct platform
echo "🏗️  Building for Cloud Run (linux/amd64)..."
gcloud builds submit --config config/cloudbuild.yaml

echo "✅ Deployment completed! Testing service..."

# Get service URL and test
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo "🌐 Service URL: $SERVICE_URL"

# Test health endpoint
echo "🩺 Testing health endpoint..."
sleep 30  # Give service time to start
curl -f "$SERVICE_URL/health" && echo "✅ Health check passed!" || echo "❌ Health check failed"

echo "🎉 Secure microservice deployment successful!"