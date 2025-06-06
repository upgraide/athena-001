#!/bin/bash

# GDPR Compliance Test Script

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "🔒 Testing GDPR Compliance Features"
echo "=================================="

# Variables
PROJECT_ID="athena-001"
AUTH_SERVICE_URL=${AUTH_SERVICE_URL:-"http://localhost:8080"}
TEST_EMAIL="gdpr-test-$(date +%s)@test.com"
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

# Test 1: Register a test user
echo -e "\n${YELLOW}1. Creating test user for GDPR tests${NC}"
register_response=$(curl -s -X POST "$AUTH_SERVICE_URL/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\",
        \"firstName\": \"GDPR\",
        \"lastName\": \"Test\"
    }")

ACCESS_TOKEN=$(echo "$register_response" | jq -r '.tokens.accessToken' 2>/dev/null)
USER_ID=$(echo "$register_response" | jq -r '.user.id' 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ Failed to register test user${NC}"
    echo "$register_response"
    exit 1
else
    echo -e "${GREEN}✓ Test user created successfully${NC}"
    echo "User ID: $USER_ID"
fi

# Test 2: Privacy Policy (Public endpoint)
test_endpoint \
    "Privacy Policy (Public)" \
    "GET" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/privacy-policy" \
    "" \
    "" \
    200

# Test 3: Update Consent
test_endpoint \
    "Update Consent Preferences" \
    "POST" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/consent" \
    '{
        "dataProcessing": true,
        "marketing": false,
        "analytics": true
    }' \
    "$ACCESS_TOKEN" \
    200

# Test 4: Get Consent History
test_endpoint \
    "Get Consent History" \
    "GET" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/consent/history" \
    "" \
    "$ACCESS_TOKEN" \
    200

# Test 5: Request Data Export
export_response=$(test_endpoint \
    "Request Data Export" \
    "POST" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/export" \
    '{}' \
    "$ACCESS_TOKEN" \
    200)

# Test 6: Get GDPR Requests
test_endpoint \
    "Get GDPR Requests" \
    "GET" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/requests" \
    "" \
    "$ACCESS_TOKEN" \
    200

# Test 7: Test unauthorized access
test_endpoint \
    "Unauthorized GDPR Request" \
    "GET" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/requests" \
    "" \
    "" \
    401

# Test 8: Delete User Data (Right to be Forgotten)
test_endpoint \
    "Delete User Data - No Password" \
    "POST" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/delete" \
    '{}' \
    "$ACCESS_TOKEN" \
    400

test_endpoint \
    "Delete User Data - Wrong Password" \
    "POST" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/delete" \
    '{"password": "WrongPassword123!"}' \
    "$ACCESS_TOKEN" \
    401

test_endpoint \
    "Delete User Data - Correct Password" \
    "POST" \
    "$AUTH_SERVICE_URL/api/v1/gdpr/delete" \
    "{\"password\": \"$TEST_PASSWORD\"}" \
    "$ACCESS_TOKEN" \
    200

# Test 9: Verify user can no longer login after deletion
echo -e "\n${YELLOW}Testing: Login after deletion (should fail)${NC}"
sleep 2  # Give time for async deletion to process

login_response=$(curl -s -w "\n%{http_code}" -X POST "$AUTH_SERVICE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

status_code=$(echo "$login_response" | tail -n1)
if [ "$status_code" -eq "401" ]; then
    echo -e "${GREEN}✓ Login properly blocked after deletion${NC}"
else
    echo -e "${RED}✗ User can still login after deletion request${NC}"
fi

# Summary
echo -e "\n${GREEN}=================================="
echo "GDPR Compliance Tests Complete"
echo "==================================${NC}"
echo ""
echo "Key GDPR Features Tested:"
echo "✓ Privacy Policy endpoint"
echo "✓ Consent management"
echo "✓ Data export requests"
echo "✓ Right to be forgotten"
echo "✓ Audit trail for requests"
echo ""

# Check if running against production
if [[ "$AUTH_SERVICE_URL" == *"run.app"* ]]; then
    echo -e "${YELLOW}Note: Running against production service${NC}"
    echo "GDPR export files will be created in: gs://$PROJECT_ID-gdpr-exports/"
fi