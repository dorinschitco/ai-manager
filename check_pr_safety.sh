#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔒 Running PR Safety Checks...${NC}\n"

# Determine the diff target (compare against dev branch)
BASE_BRANCH="dev"
DIFF_TARGET="origin/$BASE_BRANCH"

# Fetch latest to ensure we have the base branch
git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true

# Get the diff of all changes that would be in the PR
DIFF=$(git diff "$DIFF_TARGET"...HEAD 2>/dev/null || git diff "$DIFF_TARGET"..HEAD 2>/dev/null || git diff HEAD~1..HEAD)

# Also get list of changed files
CHANGED_FILES=$(git diff --name-only "$DIFF_TARGET"...HEAD 2>/dev/null || git diff --name-only "$DIFF_TARGET"..HEAD 2>/dev/null || git diff --name-only HEAD~1..HEAD)

ISSUES_FOUND=0
WARNINGS_FOUND=0
ISSUES=""
WARNINGS=""

add_issue() {
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    ISSUES="${ISSUES}\n  ${RED}❌ [$1] $2${NC}"
    if [ -n "$3" ]; then
        ISSUES="${ISSUES}\n     ${YELLOW}Files: $3${NC}"
    fi
}

add_warning() {
    WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
    WARNINGS="${WARNINGS}\n  ${YELLOW}⚠️  [$1] $2${NC}"
    if [ -n "$3" ]; then
        WARNINGS="${WARNINGS}\n     ${YELLOW}Files: $3${NC}"
    fi
}

# ============================================================
# CHECK 1: Destructive Database Operations
# ============================================================
echo -e "${BLUE}1️⃣  Checking for destructive database operations...${NC}"

DB_DESTRUCTIVE_PATTERNS=(
    "DROP\s+TABLE"
    "DROP\s+DATABASE"
    "DROP\s+SCHEMA"
    "TRUNCATE\s+TABLE"
    "DELETE\s+FROM\s+[^\s]+\s*(;|$|WHERE\s+1\s*=\s*1)"
    "DROP\s+INDEX"
    "DROP\s+COLUMN"
    "DROP\s+CONSTRAINT"
)

for pattern in "${DB_DESTRUCTIVE_PATTERNS[@]}"; do
    MATCHES=$(echo "$DIFF" | grep -inE "^\+.*${pattern}" | grep -v "^\+\+\+" || true)
    if [ -n "$MATCHES" ]; then
        add_issue "DATABASE" "Destructive operation detected: $pattern" ""
        ISSUES="${ISSUES}\n     ${RED}$(echo "$MATCHES" | head -5)${NC}"
    fi
done

# ============================================================
# CHECK 2: Sensitive Data / Secrets Exposure
# ============================================================
echo -e "${BLUE}2️⃣  Checking for sensitive data exposure...${NC}"

SECRET_PATTERNS=(
    # API keys and tokens
    "(?i)(api[_-]?key|api[_-]?secret|access[_-]?token|auth[_-]?token|secret[_-]?key)\s*[:=]\s*['\"][^\s'\"]{8,}"
    # AWS keys
    "AKIA[0-9A-Z]{16}"
    # Private keys
    "-----BEGIN\s*(RSA|DSA|EC|OPENSSH|PGP)?\s*PRIVATE KEY-----"
    # Password assignments
    "(?i)(password|passwd|pwd)\s*[:=]\s*['\"][^\s'\"]{4,}"
    # Connection strings with passwords
    "(?i)(mysql|postgres|mongodb|redis|amqp)://[^:]+:[^@]+@"
    # JWT tokens
    "eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    # Generic secret/token with value
    "(?i)(client[_-]?secret|token)\s*[:=]\s*['\"][^\s'\"]{8,}"
)

for pattern in "${SECRET_PATTERNS[@]}"; do
    MATCHES=$(echo "$DIFF" | grep -inP "^\+.*${pattern}" 2>/dev/null | grep -v "^\+\+\+" || true)
    # Fallback to extended regex if PCRE not available
    if [ $? -ne 0 ] 2>/dev/null; then
        MATCHES=$(echo "$DIFF" | grep -inE "^\+.*${pattern}" 2>/dev/null | grep -v "^\+\+\+" || true)
    fi
    if [ -n "$MATCHES" ]; then
        add_issue "SECRETS" "Potential secret or credential detected" ""
        ISSUES="${ISSUES}\n     ${RED}$(echo "$MATCHES" | head -3 | sed 's/\(.\{80\}\).*/\1.../')${NC}"
    fi
done

# Check if .env or credential files are being committed
ENV_FILES=$(echo "$CHANGED_FILES" | grep -iE "^(\.env|\.env\.|.*credentials.*|.*secret.*|.*\.pem|.*\.key|.*\.pfx|.*\.p12)$" || true)
if [ -n "$ENV_FILES" ]; then
    add_issue "SECRETS" "Sensitive files are being committed" "$ENV_FILES"
fi

# ============================================================
# CHECK 3: File Deletion / Destructive File Operations
# ============================================================
echo -e "${BLUE}3️⃣  Checking for dangerous file operations...${NC}"

FILE_DANGER_PATTERNS=(
    "rm\s+-rf\s+/"
    "rm\s+-rf\s+\*"
    "rm\s+-rf\s+\.\."
    "rmdir\s+/"
    "shred\s+"
    "> /dev/sd"
    "mkfs\."
    "dd\s+if=.+of=/dev/"
    "format\s+[cCdD]:"
)

for pattern in "${FILE_DANGER_PATTERNS[@]}"; do
    MATCHES=$(echo "$DIFF" | grep -inE "^\+.*${pattern}" | grep -v "^\+\+\+" || true)
    if [ -n "$MATCHES" ]; then
        add_issue "FILE-DESTROY" "Dangerous file operation detected" ""
        ISSUES="${ISSUES}\n     ${RED}$(echo "$MATCHES" | head -3)${NC}"
    fi
done

# ============================================================
# CHECK 4: Firewall / Network Security Changes
# ============================================================
echo -e "${BLUE}4️⃣  Checking for firewall and network security changes...${NC}"

FIREWALL_PATTERNS=(
    "iptables\s+-F"
    "iptables\s+-X"
    "iptables\s+.*-j\s+ACCEPT"
    "ufw\s+disable"
    "ufw\s+allow\s+.*from\s+any"
    "firewall-cmd\s+.*--remove"
    "0\.0\.0\.0"
    "ACCEPT\s+all\s+--\s+anywhere"
    "SecurityGroupIngress.*0\.0\.0\.0/0"
    "ingress.*cidr.*0\.0\.0\.0/0"
)

for pattern in "${FIREWALL_PATTERNS[@]}"; do
    MATCHES=$(echo "$DIFF" | grep -inE "^\+.*${pattern}" | grep -v "^\+\+\+" || true)
    if [ -n "$MATCHES" ]; then
        add_warning "FIREWALL" "Firewall/network rule change detected: may open server to external access" ""
        WARNINGS="${WARNINGS}\n     ${YELLOW}$(echo "$MATCHES" | head -3)${NC}"
    fi
done

# ============================================================
# CHECK 5: Security Vulnerability Patterns
# ============================================================
echo -e "${BLUE}5️⃣  Checking for security vulnerability patterns...${NC}"

VULN_PATTERNS=(
    # Disabling SSL/TLS verification
    "(?i)(verify\s*=\s*false|ssl[_-]?verify\s*[:=]\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*['\"]?0|CURLOPT_SSL_VERIFYPEER.*false)"
    # Eval with user input
    "eval\s*\("
    # Shell injection
    "os\.system\s*\(.*\+|subprocess.*shell\s*=\s*True"
    # SQL injection risk
    "(?i)(execute|query)\s*\(.*['\"].*%s|(?i)(execute|query)\s*\(.*\+\s*[a-zA-Z]"
    # Debug mode in production
    "(?i)DEBUG\s*[:=]\s*['\"]?true|(?i)debug\s*[:=]\s*1"
    # CORS allow all
    "(?i)(Access-Control-Allow-Origin|cors).*\*"
    # Disabled authentication
    "(?i)(auth|authentication|authorize)\s*[:=]\s*false"
)

for pattern in "${VULN_PATTERNS[@]}"; do
    MATCHES=$(echo "$DIFF" | grep -inP "^\+.*${pattern}" 2>/dev/null | grep -v "^\+\+\+" || true)
    if [ $? -ne 0 ] 2>/dev/null; then
        MATCHES=$(echo "$DIFF" | grep -inE "^\+.*${pattern}" 2>/dev/null | grep -v "^\+\+\+" || true)
    fi
    if [ -n "$MATCHES" ]; then
        add_warning "SECURITY" "Potential security vulnerability pattern" ""
        WARNINGS="${WARNINGS}\n     ${YELLOW}$(echo "$MATCHES" | head -3 | sed 's/\(.\{100\}\).*/\1.../')${NC}"
    fi
done

# ============================================================
# CHECK 6: Infrastructure / Config Changes
# ============================================================
echo -e "${BLUE}6️⃣  Checking for risky infrastructure changes...${NC}"

INFRA_FILES=$(echo "$CHANGED_FILES" | grep -iE "(dockerfile|docker-compose|\.tf$|\.tfvars|cloudformation|k8s|kubernetes|nginx\.conf|apache|httpd\.conf|\.htaccess|Vagrantfile)" || true)
if [ -n "$INFRA_FILES" ]; then
    add_warning "INFRA" "Infrastructure configuration files modified — review carefully" "$INFRA_FILES"
fi

# Check for permission changes (chmod 777, etc.)
PERM_MATCHES=$(echo "$DIFF" | grep -inE "^\+.*(chmod\s+777|chmod\s+666|chmod\s+a\+rwx)" | grep -v "^\+\+\+" || true)
if [ -n "$PERM_MATCHES" ]; then
    add_issue "PERMISSIONS" "Overly permissive file permissions detected (777/666)" ""
    ISSUES="${ISSUES}\n     ${RED}$(echo "$PERM_MATCHES" | head -3)${NC}"
fi

# ============================================================
# RESULTS
# ============================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}   PR Safety Check Results${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"

if [ $ISSUES_FOUND -gt 0 ]; then
    echo -e "\n${RED}🚫 BLOCKING ISSUES ($ISSUES_FOUND):${NC}"
    echo -e "$ISSUES"
fi

if [ $WARNINGS_FOUND -gt 0 ]; then
    echo -e "\n${YELLOW}⚠️  WARNINGS ($WARNINGS_FOUND):${NC}"
    echo -e "$WARNINGS"
fi

if [ $ISSUES_FOUND -eq 0 ] && [ $WARNINGS_FOUND -eq 0 ]; then
    echo -e "\n${GREEN}✅ All safety checks passed! No issues found.${NC}"
fi

echo -e "\n${BLUE}═══════════════════════════════════════════${NC}\n"

# Exit with failure if blocking issues found
if [ $ISSUES_FOUND -gt 0 ]; then
    echo -e "${RED}🛑 PR creation blocked due to $ISSUES_FOUND safety issue(s).${NC}"
    echo -e "${YELLOW}💡 Please fix the issues above before creating a PR.${NC}"
    echo -e "${YELLOW}   If these are intentional changes, review them carefully and use --skip-safety-check flag.${NC}"
    exit 1
fi

if [ $WARNINGS_FOUND -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PR creation will proceed, but please review the $WARNINGS_FOUND warning(s) above.${NC}\n"
fi

echo -e "${GREEN}🔓 Safety checks passed. Safe to create PR.${NC}"
exit 0
