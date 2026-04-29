#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting PR Creation Workflow (with Jira Ticket Support)...${NC}\n"

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
    echo -e "${YELLOW}   Required: GITHUB_TOKEN, GITHUB_OWNER, JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY${NC}"
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

# Check if branch follows the expected format
TICKET_ID=""
JIRA_TICKET_EXISTS=false
NEED_TO_CREATE_TICKET=false

if [[ $BRANCH =~ features/(KAN-[0-9]+) ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
    echo -e "${GREEN}   ✓ Ticket ID extracted: $TICKET_ID${NC}\n"
elif [[ $BRANCH =~ features/([^/]+) ]]; then
    # Branch has features/ prefix but not a KAN-xxx format
    BRANCH_SUFFIX="${BASH_REMATCH[1]}"
    echo -e "${YELLOW}   ⚠️  Branch doesn't have a Jira ticket ID (found: $BRANCH_SUFFIX)${NC}\n"
    NEED_TO_CREATE_TICKET=true
else
    echo -e "${RED}❌ Error: Branch name '$BRANCH' doesn't match expected format (features/...)${NC}"
    echo -e "${YELLOW}   Please use format: features/KAN-{id} or features/{feature-name}${NC}"
    exit 1
fi

# Step 3: Check if Jira ticket exists (if we have a ticket ID)
if [ -n "$TICKET_ID" ]; then
    echo -e "${BLUE}3️⃣  Checking Jira ticket...${NC}"

    JIRA_RESPONSE=$(curl -s -w "\n%{http_code}" -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_ID" \
        -H "Content-Type: application/json" 2>/dev/null || echo -e "\n000")

    HTTP_CODE=$(echo "$JIRA_RESPONSE" | tail -n1)
    JIRA_BODY=$(echo "$JIRA_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
        JIRA_TICKET_EXISTS=true
        echo -e "${GREEN}   ✓ Jira ticket $TICKET_ID exists${NC}\n"
    else
        echo -e "${YELLOW}   ⚠️  Jira ticket $TICKET_ID not found (HTTP $HTTP_CODE)${NC}\n"
        NEED_TO_CREATE_TICKET=true
    fi
fi

# Step 4: If ticket doesn't exist, ask user if they want to create one
if [ "$NEED_TO_CREATE_TICKET" = true ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📝 Jira ticket does not exist for this branch.${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    read -p "$(echo -e ${CYAN}Would you like to create a Jira ticket? [y/N]: ${NC})" CREATE_TICKET

    if [[ ! "$CREATE_TICKET" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}   Skipping Jira ticket creation. Exiting.${NC}"
        exit 0
    fi

    echo ""
    echo -e "${BLUE}📋 Please provide Jira ticket details:${NC}\n"

    # Get ticket title
    read -p "$(echo -e ${CYAN}Enter ticket title: ${NC})" JIRA_TITLE
    if [ -z "$JIRA_TITLE" ]; then
        echo -e "${RED}❌ Error: Title is required${NC}"
        exit 1
    fi

    echo ""

    # Get ticket description
    echo -e "${CYAN}Enter ticket description (press Enter twice to finish):${NC}"
    JIRA_DESCRIPTION=""
    while IFS= read -r line; do
        [ -z "$line" ] && break
        JIRA_DESCRIPTION="$JIRA_DESCRIPTION$line\n"
    done

    if [ -z "$JIRA_DESCRIPTION" ]; then
        JIRA_DESCRIPTION="Created via create_pr_and_jira_ticket.sh"
    fi

    echo ""

    # Get issue type (default: Task)
    echo -e "${CYAN}Select issue type:${NC}"
    echo "  1) Task (default)"
    echo "  2) Bug"
    echo "  3) Story"
    echo "  4) Epic"
    read -p "$(echo -e ${CYAN}Enter choice [1-4]: ${NC})" ISSUE_TYPE_CHOICE

    case $ISSUE_TYPE_CHOICE in
        2) ISSUE_TYPE="Bug" ;;
        3) ISSUE_TYPE="Story" ;;
        4) ISSUE_TYPE="Epic" ;;
        *) ISSUE_TYPE="Task" ;;
    esac

    echo ""
    echo -e "${BLUE}4️⃣  Creating Jira ticket...${NC}"

    # Build the Jira ticket JSON payload
    # Convert description to Atlassian Document Format (ADF)
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

    # Create the Jira issue
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
        TICKET_ID="$NEW_TICKET_ID"
        JIRA_TICKET_EXISTS=true

        # Ask if user wants to rename the branch
        echo -e "${YELLOW}⚠️  Note: Your branch name doesn't include the new ticket ID.${NC}"
        read -p "$(echo -e ${CYAN}Would you like to rename the branch to features/$NEW_TICKET_ID? [y/N]: ${NC})" RENAME_BRANCH

        if [[ "$RENAME_BRANCH" =~ ^[Yy]$ ]]; then
            NEW_BRANCH="features/$NEW_TICKET_ID"
            git branch -m "$BRANCH" "$NEW_BRANCH"
            BRANCH="$NEW_BRANCH"
            echo -e "${GREEN}   ✓ Branch renamed to $NEW_BRANCH${NC}\n"
        else
            echo -e "${YELLOW}   Keeping current branch name: $BRANCH${NC}\n"
        fi
    else
        echo -e "${RED}   ❌ Failed to create Jira ticket${NC}"
        echo -e "${RED}   Error: $JIRA_CREATE_ERROR${NC}"
        echo -e "${RED}   Response: $(echo "$JIRA_CREATE_RESPONSE" | jq '.' 2>/dev/null || echo "$JIRA_CREATE_RESPONSE")${NC}"
        exit 1
    fi
fi

# Step 5: Push branch to GitHub
echo -e "${BLUE}5️⃣  Pushing branch to GitHub...${NC}"
PUSH_OUTPUT=$(git push -u origin "$BRANCH" 2>&1) || true

if [[ "$PUSH_OUTPUT" == *"Everything up-to-date"* ]] || [[ "$PUSH_OUTPUT" == *"up to date"* ]]; then
    echo -e "${GREEN}   ✓ Branch already up to date${NC}\n"
elif [[ "$PUSH_OUTPUT" == *"->"* ]]; then
    echo -e "${GREEN}   ✓ Branch pushed successfully${NC}\n"
else
    # Try force push if branch was renamed
    if git push -u origin "$BRANCH" 2>/dev/null; then
        echo -e "${GREEN}   ✓ Branch pushed successfully${NC}\n"
    else
        echo -e "${RED}❌ Error: Failed to push branch to GitHub${NC}"
        echo -e "${RED}   $PUSH_OUTPUT${NC}"
        exit 1
    fi
fi

# Step 6: Get repository info
echo -e "${BLUE}6️⃣  Getting repository info...${NC}"
REPO_URL=$(git config --get remote.origin.url || echo "")
if [ -z "$REPO_URL" ]; then
    echo -e "${YELLOW}   ⚠️  Could not determine repo from git remote${NC}"
    REPO="ai-manager"
else
    # Extract repo name from URL
    REPO=$(basename "$REPO_URL" .git)
fi
echo -e "   Repository: $GITHUB_OWNER/$REPO\n"

# Step 7: Fetch Jira data (if ticket exists)
echo -e "${BLUE}7️⃣  Fetching Jira ticket details...${NC}"

if [ "$JIRA_TICKET_EXISTS" = true ] && [ -n "$TICKET_ID" ]; then
    JIRA_RESPONSE=$(curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
        "$JIRA_BASE_URL/rest/api/3/issue/$TICKET_ID" \
        -H "Content-Type: application/json" 2>/dev/null || echo "{}")

    if [ "$JIRA_RESPONSE" != "{}" ] && [ -n "$JIRA_RESPONSE" ]; then
        SUMMARY=$(echo "$JIRA_RESPONSE" | jq -r '.fields.summary // "No title"' 2>/dev/null || echo "$TICKET_ID")
        STATUS=$(echo "$JIRA_RESPONSE" | jq -r '.fields.status.name // "Unknown"' 2>/dev/null || echo "Unknown")
        PRIORITY=$(echo "$JIRA_RESPONSE" | jq -r '.fields.priority.name // "Unknown"' 2>/dev/null || echo "Unknown")
        DESCRIPTION=$(echo "$JIRA_RESPONSE" | jq -r '.fields.description.content[0].content[0].text // ""' 2>/dev/null || echo "")
    else
        SUMMARY="$TICKET_ID"
        STATUS="Unknown"
        PRIORITY="Unknown"
        DESCRIPTION=""
    fi
else
    SUMMARY="${JIRA_TITLE:-$BRANCH}"
    STATUS="New"
    PRIORITY="Medium"
    DESCRIPTION="${JIRA_DESCRIPTION:-No description provided}"
fi

echo -e "   ✓ Title: $SUMMARY"
echo -e "   ✓ Status: $STATUS"
echo -e "   ✓ Priority: $PRIORITY\n"

# Step 8: Create PR
echo -e "${BLUE}8️⃣  Creating pull request...${NC}"

# Build PR body
if [ -n "$TICKET_ID" ]; then
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
    PR_TITLE="[$TICKET_ID] $SUMMARY"
else
    PR_BODY=$(cat <<EOF
## Summary
$SUMMARY

## Description
${DESCRIPTION:-No description provided}
EOF
)
    PR_TITLE="$SUMMARY"
fi

# Escape JSON properly
PR_BODY_JSON=$(echo "$PR_BODY" | jq -Rs .)

# Create temporary JSON file for the request
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "title": $(echo "$PR_TITLE" | jq -Rs .),
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
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 Summary:${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ -n "$TICKET_ID" ]; then
        echo -e "   Jira Ticket: $TICKET_ID"
        echo -e "   Jira URL: $JIRA_BASE_URL/browse/$TICKET_ID"
    fi
    echo -e "   PR Number: #$PR_NUMBER"
    echo -e "   PR Title: $PR_TITLE"
    echo -e "   PR URL: $PR_URL"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
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
