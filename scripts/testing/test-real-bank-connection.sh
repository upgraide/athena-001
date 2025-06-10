#!/bin/bash

# Real Bank Connection Test Script
# This helps you connect your actual bank account and verify the callback flow

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🏦 Real Bank Connection Test"
echo "============================"
echo ""
echo "This script will help you connect your real bank account"
echo "and test the complete OAuth callback flow."
echo ""

# Configuration
AUTH_URL="https://auth-service-17233902905.europe-west3.run.app"
BANKING_URL="https://banking-service-17233902905.europe-west3.run.app"

# Create a test user or use existing
read -p "Do you want to create a new test user? (y/n): " create_new

if [ "$create_new" = "y" ]; then
    EMAIL="real-test-$(date +%s)@test.com"
    PASSWORD="TestPass123!"
    
    echo -e "\n${BLUE}Creating new test user...${NC}"
    RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$EMAIL\",
            \"password\": \"$PASSWORD\",
            \"firstName\": \"Real\",
            \"lastName\": \"Test\"
        }")
    
    TOKEN=$(echo "$RESPONSE" | jq -r '.tokens.accessToken')
else
    read -p "Enter your test email: " EMAIL
    read -s -p "Enter your password: " PASSWORD
    echo ""
    
    echo -e "\n${BLUE}Logging in...${NC}"
    RESPONSE=$(curl -s -X POST "$AUTH_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$EMAIL\",
            \"password\": \"$PASSWORD\"
        }")
    
    TOKEN=$(echo "$RESPONSE" | jq -r '.tokens.accessToken')
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo -e "${RED}Authentication failed${NC}"
    echo "$RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Authenticated successfully${NC}"
echo ""

# Search for bank
echo -e "${BLUE}Searching for your bank...${NC}"
read -p "Enter bank name (e.g., Revolut, Monzo, HSBC): " BANK_NAME

SEARCH_RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$BANKING_URL/api/v1/banking/institutions/search?q=$BANK_NAME&country=GB")

echo ""
echo "Found banks:"
echo "$SEARCH_RESPONSE" | jq -r '.institutions[] | "\(.name) - ID: \(.id)"'

echo ""
read -p "Enter the Bank ID from above: " BANK_ID

# Initiate connection
echo -e "\n${BLUE}Initiating bank connection...${NC}"
CONNECTION_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$BANKING_URL/api/v1/banking/connections/initiate" \
    -d "{
        \"institutionId\": \"$BANK_ID\",
        \"accountType\": \"personal\"
    }")

CONNECTION_ID=$(echo "$CONNECTION_RESPONSE" | jq -r '.connectionId')
AUTH_LINK=$(echo "$CONNECTION_RESPONSE" | jq -r '.authUrl')

if [ -z "$CONNECTION_ID" ] || [ "$CONNECTION_ID" = "null" ]; then
    echo -e "${RED}Failed to initiate connection${NC}"
    echo "$CONNECTION_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Connection initiated successfully!${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Complete these steps:${NC}"
echo ""
echo "1. Open this URL in your browser:"
echo "   $AUTH_LINK"
echo ""
echo "2. Log in to your bank account"
echo ""
echo "3. Grant permission to access your account data"
echo ""
echo "4. You'll be redirected to a success page showing the requisition ID"
echo ""
echo -e "${BLUE}Save this information:${NC}"
echo "Email: $EMAIL"
echo "Password: $PASSWORD" 
echo "Token: $TOKEN"
echo "Connection ID: $CONNECTION_ID"
echo ""
echo "After completing the bank authentication, press Enter to check the connection status..."
read -p ""

# Check connection status
echo -e "\n${BLUE}Checking connection status...${NC}"
STATUS_RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "$BANKING_URL/api/v1/banking/connections/$CONNECTION_ID")

echo "$STATUS_RESPONSE" | jq '.'

STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')

if [ "$STATUS" = "linked" ]; then
    echo -e "\n${GREEN}✓ Connection successful!${NC}"
    
    # List accounts
    echo -e "\n${BLUE}Fetching your bank accounts...${NC}"
    ACCOUNTS_RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "$BANKING_URL/api/v1/banking/accounts")
    
    echo "$ACCOUNTS_RESPONSE" | jq '.'
    
    # Offer to sync transactions
    ACCOUNT_COUNT=$(echo "$ACCOUNTS_RESPONSE" | jq '.count')
    if [ "$ACCOUNT_COUNT" -gt 0 ]; then
        echo ""
        read -p "Would you like to sync transactions? (y/n): " sync_trans
        
        if [ "$sync_trans" = "y" ]; then
            echo -e "\n${BLUE}Syncing transactions...${NC}"
            SYNC_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
                "$BANKING_URL/api/v1/banking/transactions/sync")
            
            echo "$SYNC_RESPONSE" | jq '.'
        fi
    fi
else
    echo -e "\n${YELLOW}Connection status: $STATUS${NC}"
    echo "The connection may still be processing. Try checking again in a few moments."
fi

echo ""
echo -e "${GREEN}Test complete!${NC}"
echo ""
echo "You can continue to use these commands:"
echo ""
echo "# Check connection status:"
echo "curl -H 'Authorization: Bearer $TOKEN' \\"
echo "     $BANKING_URL/api/v1/banking/connections/$CONNECTION_ID"
echo ""
echo "# List accounts:"
echo "curl -H 'Authorization: Bearer $TOKEN' \\"
echo "     $BANKING_URL/api/v1/banking/accounts"
echo ""
echo "# Get transactions:"
echo "curl -H 'Authorization: Bearer $TOKEN' \\"
echo "     $BANKING_URL/api/v1/banking/transactions"