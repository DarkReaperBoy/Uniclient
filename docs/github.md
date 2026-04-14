# GitHub Core — API Reference

Pure Go GitHub REST API v3 client. Maps GitHub concepts to the unified chat model: repositories become chats, issues/PRs become message threads, comments become messages, organizations become folders. Discussions use the GraphQL API. No CGo, no external dependencies.

**309 exported methods** across connection, issues, pull requests, discussions, notifications, gists, repos, search, releases, reactions, organizations, teams, projects, and user profile management.

## Table of Contents

- [Setup](#setup)
- [Types](#types)
- [Connection & Authentication](#connection--authentication)
- [Core Interface Methods — Messaging](#core-interface-methods--messaging)
- [Core Interface Methods — Chat Management](#core-interface-methods--chat-management)
- [Core Interface Methods — Contacts & Blocking](#core-interface-methods--contacts--blocking)
- [Core Interface Methods — Search](#core-interface-methods--search)
- [Core Interface Methods — Misc](#core-interface-methods--misc)
- [Issues — CRUD & State](#issues--crud--state)
- [Issues — Labels](#issues--labels)
- [Issues — Milestones](#issues--milestones)
- [Issues — Assignees](#issues--assignees)
- [Issues — Sub-Issues & Dependencies](#issues--sub-issues--dependencies)
- [Issues — Events & Timeline](#issues--events--timeline)
- [Pull Requests — CRUD](#pull-requests--crud)
- [Pull Requests — Reviews](#pull-requests--reviews)
- [Pull Requests — Review Comments](#pull-requests--review-comments)
- [Pull Requests — Commits, Files & Merge](#pull-requests--commits-files--merge)
- [Discussions](#discussions)
- [Comments — Commit Comments](#comments--commit-comments)
- [Reactions](#reactions)
- [Notifications](#notifications)
- [User Profiles & Social](#user-profiles--social)
- [Organizations & Members](#organizations--members)
- [Organization Roles](#organization-roles)
- [Organization Invitations](#organization-invitations)
- [Teams](#teams)
- [Repositories — CRUD & Settings](#repositories--crud--settings)
- [Repositories — Collaborators](#repositories--collaborators)
- [Repositories — Metadata](#repositories--metadata)
- [Search](#search)
- [Gists](#gists)
- [Starring & Watching](#starring--watching)
- [Events & Feeds](#events--feeds)
- [Releases & Assets](#releases--assets)
- [Contents & Files](#contents--files)
- [Branches, Tags & Commits](#branches-tags--commits)
- [Projects V2](#projects-v2)
- [Interaction Limits](#interaction-limits)
- [Utility](#utility)
- [Unsupported Core Methods](#unsupported-core-methods)

## Setup

```go
import "uniclient/cores"

gh := cores.NewGitHubCore("./sessions/github.json")
```

**Capabilities:** `TEXT`, `CHANNELS`, `REACTIONS`, `READ_RECEIPTS`, `ADMIN`, `FOLDERS`, `SEARCH`, `POLLS`

**Rate limiting:** 5,000 requests/hour. Read requests are paced at 100ms intervals, write requests at 1.5s intervals. Managed automatically by the internal rate limiter.

**Response caching:** Frequently accessed endpoints use TTL-based caching with ETags and `If-Modified-Since` headers for conditional requests.

## Types

### GitHubCore

```go
type GitHubCore struct {
    // Auth state
    authed   bool
    token    string   // Personal Access Token
    username string   // authenticated user's login
    userID   int64    // authenticated user's numeric ID

    // HTTP client, rate limiter, response cache
    client *http.Client
    rl     *ghRateLimiter
    cache  *ghCache

    // Dialog and message caches
    dialogs  map[string]*ghDialog
    messages map[string][]*Message

    // Notification polling state (ETags, If-Modified-Since)
    // Per-thread ETags for conditional polling
    // DM issue cache, group repo cache, blocked users, pinned messages, read state
    // Session persistence path
}
```

All fields are unexported. Interact through the constructor and exported methods only.

### Chat Model Mapping

| GitHub Concept | Uniclient Concept |
|---------------|-------------------|
| Repository | Chat / Dialog (Group) |
| Issue / PR | Message thread |
| Comment | Message |
| Organization | Folder |
| User | User |
| Reaction | Reaction |
| Label | Tag / Category |
| Milestone | Folder subdivision |

---

## Connection & Authentication

### Name

```go
func (g *GitHubCore) Name() string
```

Returns `"github"`.

### Capabilities

```go
func (g *GitHubCore) Capabilities() []string
```

Returns `["TEXT", "CHANNELS", "REACTIONS", "READ_RECEIPTS", "ADMIN", "FOLDERS", "SEARCH", "POLLS"]`.

### Authenticate

```go
func (g *GitHubCore) Authenticate(cfg AuthConfig) error
```

Authenticates using a GitHub Personal Access Token. Validates the token against the `/user` endpoint and persists the session.

**AuthConfig fields:**
- `BotToken` — GitHub PAT (required). Create at https://github.com/settings/tokens with appropriate scopes.

```go
err := gh.Authenticate(cores.AuthConfig{
    BotToken: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
})
// Token is validated, username and user ID are cached.
// Session is persisted to the session path for reuse.
```

### Logout

```go
func (g *GitHubCore) Logout() error
```

Clears authentication state. Does not revoke the token on GitHub's side.

### Close

```go
func (g *GitHubCore) Close() error
```

Full shutdown: saves session, cancels background context, clears caches.

### OnUpdate

```go
func (g *GitHubCore) OnUpdate(handler func(Update))
```

Registers a handler for real-time updates. GitHub uses polling-based notification checking rather than WebSocket push.

### GetSessions

```go
func (g *GitHubCore) GetSessions() ([]Session, error)
```

Returns the current PAT session as a single-element list (GitHub PATs do not have multiple sessions).

### TerminateSession

```go
func (g *GitHubCore) TerminateSession(_ string) error
```

Returns `ErrNotSupported` — GitHub PATs cannot be terminated programmatically through the API.

---

## Core Interface Methods — Messaging

Issues and PRs are the messaging substrate. `chatID` is `"owner/repo"`, `msgID` is the issue/comment number as a string.

### SendMessage

```go
func (g *GitHubCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error)
```

Creates a new issue in the repository. The message text becomes the issue title. Returns the created issue as a Message.

```go
msg, err := gh.SendMessage("octocat/hello-world", cores.OutgoingMessage{
    Text: "Bug: login page broken on Safari",
})
// msg.ID = "42" (issue number)
```

### GetMessages

```go
func (g *GitHubCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error)
```

Lists issues and their comments for a repository. Uses pagination opts for page size.

### EditMessage

```go
func (g *GitHubCore) EditMessage(chatID string, msgID string, text string) (*Message, error)
```

Edits an issue comment body, or the issue title if `msgID` refers to the issue itself.

### DeleteMessage

```go
func (g *GitHubCore) DeleteMessage(chatID string, msgID string) error
```

Deletes an issue comment.

### ReplyToMessage

```go
func (g *GitHubCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error)
```

Creates a comment on an issue (replies to a thread). The `replyToMsgID` is the issue number.

```go
reply, err := gh.ReplyToMessage("octocat/hello-world", "42", cores.OutgoingMessage{
    Text: "I can reproduce this on Safari 17.2",
})
```

### ForwardMessage

```go
func (g *GitHubCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error)
```

Copies an issue comment's text to another repository as a new issue, with attribution.

### ReactToMessage

```go
func (g *GitHubCore) ReactToMessage(chatID string, msgID string, emoji string) error
```

Adds a reaction to an issue or comment. Supported reactions: `+1`, `-1`, `laugh`, `confused`, `heart`, `hooray`, `rocket`, `eyes`.

### PinMessage

```go
func (g *GitHubCore) PinMessage(chatID string, msgID string) error
```

Pins an issue (tracked locally in session state).

### UnpinMessage

```go
func (g *GitHubCore) UnpinMessage(chatID string, msgID string) error
```

Unpins an issue.

### MarkAsRead

```go
func (g *GitHubCore) MarkAsRead(chatID string, upToMsgID string) error
```

Marks notifications as read for a repository thread up to the given message.

### GetReadState

```go
func (g *GitHubCore) GetReadState(chatID string) (*ReadState, error)
```

Returns the read state for a repository (last read message ID and unread count).

### UploadFile

```go
func (g *GitHubCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error)
```

Uploads a file as a release asset or issue attachment (via GitHub's upload endpoint). Reports progress via callback.

### DownloadFile

```go
func (g *GitHubCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error
```

Downloads a file from a GitHub URL (release asset, raw content, etc.) to a local path.

### SendImageBase64

```go
func (g *GitHubCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error)
```

Uploads a base64-encoded image as an issue attachment with an optional caption comment.

---

## Core Interface Methods — Chat Management

### GetDialogs

```go
func (g *GitHubCore) GetDialogs(opts PaginationOpts) ([]Dialog, error)
```

Lists repositories the authenticated user has access to, mapped as Dialogs.

```go
dialogs, err := gh.GetDialogs(cores.PaginationOpts{Limit: 30})
for _, d := range dialogs {
    fmt.Printf("%s — %s\n", d.ID, d.Title) // "octocat/hello-world — hello-world"
}
```

### CreateGroup

```go
func (g *GitHubCore) CreateGroup(name string, members []string) (*Dialog, error)
```

Creates a new repository and adds members as collaborators.

### CreateChannel

```go
func (g *GitHubCore) CreateChannel(name string, description string) (*Dialog, error)
```

Creates a new public repository with a description.

### CreateTopic

```go
func (g *GitHubCore) CreateTopic(chatID string, name string) (*Dialog, error)
```

Creates a new issue in the repository (issue = topic/thread within the chat).

### GetFolders

```go
func (g *GitHubCore) GetFolders() ([]Folder, error)
```

Lists organizations the user belongs to, mapped as Folders.

### CreateFolder

```go
func (g *GitHubCore) CreateFolder(name string, chatIDs []string) (*Folder, error)
```

Returns `ErrNotSupported` — organizations cannot be created via the REST API.

### GetChatInfo

```go
func (g *GitHubCore) GetChatInfo(chatID string) (*Dialog, error)
```

Returns detailed repository info as a Dialog (description, stars, forks, language, etc.).

### EditChatTitle

```go
func (g *GitHubCore) EditChatTitle(chatID string, title string) error
```

Renames a repository via `PATCH /repos/{owner}/{repo}`.

### EditChatDescription

```go
func (g *GitHubCore) EditChatDescription(chatID string, description string) error
```

Updates the repository description.

### LeaveChat

```go
func (g *GitHubCore) LeaveChat(chatID string) error
```

Removes the authenticated user as a collaborator from the repository.

### GetInviteLink

```go
func (g *GitHubCore) GetInviteLink(chatID string) (string, error)
```

Returns the repository's HTML URL as the invite link.

### AddMembers

```go
func (g *GitHubCore) AddMembers(chatID string, userIDs []string) error
```

Adds users as collaborators to the repository.

### RemoveMember

```go
func (g *GitHubCore) RemoveMember(chatID string, userID string) error
```

Removes a collaborator from the repository.

### BanMember

```go
func (g *GitHubCore) BanMember(chatID string, userID string) error
```

Blocks a user from the repository's organization (or returns error for personal repos).

### UnbanMember

```go
func (g *GitHubCore) UnbanMember(chatID string, userID string) error
```

Returns `ErrNotSupported` — GitHub does not have a per-repo unban.

### GetMembers

```go
func (g *GitHubCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error)
```

Lists repository collaborators as Users.

### SetAdmin

```go
func (g *GitHubCore) SetAdmin(chatID string, userID string, admin bool) error
```

Sets a collaborator's permission level to `admin` (true) or `push` (false).

---

## Core Interface Methods — Contacts & Blocking

### GetContacts

```go
func (g *GitHubCore) GetContacts() ([]User, error)
```

Returns the authenticated user's followers and following as contacts.

### AddContact

```go
func (g *GitHubCore) AddContact(_ string, firstName string, _ string) error
```

Follows a GitHub user. The `firstName` parameter is used as the username.

### DeleteContact

```go
func (g *GitHubCore) DeleteContact(userID string) error
```

Unfollows a GitHub user.

### BlockUser

```go
func (g *GitHubCore) BlockUser(userID string) error
```

Blocks a user via `PUT /user/blocks/{username}`.

### UnblockUser

```go
func (g *GitHubCore) UnblockUser(userID string) error
```

Unblocks a user via `DELETE /user/blocks/{username}`.

### GetBlockedUsers

```go
func (g *GitHubCore) GetBlockedUsers() ([]User, error)
```

Lists all users blocked by the authenticated user.

### GetProfile

```go
func (g *GitHubCore) GetProfile(userID string) (*User, error)
```

Fetches a user's public profile by username.

---

## Core Interface Methods — Search

### SearchMessages

```go
func (g *GitHubCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error)
```

Searches issues and comments within a repository. Uses GitHub's search API with `repo:` qualifier.

### SearchGlobal

```go
func (g *GitHubCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error)
```

Searches repositories globally. Returns matching repos as Dialogs.

---

## Core Interface Methods — Misc

### SendTyping

```go
func (g *GitHubCore) SendTyping(_ string) error
```

Returns `ErrNotSupported` — GitHub has no typing indicator.

### CreatePoll

```go
func (g *GitHubCore) CreatePoll(chatID string, question string, options []string) (*Message, error)
```

Creates an issue with a Markdown-formatted poll (checkboxes). Users vote by reacting.

### VotePoll

```go
func (g *GitHubCore) VotePoll(chatID string, msgID string, optionIndex int) error
```

Adds a reaction to simulate a poll vote.

### SendSticker

```go
func (g *GitHubCore) SendSticker(chatID string, stickerID string) (*Message, error)
```

Returns `ErrNotSupported` — GitHub has no sticker system.

---

## Issues — CRUD & State

### LockIssue

```go
func (g *GitHubCore) LockIssue(owner, repo string, number int, reason string) error
```

Locks an issue. Reason can be `"off-topic"`, `"too heated"`, `"resolved"`, or `"spam"`.

### UnlockIssue

```go
func (g *GitHubCore) UnlockIssue(owner, repo string, number int) error
```

Unlocks a previously locked issue.

### ListAuthenticatedUserIssues

```go
func (g *GitHubCore) ListAuthenticatedUserIssues() (json.RawMessage, error)
```

Lists all issues assigned to the authenticated user across all repos.

### ListOrgIssues

```go
func (g *GitHubCore) ListOrgIssues(org string) (json.RawMessage, error)
```

Lists all issues in repositories belonging to the specified organization.

---

## Issues — Labels

### ListLabels

```go
func (g *GitHubCore) ListLabels(owner, repo string) (json.RawMessage, error)
```

Lists all labels defined on a repository.

### CreateLabel

```go
func (g *GitHubCore) CreateLabel(owner, repo, name, color, description string) (json.RawMessage, error)
```

Creates a new label. Color is a 6-character hex string without `#`.

```go
label, err := gh.CreateLabel("octocat", "hello-world", "priority:high", "d73a4a", "High priority issues")
```

### UpdateLabel

```go
func (g *GitHubCore) UpdateLabel(owner, repo, name string, updates map[string]any) (json.RawMessage, error)
```

Updates a label's name, color, or description. Pass changed fields in `updates`.

### DeleteLabel

```go
func (g *GitHubCore) DeleteLabel(owner, repo, name string) error
```

Deletes a label from the repository.

### AddLabelsToIssue

```go
func (g *GitHubCore) AddLabelsToIssue(owner, repo string, number int, labels []string) (json.RawMessage, error)
```

Adds one or more labels to an issue.

### RemoveLabel

```go
func (g *GitHubCore) RemoveLabel(owner, repo string, number int, label string) error
```

Removes a single label from an issue.

### SetLabels

```go
func (g *GitHubCore) SetLabels(owner, repo string, number int, labels []string) (json.RawMessage, error)
```

Replaces all labels on an issue with the provided set.

### ListMilestoneLabels

```go
func (g *GitHubCore) ListMilestoneLabels(owner, repo string, milestoneNumber int) (json.RawMessage, error)
```

Lists labels for issues within a specific milestone.

---

## Issues — Milestones

### ListMilestones

```go
func (g *GitHubCore) ListMilestones(owner, repo string) (json.RawMessage, error)
```

Lists all milestones on a repository.

### CreateMilestone

```go
func (g *GitHubCore) CreateMilestone(owner, repo, title, description string) (json.RawMessage, error)
```

Creates a new milestone.

### UpdateMilestone

```go
func (g *GitHubCore) UpdateMilestone(owner, repo string, number int, updates map[string]any) (json.RawMessage, error)
```

Updates a milestone's title, description, state, or due date.

### DeleteMilestone

```go
func (g *GitHubCore) DeleteMilestone(owner, repo string, number int) error
```

Deletes a milestone.

---

## Issues — Assignees

### AddIssueAssignees

```go
func (g *GitHubCore) AddIssueAssignees(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error)
```

Adds assignees to an issue. Payload: `{"assignees": ["user1", "user2"]}`.

### RemoveIssueAssignees

```go
func (g *GitHubCore) RemoveIssueAssignees(owner, repo string, issueNumber int, payload map[string]any) error
```

Removes assignees from an issue. Payload: `{"assignees": ["user1"]}`.

### ListRepoAssignees

```go
func (g *GitHubCore) ListRepoAssignees(owner, repo string) (json.RawMessage, error)
```

Lists users who can be assigned to issues in a repository.

### CheckAssignable

```go
func (g *GitHubCore) CheckAssignable(owner, repo, assignee string) (json.RawMessage, error)
```

Checks whether a user can be assigned to issues in a repository.

---

## Issues — Sub-Issues & Dependencies

### ListSubIssues

```go
func (g *GitHubCore) ListSubIssues(owner, repo string, number int) (json.RawMessage, error)
```

Lists sub-issues of a parent issue.

### AddSubIssue

```go
func (g *GitHubCore) AddSubIssue(owner, repo string, number int, subIssueID int) (json.RawMessage, error)
```

Adds a sub-issue to a parent issue.

### GetParentIssue

```go
func (g *GitHubCore) GetParentIssue(owner, repo string, issueNumber int) (json.RawMessage, error)
```

Returns the parent issue of a sub-issue, if any.

### RemoveSubIssue

```go
func (g *GitHubCore) RemoveSubIssue(owner, repo string, issueNumber int) error
```

Removes an issue from its parent.

### ReprioritizeSubIssue

```go
func (g *GitHubCore) ReprioritizeSubIssue(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error)
```

Changes the priority ordering of a sub-issue within its parent.

### ListBlockingDependencies

```go
func (g *GitHubCore) ListBlockingDependencies(owner, repo string, issueNumber int) (json.RawMessage, error)
```

Lists issues that block the specified issue.

### AddBlockingDependency

```go
func (g *GitHubCore) AddBlockingDependency(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error)
```

Adds a blocking dependency to an issue.

### RemoveBlockingDependency

```go
func (g *GitHubCore) RemoveBlockingDependency(owner, repo string, issueNumber, depID int) error
```

Removes a blocking dependency from an issue.

---

## Issues — Events & Timeline

### ListIssueEvents

```go
func (g *GitHubCore) ListIssueEvents(owner, repo string, number int) (json.RawMessage, error)
```

Lists events on a specific issue (labeled, assigned, closed, etc.).

### GetIssueTimeline

```go
func (g *GitHubCore) GetIssueTimeline(owner, repo string, number int) (json.RawMessage, error)
```

Returns the full timeline of an issue including comments, events, and cross-references.

### ListRepoIssueEvents

```go
func (g *GitHubCore) ListRepoIssueEvents(owner, repo string) (json.RawMessage, error)
```

Lists all issue events across the entire repository.

### GetIssueEvent

```go
func (g *GitHubCore) GetIssueEvent(owner, repo string, eventID int) (json.RawMessage, error)
```

Gets a single issue event by ID.

---

## Pull Requests — CRUD

### ListPullRequests

```go
func (g *GitHubCore) ListPullRequests(owner, repo, state string, perPage int) (json.RawMessage, error)
```

Lists pull requests. State: `"open"`, `"closed"`, or `"all"`.

```go
prs, err := gh.ListPullRequests("octocat", "hello-world", "open", 30)
```

### CreatePullRequest

```go
func (g *GitHubCore) CreatePullRequest(owner, repo, title, head, base, body string) (json.RawMessage, error)
```

Creates a new pull request.

```go
pr, err := gh.CreatePullRequest("octocat", "hello-world",
    "Add dark mode", "feature/dark-mode", "main",
    "Implements dark mode toggle in settings.")
```

### GetPullRequest

```go
func (g *GitHubCore) GetPullRequest(owner, repo string, number int) (json.RawMessage, error)
```

Gets a single pull request by number.

### UpdatePullRequest

```go
func (g *GitHubCore) UpdatePullRequest(owner, repo string, number int, updates map[string]any) (json.RawMessage, error)
```

Updates a PR's title, body, state, base branch, etc.

### UpdatePRBranch

```go
func (g *GitHubCore) UpdatePRBranch(owner, repo string, prNumber int, payload map[string]any) (json.RawMessage, error)
```

Updates a PR's head branch (e.g., merge base into head to bring it up to date).

### ListPRsForCommit

```go
func (g *GitHubCore) ListPRsForCommit(owner, repo, sha string) (json.RawMessage, error)
```

Lists pull requests associated with a specific commit SHA.

---

## Pull Requests — Reviews

### ListPRReviews

```go
func (g *GitHubCore) ListPRReviews(owner, repo string, number int) (json.RawMessage, error)
```

Lists all reviews on a pull request.

### CreatePRReview

```go
func (g *GitHubCore) CreatePRReview(owner, repo string, number int, body, event string) (json.RawMessage, error)
```

Creates a review. Event: `"APPROVE"`, `"REQUEST_CHANGES"`, or `"COMMENT"`.

### GetPRReview

```go
func (g *GitHubCore) GetPRReview(owner, repo string, prNumber, reviewID int) (json.RawMessage, error)
```

Gets a single review by ID.

### UpdatePRReview

```go
func (g *GitHubCore) UpdatePRReview(owner, repo string, prNumber, reviewID int, payload map[string]any) (json.RawMessage, error)
```

Updates a review's body.

### SubmitPRReview

```go
func (g *GitHubCore) SubmitPRReview(owner, repo string, prNumber, reviewID int, body, event string) (json.RawMessage, error)
```

Submits a pending review with a decision (approve, request changes, or comment).

### DismissPRReview

```go
func (g *GitHubCore) DismissPRReview(owner, repo string, prNumber, reviewID int, message string) (json.RawMessage, error)
```

Dismisses a review with a dismissal message.

### DeletePendingPRReview

```go
func (g *GitHubCore) DeletePendingPRReview(owner, repo string, prNumber, reviewID int) error
```

Deletes a pending (not yet submitted) review.

### RequestReviewers

```go
func (g *GitHubCore) RequestReviewers(owner, repo string, number int, reviewers []string, teamReviewers []string) (json.RawMessage, error)
```

Requests reviews from specific users and/or teams.

### GetRequestedReviewers

```go
func (g *GitHubCore) GetRequestedReviewers(owner, repo string, prNumber int) (json.RawMessage, error)
```

Lists users and teams whose reviews have been requested.

### RemoveRequestedReviewers

```go
func (g *GitHubCore) RemoveRequestedReviewers(owner, repo string, prNumber int, payload map[string]any) error
```

Removes review requests. Payload: `{"reviewers": ["user1"], "team_reviewers": ["team1"]}`.

---

## Pull Requests — Review Comments

### ListPRComments

```go
func (g *GitHubCore) ListPRComments(owner, repo string, number int) (json.RawMessage, error)
```

Lists review comments (inline code comments) on a pull request.

### CreatePRComment

```go
func (g *GitHubCore) CreatePRComment(owner, repo string, number int, body, path, commitID string, line int) (json.RawMessage, error)
```

Creates an inline review comment on a specific file and line.

```go
comment, err := gh.CreatePRComment("octocat", "hello-world", 42,
    "This should use a mutex here.", "src/handler.go",
    "abc123def456", 15)
```

### CreatePRCommentReply

```go
func (g *GitHubCore) CreatePRCommentReply(owner, repo string, prNumber, commentID int, payload map[string]any) (json.RawMessage, error)
```

Replies to an existing PR review comment.

### ListPRReviewComments

```go
func (g *GitHubCore) ListPRReviewComments(owner, repo string, prNumber, reviewID int) (json.RawMessage, error)
```

Lists comments within a specific review.

---

## Pull Requests — Commits, Files & Merge

### MergePullRequest

```go
func (g *GitHubCore) MergePullRequest(owner, repo string, number int, mergeMethod, commitTitle, commitMessage string) (json.RawMessage, error)
```

Merges a pull request. `mergeMethod`: `"merge"`, `"squash"`, or `"rebase"`.

```go
result, err := gh.MergePullRequest("octocat", "hello-world", 42,
    "squash", "feat: add dark mode (#42)", "Squash merge of dark mode feature")
```

### CheckPRMerged

```go
func (g *GitHubCore) CheckPRMerged(owner, repo string, prNumber int) (json.RawMessage, error)
```

Checks whether a pull request has been merged.

### ListPRCommits

```go
func (g *GitHubCore) ListPRCommits(owner, repo string, prNumber int) (json.RawMessage, error)
```

Lists commits on a pull request.

### ListPRFiles

```go
func (g *GitHubCore) ListPRFiles(owner, repo string, prNumber int) (json.RawMessage, error)
```

Lists files changed in a pull request.

---

## Discussions

Discussions use the GitHub GraphQL API internally.

### ListDiscussions

```go
func (g *GitHubCore) ListDiscussions(owner, repo string, first int) (json.RawMessage, error)
```

Lists repository discussions. `first` controls page size.

### CreateDiscussion

```go
func (g *GitHubCore) CreateDiscussion(repoID, categoryID, title, body string) (json.RawMessage, error)
```

Creates a new discussion. Requires the repository's GraphQL node ID and a category ID.

### UpdateDiscussion

```go
func (g *GitHubCore) UpdateDiscussion(discussionID, title, body string) (json.RawMessage, error)
```

Updates a discussion's title and body.

### DeleteDiscussion

```go
func (g *GitHubCore) DeleteDiscussion(discussionID string) (json.RawMessage, error)
```

Deletes a discussion.

### AddDiscussionComment

```go
func (g *GitHubCore) AddDiscussionComment(discussionID, body string) (json.RawMessage, error)
```

Adds a comment to a discussion.

### UpdateDiscussionComment

```go
func (g *GitHubCore) UpdateDiscussionComment(commentID, body string) (json.RawMessage, error)
```

Edits an existing discussion comment.

### DeleteDiscussionComment

```go
func (g *GitHubCore) DeleteDiscussionComment(commentID string) (json.RawMessage, error)
```

Deletes a discussion comment.

### MarkDiscussionCommentAsAnswer

```go
func (g *GitHubCore) MarkDiscussionCommentAsAnswer(commentID string) (json.RawMessage, error)
```

Marks a comment as the accepted answer in a Q&A discussion category.

---

## Comments — Commit Comments

### ListCommitComments

```go
func (g *GitHubCore) ListCommitComments(owner, repo, sha string) (json.RawMessage, error)
```

Lists comments on a specific commit.

### CreateCommitComment

```go
func (g *GitHubCore) CreateCommitComment(owner, repo, sha, body string) (json.RawMessage, error)
```

Creates a comment on a commit.

### UpdateCommitComment

```go
func (g *GitHubCore) UpdateCommitComment(owner, repo string, commentID int, body string) (json.RawMessage, error)
```

Edits a commit comment.

### DeleteCommitComment

```go
func (g *GitHubCore) DeleteCommitComment(owner, repo string, commentID int) error
```

Deletes a commit comment.

---

## Reactions

Reactions are available on issues, issue comments, commit comments, PR review comments, and releases. Each group has list/create/delete methods.

### Commit Comment Reactions

```go
func (g *GitHubCore) ListCommitCommentReactions(owner, repo string, commentID int) (json.RawMessage, error)
func (g *GitHubCore) CreateCommitCommentReaction(owner, repo string, commentID int, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) DeleteCommitCommentReaction(owner, repo string, commentID, reactionID int) error
```

Payload for create: `{"content": "+1"}`. Valid values: `+1`, `-1`, `laugh`, `confused`, `heart`, `hooray`, `rocket`, `eyes`.

### Issue Comment Reactions

```go
func (g *GitHubCore) ListIssueCommentReactions(owner, repo string, commentID int) (json.RawMessage, error)
func (g *GitHubCore) CreateIssueCommentReaction(owner, repo string, commentID int, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) DeleteIssueCommentReaction(owner, repo string, commentID, reactionID int) error
```

### Issue Reactions

```go
func (g *GitHubCore) ListIssueReactions(owner, repo string, issueNumber int) (json.RawMessage, error)
func (g *GitHubCore) CreateIssueReaction(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) DeleteIssueReaction(owner, repo string, issueNumber, reactionID int) error
```

### PR Review Comment Reactions

```go
func (g *GitHubCore) ListPRCommentReactions(owner, repo string, commentID int) (json.RawMessage, error)
func (g *GitHubCore) CreatePRCommentReaction(owner, repo string, commentID int, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) DeletePRCommentReaction(owner, repo string, commentID, reactionID int) error
```

### Release Reactions

```go
func (g *GitHubCore) ListReleaseReactions(owner, repo string, releaseID int) (json.RawMessage, error)
func (g *GitHubCore) CreateReleaseReaction(owner, repo string, releaseID int, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) DeleteReleaseReaction(owner, repo string, releaseID, reactionID int) error
```

---

## Notifications

### ListNotifications

```go
func (g *GitHubCore) ListNotifications(all bool, perPage int) (json.RawMessage, error)
```

Lists notifications. Set `all` to true to include read notifications.

```go
notifs, err := gh.ListNotifications(false, 50) // unread only
```

### MarkAllNotificationsRead

```go
func (g *GitHubCore) MarkAllNotificationsRead() error
```

Marks all notifications as read.

### GetNotificationThread

```go
func (g *GitHubCore) GetNotificationThread(threadID string) (json.RawMessage, error)
```

Gets a single notification thread.

### MarkThreadRead

```go
func (g *GitHubCore) MarkThreadRead(threadID string) error
```

Marks a specific notification thread as read.

### SubscribeThread

```go
func (g *GitHubCore) SubscribeThread(threadID string) (json.RawMessage, error)
```

Subscribes to a notification thread to receive future updates.

### UnsubscribeThread

```go
func (g *GitHubCore) UnsubscribeThread(threadID string) error
```

Unsubscribes from a notification thread.

---

## User Profiles & Social

### UpdateProfile

```go
func (g *GitHubCore) UpdateProfile(name, bio, blog, company, location string) (json.RawMessage, error)
```

Updates the authenticated user's profile fields. Pass empty strings to leave fields unchanged.

```go
profile, err := gh.UpdateProfile("Octocat", "I love open source", "https://github.blog", "GitHub", "San Francisco")
```

### ListEmails

```go
func (g *GitHubCore) ListEmails() (json.RawMessage, error)
```

Lists the authenticated user's email addresses.

### AddEmail

```go
func (g *GitHubCore) AddEmail(emails []string) (json.RawMessage, error)
```

Adds email addresses to the authenticated user's account.

### DeleteEmail

```go
func (g *GitHubCore) DeleteEmail(emails []string) error
```

Removes email addresses from the account.

### SetEmailVisibility

```go
func (g *GitHubCore) SetEmailVisibility(payload map[string]any) (json.RawMessage, error)
```

Sets the visibility of the user's primary email. Payload: `{"visibility": "public"}` or `"private"`.

### ListPublicEmails

```go
func (g *GitHubCore) ListPublicEmails() (json.RawMessage, error)
```

Lists the authenticated user's publicly visible email addresses.

### ListSocialAccounts

```go
func (g *GitHubCore) ListSocialAccounts() (json.RawMessage, error)
```

Lists the authenticated user's linked social media accounts.

### AddSocialAccount

```go
func (g *GitHubCore) AddSocialAccount(accountURLs []string) (json.RawMessage, error)
```

Adds social account URLs to the profile.

### DeleteSocialAccount

```go
func (g *GitHubCore) DeleteSocialAccount(accountURLs []string) error
```

Removes social account URLs from the profile.

### GetUserHovercard

```go
func (g *GitHubCore) GetUserHovercard(username string) (json.RawMessage, error)
```

Gets the hovercard information for a user (contextual info shown on hover in the GitHub UI).

---

## Organizations & Members

### ListOrgs

```go
func (g *GitHubCore) ListOrgs() (json.RawMessage, error)
```

Lists organizations the authenticated user belongs to.

### GetOrg

```go
func (g *GitHubCore) GetOrg(org string) (json.RawMessage, error)
```

Gets detailed information about an organization.

### ListOrgMembers

```go
func (g *GitHubCore) ListOrgMembers(org string) (json.RawMessage, error)
```

Lists members of an organization.

### ListPublicMembers

```go
func (g *GitHubCore) ListPublicMembers(org string) (json.RawMessage, error)
```

Lists public members of an organization.

### CheckPublicMembership

```go
func (g *GitHubCore) CheckPublicMembership(org, username string) (json.RawMessage, error)
```

Checks if a user is a public member of an organization.

### PublicizeMembership

```go
func (g *GitHubCore) PublicizeMembership(org, username string) (json.RawMessage, error)
```

Makes the authenticated user's membership in an organization public.

### ConcealMembership

```go
func (g *GitHubCore) ConcealMembership(org, username string) error
```

Conceals (hides) the authenticated user's membership in an organization.

### GetOrgMembership

```go
func (g *GitHubCore) GetOrgMembership(org, username string) (json.RawMessage, error)
```

Gets a user's membership details in an organization.

### SetOrgMembership

```go
func (g *GitHubCore) SetOrgMembership(org, username string, payload map[string]any) (json.RawMessage, error)
```

Sets or updates a user's organization membership. Payload: `{"role": "admin"}` or `"member"`.

### RemoveOrgMembership

```go
func (g *GitHubCore) RemoveOrgMembership(org, username string) error
```

Removes a user from an organization.

### ListUserOrgMemberships

```go
func (g *GitHubCore) ListUserOrgMemberships() (json.RawMessage, error)
```

Lists the authenticated user's organization memberships.

### GetUserOrgMembership

```go
func (g *GitHubCore) GetUserOrgMembership(org string) (json.RawMessage, error)
```

Gets the authenticated user's membership in a specific organization.

### ListOutsideCollaborators

```go
func (g *GitHubCore) ListOutsideCollaborators(org string) (json.RawMessage, error)
```

Lists outside collaborators (non-members with repo access) in an organization.

### ConvertToOutsideCollaborator

```go
func (g *GitHubCore) ConvertToOutsideCollaborator(org, username string) (json.RawMessage, error)
```

Converts an organization member to an outside collaborator (keeps repo access, removes org membership).

### RemoveOutsideCollaborator

```go
func (g *GitHubCore) RemoveOutsideCollaborator(org, username string) error
```

Removes an outside collaborator from an organization.

### ListOrgBlockedUsers

```go
func (g *GitHubCore) ListOrgBlockedUsers(org string) (json.RawMessage, error)
```

Lists users blocked by an organization.

### BlockOrgUser

```go
func (g *GitHubCore) BlockOrgUser(org, username string) (json.RawMessage, error)
```

Blocks a user from an organization.

### UnblockOrgUser

```go
func (g *GitHubCore) UnblockOrgUser(org, username string) error
```

Unblocks a user from an organization.

---

## Organization Roles

### ListOrgRoles

```go
func (g *GitHubCore) ListOrgRoles(org string) (json.RawMessage, error)
```

Lists custom roles defined in an organization.

### GetOrgRole

```go
func (g *GitHubCore) GetOrgRole(org string, roleID int) (json.RawMessage, error)
```

Gets a specific organization role by ID.

### AssignTeamRole

```go
func (g *GitHubCore) AssignTeamRole(org, teamSlug string, roleID int) (json.RawMessage, error)
```

Assigns an organization role to a team.

### RemoveTeamRole

```go
func (g *GitHubCore) RemoveTeamRole(org, teamSlug string, roleID int) error
```

Removes an organization role from a team.

### AssignUserRole

```go
func (g *GitHubCore) AssignUserRole(org, username string, roleID int) (json.RawMessage, error)
```

Assigns an organization role to a user.

### RemoveUserRole

```go
func (g *GitHubCore) RemoveUserRole(org, username string, roleID int) error
```

Removes an organization role from a user.

### ListTeamsForRole

```go
func (g *GitHubCore) ListTeamsForRole(org string, roleID int) (json.RawMessage, error)
```

Lists teams assigned to a specific organization role.

### ListUsersForRole

```go
func (g *GitHubCore) ListUsersForRole(org string, roleID int) (json.RawMessage, error)
```

Lists users assigned to a specific organization role.

---

## Organization Invitations

### ListOrgInvitations

```go
func (g *GitHubCore) ListOrgInvitations(org string) (json.RawMessage, error)
```

Lists pending invitations for an organization.

### CreateOrgInvitation

```go
func (g *GitHubCore) CreateOrgInvitation(org string, payload map[string]any) (json.RawMessage, error)
```

Creates an organization invitation. Payload: `{"invitee_id": 123}` or `{"email": "user@example.com", "role": "direct_member"}`.

### CancelOrgInvitation

```go
func (g *GitHubCore) CancelOrgInvitation(org string, invitationID int) error
```

Cancels a pending organization invitation.

### ListInvitationTeams

```go
func (g *GitHubCore) ListInvitationTeams(org string, invitationID int) (json.RawMessage, error)
```

Lists teams that a pending invitee will be added to.

### ListFailedInvitations

```go
func (g *GitHubCore) ListFailedInvitations(org string) (json.RawMessage, error)
```

Lists failed organization invitations.

---

## Teams

### ListOrgTeams

```go
func (g *GitHubCore) ListOrgTeams(org string) (json.RawMessage, error)
```

Lists all teams in an organization.

### CreateTeam

```go
func (g *GitHubCore) CreateTeam(org, name, description, privacy string) (json.RawMessage, error)
```

Creates a team. Privacy: `"secret"` (visible to org members only) or `"closed"` (visible to all).

### UpdateTeam

```go
func (g *GitHubCore) UpdateTeam(org, teamSlug string, updates map[string]any) (json.RawMessage, error)
```

Updates a team's name, description, privacy, or other settings.

### DeleteTeam

```go
func (g *GitHubCore) DeleteTeam(org, teamSlug string) error
```

Deletes a team from the organization.

### AddTeamMember

```go
func (g *GitHubCore) AddTeamMember(org, teamSlug, username, role string) (json.RawMessage, error)
```

Adds a user to a team. Role: `"member"` or `"maintainer"`.

### RemoveTeamMember

```go
func (g *GitHubCore) RemoveTeamMember(org, teamSlug, username string) error
```

Removes a user from a team.

### ListTeamInvitations

```go
func (g *GitHubCore) ListTeamInvitations(org, teamSlug string) (json.RawMessage, error)
```

Lists pending invitations for a team.

### ListTeamRepos

```go
func (g *GitHubCore) ListTeamRepos(org, teamSlug string) (json.RawMessage, error)
```

Lists repositories accessible to a team.

### CheckTeamRepo

```go
func (g *GitHubCore) CheckTeamRepo(org, teamSlug, owner, repo string) (json.RawMessage, error)
```

Checks if a team manages a specific repository.

### AddTeamRepo

```go
func (g *GitHubCore) AddTeamRepo(org, teamSlug, owner, repo string, payload map[string]any) (json.RawMessage, error)
```

Adds a repository to a team. Payload: `{"permission": "push"}`.

### RemoveTeamRepo

```go
func (g *GitHubCore) RemoveTeamRepo(org, teamSlug, owner, repo string) error
```

Removes a repository from a team.

### ListChildTeams

```go
func (g *GitHubCore) ListChildTeams(org, teamSlug string) (json.RawMessage, error)
```

Lists child teams of a team.

### ListUserTeams

```go
func (g *GitHubCore) ListUserTeams() (json.RawMessage, error)
```

Lists teams the authenticated user belongs to across all organizations.

---

## Repositories — CRUD & Settings

### DeleteRepo

```go
func (g *GitHubCore) DeleteRepo(owner, repo string) error
```

Permanently deletes a repository. Requires admin access.

### ForkRepo

```go
func (g *GitHubCore) ForkRepo(owner, repo string) (json.RawMessage, error)
```

Forks a repository to the authenticated user's account.

### TransferRepo

```go
func (g *GitHubCore) TransferRepo(owner, repo, newOwner string) (json.RawMessage, error)
```

Transfers repository ownership to another user or organization.

### ListForks

```go
func (g *GitHubCore) ListForks(owner, repo string) (json.RawMessage, error)
```

Lists forks of a repository.

### GetRepoTopics

```go
func (g *GitHubCore) GetRepoTopics(owner, repo string) (json.RawMessage, error)
```

Lists topics (tags) on a repository.

### SetRepoTopics

```go
func (g *GitHubCore) SetRepoTopics(owner, repo string, topics []string) (json.RawMessage, error)
```

Replaces all topics on a repository.

### ListContributors

```go
func (g *GitHubCore) ListContributors(owner, repo string) (json.RawMessage, error)
```

Lists contributors to a repository.

### GetRepoActivity

```go
func (g *GitHubCore) GetRepoActivity(owner, repo string) (json.RawMessage, error)
```

Gets repository activity (push events, etc.).

### ListInvitations

```go
func (g *GitHubCore) ListInvitations(owner, repo string) (json.RawMessage, error)
```

Lists pending collaborator invitations for a repository.

### UpdateInvitation

```go
func (g *GitHubCore) UpdateInvitation(owner, repo string, invitationID int, permissions string) (json.RawMessage, error)
```

Updates an invitation's permission level. Permissions: `"read"`, `"write"`, `"admin"`.

### DeleteInvitation

```go
func (g *GitHubCore) DeleteInvitation(owner, repo string, invitationID int) error
```

Deletes a pending collaborator invitation.

### AcceptInvitation

```go
func (g *GitHubCore) AcceptInvitation(invitationID int) error
```

Accepts a repository invitation for the authenticated user.

### DeclineInvitation

```go
func (g *GitHubCore) DeclineInvitation(invitationID int) error
```

Declines a repository invitation.

---

## Repositories — Collaborators

### ListCollaborators

```go
func (g *GitHubCore) ListCollaborators(owner, repo string) (json.RawMessage, error)
```

Lists all collaborators on a repository.

### CheckCollaborator

```go
func (g *GitHubCore) CheckCollaborator(owner, repo, username string) (json.RawMessage, error)
```

Checks if a user is a collaborator on a repository.

### AddCollaborator

```go
func (g *GitHubCore) AddCollaborator(owner, repo, username string, payload map[string]any) (json.RawMessage, error)
```

Adds a collaborator to a repository. Payload: `{"permission": "push"}`.

### RemoveCollaborator

```go
func (g *GitHubCore) RemoveCollaborator(owner, repo, username string) error
```

Removes a collaborator from a repository.

### GetCollaboratorPermission

```go
func (g *GitHubCore) GetCollaboratorPermission(owner, repo, username string) (json.RawMessage, error)
```

Gets a collaborator's permission level on a repository.

---

## Repositories — Metadata

### GetCommunityProfile

```go
func (g *GitHubCore) GetCommunityProfile(owner, repo string) (json.RawMessage, error)
```

Gets the community profile metrics (README, license, code of conduct, etc.).

### GetRepoREADME

```go
func (g *GitHubCore) GetRepoREADME(owner, repo string) (json.RawMessage, error)
```

Gets the repository's root README file.

### GetDirREADME

```go
func (g *GitHubCore) GetDirREADME(owner, repo, dir string) (json.RawMessage, error)
```

Gets the README file from a specific directory.

### ListRepoLanguages

```go
func (g *GitHubCore) ListRepoLanguages(owner, repo string) (json.RawMessage, error)
```

Lists languages detected in the repository with byte counts.

### ListRepoTeams

```go
func (g *GitHubCore) ListRepoTeams(owner, repo string) (json.RawMessage, error)
```

Lists teams with access to a repository.

---

## Search

### SearchCode

```go
func (g *GitHubCore) SearchCode(query string, perPage int) (json.RawMessage, error)
```

Searches code across GitHub. Use qualifiers like `repo:owner/name` to scope.

```go
results, err := gh.SearchCode("handleError repo:octocat/hello-world", 10)
```

### SearchCommits

```go
func (g *GitHubCore) SearchCommits(query string, perPage int) (json.RawMessage, error)
```

Searches commits by message, author, or date.

### SearchIssuesAndPRs

```go
func (g *GitHubCore) SearchIssuesAndPRs(query string, params map[string]string) (json.RawMessage, error)
```

Searches issues and pull requests. Params support `sort`, `order`, `per_page`.

### SearchRepositories

```go
func (g *GitHubCore) SearchRepositories(query string, params map[string]string) (json.RawMessage, error)
```

Searches repositories. Params support `sort`, `order`, `per_page`.

### SearchUsers

```go
func (g *GitHubCore) SearchUsers(query string, params map[string]string) (json.RawMessage, error)
```

Searches GitHub users and organizations.

### SearchLabels

```go
func (g *GitHubCore) SearchLabels(repoID int, query string) (json.RawMessage, error)
```

Searches labels within a repository by name.

### SearchTopics

```go
func (g *GitHubCore) SearchTopics(query string) (json.RawMessage, error)
```

Searches repository topics by keyword.

---

## Gists

### ListGists

```go
func (g *GitHubCore) ListGists(perPage int) (json.RawMessage, error)
```

Lists the authenticated user's gists.

### CreateGist

```go
func (g *GitHubCore) CreateGist(description string, files map[string]map[string]string, public bool) (json.RawMessage, error)
```

Creates a gist. Files map: `{"filename.txt": {"content": "file contents"}}`.

```go
gist, err := gh.CreateGist("My snippet", map[string]map[string]string{
    "hello.go": {"content": "package main\n\nfunc main() {}"},
}, true)
```

### UpdateGist

```go
func (g *GitHubCore) UpdateGist(gistID string, description string, files map[string]map[string]string) (json.RawMessage, error)
```

Updates a gist's description or file contents.

### DeleteGist

```go
func (g *GitHubCore) DeleteGist(gistID string) error
```

Deletes a gist.

### StarGist

```go
func (g *GitHubCore) StarGist(gistID string) error
```

Stars a gist.

### UnstarGist

```go
func (g *GitHubCore) UnstarGist(gistID string) error
```

Unstars a gist.

### ListGistComments

```go
func (g *GitHubCore) ListGistComments(gistID string) (json.RawMessage, error)
```

Lists comments on a gist.

### CreateGistComment

```go
func (g *GitHubCore) CreateGistComment(gistID, body string) (json.RawMessage, error)
```

Creates a comment on a gist.

### GetGistRevision

```go
func (g *GitHubCore) GetGistRevision(gistID, sha string) (json.RawMessage, error)
```

Gets a specific revision of a gist by commit SHA.

### ListGistCommits

```go
func (g *GitHubCore) ListGistCommits(gistID string) (json.RawMessage, error)
```

Lists the commit history of a gist.

### ListGistForks

```go
func (g *GitHubCore) ListGistForks(gistID string) (json.RawMessage, error)
```

Lists forks of a gist.

### ForkGist

```go
func (g *GitHubCore) ForkGist(gistID string) (json.RawMessage, error)
```

Forks a gist to the authenticated user's account.

### ListPublicGists

```go
func (g *GitHubCore) ListPublicGists() (json.RawMessage, error)
```

Lists recently updated public gists.

### ListStarredGists

```go
func (g *GitHubCore) ListStarredGists() (json.RawMessage, error)
```

Lists gists starred by the authenticated user.

### ListUserGists

```go
func (g *GitHubCore) ListUserGists(username string) (json.RawMessage, error)
```

Lists public gists for a specific user.

---

## Starring & Watching

### StarRepo

```go
func (g *GitHubCore) StarRepo(owner, repo string) error
```

Stars a repository.

### UnstarRepo

```go
func (g *GitHubCore) UnstarRepo(owner, repo string) error
```

Unstars a repository.

### ListStargazers

```go
func (g *GitHubCore) ListStargazers(owner, repo string) (json.RawMessage, error)
```

Lists users who have starred a repository.

### WatchRepo

```go
func (g *GitHubCore) WatchRepo(owner, repo string) (json.RawMessage, error)
```

Subscribes to (watches) a repository for notifications.

### UnwatchRepo

```go
func (g *GitHubCore) UnwatchRepo(owner, repo string) error
```

Unsubscribes from (unwatches) a repository.

### ListWatchers

```go
func (g *GitHubCore) ListWatchers(owner, repo string) (json.RawMessage, error)
```

Lists users watching a repository.

---

## Events & Feeds

### ListEvents

```go
func (g *GitHubCore) ListEvents(perPage int) (json.RawMessage, error)
```

Lists public events across GitHub.

### ListRepoEvents

```go
func (g *GitHubCore) ListRepoEvents(owner, repo string) (json.RawMessage, error)
```

Lists events for a specific repository.

### ListUserEvents

```go
func (g *GitHubCore) ListUserEvents(username string) (json.RawMessage, error)
```

Lists events performed by a user.

### GetFeeds

```go
func (g *GitHubCore) GetFeeds() (json.RawMessage, error)
```

Gets Atom feed URLs for the authenticated user's timeline, repositories, and organizations.

---

## Releases & Assets

### ListReleases

```go
func (g *GitHubCore) ListReleases(owner, repo string) (json.RawMessage, error)
```

Lists all releases for a repository.

### CreateRelease

```go
func (g *GitHubCore) CreateRelease(owner, repo, tagName, name, body string, draft, prerelease bool) (json.RawMessage, error)
```

Creates a new release.

```go
release, err := gh.CreateRelease("octocat", "hello-world",
    "v1.0.0", "Version 1.0.0", "First stable release!", false, false)
```

### UpdateRelease

```go
func (g *GitHubCore) UpdateRelease(owner, repo string, releaseID int, updates map[string]any) (json.RawMessage, error)
```

Updates a release's name, body, draft status, or prerelease flag.

### DeleteRelease

```go
func (g *GitHubCore) DeleteRelease(owner, repo string, releaseID int) error
```

Deletes a release.

### GetLatestRelease

```go
func (g *GitHubCore) GetLatestRelease(owner, repo string) (json.RawMessage, error)
```

Gets the latest published release (excludes drafts and prereleases).

### GetReleaseByTag

```go
func (g *GitHubCore) GetReleaseByTag(owner, repo, tag string) (json.RawMessage, error)
```

Gets a release by its tag name.

### GenerateReleaseNotes

```go
func (g *GitHubCore) GenerateReleaseNotes(owner, repo string, payload map[string]any) (json.RawMessage, error)
```

Auto-generates release notes content. Payload: `{"tag_name": "v1.0.0", "previous_tag_name": "v0.9.0"}`.

### UploadReleaseAsset

```go
func (g *GitHubCore) UploadReleaseAsset(owner, repo string, releaseID int, name string, data []byte, contentType string) (json.RawMessage, error)
```

Uploads a binary asset to a release.

### ListReleaseAssets

```go
func (g *GitHubCore) ListReleaseAssets(owner, repo string, releaseID int) (json.RawMessage, error)
```

Lists assets attached to a release.

### GetReleaseAsset

```go
func (g *GitHubCore) GetReleaseAsset(owner, repo string, assetID int) (json.RawMessage, error)
```

Gets a single release asset by ID.

### UpdateReleaseAsset

```go
func (g *GitHubCore) UpdateReleaseAsset(owner, repo string, assetID int, payload map[string]any) (json.RawMessage, error)
```

Updates a release asset's name or label. Payload: `{"name": "app-v1.0.0.zip", "label": "Stable build"}`.

### DeleteReleaseAsset

```go
func (g *GitHubCore) DeleteReleaseAsset(owner, repo string, assetID int) error
```

Deletes a release asset.

---

## Contents & Files

### GetFileContents

```go
func (g *GitHubCore) GetFileContents(owner, repo, path, ref string) (json.RawMessage, error)
```

Gets file contents at a path. Set `ref` to a branch, tag, or commit SHA. Returns base64-encoded content.

### CreateOrUpdateFileContents

```go
func (g *GitHubCore) CreateOrUpdateFileContents(owner, repo, path, message, contentB64, sha, branch string) (json.RawMessage, error)
```

Creates or updates a file. Content must be base64-encoded. For updates, provide the current file's SHA.

```go
import "encoding/base64"

content := base64.StdEncoding.EncodeToString([]byte("# Hello World\n"))
result, err := gh.CreateOrUpdateFileContents("octocat", "hello-world",
    "README.md", "Update README", content, "", "main")
```

### DeleteFileContents

```go
func (g *GitHubCore) DeleteFileContents(owner, repo, path, message, sha, branch string) error
```

Deletes a file from the repository. Requires the current file SHA.

### GetArchiveLink

```go
func (g *GitHubCore) GetArchiveLink(owner, repo, format, ref string) (string, error)
```

Gets a URL to download a repository archive. Format: `"tarball"` or `"zipball"`.

### ListRepositoryTree

```go
func (g *GitHubCore) ListRepositoryTree(owner, repo, sha string, recursive bool) (json.RawMessage, error)
```

Lists the Git tree for a commit. Set `recursive` to true to include all nested files.

---

## Branches, Tags & Commits

### ListBranches

```go
func (g *GitHubCore) ListBranches(owner, repo string) (json.RawMessage, error)
```

Lists all branches in a repository.

### GetBranch

```go
func (g *GitHubCore) GetBranch(owner, repo, branch string) (json.RawMessage, error)
```

Gets detailed information about a branch including its latest commit.

### RenameBranch

```go
func (g *GitHubCore) RenameBranch(owner, repo, branch, newName string) (json.RawMessage, error)
```

Renames a branch.

### ListTags

```go
func (g *GitHubCore) ListTags(owner, repo string) (json.RawMessage, error)
```

Lists all tags in a repository.

### ListCommits

```go
func (g *GitHubCore) ListCommits(owner, repo string, perPage int) (json.RawMessage, error)
```

Lists commits on the default branch.

### GetCommit

```go
func (g *GitHubCore) GetCommit(owner, repo, sha string) (json.RawMessage, error)
```

Gets a single commit by SHA, including diff stats and files.

### CompareCommits

```go
func (g *GitHubCore) CompareCommits(owner, repo, base, head string) (json.RawMessage, error)
```

Compares two commits, branches, or tags. Returns the diff, commits between, and file changes.

---

## Projects V2

Projects V2 use the GitHub GraphQL API internally.

### ListOrgProjectsV2

```go
func (g *GitHubCore) ListOrgProjectsV2(org string) (json.RawMessage, error)
```

Lists projects (v2) in an organization.

### GetProjectV2

```go
func (g *GitHubCore) GetProjectV2(projectID string) (json.RawMessage, error)
```

Gets a project by its GraphQL node ID.

### UpdateProjectV2

```go
func (g *GitHubCore) UpdateProjectV2(projectID string, payload map[string]any) (json.RawMessage, error)
```

Updates a project's title, description, or visibility. Payload: `{"title": "New Title", "public": true}`.

### DeleteProjectV2

```go
func (g *GitHubCore) DeleteProjectV2(projectID string) (json.RawMessage, error)
```

Deletes a project.

### CopyProjectV2

```go
func (g *GitHubCore) CopyProjectV2(projectID, ownerID, title string) (json.RawMessage, error)
```

Copies a project to a new owner with a new title.

### ListProjectV2Fields

```go
func (g *GitHubCore) ListProjectV2Fields(projectID string) (json.RawMessage, error)
```

Lists all fields (columns) in a project.

### ListProjectV2Items

```go
func (g *GitHubCore) ListProjectV2Items(projectID string) (json.RawMessage, error)
```

Lists all items in a project.

### AddProjectV2Item

```go
func (g *GitHubCore) AddProjectV2Item(projectID, contentID string) (json.RawMessage, error)
```

Adds an existing issue or PR to a project by its GraphQL node ID.

### CreateProjectV2DraftItem

```go
func (g *GitHubCore) CreateProjectV2DraftItem(projectID string, payload map[string]any) (json.RawMessage, error)
```

Creates a draft item (not linked to an issue or PR). Payload: `{"title": "Draft task", "body": "Details..."}`.

### UpdateProjectV2Item

```go
func (g *GitHubCore) UpdateProjectV2Item(projectID, itemID, fieldID string, value any) (json.RawMessage, error)
```

Updates a field value on a project item (e.g., changing status, priority, or custom fields).

### DeleteProjectV2Item

```go
func (g *GitHubCore) DeleteProjectV2Item(projectID, itemID string) (json.RawMessage, error)
```

Removes an item from a project.

### CreateProjectV2View

```go
func (g *GitHubCore) CreateProjectV2View(projectID string, payload map[string]any) (json.RawMessage, error)
```

Creates a new view (board, table, or roadmap) on a project.

---

## Interaction Limits

### Organization Interaction Limits

```go
func (g *GitHubCore) GetOrgInteractionLimits(org string) (json.RawMessage, error)
func (g *GitHubCore) SetOrgInteractionLimits(org string, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) RemoveOrgInteractionLimits(org string) error
```

Manage interaction limits for an entire organization. Payload: `{"limit": "collaborators_only", "expiry": "one_month"}`.

### Repository Interaction Limits

```go
func (g *GitHubCore) GetRepoInteractionLimits(owner, repo string) (json.RawMessage, error)
func (g *GitHubCore) SetRepoInteractionLimits(owner, repo string, payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) RemoveRepoInteractionLimits(owner, repo string) error
```

Manage interaction limits for a specific repository.

### User Interaction Limits

```go
func (g *GitHubCore) GetUserInteractionLimits() (json.RawMessage, error)
func (g *GitHubCore) SetUserInteractionLimits(payload map[string]any) (json.RawMessage, error)
func (g *GitHubCore) RemoveUserInteractionLimits() error
```

Manage interaction limits for the authenticated user's repos. Limits restrict who can comment, open issues, or create PRs (`"existing_users"`, `"contributors_only"`, `"collaborators_only"`).

---

## Utility

### ListEmojis

```go
func (g *GitHubCore) ListEmojis() (json.RawMessage, error)
```

Lists all GitHub-supported emoji shortcodes and their image URLs.

### CheckRateLimit

```go
func (g *GitHubCore) CheckRateLimit() (json.RawMessage, error)
```

Returns current rate limit status (remaining requests, reset time, used count).

### RenderMarkdown

```go
func (g *GitHubCore) RenderMarkdown(text, mode, context string) (string, error)
```

Renders Markdown text to HTML using GitHub's API. Mode: `"markdown"` (standard) or `"gfm"` (GitHub Flavored Markdown). Context is the repository for GFM autolinks (e.g., `"octocat/hello-world"`).

```go
html, err := gh.RenderMarkdown("Hello **world**! #42", "gfm", "octocat/hello-world")
// html = "<p>Hello <strong>world</strong>! <a href=\"...\">#42</a></p>"
```

---

## Unsupported Core Methods

These Core interface methods return `ErrNotSupported` because GitHub has no equivalent concept:

```go
func (g *GitHubCore) StartCall(_ string, _ bool) (*CallSession, error)
func (g *GitHubCore) JoinGroupCall(_ string) (*CallSession, error)
func (g *GitHubCore) EndCall(_ string) error
func (g *GitHubCore) SetCallMuted(_ string, _ bool) error
func (g *GitHubCore) AcceptCall(callID string) (*CallSession, error)
func (g *GitHubCore) DeclineCall(callID string) error
func (g *GitHubCore) MuteChat(chatID string, muted bool) error
func (g *GitHubCore) ArchiveChat(chatID string, archived bool) error
func (g *GitHubCore) MarkUnread(chatID string, unread bool) error
func (g *GitHubCore) UnpinAllMessages(chatID string) error
func (g *GitHubCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error)
```

All return `fmt.Errorf("%w: github does not support <operation>", ErrNotSupported)`.

---

## Dependencies

- Standard library `net/http` and `encoding/json` only
- No CGo required
- No external Go modules
