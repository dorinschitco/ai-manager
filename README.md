# AI Manager

A CLI toolkit that automates the workflow between **Jira** and **GitHub** — create Jira tickets and pull requests directly from your terminal.

## Features

- 🎫 **Create Jira Tickets** — Automatically creates Jira tickets with title and description derived from your git history, then renames your branch to include the ticket ID.
- 🚀 **Create Pull Requests** — Push your branch, fetch Jira ticket details, and open a GitHub PR targeting `dev` with a rich description linking back to Jira.
- 🔍 **Check Jira Tickets** — Verify whether a Jira ticket exists for the current branch.

## Prerequisites

- Git
- Bash
- [jq](https://stedolan.github.io/jq/) (for JSON parsing)
- A `.env` file in the project root with the following variables:

```env
GITHUB_TOKEN=your_github_token
GITHUB_OWNER=your_github_org_or_user

JIRA_BASE_URL=https://your-domain.atlassian.net
JIRA_EMAIL=your_email@example.com
JIRA_API_TOKEN=your_jira_api_token
JIRA_PROJECT_KEY=KAN
```

> **Note:** `create_jira_ticket.sh` and `check_jira_ticket.sh` only require the Jira variables. `create_pr.sh` requires all variables.

## Usage

### Create a Jira Ticket

```bash
./create_jira_ticket.sh [title] [description]
```

Run this from a branch named `features/{feature-name}`. The script will:

1. Check if the branch already has a linked Jira ticket (skips creation if it exists).
2. Auto-derive the ticket title from git commits on the branch relative to `dev`/`main` (or use the optional `title` argument).
3. Auto-derive the description from the commit log and changed files (or use the optional `description` argument).
4. Create the ticket in Jira as a **Task**.
5. Rename your branch to `features/KAN-{id}`.

### Create a Pull Request

```bash
./create_pr.sh [changes_description]
```

Run this from a branch named `features/KAN-{id}` (or `features/KAN-{id}-...`). The script will:

1. Push the branch to GitHub.
2. Auto-detect the repository name from the git remote.
3. Fetch the linked Jira ticket details (title, status, priority, description).
4. Create a GitHub PR targeting `dev` with:
   - **Title**: `[KAN-{id}] {Jira ticket summary}`
   - **Body** including:
     - A link to the Jira ticket.
     - A summary section with the optional `changes_description` argument.
     - Jira metadata (status, priority, description).

If a PR for the branch already exists, the script will report it and exit.

### Check a Jira Ticket

```bash
./check_jira_ticket.sh
```

Run this from a branch named `features/KAN-{id}` (or `features/KAN-{id}-...`). The script will:

1. Extract the ticket ID from the branch name.
2. Query Jira to verify the ticket exists.
3. Print ticket title and status, or report if not found.

Exit codes:

| Code | Meaning |
|------|---------|
| `0`  | Ticket exists |
| `1`  | Not found or no ticket ID in branch name |
| `2`  | Error (missing `.env`, missing credentials, etc.) |

## Branch Naming Convention

```
features/{feature-name}          # before ticket creation
features/KAN-123                 # after ticket creation
```

## License

MIT
