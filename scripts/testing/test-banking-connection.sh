#!/bin/bash

# Banking Service Connection Test Script
# This script tests the complete bank connection flow including initiating and handling callbacks

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🏦 Banking Service Connection Test"
echo "=================================="
echo ""

# Configuration
PROJECT_ID="athena-finance-001"
REGION="europe-west3"

# Determine environment
if [ -n "$1" ] && [ "$1" = "production" ]; then
    echo -e "${BLUE}Testing in PRODUCTION environment${NC}"
    AUTH_SERVICE_URL="https://auth-service-17233902905.europe-west3.run.app"
    BANKING_SERVICE_URL="https://banking-service-17233902905.europe-west3.run.app"
else
    echo -e "${BLUE}Testing in LOCAL environment${NC}"
    AUTH_SERVICE_URL="http://localhost:8080"
    BANKING_SERVICE_URL="http://localhost:8084"
fi

# Test credentials
TEST_EMAIL=${TEST_EMAIL:-"banking-test-$(date +%s)@test.com"}
TEST_PASSWORD=${TEST_PASSWORD:-"TestPassword123!"}

# Helper functions
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
        echo -e "${GREEN}✓ Status: $status_code${NC}"
        if [ -n "$body" ]; then
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        fi
        printf "%s" "$body"  # Return the body for further processing
        return 0
    else
        echo -e "${RED}✗ Status: $status_code (Expected: $expected_status)${NC}"
        if [ -n "$body" ]; then
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
        fi
        return 1
    fi
}

# Step 1: Authenticate
echo -e "${BLUE}Step 1: Authenticating...${NC}"
# Try login first
login_response=$(curl -s -X POST "$AUTH_SERVICE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

ACCESS_TOKEN=$(echo "$login_response" | jq -r '.tokens.accessToken' 2>/dev/null)

# If login fails, register
if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "Creating new test user..."
    register_response=$(curl -s -X POST "$AUTH_SERVICE_URL/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$TEST_EMAIL\",
            \"password\": \"$TEST_PASSWORD\",
            \"firstName\": \"Banking\",
            \"lastName\": \"Test\"
        }")
    
    ACCESS_TOKEN=$(echo "$register_response" | jq -r '.tokens.accessToken' 2>/dev/null)
fi

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ Authentication failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated successfully${NC}"

# Step 2: List available institutions
echo -e "\n${BLUE}Step 2: Listing available institutions...${NC}"
institutions_response=$(test_endpoint \
    "List institutions" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/institutions?country=GB" \
    "" \
    "$ACCESS_TOKEN" \
    200)

institution_count=$(echo "$institutions_response" | jq '.count' 2>/dev/null)
echo -e "${GREEN}Found $institution_count institutions${NC}"

# Step 3: Search for specific bank
echo -e "\n${BLUE}Step 3: Searching for Revolut...${NC}"
search_response=$(test_endpoint \
    "Search for Revolut" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/institutions/search?q=revolut&country=GB" \
    "" \
    "$ACCESS_TOKEN" \
    200)

REVOLUT_ID=$(echo "$search_response" | jq -r '.institutions[]? | select(.name | contains("Revolut")) | .id' 2>/dev/null | head -1)

if [ -z "$REVOLUT_ID" ] || [ "$REVOLUT_ID" = "null" ]; then
    echo -e "${YELLOW}Revolut not found, using first available bank${NC}"
    BANK_ID=$(echo "$institutions_response" | jq -r '.institutions[0].id' 2>/dev/null)
    BANK_NAME=$(echo "$institutions_response" | jq -r '.institutions[0].name' 2>/dev/null)
else
    BANK_ID="$REVOLUT_ID"
    BANK_NAME="Revolut"
fi

echo -e "${GREEN}Selected bank: $BANK_NAME ($BANK_ID)${NC}"

# Step 4: List existing connections
echo -e "\n${BLUE}Step 4: Checking existing connections...${NC}"
connections_response=$(test_endpoint \
    "List connections" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/connections" \
    "" \
    "$ACCESS_TOKEN" \
    200)

existing_count=$(echo "$connections_response" | jq '.count' 2>/dev/null)
echo "Existing connections: $existing_count"

# Step 5: Initiate new connection
echo -e "\n${BLUE}Step 5: Initiating bank connection...${NC}"
connection_response=$(test_endpoint \
    "Initiate connection" \
    "POST" \
    "$BANKING_SERVICE_URL/api/v1/banking/connections/initiate" \
    "{
        \"institutionId\": \"$BANK_ID\",
        \"accountType\": \"personal\"
    }" \
    "$ACCESS_TOKEN" \
    200)

CONNECTION_ID=$(echo "$connection_response" | jq -r '.connectionId' 2>/dev/null)
AUTH_URL=$(echo "$connection_response" | jq -r '.authUrl' 2>/dev/null)

if [ -n "$CONNECTION_ID" ] && [ "$CONNECTION_ID" != "null" ]; then
    echo -e "${GREEN}✓ Connection initiated successfully${NC}"
    echo "Connection ID: $CONNECTION_ID"
    echo ""
    echo -e "${YELLOW}To complete the connection:${NC}"
    echo "1. Open this URL in your browser:"
    echo "   $AUTH_URL"
    echo ""
    echo "2. Complete the bank authentication"
    echo ""
    echo "3. After completion, check connection status:"
    echo "   curl -H 'Authorization: Bearer $ACCESS_TOKEN' \\"
    echo "        $BANKING_SERVICE_URL/api/v1/banking/connections/$CONNECTION_ID"
else
    echo -e "${RED}✗ Failed to initiate connection${NC}"
fi

# Step 6: List accounts (will be empty until connection is completed)
echo -e "\n${BLUE}Step 6: Checking accounts...${NC}"
accounts_response=$(test_endpoint \
    "List accounts" \
    "GET" \
    "$BANKING_SERVICE_URL/api/v1/banking/accounts" \
    "" \
    "$ACCESS_TOKEN" \
    200)

account_count=$(echo "$accounts_response" | jq '.count' 2>/dev/null)
echo "Current accounts: $account_count"

# Step 7: Show how to complete the flow
echo -e "\n${BLUE}Step 7: Next steps...${NC}"
echo -e "${GREEN}Connection Test Complete!${NC}"
echo ""
echo "To complete the bank connection flow:"
echo ""
echo "1. Open the auth URL provided above"
echo "2. Select your bank and authenticate"
echo "3. Grant permissions for account access"
echo "4. You'll be redirected back to the app"
echo ""
echo "After completing authentication, you can:"
echo ""
echo "# Check connection status:"
echo "curl -H 'Authorization: Bearer $ACCESS_TOKEN' \\"
echo "     $BANKING_SERVICE_URL/api/v1/banking/connections/$CONNECTION_ID"
echo ""
echo "# List connected accounts:"
echo "curl -H 'Authorization: Bearer $ACCESS_TOKEN' \\"
echo "     $BANKING_SERVICE_URL/api/v1/banking/accounts"
echo ""
echo "# Sync transactions:"
echo "curl -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' \\"
echo "     $BANKING_SERVICE_URL/api/v1/banking/transactions/sync"
echo ""

# Save test data for future use
echo -e "\n${BLUE}Test credentials saved:${NC}"
echo "Email: $TEST_EMAIL"
echo "Token: $ACCESS_TOKEN"
echo "Connection ID: $CONNECTION_ID"

# Optional: Create a helper script for checking status
if [ -n "$CONNECTION_ID" ] && [ "$CONNECTION_ID" != "null" ]; then
    cat > /tmp/check-banking-connection.sh << EOF
#!/bin/bash
# Check banking connection status
curl -s -H 'Authorization: Bearer $ACCESS_TOKEN' \\
     $BANKING_SERVICE_URL/api/v1/banking/connections/$CONNECTION_ID | jq '.'
EOF
    chmod +x /tmp/check-banking-connection.sh
    echo ""
    echo "Helper script created: /tmp/check-banking-connection.sh"
fi