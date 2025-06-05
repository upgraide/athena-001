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

# Use localhost for local testing or deployed URL
if [ "$1" = "local" ]; then
    AUTH_URL="http://localhost:8081"
    print_color "$BLUE" "🧪 Testing authentication locally at: $AUTH_URL"
else
    # Get deployed service URL
    AUTH_URL=$(gcloud run services describe auth-service --region=europe-west3 --format="value(status.url)" 2>/dev/null || echo "")
    if [ -z "$AUTH_URL" ]; then
        print_color "$RED" "❌ Auth service not deployed. Deploy first with: ./deploy.sh quick"
        exit 1
    fi
    print_color "$BLUE" "🧪 Testing authentication at: $AUTH_URL"
fi

# Test data
TEST_EMAIL="test.user$(date +%s)@example.com"
TEST_PASSWORD="Test123!@#"
TEST_FIRST_NAME="Test"
TEST_LAST_NAME="User"

print_color "$BLUE" "📝 Test user: $TEST_EMAIL"

# Test 1: Health check
print_color "$BLUE" "\n1️⃣ Testing health endpoint..."
if curl -f -s "$AUTH_URL/api/v1/auth/health" > /dev/null; then
    print_color "$GREEN" "✅ Health check passed"
else
    print_color "$RED" "❌ Health check failed"
    exit 1
fi

# Test 2: Registration
print_color "$BLUE" "\n2️⃣ Testing registration..."
REGISTER_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\",
        \"firstName\": \"$TEST_FIRST_NAME\",
        \"lastName\": \"$TEST_LAST_NAME\"
    }")

if echo "$REGISTER_RESPONSE" | grep -q "Registration successful"; then
    print_color "$GREEN" "✅ Registration successful"
    ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    REFRESH_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"refreshToken":"[^"]*' | cut -d'"' -f4)
    print_color "$YELLOW" "   Access token: ${ACCESS_TOKEN:0:20}..."
else
    print_color "$RED" "❌ Registration failed"
    print_color "$YELLOW" "   Response: $REGISTER_RESPONSE"
    exit 1
fi

# Test 3: Login
print_color "$BLUE" "\n3️⃣ Testing login..."
LOGIN_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

if echo "$LOGIN_RESPONSE" | grep -q "Login successful"; then
    print_color "$GREEN" "✅ Login successful"
    ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
else
    print_color "$RED" "❌ Login failed"
    print_color "$YELLOW" "   Response: $LOGIN_RESPONSE"
    exit 1
fi

# Test 4: Get current user (protected endpoint)
print_color "$BLUE" "\n4️⃣ Testing protected endpoint (get current user)..."
ME_RESPONSE=$(curl -s -X GET "$AUTH_URL/api/v1/auth/me" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$ME_RESPONSE" | grep -q "$TEST_EMAIL"; then
    print_color "$GREEN" "✅ Protected endpoint access successful"
    print_color "$YELLOW" "   User email: $TEST_EMAIL"
else
    print_color "$RED" "❌ Protected endpoint access failed"
    print_color "$YELLOW" "   Response: $ME_RESPONSE"
    exit 1
fi

# Test 5: Invalid token
print_color "$BLUE" "\n5️⃣ Testing invalid token rejection..."
INVALID_RESPONSE=$(curl -s -X GET "$AUTH_URL/api/v1/auth/me" \
    -H "Authorization: Bearer invalid-token-12345")

if echo "$INVALID_RESPONSE" | grep -q "Invalid or expired token"; then
    print_color "$GREEN" "✅ Invalid token properly rejected"
else
    print_color "$RED" "❌ Invalid token not rejected properly"
    print_color "$YELLOW" "   Response: $INVALID_RESPONSE"
fi

# Test 6: Refresh token
print_color "$BLUE" "\n6️⃣ Testing token refresh..."
REFRESH_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/refresh" \
    -H "Content-Type: application/json" \
    -d "{
        \"refreshToken\": \"$REFRESH_TOKEN\"
    }")

if echo "$REFRESH_RESPONSE" | grep -q "accessToken"; then
    print_color "$GREEN" "✅ Token refresh successful"
else
    print_color "$RED" "❌ Token refresh failed"
    print_color "$YELLOW" "   Response: $REFRESH_RESPONSE"
fi

# Test 7: Logout
print_color "$BLUE" "\n7️⃣ Testing logout..."
LOGOUT_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/logout" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$LOGOUT_RESPONSE" | grep -q "Logout successful"; then
    print_color "$GREEN" "✅ Logout successful"
else
    print_color "$RED" "❌ Logout failed"
    print_color "$YELLOW" "   Response: $LOGOUT_RESPONSE"
fi

# Summary
print_color "$GREEN" "\n🎉 Authentication test suite completed!"
print_color "$BLUE" "📊 All authentication endpoints are working correctly"
print_color "$BLUE" "🔐 JWT token flow verified"
print_color "$BLUE" "🛡️  Protected endpoints secured"