# GitHub — Fresh Checklist

**Methods:** 775 exported | **Lines:** 6,610 | **File:** `go/cores/github.go`
**Protocol:** GitHub (REST API v3, GraphQL v4)
**Last updated:** 2026-04-13

## Categories

### Core Interface (3)
- [ ] Capabilities
- [ ] Close
- [ ] Name

### Authentication & Session (5)
- [ ] Authenticate
- [ ] CheckAppToken
- [ ] GetSessions
- [ ] Logout
- [ ] TerminateSession

### App Management (14)
- [ ] CheckRateLimit
- [ ] CreateAppFromManifest
- [ ] CreateInstallationAccessToken
- [ ] CreateScopedAccessToken
- [ ] DeleteAppAuthorization
- [ ] DeleteAppInstallation
- [ ] DeleteAppToken
- [ ] GetAppBySlug
- [ ] GetAppInstallation
- [ ] GetAuthenticatedApp
- [ ] ResetAppToken
- [ ] RevokeInstallationAccessToken
- [ ] SuspendAppInstallation
- [ ] UnsuspendAppInstallation

### App Webhooks (5)
- [ ] GetAppWebhookConfig
- [ ] GetAppWebhookDelivery
- [ ] ListAppWebhookDeliveries
- [ ] RedeliverAppWebhook
- [ ] UpdateAppWebhookConfig

### User Profile & Account (16)
- [ ] AddEmail
- [ ] AddSocialAccount
- [ ] BlockUser
- [ ] DeleteEmail
- [ ] DeleteSocialAccount
- [ ] FollowUser
- [ ] GetBlockedUsers
- [ ] GetProfile
- [ ] GetUserHovercard
- [ ] ListEmails
- [ ] ListPublicEmails
- [ ] ListSocialAccounts
- [ ] SetEmailVisibility
- [ ] UnblockUser
- [ ] UnfollowUser
- [ ] UpdateProfile

### User Keys (10)
- [ ] CreateGPGKey
- [ ] CreateSSHKey
- [ ] CreateSSHSigningKey
- [ ] DeleteGPGKey
- [ ] DeleteSSHKey
- [ ] DeleteSSHSigningKey
- [ ] GetSSHSigningKey
- [ ] ListGPGKeys
- [ ] ListSSHKeys
- [ ] ListSSHSigningKeys

### Messaging & Chat (18)
- [ ] DeleteMessage
- [ ] EditMessage
- [ ] ForwardMessage
- [ ] GetMessages
- [ ] GetReadState
- [ ] MarkAsRead
- [ ] MarkUnread
- [ ] PinMessage
- [ ] ReactToMessage
- [ ] ReplyToMessage
- [ ] SearchMessages
- [ ] SendImageBase64
- [ ] SendLocation
- [ ] SendMessage
- [ ] SendSticker
- [ ] SendTyping
- [ ] UnpinAllMessages
- [ ] UnpinMessage

### Channels & Chats (8)
- [ ] ArchiveChat
- [ ] CreateChannel
- [ ] EditChatDescription
- [ ] EditChatTitle
- [ ] GetChatInfo
- [ ] GetDialogs
- [ ] LeaveChat
- [ ] MuteChat

### Contacts & Members (15)
- [ ] AddContact
- [ ] AddMembers
- [ ] AddTeamMember
- [ ] BanMember
- [ ] ConvertToOutsideCollaborator
- [ ] DeleteContact
- [ ] GetContacts
- [ ] GetInviteLink
- [ ] GetMembers
- [ ] ListOutsideCollaborators
- [ ] RemoveMember
- [ ] RemoveOutsideCollaborator
- [ ] RemoveTeamMember
- [ ] SetAdmin
- [ ] UnbanMember

### Groups (1)
- [ ] CreateGroup

### Calls (6)
- [ ] AcceptCall
- [ ] DeclineCall
- [ ] EndCall
- [ ] JoinGroupCall
- [ ] SetCallMuted
- [ ] StartCall

### Polls (2)
- [ ] CreatePoll
- [ ] VotePoll

### Folders (2)
- [ ] CreateFolder
- [ ] GetFolders

### File Operations (3)
- [ ] DownloadFile
- [ ] OnUpdate
- [ ] UploadFile

### Search (8)
- [ ] SearchCode
- [ ] SearchCommits
- [ ] SearchGlobal
- [ ] SearchIssuesAndPRs
- [ ] SearchLabels
- [ ] SearchRepositories
- [ ] SearchTopics
- [ ] SearchUsers

### Repositories — General (19)
- [ ] CreateRepoFromTemplate
- [ ] CreateRepositoryDispatch
- [ ] DeleteRepo
- [ ] ForkRepo
- [ ] GetArchiveLink
- [ ] GetCodeownersErrors
- [ ] GetCommunityProfile
- [ ] GetDirREADME
- [ ] GetRepoActivity
- [ ] GetRepoLicense
- [ ] GetRepoREADME
- [ ] GetRepoTopics
- [ ] ListContributors
- [ ] ListRepoEvents
- [ ] ListRepoLanguages
- [ ] ListRepoTeams
- [ ] SetRepoTopics
- [ ] SyncForkWithUpstream
- [ ] TransferRepo

### Repositories — Collaborators (5)
- [ ] AddCollaborator
- [ ] CheckCollaborator
- [ ] GetCollaboratorPermission
- [ ] ListCollaborators
- [ ] RemoveCollaborator

### Repository Contents (4)
- [ ] CreateOrUpdateFileContents
- [ ] DeleteFileContents
- [ ] GetFileContents
- [ ] ListRepositoryTree

### Repository Statistics (5)
- [ ] GetCodeFrequencyStats
- [ ] GetCommitActivityStats
- [ ] GetContributorStats
- [ ] GetParticipationStats
- [ ] GetPunchCardStats

### Repository Traffic (4)
- [ ] GetRepoClones
- [ ] GetRepoPageViews
- [ ] GetTopReferralPaths
- [ ] GetTopReferrers

### Starring & Watching (6)
- [ ] ListStargazers
- [ ] ListWatchers
- [ ] StarRepo
- [ ] UnstarRepo
- [ ] UnwatchRepo
- [ ] WatchRepo

### Branches & Refs (7)
- [ ] CreateRef
- [ ] DeleteRef
- [ ] GetBranch
- [ ] ListBranches
- [ ] ListMatchingRefs
- [ ] ListRefs
- [ ] RenameBranch

### Branch Protection (18)
- [ ] CreateBranchProtection
- [ ] DeleteBranchProtection
- [ ] DeleteBranchRestrictions
- [ ] GetAdminEnforcement
- [ ] GetBranchRestrictions
- [ ] GetBranchRules
- [ ] GetRequiredPRReviews
- [ ] GetRequiredSignatures
- [ ] GetRequiredStatusChecks
- [ ] RemoveAdminEnforcement
- [ ] RemoveRequiredPRReviews
- [ ] RemoveRequiredSignatures
- [ ] RemoveRequiredStatusChecks
- [ ] SetAdminEnforcement
- [ ] SetRequiredSignatures
- [ ] UpdateBranchProtection
- [ ] UpdateRequiredPRReviews
- [ ] UpdateRequiredStatusChecks

### Rulesets (7)
- [ ] CreateRuleset
- [ ] DeleteRuleset
- [ ] GetRuleset
- [ ] GetRulesetHistory
- [ ] GetRulesetVersion
- [ ] ListRulesets
- [ ] UpdateRuleset

### Rule Suites (2)
- [ ] GetRuleSuite
- [ ] ListRuleSuites

### Commits (8)
- [ ] CompareCommits
- [ ] CreateCommitStatus
- [ ] GetCombinedStatus
- [ ] GetCommit
- [ ] ListBranchesForHEADCommit
- [ ] ListCommits
- [ ] ListCommitStatuses
- [ ] ListPRsForCommit

### Commit Comments (7)
- [ ] CreateCommitComment
- [ ] CreateCommitCommentReaction
- [ ] DeleteCommitComment
- [ ] DeleteCommitCommentReaction
- [ ] ListCommitCommentReactions
- [ ] ListCommitComments
- [ ] UpdateCommitComment

### Git Objects (6)
- [ ] CreateBlob
- [ ] CreateGitCommit
- [ ] CreateGitTag
- [ ] GetBlob
- [ ] GetGitCommit
- [ ] GetGitTag

### Tags (3)
- [ ] CreateTag
- [ ] DeleteTag
- [ ] ListTags

### Merging (1)
- [ ] MergeBranch

### Issues (21)
- [ ] AddIssueAssignees
- [ ] AddLabelsToIssue
- [ ] CheckAssignable
- [ ] CreateIssueCommentReaction
- [ ] CreateIssueReaction
- [ ] DeleteIssueCommentReaction
- [ ] DeleteIssueReaction
- [ ] GetIssueEvent
- [ ] GetIssueTimeline
- [ ] ListAuthenticatedUserIssues
- [ ] ListIssueCommentReactions
- [ ] ListIssueEvents
- [ ] ListIssueReactions
- [ ] ListOrgIssues
- [ ] ListRepoAssignees
- [ ] ListRepoIssueEvents
- [ ] LockIssue
- [ ] RemoveIssueAssignees
- [ ] RemoveLabel
- [ ] SetLabels
- [ ] UnlockIssue

### Sub-Issues (5)
- [ ] AddSubIssue
- [ ] GetParentIssue
- [ ] ListSubIssues
- [ ] RemoveSubIssue
- [ ] ReprioritizeSubIssue

### Blocking Dependencies (3)
- [ ] AddBlockingDependency
- [ ] ListBlockingDependencies
- [ ] RemoveBlockingDependency

### Labels (4)
- [ ] CreateLabel
- [ ] DeleteLabel
- [ ] ListLabels
- [ ] UpdateLabel

### Milestones (5)
- [ ] CreateMilestone
- [ ] DeleteMilestone
- [ ] ListMilestoneLabels
- [ ] ListMilestones
- [ ] UpdateMilestone

### Pull Requests (18)
- [ ] CheckPRMerged
- [ ] CreatePRComment
- [ ] CreatePRCommentReaction
- [ ] CreatePRCommentReply
- [ ] CreatePullRequest
- [ ] DeletePRCommentReaction
- [ ] GetPullRequest
- [ ] GetRequestedReviewers
- [ ] ListPRCommentReactions
- [ ] ListPRComments
- [ ] ListPRCommits
- [ ] ListPRFiles
- [ ] ListPullRequests
- [ ] MergePullRequest
- [ ] RemoveRequestedReviewers
- [ ] RequestReviewers
- [ ] UpdatePRBranch
- [ ] UpdatePullRequest

### Pull Request Reviews (8)
- [ ] CreatePRReview
- [ ] DeletePendingPRReview
- [ ] DismissPRReview
- [ ] GetPRReview
- [ ] ListPRReviewComments
- [ ] ListPRReviews
- [ ] SubmitPRReview
- [ ] UpdatePRReview

### Discussions (8)
- [ ] AddDiscussionComment
- [ ] CreateDiscussion
- [ ] DeleteDiscussion
- [ ] DeleteDiscussionComment
- [ ] ListDiscussions
- [ ] MarkDiscussionCommentAsAnswer
- [ ] UpdateDiscussion
- [ ] UpdateDiscussionComment

### Releases (15)
- [ ] CreateRelease
- [ ] CreateReleaseReaction
- [ ] DeleteRelease
- [ ] DeleteReleaseAsset
- [ ] DeleteReleaseReaction
- [ ] GenerateReleaseNotes
- [ ] GetLatestRelease
- [ ] GetReleaseAsset
- [ ] GetReleaseByTag
- [ ] ListReleaseAssets
- [ ] ListReleaseReactions
- [ ] ListReleases
- [ ] UpdateRelease
- [ ] UpdateReleaseAsset
- [ ] UploadReleaseAsset

### Deploy Keys (4)
- [ ] CreateDeployKey
- [ ] DeleteDeployKey
- [ ] GetDeployKey
- [ ] ListDeployKeys

### Deployments (14)
- [ ] CreateDeployment
- [ ] CreateDeploymentBranchPolicy
- [ ] CreateDeploymentProtectionRule
- [ ] CreateDeploymentStatus
- [ ] DeleteDeploymentBranchPolicy
- [ ] GetDeploymentBranchPolicy
- [ ] GetPendingDeployments
- [ ] ListDeploymentBranchPolicies
- [ ] ListDeploymentProtectionRuleApps
- [ ] ListDeploymentProtectionRules
- [ ] ListDeployments
- [ ] ListDeploymentStatuses
- [ ] ReviewPendingDeployments
- [ ] UpdateDeploymentBranchPolicy

### Environments (14)
- [ ] CreateEnvironmentVariable
- [ ] CreateOrUpdateEnvironment
- [ ] CreateOrUpdateEnvironmentSecret
- [ ] DeleteEnvironment
- [ ] DeleteEnvironmentSecret
- [ ] DeleteEnvironmentVariable
- [ ] GetEnvironment
- [ ] GetEnvironmentPublicKey
- [ ] GetEnvironmentSecret
- [ ] GetEnvironmentVariable
- [ ] ListEnvironments
- [ ] ListEnvironmentSecrets
- [ ] ListEnvironmentVariables
- [ ] UpdateEnvironmentVariable

### Webhooks (9)
- [ ] CreateWebhook
- [ ] DeleteWebhook
- [ ] GetWebhookConfig
- [ ] GetWebhookDelivery
- [ ] ListWebhookDeliveries
- [ ] PingWebhook
- [ ] RedeliverWebhook
- [ ] UpdateWebhook
- [ ] UpdateWebhookConfig

### GitHub Actions — Workflows (8)
- [ ] ApproveWorkflowRun
- [ ] CancelWorkflowRun
- [ ] CreateWorkflowDispatch
- [ ] DisableWorkflow
- [ ] EnableWorkflow
- [ ] GetWorkflow
- [ ] GetWorkflowTiming
- [ ] ListWorkflows

### GitHub Actions — Workflow Runs (16)
- [ ] DeleteWorkflowRun
- [ ] DeleteWorkflowRunLogs
- [ ] DownloadWorkflowRunAttemptLogs
- [ ] DownloadWorkflowRunLogs
- [ ] ForceCancelWorkflowRun
- [ ] GetWorkflowRun
- [ ] GetWorkflowRunApprovals
- [ ] GetWorkflowRunAttempt
- [ ] GetWorkflowRunTiming
- [ ] ListWorkflowRunArtifacts
- [ ] ListWorkflowRunAttemptJobs
- [ ] ListWorkflowRunJobs
- [ ] ListWorkflowRuns
- [ ] ReRunWorkflow
- [ ] RerunFailedJobs
- [ ] RerunWorkflowJob

### GitHub Actions — Workflow Jobs & Artifacts (3)
- [ ] DownloadArtifact
- [ ] DownloadWorkflowJobLogs
- [ ] GetWorkflowJob

### GitHub Actions — Runners (Self-Hosted) (14)
- [ ] CreateJITRunnerConfig
- [ ] CreateOrgJITRunnerConfig
- [ ] CreateOrgRunnerRegistrationToken
- [ ] CreateOrgRunnerRemoveToken
- [ ] CreateRunnerRegistrationToken
- [ ] CreateRunnerRemoveToken
- [ ] DeleteOrgRunner
- [ ] DeleteRepoRunner
- [ ] GetOrgRunner
- [ ] GetRepoRunner
- [ ] ListOrgRunnerApplications
- [ ] ListOrgRunners
- [ ] ListRepoRunners
- [ ] ListRunnerApplications

### GitHub Actions — Runner Labels (8)
- [ ] AddOrgRunnerLabels
- [ ] AddRepoRunnerLabels
- [ ] ListOrgRunnerLabels
- [ ] ListRepoRunnerLabels
- [ ] RemoveOrgRunnerLabel
- [ ] RemoveRepoRunnerLabel
- [ ] SetOrgRunnerLabels
- [ ] SetRepoRunnerLabels

### GitHub Actions — Runner Groups (11)
- [ ] AddRunnerGroupRepo
- [ ] AddRunnerGroupRunner
- [ ] CreateOrgRunnerGroup
- [ ] DeleteOrgRunnerGroup
- [ ] GetOrgRunnerGroup
- [ ] ListOrgRunnerGroups
- [ ] ListRunnerGroupRepos
- [ ] ListRunnerGroupRunners
- [ ] RemoveRunnerGroupRepo
- [ ] RemoveRunnerGroupRunner
- [ ] SetRunnerGroupRepos
- [ ] SetRunnerGroupRunners
- [ ] UpdateOrgRunnerGroup

### GitHub Actions — Hosted Runners (5)
- [ ] CreateOrgHostedRunner
- [ ] DeleteOrgHostedRunner
- [ ] GetOrgHostedRunner
- [ ] ListOrgHostedRunners
- [ ] UpdateOrgHostedRunner

### GitHub Actions — Secrets (11)
- [ ] CreateOrUpdateOrgSecret
- [ ] CreateOrUpdateSecret
- [ ] DeleteOrgSecret
- [ ] DeleteSecret
- [ ] GetOrgPublicKey
- [ ] GetOrgSecret
- [ ] ListOrgSecretRepos
- [ ] ListOrgSecrets
- [ ] ListRepositorySecrets
- [ ] RemoveOrgSecretRepo
- [ ] SetOrgSecretRepos

### GitHub Actions — Variables (10)
- [ ] CreateOrgVariable
- [ ] CreateRepoVariable
- [ ] DeleteOrgVariable
- [ ] DeleteRepoVariable
- [ ] GetOrgVariable
- [ ] GetRepoVariable
- [ ] ListOrgVariables
- [ ] ListRepoVariables
- [ ] UpdateOrgVariable
- [ ] UpdateRepoVariable

### GitHub Actions — Permissions & Settings (16)
- [ ] GetOrgActionsPermissions
- [ ] GetOrgAllowedActions
- [ ] GetOrgArtifactRetention
- [ ] GetOrgDefaultWorkflowPermissions
- [ ] GetRepoActionsAccessSettings
- [ ] GetRepoActionsPermissions
- [ ] GetRepoAllowedActions
- [ ] GetRepoDefaultWorkflowPermissions
- [ ] SetOrgActionsPermissions
- [ ] SetOrgAllowedActions
- [ ] SetOrgArtifactRetention
- [ ] SetOrgDefaultWorkflowPermissions
- [ ] SetRepoActionsAccessSettings
- [ ] SetRepoActionsPermissions
- [ ] SetRepoAllowedActions
- [ ] SetRepoDefaultWorkflowPermissions

### GitHub Actions — Caches (6)
- [ ] DeleteRepoCacheByID
- [ ] DeleteRepoCachesByKey
- [ ] GetOrgCacheUsage
- [ ] GetOrgCacheUsageByRepo
- [ ] GetRepoCacheUsage
- [ ] ListRepoCaches

### Check Runs & Check Suites (12)
- [ ] CreateCheckRun
- [ ] GetCheckRun
- [ ] GetCheckSuite
- [ ] ListCheckRunAnnotations
- [ ] ListCheckRuns
- [ ] ListCheckRunsForRef
- [ ] ListCheckSuiteCheckRuns
- [ ] ListCheckSuites
- [ ] ListCheckSuitesForRef
- [ ] RerequestCheckRun
- [ ] RerequestCheckSuite
- [ ] UpdateCheckSuitePreferences

### Gists (15)
- [ ] CreateGist
- [ ] CreateGistComment
- [ ] DeleteGist
- [ ] ForkGist
- [ ] GetGistRevision
- [ ] ListGistComments
- [ ] ListGistCommits
- [ ] ListGistForks
- [ ] ListGists
- [ ] ListPublicGists
- [ ] ListStarredGists
- [ ] ListUserGists
- [ ] StarGist
- [ ] UnstarGist
- [ ] UpdateGist

### Organizations — General (19)
- [ ] BlockOrgUser
- [ ] CancelOrgInvitation
- [ ] CheckPublicMembership
- [ ] ConcealMembership
- [ ] CreateOrgInvitation
- [ ] GetOrg
- [ ] GetOrgMembership
- [ ] GetUserOrgMembership
- [ ] ListFailedInvitations
- [ ] ListOrgBlockedUsers
- [ ] ListOrgInvitations
- [ ] ListOrgMembers
- [ ] ListOrgs
- [ ] ListOrgTeams
- [ ] ListPublicMembers
- [ ] PublicizeMembership
- [ ] RemoveOrgMembership
- [ ] SetOrgMembership
- [ ] UnblockOrgUser

### Organizations — Custom Properties (7)
- [ ] CreateOrgCustomProperties
- [ ] CreateOrUpdateOrgCustomProperty
- [ ] DeleteOrgCustomProperty
- [ ] GetCustomPropertyValues
- [ ] GetOrgCustomProperty
- [ ] ListOrgCustomProperties
- [ ] SetCustomPropertyValues

### Organizations — Roles (8)
- [ ] AssignTeamRole
- [ ] AssignUserRole
- [ ] GetOrgRole
- [ ] ListOrgRoles
- [ ] ListTeamsForRole
- [ ] ListUsersForRole
- [ ] RemoveTeamRole
- [ ] RemoveUserRole

### Organizations — Billing & Budgets (6)
- [ ] DeleteOrgBudget
- [ ] GetOrgBillingUsage
- [ ] GetOrgBillingUsageSummary
- [ ] GetOrgBudget
- [ ] ListOrgBudgets
- [ ] UpdateOrgBudget

### Organizations — Webhooks (6)
- [ ] CreateOrgWebhook
- [ ] DeleteOrgWebhook
- [ ] GetOrgWebhook
- [ ] ListOrgWebhooks
- [ ] PingOrgWebhook
- [ ] UpdateOrgWebhook

### Organizations — Interaction Limits (3)
- [ ] GetOrgInteractionLimits
- [ ] RemoveOrgInteractionLimits
- [ ] SetOrgInteractionLimits

### Organizations — OIDC (4)
- [ ] GetOrgOIDCProperties
- [ ] GetOrgOIDCSubjectClaim
- [ ] SetOrgOIDCProperties
- [ ] SetOrgOIDCSubjectClaim

### Organizations — Fork Policy (2)
- [ ] GetOrgForkPRApproval
- [ ] SetOrgForkPRApproval

### Organizations — Security Managers (3)
- [ ] AddSecurityManagerTeam
- [ ] ListSecurityManagers
- [ ] RemoveSecurityManagerTeam

### Organizations — PATs (6)
- [ ] ListOrgPATRequests
- [ ] ListOrgPATs
- [ ] ReviewOrgPATRequest
- [ ] ReviewOrgPATRequests
- [ ] UpdateOrgPAT
- [ ] UpdateOrgPATs

### Organizations — Enabled Repos (4)
- [ ] AddOrgEnabledRepo
- [ ] GetOrgEnabledRepos
- [ ] RemoveOrgEnabledRepo
- [ ] SetOrgEnabledRepos

### Teams (10)
- [ ] AddTeamRepo
- [ ] CheckTeamRepo
- [ ] CreateTeam
- [ ] DeleteTeam
- [ ] ListChildTeams
- [ ] ListInvitationTeams
- [ ] ListTeamInvitations
- [ ] ListTeamRepos
- [ ] RemoveTeamRepo
- [ ] UpdateTeam

### Projects (Classic) (7)
- [ ] CreateProject
- [ ] CreateProjectCard
- [ ] DeleteProject
- [ ] ListProjectColumns
- [ ] ListProjects
- [ ] MoveProjectCard
- [ ] UpdateProject

### Projects V2 (12)
- [ ] AddProjectV2Item
- [ ] CopyProjectV2
- [ ] CreateProjectV2DraftItem
- [ ] CreateProjectV2View
- [ ] DeleteProjectV2
- [ ] DeleteProjectV2Item
- [ ] GetProjectV2
- [ ] ListOrgProjectsV2
- [ ] ListProjectV2Fields
- [ ] ListProjectV2Items
- [ ] UpdateProjectV2
- [ ] UpdateProjectV2Item

### Notifications (6)
- [ ] GetNotificationThread
- [ ] ListNotifications
- [ ] MarkAllNotificationsRead
- [ ] MarkThreadRead
- [ ] SubscribeThread
- [ ] UnsubscribeThread

### Pages (11)
- [ ] CancelPagesDeployment
- [ ] CreatePagesDeployment
- [ ] CreatePagesSite
- [ ] DeletePagesSite
- [ ] GetLatestPagesBuild
- [ ] GetPages
- [ ] GetPagesBuild
- [ ] GetPagesDNSHealth
- [ ] GetPagesDeploymentStatus
- [ ] ListPagesBuilds
- [ ] UpdatePagesSite

### Codespaces (21)
- [ ] AddCodespacesAccessUsers
- [ ] CheckDevContainerPermissions
- [ ] CreateCodespaceFromPR
- [ ] CreateRepoCodespace
- [ ] CreateUserCodespace
- [ ] DeleteCodespace
- [ ] ExportCodespace
- [ ] GetCodespace
- [ ] GetCodespaceDefaults
- [ ] GetCodespaceExport
- [ ] ListCodespaceMachines
- [ ] ListCodespaceMachineTypes
- [ ] ListDevContainerConfigs
- [ ] ListOrgCodespaces
- [ ] ListRepoCodespaces
- [ ] ListUserCodespaces
- [ ] PublishCodespace
- [ ] RemoveCodespacesAccessUsers
- [ ] SetOrgCodespacesAccess
- [ ] StartCodespace
- [ ] StopCodespace
- [ ] UpdateCodespace

### Codespace Secrets (5)
- [ ] CreateOrUpdateOrgCodespaceSecret
- [ ] DeleteOrgCodespaceSecret
- [ ] GetOrgCodespacePublicKey
- [ ] GetOrgCodespaceSecret
- [ ] ListOrgCodespaceSecrets

### Copilot (9)
- [ ] AddCopilotTeams
- [ ] AddCopilotUsers
- [ ] GetCopilotMetrics
- [ ] GetCopilotSeatInfo
- [ ] GetCopilotTeamMetrics
- [ ] GetCopilotUserSeat
- [ ] ListCopilotSeats
- [ ] RemoveCopilotTeams
- [ ] RemoveCopilotUsers

### Code Scanning (12)
- [ ] CreateCodeScanningAutofix
- [ ] DeleteCodeScanningAnalysis
- [ ] GetCodeScanningAlert
- [ ] GetCodeScanningAnalysis
- [ ] GetCodeScanningAutofix
- [ ] GetCodeScanningDefaultSetup
- [ ] ListCodeScanningAlertInstances
- [ ] ListCodeScanningAlerts
- [ ] ListCodeScanningAnalyses
- [ ] ListOrgCodeScanningAlerts
- [ ] UpdateCodeScanningAlert
- [ ] UpdateCodeScanningDefaultSetup

### Secret Scanning (6)
- [ ] GetSecretScanHistory
- [ ] GetSecretScanningAlert
- [ ] ListOrgSecretScanningAlerts
- [ ] ListSecretScanningAlertLocations
- [ ] ListSecretScanningAlerts
- [ ] UpdateSecretScanningAlert

### Dependabot (14)
- [ ] CreateOrUpdateOrgDependabotSecret
- [ ] CreateOrUpdateRepoDependabotSecret
- [ ] DeleteOrgDependabotSecret
- [ ] DeleteRepoDependabotSecret
- [ ] GetDependabotAlert
- [ ] GetOrgDependabotPublicKey
- [ ] GetOrgDependabotSecret
- [ ] GetRepoDependabotPublicKey
- [ ] GetRepoDependabotSecret
- [ ] ListDependabotAlerts
- [ ] ListOrgDependabotAlerts
- [ ] ListOrgDependabotSecrets
- [ ] ListRepoDependabotSecrets
- [ ] UpdateDependabotAlert

### Dependency Graph (2)
- [ ] CreateDependencySnapshot
- [ ] GetDependencyDiff

### Security Advisories (8)
- [ ] CreateRepoAdvisory
- [ ] GetGlobalAdvisory
- [ ] GetRepoAdvisory
- [ ] ListGlobalAdvisories
- [ ] ListOrgAdvisories
- [ ] ListRepoAdvisories
- [ ] ReportVulnerability
- [ ] RequestCVE
- [ ] UpdateRepoAdvisory

### Vulnerability Alerts (3)
- [ ] CheckVulnerabilityAlerts
- [ ] DisableVulnerabilityAlerts
- [ ] EnableVulnerabilityAlerts

### SBOM (1)
- [ ] ExportSBOM

### SARIF (2)
- [ ] GetSARIFUpload
- [ ] UploadSARIF

### Attestations (2)
- [ ] CreateAttestation
- [ ] ListAttestations

### Push Protection (1)
- [ ] CreatePushProtectionBypass

### CodeQL (2)
- [ ] GetCodeQLDatabase
- [ ] ListCodeQLDatabases

### Migrations — Organization (7)
- [ ] DeleteOrgMigrationArchive
- [ ] DownloadOrgMigrationArchive
- [ ] GetOrgMigration
- [ ] ListOrgMigrationRepos
- [ ] ListOrgMigrations
- [ ] StartOrgMigration
- [ ] UnlockOrgMigrationRepo

### Migrations — User (7)
- [ ] DeleteUserMigrationArchive
- [ ] DownloadUserMigrationArchive
- [ ] GetUserMigration
- [ ] ListUserMigrationRepos
- [ ] ListUserMigrations
- [ ] StartUserMigration
- [ ] UnlockUserMigrationRepo

### Imports (6)
- [ ] CancelImport
- [ ] GetImportStatus
- [ ] MapImportAuthor
- [ ] StartImport
- [ ] UpdateImport
- [ ] UpdateImportLFS

### Packages (12)
- [ ] DeleteOrgPackageVersion
- [ ] DeletePackage
- [ ] DeleteUserPackageVersion
- [ ] GetOrgPackageVersion
- [ ] GetPackage
- [ ] GetUserPackageVersion
- [ ] ListPackages
- [ ] ListPackageVersions
- [ ] RestoreOrgPackage
- [ ] RestoreOrgPackageVersion
- [ ] RestoreUserPackage
- [ ] RestoreUserPackageVersion

### Installations (10)
- [ ] AddRepoToInstallation
- [ ] GetOrgInstallation
- [ ] GetRepoInstallation
- [ ] GetUserInstallation
- [ ] ListAppInstallations
- [ ] ListInstallationRepos
- [ ] ListInstallationRequests
- [ ] ListUserInstallationRepos
- [ ] ListUserInstallations
- [ ] RemoveRepoFromInstallation

### Invitations (5)
- [ ] AcceptInvitation
- [ ] DeclineInvitation
- [ ] DeleteInvitation
- [ ] ListInvitations
- [ ] UpdateInvitation

### Repository Interaction Limits (3)
- [ ] GetRepoInteractionLimits
- [ ] RemoveRepoInteractionLimits
- [ ] SetRepoInteractionLimits

### User Interaction Limits (3)
- [ ] GetUserInteractionLimits
- [ ] RemoveUserInteractionLimits
- [ ] SetUserInteractionLimits

### Repository OIDC (2)
- [ ] GetRepoOIDCSubjectClaim
- [ ] SetRepoOIDCSubjectClaim

### Forks (2)
- [ ] CreatePrivateFork
- [ ] ListForks

### Autolinks (3)
- [ ] CreateAutolink
- [ ] DeleteAutolink
- [ ] ListAutolinks

### Topics (1)
- [ ] CreateTopic

### Classroom (6)
- [ ] GetAssignment
- [ ] GetAssignmentGrades
- [ ] GetClassroom
- [ ] ListAcceptedAssignments
- [ ] ListClassroomAssignments
- [ ] ListClassrooms

### Events (2)
- [ ] ListEvents
- [ ] ListUserEvents

### User Org & Team Memberships (2)
- [ ] ListUserOrgMemberships
- [ ] ListUserTeams

### Feeds & Rendering (4)
- [ ] GetFeeds
- [ ] GetOctocat
- [ ] GetZen
- [ ] RenderMarkdown

### Licenses & Codes of Conduct (4)
- [ ] GetCodeOfConduct
- [ ] GetLicense
- [ ] ListCodesOfConduct
- [ ] ListLicenses

### Gitignore Templates (2)
- [ ] GetGitignoreTemplate
- [ ] ListGitignoreTemplates

### Emojis (1)
- [ ] ListEmojis

### API Metadata (3)
- [ ] GetAPIRoot
- [ ] GetAPIVersions
- [ ] GetMeta
