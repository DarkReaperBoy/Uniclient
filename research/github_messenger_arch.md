# GitHub Messenger Architecture

Complete design for using GitHub as a real-time messenger within uniclient.

---

## 1. Rate Limit Budget & Polling Strategy

### 1.1 GitHub API Rate Limits (Authenticated, PAT)

| Endpoint class | Limit | Window | Notes |
|---|---|---|---|
| **REST API** | 5,000 requests | per hour | Per-user token. Tracked via `X-RateLimit-Remaining` / `X-RateLimit-Reset` headers |
| **GraphQL API** | 5,000 points | per hour | Separate budget from REST. A simple query = 1 point; nested connections scale by `first` arg |
| **Search API** | 30 requests | per minute | Both REST and GraphQL search. Much stricter. Separate from main limit |
| **Notifications API** | 5,000/hr (shared) | per hour | **BUT: 304 Not Modified responses are FREE** (do not decrement remaining). This is the key exploit |
| **Secondary rate limit** | undocumented | ~100 req/min burst | Triggered by rapid creation/mutation. Returns 403 with `retry-after` header. Not based on quota, based on velocity |
| **Abuse detection** | undocumented | varies | Concurrent identical requests, rapid content creation. Also 403 |

### 1.2 Effective Budget Calculation

With 5,000 REST requests/hour:
- 1 hour = 3,600 seconds
- **Nominal capacity: ~1.39 requests/second sustained**
- Notifications polling with conditional requests (If-Modified-Since / ETag): **304s are free**
- This means the entire notification polling loop costs 0 when idle

**Realistic budget for a daily-driver messenger:**

| Activity | Requests/hr | Notes |
|---|---|---|
| Notification polling (10s interval) | ~0 (304s are free) | Only costs when there ARE new notifications (~5-20/hr active) |
| Fetching new comments from notifications | ~50 | 1 API call per notification with new content |
| Sending messages (issue comments) | ~30 | Active chat user, 1 req per message |
| Loading conversation history on open | ~10 | User opens a few chats, paginated |
| Profile lookups | ~10 | Cached aggressively |
| Search | ~5 | Occasional, from separate 30/min budget |
| Dialog list refresh | ~6 | Once per 10 min |
| **Total active use** | **~111** | **2.2% of budget** |

**Conclusion: GitHub's rate limits are extremely generous for messenger use.** The key insight is that 304 conditional requests are free, so we can poll notifications every 10 seconds indefinitely at zero cost. We have ~4,900 requests/hour for actual data fetching, which is far more than any human can consume chatting.

### 1.3 Polling Strategy (Already Implemented, Validated)

The current implementation in `github.go` is correct. The tiered approach:

```
ghNotifPoll   = 10s   -- notifications endpoint (304s are free)
ghPollActive  = 12s   -- actively viewing a conversation
ghPollRecent  = 30s   -- recent activity
ghPollIdle    = 2min  -- no activity in 30 min
ghPollBG      = 5min  -- background / not visible
```

**Enhancement needed:** The poll loop currently only processes Issue notifications. It should also handle:
- Discussion comment notifications (for group Discussions if we add them)
- PR comment notifications (for code-review chat threads)
- `X-Poll-Interval` header from GitHub: GitHub tells you how often to poll. The default is 60s, but it can vary. We should respect it as a floor but our 10s conditional-request strategy is already efficient because 304s are free.

### 1.4 GraphQL vs REST

Use **REST for everything except Discussions.** Discussions are only available via GraphQL (no REST endpoint). This is already the case in the current code. The GraphQL point budget (5,000/hr) is separate from REST, so using GraphQL for Discussions does not eat into our REST budget.

---

## 2. DM Architecture

### 2.1 Options Evaluated

| Option | Mechanism | Pros | Cons |
|---|---|---|---|
| **A: Private repo per pair** | Create a private repo, use issues as messages | True privacy, notifications work | Repo creation has secondary rate limits (~10/min), clutters account, expensive at scale |
| **B: Profile repo issues** | Issue on `{user}/{user}` repo, label `uniclient-dm` | No new repos needed, works with public profiles, discoverable | Requires user has a profile repo, public unless repo is private |
| **C: Gist comments** | Private gist per conversation | Simple, private, no repo needed | No notifications, gist comments have no reactions, hard to search, no labels |
| **D: Single inbox repo** | One private repo `{user}/uniclient-inbox`, one issue per peer | Single repo, private, organized | Still requires repo creation, but only one |

### 2.2 Chosen Architecture: Option B (Profile Repo) with Option D Fallback

**Primary: Profile repo issues** (already implemented in `github.go`)

This is the right choice because:
1. **Zero setup for recipients** -- anyone with a GitHub profile repo can receive DMs
2. **Notifications work natively** -- GitHub sends notifications for issue comments, which our poll loop already captures
3. **Reactions, labels, search all work** -- full GitHub issue feature set
4. **The `uniclient-dm` label** keeps DMs filterable and separate from real issues

**Current implementation details:**
- Chat ID format: `dm:{username}`
- Issue title: `Uniclient DM -- {your_username}`
- Label: `uniclient-dm`
- DM issue location is cached in session (`dmIssues` map, persisted to `auth/github_session.json`)

**Fallback for users without profile repos:** If `{user}/{user}` repo doesn't exist, fall back to creating an issue on our own `{self}/uniclient-inbox` repo (create it once, private). The peer gets an @-mention notification. This covers the case where the recipient hasn't set up a profile repo.

**Privacy concern:** Profile repos are public by default. DM content is visible. Options for privacy:
1. **Encrypt message bodies** -- prefix ciphertext with `@@` so the UI can detect it. Use NaCl box (x25519) with key exchange via a pinned "public key" issue or GitHub user key (`/users/{user}/keys`). This is noted in the existing code comments as "E2EE-ready."
2. **Private profile repos** -- users can make their profile repo private, which hides issues from non-collaborators. Both parties would need to be collaborators.
3. **Pragmatic stance:** For v1, plaintext DMs are fine (GitHub already sends emails for issue comments -- it's no less private than email). E2EE is a later enhancement.

### 2.3 DM Discovery

When loading dialogs, the core should:
1. Check `GET /notifications` for any issue with `uniclient-dm` label in the title pattern
2. Query `GET /search/issues?q=label:uniclient-dm+involves:{username}` to find all DM threads
3. Cache results in `dmIssues` map for fast lookup

This is largely already implemented in `GetDialogs`.

---

## 3. Group Chat Architecture

### 3.1 Current Design (Already Implemented)

**Group = Repository. Channel = Issue. Members = Collaborators.**

- Chat ID: `repo:{owner}/{repo}` for the group, `issue:{owner}/{repo}/{number}` for a channel
- Default channel: pinned "General" issue (#1), labeled `uniclient-group`
- Creating a channel = creating an issue
- Adding members = adding collaborators with `write` permission
- The repo's `uniclient-group` topic tag enables discovery

### 3.2 Evaluation: Issues vs Discussions for Channels

| Feature | Issues | Discussions |
|---|---|---|
| REST API | Full support | **No REST API** -- GraphQL only |
| Notifications | Native, automatic | Native, automatic |
| Reactions | Yes (8 fixed emojis) | Yes (8 fixed emojis) |
| Threading | Via replies (flat comment list) | **Native threaded replies** |
| Labels | Yes | **Categories** (similar concept) |
| Pinning | Via `pin` API | Via GraphQL mutation |
| Search | Full-text via search API | Full-text via GraphQL |
| Edit/Delete | Full CRUD | Full CRUD via GraphQL |
| Real-time updates | Via notifications | Via notifications |
| File attachments | Drag-and-drop in body/comments | Drag-and-drop in body/comments |

**Verdict: Keep Issues as the primary channel mechanism.**

Reasoning:
1. Issues have full REST API support; Discussions require GraphQL for everything
2. Issues are simpler to reason about: one flat comment list = one chat thread
3. The existing implementation is already built around issues
4. Discussions could be offered as an optional "threaded mode" later

### 3.3 Group Features Mapping

| Messenger concept | GitHub implementation |
|---|---|
| Group | Repository |
| Channel (within group) | Issue (labeled `uniclient-group`) |
| Message | Issue comment |
| Thread/Reply | Issue comment with `> quoted text` prefix |
| Pin message | Lock comment (or local pin tracking) |
| Kick/Ban member | Remove collaborator / block from repo |
| Admin | Collaborator with `admin` permission |
| Group avatar | Repo owner's avatar (or custom via repo social preview) |
| Group description | Repo description |
| Invite link | Repo URL or collaboration invite link |
| Mute | Unsubscribe from repo notifications (`DELETE /repos/{owner}/{repo}/subscription`) |

---

## 4. Real-Time Update Strategy

### 4.1 Current Implementation (Correct)

The core already implements the right strategy:

1. **Poll `/notifications`** every 10 seconds with `If-Modified-Since` / `ETag` headers
2. 304 responses are free (do not count against rate limit)
3. When a notification arrives with new content, fetch the latest comment
4. Fire `UpdateNewMessage` to the update handler
5. Budget-aware: triple poll interval when rate limit is low

### 4.2 Enhancements Needed

**a) Per-thread polling for active conversations:**
The `threadETags` map exists but isn't being used in the poll loop. When a user has a conversation open, we should:
- Poll that specific issue's comments endpoint every `ghPollActive` (12s) with ETag
- This catches comments faster than waiting for the notification to propagate
- Only poll the 1-2 actively viewed conversations this way

**b) Webhook option (future):**
For users running uniclient on a server or with a public IP, we could offer webhook-based real-time updates:
- Create a webhook on repos we're watching
- Receive instant push notifications for issue comments
- This eliminates all polling latency
- Not practical for desktop-only users behind NAT, so it stays optional

**c) Notification thread subscription:**
When a DM thread is created, auto-subscribe to it via `PUT /notifications/threads/{thread_id}/subscription`. This ensures we get notifications for all new comments.

### 4.3 Latency Expectations

| Scenario | Latency | Mechanism |
|---|---|---|
| Active conversation open | 12-24s | Per-thread ETag polling |
| Background (app open) | 10-20s | Notification polling |
| Idle (30+ min inactive) | 2-5 min | Slowed polling |
| With webhooks (future) | <2s | HTTP push |

This is not instant messaging, but it's comparable to email-speed chat. For GitHub's use case (developer collaboration), this is acceptable. The UI should show a subtle indicator that this platform has higher latency than Telegram/Matrix.

---

## 5. Core Interface Mapping

### 5.1 Concept Mapping

| Core concept | GitHub implementation |
|---|---|
| `Dialog` (DM) | Issue on profile repo with `uniclient-dm` label. ID: `dm:{username}` |
| `Dialog` (Group) | Repository with `uniclient-group` topic. ID: `repo:{owner}/{repo}` |
| `Dialog` (Channel/Topic) | Issue within a group repo. ID: `issue:{owner}/{repo}/{number}` |
| `Message` | Issue comment. ID: comment ID (numeric string) |
| `User` | GitHub user. ID: username (login) |
| `Reaction` | Issue comment reaction (8 fixed emojis: +1, -1, laugh, hooray, confused, heart, rocket, eyes) |
| `FileRef` | Markdown image/link in comment body (GitHub CDN URLs) |
| `Folder` | Starred repos list |
| `ReadState` | Local tracking (GitHub has no read receipts for issue comments) |
| `Call` | Not supported |
| `Typing` | Not supported |
| `Sticker` | Emoji shortcodes in comment body (partial -- no custom stickers) |
| `Poll` | Markdown poll in comment body (rendered, but no native vote tracking) |

### 5.2 Chat ID Format

Already defined and correct:
```
dm:{username}              -- DM conversation with a user
repo:{owner}/{repo}        -- group chat (repository)
issue:{owner}/{repo}/{num} -- channel within a group (issue)
```

### 5.3 Core Interface Method Status

| Method | Status | Notes |
|---|---|---|
| `Name()` | Done | Returns "github" |
| `Capabilities()` | Done | Should be audited (see below) |
| `Authenticate()` | Done | PAT token auth |
| `Logout()` | Done | Clears state |
| `GetDialogs()` | Done | Lists DMs + groups |
| `CreateGroup()` | Done | Creates repo |
| `CreateChannel()` | Done | Creates repo (should this create an issue instead?) |
| `CreateTopic()` | Done | Creates issue in repo |
| `GetFolders()` | Done | Returns starred repos |
| `CreateFolder()` | Returns ErrNotSupported | Correct |
| `SendMessage()` | Done | Routes by chat ID prefix |
| `GetMessages()` | Done | Fetches issue comments |
| `EditMessage()` | Done | Edits comment |
| `DeleteMessage()` | Done | Deletes comment |
| `ReplyToMessage()` | Done | Comment with quote prefix |
| `ForwardMessage()` | Done | Cross-posts comment text |
| `ReactToMessage()` | Done | GitHub reactions |
| `PinMessage()` | Done | Local pin tracking |
| `UnpinMessage()` | Done | Local pin tracking |
| `MarkAsRead()` | Done | Local tracking |
| `GetReadState()` | Done | Local tracking |
| `UploadFile()` | Done | Inline in comment body |
| `DownloadFile()` | Done | HTTP download |
| `SendImageBase64()` | Done | Base64 decode + upload to comment |
| `StartCall()` | Returns ErrNotSupported | Correct -- GitHub has no calls |
| `JoinGroupCall()` | Returns ErrNotSupported | Correct |
| `EndCall()` | Returns ErrNotSupported | Correct |
| `SetCallMuted()` | Returns ErrNotSupported | Correct |
| `GetProfile()` | Done | Fetches user info |
| `OnUpdate()` | Done | Registers handler |
| `Close()` | Done | Cancels context, saves session |
| `GetChatInfo()` | Done | |
| `EditChatTitle()` | Done | Renames issue/repo |
| `EditChatDescription()` | Done | Updates repo description |
| `LeaveChat()` | Done | Removes self as collaborator |
| `GetInviteLink()` | Done | Returns repo URL |
| `AddMembers()` | Done | Adds collaborators |
| `RemoveMember()` | Done | Removes collaborator |
| `BanMember()` | Done | Blocks user from repo |
| `UnbanMember()` | Done | Unblocks |
| `GetMembers()` | Done | Lists collaborators |
| `SetAdmin()` | Done | Sets collaborator permission |
| `GetContacts()` | Done | Following list |
| `AddContact()` | Done | Follow user |
| `DeleteContact()` | Done | Unfollow user |
| `BlockUser()` | Done | GitHub user block |
| `UnblockUser()` | Done | GitHub user unblock |
| `GetBlockedUsers()` | Done | Lists blocked users |
| `SearchMessages()` | Done | Search API |
| `SearchGlobal()` | Done | Search API |
| `SendTyping()` | Returns nil (no-op) | Correct -- no typing indicator |
| `CreatePoll()` | Done | Markdown poll in comment |
| `VotePoll()` | Returns ErrNotSupported | Correct -- no native vote tracking |
| `SendSticker()` | Done | Emoji shortcode in comment |
| `GetSessions()` | Done | Returns current PAT session |
| `TerminateSession()` | Returns ErrNotSupported | Correct |
| `MuteChat()` | Returns ErrNotSupported | **Should implement** -- use repo subscription API |
| `ArchiveChat()` | Returns ErrNotSupported | **Should implement** -- archive the repo |
| `MarkUnread()` | Returns ErrNotSupported | **Should implement** -- local state |
| `UnpinAllMessages()` | Returns ErrNotSupported | **Should implement** -- clear local pin map |
| `AcceptCall()` | Returns ErrNotSupported | Correct |
| `DeclineCall()` | Returns ErrNotSupported | Correct |
| `SendLocation()` | Returns ErrNotSupported | **Could implement** -- Google Maps link in comment |

---

## 6. Method Audit: Platform-Specific Methods

### 6.1 Naming Convention Analysis

Compared against Telegram, Bale, and IRC cores. The standard pattern is:
- Core interface methods: exact match (all cores use same signatures)
- Platform-specific methods: `{Verb}{Noun}` in PascalCase, parameters use platform-native types
- No `owner, repo` splitting when the chatID already encodes it -- the unified methods parse chatID internally

**Problem:** The 228 GitHub-specific methods (beyond the 55 Core methods) all take raw `(owner, repo string, ...)` parameters. This is inconsistent with how other cores work -- they take `chatID string` and parse internally. However, these are platform-specific extras, not Core methods, so this is acceptable. The GUI will call Core methods; power users / library consumers use the extras directly.

### 6.2 Methods to Remove (Still Useless for Messenger)

These methods add no value to a messenger and should be pruned:

| Method | Reason |
|---|---|
| `GetCommunityProfile` | Repo health score -- not messaging |
| `GetRepoREADME` | Code browsing, not messaging |
| `GetDirREADME` | Code browsing, not messaging |
| `ListRepoLanguages` | Code stats, not messaging |
| `GetArchiveLink` | Download repo archive -- not messaging |
| `ListRepositoryTree` | Git tree browsing -- not messaging |
| `CompareCommits` | Git diff -- not messaging |
| `GetFileContents` | File read -- not messaging |
| `CreateOrUpdateFileContents` | File write -- not messaging |
| `DeleteFileContents` | File delete -- not messaging |
| `ListBranches` | Git branching -- not messaging |
| `GetBranch` | Git branching -- not messaging |
| `RenameBranch` | Git branching -- not messaging |
| `ListTags` | Git tagging -- not messaging |
| `ListCommits` | Git history -- not messaging |
| `GetCommit` | Git history -- not messaging |
| `ListPRsForCommit` | Git cross-ref -- not messaging |
| `ListPRCommits` | PR internals -- not messaging |
| `ListPRFiles` | PR internals -- not messaging |
| `CheckPRMerged` | PR internals -- not messaging |
| `UpdatePRBranch` | PR internals -- not messaging |
| `GetPRReview` | Could argue this is review chat, but it's metadata not messages |
| `UpdatePRReview` | Metadata |
| `DeletePendingPRReview` | Metadata |
| `ListPRReviewComments` | **Keep** -- these ARE messages in code review |
| `GetGistRevision` | Gist versioning -- not messaging |
| `ListGistCommits` | Gist versioning -- not messaging |
| `ListGistForks` | Gist social -- marginal |
| `ForkGist` | Gist forking -- not messaging |
| `ListPublicGists` | Discovery -- marginal |
| `ListStarredGists` | Discovery -- marginal |
| `ListUserGists` | Discovery -- marginal |
| `SetEmailVisibility` | Account settings -- not messaging |
| `ListPublicEmails` | Account settings -- not messaging |
| `SearchCode` | Code search -- not messaging |
| `SearchCommits` | Code search -- not messaging |
| `SearchLabels` | Label search -- marginal |
| `SearchTopics` | Topic search -- marginal |
| `ListEmojis` | Could cache once at startup instead |
| `RenderMarkdown` | Could be done client-side |
| `GetCollaboratorPermission` | Admin detail -- keep only if needed by SetAdmin |
| `CheckCollaborator` | Redundant with GetMembers |
| `ListForks` | Code social -- not messaging |
| `GetRepoActivity` | Repo stats -- not messaging |
| `CheckAssignable` | Issue triage -- not messaging |
| `ListRepoAssignees` | Issue triage -- not messaging |
| `GetParentIssue` | Issue hierarchy -- marginal |
| `RemoveSubIssue` | Issue hierarchy -- marginal |
| `ReprioritizeSubIssue` | Issue hierarchy -- marginal |
| `ListBlockingDependencies` | Issue dependencies -- not messaging |
| `AddBlockingDependency` | Issue dependencies -- not messaging |
| `RemoveBlockingDependency` | Issue dependencies -- not messaging |
| `ListMilestoneLabels` | Milestone detail -- not messaging |
| `ListRepoTeams` | Repo admin -- marginal |
| `GetLatestRelease` | Release browsing -- not messaging |
| `GetReleaseByTag` | Release browsing -- not messaging |
| `GenerateReleaseNotes` | Release automation -- not messaging |
| `GetReleaseAsset` | Release browsing -- not messaging |
| `UpdateReleaseAsset` | Release management -- not messaging |
| `DeleteReleaseAsset` | Release management -- not messaging |
| `CheckPublicMembership` | Org detail -- marginal |
| `PublicizeMembership` | Org settings -- not messaging |
| `ConcealMembership` | Org settings -- not messaging |
| `CheckTeamRepo` | Team admin -- marginal |
| `ListChildTeams` | Team hierarchy -- marginal |

**Total: ~55 methods to remove.** This would bring the count from 282 down to ~227.

### 6.3 Methods to Keep (Messaging-Relevant)

These platform-specific methods ARE useful for a messenger and should stay:

**Issue/Channel Management:**
- `LockIssue` / `UnlockIssue` -- equivalent to closing/archiving a channel
- `ListIssueEvents` / `GetIssueTimeline` -- chat history metadata (who joined, who left)
- `ListSubIssues` / `AddSubIssue` -- thread hierarchy
- `ListLabels` / `CreateLabel` / `DeleteLabel` / `AddLabelsToIssue` / `RemoveLabel` / `SetLabels` -- channel tagging/categorization
- `ListMilestones` / `CreateMilestone` / `UpdateMilestone` / `DeleteMilestone` -- can serve as channel groups or sprints in project-chat context
- `AddIssueAssignees` / `RemoveIssueAssignees` -- assign responsibility in a thread
- `ListAuthenticatedUserIssues` / `ListOrgIssues` -- cross-repo thread discovery

**PR as Code Review Chat:**
- `ListPullRequests` / `CreatePullRequest` / `GetPullRequest` / `UpdatePullRequest` / `MergePullRequest` -- PR lifecycle
- `ListPRComments` / `CreatePRComment` / `CreatePRCommentReply` -- code review conversation (these ARE messages)
- `ListPRReviews` / `CreatePRReview` / `SubmitPRReview` / `DismissPRReview` -- review workflow
- `RequestReviewers` / `GetRequestedReviewers` / `RemoveRequestedReviewers` -- mention/ping

**Notifications (Core to real-time):**
- `ListNotifications` / `MarkAllNotificationsRead` / `GetNotificationThread` / `MarkThreadRead` / `SubscribeThread` / `UnsubscribeThread`

**Repository/Group Management:**
- `DeleteRepo` / `ForkRepo` / `TransferRepo` -- group lifecycle
- `GetRepoTopics` / `SetRepoTopics` -- group tagging
- `ListContributors` -- member discovery
- `ListInvitations` / `UpdateInvitation` / `DeleteInvitation` / `AcceptInvitation` / `DeclineInvitation` -- invitation management
- `AddCollaborator` / `RemoveCollaborator` / `ListCollaborators` -- member management

**Gists (Pastebins / Quick Shares):**
- `ListGists` / `CreateGist` / `UpdateGist` / `DeleteGist` -- share code snippets
- `StarGist` / `UnstarGist` -- bookmark
- `ListGistComments` / `CreateGistComment` -- gist conversations

**Releases (Announcements):**
- `ListReleases` / `CreateRelease` / `UpdateRelease` / `DeleteRelease` -- project announcements
- `UploadReleaseAsset` / `ListReleaseAssets` -- file distribution

**Commit Comments (Code Chat):**
- `ListCommitComments` / `CreateCommitComment` / `UpdateCommitComment` / `DeleteCommitComment` -- conversations on specific commits

**Org/Team (Group Hierarchy):**
- `ListOrgs` / `GetOrg` -- org discovery
- `ListOrgMembers` -- member lists
- `ListOrgTeams` / `CreateTeam` / `UpdateTeam` / `DeleteTeam` -- sub-groups
- `AddTeamMember` / `RemoveTeamMember` -- team membership
- `ListTeamRepos` / `AddTeamRepo` / `RemoveTeamRepo` -- team-repo associations
- `ListTeamInvitations` -- team invite management
- `ListOrgBlockedUsers` / `BlockOrgUser` / `UnblockOrgUser` -- org moderation
- `ListOrgInvitations` / `CreateOrgInvitation` / `CancelOrgInvitation` / `ListInvitationTeams` / `ListFailedInvitations` -- org invite management
- `ListOrgRoles` / `GetOrgRole` / `AssignTeamRole` / `RemoveTeamRole` / `AssignUserRole` / `RemoveUserRole` / `ListTeamsForRole` / `ListUsersForRole` -- RBAC
- `ListOutsideCollaborators` / `ConvertToOutsideCollaborator` / `RemoveOutsideCollaborator` -- external member management
- `GetOrgMembership` / `SetOrgMembership` / `RemoveOrgMembership` / `ListUserOrgMemberships` / `GetUserOrgMembership` -- membership management
- `ListPublicMembers` -- member visibility

**Social/Stars/Watch:**
- `ListStargazers` / `StarRepo` / `UnstarRepo` -- bookmarking groups
- `ListWatchers` / `WatchRepo` / `UnwatchRepo` -- subscribe/unsubscribe
- `ListEvents` / `ListRepoEvents` / `ListUserEvents` -- activity feed
- `GetFeeds` -- aggregated feed

**Discussions (Threaded Chat):**
- `ListDiscussions` / `CreateDiscussion` / `UpdateDiscussion` / `DeleteDiscussion` -- threaded conversations
- `AddDiscussionComment` / `UpdateDiscussionComment` / `DeleteDiscussionComment` -- discussion messages
- `MarkDiscussionCommentAsAnswer` -- mark solution

**Reactions (All Keep):**
- All 18 reaction methods (commit comment, issue comment, issue, PR comment, release) -- reactions ARE messaging

**Profile:**
- `UpdateProfile` -- edit bio/name
- `ListEmails` / `AddEmail` / `DeleteEmail` -- contact info
- `ListSocialAccounts` / `AddSocialAccount` / `DeleteSocialAccount` -- social links
- `GetUserHovercard` -- rich profile preview

**Search:**
- `SearchIssuesAndPRs` -- find conversations
- `SearchRepositories` -- find groups
- `SearchUsers` -- find people

**Rate Limit:**
- `CheckRateLimit` -- budget monitoring

**Interaction Limits:**
- All 9 interaction limit methods -- moderation

**Projects V2 (Kanban):**
- All project methods -- can serve as task boards within groups

### 6.4 Methods to Rename

No renames needed for the platform-specific methods. They follow a consistent `{Verb}{Noun}` pattern matching the GitHub API structure. The Core interface methods already have the exact correct signatures.

### 6.5 Capabilities() Audit

Current capabilities should be:
```go
[]string{
    CapText,           // issue comments
    CapChannels,       // issues as channels (but NOTE: CreateChannel currently creates a repo, not an issue)
    CapTopics,         // issues within repos
    CapThreads,        // reply quoting
    CapReactions,      // GitHub reactions (8 fixed)
    CapSearch,         // GitHub search API
    CapAdmin,          // collaborator permissions
    CapFolders,        // starred repos
    CapFileTransfer,   // file uploads in comments
    CapBase64Image,    // image upload
    CapBlocking,       // user blocking
}
```

Should NOT include: `CapCalls`, `CapGroupCalls`, `CapReadReceipts`, `CapTyping`, `CapPolls` (no native vote tracking), `CapStickers`, `CapE2EE`, `CapPresence`, `CapVoice`, `CapLocation`, `CapScheduled`, `CapSessions`, `CapSpaces`.

---

## 7. Issues to Fix

### 7.1 `CreateChannel()` Bug

Currently, `CreateChannel()` creates a new repository, which is identical to `CreateGroup()`. In the Core interface, `CreateChannel` is supposed to create a channel WITHIN a group. For GitHub, this should create a new issue in an existing repo (same as `CreateTopic`).

**Fix:** `CreateChannel()` should take the `name` as `"{owner}/{repo}:{channel_name}"` or be documented that for GitHub, channels are created via `CreateTopic()` and `CreateChannel()` is an alias that creates a standalone repo-as-channel.

### 7.2 `MuteChat()` Should Work

GitHub has a repo subscription API:
- `DELETE /repos/{owner}/{repo}/subscription` -- unwatch (mute)
- `PUT /repos/{owner}/{repo}/subscription` with `{"ignored": true}` -- explicitly mute

This should be wired up instead of returning `ErrNotSupported`.

### 7.3 `ArchiveChat()` Should Work

GitHub has a repo archive API:
- `PATCH /repos/{owner}/{repo}` with `{"archived": true}` -- archive repo
- For issues: `PATCH /repos/{owner}/{repo}/issues/{number}` with `{"state": "closed"}` -- close issue (archive channel)

### 7.4 `MarkUnread()` Should Work

This can be local state only (same as pinned messages). Store in session.

### 7.5 `UnpinAllMessages()` Should Work

Clear the local `pinned` map for the chat. Already has the data structure.

### 7.6 `SendLocation()` Could Work

Send a Google Maps link: `https://www.google.com/maps?q={lat},{lon}` as a comment. Simple and useful.

---

## 8. New Methods Needed

### 8.1 For Messenger Functionality

| Method | Purpose |
|---|---|
| `EnsureProfileRepo()` | Create `{user}/{user}` repo if it doesn't exist (needed to receive DMs) |
| `EnsureInboxRepo()` | Create `{user}/uniclient-inbox` private repo (fallback for DMs to users without profile repos) |
| `GetDMThread(peerUsername string)` | Find or create the DM issue for a peer (consolidates DM discovery logic) |
| `PollThread(chatID string)` | Explicitly poll a single thread for updates (for active conversation view) |
| `SetNotificationSubscription(chatID string, subscribed bool)` | Subscribe/unsubscribe from a thread's notifications |

### 8.2 Not Needed

These were considered but are unnecessary:
- Webhook management -- desktop client can't receive webhooks
- GitHub Actions integration -- too far from messaging
- GitHub Packages -- not messaging
- Code Scanning / Dependabot -- not messaging

---

## 9. Summary

### Architecture at a Glance

```
DM:     Issue on {peer}/{peer} profile repo, labeled "uniclient-dm"
Group:  Repository with "uniclient-group" topic
Channel: Issue within a group repo, labeled "uniclient-group"  
Message: Issue comment
React:  GitHub reaction API (8 fixed emojis)
File:   Markdown image/link in comment body
Real-time: Poll /notifications every 10s (304s are free)
Auth:   Personal Access Token (PAT)
```

### Rate Limit Safety

- 5,000 req/hr is enormous for chat use (~111 req/hr at heavy usage = 2.2% of budget)
- Conditional notification polling is FREE
- Current `ghRateLimiter` with read/write pacing is correct
- Budget monitoring via `X-RateLimit-*` headers is correct
- Exponential backoff on 429/secondary-403 is correct

### What Works Well Already

- DM architecture (profile repo issues)
- Group architecture (repos with issues as channels)
- Notification polling with conditional requests
- Rate limiter with budget awareness
- Session persistence for DM/group caches
- All 55 Core interface methods are implemented

### What Needs Work

1. Fix `CreateChannel()` to not duplicate `CreateGroup()`
2. Implement `MuteChat()` via repo subscription API
3. Implement `ArchiveChat()` via repo archive / issue close
4. Implement `MarkUnread()` via local state
5. Implement `UnpinAllMessages()` via local state
6. Implement `SendLocation()` via Google Maps link
7. Add per-thread ETag polling for active conversations
8. Add `EnsureProfileRepo()` and `EnsureInboxRepo()` helper methods
9. Prune ~55 code-browsing methods that add no messenger value
10. Audit `Capabilities()` return value
