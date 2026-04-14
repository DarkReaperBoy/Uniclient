# GitHub Checklist — 768 methods


## Core Interface
- [x] Capabilities
- [x] Close
- [x] Name
- [x] OnUpdate

## Authentication
- [x] Authenticate
- [x] Logout

## Dialogs & Chats
- [x] ArchiveChat
- [x] EditChatDescription
- [x] EditChatTitle
- [x] GetChatInfo
- [x] GetDialogs
- [x] LeaveChat
- [x] MuteChat

## Messaging
- [x] DeleteMessage
- [x] EditMessage
- [x] ForwardMessage
- [x] GetMessages
- [x] GetReadState
- [x] MarkAsRead
- [x] MarkUnread
- [x] PinMessage
- [x] ReactToMessage
- [x] ReplyToMessage
- [x] SendImageBase64
- [x] SendLocation
- [x] SendMessage
- [x] SendSticker
- [x] SendTyping
- [x] UnpinAllMessages
- [x] UnpinMessage

## Calls
- [x] AcceptCall
- [x] DeclineCall
- [x] EndCall
- [x] SetCallMuted

## Group Calls
- [x] JoinGroupCall

## Groups & Channels
- [x] CreateChannel
- [x] CreateGroup
- [x] CreateTopic

## Members & Admin
- [x] AddMembers
- [x] BanMember
- [x] GetInviteLink
- [x] GetMembers
- [x] RemoveMember
- [x] SetAdmin
- [x] UnbanMember

## Contacts & Users
- [x] AddContact
- [x] BlockUser
- [x] DeleteContact
- [x] GetBlockedUsers
- [x] GetContacts
- [x] GetProfile
- [x] SearchGlobal
- [x] UnblockUser

## Folders
- [x] CreateFolder
- [x] GetFolders

## Sessions
- [x] GetSessions
- [x] TerminateSession

## Polls
- [x] CreatePoll
- [x] VotePoll

## Search
- [x] SearchCode
- [x] SearchMessages
- [x] SearchRepositories
- [x] SearchTopics
- [x] SearchUsers

## Pull Requests
- [x] CheckPRMerged
- [x] CreateCodespaceFromPR
- [x] CreatePRComment
- [x] CreatePRCommentReaction
- [x] CreatePRCommentReply
- [x] CreatePRReview
- [x] CreatePullRequest
- [x] DeletePendingPRReview
- [x] DeletePRCommentReaction
- [x] DismissPRReview
- [x] GetOrgForkPRApproval
- [x] GetPRReview
- [x] GetPullRequest
- [x] GetRequestedReviewers
- [x] GetRequiredPRReviews
- [x] ListPRCommentReactions
- [x] ListPRComments
- [x] ListPRCommits
- [x] ListPRFiles
- [x] ListPRReviewComments
- [x] ListPRReviews
- [x] ListPRsForCommit
- [x] ListPullRequests
- [x] MergePullRequest
- [x] RemoveRequestedReviewers
- [x] RemoveRequiredPRReviews
- [x] RequestReviewers
- [x] SearchIssuesAndPRs
- [x] SetOrgForkPRApproval
- [x] SubmitPRReview
- [x] UpdatePRBranch
- [x] UpdatePRReview
- [x] UpdatePullRequest
- [x] UpdateRequiredPRReviews

## Issues
- [x] AddIssueAssignees
- [x] AddLabelsToIssue
- [x] CreateIssueCommentReaction
- [x] CreateIssueReaction
- [x] DeleteIssueCommentReaction
- [x] DeleteIssueReaction
- [x] GetIssueEvent
- [x] GetIssueTimeline
- [x] GetParentIssue
- [x] ListAuthenticatedUserIssues
- [x] ListIssueCommentReactions
- [x] ListIssueEvents
- [x] ListIssueReactions
- [x] ListOrgIssues
- [x] ListRepoIssueEvents
- [x] LockIssue
- [x] RemoveIssueAssignees
- [x] UnlockIssue

## Sub-Issues
- [x] AddSubIssue
- [x] ListSubIssues
- [x] RemoveSubIssue
- [x] ReprioritizeSubIssue

## Labels
- [x] AddOrgRunnerLabels
- [x] AddRepoRunnerLabels
- [x] CreateLabel
- [x] DeleteLabel
- [x] ListLabels
- [x] ListMilestoneLabels
- [x] ListOrgRunnerLabels
- [x] ListRepoRunnerLabels
- [x] RemoveLabel
- [x] RemoveOrgRunnerLabel
- [x] RemoveRepoRunnerLabel
- [x] SearchLabels
- [x] SetLabels
- [x] SetOrgRunnerLabels
- [x] SetRepoRunnerLabels
- [x] UpdateLabel

## Milestones
- [x] CreateMilestone
- [x] DeleteMilestone
- [x] ListMilestones
- [x] UpdateMilestone

## Notifications
- [x] GetNotificationThread
- [x] ListNotifications
- [x] MarkAllNotificationsRead
- [x] MarkThreadRead
- [x] SubscribeThread
- [x] UnsubscribeThread

## Gists
- [x] CreateGist
- [x] CreateGistComment
- [x] DeleteGist
- [x] ForkGist
- [x] GetGistRevision
- [x] ListGistComments
- [x] ListGistCommits
- [x] ListGistForks
- [x] ListGists
- [x] ListPublicGists
- [x] ListStarredGists
- [x] ListUserGists
- [x] StarGist
- [x] UnstarGist
- [x] UpdateGist

## Releases
- [x] CreateRelease
- [x] CreateReleaseReaction
- [x] DeleteRelease
- [x] DeleteReleaseAsset
- [x] DeleteReleaseReaction
- [x] GenerateReleaseNotes
- [x] GetLatestRelease
- [x] GetReleaseAsset
- [x] GetReleaseByTag
- [x] ListReleaseAssets
- [x] ListReleaseReactions
- [x] ListReleases
- [x] UpdateRelease
- [x] UpdateReleaseAsset
- [x] UploadReleaseAsset

## Actions & Workflows
- [x] ApproveWorkflowRun
- [x] CancelWorkflowRun
- [x] CreateWorkflowDispatch
- [x] DeleteWorkflowRun
- [x] DeleteWorkflowRunLogs
- [x] DisableWorkflow
- [x] DownloadArtifact
- [x] DownloadWorkflowJobLogs
- [x] DownloadWorkflowRunAttemptLogs
- [x] DownloadWorkflowRunLogs
- [x] EnableWorkflow
- [x] ForceCancelWorkflowRun
- [x] GetOrgArtifactRetention
- [x] GetOrgDefaultWorkflowPermissions
- [x] GetRepoDefaultWorkflowPermissions
- [x] GetWorkflow
- [x] GetWorkflowJob
- [x] GetWorkflowRun
- [x] GetWorkflowRunApprovals
- [x] GetWorkflowRunAttempt
- [x] GetWorkflowRunTiming
- [x] GetWorkflowTiming
- [x] ListWorkflowRunArtifacts
- [x] ListWorkflowRunAttemptJobs
- [x] ListWorkflowRunJobs
- [x] ListWorkflowRuns
- [x] ListWorkflows
- [x] ReRunWorkflow
- [x] RerunWorkflowJob
- [x] SetOrgArtifactRetention
- [x] SetOrgDefaultWorkflowPermissions
- [x] SetRepoDefaultWorkflowPermissions

## Secrets
- [x] AddOrgSecretRepo
- [x] CreateOrUpdateEnvironmentSecret
- [x] CreateOrUpdateOrgCodespaceSecret
- [x] CreateOrUpdateOrgDependabotSecret
- [x] CreateOrUpdateOrgSecret
- [x] CreateOrUpdateRepoDependabotSecret
- [x] CreateOrUpdateSecret
- [x] DeleteEnvironmentSecret
- [x] DeleteOrgCodespaceSecret
- [x] DeleteOrgDependabotSecret
- [x] DeleteOrgSecret
- [x] DeleteRepoDependabotSecret
- [x] DeleteSecret
- [x] GetEnvironmentSecret
- [x] GetOrgCodespaceSecret
- [x] GetOrgDependabotSecret
- [x] GetOrgSecret
- [x] GetRepoDependabotSecret
- [x] GetSecretScanHistory
- [x] ListEnvironmentSecrets
- [x] ListOrgCodespaceSecrets
- [x] ListOrgDependabotSecrets
- [x] ListOrgSecretRepos
- [x] ListOrgSecrets
- [x] ListRepoDependabotSecrets
- [x] ListRepositorySecrets
- [x] RemoveOrgSecretRepo
- [x] SetOrgSecretRepos

## Checks & Statuses
- [x] CheckAppToken
- [x] CheckAssignable
- [x] CheckCollaborator
- [x] CheckDevContainerPermissions
- [x] CheckPublicMembership
- [x] CheckTeamRepo
- [x] CheckVulnerabilityAlerts
- [x] CreateCheckRun
- [x] CreateCommitComment
- [x] CreateCommitCommentReaction
- [x] CreateCommitStatus
- [x] DeleteCommitComment
- [x] DeleteCommitCommentReaction
- [x] GetCheckRun
- [x] GetCheckSuite
- [x] GetRequiredStatusChecks
- [x] ListCheckRunAnnotations
- [x] ListCheckRuns
- [x] ListCheckSuiteCheckRuns
- [x] ListCheckSuites
- [x] ListCommitCommentReactions
- [x] ListCommitComments
- [x] ListCommitStatuses
- [x] RemoveRequiredStatusChecks
- [x] RerequestCheckRun
- [x] RerequestCheckSuite
- [x] UpdateCheckSuitePreferences
- [x] UpdateCommitComment
- [x] UpdateRequiredStatusChecks

## Commits
- [x] CompareCommits
- [x] CreateGitCommit
- [x] GetCommit
- [x] GetCommitActivityStats
- [x] GetGitCommit
- [x] ListBranchesForHEADCommit
- [x] ListCommits
- [x] SearchCommits

## Branches
- [x] CreateBranchProtection
- [x] CreateDeploymentBranchPolicy
- [x] DeleteBranchProtection
- [x] DeleteBranchRestrictions
- [x] DeleteDeploymentBranchPolicy
- [x] GetBranch
- [x] GetBranchRestrictions
- [x] GetBranchRules
- [x] GetDeploymentBranchPolicy
- [x] ListBranches
- [x] ListDeploymentBranchPolicies
- [x] MergeBranch
- [x] RenameBranch
- [x] UpdateDeploymentBranchPolicy

## Tags
- [x] CreateGitTag
- [x] CreateTag
- [x] DeleteTag
- [x] GetGitTag
- [x] ListTags

## Git References
- [x] CreateRef
- [x] DeleteRef
- [x] GetTopReferralPaths
- [x] GetTopReferrers
- [x] ListMatchingRefs
- [x] ListRefs

## Organizations & Teams
- [x] AddTeamMember
- [x] CreateTeam
- [x] DeleteTeam
- [x] GetOrg
- [x] GetOrgActionsPermissions
- [x] GetOrgAllowedActions
- [x] GetOrgBillingUsage
- [x] GetOrgBillingUsageSummary
- [x] GetOrgBudget
- [x] GetOrgCacheUsage
- [x] GetOrgCacheUsageByRepo
- [x] GetOrgCodespacePublicKey
- [x] GetOrgCustomProperty
- [x] GetOrgDependabotPublicKey
- [x] GetOrgEnabledRepos
- [x] GetOrgHostedRunner
- [x] GetOrgInstallation
- [x] GetOrgInteractionLimits
- [x] GetOrgMembership
- [x] GetOrgMigration
- [x] GetOrgOIDCProperties
- [x] GetOrgOIDCSubjectClaim
- [x] GetOrgPackageVersion
- [x] GetOrgPublicKey
- [x] GetOrgRole
- [x] GetOrgRunner
- [x] GetOrgRunnerGroup
- [x] GetOrgVariable
- [x] GetOrgWebhook
- [x] ListOrgAdvisories
- [x] ListOrgBlockedUsers
- [x] ListOrgBudgets
- [x] ListOrgCodeScanningAlerts
- [x] ListOrgCodespaces
- [x] ListOrgCustomProperties
- [x] ListOrgDependabotAlerts
- [x] ListOrgHostedRunners
- [x] ListOrgInvitations
- [x] ListOrgMembers
- [x] ListOrgMigrationRepos
- [x] ListOrgMigrations
- [x] ListOrgPATRequests
- [x] ListOrgPATs
- [x] ListOrgProjectsV2
- [x] ListOrgRoles
- [x] ListOrgRunnerApplications
- [x] ListOrgRunnerGroups
- [x] ListOrgRunners
- [x] ListOrgs
- [x] ListOrgSecretScanningAlerts
- [x] ListOrgTeams
- [x] ListOrgVariables
- [x] ListOrgWebhooks
- [x] RemoveTeamMember
- [x] UpdateTeam

## Webhooks
- [x] CreateOrgWebhook
- [x] CreateWebhook
- [x] DeleteOrgWebhook
- [x] DeleteWebhook
- [x] GetAppWebhookConfig
- [x] GetAppWebhookDelivery
- [x] GetWebhookConfig
- [x] GetWebhookDelivery
- [x] ListAppWebhookDeliveries
- [x] ListWebhookDeliveries
- [x] PingOrgWebhook
- [x] PingWebhook
- [x] RedeliverAppWebhook
- [x] RedeliverWebhook
- [x] UpdateAppWebhookConfig
- [x] UpdateOrgWebhook
- [x] UpdateWebhook
- [x] UpdateWebhookConfig

## Stars & Watching
- [x] ListStargazers
- [x] ListWatchers
- [x] StarRepo
- [x] StartCall
- [x] StartCodespace
- [x] StartImport
- [x] StartOrgMigration
- [x] StartUserMigration
- [x] UnwatchRepo
- [x] WatchRepo

## Events & Feeds
- [x] GetFeeds
- [x] ListEvents
- [x] ListRepoEvents
- [x] ListUserEvents

## Discussions
- [x] AddDiscussionComment
- [x] CreateDiscussion
- [x] DeleteDiscussion
- [x] DeleteDiscussionComment
- [x] ListDiscussions
- [x] MarkDiscussionCommentAsAnswer
- [x] UpdateDiscussion
- [x] UpdateDiscussionComment

## Projects
- [x] AddProjectV2Item
- [x] CopyProjectV2
- [x] CreateProject
- [x] CreateProjectCard
- [x] CreateProjectV2DraftItem
- [x] CreateProjectV2View
- [x] DeleteProject
- [x] DeleteProjectV2
- [x] DeleteProjectV2Item
- [x] GetProjectV2
- [x] ListProjectColumns
- [x] ListProjects
- [x] ListProjectV2Fields
- [x] ListProjectV2Items
- [x] MoveProjectCard
- [x] UpdateProject
- [x] UpdateProjectV2
- [x] UpdateProjectV2Item

## Deployments
- [x] CancelPagesDeployment
- [x] CreateDeployment
- [x] CreateDeploymentProtectionRule
- [x] CreateDeploymentStatus
- [x] CreatePagesDeployment
- [x] GetPagesDeploymentStatus
- [x] GetPendingDeployments
- [x] ListDeploymentProtectionRuleApps
- [x] ListDeploymentProtectionRules
- [x] ListDeployments
- [x] ListDeploymentStatuses
- [x] ReviewPendingDeployments

## Repository Contents
- [x] CreateOrUpdateFileContents
- [x] DeleteFileContents
- [x] DeleteOrgMigrationArchive
- [x] DeleteUserMigrationArchive
- [x] DownloadFile
- [x] DownloadOrgMigrationArchive
- [x] DownloadUserMigrationArchive
- [x] GetArchiveLink
- [x] GetFileContents
- [x] ListImportLargeFiles
- [x] ListRepositoryTree
- [x] UploadFile

## Collaborators & Forks
- [x] AcceptInvitation
- [x] AddCollaborator
- [x] CancelOrgInvitation
- [x] ConvertToOutsideCollaborator
- [x] CreateOrgInvitation
- [x] CreatePrivateFork
- [x] DeclineInvitation
- [x] DeleteInvitation
- [x] ForkRepo
- [x] GetCollaboratorPermission
- [x] ListCollaborators
- [x] ListFailedInvitations
- [x] ListForks
- [x] ListInvitations
- [x] ListInvitationTeams
- [x] ListOutsideCollaborators
- [x] ListTeamInvitations
- [x] RemoveCollaborator
- [x] RemoveOutsideCollaborator
- [x] SyncForkWithUpstream
- [x] UpdateInvitation

## Security
- [x] CreateCodeScanningAutofix
- [x] DeleteCodeScanningAnalysis
- [x] GetCodeScanningAlert
- [x] GetCodeScanningAnalysis
- [x] GetCodeScanningAutofix
- [x] GetCodeScanningDefaultSetup
- [x] GetDependabotAlert
- [x] GetRepoDependabotPublicKey
- [x] GetSecretScanningAlert
- [x] ListCodeScanningAlertInstances
- [x] ListCodeScanningAlerts
- [x] ListCodeScanningAnalyses
- [x] ListDependabotAlerts
- [x] ListSecretScanningAlertLocations
- [x] ListSecretScanningAlerts
- [x] UpdateCodeScanningAlert
- [x] UpdateCodeScanningDefaultSetup
- [x] UpdateDependabotAlert
- [x] UpdateSecretScanningAlert

## GitHub Pages
- [x] CreatePagesSite
- [x] DeletePagesSite
- [x] GetLatestPagesBuild
- [x] GetPages
- [x] GetPagesBuild
- [x] GetPagesDNSHealth
- [x] ListPagesBuilds
- [x] UpdatePagesSite

## Packages
- [x] DeleteOrgPackageVersion
- [x] DeletePackage
- [x] DeleteUserPackageVersion
- [x] GetPackage
- [x] GetUserPackageVersion
- [x] ListPackages
- [x] ListPackageVersions
- [x] RestoreOrgPackage
- [x] RestoreOrgPackageVersion
- [x] RestoreUserPackage
- [x] RestoreUserPackageVersion

## SSH & GPG Keys
- [x] CreateGPGKey
- [x] CreateSSHKey
- [x] CreateSSHSigningKey
- [x] DeleteGPGKey
- [x] DeleteSSHKey
- [x] DeleteSSHSigningKey
- [x] GetSSHSigningKey
- [x] ListGPGKeys
- [x] ListSSHKeys
- [x] ListSSHSigningKeys

## Rulesets
- [x] CreateRuleset
- [x] DeleteRuleset
- [x] GetRuleset
- [x] GetRulesetHistory
- [x] GetRulesetVersion
- [x] ListRulesets
- [x] UpdateRuleset

## Autolinks
- [x] CreateAutolink
- [x] DeleteAutolink
- [x] ListAutolinks

## Environments
- [x] CreateEnvironmentVariable
- [x] CreateOrUpdateEnvironment
- [x] DeleteEnvironment
- [x] DeleteEnvironmentVariable
- [x] GetEnvironment
- [x] GetEnvironmentPublicKey
- [x] GetEnvironmentVariable
- [x] ListEnvironments
- [x] ListEnvironmentVariables
- [x] UpdateEnvironmentVariable

## Self-Hosted Runners
- [x] CreateJITRunnerConfig
- [x] CreateOrgHostedRunner
- [x] CreateOrgJITRunnerConfig
- [x] CreateOrgRunnerRegistrationToken
- [x] CreateOrgRunnerRemoveToken
- [x] CreateRunnerRegistrationToken
- [x] CreateRunnerRemoveToken
- [x] DeleteOrgHostedRunner
- [x] DeleteOrgRunner
- [x] DeleteRepoRunner
- [x] GetRepoRunner
- [x] ListRepoRunners
- [x] ListRunnerApplications
- [x] UpdateOrgHostedRunner

## Runner Groups
- [x] AddRunnerGroupRepo
- [x] AddRunnerGroupRunner
- [x] CreateOrgRunnerGroup
- [x] DeleteOrgRunnerGroup
- [x] ListRunnerGroupRepos
- [x] ListRunnerGroupRunners
- [x] RemoveRunnerGroupRepo
- [x] RemoveRunnerGroupRunner
- [x] SetRunnerGroupRepos
- [x] SetRunnerGroupRunners
- [x] UpdateOrgRunnerGroup

## Actions Permissions
- [x] AddOrgEnabledRepo
- [x] GetRepoActionsAccessSettings
- [x] GetRepoActionsPermissions
- [x] GetRepoAllowedActions
- [x] RemoveOrgEnabledRepo
- [x] SetOrgActionsPermissions
- [x] SetOrgAllowedActions
- [x] SetOrgEnabledRepos
- [x] SetRepoActionsAccessSettings
- [x] SetRepoActionsPermissions
- [x] SetRepoAllowedActions

## Emails
- [x] AddEmail
- [x] DeleteEmail
- [x] ListEmails
- [x] ListPublicEmails
- [x] SetEmailVisibility

## Social
- [x] AddSocialAccount
- [x] DeleteSocialAccount
- [x] GetUserHovercard
- [x] ListSocialAccounts

## Miscellaneous
- [x] CheckRateLimit
- [x] ListEmojis
- [x] RenderMarkdown

## User Profile
- [x] UpdateProfile

## Repositories
- [x] AddRepoToInstallation
- [x] AddTeamRepo
- [x] CreateRepoAdvisory
- [x] CreateRepoCodespace
- [x] CreateRepoFromTemplate
- [x] CreateRepositoryDispatch
- [x] CreateRepoVariable
- [x] DeleteRepo
- [x] DeleteRepoCacheByID
- [x] DeleteRepoCachesByKey
- [x] DeleteRepoVariable
- [x] GetRepoActivity
- [x] GetRepoAdvisory
- [x] GetRepoCacheUsage
- [x] GetRepoClones
- [x] GetRepoInstallation
- [x] GetRepoInteractionLimits
- [x] GetRepoLicense
- [x] GetRepoOIDCSubjectClaim
- [x] GetRepoPageViews
- [x] GetRepoREADME
- [x] GetRepoTopics
- [x] GetRepoVariable
- [x] ListInstallationRepos
- [x] ListRepoAdvisories
- [x] ListRepoAssignees
- [x] ListRepoCaches
- [x] ListRepoCodespaces
- [x] ListRepoLanguages
- [x] ListRepoTeams
- [x] ListRepoVariables
- [x] ListTeamRepos
- [x] ListUserInstallationRepos
- [x] ListUserMigrationRepos
- [x] RemoveRepoFromInstallation
- [x] RemoveRepoInteractionLimits
- [x] RemoveTeamRepo
- [x] ReportVulnerability
- [x] SetRepoInteractionLimits
- [x] SetRepoOIDCSubjectClaim
- [x] SetRepoTopics
- [x] TransferRepo
- [x] UnlockOrgMigrationRepo
- [x] UnlockUserMigrationRepo
- [x] UnstarRepo
- [x] UpdateRepoAdvisory
- [x] UpdateRepoVariable

## Queries & Info
- [x] GetAdminEnforcement
- [x] GetAPIRoot
- [x] GetAPIVersions
- [x] GetAppBySlug
- [x] GetAppInstallation
- [x] GetAssignment
- [x] GetAssignmentGrades
- [x] GetAuthenticatedApp
- [x] GetBlob
- [x] GetClassroom
- [x] GetCodeFrequencyStats
- [x] GetCodeOfConduct
- [x] GetCodeownersErrors
- [x] GetCodeQLDatabase
- [x] GetCodespace
- [x] GetCodespaceDefaults
- [x] GetCodespaceExport
- [x] GetCombinedStatus
- [x] GetCommunityProfile
- [x] GetContributorStats
- [x] GetCopilotMetrics
- [x] GetCopilotSeatInfo
- [x] GetCopilotTeamMetrics
- [x] GetCopilotUserSeat
- [x] GetCustomPropertyValues
- [x] GetDependencyDiff
- [x] GetDeployKey
- [x] GetDirREADME
- [x] GetGitignoreTemplate
- [x] GetGlobalAdvisory
- [x] GetImportStatus
- [x] GetLicense
- [x] GetMeta
- [x] GetParticipationStats
- [x] GetPunchCardStats
- [x] GetRequiredSignatures
- [x] GetRuleSuite
- [x] GetSARIFUpload
- [x] GetUserInstallation
- [x] GetUserInteractionLimits
- [x] GetUserMigration
- [x] GetUserOrgMembership

## Settings & Configuration
- [x] SetAdminEnforcement
- [x] SetCustomPropertyValues
- [x] SetOrgCodespacesAccess
- [x] SetOrgInteractionLimits
- [x] SetOrgMembership
- [x] SetOrgOIDCProperties
- [x] SetOrgOIDCSubjectClaim
- [x] SetRequiredSignatures
- [x] SetUserInteractionLimits

## Deletion
- [x] DeleteAppAuthorization
- [x] DeleteAppInstallation
- [x] DeleteAppToken
- [x] DeleteCodespace
- [x] DeleteDeployKey
- [x] DeleteOrgBudget
- [x] DeleteOrgCustomProperty
- [x] DeleteOrgVariable
- [x] RemoveAdminEnforcement
- [x] RemoveBlockingDependency
- [x] RemoveCodespacesAccessUsers
- [x] RemoveCopilotTeams
- [x] RemoveCopilotUsers
- [x] RemoveOrgInteractionLimits
- [x] RemoveOrgMembership
- [x] RemoveRequiredSignatures
- [x] RemoveSecurityManagerTeam
- [x] RemoveTeamRole
- [x] RemoveUserInteractionLimits
- [x] RemoveUserRole

## Creation
- [x] CreateAppFromManifest
- [x] CreateAttestation
- [x] CreateBlob
- [x] CreateDependencySnapshot
- [x] CreateDeployKey
- [x] CreateInstallationAccessToken
- [x] CreateOrgCustomProperties
- [x] CreateOrgVariable
- [x] CreateOrUpdateOrgCustomProperty
- [x] CreatePushProtectionBypass
- [x] CreateScopedAccessToken
- [x] CreateUserCodespace

## Listing
- [x] ListAcceptedAssignments
- [x] ListAppInstallations
- [x] ListAttestations
- [x] ListBlockingDependencies
- [x] ListChildTeams
- [x] ListClassroomAssignments
- [x] ListClassrooms
- [x] ListCodeQLDatabases
- [x] ListCodesOfConduct
- [x] ListCodespaceMachines
- [x] ListCodespaceMachineTypes
- [x] ListContributors
- [x] ListCopilotSeats
- [x] ListDeployKeys
- [x] ListDevContainerConfigs
- [x] ListGitignoreTemplates
- [x] ListGlobalAdvisories
- [x] ListImportAuthors
- [x] ListInstallationRequests
- [x] ListLicenses
- [x] ListPublicMembers
- [x] ListRuleSuites
- [x] ListSecurityManagers
- [x] ListTeamsForRole
- [x] ListUserCodespaces
- [x] ListUserInstallations
- [x] ListUserMigrations
- [x] ListUserOrgMemberships
- [x] ListUsersForRole
- [x] ListUserTeams

## Requests
- [x] RequestCVE

## Other
- [x] AddBlockingDependency
- [x] AddCodespacesAccessUsers
- [x] AddCopilotTeams
- [x] AddCopilotUsers
- [x] AddSecurityManagerTeam
- [x] AssignTeamRole
- [x] AssignUserRole
- [x] BlockOrgUser
- [x] CancelImport
- [x] ConcealMembership
- [x] DisableVulnerabilityAlerts
- [x] EnableVulnerabilityAlerts
- [x] ExportCodespace
- [x] ExportSBOM
- [x] MapImportAuthor
- [x] PublicizeMembership
- [x] PublishCodespace
- [x] RerunFailedJobs
- [x] ResetAppToken
- [x] ReviewOrgPATRequest
- [x] ReviewOrgPATRequests
- [x] RevokeInstallationAccessToken
- [x] StopCodespace
- [x] SuspendAppInstallation
- [x] UnblockOrgUser
- [x] UnsuspendAppInstallation
- [x] UpdateCodespace
- [x] UpdateImport
- [x] UpdateImportLFS
- [x] UpdateOrgBudget
- [x] UpdateOrgPAT
- [x] UpdateOrgPATs
- [x] UpdateOrgVariable
- [x] UploadSARIF
