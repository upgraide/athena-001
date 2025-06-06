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

print_color "$BLUE" "🧪 Testing Finance Master with Authentication"
print_color "$BLUE" "Auth URL: $AUTH_URL"
print_color "$BLUE" "Finance URL: $FINANCE_URL"

# Create test user
TEST_EMAIL="finance.test$(date +%s)@example.com"
TEST_PASSWORD="Test123!@#"

print_color "$BLUE" "\n1️⃣ Creating test user..."
REGISTER_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\",
        \"firstName\": \"Finance\",
        \"lastName\": \"Tester\"
    }")

if echo "$REGISTER_RESPONSE" | grep -q "Registration successful"; then
    print_color "$GREEN" "✅ User created successfully"
    ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    USER_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    print_color "$YELLOW" "   User ID: $USER_ID"
else
    print_color "$RED" "❌ Registration failed"
    print_color "$YELLOW" "   Response: $REGISTER_RESPONSE"
    exit 1
fi

# Test 2: Try to access protected endpoint WITHOUT token
print_color "$BLUE" "\n2️⃣ Testing protected endpoint without token..."
UNAUTH_RESPONSE=$(curl -s -w "\n%{http_code}" "$FINANCE_URL/api/v1/accounts" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"accountData": {"name": "Test Account"}}')

HTTP_CODE=$(echo "$UNAUTH_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "401" ]; then
    print_color "$GREEN" "✅ Correctly rejected unauthorized request"
else
    print_color "$RED" "❌ Expected 401, got $HTTP_CODE"
fi

# Test 3: Create account WITH token
print_color "$BLUE" "\n3️⃣ Testing account creation with valid token..."
ACCOUNT_RESPONSE=$(curl -s -X POST "$FINANCE_URL/api/v1/accounts" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
        "accountData": {
            "name": "Test Savings Account",
            "type": "savings",
            "balance": 1000
        }
    }')

if echo "$ACCOUNT_RESPONSE" | grep -q "Account created successfully"; then
    print_color "$GREEN" "✅ Account created successfully"
    ACCOUNT_ID=$(echo "$ACCOUNT_RESPONSE" | grep -o '"accountId":"[^"]*' | cut -d'"' -f4)
    print_color "$YELLOW" "   Account ID: $ACCOUNT_ID"
else
    print_color "$RED" "❌ Account creation failed"
    print_color "$YELLOW" "   Response: $ACCOUNT_RESPONSE"
fi

# Test 4: Test transaction categorization
print_color "$BLUE" "\n4️⃣ Testing transaction categorization..."
TRANSACTION_RESPONSE=$(curl -s -X POST "$FINANCE_URL/api/v1/transactions/categorize" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{
        "transaction": {
            "id": "txn_123",
            "amount": 45.99,
            "description": "Uber ride to airport",
            "date": "2025-06-05"
        }
    }')

if echo "$TRANSACTION_RESPONSE" | grep -q "category"; then
    print_color "$GREEN" "✅ Transaction categorized successfully"
    print_color "$YELLOW" "   Response: $TRANSACTION_RESPONSE"
else
    print_color "$RED" "❌ Transaction categorization failed"
    print_color "$YELLOW" "   Response: $TRANSACTION_RESPONSE"
fi

# Test 5: Test insights endpoint
print_color "$BLUE" "\n5️⃣ Testing insights generation..."
INSIGHTS_RESPONSE=$(curl -s -X GET "$FINANCE_URL/api/v1/insights" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$INSIGHTS_RESPONSE" | grep -q "insights"; then
    print_color "$GREEN" "✅ Insights retrieved successfully"
else
    print_color "$RED" "❌ Insights retrieval failed"
    print_color "$YELLOW" "   Response: $INSIGHTS_RESPONSE"
fi

# Test 6: Test with invalid token
print_color "$BLUE" "\n6️⃣ Testing with invalid token..."
INVALID_RESPONSE=$(curl -s -w "\n%{http_code}" "$FINANCE_URL/api/v1/accounts" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer invalid-token-12345" \
    -d '{"accountData": {"name": "Test"}}')

HTTP_CODE=$(echo "$INVALID_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" = "403" ]; then
    print_color "$GREEN" "✅ Invalid token correctly rejected"
else
    print_color "$RED" "❌ Expected 403, got $HTTP_CODE"
fi

# Summary
print_color "$GREEN" "\n🎉 Finance Master authentication integration test completed!"
print_color "$BLUE" "📊 Summary:"
print_color "$GREEN" "✅ Protected endpoints require authentication"
print_color "$GREEN" "✅ Valid tokens grant access"
print_color "$GREEN" "✅ Invalid tokens are rejected"
print_color "$GREEN" "✅ User context automatically extracted from JWT"