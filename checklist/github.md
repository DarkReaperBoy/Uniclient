## Phase 10: GitHub — IN PROGRESS

56 exported methods, ~2,847 lines. REST API via net/http. Chat mapped to repos/issues/DMs. ~230 platform-specific methods pending.

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

### Not Added in Core

Platform-specific methods beyond the 55 Core interface. These map to GitHub REST API endpoints relevant to "GitHub as chat."

**Issues Extended**
- [ ] LockIssue (lock conversation)
- [ ] UnlockIssue
- [ ] ListIssueEvents
- [ ] GetIssueTimeline
- [ ] ListSubIssues
- [ ] AddSubIssue

**Labels**
- [ ] ListLabels
- [ ] CreateLabel
- [ ] UpdateLabel
- [ ] DeleteLabel
- [ ] AddLabelsToIssue
- [ ] RemoveLabel
- [ ] SetLabels

**Milestones**
- [ ] ListMilestones
- [ ] CreateMilestone
- [ ] UpdateMilestone
- [ ] DeleteMilestone

**Pull Requests**
- [ ] ListPullRequests
- [ ] CreatePullRequest
- [ ] GetPullRequest
- [ ] UpdatePullRequest
- [ ] MergePullRequest
- [ ] ListPRComments
- [ ] CreatePRComment
- [ ] ListPRReviews
- [ ] CreatePRReview
- [ ] SubmitPRReview
- [ ] DismissPRReview
- [ ] RequestReviewers

**Notifications**
- [ ] ListNotifications
- [ ] MarkAllNotificationsRead
- [ ] GetNotificationThread
- [ ] MarkThreadRead
- [ ] SubscribeThread
- [ ] UnsubscribeThread

**Repository Extended**
- [ ] DeleteRepo
- [ ] ForkRepo
- [ ] TransferRepo
- [ ] GetRepoTopics
- [ ] SetRepoTopics
- [ ] ListContributors
- [ ] GetRepoActivity

**Repository Invitations**
- [ ] ListInvitations
- [ ] UpdateInvitation
- [ ] DeleteInvitation
- [ ] AcceptInvitation
- [ ] DeclineInvitation

**Gists**
- [ ] ListGists
- [ ] CreateGist
- [ ] UpdateGist
- [ ] DeleteGist
- [ ] StarGist
- [ ] UnstarGist
- [ ] ListGistComments
- [ ] CreateGistComment

**Releases**
- [ ] ListReleases
- [ ] CreateRelease
- [ ] UpdateRelease
- [ ] DeleteRelease
- [ ] UploadReleaseAsset
- [ ] ListReleaseAssets

**Commit Comments**
- [ ] ListCommitComments
- [ ] CreateCommitComment
- [ ] UpdateCommitComment
- [ ] DeleteCommitComment

**Organizations**
- [ ] ListOrgs
- [ ] GetOrg
- [ ] ListOrgMembers
- [ ] ListOrgTeams
- [ ] CreateTeam
- [ ] UpdateTeam
- [ ] DeleteTeam
- [ ] AddTeamMember
- [ ] RemoveTeamMember

**Webhooks**
- [ ] CreateWebhook
- [ ] UpdateWebhook
- [ ] DeleteWebhook
- [ ] PingWebhook

**Starring/Watching**
- [ ] ListStargazers
- [ ] StarRepo
- [ ] UnstarRepo
- [ ] ListWatchers
- [ ] WatchRepo
- [ ] UnwatchRepo

**Events**
- [ ] ListEvents
- [ ] ListRepoEvents
- [ ] ListUserEvents
- [ ] GetFeeds

**Discussions (GraphQL only)**
- [ ] ListDiscussions
- [ ] CreateDiscussion
- [ ] UpdateDiscussion
- [ ] DeleteDiscussion
- [ ] AddDiscussionComment
- [ ] UpdateDiscussionComment
- [ ] DeleteDiscussionComment
- [ ] MarkDiscussionCommentAsAnswer

**User Extended**
- [ ] UpdateProfile (name, bio, blog)
- [ ] ListEmails
- [ ] AddEmail
- [ ] DeleteEmail
- [ ] ListSocialAccounts
- [ ] AddSocialAccount
- [ ] DeleteSocialAccount
- [ ] GetUserHovercard

**Search Extended**
- [ ] SearchCode
- [ ] SearchCommits
- [ ] SearchLabels
- [ ] SearchTopics

**Utility**
- [ ] ListEmojis
- [ ] CheckRateLimit
- [ ] RenderMarkdown

**Branches & Branch Protection (not added)**
- [ ] ListBranches
- [ ] GetBranch
- [ ] CreateBranchProtection
- [ ] UpdateBranchProtection
- [ ] DeleteBranchProtection
- [ ] RenameBranch

**Git References / Tags (not added)**
- [ ] ListTags
- [ ] CreateTag
- [ ] DeleteTag
- [ ] ListRefs
- [ ] CreateRef
- [ ] DeleteRef

**Commits (not added)**
- [ ] ListCommits
- [ ] GetCommit
- [ ] CompareCommits

**Actions / Workflows (not added)**
- [ ] ListWorkflows
- [ ] ListWorkflowRuns
- [ ] GetWorkflowRun
- [ ] ReRunWorkflow
- [ ] CancelWorkflowRun
- [ ] ListWorkflowRunArtifacts
- [ ] DownloadArtifact
- [ ] ListRepositorySecrets
- [ ] CreateOrUpdateSecret
- [ ] DeleteSecret

**Checks / Statuses (not added)**
- [ ] ListCheckRuns
- [ ] GetCheckRun
- [ ] ListCheckSuites
- [ ] CreateCheckRun
- [ ] ListCommitStatuses
- [ ] CreateCommitStatus

**Projects (not added)**
- [ ] ListProjects
- [ ] CreateProject
- [ ] UpdateProject
- [ ] DeleteProject
- [ ] ListProjectColumns
- [ ] CreateProjectCard
- [ ] MoveProjectCard

**Deployments (not added)**
- [ ] ListDeployments
- [ ] CreateDeployment
- [ ] ListDeploymentStatuses
- [ ] CreateDeploymentStatus

**Repository Contents (not added)**
- [ ] GetFileContents
- [ ] CreateOrUpdateFileContents
- [ ] DeleteFileContents
- [ ] GetArchiveLink (tarball/zipball)
- [ ] ListRepositoryTree (git trees)

**Forks (not added)**
- [ ] ListForks

**Collaborator Permissions (not added)**
- [ ] GetCollaboratorPermission
- [ ] ListPendingInvitations

**Code Scanning / Security (not added)**
- [ ] ListCodeScanningAlerts
- [ ] GetCodeScanningAlert
- [ ] ListDependabotAlerts
- [ ] ListSecretScanningAlerts

**Pages (not added)**
- [ ] GetPages
- [ ] CreatePagesSite
- [ ] ListPagesBuilds

**Packages (not added)**
- [ ] ListPackages
- [ ] GetPackage
- [ ] DeletePackage
- [ ] ListPackageVersions

**SSH / GPG Keys (not added)**
- [ ] ListSSHKeys
- [ ] CreateSSHKey
- [ ] DeleteSSHKey
- [ ] ListGPGKeys
- [ ] CreateGPGKey
- [ ] DeleteGPGKey

**Rulesets (not added)**
- [ ] ListRulesets
- [ ] CreateRuleset
- [ ] GetRuleset
- [ ] UpdateRuleset
- [ ] DeleteRuleset

**Autolinks (not added)**
- [ ] ListAutolinks
- [ ] CreateAutolink
- [ ] DeleteAutolink

**Environments (not added)**
- [ ] ListEnvironments
- [ ] GetEnvironment
- [ ] CreateOrUpdateEnvironment
- [ ] DeleteEnvironment
