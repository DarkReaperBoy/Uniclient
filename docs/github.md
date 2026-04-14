# GitHub Core

REST API client for GitHub. Maps GitHub concepts to the unified chat model: issues/PRs become messages, repos become chats, organizations become groups.

## Setup

```go
import "uniclient/cores"

gh := cores.NewGitHubCore("./sessions/github.json")
```

## Authentication

```go
err := gh.Authenticate(cores.AuthConfig{
    BotToken: "ghp_xxxxxxxxxxxx", // Personal Access Token
})
```

Only PAT (Personal Access Token) auth is supported. Create one at https://github.com/settings/tokens with appropriate scopes.

## Key Features

- 768 exported methods covering the GitHub REST API
- Chat-via-issues model (DM = profile repo, group = org repo)
- Full repo management (create, fork, delete, settings)
- Actions/workflows management
- Pull request lifecycle (create, review, merge)
- Issue tracking with labels, milestones, projects
- Organization and team management
- Rate limiting with 5,000 req/hr budget
- Response caching for frequently accessed data

## Capabilities

`TEXT, CHANNELS, REACTIONS, READ_RECEIPTS, ADMIN, FOLDERS, SEARCH, POLLS`

## Example

```go
// Create a repository
err := gh.CreateRepo("my-project", "A cool project", false)

// Create an issue (= send message)
msg, err := gh.SendMessage("owner/repo", "Bug report: something broke")

// List repos (= get dialogs)
dialogs, err := gh.GetDialogs(20)

// Search code
results, err := gh.SearchCode("function handleError", "owner/repo")

// Create a pull request
pr, err := gh.CreatePullRequest("owner/repo", "feature-branch", "main", "Add feature", "Description")
```

## Chat Model Mapping

| GitHub Concept | Uniclient Concept |
|---------------|-------------------|
| Repository | Chat (Group) |
| Issue/PR | Message thread |
| Comment | Message |
| Organization | Folder |
| User | User |
| Reaction | Reaction |

## Dependencies

- Standard library `net/http` only
- No CGo required
