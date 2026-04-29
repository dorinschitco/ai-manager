# AI Manager

A CLI toolkit that automates the workflow between **Jira** and **GitHub** — create Jira tickets and pull requests directly from your terminal.

## Features

- 🎫 **Create Jira Tickets** — Interactively create Jira tickets and automatically rename your branch to include the ticket ID.
- 🚀 **Create Pull Requests** — Push your branch, fetch Jira ticket details, and open a GitHub PR with a rich description linking back to Jira.

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

## Usage

### Create a Jira Ticket

```bash
./create_jira_ticket.sh
```

Run this from a branch named `features/{feature-name}`. The script will:

1. Prompt you for a title, description, issue type, and priority.
2. Create the ticket in Jira.
3. Rename your branch to `features/KAN-{id}-{feature-name}`.

### Create a Pull Request

```bash
./create_pr.sh
```

Run this from a branch named `features/KAN-{id}-...`. The script will:

1. Push the branch to GitHub.
2. Fetch the linked Jira ticket details (title, status, priority).
3. Create a GitHub PR with a formatted description and a link to the Jira ticket.

## Branch Naming Convention

```
features/{feature-name}          # before ticket creation
features/KAN-123-{feature-name}  # after ticket creation
```

## License

MIT
