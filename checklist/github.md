# GitHub — Full Protocol Surface Checklist

**Last updated:** 2026-04-13 (Step 3)
**Current:** 299 exported methods, ~4,254 lines. REST API v3 + GraphQL v4.
**Confirmed working:** 190 extended + 55 Core interface methods (all pass, Step 2).
**Full API surface:** ~1,112 endpoint-method combinations across 44 categories.
**Remaining:** ~800 endpoint-method combinations listed below.

Only methods NOT yet implemented are listed. All Core interface (55/55) and previously tested extended methods are omitted.

---

## Actions — Runners (~40 endpoints)

- [ ] ListRepoRunners — `GET /repos/{owner}/{repo}/actions/runners`
- [ ] ListRunnerApplications — `GET /repos/{owner}/{repo}/actions/runners/downloads`
- [ ] CreateJITRunnerConfig — `POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig`
- [ ] CreateRunnerRegistrationToken — `POST /repos/{owner}/{repo}/actions/runners/registration-token`
- [ ] CreateRunnerRemoveToken — `POST /repos/{owner}/{repo}/actions/runners/remove-token`
- [ ] GetRepoRunner — `GET /repos/{owner}/{repo}/actions/runners/{id}`
- [ ] DeleteRepoRunner — `DELETE /repos/{owner}/{repo}/actions/runners/{id}`
- [ ] ListRepoRunnerLabels — `GET /repos/{owner}/{repo}/actions/runners/{id}/labels`
- [ ] AddRepoRunnerLabels — `POST /repos/{owner}/{repo}/actions/runners/{id}/labels`
- [ ] SetRepoRunnerLabels — `PUT /repos/{owner}/{repo}/actions/runners/{id}/labels`
- [ ] RemoveRepoRunnerLabel — `DELETE /repos/{owner}/{repo}/actions/runners/{id}/labels/{name}`
- [ ] ListOrgRunners — `GET /orgs/{org}/actions/runners`
- [ ] ListOrgRunnerApplications — `GET /orgs/{org}/actions/runners/downloads`
- [ ] CreateOrgJITRunnerConfig — `POST /orgs/{org}/actions/runners/generate-jitconfig`
- [ ] CreateOrgRunnerRegistrationToken — `POST /orgs/{org}/actions/runners/registration-token`
- [ ] CreateOrgRunnerRemoveToken — `POST /orgs/{org}/actions/runners/remove-token`
- [ ] GetOrgRunner — `GET /orgs/{org}/actions/runners/{id}`
- [ ] DeleteOrgRunner — `DELETE /orgs/{org}/actions/runners/{id}`
- [ ] ListOrgRunnerLabels — `GET /orgs/{org}/actions/runners/{id}/labels`
- [ ] AddOrgRunnerLabels — `POST /orgs/{org}/actions/runners/{id}/labels`
- [ ] SetOrgRunnerLabels — `PUT /orgs/{org}/actions/runners/{id}/labels`
- [ ] RemoveOrgRunnerLabel — `DELETE /orgs/{org}/actions/runners/{id}/labels/{name}`

## Actions — Runner Groups (~16 endpoints)

- [ ] ListOrgRunnerGroups — `GET /orgs/{org}/actions/runner-groups`
- [ ] CreateOrgRunnerGroup — `POST /orgs/{org}/actions/runner-groups`
- [ ] GetOrgRunnerGroup — `GET /orgs/{org}/actions/runner-groups/{id}`
- [ ] UpdateOrgRunnerGroup — `PATCH /orgs/{org}/actions/runner-groups/{id}`
- [ ] DeleteOrgRunnerGroup — `DELETE /orgs/{org}/actions/runner-groups/{id}`
- [ ] ListRunnerGroupRepos — `GET /orgs/{org}/actions/runner-groups/{id}/repositories`
- [ ] SetRunnerGroupRepos — `PUT /orgs/{org}/actions/runner-groups/{id}/repositories`
- [ ] AddRunnerGroupRepo — `PUT /orgs/{org}/actions/runner-groups/{id}/repositories/{repo_id}`
- [ ] RemoveRunnerGroupRepo — `DELETE /orgs/{org}/actions/runner-groups/{id}/repositories/{repo_id}`
- [ ] ListRunnerGroupRunners — `GET /orgs/{org}/actions/runner-groups/{id}/runners`
- [ ] SetRunnerGroupRunners — `PUT /orgs/{org}/actions/runner-groups/{id}/runners`
- [ ] AddRunnerGroupRunner — `PUT /orgs/{org}/actions/runner-groups/{id}/runners/{runner_id}`
- [ ] RemoveRunnerGroupRunner — `DELETE /orgs/{org}/actions/runner-groups/{id}/runners/{runner_id}`

## Actions — Hosted Runners (~14 endpoints)

- [ ] ListOrgHostedRunners — `GET /orgs/{org}/actions/hosted-runners`
- [ ] CreateOrgHostedRunner — `POST /orgs/{org}/actions/hosted-runners`
- [ ] GetOrgHostedRunner — `GET /orgs/{org}/actions/hosted-runners/{id}`
- [ ] UpdateOrgHostedRunner — `PATCH /orgs/{org}/actions/hosted-runners/{id}`
- [ ] DeleteOrgHostedRunner — `DELETE /orgs/{org}/actions/hosted-runners/{id}`
- [ ] ListHostedRunnerCustomImages — `GET /orgs/{org}/actions/hosted-runners/images/custom`
- [ ] ListHostedRunnerGitHubImages — `GET /orgs/{org}/actions/hosted-runners/images/github-owned`
- [ ] ListHostedRunnerPartnerImages — `GET /orgs/{org}/actions/hosted-runners/images/partner`
- [ ] GetHostedRunnerLimits — `GET /orgs/{org}/actions/hosted-runners/limits`
- [ ] ListHostedRunnerMachineSizes — `GET /orgs/{org}/actions/hosted-runners/machine-sizes`
- [ ] ListHostedRunnerPlatforms — `GET /orgs/{org}/actions/hosted-runners/platforms`

## Actions — Permissions (~30 endpoints)

- [ ] GetOrgActionsPermissions — `GET /orgs/{org}/actions/permissions`
- [ ] SetOrgActionsPermissions — `PUT /orgs/{org}/actions/permissions`
- [ ] GetOrgArtifactRetention — `GET /orgs/{org}/actions/permissions/artifact-and-log-retention`
- [ ] SetOrgArtifactRetention — `PUT /orgs/{org}/actions/permissions/artifact-and-log-retention`
- [ ] GetOrgForkPRApproval — `GET /orgs/{org}/actions/permissions/fork-pr-contributor-approval`
- [ ] SetOrgForkPRApproval — `PUT /orgs/{org}/actions/permissions/fork-pr-contributor-approval`
- [ ] GetOrgEnabledRepos — `GET /orgs/{org}/actions/permissions/repositories`
- [ ] SetOrgEnabledRepos — `PUT /orgs/{org}/actions/permissions/repositories`
- [ ] AddOrgEnabledRepo — `PUT /orgs/{org}/actions/permissions/repositories/{repo_id}`
- [ ] RemoveOrgEnabledRepo — `DELETE /orgs/{org}/actions/permissions/repositories/{repo_id}`
- [ ] GetOrgAllowedActions — `GET /orgs/{org}/actions/permissions/selected-actions`
- [ ] SetOrgAllowedActions — `PUT /orgs/{org}/actions/permissions/selected-actions`
- [ ] GetOrgDefaultWorkflowPermissions — `GET /orgs/{org}/actions/permissions/workflow`
- [ ] SetOrgDefaultWorkflowPermissions — `PUT /orgs/{org}/actions/permissions/workflow`
- [ ] GetRepoActionsPermissions — `GET /repos/{owner}/{repo}/actions/permissions`
- [ ] SetRepoActionsPermissions — `PUT /repos/{owner}/{repo}/actions/permissions`
- [ ] GetRepoActionsAccessSettings — `GET /repos/{owner}/{repo}/actions/permissions/access`
- [ ] SetRepoActionsAccessSettings — `PUT /repos/{owner}/{repo}/actions/permissions/access`
- [ ] GetRepoAllowedActions — `GET /repos/{owner}/{repo}/actions/permissions/selected-actions`
- [ ] SetRepoAllowedActions — `PUT /repos/{owner}/{repo}/actions/permissions/selected-actions`
- [ ] GetRepoDefaultWorkflowPermissions — `GET /repos/{owner}/{repo}/actions/permissions/workflow`
- [ ] SetRepoDefaultWorkflowPermissions — `PUT /repos/{owner}/{repo}/actions/permissions/workflow`

## Actions — Variables (~10 endpoints)

- [ ] ListRepoVariables — `GET /repos/{owner}/{repo}/actions/variables`
- [ ] CreateRepoVariable — `POST /repos/{owner}/{repo}/actions/variables`
- [ ] GetRepoVariable — `GET /repos/{owner}/{repo}/actions/variables/{name}`
- [ ] UpdateRepoVariable — `PATCH /repos/{owner}/{repo}/actions/variables/{name}`
- [ ] DeleteRepoVariable — `DELETE /repos/{owner}/{repo}/actions/variables/{name}`
- [ ] ListOrgVariables — `GET /orgs/{org}/actions/variables`
- [ ] CreateOrgVariable — `POST /orgs/{org}/actions/variables`
- [ ] GetOrgVariable — `GET /orgs/{org}/actions/variables/{name}`
- [ ] UpdateOrgVariable — `PATCH /orgs/{org}/actions/variables/{name}`
- [ ] DeleteOrgVariable — `DELETE /orgs/{org}/actions/variables/{name}`

## Actions — Org Secrets (~8 endpoints)

- [ ] ListOrgSecrets — `GET /orgs/{org}/actions/secrets`
- [ ] GetOrgPublicKey — `GET /orgs/{org}/actions/secrets/public-key`
- [ ] GetOrgSecret — `GET /orgs/{org}/actions/secrets/{name}`
- [ ] CreateOrUpdateOrgSecret — `PUT /orgs/{org}/actions/secrets/{name}`
- [ ] DeleteOrgSecret — `DELETE /orgs/{org}/actions/secrets/{name}`
- [ ] ListOrgSecretRepos — `GET /orgs/{org}/actions/secrets/{name}/repositories`
- [ ] SetOrgSecretRepos — `PUT /orgs/{org}/actions/secrets/{name}/repositories`
- [ ] AddOrgSecretRepo — `PUT /orgs/{org}/actions/secrets/{name}/repositories/{repo_id}`
- [ ] RemoveOrgSecretRepo — `DELETE /orgs/{org}/actions/secrets/{name}/repositories/{repo_id}`

## Actions — Caches (~10 endpoints)

- [ ] GetRepoCacheUsage — `GET /repos/{owner}/{repo}/actions/cache/usage`
- [ ] ListRepoCaches — `GET /repos/{owner}/{repo}/actions/caches`
- [ ] DeleteRepoCachesByKey — `DELETE /repos/{owner}/{repo}/actions/caches` (by key query)
- [ ] DeleteRepoCacheByID — `DELETE /repos/{owner}/{repo}/actions/caches/{cache_id}`
- [ ] GetOrgCacheUsage — `GET /orgs/{org}/actions/cache/usage`
- [ ] GetOrgCacheUsageByRepo — `GET /orgs/{org}/actions/cache/usage-by-repository`

## Actions — Workflow Runs Details (~20 endpoints)

- [ ] GetWorkflowRunApprovals — `GET /repos/{owner}/{repo}/actions/runs/{id}/approvals`
- [ ] ApproveWorkflowRun — `POST /repos/{owner}/{repo}/actions/runs/{id}/approve`
- [ ] GetWorkflowRunAttempt — `GET /repos/{owner}/{repo}/actions/runs/{id}/attempts/{n}`
- [ ] ListWorkflowRunAttemptJobs — `GET /repos/{owner}/{repo}/actions/runs/{id}/attempts/{n}/jobs`
- [ ] DownloadWorkflowRunAttemptLogs — `GET /repos/{owner}/{repo}/actions/runs/{id}/attempts/{n}/logs`
- [ ] ForceCancelWorkflowRun — `POST /repos/{owner}/{repo}/actions/runs/{id}/force-cancel`
- [ ] ListWorkflowRunJobs — `GET /repos/{owner}/{repo}/actions/runs/{id}/jobs`
- [ ] DownloadWorkflowRunLogs — `GET /repos/{owner}/{repo}/actions/runs/{id}/logs`
- [ ] DeleteWorkflowRunLogs — `DELETE /repos/{owner}/{repo}/actions/runs/{id}/logs`
- [ ] GetPendingDeployments — `GET /repos/{owner}/{repo}/actions/runs/{id}/pending_deployments`
- [ ] ReviewPendingDeployments — `POST /repos/{owner}/{repo}/actions/runs/{id}/pending_deployments`
- [ ] RerunFailedJobs — `POST /repos/{owner}/{repo}/actions/runs/{id}/rerun-failed-jobs`
- [ ] GetWorkflowRunTiming — `GET /repos/{owner}/{repo}/actions/runs/{id}/timing`
- [ ] DeleteWorkflowRun — `DELETE /repos/{owner}/{repo}/actions/runs/{id}`
- [ ] GetWorkflowJob — `GET /repos/{owner}/{repo}/actions/jobs/{job_id}`
- [ ] DownloadWorkflowJobLogs — `GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs`
- [ ] RerunWorkflowJob — `POST /repos/{owner}/{repo}/actions/jobs/{job_id}/rerun`

## Actions — Workflow Management (~7 endpoints)

- [ ] GetWorkflow — `GET /repos/{owner}/{repo}/actions/workflows/{id}`
- [ ] DisableWorkflow — `PUT /repos/{owner}/{repo}/actions/workflows/{id}/disable`
- [ ] EnableWorkflow — `PUT /repos/{owner}/{repo}/actions/workflows/{id}/enable`
- [ ] CreateWorkflowDispatch — `POST /repos/{owner}/{repo}/actions/workflows/{id}/dispatches`
- [ ] GetWorkflowTiming — `GET /repos/{owner}/{repo}/actions/workflows/{id}/timing`

## Actions — Environment Secrets & Variables (~10 endpoints)

- [ ] ListEnvironmentSecrets — `GET /repos/{owner}/{repo}/environments/{env}/secrets`
- [ ] GetEnvironmentPublicKey — `GET /repos/{owner}/{repo}/environments/{env}/secrets/public-key`
- [ ] GetEnvironmentSecret — `GET /repos/{owner}/{repo}/environments/{env}/secrets/{name}`
- [ ] CreateOrUpdateEnvironmentSecret — `PUT /repos/{owner}/{repo}/environments/{env}/secrets/{name}`
- [ ] DeleteEnvironmentSecret — `DELETE /repos/{owner}/{repo}/environments/{env}/secrets/{name}`
- [ ] ListEnvironmentVariables — `GET /repos/{owner}/{repo}/environments/{env}/variables`
- [ ] CreateEnvironmentVariable — `POST /repos/{owner}/{repo}/environments/{env}/variables`
- [ ] GetEnvironmentVariable — `GET /repos/{owner}/{repo}/environments/{env}/variables/{name}`
- [ ] UpdateEnvironmentVariable — `PATCH /repos/{owner}/{repo}/environments/{env}/variables/{name}`
- [ ] DeleteEnvironmentVariable — `DELETE /repos/{owner}/{repo}/environments/{env}/variables/{name}`

## Actions — OIDC (~2 endpoints)

- [ ] GetRepoOIDCSubjectClaim — `GET /repos/{owner}/{repo}/actions/oidc/customization/sub`
- [ ] SetRepoOIDCSubjectClaim — `PUT /repos/{owner}/{repo}/actions/oidc/customization/sub`

## GitHub Apps (37 endpoints)

- [ ] GetAuthenticatedApp — `GET /app`
- [ ] CreateAppFromManifest — `POST /app-manifests/{code}/conversions`
- [ ] GetAppWebhookConfig — `GET /app/hook/config`
- [ ] UpdateAppWebhookConfig — `PATCH /app/hook/config`
- [ ] ListAppWebhookDeliveries — `GET /app/hook/deliveries`
- [ ] GetAppWebhookDelivery — `GET /app/hook/deliveries/{delivery_id}`
- [ ] RedeliverAppWebhook — `POST /app/hook/deliveries/{delivery_id}/attempts`
- [ ] ListInstallationRequests — `GET /app/installation-requests`
- [ ] ListAppInstallations — `GET /app/installations`
- [ ] GetAppInstallation — `GET /app/installations/{id}`
- [ ] DeleteAppInstallation — `DELETE /app/installations/{id}`
- [ ] CreateInstallationAccessToken — `POST /app/installations/{id}/access_tokens`
- [ ] SuspendAppInstallation — `PUT /app/installations/{id}/suspended`
- [ ] UnsuspendAppInstallation — `DELETE /app/installations/{id}/suspended`
- [ ] DeleteAppAuthorization — `DELETE /applications/{client_id}/grant`
- [ ] CheckAppToken — `POST /applications/{client_id}/token`
- [ ] ResetAppToken — `PATCH /applications/{client_id}/token`
- [ ] DeleteAppToken — `DELETE /applications/{client_id}/token`
- [ ] CreateScopedAccessToken — `POST /applications/{client_id}/token/scoped`
- [ ] GetAppBySlug — `GET /apps/{app_slug}`
- [ ] ListInstallationRepos — `GET /installation/repositories`
- [ ] RevokeInstallationAccessToken — `DELETE /installation/token`
- [ ] GetMarketplaceSubscription — `GET /marketplace_listing/accounts/{account_id}`
- [ ] ListMarketplacePlans — `GET /marketplace_listing/plans`
- [ ] ListMarketplacePlanAccounts — `GET /marketplace_listing/plans/{plan_id}/accounts`
- [ ] GetOrgInstallation — `GET /orgs/{org}/installation`
- [ ] GetRepoInstallation — `GET /repos/{owner}/{repo}/installation`
- [ ] ListUserInstallations — `GET /user/installations`
- [ ] ListUserInstallationRepos — `GET /user/installations/{id}/repositories`
- [ ] AddRepoToInstallation — `PUT /user/installations/{id}/repositories/{repo_id}`
- [ ] RemoveRepoFromInstallation — `DELETE /user/installations/{id}/repositories/{repo_id}`
- [ ] ListUserMarketplacePurchases — `GET /user/marketplace_purchases`
- [ ] GetUserInstallation — `GET /users/{username}/installation`

## Repos — Collaborators (5 endpoints)

- [ ] ListCollaborators — `GET /repos/{owner}/{repo}/collaborators`
- [ ] CheckCollaborator — `GET /repos/{owner}/{repo}/collaborators/{username}`
- [ ] AddCollaborator — `PUT /repos/{owner}/{repo}/collaborators/{username}`
- [ ] RemoveCollaborator — `DELETE /repos/{owner}/{repo}/collaborators/{username}`

## Repos — Deploy Keys (4 endpoints)

- [ ] ListDeployKeys — `GET /repos/{owner}/{repo}/keys`
- [ ] CreateDeployKey — `POST /repos/{owner}/{repo}/keys`
- [ ] GetDeployKey — `GET /repos/{owner}/{repo}/keys/{key_id}`
- [ ] DeleteDeployKey — `DELETE /repos/{owner}/{repo}/keys/{key_id}`

## Repos — Statistics (5 endpoints)

- [ ] GetCodeFrequencyStats — `GET /repos/{owner}/{repo}/stats/code_frequency`
- [ ] GetCommitActivityStats — `GET /repos/{owner}/{repo}/stats/commit_activity`
- [ ] GetContributorStats — `GET /repos/{owner}/{repo}/stats/contributors`
- [ ] GetParticipationStats — `GET /repos/{owner}/{repo}/stats/participation`
- [ ] GetPunchCardStats — `GET /repos/{owner}/{repo}/stats/punch_card`

## Repos — Traffic (4 endpoints)

- [ ] GetRepoClones — `GET /repos/{owner}/{repo}/traffic/clones`
- [ ] GetTopReferralPaths — `GET /repos/{owner}/{repo}/traffic/popular/paths`
- [ ] GetTopReferrers — `GET /repos/{owner}/{repo}/traffic/popular/referrers`
- [ ] GetRepoPageViews — `GET /repos/{owner}/{repo}/traffic/views`

## Repos — Community & README (3 endpoints)

- [ ] GetCommunityProfile — `GET /repos/{owner}/{repo}/community/profile`
- [ ] GetRepoREADME — `GET /repos/{owner}/{repo}/readme`
- [ ] GetDirREADME — `GET /repos/{owner}/{repo}/readme/{dir}`

## Repos — Git Objects (7 endpoints)

- [ ] CreateBlob — `POST /repos/{owner}/{repo}/git/blobs`
- [ ] GetBlob — `GET /repos/{owner}/{repo}/git/blobs/{sha}`
- [ ] CreateGitCommit — `POST /repos/{owner}/{repo}/git/commits`
- [ ] GetGitCommit — `GET /repos/{owner}/{repo}/git/commits/{sha}`
- [ ] ListMatchingRefs — `GET /repos/{owner}/{repo}/git/matching-refs/{ref}`
- [ ] CreateGitTag — `POST /repos/{owner}/{repo}/git/tags`
- [ ] GetGitTag — `GET /repos/{owner}/{repo}/git/tags/{sha}`

## Repos — Misc Missing (~20 endpoints)

- [ ] GetCodeownersErrors — `GET /repos/{owner}/{repo}/codeowners/errors`
- [ ] ListRepoLanguages — `GET /repos/{owner}/{repo}/languages`
- [ ] ListRepoTeams — `GET /repos/{owner}/{repo}/teams`
- [ ] DownloadTarArchive — `GET /repos/{owner}/{repo}/tarball/{ref}`
- [ ] DownloadZipArchive — `GET /repos/{owner}/{repo}/zipball/{ref}`
- [ ] CreateRepoFromTemplate — `POST /repos/{template_owner}/{template_repo}/generate`
- [ ] CreateRepositoryDispatch — `POST /repos/{owner}/{repo}/dispatches`
- [ ] SyncForkWithUpstream — `POST /repos/{owner}/{repo}/merge-upstream`
- [ ] MergeBranch — `POST /repos/{owner}/{repo}/merges`
- [ ] CheckVulnerabilityAlerts — `GET /repos/{owner}/{repo}/vulnerability-alerts`
- [ ] EnableVulnerabilityAlerts — `PUT /repos/{owner}/{repo}/vulnerability-alerts`
- [ ] DisableVulnerabilityAlerts — `DELETE /repos/{owner}/{repo}/vulnerability-alerts`
- [ ] GetCustomPropertyValues — `GET /repos/{owner}/{repo}/properties/values`
- [ ] SetCustomPropertyValues — `PATCH /repos/{owner}/{repo}/properties/values`
- [ ] CreateAttestation — `POST /repos/{owner}/{repo}/attestations`
- [ ] ListAttestations — `GET /repos/{owner}/{repo}/attestations/{subject_digest}`
- [ ] GetLatestRelease — `GET /repos/{owner}/{repo}/releases/latest`
- [ ] GetReleaseByTag — `GET /repos/{owner}/{repo}/releases/tags/{tag}`
- [ ] GenerateReleaseNotes — `POST /repos/{owner}/{repo}/releases/generate-notes`
- [ ] GetReleaseAsset — `GET /repos/{owner}/{repo}/releases/assets/{asset_id}`
- [ ] UpdateReleaseAsset — `PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}`
- [ ] DeleteReleaseAsset — `DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}`

## Repos — Branch Protection Details (~20 endpoints)

- [ ] GetAdminEnforcement — `GET /repos/{owner}/{repo}/branches/{branch}/protection/enforce_admins`
- [ ] SetAdminEnforcement — `POST /repos/{owner}/{repo}/branches/{branch}/protection/enforce_admins`
- [ ] RemoveAdminEnforcement — `DELETE /repos/{owner}/{repo}/branches/{branch}/protection/enforce_admins`
- [ ] GetRequiredPRReviews — `GET /repos/{owner}/{repo}/branches/{branch}/protection/required_pull_request_reviews`
- [ ] UpdateRequiredPRReviews — `PATCH /repos/{owner}/{repo}/branches/{branch}/protection/required_pull_request_reviews`
- [ ] RemoveRequiredPRReviews — `DELETE /repos/{owner}/{repo}/branches/{branch}/protection/required_pull_request_reviews`
- [ ] GetRequiredSignatures — `GET /repos/{owner}/{repo}/branches/{branch}/protection/required_signatures`
- [ ] SetRequiredSignatures — `POST /repos/{owner}/{repo}/branches/{branch}/protection/required_signatures`
- [ ] RemoveRequiredSignatures — `DELETE /repos/{owner}/{repo}/branches/{branch}/protection/required_signatures`
- [ ] GetRequiredStatusChecks — `GET /repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks`
- [ ] UpdateRequiredStatusChecks — `PATCH /repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks`
- [ ] RemoveRequiredStatusChecks — `DELETE /repos/{owner}/{repo}/branches/{branch}/protection/required_status_checks`
- [ ] GetBranchRestrictions — `GET /repos/{owner}/{repo}/branches/{branch}/protection/restrictions`
- [ ] DeleteBranchRestrictions — `DELETE /repos/{owner}/{repo}/branches/{branch}/protection/restrictions`

## Repos — Pages Extras (8 endpoints)

- [ ] UpdatePagesSite — `PUT /repos/{owner}/{repo}/pages`
- [ ] DeletePagesSite — `DELETE /repos/{owner}/{repo}/pages`
- [ ] GetLatestPagesBuild — `GET /repos/{owner}/{repo}/pages/builds/latest`
- [ ] GetPagesBuild — `GET /repos/{owner}/{repo}/pages/builds/{build_id}`
- [ ] CreatePagesDeployment — `POST /repos/{owner}/{repo}/pages/deployments`
- [ ] GetPagesDeploymentStatus — `GET /repos/{owner}/{repo}/pages/deployments/{id}`
- [ ] CancelPagesDeployment — `POST /repos/{owner}/{repo}/pages/deployments/{id}/cancel`
- [ ] GetPagesDNSHealth — `GET /repos/{owner}/{repo}/pages/health`

## Repos — Webhook Extras (5 endpoints)

- [ ] ListWebhookDeliveries — `GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries`
- [ ] GetWebhookDelivery — `GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{id}`
- [ ] RedeliverWebhook — `POST /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{id}/attempts`
- [ ] GetWebhookConfig — `GET /repos/{owner}/{repo}/hooks/{hook_id}/config`
- [ ] UpdateWebhookConfig — `PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config`

## Repos — Ruleset Extras (5 endpoints)

- [ ] ListRuleSuites — `GET /repos/{owner}/{repo}/rulesets/rule-suites`
- [ ] GetRuleSuite — `GET /repos/{owner}/{repo}/rulesets/rule-suites/{id}`
- [ ] GetRulesetHistory — `GET /repos/{owner}/{repo}/rulesets/{id}/history`
- [ ] GetRulesetVersion — `GET /repos/{owner}/{repo}/rulesets/{id}/history/{version_id}`
- [ ] GetBranchRules — `GET /repos/{owner}/{repo}/rules/branches/{branch}`

## Repos — Commits Extras (3 endpoints)

- [ ] ListBranchesForHEADCommit — `GET /repos/{owner}/{repo}/commits/{sha}/branches-where-head`
- [ ] ListPRsForCommit — `GET /repos/{owner}/{repo}/commits/{sha}/pulls`
- [ ] GetCombinedStatus — `GET /repos/{owner}/{repo}/commits/{ref}/status`

## Repos — Environment Deployment Policies (~8 endpoints)

- [ ] ListDeploymentBranchPolicies — `GET /repos/{owner}/{repo}/environments/{env}/deployment-branch-policies`
- [ ] CreateDeploymentBranchPolicy — `POST /repos/{owner}/{repo}/environments/{env}/deployment-branch-policies`
- [ ] GetDeploymentBranchPolicy — `GET /repos/{owner}/{repo}/environments/{env}/deployment-branch-policies/{id}`
- [ ] UpdateDeploymentBranchPolicy — `PUT /repos/{owner}/{repo}/environments/{env}/deployment-branch-policies/{id}`
- [ ] DeleteDeploymentBranchPolicy — `DELETE /repos/{owner}/{repo}/environments/{env}/deployment-branch-policies/{id}`
- [ ] ListDeploymentProtectionRules — `GET /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules`
- [ ] CreateDeploymentProtectionRule — `POST /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules`
- [ ] ListDeploymentProtectionRuleApps — `GET /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules/apps`

## Pull Requests — Missing (~11 endpoints)

- [ ] CreatePRCommentReply — `POST /repos/{owner}/{repo}/pulls/{number}/comments/{id}/replies`
- [ ] ListPRCommits — `GET /repos/{owner}/{repo}/pulls/{number}/commits`
- [ ] ListPRFiles — `GET /repos/{owner}/{repo}/pulls/{number}/files`
- [ ] CheckPRMerged — `GET /repos/{owner}/{repo}/pulls/{number}/merge`
- [ ] GetRequestedReviewers — `GET /repos/{owner}/{repo}/pulls/{number}/requested_reviewers`
- [ ] RemoveRequestedReviewers — `DELETE /repos/{owner}/{repo}/pulls/{number}/requested_reviewers`
- [ ] GetPRReview — `GET /repos/{owner}/{repo}/pulls/{number}/reviews/{id}`
- [ ] UpdatePRReview — `PUT /repos/{owner}/{repo}/pulls/{number}/reviews/{id}`
- [ ] DeletePendingPRReview — `DELETE /repos/{owner}/{repo}/pulls/{number}/reviews/{id}`
- [ ] ListPRReviewComments — `GET /repos/{owner}/{repo}/pulls/{number}/reviews/{id}/comments`
- [ ] UpdatePRBranch — `PUT /repos/{owner}/{repo}/pulls/{number}/update-branch`

## Issues — Missing (~20 endpoints)

- [ ] ListRepoIssueEvents — `GET /repos/{owner}/{repo}/issues/events`
- [ ] GetIssueEvent — `GET /repos/{owner}/{repo}/issues/events/{event_id}`
- [ ] AddIssueAssignees — `POST /repos/{owner}/{repo}/issues/{number}/assignees`
- [ ] RemoveIssueAssignees — `DELETE /repos/{owner}/{repo}/issues/{number}/assignees`
- [ ] ListRepoAssignees — `GET /repos/{owner}/{repo}/assignees`
- [ ] CheckAssignable — `GET /repos/{owner}/{repo}/assignees/{assignee}`
- [ ] GetParentIssue — `GET /repos/{owner}/{repo}/issues/{number}/parent`
- [ ] RemoveSubIssue — `DELETE /repos/{owner}/{repo}/issues/{number}/sub_issue`
- [ ] ReprioritizeSubIssue — `PATCH /repos/{owner}/{repo}/issues/{number}/sub_issues/priority`
- [ ] ListBlockingDependencies — `GET /repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by`
- [ ] AddBlockingDependency — `POST /repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by`
- [ ] RemoveBlockingDependency — `DELETE /repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by/{id}`
- [ ] ListAuthenticatedUserIssues — `GET /issues`
- [ ] ListOrgIssues — `GET /orgs/{org}/issues`
- [ ] ListMilestoneLabels — `GET /repos/{owner}/{repo}/milestones/{number}/labels`

## Codespaces (48 endpoints)

- [ ] ListOrgCodespaces — `GET /orgs/{org}/codespaces`
- [ ] SetOrgCodespacesAccess — `PUT /orgs/{org}/codespaces/access`
- [ ] AddCodespacesAccessUsers — `POST /orgs/{org}/codespaces/access/selected_users`
- [ ] RemoveCodespacesAccessUsers — `DELETE /orgs/{org}/codespaces/access/selected_users`
- [ ] ListOrgCodespaceSecrets — `GET /orgs/{org}/codespaces/secrets`
- [ ] GetOrgCodespacePublicKey — `GET /orgs/{org}/codespaces/secrets/public-key`
- [ ] GetOrgCodespaceSecret — `GET /orgs/{org}/codespaces/secrets/{name}`
- [ ] CreateOrUpdateOrgCodespaceSecret — `PUT /orgs/{org}/codespaces/secrets/{name}`
- [ ] DeleteOrgCodespaceSecret — `DELETE /orgs/{org}/codespaces/secrets/{name}`
- [ ] ListRepoCodespaces — `GET /repos/{owner}/{repo}/codespaces`
- [ ] CreateRepoCodespace — `POST /repos/{owner}/{repo}/codespaces`
- [ ] ListDevContainerConfigs — `GET /repos/{owner}/{repo}/codespaces/devcontainers`
- [ ] ListCodespaceMachineTypes — `GET /repos/{owner}/{repo}/codespaces/machines`
- [ ] GetCodespaceDefaults — `GET /repos/{owner}/{repo}/codespaces/new`
- [ ] CheckDevContainerPermissions — `GET /repos/{owner}/{repo}/codespaces/permissions_check`
- [ ] CreateCodespaceFromPR — `POST /repos/{owner}/{repo}/pulls/{number}/codespaces`
- [ ] ListUserCodespaces — `GET /user/codespaces`
- [ ] CreateUserCodespace — `POST /user/codespaces`
- [ ] GetCodespace — `GET /user/codespaces/{name}`
- [ ] UpdateCodespace — `PATCH /user/codespaces/{name}`
- [ ] DeleteCodespace — `DELETE /user/codespaces/{name}`
- [ ] ExportCodespace — `POST /user/codespaces/{name}/exports`
- [ ] GetCodespaceExport — `GET /user/codespaces/{name}/exports/{export_id}`
- [ ] ListCodespaceMachines — `GET /user/codespaces/{name}/machines`
- [ ] PublishCodespace — `POST /user/codespaces/{name}/publish`
- [ ] StartCodespace — `POST /user/codespaces/{name}/start`
- [ ] StopCodespace — `POST /user/codespaces/{name}/stop`

## Copilot (25 endpoints)

- [ ] GetCopilotSeatInfo — `GET /orgs/{org}/copilot/billing`
- [ ] ListCopilotSeats — `GET /orgs/{org}/copilot/billing/seats`
- [ ] AddCopilotTeams — `POST /orgs/{org}/copilot/billing/selected_teams`
- [ ] RemoveCopilotTeams — `DELETE /orgs/{org}/copilot/billing/selected_teams`
- [ ] AddCopilotUsers — `POST /orgs/{org}/copilot/billing/selected_users`
- [ ] RemoveCopilotUsers — `DELETE /orgs/{org}/copilot/billing/selected_users`
- [ ] GetCopilotMetrics — `GET /orgs/{org}/copilot/metrics`
- [ ] GetCopilotUserSeat — `GET /orgs/{org}/members/{username}/copilot`
- [ ] GetCopilotTeamMetrics — `GET /orgs/{org}/team/{team_slug}/copilot/metrics`

## Migrations (22 endpoints)

- [ ] ListOrgMigrations — `GET /orgs/{org}/migrations`
- [ ] StartOrgMigration — `POST /orgs/{org}/migrations`
- [ ] GetOrgMigration — `GET /orgs/{org}/migrations/{id}`
- [ ] DownloadOrgMigrationArchive — `GET /orgs/{org}/migrations/{id}/archive`
- [ ] DeleteOrgMigrationArchive — `DELETE /orgs/{org}/migrations/{id}/archive`
- [ ] UnlockOrgMigrationRepo — `DELETE /orgs/{org}/migrations/{id}/repos/{repo_name}/lock`
- [ ] ListOrgMigrationRepos — `GET /orgs/{org}/migrations/{id}/repositories`
- [ ] GetImportStatus — `GET /repos/{owner}/{repo}/import`
- [ ] StartImport — `PUT /repos/{owner}/{repo}/import`
- [ ] UpdateImport — `PATCH /repos/{owner}/{repo}/import`
- [ ] CancelImport — `DELETE /repos/{owner}/{repo}/import`
- [ ] ListImportAuthors — `GET /repos/{owner}/{repo}/import/authors`
- [ ] MapImportAuthor — `PATCH /repos/{owner}/{repo}/import/authors/{id}`
- [ ] ListImportLargeFiles — `GET /repos/{owner}/{repo}/import/large_files`
- [ ] UpdateImportLFS — `PATCH /repos/{owner}/{repo}/import/lfs`
- [ ] ListUserMigrations — `GET /user/migrations`
- [ ] StartUserMigration — `POST /user/migrations`
- [ ] GetUserMigration — `GET /user/migrations/{id}`
- [ ] DownloadUserMigrationArchive — `GET /user/migrations/{id}/archive`
- [ ] DeleteUserMigrationArchive — `DELETE /user/migrations/{id}/archive`
- [ ] UnlockUserMigrationRepo — `DELETE /user/migrations/{id}/repos/{repo_name}/lock`
- [ ] ListUserMigrationRepos — `GET /user/migrations/{id}/repositories`

## Reactions (15 endpoints)

- [ ] ListCommitCommentReactions — `GET /repos/{owner}/{repo}/comments/{id}/reactions`
- [ ] CreateCommitCommentReaction — `POST /repos/{owner}/{repo}/comments/{id}/reactions`
- [ ] DeleteCommitCommentReaction — `DELETE /repos/{owner}/{repo}/comments/{id}/reactions/{id}`
- [ ] ListIssueCommentReactions — `GET /repos/{owner}/{repo}/issues/comments/{id}/reactions`
- [ ] CreateIssueCommentReaction — `POST /repos/{owner}/{repo}/issues/comments/{id}/reactions`
- [ ] DeleteIssueCommentReaction — `DELETE /repos/{owner}/{repo}/issues/comments/{id}/reactions/{id}`
- [ ] ListIssueReactions — `GET /repos/{owner}/{repo}/issues/{number}/reactions`
- [ ] CreateIssueReaction — `POST /repos/{owner}/{repo}/issues/{number}/reactions`
- [ ] DeleteIssueReaction — `DELETE /repos/{owner}/{repo}/issues/{number}/reactions/{id}`
- [ ] ListPRCommentReactions — `GET /repos/{owner}/{repo}/pulls/comments/{id}/reactions`
- [ ] CreatePRCommentReaction — `POST /repos/{owner}/{repo}/pulls/comments/{id}/reactions`
- [ ] DeletePRCommentReaction — `DELETE /repos/{owner}/{repo}/pulls/comments/{id}/reactions/{id}`
- [ ] ListReleaseReactions — `GET /repos/{owner}/{repo}/releases/{id}/reactions`
- [ ] CreateReleaseReaction — `POST /repos/{owner}/{repo}/releases/{id}/reactions`
- [ ] DeleteReleaseReaction — `DELETE /repos/{owner}/{repo}/releases/{id}/reactions/{id}`

## Security Advisories (10 endpoints)

- [ ] ListGlobalAdvisories — `GET /advisories`
- [ ] GetGlobalAdvisory — `GET /advisories/{ghsa_id}`
- [ ] ListOrgAdvisories — `GET /orgs/{org}/security-advisories`
- [ ] ListRepoAdvisories — `GET /repos/{owner}/{repo}/security-advisories`
- [ ] CreateRepoAdvisory — `POST /repos/{owner}/{repo}/security-advisories`
- [ ] ReportVulnerability — `POST /repos/{owner}/{repo}/security-advisories/reports`
- [ ] GetRepoAdvisory — `GET /repos/{owner}/{repo}/security-advisories/{ghsa_id}`
- [ ] UpdateRepoAdvisory — `PATCH /repos/{owner}/{repo}/security-advisories/{ghsa_id}`
- [ ] RequestCVE — `POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/cve`
- [ ] CreatePrivateFork — `POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/forks`

## Code Scanning — Extended (~18 endpoints)

- [ ] UpdateCodeScanningAlert — `PATCH /repos/{owner}/{repo}/code-scanning/alerts/{number}`
- [ ] GetCodeScanningAutofix — `GET /repos/{owner}/{repo}/code-scanning/alerts/{number}/autofix`
- [ ] CreateCodeScanningAutofix — `POST /repos/{owner}/{repo}/code-scanning/alerts/{number}/autofix`
- [ ] ListCodeScanningAlertInstances — `GET /repos/{owner}/{repo}/code-scanning/alerts/{number}/instances`
- [ ] ListCodeScanningAnalyses — `GET /repos/{owner}/{repo}/code-scanning/analyses`
- [ ] GetCodeScanningAnalysis — `GET /repos/{owner}/{repo}/code-scanning/analyses/{id}`
- [ ] DeleteCodeScanningAnalysis — `DELETE /repos/{owner}/{repo}/code-scanning/analyses/{id}`
- [ ] ListCodeQLDatabases — `GET /repos/{owner}/{repo}/code-scanning/codeql/databases`
- [ ] GetCodeQLDatabase — `GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{lang}`
- [ ] GetCodeScanningDefaultSetup — `GET /repos/{owner}/{repo}/code-scanning/default-setup`
- [ ] UpdateCodeScanningDefaultSetup — `PATCH /repos/{owner}/{repo}/code-scanning/default-setup`
- [ ] UploadSARIF — `POST /repos/{owner}/{repo}/code-scanning/sarifs`
- [ ] GetSARIFUpload — `GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id}`
- [ ] ListOrgCodeScanningAlerts — `GET /orgs/{org}/code-scanning/alerts`

## Dependabot — Extended (~14 endpoints)

- [ ] GetDependabotAlert — `GET /repos/{owner}/{repo}/dependabot/alerts/{number}`
- [ ] UpdateDependabotAlert — `PATCH /repos/{owner}/{repo}/dependabot/alerts/{number}`
- [ ] ListRepoDependabotSecrets — `GET /repos/{owner}/{repo}/dependabot/secrets`
- [ ] GetRepoDependabotPublicKey — `GET /repos/{owner}/{repo}/dependabot/secrets/public-key`
- [ ] GetRepoDependabotSecret — `GET /repos/{owner}/{repo}/dependabot/secrets/{name}`
- [ ] CreateOrUpdateRepoDependabotSecret — `PUT /repos/{owner}/{repo}/dependabot/secrets/{name}`
- [ ] DeleteRepoDependabotSecret — `DELETE /repos/{owner}/{repo}/dependabot/secrets/{name}`
- [ ] ListOrgDependabotSecrets — `GET /orgs/{org}/dependabot/secrets`
- [ ] GetOrgDependabotPublicKey — `GET /orgs/{org}/dependabot/secrets/public-key`
- [ ] GetOrgDependabotSecret — `GET /orgs/{org}/dependabot/secrets/{name}`
- [ ] CreateOrUpdateOrgDependabotSecret — `PUT /orgs/{org}/dependabot/secrets/{name}`
- [ ] DeleteOrgDependabotSecret — `DELETE /orgs/{org}/dependabot/secrets/{name}`
- [ ] ListOrgDependabotAlerts — `GET /orgs/{org}/dependabot/alerts`

## Secret Scanning — Extended (~6 endpoints)

- [ ] GetSecretScanningAlert — `GET /repos/{owner}/{repo}/secret-scanning/alerts/{number}`
- [ ] UpdateSecretScanningAlert — `PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{number}`
- [ ] ListSecretScanningAlertLocations — `GET /repos/{owner}/{repo}/secret-scanning/alerts/{number}/locations`
- [ ] CreatePushProtectionBypass — `POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses`
- [ ] GetSecretScanHistory — `GET /repos/{owner}/{repo}/secret-scanning/scan-history`
- [ ] ListOrgSecretScanningAlerts — `GET /orgs/{org}/secret-scanning/alerts`

## Organizations — Webhooks (7 endpoints)

- [ ] ListOrgWebhooks — `GET /orgs/{org}/hooks`
- [ ] CreateOrgWebhook — `POST /orgs/{org}/hooks`
- [ ] GetOrgWebhook — `GET /orgs/{org}/hooks/{id}`
- [ ] UpdateOrgWebhook — `PATCH /orgs/{org}/hooks/{id}`
- [ ] DeleteOrgWebhook — `DELETE /orgs/{org}/hooks/{id}`
- [ ] PingOrgWebhook — `POST /orgs/{org}/hooks/{id}/pings`

## Organizations — Blocks (3 endpoints)

- [ ] ListOrgBlockedUsers — `GET /orgs/{org}/blocks`
- [ ] BlockOrgUser — `PUT /orgs/{org}/blocks/{username}`
- [ ] UnblockOrgUser — `DELETE /orgs/{org}/blocks/{username}`

## Organizations — Invitations (5 endpoints)

- [ ] ListOrgInvitations — `GET /orgs/{org}/invitations`
- [ ] CreateOrgInvitation — `POST /orgs/{org}/invitations`
- [ ] CancelOrgInvitation — `DELETE /orgs/{org}/invitations/{id}`
- [ ] ListInvitationTeams — `GET /orgs/{org}/invitations/{id}/teams`
- [ ] ListFailedInvitations — `GET /orgs/{org}/failed_invitations`

## Organizations — Roles (10 endpoints)

- [ ] ListOrgRoles — `GET /orgs/{org}/organization-roles`
- [ ] GetOrgRole — `GET /orgs/{org}/organization-roles/{id}`
- [ ] AssignTeamRole — `PUT /orgs/{org}/organization-roles/teams/{team_slug}/{role_id}`
- [ ] RemoveTeamRole — `DELETE /orgs/{org}/organization-roles/teams/{team_slug}/{role_id}`
- [ ] AssignUserRole — `PUT /orgs/{org}/organization-roles/users/{username}/{role_id}`
- [ ] RemoveUserRole — `DELETE /orgs/{org}/organization-roles/users/{username}/{role_id}`
- [ ] ListTeamsForRole — `GET /orgs/{org}/organization-roles/{id}/teams`
- [ ] ListUsersForRole — `GET /orgs/{org}/organization-roles/{id}/users`

## Organizations — Outside Collaborators (3 endpoints)

- [ ] ListOutsideCollaborators — `GET /orgs/{org}/outside_collaborators`
- [ ] ConvertToOutsideCollaborator — `PUT /orgs/{org}/outside_collaborators/{username}`
- [ ] RemoveOutsideCollaborator — `DELETE /orgs/{org}/outside_collaborators/{username}`

## Organizations — Memberships (5 endpoints)

- [ ] GetOrgMembership — `GET /orgs/{org}/memberships/{username}`
- [ ] SetOrgMembership — `PUT /orgs/{org}/memberships/{username}`
- [ ] RemoveOrgMembership — `DELETE /orgs/{org}/memberships/{username}`
- [ ] ListUserOrgMemberships — `GET /user/memberships/orgs`
- [ ] GetUserOrgMembership — `GET /user/memberships/orgs/{org}`

## Organizations — Custom Properties (5 endpoints)

- [ ] ListOrgCustomProperties — `GET /orgs/{org}/properties/schema`
- [ ] CreateOrgCustomProperties — `PATCH /orgs/{org}/properties/schema`
- [ ] GetOrgCustomProperty — `GET /orgs/{org}/properties/schema/{name}`
- [ ] CreateOrUpdateOrgCustomProperty — `PUT /orgs/{org}/properties/schema/{name}`
- [ ] DeleteOrgCustomProperty — `DELETE /orgs/{org}/properties/schema/{name}`

## Organizations — PAT Management (8 endpoints)

- [ ] ListOrgPATRequests — `GET /orgs/{org}/personal-access-token-requests`
- [ ] ReviewOrgPATRequests — `POST /orgs/{org}/personal-access-token-requests`
- [ ] ReviewOrgPATRequest — `POST /orgs/{org}/personal-access-token-requests/{id}`
- [ ] ListOrgPATs — `GET /orgs/{org}/personal-access-tokens`
- [ ] UpdateOrgPATs — `POST /orgs/{org}/personal-access-tokens`
- [ ] UpdateOrgPAT — `POST /orgs/{org}/personal-access-tokens/{id}`

## Organizations — Security Managers (3 endpoints)

- [ ] ListSecurityManagers — `GET /orgs/{org}/security-managers`
- [ ] AddSecurityManagerTeam — `PUT /orgs/{org}/security-managers/teams/{team_slug}`
- [ ] RemoveSecurityManagerTeam — `DELETE /orgs/{org}/security-managers/teams/{team_slug}`

## Organizations — Public Members (3 endpoints)

- [ ] ListPublicMembers — `GET /orgs/{org}/public_members`
- [ ] CheckPublicMembership — `GET /orgs/{org}/public_members/{username}`
- [ ] PublicizeMembership — `PUT /orgs/{org}/public_members/{username}`
- [ ] ConcealMembership — `DELETE /orgs/{org}/public_members/{username}`

## Teams — Extended (~10 endpoints)

- [ ] ListTeamInvitations — `GET /orgs/{org}/teams/{team_slug}/invitations`
- [ ] ListTeamRepos — `GET /orgs/{org}/teams/{team_slug}/repos`
- [ ] CheckTeamRepo — `GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}`
- [ ] AddTeamRepo — `PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}`
- [ ] RemoveTeamRepo — `DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}`
- [ ] ListChildTeams — `GET /orgs/{org}/teams/{team_slug}/teams`
- [ ] ListUserTeams — `GET /user/teams`

## Users — Extended (~8 endpoints)

- [ ] SetEmailVisibility — `PATCH /user/email/visibility`
- [ ] ListPublicEmails — `GET /user/public_emails`
- [ ] ListSSHSigningKeys — `GET /user/ssh_signing_keys`
- [ ] CreateSSHSigningKey — `POST /user/ssh_signing_keys`
- [ ] GetSSHSigningKey — `GET /user/ssh_signing_keys/{id}`
- [ ] DeleteSSHSigningKey — `DELETE /user/ssh_signing_keys/{id}`
- [ ] FollowUser — `PUT /user/following/{username}`
- [ ] UnfollowUser — `DELETE /user/following/{username}`

## Search — Extended (3 endpoints)

- [ ] SearchIssuesAndPRs — `GET /search/issues`
- [ ] SearchRepositories — `GET /search/repositories`
- [ ] SearchUsers — `GET /search/users`

## Checks — Extended (8 endpoints)

- [ ] ListCheckRunAnnotations — `GET /repos/{owner}/{repo}/check-runs/{id}/annotations`
- [ ] RerequestCheckRun — `POST /repos/{owner}/{repo}/check-runs/{id}/rerequest`
- [ ] UpdateCheckSuitePreferences — `PATCH /repos/{owner}/{repo}/check-suites/preferences`
- [ ] GetCheckSuite — `GET /repos/{owner}/{repo}/check-suites/{id}`
- [ ] RerequestCheckSuite — `POST /repos/{owner}/{repo}/check-suites/{id}/rerequest`
- [ ] ListCheckSuiteCheckRuns — `GET /repos/{owner}/{repo}/check-suites/{id}/check-runs`
- [ ] ListCheckRunsForRef — `GET /repos/{owner}/{repo}/commits/{ref}/check-runs`
- [ ] ListCheckSuitesForRef — `GET /repos/{owner}/{repo}/commits/{ref}/check-suites`

## Gists — Extended (7 endpoints)

- [ ] GetGistRevision — `GET /gists/{gist_id}/{sha}`
- [ ] ListGistCommits — `GET /gists/{gist_id}/commits`
- [ ] ListGistForks — `GET /gists/{gist_id}/forks`
- [ ] ForkGist — `POST /gists/{gist_id}/forks`
- [ ] ListPublicGists — `GET /gists/public`
- [ ] ListStarredGists — `GET /gists/starred`
- [ ] ListUserGists — `GET /users/{username}/gists`

## Packages — Extended (~12 endpoints)

- [ ] RestoreOrgPackage — `POST /orgs/{org}/packages/{type}/{name}/restore`
- [ ] GetOrgPackageVersion — `GET /orgs/{org}/packages/{type}/{name}/versions/{id}`
- [ ] DeleteOrgPackageVersion — `DELETE /orgs/{org}/packages/{type}/{name}/versions/{id}`
- [ ] RestoreOrgPackageVersion — `POST /orgs/{org}/packages/{type}/{name}/versions/{id}/restore`
- [ ] RestoreUserPackage — `POST /user/packages/{type}/{name}/restore`
- [ ] GetUserPackageVersion — `GET /user/packages/{type}/{name}/versions/{id}`
- [ ] DeleteUserPackageVersion — `DELETE /user/packages/{type}/{name}/versions/{id}`
- [ ] RestoreUserPackageVersion — `POST /user/packages/{type}/{name}/versions/{id}/restore`

## Dependency Graph (3 endpoints)

- [ ] GetDependencyDiff — `GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead}`
- [ ] ExportSBOM — `GET /repos/{owner}/{repo}/dependency-graph/sbom`
- [ ] CreateDependencySnapshot — `POST /repos/{owner}/{repo}/dependency-graph/snapshots`

## Interactions (9 endpoints)

- [ ] GetOrgInteractionLimits — `GET /orgs/{org}/interaction-limits`
- [ ] SetOrgInteractionLimits — `PUT /orgs/{org}/interaction-limits`
- [ ] RemoveOrgInteractionLimits — `DELETE /orgs/{org}/interaction-limits`
- [ ] GetRepoInteractionLimits — `GET /repos/{owner}/{repo}/interaction-limits`
- [ ] SetRepoInteractionLimits — `PUT /repos/{owner}/{repo}/interaction-limits`
- [ ] RemoveRepoInteractionLimits — `DELETE /repos/{owner}/{repo}/interaction-limits`
- [ ] GetUserInteractionLimits — `GET /user/interaction-limits`
- [ ] SetUserInteractionLimits — `PUT /user/interaction-limits`
- [ ] RemoveUserInteractionLimits — `DELETE /user/interaction-limits`

## Billing (10 endpoints)

- [ ] ListOrgBudgets — `GET /organizations/{org}/settings/billing/budgets`
- [ ] GetOrgBudget — `GET /organizations/{org}/settings/billing/budgets/{id}`
- [ ] UpdateOrgBudget — `PATCH /organizations/{org}/settings/billing/budgets/{id}`
- [ ] DeleteOrgBudget — `DELETE /organizations/{org}/settings/billing/budgets/{id}`
- [ ] GetOrgBillingUsage — `GET /organizations/{org}/settings/billing/usage`
- [ ] GetOrgBillingUsageSummary — `GET /organizations/{org}/settings/billing/usage/summary`

## Licenses (3 endpoints)

- [ ] ListLicenses — `GET /licenses`
- [ ] GetLicense — `GET /licenses/{license}`
- [ ] GetRepoLicense — `GET /repos/{owner}/{repo}/license`

## Meta / Server Info (5 endpoints)

- [ ] GetAPIRoot — `GET /`
- [ ] GetMeta — `GET /meta`
- [ ] GetOctocat — `GET /octocat`
- [ ] GetAPIVersions — `GET /versions`
- [ ] GetZen — `GET /zen`

## Gitignore Templates (2 endpoints)

- [ ] ListGitignoreTemplates — `GET /gitignore/templates`
- [ ] GetGitignoreTemplate — `GET /gitignore/templates/{name}`

## Codes of Conduct (2 endpoints)

- [ ] ListCodesOfConduct — `GET /codes_of_conduct`
- [ ] GetCodeOfConduct — `GET /codes_of_conduct/{key}`

## Projects V2 — GraphQL-based (~15 methods)

- [ ] ListOrgProjectsV2 — GraphQL query
- [ ] GetProjectV2 — GraphQL query
- [ ] CreateProjectV2DraftItem — GraphQL mutation
- [ ] ListProjectV2Fields — GraphQL query
- [ ] ListProjectV2Items — GraphQL query
- [ ] AddProjectV2Item — GraphQL mutation
- [ ] UpdateProjectV2Item — GraphQL mutation
- [ ] DeleteProjectV2Item — GraphQL mutation
- [ ] CreateProjectV2View — GraphQL mutation
- [ ] UpdateProjectV2 — GraphQL mutation
- [ ] DeleteProjectV2 — GraphQL mutation
- [ ] CopyProjectV2 — GraphQL mutation

## Classroom (6 endpoints)

- [ ] GetAssignment — `GET /assignments/{id}`
- [ ] ListAcceptedAssignments — `GET /assignments/{id}/accepted_assignments`
- [ ] GetAssignmentGrades — `GET /assignments/{id}/grades`
- [ ] ListClassrooms — `GET /classrooms`
- [ ] GetClassroom — `GET /classrooms/{id}`
- [ ] ListClassroomAssignments — `GET /classrooms/{id}/assignments`

## OIDC (4 endpoints)

- [ ] GetOrgOIDCSubjectClaim — `GET /orgs/{org}/actions/oidc/customization/sub`
- [ ] SetOrgOIDCSubjectClaim — `PUT /orgs/{org}/actions/oidc/customization/sub`
- [ ] GetOrgOIDCProperties — `GET /orgs/{org}/actions/oidc/customization/properties/repo`
- [ ] SetOrgOIDCProperties — `POST /orgs/{org}/actions/oidc/customization/properties/repo`
