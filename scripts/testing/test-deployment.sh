#!/bin/bash
set -e

echo "🧪 Testing secure microservice deployment locally..."

# Build the Docker image
echo "🏗️  Building Docker image..."
docker build --platform linux/amd64 -t athena-finance-master:test --build-arg SERVICE_NAME=finance-master .

# Test the image
echo "🚀 Testing the container..."
docker run --rm -d --name athena-test -p 8080:8080 -e NODE_ENV=development athena-finance-master:test

# Wait for container to start
echo "⏳ Waiting for service to start..."
sleep 10

# Test health endpoint
echo "🩺 Testing health endpoint..."
if curl -f http://localhost:8080/health; then
    echo "✅ Health check passed!"
else
    echo "❌ Health check failed!"
    docker logs athena-test
    exit 1
fi

# Clean up
echo "🧹 Cleaning up..."
docker stop athena-test

echo "✅ Local deployment test passed!"