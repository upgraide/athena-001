#!/bin/bash

# Banking Service Test Script

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "🏦 Testing Banking Service"
echo "=========================="

# Variables
PROJECT_ID="athena-001"
AUTH_SERVICE_URL=${AUTH_SERVICE_URL:-"http://localhost:8080"}
BANKING_SERVICE_URL=${BANKING_SERVICE_URL:-"http://localhost:8084"}
TEST_EMAIL="banking-test-$(date +%s)@test.com"
TEST_PASSWORD="TestPassword123!"

# Function to test endpoint
test_endpoint() {
    local description=$1
    local method=$2
    local url=$3
    local data=$4
    local token=$5
    local expected_status=$6
    
    echo -e "\n${YELLOW}Testing:${NC} $description"
    
    if [ -n "$token" ]; then
        response=$(curl -s -w "\n%{http_code}" -X $method "$url" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -d "$data" 2>/dev/null)
    else
        response=$(curl -s -w "\n%{http_code}" -X $method "$url" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null)
    fi
    
    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$status_code" -eq "$expected_status" ]; then
        echo -e "${GREEN}✓ Status: $status_code (Expected: $expected_status)${NC}"
        echo "Response: $body" | jq '.' 2>/dev/null || echo "$body"
        return 0
    else
        echo -e "${RED}✗ Status: $status_code (Expected: $expected_status)${NC}"
        echo "Response: $body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
}

# Test 1: Health check
test_endpoint \
    "Banking Service Health Check" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/health" \
    "" \
    "" \
    200

# Test 2: Create test user and get token
echo -e "\n${YELLOW}Creating test user for banking tests${NC}"
register_response=$(curl -s -X POST "$AUTH_SERVICE_URL/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\",
        \"firstName\": \"Banking\",
        \"lastName\": \"Test\"
    }")

ACCESS_TOKEN=$(echo "$register_response" | jq -r '.tokens.accessToken' 2>/dev/null)
USER_ID=$(echo "$register_response" | jq -r '.user.id' 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ Failed to create test user${NC}"
    echo "$register_response"
    exit 1
else
    echo -e "${GREEN}✓ Test user created successfully${NC}"
    echo "User ID: $USER_ID"
fi

# Test 3: List institutions (GB)
test_endpoint \
    "List UK Banking Institutions" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/institutions?country=GB" \
    "" \
    "$ACCESS_TOKEN" \
    200

# Test 4: Search for Revolut
institution_response=$(test_endpoint \
    "Search for Revolut" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/institutions/search?q=revolut&country=GB" \
    "" \
    "$ACCESS_TOKEN" \
    200)

# Extract institution ID based on environment
if [ "$GOCARDLESS_ENV" = "sandbox" ]; then
    echo -e "${YELLOW}Running in sandbox mode${NC}"
    BANK_ID="SANDBOXFINANCE_SFIN0000"
    BANK_NAME="Sandbox Finance"
else
    # Try to find Revolut or another real bank
    REVOLUT_ID=$(echo "$institution_response" | grep -A20 "Response:" | jq -r '.institutions[]? | select(.name | contains("Revolut")) | .id' 2>/dev/null | head -1)
    
    if [ -n "$REVOLUT_ID" ] && [ "$REVOLUT_ID" != "null" ]; then
        echo -e "${GREEN}✓ Found Revolut: $REVOLUT_ID${NC}"
        BANK_ID="$REVOLUT_ID"
        BANK_NAME="Revolut"
    else
        # Try to find any available bank
        FIRST_BANK=$(echo "$institution_response" | grep -A20 "Response:" | jq -r '.institutions[0]?' 2>/dev/null)
        if [ -n "$FIRST_BANK" ] && [ "$FIRST_BANK" != "null" ]; then
            BANK_ID=$(echo "$FIRST_BANK" | jq -r '.id')
            BANK_NAME=$(echo "$FIRST_BANK" | jq -r '.name')
            echo -e "${YELLOW}Using first available bank: $BANK_NAME ($BANK_ID)${NC}"
        else
            echo -e "${RED}No banks available. Check your GoCardless credentials.${NC}"
            exit 1
        fi
    fi
fi

# Test 5: Initiate bank connection
connection_response=$(test_endpoint \
    "Initiate Bank Connection" \
    "POST" \
    "$BANKING_SERVICE_URL/api/v1/banking/connections/initiate" \
    "{
        \"institutionId\": \"$BANK_ID\",
        \"accountType\": \"personal\"
    }" \
    "$ACCESS_TOKEN" \
    200)

CONNECTION_ID=$(echo "$connection_response" | grep -A10 "Response:" | jq -r '.connectionId' 2>/dev/null)
AUTH_URL=$(echo "$connection_response" | grep -A10 "Response:" | jq -r '.authUrl' 2>/dev/null)

if [ -n "$CONNECTION_ID" ] && [ "$CONNECTION_ID" != "null" ]; then
    echo -e "${GREEN}✓ Connection initiated: $CONNECTION_ID${NC}"
    echo -e "${YELLOW}Auth URL: $AUTH_URL${NC}"
else
    echo -e "${RED}✗ Failed to initiate connection${NC}"
fi

# Test 6: List user connections
test_endpoint \
    "List User Bank Connections" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/connections" \
    "" \
    "$ACCESS_TOKEN" \
    200

# Test 7: Get specific connection
if [ -n "$CONNECTION_ID" ] && [ "$CONNECTION_ID" != "null" ]; then
    test_endpoint \
        "Get Connection Details" \
        "GET" \
        "$BANKING_SERVICE_URL/api/v1/banking/connections/$CONNECTION_ID" \
        "" \
        "$ACCESS_TOKEN" \
        200
fi

# Test 8: List accounts (should be empty before auth)
test_endpoint \
    "List Bank Accounts (Before Auth)" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/accounts" \
    "" \
    "$ACCESS_TOKEN" \
    200

# Test 9: Get accounts summary
test_endpoint \
    "Get Accounts Summary" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/summary" \
    "" \
    "$ACCESS_TOKEN" \
    200

# Test 10: Test unauthorized access
test_endpoint \
    "Unauthorized Request" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/institutions" \
    "" \
    "" \
    401

# Test 11: Test invalid institution
test_endpoint \
    "Invalid Institution ID" \
    "POST" \
    "$BANKING_SERVICE_URL/api/v1/banking/connections/initiate" \
    "{
        \"institutionId\": \"INVALID_BANK_ID\",
        \"accountType\": \"personal\"
    }" \
    "$ACCESS_TOKEN" \
    500

# Summary
echo -e "\n${GREEN}==================================="
echo "Banking Service Tests Complete"
echo "===================================${NC}"
echo ""
echo "Key Features Tested:"
echo "✓ Service health check"
echo "✓ Institution listing and search"
echo "✓ Bank connection initiation"
echo "✓ Connection management"
echo "✓ Account listing"
echo "✓ Authorization checks"
echo ""

if [ -n "$AUTH_URL" ] && [ "$AUTH_URL" != "null" ]; then
    echo -e "${YELLOW}Note: To complete the connection flow:${NC}"
    echo "1. Visit the auth URL: $AUTH_URL"
    echo "2. Complete authentication with the bank"
    echo "3. You'll be redirected back to complete the connection"
fi

# Check if running in sandbox mode
if [ "$GOCARDLESS_ENV" = "sandbox" ] || [ "$BANK_ID" = "SANDBOXFINANCE_SFIN0000" ]; then
    echo -e "\n${YELLOW}Running in sandbox mode. To test with real banks:${NC}"
    echo "1. Register for GoCardless Bank Account Data API"
    echo "2. Add credentials to .env file or Google Secret Manager:"
    echo "   - GOCARDLESS_SECRET_ID=your-secret-id"
    echo "   - GOCARDLESS_SECRET_KEY=your-secret-key"
    echo "3. Set GOCARDLESS_ENV=production"
    echo "4. See GOCARDLESS_SETUP.md for detailed instructions"
fi