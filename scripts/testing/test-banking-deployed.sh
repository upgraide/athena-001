#!/bin/bash

# Test Banking Service in Cloud Run

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Service URLs
AUTH_URL="https://auth-service-17233902905.europe-west3.run.app"
BANKING_URL="https://banking-service-17233902905.europe-west3.run.app"

echo "🏦 Testing Banking Service in Cloud Run"
echo "======================================"
echo ""

# Step 1: Register a test user
echo -e "${BLUE}1. Registering test user...${NC}"
REGISTER_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "banking-test@athena.com",
    "password": "BankingTest123!",
    "firstName": "Banking",
    "lastName": "Test"
  }')

if echo "$REGISTER_RESPONSE" | grep -q "accessToken"; then
    echo -e "${GREEN}✓ User registered successfully${NC}"
    ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.accessToken')
else
    # Try login if user already exists
    echo -e "${YELLOW}User might already exist, trying login...${NC}"
    LOGIN_RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/login" \
      -H "Content-Type: application/json" \
      -d '{
        "email": "banking-test@athena.com",
        "password": "BankingTest123!"
      }')
    
    if echo "$LOGIN_RESPONSE" | grep -q "accessToken"; then
        echo -e "${GREEN}✓ Login successful${NC}"
        ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.tokens.accessToken')
    else
        echo -e "${RED}✗ Authentication failed${NC}"
        echo "$LOGIN_RESPONSE" | jq
        exit 1
    fi
fi

# Step 2: Test health endpoints
echo -e "\n${BLUE}2. Testing health endpoints...${NC}"
curl -s "$BANKING_URL/health" | jq

# Step 3: Test API health (requires auth)
echo -e "\n${BLUE}3. Testing API health endpoint...${NC}"
API_HEALTH=$(curl -s "$BANKING_URL/api/v1/banking/health" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$API_HEALTH" | grep -q "healthy"; then
    echo -e "${GREEN}✓ API health check passed${NC}"
    echo "$API_HEALTH" | jq
else
    echo -e "${RED}✗ API health check failed${NC}"
    echo "$API_HEALTH"
fi

# Step 4: List institutions
echo -e "\n${BLUE}4. Listing available banks...${NC}"
INSTITUTIONS=$(curl -s "$BANKING_URL/api/v1/banking/institutions?country=GB" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$INSTITUTIONS" | grep -q "institutions"; then
    echo -e "${GREEN}✓ Retrieved institutions list${NC}"
    INSTITUTION_COUNT=$(echo "$INSTITUTIONS" | jq '.count')
    echo "Found $INSTITUTION_COUNT institutions"
    
    # Show first 5 institutions
    echo "$INSTITUTIONS" | jq '.institutions[:5][] | {id, name, logo}'
else
    echo -e "${RED}✗ Failed to retrieve institutions${NC}"
    echo "$INSTITUTIONS"
fi

# Step 5: Search for Revolut
echo -e "\n${BLUE}5. Searching for Revolut...${NC}"
REVOLUT_SEARCH=$(curl -s "$BANKING_URL/api/v1/banking/institutions/search?q=Revolut&country=GB" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$REVOLUT_SEARCH" | grep -q "Revolut"; then
    echo -e "${GREEN}✓ Found Revolut${NC}"
    echo "$REVOLUT_SEARCH" | jq '.institutions[] | select(.name | contains("Revolut")) | {id, name, logo}'
    
    # Get Revolut ID
    REVOLUT_ID=$(echo "$REVOLUT_SEARCH" | jq -r '.institutions[] | select(.name | contains("Revolut")) | .id' | head -1)
    echo -e "\n${YELLOW}Revolut Institution ID: $REVOLUT_ID${NC}"
else
    echo -e "${RED}✗ Revolut not found${NC}"
    echo "$REVOLUT_SEARCH"
fi

# Step 6: List user connections
echo -e "\n${BLUE}6. Listing user bank connections...${NC}"
CONNECTIONS=$(curl -s "$BANKING_URL/api/v1/banking/connections" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

echo "$CONNECTIONS" | jq

# Step 7: Show how to initiate connection
echo -e "\n${BLUE}7. Initiating bank connection...${NC}"
echo -e "${YELLOW}To connect your bank account, use:${NC}"
echo ""
echo "curl -X POST \"$BANKING_URL/api/v1/banking/connections/initiate\" \\"
echo "  -H \"Authorization: Bearer \$ACCESS_TOKEN\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{"
echo "    \"institutionId\": \"$REVOLUT_ID\","
echo "    \"accountType\": \"personal\""
echo "  }'"
echo ""
echo -e "${GREEN}This will return an auth URL to complete the bank connection.${NC}"

echo ""
echo -e "${GREEN}✅ Banking Service Test Complete!${NC}"
echo ""
echo "Service URLs:"
echo "- Auth Service: $AUTH_URL"
echo "- Banking Service: $BANKING_URL"
echo ""