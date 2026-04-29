#!/bin/bash

# Check if a Jira ticket exists for the current branch
# Returns exit code 0 if ticket exists, 1 if not found, 2 if error

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Checking if Jira ticket exists...${NC}\n"

# Load .env
if [ ! -f .env ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    exit 2
fi
source .env

# Validate credentials
if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
    echo -e "${RED}❌ Error: Missing Jira environment variables${NC}"
    exit 2
fi

# Get current branch
BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ]; then
    echo -e "${RED}❌ Error: Could not determine current branch${NC}"
    exit 2
fi

# Extract ticket ID from branch
if [[ $BRANCH =~ features/(KAN-[0-9]+) ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
    echo -e "   Branch: $BRANCH"
    echo -e "   Ticket ID: $TICKET_ID"
else
    echo -e "${YELLOW}⚠️  Branch '$BRANCH' has no ticket ID (expected format: features/KAN-{id})${NC}"
    echo "NO_TICKET_IN_BRANCH"
    exit 1
fi

# Check if ticket exists in Jira
JIRA_RESPONSE=$(curl -s -w "\n%{http_code}" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_ID" \
    -H "Content-Type: application/json" 2>/dev/null)

HTTP_CODE=$(echo "$JIRA_RESPONSE" | tail -n1)
BODY=$(echo "$JIRA_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    SUMMARY=$(echo "$BODY" | jq -r '.fields.summary // "No title"' 2>/dev/null || echo "Unknown")
    STATUS=$(echo "$BODY" | jq -r '.fields.status.name // "Unknown"' 2>/dev/null || echo "Unknown")
    echo -e "\n${GREEN}✅ Jira ticket exists!${NC}"
    echo -e "   Title: $SUMMARY"
    echo -e "   Status: $STATUS"
    echo "TICKET_EXISTS"
    exit 0
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "\n${YELLOW}⚠️  Jira ticket $TICKET_ID does NOT exist${NC}"
    echo "TICKET_NOT_FOUND"
    exit 1
else
    echo -e "\n${RED}❌ Error checking Jira ticket (HTTP $HTTP_CODE)${NC}"
    echo "ERROR"
    exit 2
fi
