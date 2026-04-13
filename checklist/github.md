## Phase 10: GitHub — DONE (core complete, all extended methods implemented)

246 exported methods, ~4,254 lines. All extended methods implemented (not yet tested). REST API via net/http + GraphQL for Discussions.

### Core Interface (55/55)

- [x] Name
- [x] Capabilities
- [x] Authenticate (Personal Access Token)
- [x] Logout
- [x] GetDialogs (DM threads + group repos)
- [x] CreateGroup (create repo + add collaborators)
- [x] CreateChannel (create repo)
- [x] CreateTopic (create issue within repo)
- [x] GetFolders (starred repos)
- [x] CreateFolder — returns ErrNotSupported
- [x] SendMessage (DM/issue comment/group message)
- [x] GetMessages (with pagination)
- [x] EditMessage (edit comment)
- [x] DeleteMessage (delete comment)
- [x] ReplyToMessage (quoted reply)
- [x] ForwardMessage (forwarded attribution)
- [x] ReactToMessage (GitHub reaction emoji)
- [x] PinMessage (local cache)
- [x] UnpinMessage (local cache)
- [x] MarkAsRead
- [x] GetReadState
- [x] UploadFile (repo file upload, max 25MB)
- [x] DownloadFile
- [x] SendImageBase64 (markdown details block)
- [x] StartCall — returns ErrNotSupported
- [x] JoinGroupCall — returns ErrNotSupported
- [x] EndCall — returns ErrNotSupported
- [x] SetCallMuted — returns ErrNotSupported
- [x] GetProfile
- [x] OnUpdate (polling loop)
- [x] Close
- [x] GetChatInfo
- [x] EditChatTitle (rename repo)
- [x] EditChatDescription (update repo description)
- [x] LeaveChat (unwatch repo)
- [x] GetInviteLink (repo URL)
- [x] AddMembers (add collaborators)
- [x] RemoveMember (remove collaborator)
- [x] BanMember (remove + block)
- [x] UnbanMember (unblock)
- [x] GetMembers (list collaborators)
- [x] SetAdmin (collaborator permission)
- [x] GetContacts (following list)
- [x] AddContact (follow user)
- [x] DeleteContact (unfollow)
- [x] BlockUser
- [x] UnblockUser
- [x] GetBlockedUsers
- [x] SearchMessages (search issues)
- [x] SearchGlobal (search repos)
- [x] SendTyping — no-op
- [x] CreatePoll (markdown poll with reaction voting)
- [x] VotePoll (react with emoji)
- [x] SendSticker (emoji message)
- [x] GetSessions (current PAT session)
- [x] TerminateSession — returns ErrNotSupported

---

### Extended Methods (190 — all implemented, not yet tested)

#### Issues Extended (6)
- [x] LockIssue
- [x] UnlockIssue
- [x] ListIssueEvents
- [x] GetIssueTimeline
- [x] ListSubIssues
- [x] AddSubIssue

#### Labels (7)
- [x] ListLabels
- [x] CreateLabel
- [x] UpdateLabel
- [x] DeleteLabel
- [x] AddLabelsToIssue
- [x] RemoveLabel
- [x] SetLabels

#### Milestones (4)
- [x] ListMilestones
- [x] CreateMilestone
- [x] UpdateMilestone
- [x] DeleteMilestone

#### Pull Requests (12)
- [x] ListPullRequests
- [x] CreatePullRequest
- [x] GetPullRequest
- [x] UpdatePullRequest
- [x] MergePullRequest
- [x] ListPRComments
- [x] CreatePRComment
- [x] ListPRReviews
- [x] CreatePRReview
- [x] SubmitPRReview
- [x] DismissPRReview
- [x] RequestReviewers

#### Notifications (6)
- [x] ListNotifications
- [x] MarkAllNotificationsRead
- [x] GetNotificationThread
- [x] MarkThreadRead
- [x] SubscribeThread
- [x] UnsubscribeThread

#### Repository Extended (7)
- [x] DeleteRepo
- [x] ForkRepo
- [x] TransferRepo
- [x] GetRepoTopics
- [x] SetRepoTopics
- [x] ListContributors
- [x] GetRepoActivity

#### Repository Invitations (5)
- [x] ListInvitations
- [x] UpdateInvitation
- [x] DeleteInvitation
- [x] AcceptInvitation
- [x] DeclineInvitation

#### Gists (8)
- [x] ListGists
- [x] CreateGist
- [x] UpdateGist
- [x] DeleteGist
- [x] StarGist
- [x] UnstarGist
- [x] ListGistComments
- [x] CreateGistComment

#### Releases (6)
- [x] ListReleases
- [x] CreateRelease
- [x] UpdateRelease
- [x] DeleteRelease
- [x] UploadReleaseAsset
- [x] ListReleaseAssets

#### Commit Comments (4)
- [x] ListCommitComments
- [x] CreateCommitComment
- [x] UpdateCommitComment
- [x] DeleteCommitComment

#### Organizations (9)
- [x] ListOrgs
- [x] GetOrg
- [x] ListOrgMembers
- [x] ListOrgTeams
- [x] CreateTeam
- [x] UpdateTeam
- [x] DeleteTeam
- [x] AddTeamMember
- [x] RemoveTeamMember

#### Webhooks (4)
- [x] CreateWebhook
- [x] UpdateWebhook
- [x] DeleteWebhook
- [x] PingWebhook

#### Starring/Watching (6)
- [x] ListStargazers
- [x] StarRepo
- [x] UnstarRepo
- [x] ListWatchers
- [x] WatchRepo
- [x] UnwatchRepo

#### Events (4)
- [x] ListEvents
- [x] ListRepoEvents
- [x] ListUserEvents
- [x] GetFeeds

#### Discussions (GraphQL) (8)
- [x] ListDiscussions
- [x] CreateDiscussion
- [x] UpdateDiscussion
- [x] DeleteDiscussion
- [x] AddDiscussionComment
- [x] UpdateDiscussionComment
- [x] DeleteDiscussionComment
- [x] MarkDiscussionCommentAsAnswer

#### User Extended (8)
- [x] UpdateProfile
- [x] ListEmails
- [x] AddEmail
- [x] DeleteEmail
- [x] ListSocialAccounts
- [x] AddSocialAccount
- [x] DeleteSocialAccount
- [x] GetUserHovercard

#### Search Extended (4)
- [x] SearchCode
- [x] SearchCommits
- [x] SearchLabels
- [x] SearchTopics

#### Utility (3)
- [x] ListEmojis
- [x] CheckRateLimit
- [x] RenderMarkdown

#### Branches & Branch Protection (6)
- [x] ListBranches
- [x] GetBranch
- [x] CreateBranchProtection
- [x] UpdateBranchProtection
- [x] DeleteBranchProtection
- [x] RenameBranch

#### Git References / Tags (6)
- [x] ListTags
- [x] CreateTag
- [x] DeleteTag
- [x] ListRefs
- [x] CreateRef
- [x] DeleteRef

#### Commits (3)
- [x] ListCommits
- [x] GetCommit
- [x] CompareCommits

#### Actions / Workflows (10)
- [x] ListWorkflows
- [x] ListWorkflowRuns
- [x] GetWorkflowRun
- [x] ReRunWorkflow
- [x] CancelWorkflowRun
- [x] ListWorkflowRunArtifacts
- [x] DownloadArtifact
- [x] ListRepositorySecrets
- [x] CreateOrUpdateSecret
- [x] DeleteSecret

#### Checks / Statuses (6)
- [x] ListCheckRuns
- [x] GetCheckRun
- [x] ListCheckSuites
- [x] CreateCheckRun
- [x] ListCommitStatuses
- [x] CreateCommitStatus

#### Projects (7)
- [x] ListProjects
- [x] CreateProject
- [x] UpdateProject
- [x] DeleteProject
- [x] ListProjectColumns
- [x] CreateProjectCard
- [x] MoveProjectCard

#### Deployments (4)
- [x] ListDeployments
- [x] CreateDeployment
- [x] ListDeploymentStatuses
- [x] CreateDeploymentStatus

#### Repository Contents (5)
- [x] GetFileContents
- [x] CreateOrUpdateFileContents
- [x] DeleteFileContents
- [x] GetArchiveLink
- [x] ListRepositoryTree

#### Forks (1)
- [x] ListForks

#### Collaborator Permissions (2)
- [x] GetCollaboratorPermission
- [x] ListPendingInvitations

#### Code Scanning / Security (4)
- [x] ListCodeScanningAlerts
- [x] GetCodeScanningAlert
- [x] ListDependabotAlerts
- [x] ListSecretScanningAlerts

#### Pages (3)
- [x] GetPages
- [x] CreatePagesSite
- [x] ListPagesBuilds

#### Packages (4)
- [x] ListPackages
- [x] GetPackage
- [x] DeletePackage
- [x] ListPackageVersions

#### SSH / GPG Keys (6)
- [x] ListSSHKeys
- [x] CreateSSHKey
- [x] DeleteSSHKey
- [x] ListGPGKeys
- [x] CreateGPGKey
- [x] DeleteGPGKey

#### Rulesets (5)
- [x] ListRulesets
- [x] CreateRuleset
- [x] GetRuleset
- [x] UpdateRuleset
- [x] DeleteRuleset

#### Autolinks (3)
- [x] ListAutolinks
- [x] CreateAutolink
- [x] DeleteAutolink

#### Environments (4)
- [x] ListEnvironments
- [x] GetEnvironment
- [x] CreateOrUpdateEnvironment
- [x] DeleteEnvironment
