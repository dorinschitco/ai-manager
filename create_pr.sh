#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting PR Creation Workflow...${NC}\n"

# Step 1: Load .env file
echo -e "${BLUE}1️⃣  Loading credentials...${NC}"
if [ ! -f .env ]; then
    echo -e "${RED}❌ Error: .env file not found${NC}"
    exit 1
fi

# Source .env file
source .env

# Validate credentials
if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_OWNER" ] || [ -z "$JIRA_BASE_URL" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ] || [ -z "$JIRA_PROJECT_KEY" ]; then
    echo -e "${RED}❌ Error: Missing required environment variables${NC}"
    exit 1
fi

echo -e "${GREEN}   ✓ Credentials loaded${NC}\n"

# Step 2: Get current branch
echo -e "${BLUE}2️⃣  Validating branch...${NC}"
BRANCH=$(git branch --show-current)
if [ -z "$BRANCH" ]; then
    echo -e "${RED}❌ Error: Could not determine current branch${NC}"
    exit 1
fi
echo -e "   Current branch: $BRANCH"

# Extract ticket ID
if [[ $BRANCH =~ features/(KAN-[0-9]+) ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
    echo -e "${GREEN}   ✓ Ticket ID extracted: $TICKET_ID${NC}\n"
else
    echo -e "${RED}❌ Error: Branch name '$BRANCH' doesn't match expected format (features/KAN-{id})${NC}"
    exit 1
fi

# Step 3: Push branch to GitHub
echo -e "${BLUE}3️⃣  Pushing branch to GitHub...${NC}"
if git push -u origin "$BRANCH" 2>/dev/null; then
    echo -e "${GREEN}   ✓ Branch pushed successfully${NC}\n"
else
    # Check if it failed because it's already up to date
    PUSH_OUTPUT=$(git push -u origin "$BRANCH" 2>&1)
    if [[ "$PUSH_OUTPUT" == *"Everything up-to-date"* ]] || [[ "$PUSH_OUTPUT" == *"up to date"* ]]; then
        echo -e "${GREEN}   ✓ Branch already up to date${NC}\n"
    else
        echo -e "${RED}❌ Error: Failed to push branch to GitHub${NC}"
        echo -e "${RED}   $PUSH_OUTPUT${NC}"
        exit 1
    fi
fi

# Step 4: Get repository info
echo -e "${BLUE}4️⃣  Getting repository info...${NC}"
REPO_URL=$(git config --get remote.origin.url || echo "")
if [ -z "$REPO_URL" ]; then
    echo -e "${YELLOW}   ⚠️  Could not determine repo from git remote${NC}"
    REPO="ai-manager"
else
    # Extract repo name from URL
    REPO=$(basename "$REPO_URL" .git)
fi
echo -e "   Repository: $GITHUB_OWNER/$REPO\n"

# Step 5: Fetch Jira data
echo -e "${BLUE}5️⃣  Fetching Jira ticket...${NC}"
JIRA_RESPONSE=$(curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_ID" \
    -H "Content-Type: application/json" 2>/dev/null || echo "{}")

if [ "$JIRA_RESPONSE" = "{}" ] || [ -z "$JIRA_RESPONSE" ]; then
    echo -e "${YELLOW}   ⚠️  Could not fetch Jira data, using defaults${NC}"
    SUMMARY="$TICKET_ID"
    STATUS="Unknown"
    PRIORITY="Unknown"
else
    # Parse JSON
    SUMMARY=$(echo "$JIRA_RESPONSE" | jq -r '.fields.summary // "No title"' 2>/dev/null || echo "$TICKET_ID")
    STATUS=$(echo "$JIRA_RESPONSE" | jq -r '.fields.status.name // "Unknown"' 2>/dev/null || echo "Unknown")
    PRIORITY=$(echo "$JIRA_RESPONSE" | jq -r '.fields.priority.name // "Unknown"' 2>/dev/null || echo "Unknown")
    DESCRIPTION=$(echo "$JIRA_RESPONSE" | jq -r '.fields.description // ""' 2>/dev/null || echo "")
fi

echo -e "   ✓ Title: $SUMMARY"
echo -e "   ✓ Status: $STATUS"
echo -e "   ✓ Priority: $PRIORITY\n"

# Step 6: Create PR
echo -e "${BLUE}6️⃣  Creating pull request...${NC}"

# Build PR body with proper JSON escaping
PR_BODY=$(cat <<EOF
## Jira Ticket
[$TICKET_ID]($JIRA_BASE_URL/browse/$TICKET_ID)

## Summary
$SUMMARY

## Description
${DESCRIPTION:-No description provided}

## Status
- **Status**: $STATUS
- **Priority**: $PRIORITY
EOF
)

# Escape JSON properly
PR_BODY_JSON=$(echo "$PR_BODY" | jq -Rs .)
SUMMARY_JSON=$(echo "$SUMMARY" | jq -Rs .)

# Create temporary JSON file for the request
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "title": "[$TICKET_ID] $SUMMARY",
  "body": $PR_BODY_JSON,
  "head": "$BRANCH",
  "base": "dev"
}
EOF

# Create PR
PR_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_OWNER/$REPO/pulls" \
    -d @"$TEMP_JSON")

# Clean up temp file
rm -f "$TEMP_JSON"

# Check if PR was created successfully
PR_NUMBER=$(echo "$PR_RESPONSE" | jq -r '.number // empty' 2>/dev/null)
PR_URL=$(echo "$PR_RESPONSE" | jq -r '.html_url // empty' 2>/dev/null)
PR_ERROR=$(echo "$PR_RESPONSE" | jq -r '.errors[0].message // .message // empty' 2>/dev/null)

if [ -n "$PR_NUMBER" ]; then
    echo -e "   ${GREEN}✓ PR created successfully!${NC}\n"
    echo -e "${GREEN}📊 Pull Request Details:${NC}"
    echo -e "   PR Number: #$PR_NUMBER"
    echo -e "   Title: [$TICKET_ID] $SUMMARY"
    echo -e "   URL: $PR_URL\n"
    echo -e "${GREEN}✅ All done! Your PR is ready for review.${NC}"
elif [ -n "$PR_ERROR" ]; then
    if [[ "$PR_ERROR" == *"already exists"* ]]; then
        echo -e "${YELLOW}   ⚠️  A pull request for this branch already exists${NC}"
    else
        echo -e "${RED}   ❌ Error creating PR: $PR_ERROR${NC}"
    fi
    exit 1
else
    echo -e "${RED}   ❌ Failed to create PR${NC}"
    echo -e "${RED}Response: $(echo "$PR_RESPONSE" | jq '.' 2>/dev/null || echo "$PR_RESPONSE")${NC}"
    exit 1
fi
