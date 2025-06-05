#!/bin/bash
set -e

echo "🚀 Athena Finance - Deployment Orchestrator"
echo "==========================================="

# Check if this is a quick deployment or full deployment
if [ "$1" = "quick" ]; then
    echo "📦 Running quick deployment (services only)..."
    ./scripts/deployment/quick-deploy.sh
elif [ "$1" = "verify" ]; then
    echo "🔍 Running verification only..."
    ./scripts/testing/verify-security.sh
else
    echo "🏗️  Running complete deployment (infrastructure + services)..."
    ./scripts/deployment/deploy-complete.sh
fi

echo ""
echo "✅ Deployment orchestration completed!"
echo ""
echo "📖 Available commands:"
echo "  ./deploy.sh           - Full deployment"
echo "  ./deploy.sh quick     - Quick service deployment"
echo "  ./deploy.sh verify    - Verification only"