#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🎫 Starting Jira Ticket Creation Workflow...${NC}\n"

# Step 1: Load .env file
echo -e "${BLUE}1️⃣  Loading credentials...${NC}"
if [ ! -f .env ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    exit 1
fi

source .env

# Validate Jira credentials
if [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ] || [ -z "$JIRA_PROJECT_KEY" ]; then
    echo -e "${RED}❌ Error: Missing required Jira environment variables${NC}"
    echo -e "${YELLOW}   Required: JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY${NC}"
    exit 1
fi

echo -e "${GREEN}   ✓ Credentials loaded${NC}\n"

# Step 2: Get current branch
echo -e "${BLUE}2️⃣  Checking current branch...${NC}"
BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ]; then
    echo -e "${RED}❌ Error: Could not determine current branch${NC}"
    exit 1
fi
echo -e "   Current branch: $BRANCH"

# Check if branch already has a Jira ticket
if [[ $BRANCH =~ features/(KAN-[0-9]+) ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
    echo -e "${YELLOW}   ⚠️  Branch already has ticket ID: $TICKET_ID${NC}"

    # Check if ticket exists in Jira
    JIRA_RESPONSE=$(curl -s -w "\n%{http_code}" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_ID" \
        -H "Content-Type: application/json" 2>/dev/null || echo -e "\n000")

    HTTP_CODE=$(echo "$JIRA_RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}   ✓ Jira ticket $TICKET_ID already exists${NC}"
        echo -e "   URL: $JIRA_BASE_URL/browse/$TICKET_ID\n"
        echo -e "${GREEN}✅ No action needed. Ticket already exists.${NC}"
        exit 0
    else
        echo -e "${YELLOW}   Ticket $TICKET_ID not found in Jira, will create it${NC}\n"
    fi
elif [[ ! $BRANCH =~ features/ ]]; then
    echo -e "${RED}❌ Error: Branch name '$BRANCH' doesn't match expected format (features/...)${NC}"
    echo -e "${YELLOW}   Please use format: features/{feature-name}${NC}"
    exit 1
fi

echo ""

# Step 3: Get ticket details from arguments or git history
echo -e "${BLUE}3️⃣  Collecting ticket details...${NC}"

JIRA_TITLE="${1:-}"
JIRA_DESCRIPTION="${2:-}"

# If title not provided as argument, derive from commit messages on current branch
if [ -z "$JIRA_TITLE" ]; then
    # Get the first commit message on this branch (relative to dev/main)
    BASE_BRANCH=$(git merge-base HEAD dev 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo "")
    if [ -n "$BASE_BRANCH" ]; then
        JIRA_TITLE=$(git log --format="%s" "$BASE_BRANCH..HEAD" | tail -1)
    fi
    # Fallback to latest commit message
    if [ -z "$JIRA_TITLE" ]; then
        JIRA_TITLE=$(git log -1 --format="%s")
    fi
fi

if [ -z "$JIRA_TITLE" ]; then
    echo -e "${RED}❌ Error: Could not determine ticket title from commits. Pass it as first argument.${NC}"
    exit 1
fi

# If description not provided, derive from commit log and changed files
if [ -z "$JIRA_DESCRIPTION" ]; then
    BASE_BRANCH=$(git merge-base HEAD dev 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo "")
    if [ -n "$BASE_BRANCH" ]; then
        COMMIT_LOG=$(git log --format="- %s" "$BASE_BRANCH..HEAD" 2>/dev/null)
        CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH..HEAD" 2>/dev/null | sed 's/^/- /')
    else
        COMMIT_LOG=$(git log -5 --format="- %s" 2>/dev/null)
        CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null | sed 's/^/- /' || echo "")
    fi
    JIRA_DESCRIPTION="Commits:\\n${COMMIT_LOG}\\n\\nChanged files:\\n${CHANGED_FILES}"
fi

echo -e "   Title: $JIRA_TITLE"
echo -e "   Type: Task (default)"
echo ""

ISSUE_TYPE="Task"

# Step 4: Create Jira ticket
echo -e "${BLUE}3️⃣  Creating Jira ticket...${NC}"

# Build description in Atlassian Document Format (ADF)
DESCRIPTION_JSON=$(cat <<EOF
{
    "type": "doc",
    "version": 1,
    "content": [
        {
            "type": "paragraph",
            "content": [
                {
                    "type": "text",
                    "text": "$(echo -e "$JIRA_DESCRIPTION" | sed 's/"/\\"/g' | tr -d '\n')"
                }
            ]
        }
    ]
}
EOF
)

# Create the Jira issue payload
JIRA_CREATE_PAYLOAD=$(cat <<EOF
{
    "fields": {
        "project": {
            "key": "$JIRA_PROJECT_KEY"
        },
        "summary": "$(echo "$JIRA_TITLE" | sed 's/"/\\"/g')",
        "description": $DESCRIPTION_JSON,
        "issuetype": {
            "name": "$ISSUE_TYPE"
        }
    }
}
EOF
)

# Create temp file for JSON payload
TEMP_JIRA_JSON=$(mktemp)
echo "$JIRA_CREATE_PAYLOAD" > "$TEMP_JIRA_JSON"

JIRA_CREATE_RESPONSE=$(curl -s -X POST \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/api/3/issue" \
    -d @"$TEMP_JIRA_JSON" 2>/dev/null || echo "{}")

rm -f "$TEMP_JIRA_JSON"

# Parse response
NEW_TICKET_ID=$(echo "$JIRA_CREATE_RESPONSE" | jq -r '.key // empty' 2>/dev/null)
JIRA_CREATE_ERROR=$(echo "$JIRA_CREATE_RESPONSE" | jq -r '.errors // .errorMessages // empty' 2>/dev/null)

if [ -n "$NEW_TICKET_ID" ]; then
    echo -e "${GREEN}   ✓ Jira ticket created: $NEW_TICKET_ID${NC}"
    echo -e "   URL: $JIRA_BASE_URL/browse/$NEW_TICKET_ID\n"

    # Auto-rename branch to include ticket ID
    if [[ ! $BRANCH =~ features/(KAN-[0-9]+) ]]; then
        NEW_BRANCH="features/$NEW_TICKET_ID"
        git branch -m "$BRANCH" "$NEW_BRANCH"
        BRANCH="$NEW_BRANCH"
        echo -e "${GREEN}   ✓ Branch renamed to $NEW_BRANCH${NC}\n"
    fi

    # Summary
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 Summary:${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   Jira Ticket: $NEW_TICKET_ID"
    echo -e "   Title: $JIRA_TITLE"
    echo -e "   Type: $ISSUE_TYPE"
    echo -e "   URL: $JIRA_BASE_URL/browse/$NEW_TICKET_ID"
    echo -e "   Branch: $BRANCH"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "${GREEN}✅ Jira ticket created successfully!${NC}"
else
    echo -e "${RED}   ❌ Failed to create Jira ticket${NC}"
    echo -e "${RED}   Error: $JIRA_CREATE_ERROR${NC}"
    echo -e "${RED}   Response: $(echo "$JIRA_CREATE_RESPONSE" | jq '.' 2>/dev/null || echo "$JIRA_CREATE_RESPONSE")${NC}"
    exit 1
fi
