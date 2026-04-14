package cores

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	neturl "net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ════════════════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════════════════

const (
	ghAPIBase     = "https://api.github.com"
	ghPlatform    = "github"
	ghDMPrefix    = "Uniclient DM \u2014 " // human-readable issue title for DM threads: "Uniclient DM — {peer}"
	ghDMLabel     = "uniclient-dm"       // label to tag DM issues (keeps them filterable)
	ghGroupLabel  = "uniclient-group"    // label to tag group chat repos
	ghGeneralTitle = "General"           // default channel (pinned issue) in every group

	// Polling intervals
	ghPollActive  = 12 * time.Second  // actively viewing a conversation
	ghPollRecent  = 30 * time.Second  // recent activity (last 5 min)
	ghPollIdle    = 2 * time.Minute   // no activity in 30 min
	ghPollBG      = 5 * time.Minute   // background / not visible
	ghNotifPoll   = 10 * time.Second  // notifications endpoint (304s are free)

	// Limits
	ghMaxCommentLen = 65536 // GitHub comment body max length
	ghMaxFileUpload = 25 * 1024 * 1024 // 25MB for images in comments
	ghPageSize      = 30    // default items per page

	// Chat ID formats:
	//   "dm:{username}"                — DM (issue on {peer}/{peer} profile repo)
	//   "repo:{owner}/{repo}"          — group chat (repo = group)
	//   "issue:{owner}/{repo}/{number}" — channel within a group (issue = channel)
)

var ghReactionMap = map[string]string{
	"+1": "\U0001f44d", "-1": "\U0001f44e", "laugh": "\U0001f604", "hooray": "\U0001f389",
	"confused": "\U0001f615", "heart": "\u2764\ufe0f", "rocket": "\U0001f680", "eyes": "\U0001f440",
}

var ghEmojiToReaction = map[string]string{
	"\U0001f44d": "+1", "\U0001f44e": "-1", "\U0001f604": "laugh", "\U0001f389": "hooray",
	"\U0001f615": "confused", "\u2764\ufe0f": "heart", "\U0001f680": "rocket", "\U0001f440": "eyes",
	"+1": "+1", "-1": "-1", "laugh": "laugh", "hooray": "hooray",
	"confused": "confused", "heart": "heart", "rocket": "rocket", "eyes": "eyes",
	"thumbsup": "+1", "thumbsdown": "-1",
}

func ghRepoPath(owner, repo string) string {
	return "/repos/" + owner + "/" + repo
}

func ghIntStr(f float64) string {
	return strconv.FormatInt(int64(f), 10)
}

// ════════════════════════════════════════════════════════════════════════════════
// Rate Limiter & Cache Types
// ════════════════════════════════════════════════════════════════════════════════

// ghRateLimiter paces GitHub API requests to avoid hitting rate limits and bans.
//
// GitHub limits:
//   - REST: 5,000 req/hr authenticated, 304 Not-Modified responses are FREE
//   - Search: 30 req/min (stricter, separate from main limit)
//   - Secondary (abuse): undocumented, triggered by rapid creation or burst activity
//
// Strategy: track X-RateLimit-* headers, enforce min intervals between requests,
// use exponential backoff on 429/secondary-403, slow down when budget is low.
type ghRateLimiter struct {
	mu sync.Mutex

	// From GitHub response headers
	remaining int       // X-RateLimit-Remaining
	resetAt   time.Time // X-RateLimit-Reset

	// Pacing: prevent request bursts
	lastRequest time.Time
	readDelay   time.Duration // min interval between reads
	writeDelay  time.Duration // min interval between writes (mutations)
	lastWrite   time.Time
}

// ghCache provides TTL-based response caching to avoid redundant API calls.
type ghCache struct {
	mu    sync.RWMutex
	items map[string]*ghCacheItem
}

type ghCacheItem struct {
	data    json.RawMessage
	expires time.Time
}

// ghDMIssueInfo tracks where a DM issue lives (persisted in session).
type ghDMIssueInfo struct {
	IssueNum  int    `json:"n"`           // issue number
	RepoOwner string `json:"o"`           // owner of the repo where the issue lives
	RepoName  string `json:"r"`           // repo name where the issue lives
}

// ════════════════════════════════════════════════════════════════════════════════
// Types
// ════════════════════════════════════════════════════════════════════════════════

// GitHubCore implements the Core interface for GitHub as a social/messaging platform.
//
// Architecture:
//   - DMs: via profile repos ({user}/{user}). To DM someone, open an issue on their
//     profile repo. Title: "Uniclient DM — {your_username}". Label: "uniclient-dm".
//     Auto-created on auth. E2EE-ready (@@-prefixed ciphertext in any comment).
//   - Groups: repos where issues serve as channels. A pinned "General" issue is the
//     default channel. Additional issues = topic channels. Collaborators = members.
//   - Real-time: poll /notifications with If-Modified-Since (304s are FREE).
//   - Rate limits: 5,000 req/hr nominal. Managed by ghRateLimiter — paces requests
//     (100ms reads, 1.5s writes), retries 429/5xx/secondary-403 with exponential
//     backoff, tracks budget from response headers, slows polling when quota is low.
//     Conditional requests (304) + response cache + session-persistent DM/group
//     caches minimize actual API calls. Effective capacity well above nominal.
type GitHubCore struct {
	mu sync.RWMutex

	// Auth
	authed   bool
	token    string // Personal Access Token
	username string // authenticated user's login
	userID   int64  // authenticated user's numeric ID

	// HTTP client with auth headers
	client *http.Client

	// Rate limiter & response cache
	rl    *ghRateLimiter
	cache *ghCache

	// Dialog cache: chatID → ghDialog
	dialogs   map[string]*ghDialog
	dialogsMu sync.RWMutex

	// Message cache: chatID → ordered messages
	messages   map[string][]*Message
	messagesMu sync.RWMutex

	// Notification polling state
	notifLastModified string // If-Modified-Since for /notifications
	notifEtag         string // ETag for /notifications

	// Per-thread ETags for conditional polling
	threadETags   map[string]string // chatID → ETag
	threadETagsMu sync.RWMutex

	// Active threads: recently active chatIDs with last activity time
	activeThreads   map[string]time.Time
	activeThreadsMu sync.RWMutex

	// Session-persistent caches (survive restarts)
	dmIssues     map[string]*ghDMIssueInfo // peerUser → DM issue location
	dmIssuesMu   sync.RWMutex
	groupRepos   map[string]int            // "owner/repo" → General issue number
	groupReposMu sync.RWMutex

	// Blocked users (local cache)
	blocked   map[string]bool
	blockedMu sync.RWMutex

	// Pinned messages (local, per-chat)
	pinned   map[string]map[string]bool // chatID → msgID → pinned
	pinnedMu sync.RWMutex

	// Read state (local tracking)
	readState   map[string]*ReadState // chatID → read state
	readStateMu sync.RWMutex

	// Update handlers
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Session
	sessionPath string

	// Context for goroutines
	ctx    context.Context
	cancel context.CancelFunc
	wg     sync.WaitGroup
}

var _ Core = (*GitHubCore)(nil)

// ghDialog is internal dialog metadata.
type ghDialog struct {
	ChatID      string
	Type        ChatType
	Title       string
	Owner       string // repo owner (for DMs: owner of repo where issue lives)
	Repo        string // repo name  (for DMs: repo where issue lives)
	IssueNum    int    // for DMs: issue number; for channels: issue number
	AvatarURL   string
	MemberCount int
	LastActive  time.Time
	UnreadCount int
	IsMuted     bool
	IsPinned    bool
	PeerUser    string // for DMs: the other user's login
}

// ghSession is the persisted session state.
type ghSession struct {
	Token      string                     `json:"token"`
	Username   string                     `json:"username"`
	UserID     int64                      `json:"user_id"`
	Blocked    []string                   `json:"blocked,omitempty"`
	Pinned     map[string][]string        `json:"pinned,omitempty"`
	ReadState  map[string]*ReadState      `json:"read_state,omitempty"`
	DMIssues   map[string]*ghDMIssueInfo  `json:"dm_issues,omitempty"`   // persistent DM cache
	GroupRepos map[string]int             `json:"group_repos,omitempty"` // persistent group cache
}

// ════════════════════════════════════════════════════════════════════════════════
// Constructor
// ════════════════════════════════════════════════════════════════════════════════

func NewGitHubCore(sessionPath string) *GitHubCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &GitHubCore{
		rl: &ghRateLimiter{
			readDelay:  100 * time.Millisecond,
			writeDelay: 1500 * time.Millisecond,
		},
		cache:         &ghCache{items: make(map[string]*ghCacheItem)},
		dialogs:       make(map[string]*ghDialog),
		messages:      make(map[string][]*Message),
		threadETags:   make(map[string]string),
		activeThreads: make(map[string]time.Time),
		dmIssues:      make(map[string]*ghDMIssueInfo),
		groupRepos:    make(map[string]int),
		blocked:       make(map[string]bool),
		pinned:        make(map[string]map[string]bool),
		readState:     make(map[string]*ReadState),
		sessionPath:   sessionPath,
		ctx:           ctx,
		cancel:        cancel,
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Identity
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) Name() string { return ghPlatform }

func (g *GitHubCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapReactions, CapReadReceipts,
		CapAdmin, CapFolders, CapSearch, CapPolls,
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Auth
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) Authenticate(cfg AuthConfig) error {
	g.mu.Lock()
	defer g.mu.Unlock()

	// Try loading existing session
	if err := g.loadSession(); err == nil && g.token != "" {
		g.client = g.makeHTTPClient(g.token)
		// Verify token still works
		user, err := g.apiGetUser("")
		if err == nil {
			g.username = user.Username
			g.userID, _ = strconv.ParseInt(user.ID, 10, 64)
			g.authed = true
			g.ensureProfileRepo() // best-effort, non-blocking
			g.wg.Add(1)
			go g.pollLoop()
			return nil
		}
		// Token expired, fall through to fresh auth
		g.token = ""
	}

	// Fresh auth — token from BotToken field (PAT) or Extra["token"]
	token := cfg.BotToken
	if token == "" {
		token = cfg.Extra["token"]
	}
	if token == "" {
		return fmt.Errorf("%w: github requires a personal access token (pass as bot_token or extra.token)", ErrAuth)
	}

	g.client = g.makeHTTPClient(token)

	// Validate token
	user, err := g.apiGetUser("")
	if err != nil {
		return fmt.Errorf("%w: invalid token: %v", ErrAuth, err)
	}

	g.token = token
	g.username = user.Username
	g.userID, _ = strconv.ParseInt(user.ID, 10, 64)
	g.authed = true

	// Ensure profile repo ({username}/{username}) exists for receiving DMs
	g.ensureProfileRepo() // best-effort, non-blocking

	g.saveSession()
	g.wg.Add(1)
	go g.pollLoop()
	return nil
}

func (g *GitHubCore) Logout() error {
	g.mu.Lock()
	defer g.mu.Unlock()

	g.authed = false
	g.token = ""
	g.cancel()
	os.Remove(g.sessionPath)
	return nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Dialogs
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	dialogs := []Dialog{}

	// 1. Fetch DM threads (issues on our inbox repo and issues we created on others' inbox repos)
	dms, err := g.fetchDMDialogs()
	if err == nil {
		dialogs = append(dialogs, dms...)
	}

	// 2. Fetch group chats (repos with issues-as-channels)
	groups, err := g.fetchGroupDialogs()
	if err == nil {
		dialogs = append(dialogs, groups...)
	}

	// Sort by last activity
	sort.Slice(dialogs, func(i, j int) bool {
		ti := time.Time{}
		tj := time.Time{}
		if dialogs[i].LastMessage != nil {
			ti = dialogs[i].LastMessage.Timestamp
		}
		if dialogs[j].LastMessage != nil {
			tj = dialogs[j].LastMessage.Timestamp
		}
		return ti.After(tj)
	})

	// Apply offset
	offset := 0
	if opts.Offset != "" {
		offset, _ = strconv.Atoi(opts.Offset)
	}
	if offset > 0 {
		if offset >= len(dialogs) {
			return []Dialog{}, nil
		}
		dialogs = dialogs[offset:]
	}

	// Apply limit
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > len(dialogs) {
		limit = len(dialogs)
	}
	return dialogs[:limit], nil
}

// ghValidRepoName checks if a name is valid for a GitHub repository.
var ghValidRepoName = regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)

func (g *GitHubCore) CreateGroup(name string, members []string) (*Dialog, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	// Validate repo name (GitHub rules: alphanumeric, hyphens, underscores, dots, no spaces)
	if name == "" || len(name) > 100 {
		return nil, fmt.Errorf("%w: group name must be 1-100 characters", ErrInvalidInput)
	}
	if !ghValidRepoName.MatchString(name) {
		return nil, fmt.Errorf("%w: group name can only contain letters, numbers, hyphens, underscores, and dots (no spaces)", ErrInvalidInput)
	}

	// Group = repo. Issues = channels. Collaborators = members.
	resp, err := g.apiPost("/user/repos", map[string]any{
		"name":        name,
		"description": "Uniclient group chat",
		"has_issues":  true,
		"private":     false,
		"auto_init":   true,
	})
	if err != nil {
		return nil, fmt.Errorf("create repo: %w", err)
	}

	owner := gjsonStr(resp, "owner.login")
	repo := gjsonStr(resp, "name")
	chatID := "repo:" + owner + "/" + repo

	// Tag the repo with uniclient-group topic (enables discovery by topic search)
	g.apiPut(ghRepoPath(owner, repo) + "/topics", map[string]any{
		"names": []string{"uniclient-group"},
	})

	// Create the default "General" channel (pinned issue)
	issueResp, err := g.apiPost(ghRepoPath(owner, repo) + "/issues", map[string]any{
		"title":  ghGeneralTitle,
		"body":   "Welcome! This is the default channel for **" + name + "**.\n\nPowered by [Uniclient](https://github.com/DarkReaperBoy/uniclient).",
		"labels": []string{ghGroupLabel},
	})
	generalNum := 0
	if err == nil {
		generalNum = int(gjsonFloat(issueResp, "number"))
	}

	// Cache in session-persistent group list
	g.groupReposMu.Lock()
	g.groupRepos[owner+"/"+repo] = generalNum
	g.groupReposMu.Unlock()
	g.saveSession()

	// Invite members as collaborators
	for _, member := range members {
		g.apiPut(ghRepoPath(owner, repo) + "/collaborators/" + member, map[string]any{
			"permission": "write",
		})
	}

	dlg := &Dialog{
		ID:       chatID,
		Type:     ChatTypeGroup,
		Title:    name,
		Platform: ghPlatform,
	}
	return dlg, nil
}

func (g *GitHubCore) CreateChannel(name string, description string) (*Dialog, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	if name == "" || len(name) > 100 {
		return nil, fmt.Errorf("%w: channel name must be 1-100 characters", ErrInvalidInput)
	}
	if !ghValidRepoName.MatchString(name) {
		return nil, fmt.Errorf("%w: channel name can only contain letters, numbers, hyphens, underscores, and dots (no spaces)", ErrInvalidInput)
	}

	desc := "Uniclient group chat"
	if description != "" {
		desc = description
	}
	resp, err := g.apiPost("/user/repos", map[string]any{
		"name":        name,
		"description": desc,
		"has_issues":  true,
		"private":     false,
		"auto_init":   true,
	})
	if err != nil {
		return nil, fmt.Errorf("create channel: %w", err)
	}
	owner := gjsonStr(resp, "owner.login")
	repo := gjsonStr(resp, "name")
	chatID := "repo:" + owner + "/" + repo
	return &Dialog{ID: chatID, Type: ChatTypeGroup, Title: name, Platform: ghPlatform}, nil
}

func (g *GitHubCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	// chatID = "repo:owner/repo" — create a new issue (channel) in the group repo
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return nil, err
	}

	resp, err := g.apiPost(ghRepoPath(owner, repo) + "/issues", map[string]any{
		"title":  name,
		"body":   "Channel: **" + name + "**",
		"labels": []string{ghGroupLabel},
	})
	if err != nil {
		return nil, fmt.Errorf("create channel issue: %w", err)
	}

	num := int(gjsonFloat(resp, "number"))
	topicID := "issue:" + owner + "/" + repo + "/" + strconv.Itoa(num)

	g.dialogsMu.Lock()
	g.dialogs[topicID] = &ghDialog{
		ChatID:   topicID,
		Type:     ChatTypeTopic,
		Title:    name,
		Owner:    owner,
		Repo:     repo,
		IssueNum: num,
	}
	g.dialogsMu.Unlock()

	return &Dialog{
		ID:       topicID,
		Type:     ChatTypeTopic,
		Title:    name,
		ParentID: chatID,
		Platform: ghPlatform,
	}, nil
}

func (g *GitHubCore) GetFolders() ([]Folder, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	// Map GitHub stars/lists to folders
	// GitHub has "Lists" feature for starring repos in categories
	resp, err := g.apiGet("/user/starred", nil)
	if err != nil {
		return nil, err
	}

	var repos []map[string]any
	json.Unmarshal(resp, &repos)

	chatIDs := make([]string, 0, len(repos))
	for _, r := range repos {
		owner := gjsonMapStr(r, "owner", "login")
		name, _ := r["name"].(string)
		if owner != "" && name != "" {
			chatIDs = append(chatIDs, "repo:"+owner+"/"+name)
		}
	}

	return []Folder{{
		ID:      "starred",
		Name:    "Starred",
		ChatIDs: chatIDs,
	}}, nil
}

func (g *GitHubCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	return nil, fmt.Errorf("%w: github does not support custom folders", ErrNotSupported)
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Messages
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	text := msg.Text
	if len(text) > ghMaxCommentLen {
		text = text[:ghMaxCommentLen]
	}

	switch {
	case strings.HasPrefix(chatID, "dm:"):
		return g.sendDMMessage(chatID, text)
	case strings.HasPrefix(chatID, "issue:"):
		return g.sendIssueComment(chatID, text)
	case strings.HasPrefix(chatID, "repo:"):
		// Sending to a group: comment on the "General" issue
		return g.sendRepoMessage(chatID, text)
	default:
		return nil, fmt.Errorf("%w: unknown chat ID format: %s", ErrInvalidInput, chatID)
	}
}

func (g *GitHubCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}

	switch {
	case strings.HasPrefix(chatID, "dm:"):
		return g.getDMMessages(chatID, limit, opts.Offset)
	case strings.HasPrefix(chatID, "issue:"):
		return g.getIssueMessages(chatID, limit, opts.Offset)
	case strings.HasPrefix(chatID, "repo:"):
		// Group-level: list channels (issues) or get General issue messages
		return g.getRepoMessages(chatID, limit)
	default:
		return nil, fmt.Errorf("%w: unknown chat ID format: %s", ErrInvalidInput, chatID)
	}
}

func (g *GitHubCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	// msgID format: "comment:{id}"
	commentID := strings.TrimPrefix(msgID, "comment:")
	owner, repo, _ := g.parseChatOwnerRepo(chatID)
	resp, err := g.apiPatch(ghRepoPath(owner, repo) + "/issues/comments/" + commentID, map[string]any{
		"body": text,
	})
	if err != nil {
		return nil, err
	}

	return g.commentToMessage(chatID, resp), nil
}

func (g *GitHubCore) DeleteMessage(chatID string, msgID string) error {
	if !g.authed {
		return ErrAuth
	}

	commentID := strings.TrimPrefix(msgID, "comment:")
	owner, repo, _ := g.parseChatOwnerRepo(chatID)
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/comments/" + commentID)
	return err
}

func (g *GitHubCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	// GitHub doesn't have native reply-to on comments, so we quote-block
	quotedText := msg.Text
	if replyToMsgID != "" {
		original := g.findCachedOrFetchComment(chatID, replyToMsgID)
		if original != nil {
			firstLine := original.Text
			if idx := strings.Index(firstLine, "\n"); idx > 0 {
				firstLine = firstLine[:idx]
			}
			if len(firstLine) > 100 {
				firstLine = firstLine[:100] + "..."
			}
			quotedText = fmt.Sprintf("> **%s**: %s\n\n%s", original.SenderName, firstLine, msg.Text)
		}
	}

	return g.SendMessage(chatID, OutgoingMessage{Text: quotedText})
}

func (g *GitHubCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	original := g.findCachedOrFetchComment(fromChatID, msgID)
	if original == nil {
		return nil, fmt.Errorf("%w: message %s not found in %s", ErrNotFound, msgID, fromChatID)
	}

	text := fmt.Sprintf("*Forwarded from %s:*\n\n%s", original.SenderName, original.Text)
	return g.SendMessage(toChatID, OutgoingMessage{Text: text})
}

func (g *GitHubCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	if !g.authed {
		return ErrAuth
	}

	// Map common emoji to GitHub's supported reactions
	ghReaction := g.mapReaction(emoji)
	if ghReaction == "" {
		return fmt.Errorf("%w: unsupported reaction (GitHub supports: +1, -1, laugh, confused, heart, hooray, rocket, eyes)", ErrInvalidInput)
	}

	commentID := strings.TrimPrefix(msgID, "comment:")
	owner, repo, _ := g.parseChatOwnerRepo(chatID)
	_, err := g.apiPost(ghRepoPath(owner, repo) + "/issues/comments/" + commentID + "/reactions", map[string]any{
		"content": ghReaction,
	})
	return err
}

func (g *GitHubCore) PinMessage(chatID string, msgID string) error {
	g.pinnedMu.Lock()
	if g.pinned[chatID] == nil {
		g.pinned[chatID] = make(map[string]bool)
	}
	g.pinned[chatID][msgID] = true
	g.pinnedMu.Unlock()
	g.saveSession()
	return nil
}

func (g *GitHubCore) UnpinMessage(chatID string, msgID string) error {
	g.pinnedMu.Lock()
	if g.pinned[chatID] != nil {
		delete(g.pinned[chatID], msgID)
	}
	g.pinnedMu.Unlock()
	g.saveSession()
	return nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Read State
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) MarkAsRead(chatID string, upToMsgID string) error {
	g.readStateMu.Lock()
	if g.readState[chatID] == nil {
		g.readState[chatID] = &ReadState{PeerLastRead: make(map[string]string)}
	}
	g.readState[chatID].MyLastRead = upToMsgID
	g.readStateMu.Unlock()

	// Also mark notification as read if it maps to a thread
	if strings.HasPrefix(chatID, "dm:") || strings.HasPrefix(chatID, "issue:") {
		owner, repo, num := g.parseChatOwnerRepo(chatID)
		if num != "" {
			g.apiPut(ghRepoPath(owner, repo) + "/issues/" + num, map[string]any{})
		}
	}

	g.saveSession()
	return nil
}

func (g *GitHubCore) GetReadState(chatID string) (*ReadState, error) {
	g.readStateMu.RLock()
	defer g.readStateMu.RUnlock()
	if rs, ok := g.readState[chatID]; ok {
		return rs, nil
	}
	return &ReadState{PeerLastRead: make(map[string]string)}, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Files
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	data, err := io.ReadAll(io.LimitReader(file.Reader, ghMaxFileUpload+1))
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}
	if int64(len(data)) > ghMaxFileUpload {
		return nil, fmt.Errorf("%w: file too large (max 25MB)", ErrInvalidInput)
	}

	if progress != nil {
		progress(int64(len(data)), int64(len(data)))
	}

	// Upload to the repo's file-share branch via Contents API, then link in comment.
	// For DMs we use the profile repo, for groups the group repo.
	owner, repo, _ := g.parseChatOwnerRepo(chatID)
	if owner == "" || repo == "" {
		// Fallback: just describe the file in the message
		return g.SendMessage(chatID, OutgoingMessage{Text: fmt.Sprintf("📎 **%s** (%s, %d bytes)", file.Name, file.MimeType, len(data))})
	}

	// Upload to uniclient-files/ path in the repo (avoids polluting root)
	import_b64 := base64.StdEncoding.EncodeToString(data)
	filePath := fmt.Sprintf("uniclient-files/%d-%s", time.Now().UnixMilli(), file.Name)
	_, uploadErr := g.apiPut(ghRepoPath(owner, repo) + "/contents/" + filePath, map[string]any{
		"message": "Upload: " + file.Name,
		"content": import_b64,
	})

	if uploadErr != nil {
		// Contents API failed (maybe no push access) — send metadata-only message
		return g.SendMessage(chatID, OutgoingMessage{
			Text: fmt.Sprintf("📎 **%s** (%s, %d bytes)\n\n*File upload failed — %v*", file.Name, file.MimeType, len(data), uploadErr),
		})
	}

	// Build download URL and send link in comment
	downloadURL := "https://raw.githubusercontent.com/" + owner + "/" + repo + "/main/" + filePath
	text := fmt.Sprintf("📎 **[%s](%s)** (%s, %d bytes)", file.Name, downloadURL, file.MimeType, len(data))
	return g.SendMessage(chatID, OutgoingMessage{Text: text})
}

func (g *GitHubCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	if fileRef.URL == "" {
		return fmt.Errorf("%w: no download URL", ErrInvalidInput)
	}

	req, err := http.NewRequestWithContext(g.ctx, "GET", fileRef.URL, nil)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrNetwork, err)
	}
	req.Header.Set("Authorization", "Bearer "+g.token)
	resp, err := g.client.Do(req)
	if err != nil {
		return fmt.Errorf("%w: download: %v", ErrNetwork, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("%w: download returned %d", ErrNetwork, resp.StatusCode)
	}

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()

	total := resp.ContentLength
	if total <= 0 {
		total = fileRef.Size
	}

	written, err := io.Copy(f, resp.Body)
	if progress != nil {
		progress(written, total)
	}
	return err
}

func (g *GitHubCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	text := caption
	if b64 != "" {
		// GitHub comments strip data: URIs from img tags for security, so we can't
		// embed the image inline. Instead, store the base64 in a collapsed details
		// block that Uniclient clients can parse and render, while GitHub web shows
		// a clean caption + "[Image attached]" indicator.
		text += "\n\n<details><summary>📷 Image attached (view in Uniclient)</summary>\n\n"
		text += "```uniclient-image\n" + b64 + "\n```\n\n</details>"
	}
	return g.SendMessage(chatID, OutgoingMessage{Text: text})
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Calls (not supported)
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) StartCall(_ string, _ bool) (*CallSession, error) {
	return nil, fmt.Errorf("%w: github does not support calls", ErrNotSupported)
}
func (g *GitHubCore) JoinGroupCall(_ string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: github does not support calls", ErrNotSupported)
}
func (g *GitHubCore) EndCall(_ string) error {
	return fmt.Errorf("%w: github does not support calls", ErrNotSupported)
}
func (g *GitHubCore) SetCallMuted(_ string, _ bool) error {
	return fmt.Errorf("%w: github does not support calls", ErrNotSupported)
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Profile
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) GetProfile(userID string) (*User, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	return g.apiGetUser(userID)
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Real-time & Lifecycle
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) OnUpdate(handler func(Update)) {
	g.updateMu.Lock()
	defer g.updateMu.Unlock()
	g.updateHandlers = append(g.updateHandlers, handler)
}

func (g *GitHubCore) Close() error {
	g.mu.Lock()
	g.saveSession()
	g.cancel()
	g.authed = false
	g.mu.Unlock()
	g.wg.Wait()
	return nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Chat Management
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) GetChatInfo(chatID string) (*Dialog, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	g.dialogsMu.RLock()
	dlg, ok := g.dialogs[chatID]
	g.dialogsMu.RUnlock()

	if ok {
		return g.ghDialogToDialog(dlg), nil
	}

	// Try to fetch it
	if strings.HasPrefix(chatID, "repo:") {
		owner, repo, err := g.parseRepoChat(chatID)
		if err != nil {
			return nil, err
		}
		resp, err := g.apiGet(ghRepoPath(owner, repo), nil)
		if err != nil {
			return nil, err
		}
		return &Dialog{
			ID:          chatID,
			Type:        ChatTypeGroup,
			Title:       gjsonStr(resp, "name"),
			AvatarURL:   gjsonStr(resp, "owner.avatar_url"),
			MemberCount: int(gjsonFloat(resp, "subscribers_count")),
			Platform:    ghPlatform,
		}, nil
	}

	return nil, ErrNotFound
}

func (g *GitHubCore) EditChatTitle(chatID string, title string) error {
	if !g.authed {
		return ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return err
	}
	_, err = g.apiPatch(ghRepoPath(owner, repo), map[string]any{
		"name": title,
	})
	return err
}

func (g *GitHubCore) EditChatDescription(chatID string, description string) error {
	if !g.authed {
		return ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return err
	}
	_, err = g.apiPatch(ghRepoPath(owner, repo), map[string]any{
		"description": description,
	})
	return err
}

func (g *GitHubCore) LeaveChat(chatID string) error {
	if !g.authed {
		return ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return err
	}
	// Unwatch repo
	_, err = g.apiDelete(ghRepoPath(owner, repo) + "/subscription")
	return err
}

func (g *GitHubCore) GetInviteLink(chatID string) (string, error) {
	if !g.authed {
		return "", ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return "", err
	}
	return "https://github.com/" + owner + "/" + repo, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Members
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) AddMembers(chatID string, userIDs []string) error {
	if !g.authed {
		return ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return err
	}
	for _, uid := range userIDs {
		_, err := g.apiPut(ghRepoPath(owner, repo) + "/collaborators/" + uid, map[string]any{
			"permission": "write",
		})
		if err != nil {
			return fmt.Errorf("invite %s: %w", uid, err)
		}
	}
	return nil
}

func (g *GitHubCore) RemoveMember(chatID string, userID string) error {
	if !g.authed {
		return ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return err
	}
	_, err = g.apiDelete(ghRepoPath(owner, repo) + "/collaborators/" + userID)
	return err
}

func (g *GitHubCore) BanMember(chatID string, userID string) error {
	// GitHub repos don't have a ban concept — remove + block
	if err := g.RemoveMember(chatID, userID); err != nil {
		return err
	}
	return g.BlockUser(userID)
}

func (g *GitHubCore) UnbanMember(chatID string, userID string) error {
	return g.UnblockUser(userID)
}

func (g *GitHubCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return nil, err
	}
	resp, err := g.apiGet(ghRepoPath(owner, repo) + "/collaborators", nil)
	if err != nil {
		return nil, err
	}

	var collabs []map[string]any
	json.Unmarshal(resp, &collabs)

	users := make([]User, 0, len(collabs))
	for _, c := range collabs {
		users = append(users, User{
			ID:          ghIntStr(gjsonMapFloat(c, "id")),
			Username:    strOf(c["login"]),
			DisplayName: strOf(c["login"]),
			AvatarURL:   strOf(c["avatar_url"]),
			Platform:    ghPlatform,
		})
	}
	return users, nil
}

func (g *GitHubCore) SetAdmin(chatID string, userID string, admin bool) error {
	if !g.authed {
		return ErrAuth
	}
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return err
	}
	perm := "write"
	if admin {
		perm = "admin"
	}
	_, err = g.apiPut(ghRepoPath(owner, repo) + "/collaborators/" + userID, map[string]any{
		"permission": perm,
	})
	return err
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Contacts
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) GetContacts() ([]User, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	resp, err := g.apiGet("/user/following", nil)
	if err != nil {
		return nil, err
	}

	var users []map[string]any
	json.Unmarshal(resp, &users)

	result := make([]User, 0, len(users))
	for _, u := range users {
		result = append(result, User{
			ID:          ghIntStr(gjsonMapFloat(u, "id")),
			Username:    strOf(u["login"]),
			DisplayName: strOf(u["login"]),
			AvatarURL:   strOf(u["avatar_url"]),
			Platform:    ghPlatform,
		})
	}
	return result, nil
}

func (g *GitHubCore) AddContact(_ string, firstName string, _ string) error {
	if !g.authed {
		return ErrAuth
	}
	// firstName = GitHub username to follow
	if firstName == "" {
		return fmt.Errorf("%w: username required (pass GitHub username as firstName)", ErrInvalidInput)
	}
	_, err := g.apiPut("/user/following/" + firstName, nil)
	return err
}

func (g *GitHubCore) DeleteContact(userID string) error {
	if !g.authed {
		return ErrAuth
	}
	_, err := g.apiDelete("/user/following/" + userID)
	return err
}

func (g *GitHubCore) BlockUser(userID string) error {
	if !g.authed {
		return ErrAuth
	}
	_, err := g.apiPut("/user/blocks/" + userID, nil)
	if err != nil {
		return err
	}
	g.blockedMu.Lock()
	g.blocked[userID] = true
	g.blockedMu.Unlock()
	g.saveSession()
	return nil
}

func (g *GitHubCore) UnblockUser(userID string) error {
	if !g.authed {
		return ErrAuth
	}
	_, err := g.apiDelete("/user/blocks/" + userID)
	if err != nil {
		return err
	}
	g.blockedMu.Lock()
	delete(g.blocked, userID)
	g.blockedMu.Unlock()
	g.saveSession()
	return nil
}

func (g *GitHubCore) GetBlockedUsers() ([]User, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	resp, err := g.apiGet("/user/blocks", nil)
	if err != nil {
		return nil, err
	}

	var users []map[string]any
	json.Unmarshal(resp, &users)

	result := make([]User, 0, len(users))
	for _, u := range users {
		login := strOf(u["login"])
		result = append(result, User{
			ID:          ghIntStr(gjsonMapFloat(u, "id")),
			Username:    login,
			DisplayName: login,
			AvatarURL:   strOf(u["avatar_url"]),
			Platform:    ghPlatform,
		})
	}
	return result, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Search
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	// GitHub can't search comments across all repos — need a specific repo scope
	owner, repo, _ := g.parseChatOwnerRepo(chatID)
	if owner == "" || repo == "" {
		return nil, fmt.Errorf("%w: GitHub requires a specific chat/repo for message search (cross-repo comment search is not supported)", ErrNotSupported)
	}
	searchQ := query + " repo:" + owner + "/" + repo

	resp, err := g.apiGet("/search/issues", map[string]string{
		"q":        searchQ,
		"per_page": "20",
	})
	if err != nil {
		return nil, err
	}

	items := gjsonArray(resp, "items")
	msgs := make([]Message, 0, len(items))
	for _, item := range items {
		m, _ := item.(map[string]any)
		if m == nil {
			continue
		}
		ts, _ := time.Parse(time.RFC3339, strOf(m["created_at"]))
		user, _ := m["user"].(map[string]any)
		msgs = append(msgs, Message{
			ID:         "issue:" + ghIntStr(gjsonMapFloat(m, "number")),
			ChatID:     chatID,
			SenderID:   strOf(user["login"]),
			SenderName: strOf(user["login"]),
			Text:       strOf(m["title"]) + "\n\n" + strOf(m["body"]),
			Timestamp:  ts,
			Status:     MessageStatusSent,
			Platform:   ghPlatform,
		})
	}
	return msgs, nil
}

func (g *GitHubCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	if !g.authed {
		return nil, ErrAuth
	}

	// Search repos (groups are repos with issues as channels)
	resp, err := g.apiGet("/search/repositories", map[string]string{
		"q":        query,
		"per_page": "20",
	})
	if err != nil {
		return nil, err
	}

	items := gjsonArray(resp, "items")
	dialogs := make([]Dialog, 0, len(items))
	for _, item := range items {
		r, _ := item.(map[string]any)
		if r == nil {
			continue
		}
		owner, _ := r["owner"].(map[string]any)
		dialogs = append(dialogs, Dialog{
			ID:       "repo:" + strOf(owner["login"]) + "/" + strOf(r["name"]),
			Type:     ChatTypeGroup,
			Title:    strOf(r["full_name"]),
			Platform: ghPlatform,
		})
	}
	return dialogs, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Typing, Polls, Stickers, Sessions
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) SendTyping(_ string) error {
	// GitHub has no typing indicator concept
	return nil
}

func (g *GitHubCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	// Build markdown poll with reaction-based voting
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("## 📊 %s\n\n", question))
	for i, opt := range options {
		sb.WriteString(fmt.Sprintf("- [ ] **%d.** %s — react with %s to vote\n", i+1, opt, pollEmojis[i%len(pollEmojis)]))
	}
	sb.WriteString("\n*Vote by reacting to this message with the corresponding emoji.*")

	return g.SendMessage(chatID, OutgoingMessage{Text: sb.String()})
}

var pollEmojis = []string{"👍", "❤️", "🎉", "🚀", "👀", "😄", "😕", "👎"}

func (g *GitHubCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	if optionIndex >= len(pollEmojis) {
		return fmt.Errorf("%w: option index out of range", ErrInvalidInput)
	}
	return g.ReactToMessage(chatID, msgID, pollEmojis[optionIndex])
}

func (g *GitHubCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	// Send emoji as a message
	return g.SendMessage(chatID, OutgoingMessage{Text: stickerID})
}

func (g *GitHubCore) GetSessions() ([]Session, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	return []Session{{
		ID:         "pat",
		Device:     "Personal Access Token",
		Platform:   ghPlatform,
		AppName:    "Uniclient",
		LastActive: time.Now(),
		IsCurrent:  true,
	}}, nil
}

func (g *GitHubCore) TerminateSession(_ string) error {
	return fmt.Errorf("%w: github cannot revoke PAT via API", ErrNotSupported)
}

// ════════════════════════════════════════════════════════════════════════════════
// DM System — Profile Repo Convention
//
// Strategy: use {username}/{username} (the profile README repo) as the DM target.
// Most active GitHub users already have this repo — it's the canonical identity
// location on GitHub. To DM someone, we open an issue on their profile repo
// ({peer}/{peer}) with title "Uniclient DM — {sender}".
//
// For receiving DMs: we ensure our OWN profile repo exists on auth.
// ════════════════════════════════════════════════════════════════════════════════

// ensureProfileRepo ensures the user's profile repo ({username}/{username}) exists
// for receiving DMs. Creates it if missing — this also gives them a profile README.
func (g *GitHubCore) ensureProfileRepo() error {
	// Check if profile repo already exists
	_, err := g.apiGet(ghRepoPath(g.username, g.username), nil)
	if err == nil {
		return nil // already exists
	}

	// Create it — enables issues (for DMs) and auto_init (so it shows on profile)
	_, err = g.apiPost("/user/repos", map[string]any{
		"name":        g.username,
		"description": "My GitHub profile",
		"has_issues":  true,
		"auto_init":   true,
	})
	return err
}

// sendDMMessage sends a message to a DM conversation.
// chatID format: "dm:{username}" — routes to the profile repo that holds the DM issue.
func (g *GitHubCore) sendDMMessage(chatID string, text string) (*Message, error) {
	peerUser := strings.TrimPrefix(chatID, "dm:")

	issueNum, err := g.findOrCreateDMIssue(peerUser)
	if err != nil {
		return nil, fmt.Errorf("dm setup: %w", err)
	}

	owner, repo := g.dmIssueLocation(peerUser, issueNum)
	resp, err := g.apiPost(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNum) + "/comments", map[string]any{
		"body": text,
	})
	if err != nil {
		return nil, err
	}

	msg := g.commentToMessage(chatID, resp)
	g.cacheMessage(chatID, msg)
	g.touchThread(chatID)
	return msg, nil
}

// findOrCreateDMIssue finds an existing DM issue or creates one on the peer's
// profile repo ({peer}/{peer}). Returns (issue_number, error).
func (g *GitHubCore) findOrCreateDMIssue(peerUser string) (int, error) {
	// Check dialog cache first (0 API calls)
	g.dialogsMu.RLock()
	if dlg, ok := g.dialogs["dm:"+peerUser]; ok && dlg.IssueNum > 0 {
		g.dialogsMu.RUnlock()
		return dlg.IssueNum, nil
	}
	g.dialogsMu.RUnlock()

	// Check session-persistent cache (0 API calls, survives restarts)
	g.dmIssuesMu.RLock()
	if info, ok := g.dmIssues[peerUser]; ok && info.IssueNum > 0 {
		g.dmIssuesMu.RUnlock()
		g.cacheDMDialog(peerUser, info.IssueNum, info.RepoOwner, info.RepoName)
		return info.IssueNum, nil
	}
	g.dmIssuesMu.RUnlock()

	// Search for existing DM issue we created on their profile repo
	resp, err := g.apiGet(ghRepoPath(peerUser, peerUser) + "/issues", map[string]string{
		"creator": g.username,
		"state":   "open",
	})
	if err != nil {
		return 0, fmt.Errorf("user %q has no profile repo (%s/%s) — they need to enable DMs by creating a %s/%s repository with issues enabled: %w",
			peerUser, peerUser, peerUser, peerUser, peerUser, err)
	}

	var issues []map[string]any
	json.Unmarshal(resp, &issues)

	for _, issue := range issues {
		title := strOf(issue["title"])
		if strings.HasPrefix(title, ghDMPrefix) {
			num := int(gjsonMapFloat(issue, "number"))
			g.cacheDMDialog(peerUser, num, peerUser, peerUser)
			return num, nil
		}
	}

	// Check if the PEER created a DM issue to US on OUR profile repo
	// (they might have initiated the conversation — check our repo too)
	resp2, err := g.apiGet(ghRepoPath(g.username, g.username) + "/issues", map[string]string{
		"state": "open",
	})
	if err == nil {
		var ourIssues []map[string]any
		json.Unmarshal(resp2, &ourIssues)
		for _, issue := range ourIssues {
			title := strOf(issue["title"])
			if title == ghDMPrefix+peerUser {
				// They messaged us on OUR repo
				num := int(gjsonMapFloat(issue, "number"))
				g.cacheDMDialog(peerUser, num, g.username, g.username)
				return num, nil
			}
		}
	}

	// No existing DM thread — create one on peer's profile repo
	body := map[string]any{
		"title": ghDMPrefix + g.username,
		"body":  fmt.Sprintf("DM from @%s via [Uniclient](https://github.com/DarkReaperBoy/uniclient).", g.username),
	}
	// Only add label if we own the repo (can't create labels on someone else's repo)
	if strings.EqualFold(peerUser, g.username) {
		body["labels"] = []string{ghDMLabel}
	}
	resp3, err := g.apiPost(ghRepoPath(peerUser, peerUser) + "/issues", body)
	if err != nil {
		return 0, err
	}

	num := int(gjsonFloat(resp3, "number"))
	g.cacheDMDialog(peerUser, num, peerUser, peerUser)
	return num, nil
}

func (g *GitHubCore) getDMMessages(chatID string, limit int, cursor string) ([]Message, error) {
	peerUser := strings.TrimPrefix(chatID, "dm:")

	issueNum, err := g.findOrCreateDMIssue(peerUser)
	if err != nil {
		return nil, err
	}

	// DM issue lives on peer's profile repo ({peer}/{peer})
	// But if the peer initiated, the issue is on OUR profile repo ({us}/{us})
	// We need to figure out which repo holds this issue
	owner, repo := g.dmIssueLocation(peerUser, issueNum)

	params := map[string]string{
		"per_page":  strconv.Itoa(limit),
		"sort":      "created",
		"direction": "desc",
	}
	if cursor != "" {
		params["page"] = cursor
	}

	resp, err := g.apiGetConditional(
		ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNum) + "/comments",
		params, chatID,
	)
	if err != nil {
		if errors.Is(err, errNotModified) {
			return g.getCachedMessages(chatID, limit), nil
		}
		return nil, err
	}

	var comments []json.RawMessage
	json.Unmarshal(resp, &comments)

	msgs := make([]Message, 0, len(comments))
	for _, raw := range comments {
		msgs = append(msgs, *g.commentToMessage(chatID, raw))
	}

	// Cache
	g.messagesMu.Lock()
	msgPtrs := make([]*Message, len(msgs))
	for i := range msgs {
		msgPtrs[i] = &msgs[i]
	}
	g.messages[chatID] = msgPtrs
	g.messagesMu.Unlock()

	return msgs, nil
}

// dmIssueLocation determines which profile repo holds a DM issue.
// Uses dialog/session cache to avoid speculative API calls.
func (g *GitHubCore) dmIssueLocation(peerUser string, issueNum int) (owner, repo string) {
	// Check dialog cache (populated by findOrCreateDMIssue)
	g.dialogsMu.RLock()
	if dlg, ok := g.dialogs["dm:"+peerUser]; ok {
		g.dialogsMu.RUnlock()
		return dlg.Owner, dlg.Repo
	}
	g.dialogsMu.RUnlock()

	// Check session-persistent cache
	g.dmIssuesMu.RLock()
	if info, ok := g.dmIssues[peerUser]; ok {
		g.dmIssuesMu.RUnlock()
		return info.RepoOwner, info.RepoName
	}
	g.dmIssuesMu.RUnlock()

	// Fallback: speculative check (rare — only if cache was cleared)
	_, err := g.apiGet(ghRepoPath(peerUser, peerUser) + "/issues/" + strconv.Itoa(issueNum), nil)
	if err == nil {
		return peerUser, peerUser
	}
	return g.username, g.username
}

// fetchDMDialogs finds all DM conversations on profile repos.
func (g *GitHubCore) fetchDMDialogs() ([]Dialog, error) {
	dialogs := []Dialog{}
	seen := make(map[string]bool)

	// 1. Issues on OUR profile repo (people messaging us via {us}/{us})
	resp, err := g.apiGet(ghRepoPath(g.username, g.username) + "/issues", map[string]string{
		"state": "open",
	})
	if err == nil {
		var issues []map[string]any
		json.Unmarshal(resp, &issues)
		for _, issue := range issues {
			title := strOf(issue["title"])
			if !strings.HasPrefix(title, ghDMPrefix) {
				continue
			}
			peerUser := strings.TrimPrefix(title, ghDMPrefix)
			if seen[peerUser] {
				continue
			}
			seen[peerUser] = true

			num := int(gjsonMapFloat(issue, "number"))
			user, _ := issue["user"].(map[string]any)
			g.cacheDMDialog(peerUser, num, g.username, g.username) // on OUR repo

			updatedAt, _ := time.Parse(time.RFC3339, strOf(issue["updated_at"]))
			dialogs = append(dialogs, Dialog{
				ID:          "dm:" + peerUser,
				Type:        ChatTypeDM,
				Title:       peerUser,
				AvatarURL:   strOf(user["avatar_url"]),
				LastMessage: &Message{Timestamp: updatedAt, Platform: ghPlatform},
				Platform:    ghPlatform,
			})
		}
	}

	// 2. Issues WE created on others' profile repos (us messaging them)
	searchResp, err := g.apiGet("/search/issues", map[string]string{
		"q":        fmt.Sprintf("author:%s \"%s\" in:title", g.username, "Uniclient DM"),
		"per_page": "30",
	})
	if err == nil {
		items := gjsonArray(searchResp, "items")
		for _, item := range items {
			issue, _ := item.(map[string]any)
			if issue == nil {
				continue
			}
			repoURL := strOf(issue["repository_url"])
			parts := strings.Split(repoURL, "/")
			if len(parts) < 2 {
				continue
			}
			peerUser := parts[len(parts)-2] // repo owner = peer (profile repo)
			if peerUser == g.username || seen[peerUser] {
				continue
			}
			seen[peerUser] = true

			num := int(gjsonMapFloat(issue, "number"))
			g.cacheDMDialog(peerUser, num, peerUser, peerUser) // on PEER's repo

			updatedAt, _ := time.Parse(time.RFC3339, strOf(issue["updated_at"]))
			dialogs = append(dialogs, Dialog{
				ID:          "dm:" + peerUser,
				Type:        ChatTypeDM,
				Title:       peerUser,
				LastMessage: &Message{Timestamp: updatedAt, Platform: ghPlatform},
				Platform:    ghPlatform,
			})
		}
	}

	return dialogs, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Group Chat — Repos with Issues as Channels
//
// Architecture: repo = group, issues = channels, comments = messages.
// Every group has a pinned "General" issue as the default channel.
// Additional issues are topic channels. Collaborators = members.
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) fetchGroupDialogs() ([]Dialog, error) {
	// Fetch repos we participate in (1 API call)
	resp, err := g.apiGet("/user/repos", map[string]string{
		"per_page":  "50",
		"sort":      "updated",
		"direction": "desc",
	})
	if err != nil {
		// On error, return whatever we have cached (0 API calls)
		return g.cachedGroupDialogs(), nil
	}

	var repos []map[string]any
	json.Unmarshal(resp, &repos)

	dialogs := []Dialog{}
	newChecks := 0

	for _, r := range repos {
		name := strOf(r["name"])
		owner, _ := r["owner"].(map[string]any)
		ownerLogin := strOf(owner["login"])

		// Skip profile repos (those are for DMs)
		if name == ownerLogin {
			continue
		}

		fullName := ownerLogin + "/" + name
		chatID := "repo:" + fullName
		updatedAt, _ := time.Parse(time.RFC3339, strOf(r["updated_at"]))

		// Check session cache first (0 API calls)
		g.groupReposMu.RLock()
		generalNum, known := g.groupRepos[fullName]
		g.groupReposMu.RUnlock()

		if !known {
			// Description-based filter: "Uniclient group chat" (local check, 0 API calls)
			desc := strOf(r["description"])
			if !strings.HasPrefix(desc, "Uniclient group") {
				continue
			}
			// Verify with findGeneralIssue — but cap at 3 new discoveries per cycle
			// to avoid N+1 burst. Remaining repos discovered next cycle.
			if newChecks >= 3 {
				continue
			}
			generalNum = g.findGeneralIssue(ownerLogin, name)
			if generalNum == 0 {
				continue
			}
			g.groupReposMu.Lock()
			g.groupRepos[fullName] = generalNum
			g.groupReposMu.Unlock()
			g.saveSession()
			newChecks++
		}

		g.dialogsMu.Lock()
		g.dialogs[chatID] = &ghDialog{
			ChatID:    chatID,
			Type:      ChatTypeGroup,
			Title:     fullName,
			Owner:     ownerLogin,
			Repo:      name,
			IssueNum:  generalNum,
			AvatarURL: strOf(owner["avatar_url"]),
		}
		g.dialogsMu.Unlock()

		dialogs = append(dialogs, Dialog{
			ID:          chatID,
			Type:        ChatTypeGroup,
			Title:       ownerLogin + "/" + name,
			AvatarURL:   strOf(owner["avatar_url"]),
			LastMessage: &Message{Timestamp: updatedAt, Platform: ghPlatform},
			Platform:    ghPlatform,
		})
	}

	// Include cached groups not in the repos list (collaborator on other user's repos
	// beyond the first 50 results)
	g.groupReposMu.RLock()
	for fullName, generalNum := range g.groupRepos {
		chatID := "repo:" + fullName
		alreadyListed := false
		for _, d := range dialogs {
			if d.ID == chatID {
				alreadyListed = true
				break
			}
		}
		if !alreadyListed {
			parts := strings.SplitN(fullName, "/", 2)
			if len(parts) == 2 {
				g.dialogsMu.Lock()
				g.dialogs[chatID] = &ghDialog{
					ChatID:   chatID,
					Type:     ChatTypeGroup,
					Title:    fullName,
					Owner:    parts[0],
					Repo:     parts[1],
					IssueNum: generalNum,
				}
				g.dialogsMu.Unlock()
				dialogs = append(dialogs, Dialog{
					ID:       chatID,
					Type:     ChatTypeGroup,
					Title:    fullName,
					Platform: ghPlatform,
				})
			}
		}
	}
	g.groupReposMu.RUnlock()

	return dialogs, nil
}

// cachedGroupDialogs returns groups from session cache when API is unavailable.
func (g *GitHubCore) cachedGroupDialogs() []Dialog {
	g.groupReposMu.RLock()
	defer g.groupReposMu.RUnlock()
	var dialogs []Dialog
	for fullName := range g.groupRepos {
		dialogs = append(dialogs, Dialog{
			ID:       "repo:" + fullName,
			Type:     ChatTypeGroup,
			Title:    fullName,
			Platform: ghPlatform,
		})
	}
	return dialogs
}

// findGeneralIssue looks for the "General" issue in a repo (our group chat marker).
// Returns the issue number, or 0 if not found.
func (g *GitHubCore) findGeneralIssue(owner, repo string) int {
	resp, err := g.apiGet(ghRepoPath(owner, repo) + "/issues", map[string]string{
		"state": "open",
	})
	if err != nil {
		return 0
	}
	var issues []map[string]any
	json.Unmarshal(resp, &issues)
	for _, issue := range issues {
		if strOf(issue["title"]) == ghGeneralTitle {
			return int(gjsonMapFloat(issue, "number"))
		}
	}
	return 0
}

func (g *GitHubCore) sendIssueComment(chatID string, text string) (*Message, error) {
	owner, repo, numStr := g.parseIssueChat(chatID)
	if owner == "" {
		return nil, fmt.Errorf("%w: invalid channel ID %q (expected issue:owner/repo/number)", ErrInvalidInput, chatID)
	}
	resp, err := g.apiPost(ghRepoPath(owner, repo) + "/issues/" + numStr + "/comments", map[string]any{
		"body": text,
	})
	if err != nil {
		return nil, err
	}
	msg := g.commentToMessage(chatID, resp)
	g.cacheMessage(chatID, msg)
	g.touchThread(chatID)
	return msg, nil
}

func (g *GitHubCore) getIssueMessages(chatID string, limit int, cursor string) ([]Message, error) {
	owner, repo, numStr := g.parseIssueChat(chatID)
	if owner == "" {
		return nil, fmt.Errorf("%w: invalid channel ID %q (expected issue:owner/repo/number)", ErrInvalidInput, chatID)
	}

	params := map[string]string{
		"per_page":  strconv.Itoa(limit),
		"sort":      "created",
		"direction": "desc",
	}
	if cursor != "" {
		params["page"] = cursor
	}

	resp, err := g.apiGetConditional(
		ghRepoPath(owner, repo) + "/issues/" + numStr + "/comments",
		params, chatID,
	)
	if err != nil {
		if errors.Is(err, errNotModified) {
			return g.getCachedMessages(chatID, limit), nil
		}
		return nil, err
	}

	var comments []json.RawMessage
	json.Unmarshal(resp, &comments)

	msgs := make([]Message, 0, len(comments))
	for _, raw := range comments {
		msgs = append(msgs, *g.commentToMessage(chatID, raw))
	}
	return msgs, nil
}

// sendRepoMessage sends a message to a group's default "General" channel.
func (g *GitHubCore) sendRepoMessage(chatID string, text string) (*Message, error) {
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return nil, err
	}

	// Find the "General" issue (default channel)
	generalNum := g.findGeneralIssue(owner, repo)
	if generalNum == 0 {
		return nil, fmt.Errorf("%w: no General channel found in %s/%s (not a Uniclient group?)", ErrNotFound, owner, repo)
	}

	// Post as a comment on the General issue
	generalChatID := fmt.Sprintf("issue:%s/%s/%d", owner, repo, generalNum)
	return g.sendIssueComment(generalChatID, text)
}

// getRepoMessages returns messages from a group: lists channels (issues) as summary messages,
// plus recent comments from the "General" channel.
func (g *GitHubCore) getRepoMessages(chatID string, limit int) ([]Message, error) {
	owner, repo, err := g.parseRepoChat(chatID)
	if err != nil {
		return nil, err
	}

	// Fetch open issues (channels) in this group
	resp, err := g.apiGet(ghRepoPath(owner, repo) + "/issues", map[string]string{
		"state":    "open",
		"per_page": strconv.Itoa(limit),
		"sort":     "updated",
	})
	if err != nil {
		return nil, err
	}

	var issues []map[string]any
	json.Unmarshal(resp, &issues)

	msgs := make([]Message, 0, len(issues))
	for _, issue := range issues {
		user, _ := issue["user"].(map[string]any)
		ts, _ := time.Parse(time.RFC3339, strOf(issue["updated_at"]))
		num := int(gjsonMapFloat(issue, "number"))
		comments := int(gjsonMapFloat(issue, "comments"))

		msgs = append(msgs, Message{
			ID:         "issue:" + owner + "/" + repo + "/" + strconv.Itoa(num),
			ChatID:     chatID,
			SenderID:   strOf(user["login"]),
			SenderName: strOf(user["login"]),
			Text:       fmt.Sprintf("**#%d %s** (%d messages)", num, strOf(issue["title"]), comments),
			Timestamp:  ts,
			Status:     MessageStatusSent,
			Platform:   ghPlatform,
		})
	}
	return msgs, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Polling Loop — Adaptive, Conditional, Notification-multiplexed
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) pollLoop() {
	defer g.wg.Done()
	interval := ghNotifPoll
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-g.ctx.Done():
			return
		case <-ticker.C:
			// Budget-aware: triple the poll interval when rate limit is getting low.
			// Notification 304s are free, but 200s (actual changes) count.
			if g.rl.isLowBudget() {
				if newInterval := 3 * ghNotifPoll; newInterval != interval {
					interval = newInterval
					ticker.Reset(interval)
				}
			} else if interval != ghNotifPoll {
				interval = ghNotifPoll
				ticker.Reset(interval)
			}

			g.pollNotifications()
		}
	}
}

func (g *GitHubCore) pollNotifications() {
	headers := map[string]string{}
	if g.notifLastModified != "" {
		headers["If-Modified-Since"] = g.notifLastModified
	}
	if g.notifEtag != "" {
		headers["If-None-Match"] = g.notifEtag
	}

	req, _ := http.NewRequestWithContext(g.ctx, "GET", ghAPIBase+"/notifications", nil)
	req.Header.Set("Authorization", "Bearer "+g.token)
	req.Header.Set("Accept", "application/vnd.github+json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := g.client.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()

	// Save conditional headers for next request (304s are FREE)
	if lm := resp.Header.Get("Last-Modified"); lm != "" {
		g.notifLastModified = lm
	}
	if etag := resp.Header.Get("ETag"); etag != "" {
		g.notifEtag = etag
	}

	if resp.StatusCode == 304 {
		return // nothing new, and this request was FREE
	}

	body, _ := io.ReadAll(resp.Body)
	var notifs []map[string]any
	json.Unmarshal(body, &notifs)

	for _, n := range notifs {
		g.processNotification(n)
	}
}

func (g *GitHubCore) processNotification(n map[string]any) {
	subject, _ := n["subject"].(map[string]any)
	if subject == nil {
		return
	}

	subjectType := strOf(subject["type"])
	subjectURL := strOf(subject["latest_comment_url"])
	if subjectURL == "" {
		subjectURL = strOf(subject["url"])
	}

	repo, _ := n["repository"].(map[string]any)
	if repo == nil {
		return
	}
	repoFullName := strOf(repo["full_name"])

	// Determine chatID from notification context
	var chatID string
	switch subjectType {
	case "Issue":
		// Could be DM or regular issue
		title := strOf(subject["title"])
		if strings.HasPrefix(title, ghDMPrefix) {
			peerUser := strings.TrimPrefix(title, ghDMPrefix)
			chatID = "dm:" + peerUser
		} else {
			// Extract issue number from URL
			url := strOf(subject["url"])
			if num := extractTrailingNumber(url); num != "" {
				chatID = "issue:" + repoFullName + "/" + num
			}
		}
	default:
		return // skip non-conversation notifications
	}

	if chatID == "" {
		return
	}

	// Fetch the latest comment if URL available
	if subjectURL != "" {
		data, err := g.apiGetRaw(subjectURL)
		if err == nil {
			msg := g.commentToMessage(chatID, data)
			if msg.SenderID != g.username {
				g.fireUpdate(Update{
					Type:     UpdateNewMessage,
					ChatID:   chatID,
					Message:  msg,
					Platform: ghPlatform,
				})
			}
		}
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// REST API Helpers — Rate-limited, Retry-aware, Cached
// ════════════════════════════════════════════════════════════════════════════════

var errNotModified = errors.New("not modified")

type ghTransport struct {
	token string
	inner http.RoundTripper
}

func (t *ghTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req.Header.Set("Authorization", "Bearer "+t.token)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "Uniclient/1.0 (+https://github.com/DarkReaperBoy/uniclient)")
	return t.inner.RoundTrip(req)
}

func (g *GitHubCore) makeHTTPClient(token string) *http.Client {
	return &http.Client{
		Timeout:   30 * time.Second,
		Transport: &ghTransport{token: token, inner: http.DefaultTransport},
	}
}

// doAPI executes an HTTP request with rate limiting, automatic retry, and backoff.
// All API helpers route through this — it's the single enforcement point for pacing,
// retry on 429/5xx/secondary-403, and rate limit header tracking.
func (g *GitHubCore) doAPI(method, url string, body []byte, extraHeaders map[string]string) (json.RawMessage, int, http.Header, error) {
	isWrite := method != "GET" && method != "HEAD"

	for attempt := range 4 {
		// Rate limiter: pace requests, enforce min intervals
		g.rl.wait(g.ctx, isWrite)

		var bodyReader io.Reader
		if body != nil {
			bodyReader = bytes.NewReader(body)
		}

		req, err := http.NewRequestWithContext(g.ctx, method, url, bodyReader)
		if err != nil {
			return nil, 0, nil, err
		}
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		for k, v := range extraHeaders {
			req.Header.Set(k, v)
		}

		resp, err := g.client.Do(req)
		if err != nil {
			if attempt < 3 {
				sleepCtx(g.ctx, ghBackoffDelay(attempt, 500*time.Millisecond))
				continue
			}
			return nil, 0, nil, fmt.Errorf("%w: %v", ErrNetwork, err)
		}

		respBody, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		// Track rate limit budget from every response
		g.rl.updateFromHeaders(resp.Header)

		// 429 Too Many Requests — honor Retry-After
		if resp.StatusCode == 429 && attempt < 3 {
			sleepCtx(g.ctx, ghParseRetryAfter(resp.Header))
			continue
		}

		// 5xx server error — retry with exponential backoff
		if resp.StatusCode >= 500 && attempt < 3 {
			sleepCtx(g.ctx, ghBackoffDelay(attempt, time.Second))
			continue
		}

		// 403: distinguish primary rate limit / secondary abuse / genuine permission error
		if resp.StatusCode == 403 && attempt < 3 {
			if g.rl.isExhausted() {
				// Primary rate limit — wait for reset window
				sleepCtx(g.ctx, g.rl.waitForReset())
				continue
			}
			if ghIsSecondaryRateLimit(respBody) {
				// Abuse detection — aggressive backoff
				sleepCtx(g.ctx, ghBackoffDelay(attempt, 5*time.Second))
				continue
			}
			// Genuine 403 (permission) — don't retry
		}

		return respBody, resp.StatusCode, resp.Header, nil
	}
	return nil, 0, nil, fmt.Errorf("%w: max retries exceeded", ErrNetwork)
}

func (g *GitHubCore) buildURL(path string, params map[string]string) string {
	u := ghAPIBase + path
	if len(params) > 0 {
		v := neturl.Values{}
		for k, val := range params {
			v.Set(k, val)
		}
		u += "?" + v.Encode()
	}
	return u
}

func (g *GitHubCore) apiGet(path string, params map[string]string) (json.RawMessage, error) {
	url := g.buildURL(path, params)

	// Check response cache first (avoids API call entirely)
	if data := g.cache.get(url); data != nil {
		return data, nil
	}

	body, status, _, err := g.doAPI("GET", url, nil, nil)
	if err != nil {
		return nil, err
	}

	switch {
	case status == 404:
		return nil, ErrNotFound
	case status == 403:
		return nil, ErrPermission
	case status >= 400:
		return nil, fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}

	g.cache.set(url, body, 2*time.Minute)
	return body, nil
}

// apiGetConditional uses ETag/If-None-Match for free 304 polling.
func (g *GitHubCore) apiGetConditional(path string, params map[string]string, cacheKey string) (json.RawMessage, error) {
	url := g.buildURL(path, params)

	headers := map[string]string{}
	g.threadETagsMu.RLock()
	if etag := g.threadETags[cacheKey]; etag != "" {
		headers["If-None-Match"] = etag
	}
	g.threadETagsMu.RUnlock()

	body, status, respHeaders, err := g.doAPI("GET", url, nil, headers)
	if err != nil {
		return nil, err
	}

	if respHeaders != nil {
		if newEtag := respHeaders.Get("ETag"); newEtag != "" {
			g.threadETagsMu.Lock()
			g.threadETags[cacheKey] = newEtag
			g.threadETagsMu.Unlock()
		}
	}

	if status == 304 {
		return nil, errNotModified
	}
	if status >= 400 {
		return nil, fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}
	return body, nil
}

func (g *GitHubCore) apiGetRaw(rawURL string) (json.RawMessage, error) {
	body, status, _, err := g.doAPI("GET", rawURL, nil, nil)
	if err != nil {
		return nil, err
	}
	if status >= 400 {
		return nil, fmt.Errorf("github API error %d", status)
	}
	return body, nil
}

func (g *GitHubCore) apiPost(path string, payload any) (json.RawMessage, error) {
	return g.apiMutate("POST", path, payload)
}

func (g *GitHubCore) apiPatch(path string, payload any) (json.RawMessage, error) {
	return g.apiMutate("PATCH", path, payload)
}

func (g *GitHubCore) apiPut(path string, payload any) (json.RawMessage, error) {
	return g.apiMutate("PUT", path, payload)
}

func (g *GitHubCore) apiDelete(path string) (json.RawMessage, error) {
	body, status, _, err := g.doAPI("DELETE", ghAPIBase+path, nil, nil)
	if err != nil {
		return nil, err
	}
	if status >= 400 {
		return nil, fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}
	return body, nil
}

func (g *GitHubCore) apiMutate(method, path string, payload any) (json.RawMessage, error) {
	var data []byte
	if payload != nil {
		data, _ = json.Marshal(payload)
	}

	body, status, _, err := g.doAPI(method, ghAPIBase+path, data, nil)
	if err != nil {
		return nil, err
	}

	switch {
	case status == 404:
		return nil, ErrNotFound
	case status == 422:
		return nil, fmt.Errorf("%w: %s", ErrInvalidInput, truncate(string(body), 200))
	case status >= 400:
		return nil, fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}

	// Invalidate cached responses for the affected resource
	g.cache.invalidatePrefix(ghAPIBase + path)

	return body, nil
}

func (g *GitHubCore) apiGetUser(username string) (*User, error) {
	path := "/user"
	if username != "" {
		path = "/users/" + username
	}
	resp, err := g.apiGet(path, nil)
	if err != nil {
		return nil, err
	}

	var u struct {
		ID        float64 `json:"id"`
		Login     string  `json:"login"`
		Name      string  `json:"name"`
		AvatarURL string  `json:"avatar_url"`
		Type      string  `json:"type"`
	}
	json.Unmarshal(resp, &u)

	return &User{
		ID:          ghIntStr(u.ID),
		Username:    u.Login,
		DisplayName: u.Name,
		AvatarURL:   u.AvatarURL,
		IsBot:       u.Type == "Bot",
		Platform:    ghPlatform,
	}, nil
}

// ════════════════════════════════════════════════════════════════════════════════
// Rate Limiter Methods
// ════════════════════════════════════════════════════════════════════════════════

// wait enforces minimum intervals between requests and slows down when budget is low.
func (rl *ghRateLimiter) wait(ctx context.Context, isWrite bool) {
	rl.mu.Lock()
	now := time.Now()

	var delay time.Duration

	// Enforce minimum interval between any two requests
	if since := now.Sub(rl.lastRequest); since < rl.readDelay {
		delay = rl.readDelay - since
	}

	// Mutations get a longer delay (prevents abuse detection)
	if isWrite {
		if writeSince := now.Sub(rl.lastWrite); writeSince < rl.writeDelay {
			writeWait := rl.writeDelay - writeSince
			if writeWait > delay {
				delay = writeWait
			}
		}
		rl.lastWrite = now.Add(delay)
	}

	// Budget-aware slowdown: back off as we approach limits
	if rl.remaining > 0 && rl.remaining < 100 {
		delay += 3 * time.Second // critical: <2% budget left
	} else if rl.remaining > 0 && rl.remaining < 500 {
		delay += 500 * time.Millisecond // caution: <10% budget left
	}

	rl.lastRequest = now.Add(delay)
	rl.mu.Unlock()

	if delay > 0 {
		sleepCtx(ctx, delay)
	}
}

// updateFromHeaders reads X-RateLimit-* from every response to track budget.
func (rl *ghRateLimiter) updateFromHeaders(h http.Header) {
	if h == nil {
		return
	}
	rl.mu.Lock()
	defer rl.mu.Unlock()
	if rem := h.Get("X-RateLimit-Remaining"); rem != "" {
		rl.remaining, _ = strconv.Atoi(rem)
	}
	if reset := h.Get("X-RateLimit-Reset"); reset != "" {
		ts, _ := strconv.ParseInt(reset, 10, 64)
		rl.resetAt = time.Unix(ts, 0)
	}
}

// isExhausted returns true if we've burned through all API quota.
func (rl *ghRateLimiter) isExhausted() bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	return rl.remaining == 0 && time.Now().Before(rl.resetAt)
}

// waitForReset returns how long to sleep before the rate limit window resets.
func (rl *ghRateLimiter) waitForReset() time.Duration {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	d := time.Until(rl.resetAt) + time.Second
	if d < time.Second {
		d = time.Second
	}
	if d > 60*time.Second {
		d = 60 * time.Second // cap: don't block for the full hour
	}
	return d
}

// isLowBudget returns true when we should reduce non-essential activity.
func (rl *ghRateLimiter) isLowBudget() bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	return rl.remaining > 0 && rl.remaining < 500
}

// ════════════════════════════════════════════════════════════════════════════════
// Response Cache Methods
// ════════════════════════════════════════════════════════════════════════════════

func (c *ghCache) get(key string) json.RawMessage {
	c.mu.RLock()
	defer c.mu.RUnlock()
	item := c.items[key]
	if item == nil || time.Now().After(item.expires) {
		return nil
	}
	return item.data
}

func (c *ghCache) set(key string, data json.RawMessage, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.items[key] = &ghCacheItem{data: data, expires: time.Now().Add(ttl)}
	// Lazy eviction when cache grows large
	if len(c.items) > 200 {
		now := time.Now()
		for k, v := range c.items {
			if now.After(v.expires) {
				delete(c.items, k)
			}
		}
	}
}

func (c *ghCache) invalidatePrefix(prefix string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for k := range c.items {
		if strings.HasPrefix(k, prefix) {
			delete(c.items, k)
		}
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// Retry & Rate Limit Helpers (package-level)
// ════════════════════════════════════════════════════════════════════════════════

// sleepCtx sleeps for d, but returns early if ctx is cancelled.
func sleepCtx(ctx context.Context, d time.Duration) {
	if d <= 0 {
		return
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}

// ghBackoffDelay computes exponential backoff with jitter.
func ghBackoffDelay(attempt int, base time.Duration) time.Duration {
	delay := base
	for range attempt {
		delay *= 2
	}
	// Jitter: add 0-25% to prevent thundering herd
	jitter := time.Duration(time.Now().UnixNano() % int64(delay/4+1))
	return delay + jitter
}

// ghIsSecondaryRateLimit detects GitHub's abuse/secondary rate limit responses.
func ghIsSecondaryRateLimit(body []byte) bool {
	s := string(body)
	return strings.Contains(s, "secondary rate") || strings.Contains(s, "Secondary rate") ||
		strings.Contains(s, "abuse detection") || strings.Contains(s, "Abuse detection") ||
		strings.Contains(s, "you have exceeded a secondary rate limit") ||
		strings.Contains(s, "You have exceeded a secondary rate limit")
}

// ghParseRetryAfter extracts wait time from 429 response headers.
func ghParseRetryAfter(h http.Header) time.Duration {
	if ra := h.Get("Retry-After"); ra != "" {
		if secs, err := strconv.Atoi(ra); err == nil {
			return time.Duration(secs) * time.Second
		}
	}
	return 60 * time.Second // conservative default
}

// ════════════════════════════════════════════════════════════════════════════════
// Session Persistence
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) loadSession() error {
	data, err := os.ReadFile(g.sessionPath)
	if err != nil {
		return err
	}
	var sess ghSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return err
	}
	g.token = sess.Token
	g.username = sess.Username
	g.userID = sess.UserID

	for _, b := range sess.Blocked {
		g.blocked[b] = true
	}
	if sess.Pinned != nil {
		for chatID, msgIDs := range sess.Pinned {
			g.pinned[chatID] = make(map[string]bool)
			for _, id := range msgIDs {
				g.pinned[chatID][id] = true
			}
		}
	}
	if sess.ReadState != nil {
		g.readState = sess.ReadState
	}
	// Restore persistent DM & group caches
	if sess.DMIssues != nil {
		g.dmIssues = sess.DMIssues
	}
	if sess.GroupRepos != nil {
		g.groupRepos = sess.GroupRepos
	}
	return nil
}

func (g *GitHubCore) saveSession() {
	sess := ghSession{
		Token:    g.token,
		Username: g.username,
		UserID:   g.userID,
	}

	g.blockedMu.RLock()
	for b := range g.blocked {
		sess.Blocked = append(sess.Blocked, b)
	}
	g.blockedMu.RUnlock()

	g.pinnedMu.RLock()
	sess.Pinned = make(map[string][]string)
	for chatID, msgs := range g.pinned {
		for msgID := range msgs {
			sess.Pinned[chatID] = append(sess.Pinned[chatID], msgID)
		}
	}
	g.pinnedMu.RUnlock()

	g.readStateMu.RLock()
	sess.ReadState = g.readState
	g.readStateMu.RUnlock()

	// Persist DM & group caches (survives restarts)
	g.dmIssuesMu.RLock()
	sess.DMIssues = g.dmIssues
	g.dmIssuesMu.RUnlock()

	g.groupReposMu.RLock()
	sess.GroupRepos = g.groupRepos
	g.groupReposMu.RUnlock()

	data, _ := json.MarshalIndent(sess, "", "  ")
	os.MkdirAll(filepath.Dir(g.sessionPath), 0o755)
	os.WriteFile(g.sessionPath, data, 0o600)
}

// ════════════════════════════════════════════════════════════════════════════════
// Internal Helpers
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) fireUpdate(u Update) {
	g.updateMu.RLock()
	handlers := make([]func(Update), len(g.updateHandlers))
	copy(handlers, g.updateHandlers)
	g.updateMu.RUnlock()
	for _, h := range handlers {
		h(u)
	}
}

func (g *GitHubCore) commentToMessage(chatID string, raw json.RawMessage) *Message {
	var c map[string]any
	json.Unmarshal(raw, &c)

	user, _ := c["user"].(map[string]any)
	if user == nil {
		user, _ = c["author"].(map[string]any)
	}

	ts, _ := time.Parse(time.RFC3339, strOf(c["created_at"]))
	if ts.IsZero() {
		ts, _ = time.Parse(time.RFC3339, strOf(c["createdAt"]))
	}

	var editedAt *time.Time
	if ua := strOf(c["updated_at"]); ua != "" {
		if t, err := time.Parse(time.RFC3339, ua); err == nil && !t.Equal(ts) {
			editedAt = &t
		}
	}

	commentID := ghIntStr(gjsonMapFloat(c, "id"))
	msgID := "comment:" + commentID

	body := strOf(c["body"])
	if body == "" {
		body = strOf(c["title"])
	}

	return &Message{
		ID:         msgID,
		ChatID:     chatID,
		SenderID:   strOf(user["login"]),
		SenderName: strOf(user["login"]),
		Text:       body,
		Timestamp:  ts,
		EditedAt:   editedAt,
		Status:     MessageStatusSent,
		Reactions:  g.parseRESTReactions(c),
		Platform:   ghPlatform,
	}
}

func (g *GitHubCore) parseRESTReactions(c map[string]any) []Reaction {
	var reactions []Reaction
	for key, emoji := range ghReactionMap {
		if count, ok := c[key].(float64); ok && count > 0 {
			reactions = append(reactions, Reaction{Emoji: emoji, Count: int(count)})
		}
	}
	if r, ok := c["reactions"].(map[string]any); ok {
		for key, emoji := range ghReactionMap {
			if count, ok := r[key].(float64); ok && count > 0 {
				reactions = append(reactions, Reaction{Emoji: emoji, Count: int(count)})
			}
		}
	}
	return reactions
}



func (g *GitHubCore) mapReaction(emoji string) string {
	return ghEmojiToReaction[emoji]
}

// Chat ID parsing helpers

func (g *GitHubCore) parseRepoChat(chatID string) (owner, repo string, err error) {
	s := strings.TrimPrefix(chatID, "repo:")
	parts := strings.SplitN(s, "/", 2)
	if len(parts) != 2 {
		return "", "", fmt.Errorf("%w: invalid repo chat ID: %s", ErrInvalidInput, chatID)
	}
	return parts[0], parts[1], nil
}

func (g *GitHubCore) parseIssueChat(chatID string) (owner, repo, num string) {
	s := strings.TrimPrefix(chatID, "issue:")
	parts := strings.SplitN(s, "/", 3)
	if len(parts) == 3 {
		return parts[0], parts[1], parts[2]
	}
	return "", "", ""
}

func (g *GitHubCore) parseChatOwnerRepo(chatID string) (owner, repo, num string) {
	// DM chats: look up the actual repo from cache (DM issue may live on either party's profile repo)
	if strings.HasPrefix(chatID, "dm:") {
		peerUser := strings.TrimPrefix(chatID, "dm:")
		g.dialogsMu.RLock()
		if dlg, ok := g.dialogs[chatID]; ok {
			g.dialogsMu.RUnlock()
			return dlg.Owner, dlg.Repo, ""
		}
		g.dialogsMu.RUnlock()
		g.dmIssuesMu.RLock()
		if info, ok := g.dmIssues[peerUser]; ok {
			g.dmIssuesMu.RUnlock()
			return info.RepoOwner, info.RepoName, ""
		}
		g.dmIssuesMu.RUnlock()
		// Fallback: assume peer's profile repo
		return peerUser, peerUser, ""
	}

	for _, prefix := range []string{"issue:", "repo:"} {
		if strings.HasPrefix(chatID, prefix) {
			s := strings.TrimPrefix(chatID, prefix)
			parts := strings.SplitN(s, "/", 3)
			switch len(parts) {
			case 3:
				return parts[0], parts[1], parts[2]
			case 2:
				return parts[0], parts[1], ""
			}
		}
	}
	return "", "", ""
}

func (g *GitHubCore) cacheDMDialog(peerUser string, issueNum int, repoOwner, repoName string) {
	chatID := "dm:" + peerUser
	g.dialogsMu.Lock()
	g.dialogs[chatID] = &ghDialog{
		ChatID:   chatID,
		Type:     ChatTypeDM,
		Title:    peerUser,
		Owner:    repoOwner,
		Repo:     repoName,
		IssueNum: issueNum,
		PeerUser: peerUser,
	}
	g.dialogsMu.Unlock()

	// Persist in session cache (survives restarts, avoids re-discovery API calls)
	g.dmIssuesMu.Lock()
	g.dmIssues[peerUser] = &ghDMIssueInfo{
		IssueNum:  issueNum,
		RepoOwner: repoOwner,
		RepoName:  repoName,
	}
	g.dmIssuesMu.Unlock()
}

func (g *GitHubCore) cacheMessage(chatID string, msg *Message) {
	g.messagesMu.Lock()
	g.messages[chatID] = append(g.messages[chatID], msg)
	g.messagesMu.Unlock()
}

// findCachedOrFetchComment searches local cache first, then fetches from API.
func (g *GitHubCore) findCachedOrFetchComment(chatID string, msgID string) *Message {
	// 1. Check local cache
	g.messagesMu.RLock()
	for _, m := range g.messages[chatID] {
		if m.ID == msgID {
			g.messagesMu.RUnlock()
			return m
		}
	}
	g.messagesMu.RUnlock()

	// 2. Try fetching from API (comment:{id} → GET /repos/{owner}/{repo}/issues/comments/{id})
	commentID := strings.TrimPrefix(msgID, "comment:")
	if commentID == msgID {
		return nil // not a comment: prefixed ID
	}
	owner, repo, _ := g.parseChatOwnerRepo(chatID)
	if owner == "" {
		return nil
	}
	resp, err := g.apiGet(ghRepoPath(owner, repo) + "/issues/comments/" + commentID, nil)
	if err != nil {
		return nil
	}
	msg := g.commentToMessage(chatID, resp)
	g.cacheMessage(chatID, msg)
	return msg
}

func (g *GitHubCore) getCachedMessages(chatID string, limit int) []Message {
	g.messagesMu.RLock()
	defer g.messagesMu.RUnlock()
	cached := g.messages[chatID]
	if len(cached) == 0 {
		return nil
	}
	msgs := make([]Message, 0, len(cached))
	start := 0
	if len(cached) > limit {
		start = len(cached) - limit
	}
	for _, m := range cached[start:] {
		msgs = append(msgs, *m)
	}
	return msgs
}

func (g *GitHubCore) touchThread(chatID string) {
	g.activeThreadsMu.Lock()
	g.activeThreads[chatID] = time.Now()
	g.activeThreadsMu.Unlock()
}

func (g *GitHubCore) ghDialogToDialog(d *ghDialog) *Dialog {
	return &Dialog{
		ID:          d.ChatID,
		Type:        d.Type,
		Title:       d.Title,
		AvatarURL:   d.AvatarURL,
		MemberCount: d.MemberCount,
		UnreadCount: d.UnreadCount,
		IsMuted:     d.IsMuted,
		IsPinned:    d.IsPinned,
		Platform:    ghPlatform,
	}
}

// JSON helper functions (no external dependencies)

func gjsonStr(raw json.RawMessage, path string) string {
	var m map[string]any
	json.Unmarshal(raw, &m)
	parts := strings.Split(path, ".")
	var current any = m
	for _, p := range parts {
		cm, ok := current.(map[string]any)
		if !ok {
			return ""
		}
		current = cm[p]
	}
	s, _ := current.(string)
	return s
}

func gjsonFloat(raw json.RawMessage, path string) float64 {
	var m map[string]any
	json.Unmarshal(raw, &m)
	parts := strings.Split(path, ".")
	var current any = m
	for _, p := range parts {
		cm, ok := current.(map[string]any)
		if !ok {
			return 0
		}
		current = cm[p]
	}
	f, _ := current.(float64)
	return f
}

func gjsonArray(raw json.RawMessage, key string) []any {
	var m map[string]any
	json.Unmarshal(raw, &m)
	arr, _ := m[key].([]any)
	return arr
}

func gjsonMapStr(m map[string]any, keys ...string) string {
	var current any = m
	for _, k := range keys {
		cm, ok := current.(map[string]any)
		if !ok {
			return ""
		}
		current = cm[k]
	}
	s, _ := current.(string)
	return s
}

func gjsonMapFloat(m map[string]any, key string) float64 {
	f, _ := m[key].(float64)
	return f
}

func strOf(v any) string {
	if v == nil {
		return ""
	}
	switch s := v.(type) {
	case string:
		return s
	case float64:
		return strconv.FormatFloat(s, 'f', -1, 64)
	default:
		return fmt.Sprintf("%v", v)
	}
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}

func timePtr(t time.Time) *time.Time {
	return &t
}

var trailingNumberRe = regexp.MustCompile(`/(\d+)$`)

func extractTrailingNumber(url string) string {
	m := trailingNumberRe.FindStringSubmatch(url)
	if len(m) == 2 {
		return m[1]
	}
	return ""
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Issues (6)
// ══════════════════════════════════════════════════════════════════════════════

// LockIssue locks an issue conversation.
func (g *GitHubCore) LockIssue(owner, repo string, number int, reason string) error {
	payload := map[string]any{}
	if reason != "" {
		payload["lock_reason"] = reason
	}
	_, err := g.apiPut(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/lock", payload)
	return err
}

// UnlockIssue unlocks an issue conversation.
func (g *GitHubCore) UnlockIssue(owner, repo string, number int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/lock")
	return err
}

// ListIssueEvents lists events for an issue.
func (g *GitHubCore) ListIssueEvents(owner, repo string, number int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/events", nil)
}

// GetIssueTimeline gets the timeline of an issue.
func (g *GitHubCore) GetIssueTimeline(owner, repo string, number int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/timeline", nil)
}

// ListSubIssues lists sub-issues of an issue.
func (g *GitHubCore) ListSubIssues(owner, repo string, number int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/sub_issues", nil)
}

// AddSubIssue adds a sub-issue to a parent issue.
func (g *GitHubCore) AddSubIssue(owner, repo string, number int, subIssueID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/sub_issues", map[string]any{
		"sub_issue_id": subIssueID,
	})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Labels (7)
// ══════════════════════════════════════════════════════════════════════════════

// ListLabels lists all labels for a repository.
func (g *GitHubCore) ListLabels(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/labels", map[string]string{"per_page": "100"})
}

// CreateLabel creates a label.
func (g *GitHubCore) CreateLabel(owner, repo, name, color, description string) (json.RawMessage, error) {
	payload := map[string]any{"name": name, "color": color}
	if description != "" {
		payload["description"] = description
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/labels", payload)
}

// UpdateLabel updates a label.
func (g *GitHubCore) UpdateLabel(owner, repo, name string, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/labels/" + name, updates)
}

// DeleteLabel deletes a label.
func (g *GitHubCore) DeleteLabel(owner, repo, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/labels/" + name)
	return err
}

// AddLabelsToIssue adds labels to an issue.
func (g *GitHubCore) AddLabelsToIssue(owner, repo string, number int, labels []string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/labels", map[string]any{"labels": labels})
}

// RemoveLabel removes a label from an issue.
func (g *GitHubCore) RemoveLabel(owner, repo string, number int, label string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/labels/" + label)
	return err
}

// SetLabels replaces all labels on an issue.
func (g *GitHubCore) SetLabels(owner, repo string, number int, labels []string) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(number) + "/labels", map[string]any{"labels": labels})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Milestones (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListMilestones lists milestones for a repository.
func (g *GitHubCore) ListMilestones(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/milestones", map[string]string{"per_page": "100"})
}

// CreateMilestone creates a milestone.
func (g *GitHubCore) CreateMilestone(owner, repo, title, description string) (json.RawMessage, error) {
	payload := map[string]any{"title": title}
	if description != "" {
		payload["description"] = description
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/milestones", payload)
}

// UpdateMilestone updates a milestone.
func (g *GitHubCore) UpdateMilestone(owner, repo string, number int, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/milestones/" + strconv.Itoa(number), updates)
}

// DeleteMilestone deletes a milestone.
func (g *GitHubCore) DeleteMilestone(owner, repo string, number int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/milestones/" + strconv.Itoa(number))
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Pull Requests (12)
// ══════════════════════════════════════════════════════════════════════════════

// ListPullRequests lists pull requests for a repository.
func (g *GitHubCore) ListPullRequests(owner, repo, state string, perPage int) (json.RawMessage, error) {
	params := map[string]string{"per_page": strconv.Itoa(perPage)}
	if state != "" {
		params["state"] = state
	}
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls", params)
}

// CreatePullRequest creates a pull request.
func (g *GitHubCore) CreatePullRequest(owner, repo, title, head, base, body string) (json.RawMessage, error) {
	payload := map[string]any{
		"title": title,
		"head":  head,
		"base":  base,
	}
	if body != "" {
		payload["body"] = body
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls", payload)
}

// GetPullRequest gets a pull request.
func (g *GitHubCore) GetPullRequest(owner, repo string, number int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number), nil)
}

// UpdatePullRequest updates a pull request.
func (g *GitHubCore) UpdatePullRequest(owner, repo string, number int, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number), updates)
}

// MergePullRequest merges a pull request.
func (g *GitHubCore) MergePullRequest(owner, repo string, number int, mergeMethod, commitTitle, commitMessage string) (json.RawMessage, error) {
	payload := map[string]any{}
	if mergeMethod != "" {
		payload["merge_method"] = mergeMethod
	}
	if commitTitle != "" {
		payload["commit_title"] = commitTitle
	}
	if commitMessage != "" {
		payload["commit_message"] = commitMessage
	}
	return g.apiPut(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number) + "/merge", payload)
}

// ListPRComments lists review comments on a pull request.
func (g *GitHubCore) ListPRComments(owner, repo string, number int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number) + "/comments", nil)
}

// CreatePRComment creates a review comment on a pull request.
func (g *GitHubCore) CreatePRComment(owner, repo string, number int, body, path, commitID string, line int) (json.RawMessage, error) {
	payload := map[string]any{"body": body}
	if path != "" {
		payload["path"] = path
	}
	if commitID != "" {
		payload["commit_id"] = commitID
	}
	if line > 0 {
		payload["line"] = line
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number) + "/comments", payload)
}

// ListPRReviews lists reviews on a pull request.
func (g *GitHubCore) ListPRReviews(owner, repo string, number int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number) + "/reviews", nil)
}

// CreatePRReview creates a review on a pull request.
func (g *GitHubCore) CreatePRReview(owner, repo string, number int, body, event string) (json.RawMessage, error) {
	payload := map[string]any{}
	if body != "" {
		payload["body"] = body
	}
	if event != "" {
		payload["event"] = event
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number) + "/reviews", payload)
}

// SubmitPRReview submits a pending review.
func (g *GitHubCore) SubmitPRReview(owner, repo string, prNumber, reviewID int, body, event string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID) + "/events", map[string]any{
		"body":  body,
		"event": event,
	})
}

// DismissPRReview dismisses a review.
func (g *GitHubCore) DismissPRReview(owner, repo string, prNumber, reviewID int, message string) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID) + "/dismissals", map[string]any{
		"message": message,
	})
}

// RequestReviewers requests reviewers for a pull request.
func (g *GitHubCore) RequestReviewers(owner, repo string, number int, reviewers []string, teamReviewers []string) (json.RawMessage, error) {
	payload := map[string]any{}
	if len(reviewers) > 0 {
		payload["reviewers"] = reviewers
	}
	if len(teamReviewers) > 0 {
		payload["team_reviewers"] = teamReviewers
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(number) + "/requested_reviewers", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Notifications (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListNotifications lists notifications for the authenticated user.
func (g *GitHubCore) ListNotifications(all bool, perPage int) (json.RawMessage, error) {
	params := map[string]string{"per_page": strconv.Itoa(perPage)}
	if all {
		params["all"] = "true"
	}
	return g.apiGet("/notifications", params)
}

// MarkAllNotificationsRead marks all notifications as read.
func (g *GitHubCore) MarkAllNotificationsRead() error {
	_, err := g.apiPut("/notifications", map[string]any{"last_read_at": time.Now().UTC().Format(time.RFC3339)})
	return err
}

// GetNotificationThread gets a notification thread.
func (g *GitHubCore) GetNotificationThread(threadID string) (json.RawMessage, error) {
	return g.apiGet("/notifications/threads/" + threadID, nil)
}

// MarkThreadRead marks a notification thread as read.
func (g *GitHubCore) MarkThreadRead(threadID string) error {
	_, err := g.apiPatch("/notifications/threads/" + threadID, nil)
	return err
}

// SubscribeThread subscribes to a notification thread.
func (g *GitHubCore) SubscribeThread(threadID string) (json.RawMessage, error) {
	return g.apiPut("/notifications/threads/" + threadID + "/subscription", map[string]any{"ignored": false})
}

// UnsubscribeThread unsubscribes from a notification thread.
func (g *GitHubCore) UnsubscribeThread(threadID string) error {
	_, err := g.apiDelete("/notifications/threads/" + threadID + "/subscription")
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Repository Extended (7)
// ══════════════════════════════════════════════════════════════════════════════

// DeleteRepo deletes a repository.
func (g *GitHubCore) DeleteRepo(owner, repo string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo))
	return err
}

// ForkRepo forks a repository.
func (g *GitHubCore) ForkRepo(owner, repo string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/forks", nil)
}

// TransferRepo transfers a repository to another owner.
func (g *GitHubCore) TransferRepo(owner, repo, newOwner string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/transfer", map[string]any{"new_owner": newOwner})
}

// GetRepoTopics gets repository topics.
func (g *GitHubCore) GetRepoTopics(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/topics", nil)
}

// SetRepoTopics replaces all repository topics.
func (g *GitHubCore) SetRepoTopics(owner, repo string, topics []string) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/topics", map[string]any{"names": topics})
}

// ListContributors lists repository contributors.
func (g *GitHubCore) ListContributors(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/contributors", map[string]string{"per_page": "100"})
}

// GetRepoActivity gets repository activity.
func (g *GitHubCore) GetRepoActivity(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/activity", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Repository Invitations (5)
// ══════════════════════════════════════════════════════════════════════════════

// ListInvitations lists repository invitations.
func (g *GitHubCore) ListInvitations(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/invitations", nil)
}

// UpdateInvitation updates a repository invitation.
func (g *GitHubCore) UpdateInvitation(owner, repo string, invitationID int, permissions string) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/invitations/" + strconv.Itoa(invitationID), map[string]any{"permissions": permissions})
}

// DeleteInvitation deletes a repository invitation.
func (g *GitHubCore) DeleteInvitation(owner, repo string, invitationID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/invitations/" + strconv.Itoa(invitationID))
	return err
}

// AcceptInvitation accepts a repository invitation.
func (g *GitHubCore) AcceptInvitation(invitationID int) error {
	_, err := g.apiPatch("/user/repository_invitations/" + strconv.Itoa(invitationID), nil)
	return err
}

// DeclineInvitation declines a repository invitation.
func (g *GitHubCore) DeclineInvitation(invitationID int) error {
	_, err := g.apiDelete("/user/repository_invitations/" + strconv.Itoa(invitationID))
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Gists (8)
// ══════════════════════════════════════════════════════════════════════════════

// ListGists lists gists for the authenticated user.
func (g *GitHubCore) ListGists(perPage int) (json.RawMessage, error) {
	return g.apiGet("/gists", map[string]string{"per_page": strconv.Itoa(perPage)})
}

// CreateGist creates a gist.
func (g *GitHubCore) CreateGist(description string, files map[string]map[string]string, public bool) (json.RawMessage, error) {
	return g.apiPost("/gists", map[string]any{
		"description": description,
		"files":       files,
		"public":      public,
	})
}

// UpdateGist updates a gist.
func (g *GitHubCore) UpdateGist(gistID string, description string, files map[string]map[string]string) (json.RawMessage, error) {
	payload := map[string]any{}
	if description != "" {
		payload["description"] = description
	}
	if files != nil {
		payload["files"] = files
	}
	return g.apiPatch("/gists/" + gistID, payload)
}

// DeleteGist deletes a gist.
func (g *GitHubCore) DeleteGist(gistID string) error {
	_, err := g.apiDelete("/gists/" + gistID)
	return err
}

// StarGist stars a gist.
func (g *GitHubCore) StarGist(gistID string) error {
	_, err := g.apiPut("/gists/" + gistID + "/star", nil)
	return err
}

// UnstarGist unstars a gist.
func (g *GitHubCore) UnstarGist(gistID string) error {
	_, err := g.apiDelete("/gists/" + gistID + "/star")
	return err
}

// ListGistComments lists comments on a gist.
func (g *GitHubCore) ListGistComments(gistID string) (json.RawMessage, error) {
	return g.apiGet("/gists/" + gistID + "/comments", nil)
}

// CreateGistComment creates a comment on a gist.
func (g *GitHubCore) CreateGistComment(gistID, body string) (json.RawMessage, error) {
	return g.apiPost("/gists/" + gistID + "/comments", map[string]any{"body": body})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Releases (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListReleases lists releases for a repository.
func (g *GitHubCore) ListReleases(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/releases", map[string]string{"per_page": "30"})
}

// CreateRelease creates a release.
func (g *GitHubCore) CreateRelease(owner, repo, tagName, name, body string, draft, prerelease bool) (json.RawMessage, error) {
	payload := map[string]any{
		"tag_name":   tagName,
		"name":       name,
		"body":       body,
		"draft":      draft,
		"prerelease": prerelease,
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/releases", payload)
}

// UpdateRelease updates a release.
func (g *GitHubCore) UpdateRelease(owner, repo string, releaseID int, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID), updates)
}

// DeleteRelease deletes a release.
func (g *GitHubCore) DeleteRelease(owner, repo string, releaseID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID))
	return err
}

// UploadReleaseAsset uploads an asset to a release.
func (g *GitHubCore) UploadReleaseAsset(owner, repo string, releaseID int, name string, data []byte, contentType string) (json.RawMessage, error) {
	uploadURL := "https://uploads.github.com" + ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID) + "/assets?name=" + name
	body, status, _, err := g.doAPI("POST", uploadURL, data, map[string]string{"Content-Type": contentType})
	if err != nil {
		return nil, err
	}
	if status >= 400 {
		return nil, fmt.Errorf("github upload error %d: %s", status, truncate(string(body), 200))
	}
	return body, nil
}

// ListReleaseAssets lists assets for a release.
func (g *GitHubCore) ListReleaseAssets(owner, repo string, releaseID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID) + "/assets", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Commit Comments (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListCommitComments lists comments for a commit.
func (g *GitHubCore) ListCommitComments(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + sha + "/comments", nil)
}

// CreateCommitComment creates a comment on a commit.
func (g *GitHubCore) CreateCommitComment(owner, repo, sha, body string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/commits/" + sha + "/comments", map[string]any{"body": body})
}

// UpdateCommitComment updates a commit comment.
func (g *GitHubCore) UpdateCommitComment(owner, repo string, commentID int, body string) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/comments/" + strconv.Itoa(commentID), map[string]any{"body": body})
}

// DeleteCommitComment deletes a commit comment.
func (g *GitHubCore) DeleteCommitComment(owner, repo string, commentID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/comments/" + strconv.Itoa(commentID))
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Organizations (9)
// ══════════════════════════════════════════════════════════════════════════════

// ListOrgs lists organizations for the authenticated user.
func (g *GitHubCore) ListOrgs() (json.RawMessage, error) {
	return g.apiGet("/user/orgs", map[string]string{"per_page": "100"})
}

// GetOrg gets an organization.
func (g *GitHubCore) GetOrg(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org, nil)
}

// ListOrgMembers lists organization members.
func (g *GitHubCore) ListOrgMembers(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/members", map[string]string{"per_page": "100"})
}

// ListOrgTeams lists organization teams.
func (g *GitHubCore) ListOrgTeams(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams", map[string]string{"per_page": "100"})
}

// CreateTeam creates a team in an organization.
func (g *GitHubCore) CreateTeam(org, name, description, privacy string) (json.RawMessage, error) {
	payload := map[string]any{"name": name}
	if description != "" {
		payload["description"] = description
	}
	if privacy != "" {
		payload["privacy"] = privacy
	}
	return g.apiPost("/orgs/" + org + "/teams", payload)
}

// UpdateTeam updates a team.
func (g *GitHubCore) UpdateTeam(org, teamSlug string, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/orgs/" + org + "/teams/" + teamSlug, updates)
}

// DeleteTeam deletes a team.
func (g *GitHubCore) DeleteTeam(org, teamSlug string) error {
	_, err := g.apiDelete("/orgs/" + org + "/teams/" + teamSlug)
	return err
}

// AddTeamMember adds a member to a team.
func (g *GitHubCore) AddTeamMember(org, teamSlug, username, role string) (json.RawMessage, error) {
	payload := map[string]any{}
	if role != "" {
		payload["role"] = role
	}
	return g.apiPut("/orgs/" + org + "/teams/" + teamSlug + "/memberships/" + username, payload)
}

// RemoveTeamMember removes a member from a team.
func (g *GitHubCore) RemoveTeamMember(org, teamSlug, username string) error {
	_, err := g.apiDelete("/orgs/" + org + "/teams/" + teamSlug + "/memberships/" + username)
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Webhooks (4)
// ══════════════════════════════════════════════════════════════════════════════

// CreateWebhook creates a webhook.
func (g *GitHubCore) CreateWebhook(owner, repo, url, contentType, secret string, events []string) (json.RawMessage, error) {
	config := map[string]any{"url": url, "content_type": contentType}
	if secret != "" {
		config["secret"] = secret
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/hooks", map[string]any{
		"config": config,
		"events": events,
		"active": true,
	})
}

// UpdateWebhook updates a webhook.
func (g *GitHubCore) UpdateWebhook(owner, repo string, hookID int, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID), updates)
}

// DeleteWebhook deletes a webhook.
func (g *GitHubCore) DeleteWebhook(owner, repo string, hookID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID))
	return err
}

// PingWebhook pings a webhook.
func (g *GitHubCore) PingWebhook(owner, repo string, hookID int) error {
	_, err := g.apiPost(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID) + "/pings", nil)
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Starring / Watching (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListStargazers lists stargazers for a repository.
func (g *GitHubCore) ListStargazers(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/stargazers", map[string]string{"per_page": "100"})
}

// StarRepo stars a repository.
func (g *GitHubCore) StarRepo(owner, repo string) error {
	_, err := g.apiPut("/user/starred/" + owner + "/" + repo, nil)
	return err
}

// UnstarRepo unstars a repository.
func (g *GitHubCore) UnstarRepo(owner, repo string) error {
	_, err := g.apiDelete("/user/starred/" + owner + "/" + repo)
	return err
}

// ListWatchers lists watchers for a repository.
func (g *GitHubCore) ListWatchers(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/subscribers", map[string]string{"per_page": "100"})
}

// WatchRepo watches a repository.
func (g *GitHubCore) WatchRepo(owner, repo string) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/subscription", map[string]any{"subscribed": true})
}

// UnwatchRepo unwatches a repository.
func (g *GitHubCore) UnwatchRepo(owner, repo string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/subscription")
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Events (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListEvents lists public events.
func (g *GitHubCore) ListEvents(perPage int) (json.RawMessage, error) {
	return g.apiGet("/events", map[string]string{"per_page": strconv.Itoa(perPage)})
}

// ListRepoEvents lists events for a repository.
func (g *GitHubCore) ListRepoEvents(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/events", map[string]string{"per_page": "30"})
}

// ListUserEvents lists events for a user.
func (g *GitHubCore) ListUserEvents(username string) (json.RawMessage, error) {
	return g.apiGet("/users/" + username + "/events", map[string]string{"per_page": "30"})
}

// GetFeeds lists feeds available to the authenticated user.
func (g *GitHubCore) GetFeeds() (json.RawMessage, error) {
	return g.apiGet("/feeds", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Discussions (GraphQL) (8)
// ══════════════════════════════════════════════════════════════════════════════

// ghGraphQL executes a GraphQL query against GitHub's API.
func (g *GitHubCore) ghGraphQL(query string, variables map[string]any) (json.RawMessage, error) {
	payload := map[string]any{"query": query}
	if variables != nil {
		payload["variables"] = variables
	}
	data, _ := json.Marshal(payload)
	body, status, _, err := g.doAPI("POST", "https://api.github.com/graphql", data, nil)
	if err != nil {
		return nil, err
	}
	if status >= 400 {
		return nil, fmt.Errorf("github graphql error %d: %s", status, truncate(string(body), 200))
	}
	return body, nil
}

// ListDiscussions lists discussions in a repository.
func (g *GitHubCore) ListDiscussions(owner, repo string, first int) (json.RawMessage, error) {
	query := `query($owner:String!,$repo:String!,$first:Int!){repository(owner:$owner,name:$repo){discussions(first:$first,orderBy:{field:CREATED_AT,direction:DESC}){nodes{id number title body createdAt author{login}}}}}`
	return g.ghGraphQL(query, map[string]any{"owner": owner, "repo": repo, "first": first})
}

// CreateDiscussion creates a discussion.
func (g *GitHubCore) CreateDiscussion(repoID, categoryID, title, body string) (json.RawMessage, error) {
	query := `mutation($repoId:ID!,$catId:ID!,$title:String!,$body:String!){createDiscussion(input:{repositoryId:$repoId,categoryId:$catId,title:$title,body:$body}){discussion{id number}}}`
	return g.ghGraphQL(query, map[string]any{"repoId": repoID, "catId": categoryID, "title": title, "body": body})
}

// UpdateDiscussion updates a discussion.
func (g *GitHubCore) UpdateDiscussion(discussionID, title, body string) (json.RawMessage, error) {
	query := `mutation($id:ID!,$title:String,$body:String){updateDiscussion(input:{discussionId:$id,title:$title,body:$body}){discussion{id number}}}`
	return g.ghGraphQL(query, map[string]any{"id": discussionID, "title": title, "body": body})
}

// DeleteDiscussion deletes a discussion.
func (g *GitHubCore) DeleteDiscussion(discussionID string) (json.RawMessage, error) {
	query := `mutation($id:ID!){deleteDiscussion(input:{id:$id}){discussion{id}}}`
	return g.ghGraphQL(query, map[string]any{"id": discussionID})
}

// AddDiscussionComment adds a comment to a discussion.
func (g *GitHubCore) AddDiscussionComment(discussionID, body string) (json.RawMessage, error) {
	query := `mutation($id:ID!,$body:String!){addDiscussionComment(input:{discussionId:$id,body:$body}){comment{id}}}`
	return g.ghGraphQL(query, map[string]any{"id": discussionID, "body": body})
}

// UpdateDiscussionComment updates a discussion comment.
func (g *GitHubCore) UpdateDiscussionComment(commentID, body string) (json.RawMessage, error) {
	query := `mutation($id:ID!,$body:String!){updateDiscussionComment(input:{commentId:$id,body:$body}){comment{id}}}`
	return g.ghGraphQL(query, map[string]any{"id": commentID, "body": body})
}

// DeleteDiscussionComment deletes a discussion comment.
func (g *GitHubCore) DeleteDiscussionComment(commentID string) (json.RawMessage, error) {
	query := `mutation($id:ID!){deleteDiscussionComment(input:{id:$id}){comment{id}}}`
	return g.ghGraphQL(query, map[string]any{"id": commentID})
}

// MarkDiscussionCommentAsAnswer marks a discussion comment as the answer.
func (g *GitHubCore) MarkDiscussionCommentAsAnswer(commentID string) (json.RawMessage, error) {
	query := `mutation($id:ID!){markDiscussionCommentAsAnswer(input:{id:$id}){discussion{id}}}`
	return g.ghGraphQL(query, map[string]any{"id": commentID})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — User Extended (8)
// ══════════════════════════════════════════════════════════════════════════════

// UpdateProfile updates the authenticated user's profile.
func (g *GitHubCore) UpdateProfile(name, bio, blog, company, location string) (json.RawMessage, error) {
	payload := map[string]any{}
	if name != "" {
		payload["name"] = name
	}
	if bio != "" {
		payload["bio"] = bio
	}
	if blog != "" {
		payload["blog"] = blog
	}
	if company != "" {
		payload["company"] = company
	}
	if location != "" {
		payload["location"] = location
	}
	return g.apiPatch("/user", payload)
}

// ListEmails lists email addresses for the authenticated user.
func (g *GitHubCore) ListEmails() (json.RawMessage, error) {
	return g.apiGet("/user/emails", nil)
}

// AddEmail adds email addresses.
func (g *GitHubCore) AddEmail(emails []string) (json.RawMessage, error) {
	return g.apiPost("/user/emails", map[string]any{"emails": emails})
}

// DeleteEmail removes email addresses.
func (g *GitHubCore) DeleteEmail(emails []string) error {
	data, _ := json.Marshal(map[string]any{"emails": emails})
	body, status, _, err := g.doAPI("DELETE", ghAPIBase+"/user/emails", data, nil)
	if err != nil {
		return err
	}
	if status >= 400 {
		return fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}
	return nil
}

// ListSocialAccounts lists social accounts for the authenticated user.
func (g *GitHubCore) ListSocialAccounts() (json.RawMessage, error) {
	return g.apiGet("/user/social_accounts", nil)
}

// AddSocialAccount adds social account URLs.
func (g *GitHubCore) AddSocialAccount(accountURLs []string) (json.RawMessage, error) {
	return g.apiPost("/user/social_accounts", map[string]any{"account_urls": accountURLs})
}

// DeleteSocialAccount removes social account URLs.
func (g *GitHubCore) DeleteSocialAccount(accountURLs []string) error {
	data, _ := json.Marshal(map[string]any{"account_urls": accountURLs})
	body, status, _, err := g.doAPI("DELETE", ghAPIBase+"/user/social_accounts", data, nil)
	if err != nil {
		return err
	}
	if status >= 400 {
		return fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}
	return nil
}

// GetUserHovercard gets hovercard info for a user.
func (g *GitHubCore) GetUserHovercard(username string) (json.RawMessage, error) {
	return g.apiGet("/users/" + username + "/hovercard", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Search Extended (4)
// ══════════════════════════════════════════════════════════════════════════════

// SearchCode searches code.
func (g *GitHubCore) SearchCode(query string, perPage int) (json.RawMessage, error) {
	return g.apiGet("/search/code", map[string]string{"q": query, "per_page": strconv.Itoa(perPage)})
}

// SearchCommits searches commits.
func (g *GitHubCore) SearchCommits(query string, perPage int) (json.RawMessage, error) {
	return g.apiGet("/search/commits", map[string]string{"q": query, "per_page": strconv.Itoa(perPage)})
}

// SearchLabels searches labels.
func (g *GitHubCore) SearchLabels(repoID int, query string) (json.RawMessage, error) {
	return g.apiGet("/search/labels", map[string]string{"repository_id": strconv.Itoa(repoID), "q": query})
}

// SearchTopics searches topics.
func (g *GitHubCore) SearchTopics(query string) (json.RawMessage, error) {
	return g.apiGet("/search/topics", map[string]string{"q": query})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Utility (3)
// ══════════════════════════════════════════════════════════════════════════════

// ListEmojis lists all GitHub emojis.
func (g *GitHubCore) ListEmojis() (json.RawMessage, error) {
	return g.apiGet("/emojis", nil)
}

// CheckRateLimit checks the current rate limit status.
func (g *GitHubCore) CheckRateLimit() (json.RawMessage, error) {
	return g.apiGet("/rate_limit", nil)
}

// RenderMarkdown renders markdown to HTML.
func (g *GitHubCore) RenderMarkdown(text, mode, context string) (string, error) {
	payload := map[string]any{"text": text}
	if mode != "" {
		payload["mode"] = mode
	}
	if context != "" {
		payload["context"] = context
	}
	data, _ := json.Marshal(payload)
	body, status, _, err := g.doAPI("POST", ghAPIBase+"/markdown", data, nil)
	if err != nil {
		return "", err
	}
	if status >= 400 {
		return "", fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}
	return string(body), nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Branches & Branch Protection (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListBranches lists branches for a repository.
func (g *GitHubCore) ListBranches(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches", map[string]string{"per_page": "100"})
}

// GetBranch gets a branch.
func (g *GitHubCore) GetBranch(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches/" + branch, nil)
}

// CreateBranchProtection creates branch protection rules.
func (g *GitHubCore) CreateBranchProtection(owner, repo, branch string, rules map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection", rules)
}

// DeleteBranchProtection removes branch protection.
func (g *GitHubCore) DeleteBranchProtection(owner, repo, branch string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection")
	return err
}

// RenameBranch renames a branch.
func (g *GitHubCore) RenameBranch(owner, repo, branch, newName string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/branches/" + branch + "/rename", map[string]any{"new_name": newName})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Git References / Tags (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListTags lists tags for a repository.
func (g *GitHubCore) ListTags(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/tags", map[string]string{"per_page": "100"})
}

// CreateTag creates a tag object.
func (g *GitHubCore) CreateTag(owner, repo, tag, message, sha, objectType string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/git/tags", map[string]any{
		"tag":     tag,
		"message": message,
		"object":  sha,
		"type":    objectType,
	})
}

// DeleteTag deletes a tag by deleting its reference.
func (g *GitHubCore) DeleteTag(owner, repo, tag string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/git/refs/tags/" + tag)
	return err
}

// ListRefs lists git references.
func (g *GitHubCore) ListRefs(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/git/refs", nil)
}

// CreateRef creates a git reference.
func (g *GitHubCore) CreateRef(owner, repo, ref, sha string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/git/refs", map[string]any{"ref": ref, "sha": sha})
}

// DeleteRef deletes a git reference.
func (g *GitHubCore) DeleteRef(owner, repo, ref string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/git/refs/" + ref)
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Commits (3)
// ══════════════════════════════════════════════════════════════════════════════

// ListCommits lists commits for a repository.
func (g *GitHubCore) ListCommits(owner, repo string, perPage int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits", map[string]string{"per_page": strconv.Itoa(perPage)})
}

// GetCommit gets a commit.
func (g *GitHubCore) GetCommit(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + sha, nil)
}

// CompareCommits compares two commits.
func (g *GitHubCore) CompareCommits(owner, repo, base, head string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/compare/" + base + "..." + head, nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Actions / Workflows (10)
// ══════════════════════════════════════════════════════════════════════════════

// ListWorkflows lists workflows for a repository.
func (g *GitHubCore) ListWorkflows(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/workflows", nil)
}

// ListWorkflowRuns lists workflow runs.
func (g *GitHubCore) ListWorkflowRuns(owner, repo string, perPage int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs", map[string]string{"per_page": strconv.Itoa(perPage)})
}

// GetWorkflowRun gets a workflow run.
func (g *GitHubCore) GetWorkflowRun(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID), nil)
}

// ReRunWorkflow re-runs a workflow.
func (g *GitHubCore) ReRunWorkflow(owner, repo string, runID int) error {
	_, err := g.apiPost(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/rerun", nil)
	return err
}

// CancelWorkflowRun cancels a workflow run.
func (g *GitHubCore) CancelWorkflowRun(owner, repo string, runID int) error {
	_, err := g.apiPost(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/cancel", nil)
	return err
}

// ListWorkflowRunArtifacts lists artifacts for a workflow run.
func (g *GitHubCore) ListWorkflowRunArtifacts(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/artifacts", nil)
}

// DownloadArtifact gets the download URL for an artifact.
func (g *GitHubCore) DownloadArtifact(owner, repo string, artifactID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/artifacts/" + strconv.Itoa(artifactID) + "/zip", nil)
}

// ListRepositorySecrets lists repository secrets.
func (g *GitHubCore) ListRepositorySecrets(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/secrets", nil)
}

// CreateOrUpdateSecret creates or updates a repository secret.
func (g *GitHubCore) CreateOrUpdateSecret(owner, repo, name, encryptedValue, keyID string) error {
	_, err := g.apiPut(ghRepoPath(owner, repo) + "/actions/secrets/" + name, map[string]any{
		"encrypted_value": encryptedValue,
		"key_id":          keyID,
	})
	return err
}

// DeleteSecret deletes a repository secret.
func (g *GitHubCore) DeleteSecret(owner, repo, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/secrets/" + name)
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Checks / Statuses (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListCheckRuns lists check runs for a ref.
func (g *GitHubCore) ListCheckRuns(owner, repo, ref string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + ref + "/check-runs", nil)
}

// GetCheckRun gets a check run.
func (g *GitHubCore) GetCheckRun(owner, repo string, checkRunID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/check-runs/" + strconv.Itoa(checkRunID), nil)
}

// ListCheckSuites lists check suites for a ref.
func (g *GitHubCore) ListCheckSuites(owner, repo, ref string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + ref + "/check-suites", nil)
}

// CreateCheckRun creates a check run.
func (g *GitHubCore) CreateCheckRun(owner, repo, name, headSHA string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/check-runs", map[string]any{
		"name":     name,
		"head_sha": headSHA,
	})
}

// ListCommitStatuses lists statuses for a ref.
func (g *GitHubCore) ListCommitStatuses(owner, repo, ref string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + ref + "/statuses", nil)
}

// CreateCommitStatus creates a commit status.
func (g *GitHubCore) CreateCommitStatus(owner, repo, sha, state, targetURL, description, context string) (json.RawMessage, error) {
	payload := map[string]any{"state": state}
	if targetURL != "" {
		payload["target_url"] = targetURL
	}
	if description != "" {
		payload["description"] = description
	}
	if context != "" {
		payload["context"] = context
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/statuses/" + sha, payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Projects (7)
// ══════════════════════════════════════════════════════════════════════════════

// ListProjects lists projects for a repository.
func (g *GitHubCore) ListProjects(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/projects", nil)
}

// CreateProject creates a project.
func (g *GitHubCore) CreateProject(owner, repo, name, body string) (json.RawMessage, error) {
	payload := map[string]any{"name": name}
	if body != "" {
		payload["body"] = body
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/projects", payload)
}

// UpdateProject updates a project.
func (g *GitHubCore) UpdateProject(projectID int, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/projects/" + strconv.Itoa(projectID), updates)
}

// DeleteProject deletes a project.
func (g *GitHubCore) DeleteProject(projectID int) error {
	_, err := g.apiDelete("/projects/" + strconv.Itoa(projectID))
	return err
}

// ListProjectColumns lists columns for a project.
func (g *GitHubCore) ListProjectColumns(projectID int) (json.RawMessage, error) {
	return g.apiGet("/projects/" + strconv.Itoa(projectID) + "/columns", nil)
}

// CreateProjectCard creates a card in a project column.
func (g *GitHubCore) CreateProjectCard(columnID int, note string) (json.RawMessage, error) {
	return g.apiPost("/projects/columns/" + strconv.Itoa(columnID) + "/cards", map[string]any{"note": note})
}

// MoveProjectCard moves a project card.
func (g *GitHubCore) MoveProjectCard(cardID int, position string, columnID int) (json.RawMessage, error) {
	payload := map[string]any{"position": position}
	if columnID > 0 {
		payload["column_id"] = columnID
	}
	return g.apiPost("/projects/columns/cards/" + strconv.Itoa(cardID) + "/moves", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Deployments (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListDeployments lists deployments for a repository.
func (g *GitHubCore) ListDeployments(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/deployments", nil)
}

// CreateDeployment creates a deployment.
func (g *GitHubCore) CreateDeployment(owner, repo, ref, environment, description string) (json.RawMessage, error) {
	payload := map[string]any{"ref": ref}
	if environment != "" {
		payload["environment"] = environment
	}
	if description != "" {
		payload["description"] = description
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/deployments", payload)
}

// ListDeploymentStatuses lists statuses for a deployment.
func (g *GitHubCore) ListDeploymentStatuses(owner, repo string, deploymentID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/deployments/" + strconv.Itoa(deploymentID) + "/statuses", nil)
}

// CreateDeploymentStatus creates a deployment status.
func (g *GitHubCore) CreateDeploymentStatus(owner, repo string, deploymentID int, state, logURL, description string) (json.RawMessage, error) {
	payload := map[string]any{"state": state}
	if logURL != "" {
		payload["log_url"] = logURL
	}
	if description != "" {
		payload["description"] = description
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/deployments/" + strconv.Itoa(deploymentID) + "/statuses", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Repository Contents (5)
// ══════════════════════════════════════════════════════════════════════════════

// GetFileContents gets the contents of a file in a repository.
func (g *GitHubCore) GetFileContents(owner, repo, path, ref string) (json.RawMessage, error) {
	params := map[string]string{}
	if ref != "" {
		params["ref"] = ref
	}
	return g.apiGet(ghRepoPath(owner, repo) + "/contents/" + path, params)
}

// CreateOrUpdateFileContents creates or updates a file.
func (g *GitHubCore) CreateOrUpdateFileContents(owner, repo, path, message, contentB64, sha, branch string) (json.RawMessage, error) {
	payload := map[string]any{
		"message": message,
		"content": contentB64,
	}
	if sha != "" {
		payload["sha"] = sha
	}
	if branch != "" {
		payload["branch"] = branch
	}
	return g.apiPut(ghRepoPath(owner, repo) + "/contents/" + path, payload)
}

// DeleteFileContents deletes a file from a repository.
func (g *GitHubCore) DeleteFileContents(owner, repo, path, message, sha, branch string) error {
	payload := map[string]any{
		"message": message,
		"sha":     sha,
	}
	if branch != "" {
		payload["branch"] = branch
	}
	data, _ := json.Marshal(payload)
	body, status, _, err := g.doAPI("DELETE", ghAPIBase+ghRepoPath(owner, repo) + "/contents/" + path, data, nil)
	if err != nil {
		return err
	}
	if status >= 400 {
		return fmt.Errorf("github API error %d: %s", status, truncate(string(body), 200))
	}
	return nil
}

// GetArchiveLink gets a tarball or zipball link for a repository.
func (g *GitHubCore) GetArchiveLink(owner, repo, format, ref string) (string, error) {
	if format == "" {
		format = "tarball"
	}
	path := ghRepoPath(owner, repo) + "/" + format + "/" + ref
	// The API returns a 302 redirect — we just want the URL
	resp, err := g.apiGet(path, nil)
	if err != nil {
		return "", err
	}
	return string(resp), nil
}

// ListRepositoryTree lists the git tree for a repository.
func (g *GitHubCore) ListRepositoryTree(owner, repo, sha string, recursive bool) (json.RawMessage, error) {
	params := map[string]string{}
	if recursive {
		params["recursive"] = "1"
	}
	return g.apiGet(ghRepoPath(owner, repo) + "/git/trees/" + sha, params)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Forks (1)
// ══════════════════════════════════════════════════════════════════════════════

// ListForks lists forks for a repository.
func (g *GitHubCore) ListForks(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/forks", map[string]string{"per_page": "30"})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Collaborator Permissions (2)
// ══════════════════════════════════════════════════════════════════════════════

// GetCollaboratorPermission gets the permission level for a collaborator.
func (g *GitHubCore) GetCollaboratorPermission(owner, repo, username string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/collaborators/" + username + "/permission", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Code Scanning / Security (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListCodeScanningAlerts lists code scanning alerts.
func (g *GitHubCore) ListCodeScanningAlerts(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/alerts", nil)
}

// GetCodeScanningAlert gets a code scanning alert.
func (g *GitHubCore) GetCodeScanningAlert(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/alerts/" + strconv.Itoa(alertNumber), nil)
}

// ListDependabotAlerts lists Dependabot alerts.
func (g *GitHubCore) ListDependabotAlerts(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependabot/alerts", nil)
}

// ListSecretScanningAlerts lists secret scanning alerts.
func (g *GitHubCore) ListSecretScanningAlerts(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/secret-scanning/alerts", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Pages (3)
// ══════════════════════════════════════════════════════════════════════════════

// GetPages gets GitHub Pages info for a repository.
func (g *GitHubCore) GetPages(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pages", nil)
}

// CreatePagesSite creates a GitHub Pages site.
func (g *GitHubCore) CreatePagesSite(owner, repo, branch, path string) (json.RawMessage, error) {
	source := map[string]any{"branch": branch}
	if path != "" {
		source["path"] = path
	}
	return g.apiPost(ghRepoPath(owner, repo) + "/pages", map[string]any{"source": source})
}

// ListPagesBuilds lists Pages builds.
func (g *GitHubCore) ListPagesBuilds(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pages/builds", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Packages (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListPackages lists packages for the authenticated user.
func (g *GitHubCore) ListPackages(packageType string) (json.RawMessage, error) {
	return g.apiGet("/user/packages", map[string]string{"package_type": packageType})
}

// GetPackage gets a package.
func (g *GitHubCore) GetPackage(packageType, packageName string) (json.RawMessage, error) {
	return g.apiGet("/user/packages/" + packageType + "/" + packageName, nil)
}

// DeletePackage deletes a package.
func (g *GitHubCore) DeletePackage(packageType, packageName string) error {
	_, err := g.apiDelete("/user/packages/" + packageType + "/" + packageName)
	return err
}

// ListPackageVersions lists versions of a package.
func (g *GitHubCore) ListPackageVersions(packageType, packageName string) (json.RawMessage, error) {
	return g.apiGet("/user/packages/" + packageType + "/" + packageName + "/versions", nil)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — SSH / GPG Keys (6)
// ══════════════════════════════════════════════════════════════════════════════

// ListSSHKeys lists SSH keys for the authenticated user.
func (g *GitHubCore) ListSSHKeys() (json.RawMessage, error) {
	return g.apiGet("/user/keys", nil)
}

// CreateSSHKey adds an SSH key.
func (g *GitHubCore) CreateSSHKey(title, key string) (json.RawMessage, error) {
	return g.apiPost("/user/keys", map[string]any{"title": title, "key": key})
}

// DeleteSSHKey deletes an SSH key.
func (g *GitHubCore) DeleteSSHKey(keyID int) error {
	_, err := g.apiDelete("/user/keys/" + strconv.Itoa(keyID))
	return err
}

// ListGPGKeys lists GPG keys for the authenticated user.
func (g *GitHubCore) ListGPGKeys() (json.RawMessage, error) {
	return g.apiGet("/user/gpg_keys", nil)
}

// CreateGPGKey adds a GPG key.
func (g *GitHubCore) CreateGPGKey(armoredPublicKey string) (json.RawMessage, error) {
	return g.apiPost("/user/gpg_keys", map[string]any{"armored_public_key": armoredPublicKey})
}

// DeleteGPGKey deletes a GPG key.
func (g *GitHubCore) DeleteGPGKey(keyID int) error {
	_, err := g.apiDelete("/user/gpg_keys/" + strconv.Itoa(keyID))
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Rulesets (5)
// ══════════════════════════════════════════════════════════════════════════════

// ListRulesets lists rulesets for a repository.
func (g *GitHubCore) ListRulesets(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rulesets", nil)
}

// CreateRuleset creates a ruleset.
func (g *GitHubCore) CreateRuleset(owner, repo string, ruleset map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/rulesets", ruleset)
}

// GetRuleset gets a ruleset.
func (g *GitHubCore) GetRuleset(owner, repo string, rulesetID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rulesets/" + strconv.Itoa(rulesetID), nil)
}

// UpdateRuleset updates a ruleset.
func (g *GitHubCore) UpdateRuleset(owner, repo string, rulesetID int, updates map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/rulesets/" + strconv.Itoa(rulesetID), updates)
}

// DeleteRuleset deletes a ruleset.
func (g *GitHubCore) DeleteRuleset(owner, repo string, rulesetID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/rulesets/" + strconv.Itoa(rulesetID))
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Autolinks (3)
// ══════════════════════════════════════════════════════════════════════════════

// ListAutolinks lists autolinks for a repository.
func (g *GitHubCore) ListAutolinks(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/autolinks", nil)
}

// CreateAutolink creates an autolink reference.
func (g *GitHubCore) CreateAutolink(owner, repo, keyPrefix, urlTemplate string, isAlphanumeric bool) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/autolinks", map[string]any{
		"key_prefix":     keyPrefix,
		"url_template":   urlTemplate,
		"is_alphanumeric": isAlphanumeric,
	})
}

// DeleteAutolink deletes an autolink.
func (g *GitHubCore) DeleteAutolink(owner, repo string, autolinkID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/autolinks/" + strconv.Itoa(autolinkID))
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Environments (4)
// ══════════════════════════════════════════════════════════════════════════════

// ListEnvironments lists environments for a repository.
func (g *GitHubCore) ListEnvironments(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments", nil)
}

// GetEnvironment gets an environment.
func (g *GitHubCore) GetEnvironment(owner, repo, envName string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + envName, nil)
}

// CreateOrUpdateEnvironment creates or updates an environment.
func (g *GitHubCore) CreateOrUpdateEnvironment(owner, repo, envName string, config map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/environments/" + envName, config)
}

// DeleteEnvironment deletes an environment.
func (g *GitHubCore) DeleteEnvironment(owner, repo, envName string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/environments/" + envName)
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — New Methods (~800 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ── Actions — Runners ────────────────────────────────────────────────────────

func (g *GitHubCore) ListRepoRunners(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runners", nil)
}

func (g *GitHubCore) ListRunnerApplications(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runners/downloads", nil)
}

func (g *GitHubCore) CreateJITRunnerConfig(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runners/generate-jitconfig", payload)
}

func (g *GitHubCore) CreateRunnerRegistrationToken(owner, repo string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runners/registration-token", nil)
}

func (g *GitHubCore) CreateRunnerRemoveToken(owner, repo string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runners/remove-token", nil)
}

func (g *GitHubCore) GetRepoRunner(owner, repo string, runnerID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runners/" + strconv.Itoa(runnerID), nil)
}

func (g *GitHubCore) DeleteRepoRunner(owner, repo string, runnerID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/runners/" + strconv.Itoa(runnerID))
	return err
}

func (g *GitHubCore) ListRepoRunnerLabels(owner, repo string, runnerID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels", nil)
}

func (g *GitHubCore) AddRepoRunnerLabels(owner, repo string, runnerID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels", payload)
}

func (g *GitHubCore) SetRepoRunnerLabels(owner, repo string, runnerID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels", payload)
}

func (g *GitHubCore) RemoveRepoRunnerLabel(owner, repo string, runnerID int, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels/" + name)
	return err
}

func (g *GitHubCore) ListOrgRunners(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runners", nil)
}

func (g *GitHubCore) ListOrgRunnerApplications(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runners/downloads", nil)
}

func (g *GitHubCore) CreateOrgJITRunnerConfig(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/runners/generate-jitconfig", payload)
}

func (g *GitHubCore) CreateOrgRunnerRegistrationToken(org string) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/runners/registration-token", nil)
}

func (g *GitHubCore) CreateOrgRunnerRemoveToken(org string) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/runners/remove-token", nil)
}

func (g *GitHubCore) GetOrgRunner(org string, runnerID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runners/" + strconv.Itoa(runnerID), nil)
}

func (g *GitHubCore) DeleteOrgRunner(org string, runnerID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/runners/" + strconv.Itoa(runnerID))
	return err
}

func (g *GitHubCore) ListOrgRunnerLabels(org string, runnerID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels", nil)
}

func (g *GitHubCore) AddOrgRunnerLabels(org string, runnerID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels", payload)
}

func (g *GitHubCore) SetOrgRunnerLabels(org string, runnerID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels", payload)
}

func (g *GitHubCore) RemoveOrgRunnerLabel(org string, runnerID int, name string) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/runners/" + strconv.Itoa(runnerID) + "/labels/" + name)
	return err
}

// ── Actions — Runner Groups ─────────────────────────────────────────────────

func (g *GitHubCore) ListOrgRunnerGroups(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runner-groups", nil)
}

func (g *GitHubCore) CreateOrgRunnerGroup(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/runner-groups", payload)
}

func (g *GitHubCore) GetOrgRunnerGroup(org string, groupID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID), nil)
}

func (g *GitHubCore) UpdateOrgRunnerGroup(org string, groupID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID), payload)
}

func (g *GitHubCore) DeleteOrgRunnerGroup(org string, groupID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID))
	return err
}

func (g *GitHubCore) ListRunnerGroupRepos(org string, groupID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/repositories", nil)
}

func (g *GitHubCore) SetRunnerGroupRepos(org string, groupID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/repositories", payload)
}

func (g *GitHubCore) AddRunnerGroupRepo(org string, groupID, repoID int) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/repositories/" + strconv.Itoa(repoID), nil)
}

func (g *GitHubCore) RemoveRunnerGroupRepo(org string, groupID, repoID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/repositories/" + strconv.Itoa(repoID))
	return err
}

func (g *GitHubCore) ListRunnerGroupRunners(org string, groupID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/runners", nil)
}

func (g *GitHubCore) SetRunnerGroupRunners(org string, groupID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/runners", payload)
}

func (g *GitHubCore) AddRunnerGroupRunner(org string, groupID, runnerID int) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/runners/" + strconv.Itoa(runnerID), nil)
}

func (g *GitHubCore) RemoveRunnerGroupRunner(org string, groupID, runnerID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/runner-groups/" + strconv.Itoa(groupID) + "/runners/" + strconv.Itoa(runnerID))
	return err
}

// ── Actions — Hosted Runners ─────────────────────────────────────────────────

func (g *GitHubCore) ListOrgHostedRunners(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/hosted-runners", nil)
}

func (g *GitHubCore) CreateOrgHostedRunner(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/hosted-runners", payload)
}

func (g *GitHubCore) GetOrgHostedRunner(org string, runnerID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/hosted-runners/" + strconv.Itoa(runnerID), nil)
}

func (g *GitHubCore) UpdateOrgHostedRunner(org string, runnerID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/orgs/" + org + "/actions/hosted-runners/" + strconv.Itoa(runnerID), payload)
}

func (g *GitHubCore) DeleteOrgHostedRunner(org string, runnerID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/hosted-runners/" + strconv.Itoa(runnerID))
	return err
}

// ── Actions — Permissions ────────────────────────────────────────────────────

func (g *GitHubCore) GetOrgActionsPermissions(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/permissions", nil)
}

func (g *GitHubCore) SetOrgActionsPermissions(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions", payload)
}

func (g *GitHubCore) GetOrgArtifactRetention(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/permissions/artifact-and-log-retention", nil)
}

func (g *GitHubCore) SetOrgArtifactRetention(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions/artifact-and-log-retention", payload)
}

func (g *GitHubCore) GetOrgForkPRApproval(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/permissions/fork-pr-contributor-approval", nil)
}

func (g *GitHubCore) SetOrgForkPRApproval(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions/fork-pr-contributor-approval", payload)
}

func (g *GitHubCore) GetOrgEnabledRepos(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/permissions/repositories", nil)
}

func (g *GitHubCore) SetOrgEnabledRepos(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions/repositories", payload)
}

func (g *GitHubCore) AddOrgEnabledRepo(org string, repoID int) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions/repositories/" + strconv.Itoa(repoID), nil)
}

func (g *GitHubCore) RemoveOrgEnabledRepo(org string, repoID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/permissions/repositories/" + strconv.Itoa(repoID))
	return err
}

func (g *GitHubCore) GetOrgAllowedActions(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/permissions/selected-actions", nil)
}

func (g *GitHubCore) SetOrgAllowedActions(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions/selected-actions", payload)
}

func (g *GitHubCore) GetOrgDefaultWorkflowPermissions(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/permissions/workflow", nil)
}

func (g *GitHubCore) SetOrgDefaultWorkflowPermissions(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/permissions/workflow", payload)
}

func (g *GitHubCore) GetRepoActionsPermissions(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/permissions", nil)
}

func (g *GitHubCore) SetRepoActionsPermissions(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/permissions", payload)
}

func (g *GitHubCore) GetRepoActionsAccessSettings(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/permissions/access", nil)
}

func (g *GitHubCore) SetRepoActionsAccessSettings(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/permissions/access", payload)
}

func (g *GitHubCore) GetRepoAllowedActions(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/permissions/selected-actions", nil)
}

func (g *GitHubCore) SetRepoAllowedActions(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/permissions/selected-actions", payload)
}

func (g *GitHubCore) GetRepoDefaultWorkflowPermissions(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/permissions/workflow", nil)
}

func (g *GitHubCore) SetRepoDefaultWorkflowPermissions(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/permissions/workflow", payload)
}

// ── Actions — Variables ──────────────────────────────────────────────────────

func (g *GitHubCore) ListRepoVariables(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/variables", nil)
}

func (g *GitHubCore) CreateRepoVariable(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/variables", payload)
}

func (g *GitHubCore) GetRepoVariable(owner, repo, name string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/variables/" + name, nil)
}

func (g *GitHubCore) UpdateRepoVariable(owner, repo, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/actions/variables/" + name, payload)
}

func (g *GitHubCore) DeleteRepoVariable(owner, repo, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/variables/" + name)
	return err
}

func (g *GitHubCore) ListOrgVariables(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/variables", nil)
}

func (g *GitHubCore) CreateOrgVariable(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/variables", payload)
}

func (g *GitHubCore) GetOrgVariable(org, name string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/variables/" + name, nil)
}

func (g *GitHubCore) UpdateOrgVariable(org, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/orgs/" + org + "/actions/variables/" + name, payload)
}

func (g *GitHubCore) DeleteOrgVariable(org, name string) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/variables/" + name)
	return err
}

// ── Actions — Org Secrets ────────────────────────────────────────────────────

func (g *GitHubCore) ListOrgSecrets(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/secrets", nil)
}

func (g *GitHubCore) GetOrgPublicKey(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/secrets/public-key", nil)
}

func (g *GitHubCore) GetOrgSecret(org, name string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/secrets/" + name, nil)
}

func (g *GitHubCore) CreateOrUpdateOrgSecret(org, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/secrets/" + name, payload)
}

func (g *GitHubCore) DeleteOrgSecret(org, name string) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/secrets/" + name)
	return err
}

func (g *GitHubCore) ListOrgSecretRepos(org, name string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/secrets/" + name + "/repositories", nil)
}

func (g *GitHubCore) SetOrgSecretRepos(org, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/secrets/" + name + "/repositories", payload)
}

func (g *GitHubCore) AddOrgSecretRepo(org, name string, repoID int) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/secrets/" + name + "/repositories/" + strconv.Itoa(repoID), nil)
}

func (g *GitHubCore) RemoveOrgSecretRepo(org, name string, repoID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/actions/secrets/" + name + "/repositories/" + strconv.Itoa(repoID))
	return err
}

// ── Actions — Caches ─────────────────────────────────────────────────────────

func (g *GitHubCore) GetRepoCacheUsage(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/cache/usage", nil)
}

func (g *GitHubCore) ListRepoCaches(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/caches", nil)
}

func (g *GitHubCore) DeleteRepoCachesByKey(owner, repo, key string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/caches?key=" + neturl.QueryEscape(key))
	return err
}

func (g *GitHubCore) DeleteRepoCacheByID(owner, repo string, cacheID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/caches/" + strconv.Itoa(cacheID))
	return err
}

func (g *GitHubCore) GetOrgCacheUsage(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/cache/usage", nil)
}

func (g *GitHubCore) GetOrgCacheUsageByRepo(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/cache/usage-by-repository", nil)
}

// ── Actions — Workflow Runs Details ──────────────────────────────────────────

func (g *GitHubCore) GetWorkflowRunApprovals(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/approvals", nil)
}

func (g *GitHubCore) ApproveWorkflowRun(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/approve", nil)
}

func (g *GitHubCore) GetWorkflowRunAttempt(owner, repo string, runID, attempt int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/attempts/" + strconv.Itoa(attempt), nil)
}

func (g *GitHubCore) ListWorkflowRunAttemptJobs(owner, repo string, runID, attempt int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/attempts/" + strconv.Itoa(attempt) + "/jobs", nil)
}

func (g *GitHubCore) DownloadWorkflowRunAttemptLogs(owner, repo string, runID, attempt int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/attempts/" + strconv.Itoa(attempt) + "/logs", nil)
}

func (g *GitHubCore) ForceCancelWorkflowRun(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/force-cancel", nil)
}

func (g *GitHubCore) ListWorkflowRunJobs(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/jobs", nil)
}

func (g *GitHubCore) DownloadWorkflowRunLogs(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/logs", nil)
}

func (g *GitHubCore) DeleteWorkflowRunLogs(owner, repo string, runID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/logs")
	return err
}

func (g *GitHubCore) GetPendingDeployments(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/pending_deployments", nil)
}

func (g *GitHubCore) ReviewPendingDeployments(owner, repo string, runID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/pending_deployments", payload)
}

func (g *GitHubCore) RerunFailedJobs(owner, repo string, runID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/rerun-failed-jobs", payload)
}

func (g *GitHubCore) GetWorkflowRunTiming(owner, repo string, runID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID) + "/timing", nil)
}

func (g *GitHubCore) DeleteWorkflowRun(owner, repo string, runID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/actions/runs/" + strconv.Itoa(runID))
	return err
}

func (g *GitHubCore) GetWorkflowJob(owner, repo string, jobID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/jobs/" + strconv.Itoa(jobID), nil)
}

func (g *GitHubCore) DownloadWorkflowJobLogs(owner, repo string, jobID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/jobs/" + strconv.Itoa(jobID) + "/logs", nil)
}

func (g *GitHubCore) RerunWorkflowJob(owner, repo string, jobID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/jobs/" + strconv.Itoa(jobID) + "/rerun", payload)
}

// ── Actions — Workflow Management ────────────────────────────────────────────

func (g *GitHubCore) GetWorkflow(owner, repo string, workflowID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/workflows/" + strconv.Itoa(workflowID), nil)
}

func (g *GitHubCore) DisableWorkflow(owner, repo string, workflowID int) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/workflows/" + strconv.Itoa(workflowID) + "/disable", nil)
}

func (g *GitHubCore) EnableWorkflow(owner, repo string, workflowID int) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/workflows/" + strconv.Itoa(workflowID) + "/enable", nil)
}

func (g *GitHubCore) CreateWorkflowDispatch(owner, repo string, workflowID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/actions/workflows/" + strconv.Itoa(workflowID) + "/dispatches", payload)
}

func (g *GitHubCore) GetWorkflowTiming(owner, repo string, workflowID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/workflows/" + strconv.Itoa(workflowID) + "/timing", nil)
}

// ── Actions — Environment Secrets & Variables ────────────────────────────────

func (g *GitHubCore) ListEnvironmentSecrets(owner, repo, env string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/secrets", nil)
}

func (g *GitHubCore) GetEnvironmentPublicKey(owner, repo, env string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/secrets/public-key", nil)
}

func (g *GitHubCore) GetEnvironmentSecret(owner, repo, env, name string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/secrets/" + name, nil)
}

func (g *GitHubCore) CreateOrUpdateEnvironmentSecret(owner, repo, env, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/environments/" + env + "/secrets/" + name, payload)
}

func (g *GitHubCore) DeleteEnvironmentSecret(owner, repo, env, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/environments/" + env + "/secrets/" + name)
	return err
}

func (g *GitHubCore) ListEnvironmentVariables(owner, repo, env string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/variables", nil)
}

func (g *GitHubCore) CreateEnvironmentVariable(owner, repo, env string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/environments/" + env + "/variables", payload)
}

func (g *GitHubCore) GetEnvironmentVariable(owner, repo, env, name string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/variables/" + name, nil)
}

func (g *GitHubCore) UpdateEnvironmentVariable(owner, repo, env, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/environments/" + env + "/variables/" + name, payload)
}

func (g *GitHubCore) DeleteEnvironmentVariable(owner, repo, env, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/environments/" + env + "/variables/" + name)
	return err
}

// ── Actions — OIDC ───────────────────────────────────────────────────────────

func (g *GitHubCore) GetRepoOIDCSubjectClaim(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/actions/oidc/customization/sub", nil)
}

func (g *GitHubCore) SetRepoOIDCSubjectClaim(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/actions/oidc/customization/sub", payload)
}

// ── GitHub Apps ───────────────────────────────────────────────────────────────

func (g *GitHubCore) GetAuthenticatedApp() (json.RawMessage, error) {
	return g.apiGet("/app", nil)
}

func (g *GitHubCore) CreateAppFromManifest(code string) (json.RawMessage, error) {
	return g.apiPost("/app-manifests/" + code + "/conversions", nil)
}

func (g *GitHubCore) GetAppWebhookConfig() (json.RawMessage, error) {
	return g.apiGet("/app/hook/config", nil)
}

func (g *GitHubCore) UpdateAppWebhookConfig(payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/app/hook/config", payload)
}

func (g *GitHubCore) ListAppWebhookDeliveries() (json.RawMessage, error) {
	return g.apiGet("/app/hook/deliveries", nil)
}

func (g *GitHubCore) GetAppWebhookDelivery(deliveryID int) (json.RawMessage, error) {
	return g.apiGet("/app/hook/deliveries/" + strconv.Itoa(deliveryID), nil)
}

func (g *GitHubCore) RedeliverAppWebhook(deliveryID int) (json.RawMessage, error) {
	return g.apiPost("/app/hook/deliveries/" + strconv.Itoa(deliveryID) + "/attempts", nil)
}

func (g *GitHubCore) ListInstallationRequests() (json.RawMessage, error) {
	return g.apiGet("/app/installation-requests", nil)
}

func (g *GitHubCore) ListAppInstallations() (json.RawMessage, error) {
	return g.apiGet("/app/installations", nil)
}

func (g *GitHubCore) GetAppInstallation(installationID int) (json.RawMessage, error) {
	return g.apiGet("/app/installations/" + strconv.Itoa(installationID), nil)
}

func (g *GitHubCore) DeleteAppInstallation(installationID int) error {
	_, err := g.apiDelete("/app/installations/" + strconv.Itoa(installationID))
	return err
}

func (g *GitHubCore) CreateInstallationAccessToken(installationID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/app/installations/" + strconv.Itoa(installationID) + "/access_tokens", payload)
}

func (g *GitHubCore) SuspendAppInstallation(installationID int) (json.RawMessage, error) {
	return g.apiPut("/app/installations/" + strconv.Itoa(installationID) + "/suspended", nil)
}

func (g *GitHubCore) UnsuspendAppInstallation(installationID int) error {
	_, err := g.apiDelete("/app/installations/" + strconv.Itoa(installationID) + "/suspended")
	return err
}

func (g *GitHubCore) DeleteAppAuthorization(clientID string) error {
	_, err := g.apiDelete("/applications/" + clientID + "/grant")
	return err
}

func (g *GitHubCore) CheckAppToken(clientID string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/applications/" + clientID + "/token", payload)
}

func (g *GitHubCore) ResetAppToken(clientID string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/applications/" + clientID + "/token", payload)
}

func (g *GitHubCore) DeleteAppToken(clientID string) error {
	_, err := g.apiDelete("/applications/" + clientID + "/token")
	return err
}

func (g *GitHubCore) CreateScopedAccessToken(clientID string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/applications/" + clientID + "/token/scoped", payload)
}

func (g *GitHubCore) GetAppBySlug(appSlug string) (json.RawMessage, error) {
	return g.apiGet("/apps/" + appSlug, nil)
}

func (g *GitHubCore) ListInstallationRepos() (json.RawMessage, error) {
	return g.apiGet("/installation/repositories", nil)
}

func (g *GitHubCore) RevokeInstallationAccessToken() error {
	_, err := g.apiDelete("/installation/token")
	return err
}

func (g *GitHubCore) GetOrgInstallation(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/installation", nil)
}

func (g *GitHubCore) GetRepoInstallation(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/installation", nil)
}

func (g *GitHubCore) ListUserInstallations() (json.RawMessage, error) {
	return g.apiGet("/user/installations", nil)
}

func (g *GitHubCore) ListUserInstallationRepos(installationID int) (json.RawMessage, error) {
	return g.apiGet("/user/installations/" + strconv.Itoa(installationID) + "/repositories", nil)
}

func (g *GitHubCore) AddRepoToInstallation(installationID, repoID int) (json.RawMessage, error) {
	return g.apiPut("/user/installations/" + strconv.Itoa(installationID) + "/repositories/" + strconv.Itoa(repoID), nil)
}

func (g *GitHubCore) RemoveRepoFromInstallation(installationID, repoID int) error {
	_, err := g.apiDelete("/user/installations/" + strconv.Itoa(installationID) + "/repositories/" + strconv.Itoa(repoID))
	return err
}

func (g *GitHubCore) GetUserInstallation(username string) (json.RawMessage, error) {
	return g.apiGet("/users/" + username + "/installation", nil)
}

// ── Repos — Collaborators ────────────────────────────────────────────────────

func (g *GitHubCore) ListCollaborators(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/collaborators", nil)
}

func (g *GitHubCore) CheckCollaborator(owner, repo, username string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/collaborators/" + username, nil)
}

func (g *GitHubCore) AddCollaborator(owner, repo, username string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/collaborators/" + username, payload)
}

func (g *GitHubCore) RemoveCollaborator(owner, repo, username string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/collaborators/" + username)
	return err
}

// ── Repos — Deploy Keys ─────────────────────────────────────────────────────

func (g *GitHubCore) ListDeployKeys(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/keys", nil)
}

func (g *GitHubCore) CreateDeployKey(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/keys", payload)
}

func (g *GitHubCore) GetDeployKey(owner, repo string, keyID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/keys/" + strconv.Itoa(keyID), nil)
}

func (g *GitHubCore) DeleteDeployKey(owner, repo string, keyID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/keys/" + strconv.Itoa(keyID))
	return err
}

// ── Repos — Statistics ───────────────────────────────────────────────────────

func (g *GitHubCore) GetCodeFrequencyStats(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/stats/code_frequency", nil)
}

func (g *GitHubCore) GetCommitActivityStats(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/stats/commit_activity", nil)
}

func (g *GitHubCore) GetContributorStats(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/stats/contributors", nil)
}

func (g *GitHubCore) GetParticipationStats(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/stats/participation", nil)
}

func (g *GitHubCore) GetPunchCardStats(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/stats/punch_card", nil)
}

// ── Repos — Traffic ──────────────────────────────────────────────────────────

func (g *GitHubCore) GetRepoClones(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/traffic/clones", nil)
}

func (g *GitHubCore) GetTopReferralPaths(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/traffic/popular/paths", nil)
}

func (g *GitHubCore) GetTopReferrers(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/traffic/popular/referrers", nil)
}

func (g *GitHubCore) GetRepoPageViews(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/traffic/views", nil)
}

// ── Repos — Community & README ───────────────────────────────────────────────

func (g *GitHubCore) GetCommunityProfile(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/community/profile", nil)
}

func (g *GitHubCore) GetRepoREADME(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/readme", nil)
}

func (g *GitHubCore) GetDirREADME(owner, repo, dir string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/readme/" + dir, nil)
}

// ── Repos — Git Objects ──────────────────────────────────────────────────────

func (g *GitHubCore) CreateBlob(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/git/blobs", payload)
}

func (g *GitHubCore) GetBlob(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/git/blobs/" + sha, nil)
}

func (g *GitHubCore) CreateGitCommit(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/git/commits", payload)
}

func (g *GitHubCore) GetGitCommit(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/git/commits/" + sha, nil)
}

func (g *GitHubCore) ListMatchingRefs(owner, repo, ref string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/git/matching-refs/" + ref, nil)
}

func (g *GitHubCore) CreateGitTag(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/git/tags", payload)
}

func (g *GitHubCore) GetGitTag(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/git/tags/" + sha, nil)
}

// ── Repos — Misc Missing ────────────────────────────────────────────────────

func (g *GitHubCore) GetCodeownersErrors(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/codeowners/errors", nil)
}

func (g *GitHubCore) ListRepoLanguages(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/languages", nil)
}

func (g *GitHubCore) ListRepoTeams(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/teams", nil)
}

func (g *GitHubCore) CreateRepoFromTemplate(templateOwner, templateRepo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(templateOwner, templateRepo) + "/generate", payload)
}

func (g *GitHubCore) CreateRepositoryDispatch(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/dispatches", payload)
}

func (g *GitHubCore) SyncForkWithUpstream(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/merge-upstream", payload)
}

func (g *GitHubCore) MergeBranch(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/merges", payload)
}

func (g *GitHubCore) CheckVulnerabilityAlerts(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/vulnerability-alerts", nil)
}

func (g *GitHubCore) EnableVulnerabilityAlerts(owner, repo string) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/vulnerability-alerts", nil)
}

func (g *GitHubCore) DisableVulnerabilityAlerts(owner, repo string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/vulnerability-alerts")
	return err
}

func (g *GitHubCore) GetCustomPropertyValues(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/properties/values", nil)
}

func (g *GitHubCore) SetCustomPropertyValues(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/properties/values", payload)
}

func (g *GitHubCore) CreateAttestation(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/attestations", payload)
}

func (g *GitHubCore) ListAttestations(owner, repo, subjectDigest string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/attestations/" + subjectDigest, nil)
}

func (g *GitHubCore) GetLatestRelease(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/releases/latest", nil)
}

func (g *GitHubCore) GetReleaseByTag(owner, repo, tag string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/releases/tags/" + tag, nil)
}

func (g *GitHubCore) GenerateReleaseNotes(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/releases/generate-notes", payload)
}

func (g *GitHubCore) GetReleaseAsset(owner, repo string, assetID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/releases/assets/" + strconv.Itoa(assetID), nil)
}

func (g *GitHubCore) UpdateReleaseAsset(owner, repo string, assetID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/releases/assets/" + strconv.Itoa(assetID), payload)
}

func (g *GitHubCore) DeleteReleaseAsset(owner, repo string, assetID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/releases/assets/" + strconv.Itoa(assetID))
	return err
}

// ── Repos — Branch Protection Details ────────────────────────────────────────

func (g *GitHubCore) GetAdminEnforcement(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/enforce_admins", nil)
}

func (g *GitHubCore) SetAdminEnforcement(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/enforce_admins", nil)
}

func (g *GitHubCore) RemoveAdminEnforcement(owner, repo, branch string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/enforce_admins")
	return err
}

func (g *GitHubCore) GetRequiredPRReviews(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_pull_request_reviews", nil)
}

func (g *GitHubCore) UpdateRequiredPRReviews(owner, repo, branch string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_pull_request_reviews", payload)
}

func (g *GitHubCore) RemoveRequiredPRReviews(owner, repo, branch string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_pull_request_reviews")
	return err
}

func (g *GitHubCore) GetRequiredSignatures(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_signatures", nil)
}

func (g *GitHubCore) SetRequiredSignatures(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_signatures", nil)
}

func (g *GitHubCore) RemoveRequiredSignatures(owner, repo, branch string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_signatures")
	return err
}

func (g *GitHubCore) GetRequiredStatusChecks(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_status_checks", nil)
}

func (g *GitHubCore) UpdateRequiredStatusChecks(owner, repo, branch string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_status_checks", payload)
}

func (g *GitHubCore) RemoveRequiredStatusChecks(owner, repo, branch string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/required_status_checks")
	return err
}

func (g *GitHubCore) GetBranchRestrictions(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/restrictions", nil)
}

func (g *GitHubCore) DeleteBranchRestrictions(owner, repo, branch string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/branches/" + branch + "/protection/restrictions")
	return err
}

// ── Repos — Pages Extras ────────────────────────────────────────────────────

func (g *GitHubCore) UpdatePagesSite(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/pages", payload)
}

func (g *GitHubCore) DeletePagesSite(owner, repo string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/pages")
	return err
}

func (g *GitHubCore) GetLatestPagesBuild(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pages/builds/latest", nil)
}

func (g *GitHubCore) GetPagesBuild(owner, repo string, buildID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pages/builds/" + strconv.Itoa(buildID), nil)
}

func (g *GitHubCore) CreatePagesDeployment(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pages/deployments", payload)
}

func (g *GitHubCore) GetPagesDeploymentStatus(owner, repo string, deploymentID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pages/deployments/" + strconv.Itoa(deploymentID), nil)
}

func (g *GitHubCore) CancelPagesDeployment(owner, repo string, deploymentID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pages/deployments/" + strconv.Itoa(deploymentID) + "/cancel", nil)
}

func (g *GitHubCore) GetPagesDNSHealth(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pages/health", nil)
}

// ── Repos — Webhook Extras ───────────────────────────────────────────────────

func (g *GitHubCore) ListWebhookDeliveries(owner, repo string, hookID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID) + "/deliveries", nil)
}

func (g *GitHubCore) GetWebhookDelivery(owner, repo string, hookID, deliveryID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID) + "/deliveries/" + strconv.Itoa(deliveryID), nil)
}

func (g *GitHubCore) RedeliverWebhook(owner, repo string, hookID, deliveryID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID) + "/deliveries/" + strconv.Itoa(deliveryID) + "/attempts", nil)
}

func (g *GitHubCore) GetWebhookConfig(owner, repo string, hookID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID) + "/config", nil)
}

func (g *GitHubCore) UpdateWebhookConfig(owner, repo string, hookID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/hooks/" + strconv.Itoa(hookID) + "/config", payload)
}

// ── Repos — Ruleset Extras ───────────────────────────────────────────────────

func (g *GitHubCore) ListRuleSuites(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rulesets/rule-suites", nil)
}

func (g *GitHubCore) GetRuleSuite(owner, repo string, suiteID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rulesets/rule-suites/" + strconv.Itoa(suiteID), nil)
}

func (g *GitHubCore) GetRulesetHistory(owner, repo string, rulesetID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rulesets/" + strconv.Itoa(rulesetID) + "/history", nil)
}

func (g *GitHubCore) GetRulesetVersion(owner, repo string, rulesetID, versionID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rulesets/" + strconv.Itoa(rulesetID) + "/history/" + strconv.Itoa(versionID), nil)
}

func (g *GitHubCore) GetBranchRules(owner, repo, branch string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/rules/branches/" + branch, nil)
}

// ── Repos — Commits Extras ───────────────────────────────────────────────────

func (g *GitHubCore) ListBranchesForHEADCommit(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + sha + "/branches-where-head", nil)
}

func (g *GitHubCore) ListPRsForCommit(owner, repo, sha string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + sha + "/pulls", nil)
}

func (g *GitHubCore) GetCombinedStatus(owner, repo, ref string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/commits/" + ref + "/status", nil)
}

// ── Repos — Environment Deployment Policies ──────────────────────────────────

func (g *GitHubCore) ListDeploymentBranchPolicies(owner, repo, env string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment-branch-policies", nil)
}

func (g *GitHubCore) CreateDeploymentBranchPolicy(owner, repo, env string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment-branch-policies", payload)
}

func (g *GitHubCore) GetDeploymentBranchPolicy(owner, repo, env string, policyID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment-branch-policies/" + strconv.Itoa(policyID), nil)
}

func (g *GitHubCore) UpdateDeploymentBranchPolicy(owner, repo, env string, policyID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment-branch-policies/" + strconv.Itoa(policyID), payload)
}

func (g *GitHubCore) DeleteDeploymentBranchPolicy(owner, repo, env string, policyID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment-branch-policies/" + strconv.Itoa(policyID))
	return err
}

func (g *GitHubCore) ListDeploymentProtectionRules(owner, repo, env string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment_protection_rules", nil)
}

func (g *GitHubCore) CreateDeploymentProtectionRule(owner, repo, env string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment_protection_rules", payload)
}

func (g *GitHubCore) ListDeploymentProtectionRuleApps(owner, repo, env string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/environments/" + env + "/deployment_protection_rules/apps", nil)
}

// ── Pull Requests — Missing ──────────────────────────────────────────────────

func (g *GitHubCore) CreatePRCommentReply(owner, repo string, prNumber, commentID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/comments/" + strconv.Itoa(commentID) + "/replies", payload)
}

func (g *GitHubCore) ListPRCommits(owner, repo string, prNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/commits", nil)
}

func (g *GitHubCore) ListPRFiles(owner, repo string, prNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/files", nil)
}

func (g *GitHubCore) CheckPRMerged(owner, repo string, prNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/merge", nil)
}

func (g *GitHubCore) GetRequestedReviewers(owner, repo string, prNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/requested_reviewers", nil)
}

func (g *GitHubCore) RemoveRequestedReviewers(owner, repo string, prNumber int, payload map[string]any) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/requested_reviewers")
	return err
}

func (g *GitHubCore) GetPRReview(owner, repo string, prNumber, reviewID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID), nil)
}

func (g *GitHubCore) UpdatePRReview(owner, repo string, prNumber, reviewID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID), payload)
}

func (g *GitHubCore) DeletePendingPRReview(owner, repo string, prNumber, reviewID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID))
	return err
}

func (g *GitHubCore) ListPRReviewComments(owner, repo string, prNumber, reviewID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID) + "/comments", nil)
}

func (g *GitHubCore) UpdatePRBranch(owner, repo string, prNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/update-branch", payload)
}

// ── Issues — Missing ─────────────────────────────────────────────────────────

func (g *GitHubCore) ListRepoIssueEvents(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/events", nil)
}

func (g *GitHubCore) GetIssueEvent(owner, repo string, eventID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/events/" + strconv.Itoa(eventID), nil)
}

func (g *GitHubCore) AddIssueAssignees(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/assignees", payload)
}

func (g *GitHubCore) RemoveIssueAssignees(owner, repo string, issueNumber int, payload map[string]any) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/assignees")
	return err
}

func (g *GitHubCore) ListRepoAssignees(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/assignees", nil)
}

func (g *GitHubCore) CheckAssignable(owner, repo, assignee string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/assignees/" + assignee, nil)
}

func (g *GitHubCore) GetParentIssue(owner, repo string, issueNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/parent", nil)
}

func (g *GitHubCore) RemoveSubIssue(owner, repo string, issueNumber int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/sub_issue")
	return err
}

func (g *GitHubCore) ReprioritizeSubIssue(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/sub_issues/priority", payload)
}

func (g *GitHubCore) ListBlockingDependencies(owner, repo string, issueNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/dependencies/blocked_by", nil)
}

func (g *GitHubCore) AddBlockingDependency(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/dependencies/blocked_by", payload)
}

func (g *GitHubCore) RemoveBlockingDependency(owner, repo string, issueNumber, depID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/dependencies/blocked_by/" + strconv.Itoa(depID))
	return err
}

func (g *GitHubCore) ListAuthenticatedUserIssues() (json.RawMessage, error) {
	return g.apiGet("/issues", nil)
}

func (g *GitHubCore) ListOrgIssues(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/issues", nil)
}

func (g *GitHubCore) ListMilestoneLabels(owner, repo string, milestoneNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/milestones/" + strconv.Itoa(milestoneNumber) + "/labels", nil)
}

// ── Codespaces ───────────────────────────────────────────────────────────────

func (g *GitHubCore) ListOrgCodespaces(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/codespaces", nil)
}

func (g *GitHubCore) SetOrgCodespacesAccess(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/codespaces/access", payload)
}

func (g *GitHubCore) AddCodespacesAccessUsers(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/codespaces/access/selected_users", payload)
}

func (g *GitHubCore) RemoveCodespacesAccessUsers(org string, payload map[string]any) error {
	_, err := g.apiDelete("/orgs/" + org + "/codespaces/access/selected_users")
	return err
}

func (g *GitHubCore) ListOrgCodespaceSecrets(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/codespaces/secrets", nil)
}

func (g *GitHubCore) GetOrgCodespacePublicKey(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/codespaces/secrets/public-key", nil)
}

func (g *GitHubCore) GetOrgCodespaceSecret(org, name string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/codespaces/secrets/" + name, nil)
}

func (g *GitHubCore) CreateOrUpdateOrgCodespaceSecret(org, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/codespaces/secrets/" + name, payload)
}

func (g *GitHubCore) DeleteOrgCodespaceSecret(org, name string) error {
	_, err := g.apiDelete("/orgs/" + org + "/codespaces/secrets/" + name)
	return err
}

func (g *GitHubCore) ListRepoCodespaces(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/codespaces", nil)
}

func (g *GitHubCore) CreateRepoCodespace(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/codespaces", payload)
}

func (g *GitHubCore) ListDevContainerConfigs(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/codespaces/devcontainers", nil)
}

func (g *GitHubCore) ListCodespaceMachineTypes(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/codespaces/machines", nil)
}

func (g *GitHubCore) GetCodespaceDefaults(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/codespaces/new", nil)
}

func (g *GitHubCore) CheckDevContainerPermissions(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/codespaces/permissions_check", nil)
}

func (g *GitHubCore) CreateCodespaceFromPR(owner, repo string, prNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/codespaces", payload)
}

func (g *GitHubCore) ListUserCodespaces() (json.RawMessage, error) {
	return g.apiGet("/user/codespaces", nil)
}

func (g *GitHubCore) CreateUserCodespace(payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/user/codespaces", payload)
}

func (g *GitHubCore) GetCodespace(name string) (json.RawMessage, error) {
	return g.apiGet("/user/codespaces/" + name, nil)
}

func (g *GitHubCore) UpdateCodespace(name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/user/codespaces/" + name, payload)
}

func (g *GitHubCore) DeleteCodespace(name string) error {
	_, err := g.apiDelete("/user/codespaces/" + name)
	return err
}

func (g *GitHubCore) ExportCodespace(name string) (json.RawMessage, error) {
	return g.apiPost("/user/codespaces/" + name + "/exports", nil)
}

func (g *GitHubCore) GetCodespaceExport(name, exportID string) (json.RawMessage, error) {
	return g.apiGet("/user/codespaces/" + name + "/exports/" + exportID, nil)
}

func (g *GitHubCore) ListCodespaceMachines(name string) (json.RawMessage, error) {
	return g.apiGet("/user/codespaces/" + name + "/machines", nil)
}

func (g *GitHubCore) PublishCodespace(name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/user/codespaces/" + name + "/publish", payload)
}

func (g *GitHubCore) StartCodespace(name string) (json.RawMessage, error) {
	return g.apiPost("/user/codespaces/" + name + "/start", nil)
}

func (g *GitHubCore) StopCodespace(name string) (json.RawMessage, error) {
	return g.apiPost("/user/codespaces/" + name + "/stop", nil)
}

// ── Copilot ──────────────────────────────────────────────────────────────────

func (g *GitHubCore) GetCopilotSeatInfo(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/copilot/billing", nil)
}

func (g *GitHubCore) ListCopilotSeats(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/copilot/billing/seats", nil)
}

func (g *GitHubCore) AddCopilotTeams(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/copilot/billing/selected_teams", payload)
}

func (g *GitHubCore) RemoveCopilotTeams(org string, payload map[string]any) error {
	_, err := g.apiDelete("/orgs/" + org + "/copilot/billing/selected_teams")
	return err
}

func (g *GitHubCore) AddCopilotUsers(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/copilot/billing/selected_users", payload)
}

func (g *GitHubCore) RemoveCopilotUsers(org string, payload map[string]any) error {
	_, err := g.apiDelete("/orgs/" + org + "/copilot/billing/selected_users")
	return err
}

func (g *GitHubCore) GetCopilotMetrics(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/copilot/metrics", nil)
}

func (g *GitHubCore) GetCopilotUserSeat(org, username string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/members/" + username + "/copilot", nil)
}

func (g *GitHubCore) GetCopilotTeamMetrics(org, teamSlug string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/team/" + teamSlug + "/copilot/metrics", nil)
}

// ── Migrations ───────────────────────────────────────────────────────────────

func (g *GitHubCore) ListOrgMigrations(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/migrations", nil)
}

func (g *GitHubCore) StartOrgMigration(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/migrations", payload)
}

func (g *GitHubCore) GetOrgMigration(org string, migrationID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/migrations/" + strconv.Itoa(migrationID), nil)
}

func (g *GitHubCore) DownloadOrgMigrationArchive(org string, migrationID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/migrations/" + strconv.Itoa(migrationID) + "/archive", nil)
}

func (g *GitHubCore) DeleteOrgMigrationArchive(org string, migrationID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/migrations/" + strconv.Itoa(migrationID) + "/archive")
	return err
}

func (g *GitHubCore) UnlockOrgMigrationRepo(org string, migrationID int, repoName string) error {
	_, err := g.apiDelete("/orgs/" + org + "/migrations/" + strconv.Itoa(migrationID) + "/repos/" + repoName + "/lock")
	return err
}

func (g *GitHubCore) ListOrgMigrationRepos(org string, migrationID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/migrations/" + strconv.Itoa(migrationID) + "/repositories", nil)
}

func (g *GitHubCore) GetImportStatus(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/import", nil)
}

func (g *GitHubCore) StartImport(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/import", payload)
}

func (g *GitHubCore) UpdateImport(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/import", payload)
}

func (g *GitHubCore) CancelImport(owner, repo string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/import")
	return err
}

func (g *GitHubCore) ListImportAuthors(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/import/authors", nil)
}

func (g *GitHubCore) MapImportAuthor(owner, repo string, authorID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/import/authors/" + strconv.Itoa(authorID), payload)
}

func (g *GitHubCore) ListImportLargeFiles(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/import/large_files", nil)
}

func (g *GitHubCore) UpdateImportLFS(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/import/lfs", payload)
}

func (g *GitHubCore) ListUserMigrations() (json.RawMessage, error) {
	return g.apiGet("/user/migrations", nil)
}

func (g *GitHubCore) StartUserMigration(payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/user/migrations", payload)
}

func (g *GitHubCore) GetUserMigration(migrationID int) (json.RawMessage, error) {
	return g.apiGet("/user/migrations/" + strconv.Itoa(migrationID), nil)
}

func (g *GitHubCore) DownloadUserMigrationArchive(migrationID int) (json.RawMessage, error) {
	return g.apiGet("/user/migrations/" + strconv.Itoa(migrationID) + "/archive", nil)
}

func (g *GitHubCore) DeleteUserMigrationArchive(migrationID int) error {
	_, err := g.apiDelete("/user/migrations/" + strconv.Itoa(migrationID) + "/archive")
	return err
}

func (g *GitHubCore) UnlockUserMigrationRepo(migrationID int, repoName string) error {
	_, err := g.apiDelete("/user/migrations/" + strconv.Itoa(migrationID) + "/repos/" + repoName + "/lock")
	return err
}

func (g *GitHubCore) ListUserMigrationRepos(migrationID int) (json.RawMessage, error) {
	return g.apiGet("/user/migrations/" + strconv.Itoa(migrationID) + "/repositories", nil)
}

// ── Reactions ────────────────────────────────────────────────────────────────

func (g *GitHubCore) ListCommitCommentReactions(owner, repo string, commentID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/comments/" + strconv.Itoa(commentID) + "/reactions", nil)
}

func (g *GitHubCore) CreateCommitCommentReaction(owner, repo string, commentID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/comments/" + strconv.Itoa(commentID) + "/reactions", payload)
}

func (g *GitHubCore) DeleteCommitCommentReaction(owner, repo string, commentID, reactionID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/comments/" + strconv.Itoa(commentID) + "/reactions/" + strconv.Itoa(reactionID))
	return err
}

func (g *GitHubCore) ListIssueCommentReactions(owner, repo string, commentID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/comments/" + strconv.Itoa(commentID) + "/reactions", nil)
}

func (g *GitHubCore) CreateIssueCommentReaction(owner, repo string, commentID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/issues/comments/" + strconv.Itoa(commentID) + "/reactions", payload)
}

func (g *GitHubCore) DeleteIssueCommentReaction(owner, repo string, commentID, reactionID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/comments/" + strconv.Itoa(commentID) + "/reactions/" + strconv.Itoa(reactionID))
	return err
}

func (g *GitHubCore) ListIssueReactions(owner, repo string, issueNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/reactions", nil)
}

func (g *GitHubCore) CreateIssueReaction(owner, repo string, issueNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/reactions", payload)
}

func (g *GitHubCore) DeleteIssueReaction(owner, repo string, issueNumber, reactionID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/issues/" + strconv.Itoa(issueNumber) + "/reactions/" + strconv.Itoa(reactionID))
	return err
}

func (g *GitHubCore) ListPRCommentReactions(owner, repo string, commentID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/comments/" + strconv.Itoa(commentID) + "/reactions", nil)
}

func (g *GitHubCore) CreatePRCommentReaction(owner, repo string, commentID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/comments/" + strconv.Itoa(commentID) + "/reactions", payload)
}

func (g *GitHubCore) DeletePRCommentReaction(owner, repo string, commentID, reactionID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/pulls/comments/" + strconv.Itoa(commentID) + "/reactions/" + strconv.Itoa(reactionID))
	return err
}

func (g *GitHubCore) ListReleaseReactions(owner, repo string, releaseID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID) + "/reactions", nil)
}

func (g *GitHubCore) CreateReleaseReaction(owner, repo string, releaseID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID) + "/reactions", payload)
}

func (g *GitHubCore) DeleteReleaseReaction(owner, repo string, releaseID, reactionID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/releases/" + strconv.Itoa(releaseID) + "/reactions/" + strconv.Itoa(reactionID))
	return err
}

// ── Security Advisories ──────────────────────────────────────────────────────

func (g *GitHubCore) ListGlobalAdvisories() (json.RawMessage, error) {
	return g.apiGet("/advisories", nil)
}

func (g *GitHubCore) GetGlobalAdvisory(ghsaID string) (json.RawMessage, error) {
	return g.apiGet("/advisories/" + ghsaID, nil)
}

func (g *GitHubCore) ListOrgAdvisories(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/security-advisories", nil)
}

func (g *GitHubCore) ListRepoAdvisories(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/security-advisories", nil)
}

func (g *GitHubCore) CreateRepoAdvisory(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/security-advisories", payload)
}

func (g *GitHubCore) ReportVulnerability(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/security-advisories/reports", payload)
}

func (g *GitHubCore) GetRepoAdvisory(owner, repo, ghsaID string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/security-advisories/" + ghsaID, nil)
}

func (g *GitHubCore) UpdateRepoAdvisory(owner, repo, ghsaID string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/security-advisories/" + ghsaID, payload)
}

func (g *GitHubCore) RequestCVE(owner, repo, ghsaID string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/security-advisories/" + ghsaID + "/cve", nil)
}

func (g *GitHubCore) CreatePrivateFork(owner, repo, ghsaID string) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/security-advisories/" + ghsaID + "/forks", nil)
}

// ── Code Scanning — Extended ─────────────────────────────────────────────────

func (g *GitHubCore) UpdateCodeScanningAlert(owner, repo string, alertNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/code-scanning/alerts/" + strconv.Itoa(alertNumber), payload)
}

func (g *GitHubCore) GetCodeScanningAutofix(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/alerts/" + strconv.Itoa(alertNumber) + "/autofix", nil)
}

func (g *GitHubCore) CreateCodeScanningAutofix(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/code-scanning/alerts/" + strconv.Itoa(alertNumber) + "/autofix", nil)
}

func (g *GitHubCore) ListCodeScanningAlertInstances(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/alerts/" + strconv.Itoa(alertNumber) + "/instances", nil)
}

func (g *GitHubCore) ListCodeScanningAnalyses(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/analyses", nil)
}

func (g *GitHubCore) GetCodeScanningAnalysis(owner, repo string, analysisID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/analyses/" + strconv.Itoa(analysisID), nil)
}

func (g *GitHubCore) DeleteCodeScanningAnalysis(owner, repo string, analysisID int) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/code-scanning/analyses/" + strconv.Itoa(analysisID))
	return err
}

func (g *GitHubCore) ListCodeQLDatabases(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/codeql/databases", nil)
}

func (g *GitHubCore) GetCodeQLDatabase(owner, repo, lang string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/codeql/databases/" + lang, nil)
}

func (g *GitHubCore) GetCodeScanningDefaultSetup(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/default-setup", nil)
}

func (g *GitHubCore) UpdateCodeScanningDefaultSetup(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/code-scanning/default-setup", payload)
}

func (g *GitHubCore) UploadSARIF(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/code-scanning/sarifs", payload)
}

func (g *GitHubCore) GetSARIFUpload(owner, repo, sarifID string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/code-scanning/sarifs/" + sarifID, nil)
}

func (g *GitHubCore) ListOrgCodeScanningAlerts(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/code-scanning/alerts", nil)
}

// ── Dependabot — Extended ────────────────────────────────────────────────────

func (g *GitHubCore) GetDependabotAlert(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependabot/alerts/" + strconv.Itoa(alertNumber), nil)
}

func (g *GitHubCore) UpdateDependabotAlert(owner, repo string, alertNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/dependabot/alerts/" + strconv.Itoa(alertNumber), payload)
}

func (g *GitHubCore) ListRepoDependabotSecrets(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependabot/secrets", nil)
}

func (g *GitHubCore) GetRepoDependabotPublicKey(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependabot/secrets/public-key", nil)
}

func (g *GitHubCore) GetRepoDependabotSecret(owner, repo, name string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependabot/secrets/" + name, nil)
}

func (g *GitHubCore) CreateOrUpdateRepoDependabotSecret(owner, repo, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/dependabot/secrets/" + name, payload)
}

func (g *GitHubCore) DeleteRepoDependabotSecret(owner, repo, name string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/dependabot/secrets/" + name)
	return err
}

func (g *GitHubCore) ListOrgDependabotSecrets(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/dependabot/secrets", nil)
}

func (g *GitHubCore) GetOrgDependabotPublicKey(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/dependabot/secrets/public-key", nil)
}

func (g *GitHubCore) GetOrgDependabotSecret(org, name string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/dependabot/secrets/" + name, nil)
}

func (g *GitHubCore) CreateOrUpdateOrgDependabotSecret(org, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/dependabot/secrets/" + name, payload)
}

func (g *GitHubCore) DeleteOrgDependabotSecret(org, name string) error {
	_, err := g.apiDelete("/orgs/" + org + "/dependabot/secrets/" + name)
	return err
}

func (g *GitHubCore) ListOrgDependabotAlerts(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/dependabot/alerts", nil)
}

// ── Secret Scanning — Extended ───────────────────────────────────────────────

func (g *GitHubCore) GetSecretScanningAlert(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/secret-scanning/alerts/" + strconv.Itoa(alertNumber), nil)
}

func (g *GitHubCore) UpdateSecretScanningAlert(owner, repo string, alertNumber int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/secret-scanning/alerts/" + strconv.Itoa(alertNumber), payload)
}

func (g *GitHubCore) ListSecretScanningAlertLocations(owner, repo string, alertNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/secret-scanning/alerts/" + strconv.Itoa(alertNumber) + "/locations", nil)
}

func (g *GitHubCore) CreatePushProtectionBypass(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/secret-scanning/push-protection-bypasses", payload)
}

func (g *GitHubCore) GetSecretScanHistory(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/secret-scanning/scan-history", nil)
}

func (g *GitHubCore) ListOrgSecretScanningAlerts(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/secret-scanning/alerts", nil)
}

// ── Organizations — Webhooks ─────────────────────────────────────────────────

func (g *GitHubCore) ListOrgWebhooks(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/hooks", nil)
}

func (g *GitHubCore) CreateOrgWebhook(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/hooks", payload)
}

func (g *GitHubCore) GetOrgWebhook(org string, hookID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/hooks/" + strconv.Itoa(hookID), nil)
}

func (g *GitHubCore) UpdateOrgWebhook(org string, hookID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/orgs/" + org + "/hooks/" + strconv.Itoa(hookID), payload)
}

func (g *GitHubCore) DeleteOrgWebhook(org string, hookID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/hooks/" + strconv.Itoa(hookID))
	return err
}

func (g *GitHubCore) PingOrgWebhook(org string, hookID int) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/hooks/" + strconv.Itoa(hookID) + "/pings", nil)
}

// ── Organizations — Blocks ───────────────────────────────────────────────────

func (g *GitHubCore) ListOrgBlockedUsers(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/blocks", nil)
}

func (g *GitHubCore) BlockOrgUser(org, username string) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/blocks/" + username, nil)
}

func (g *GitHubCore) UnblockOrgUser(org, username string) error {
	_, err := g.apiDelete("/orgs/" + org + "/blocks/" + username)
	return err
}

// ── Organizations — Invitations ──────────────────────────────────────────────

func (g *GitHubCore) ListOrgInvitations(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/invitations", nil)
}

func (g *GitHubCore) CreateOrgInvitation(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/invitations", payload)
}

func (g *GitHubCore) CancelOrgInvitation(org string, invitationID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/invitations/" + strconv.Itoa(invitationID))
	return err
}

func (g *GitHubCore) ListInvitationTeams(org string, invitationID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/invitations/" + strconv.Itoa(invitationID) + "/teams", nil)
}

func (g *GitHubCore) ListFailedInvitations(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/failed_invitations", nil)
}

// ── Organizations — Roles ────────────────────────────────────────────────────

func (g *GitHubCore) ListOrgRoles(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/organization-roles", nil)
}

func (g *GitHubCore) GetOrgRole(org string, roleID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/organization-roles/" + strconv.Itoa(roleID), nil)
}

func (g *GitHubCore) AssignTeamRole(org, teamSlug string, roleID int) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/organization-roles/teams/" + teamSlug + "/" + strconv.Itoa(roleID), nil)
}

func (g *GitHubCore) RemoveTeamRole(org, teamSlug string, roleID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/organization-roles/teams/" + teamSlug + "/" + strconv.Itoa(roleID))
	return err
}

func (g *GitHubCore) AssignUserRole(org, username string, roleID int) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/organization-roles/users/" + username + "/" + strconv.Itoa(roleID), nil)
}

func (g *GitHubCore) RemoveUserRole(org, username string, roleID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/organization-roles/users/" + username + "/" + strconv.Itoa(roleID))
	return err
}

func (g *GitHubCore) ListTeamsForRole(org string, roleID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/organization-roles/" + strconv.Itoa(roleID) + "/teams", nil)
}

func (g *GitHubCore) ListUsersForRole(org string, roleID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/organization-roles/" + strconv.Itoa(roleID) + "/users", nil)
}

// ── Organizations — Outside Collaborators ────────────────────────────────────

func (g *GitHubCore) ListOutsideCollaborators(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/outside_collaborators", nil)
}

func (g *GitHubCore) ConvertToOutsideCollaborator(org, username string) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/outside_collaborators/" + username, nil)
}

func (g *GitHubCore) RemoveOutsideCollaborator(org, username string) error {
	_, err := g.apiDelete("/orgs/" + org + "/outside_collaborators/" + username)
	return err
}

// ── Organizations — Memberships ──────────────────────────────────────────────

func (g *GitHubCore) GetOrgMembership(org, username string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/memberships/" + username, nil)
}

func (g *GitHubCore) SetOrgMembership(org, username string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/memberships/" + username, payload)
}

func (g *GitHubCore) RemoveOrgMembership(org, username string) error {
	_, err := g.apiDelete("/orgs/" + org + "/memberships/" + username)
	return err
}

func (g *GitHubCore) ListUserOrgMemberships() (json.RawMessage, error) {
	return g.apiGet("/user/memberships/orgs", nil)
}

func (g *GitHubCore) GetUserOrgMembership(org string) (json.RawMessage, error) {
	return g.apiGet("/user/memberships/orgs/" + org, nil)
}

// ── Organizations — Custom Properties ────────────────────────────────────────

func (g *GitHubCore) ListOrgCustomProperties(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/properties/schema", nil)
}

func (g *GitHubCore) CreateOrgCustomProperties(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/orgs/" + org + "/properties/schema", payload)
}

func (g *GitHubCore) GetOrgCustomProperty(org, name string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/properties/schema/" + name, nil)
}

func (g *GitHubCore) CreateOrUpdateOrgCustomProperty(org, name string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/properties/schema/" + name, payload)
}

func (g *GitHubCore) DeleteOrgCustomProperty(org, name string) error {
	_, err := g.apiDelete("/orgs/" + org + "/properties/schema/" + name)
	return err
}

// ── Organizations — PAT Management ───────────────────────────────────────────

func (g *GitHubCore) ListOrgPATRequests(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/personal-access-token-requests", nil)
}

func (g *GitHubCore) ReviewOrgPATRequests(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/personal-access-token-requests", payload)
}

func (g *GitHubCore) ReviewOrgPATRequest(org string, requestID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/personal-access-token-requests/" + strconv.Itoa(requestID), payload)
}

func (g *GitHubCore) ListOrgPATs(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/personal-access-tokens", nil)
}

func (g *GitHubCore) UpdateOrgPATs(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/personal-access-tokens", payload)
}

func (g *GitHubCore) UpdateOrgPAT(org string, patID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/personal-access-tokens/" + strconv.Itoa(patID), payload)
}

// ── Organizations — Security Managers ────────────────────────────────────────

func (g *GitHubCore) ListSecurityManagers(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/security-managers", nil)
}

func (g *GitHubCore) AddSecurityManagerTeam(org, teamSlug string) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/security-managers/teams/" + teamSlug, nil)
}

func (g *GitHubCore) RemoveSecurityManagerTeam(org, teamSlug string) error {
	_, err := g.apiDelete("/orgs/" + org + "/security-managers/teams/" + teamSlug)
	return err
}

// ── Organizations — Public Members ───────────────────────────────────────────

func (g *GitHubCore) ListPublicMembers(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/public_members", nil)
}

func (g *GitHubCore) CheckPublicMembership(org, username string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/public_members/" + username, nil)
}

func (g *GitHubCore) PublicizeMembership(org, username string) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/public_members/" + username, nil)
}

func (g *GitHubCore) ConcealMembership(org, username string) error {
	_, err := g.apiDelete("/orgs/" + org + "/public_members/" + username)
	return err
}

// ── Teams — Extended ─────────────────────────────────────────────────────────

func (g *GitHubCore) ListTeamInvitations(org, teamSlug string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams/" + teamSlug + "/invitations", nil)
}

func (g *GitHubCore) ListTeamRepos(org, teamSlug string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams/" + teamSlug + "/repos", nil)
}

func (g *GitHubCore) CheckTeamRepo(org, teamSlug, owner, repo string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams/" + teamSlug + "/repos/" + owner + "/" + repo, nil)
}

func (g *GitHubCore) AddTeamRepo(org, teamSlug, owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/teams/" + teamSlug + "/repos/" + owner + "/" + repo, payload)
}

func (g *GitHubCore) RemoveTeamRepo(org, teamSlug, owner, repo string) error {
	_, err := g.apiDelete("/orgs/" + org + "/teams/" + teamSlug + "/repos/" + owner + "/" + repo)
	return err
}

func (g *GitHubCore) ListChildTeams(org, teamSlug string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams/" + teamSlug + "/teams", nil)
}

func (g *GitHubCore) ListUserTeams() (json.RawMessage, error) {
	return g.apiGet("/user/teams", nil)
}

// ── Users — Extended ─────────────────────────────────────────────────────────

func (g *GitHubCore) SetEmailVisibility(payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/user/email/visibility", payload)
}

func (g *GitHubCore) ListPublicEmails() (json.RawMessage, error) {
	return g.apiGet("/user/public_emails", nil)
}

func (g *GitHubCore) ListSSHSigningKeys() (json.RawMessage, error) {
	return g.apiGet("/user/ssh_signing_keys", nil)
}

func (g *GitHubCore) CreateSSHSigningKey(payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/user/ssh_signing_keys", payload)
}

func (g *GitHubCore) GetSSHSigningKey(keyID int) (json.RawMessage, error) {
	return g.apiGet("/user/ssh_signing_keys/" + strconv.Itoa(keyID), nil)
}

func (g *GitHubCore) DeleteSSHSigningKey(keyID int) error {
	_, err := g.apiDelete("/user/ssh_signing_keys/" + strconv.Itoa(keyID))
	return err
}

// ── Search — Extended ────────────────────────────────────────────────────────

func (g *GitHubCore) SearchIssuesAndPRs(query string, params map[string]string) (json.RawMessage, error) {
	if params == nil {
		params = map[string]string{}
	}
	params["q"] = query
	return g.apiGet("/search/issues", params)
}

func (g *GitHubCore) SearchRepositories(query string, params map[string]string) (json.RawMessage, error) {
	if params == nil {
		params = map[string]string{}
	}
	params["q"] = query
	return g.apiGet("/search/repositories", params)
}

func (g *GitHubCore) SearchUsers(query string, params map[string]string) (json.RawMessage, error) {
	if params == nil {
		params = map[string]string{}
	}
	params["q"] = query
	return g.apiGet("/search/users", params)
}

// ── Checks — Extended ────────────────────────────────────────────────────────

func (g *GitHubCore) ListCheckRunAnnotations(owner, repo string, checkRunID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/check-runs/" + strconv.Itoa(checkRunID) + "/annotations", nil)
}

func (g *GitHubCore) RerequestCheckRun(owner, repo string, checkRunID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/check-runs/" + strconv.Itoa(checkRunID) + "/rerequest", nil)
}

func (g *GitHubCore) UpdateCheckSuitePreferences(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch(ghRepoPath(owner, repo) + "/check-suites/preferences", payload)
}

func (g *GitHubCore) GetCheckSuite(owner, repo string, checkSuiteID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/check-suites/" + strconv.Itoa(checkSuiteID), nil)
}

func (g *GitHubCore) RerequestCheckSuite(owner, repo string, checkSuiteID int) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/check-suites/" + strconv.Itoa(checkSuiteID) + "/rerequest", nil)
}

func (g *GitHubCore) ListCheckSuiteCheckRuns(owner, repo string, checkSuiteID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/check-suites/" + strconv.Itoa(checkSuiteID) + "/check-runs", nil)
}



// ── Gists — Extended ─────────────────────────────────────────────────────────

func (g *GitHubCore) GetGistRevision(gistID, sha string) (json.RawMessage, error) {
	return g.apiGet("/gists/" + gistID + "/" + sha, nil)
}

func (g *GitHubCore) ListGistCommits(gistID string) (json.RawMessage, error) {
	return g.apiGet("/gists/" + gistID + "/commits", nil)
}

func (g *GitHubCore) ListGistForks(gistID string) (json.RawMessage, error) {
	return g.apiGet("/gists/" + gistID + "/forks", nil)
}

func (g *GitHubCore) ForkGist(gistID string) (json.RawMessage, error) {
	return g.apiPost("/gists/" + gistID + "/forks", nil)
}

func (g *GitHubCore) ListPublicGists() (json.RawMessage, error) {
	return g.apiGet("/gists/public", nil)
}

func (g *GitHubCore) ListStarredGists() (json.RawMessage, error) {
	return g.apiGet("/gists/starred", nil)
}

func (g *GitHubCore) ListUserGists(username string) (json.RawMessage, error) {
	return g.apiGet("/users/" + username + "/gists", nil)
}

// ── Packages — Extended ─────────────────────────────────────────────────────

func (g *GitHubCore) RestoreOrgPackage(org, packageType, packageName string) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/packages/" + packageType + "/" + packageName + "/restore", nil)
}

func (g *GitHubCore) GetOrgPackageVersion(org, packageType, packageName string, versionID int) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/packages/" + packageType + "/" + packageName + "/versions/" + strconv.Itoa(versionID), nil)
}

func (g *GitHubCore) DeleteOrgPackageVersion(org, packageType, packageName string, versionID int) error {
	_, err := g.apiDelete("/orgs/" + org + "/packages/" + packageType + "/" + packageName + "/versions/" + strconv.Itoa(versionID))
	return err
}

func (g *GitHubCore) RestoreOrgPackageVersion(org, packageType, packageName string, versionID int) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/packages/" + packageType + "/" + packageName + "/versions/" + strconv.Itoa(versionID) + "/restore", nil)
}

func (g *GitHubCore) RestoreUserPackage(packageType, packageName string) (json.RawMessage, error) {
	return g.apiPost("/user/packages/" + packageType + "/" + packageName + "/restore", nil)
}

func (g *GitHubCore) GetUserPackageVersion(packageType, packageName string, versionID int) (json.RawMessage, error) {
	return g.apiGet("/user/packages/" + packageType + "/" + packageName + "/versions/" + strconv.Itoa(versionID), nil)
}

func (g *GitHubCore) DeleteUserPackageVersion(packageType, packageName string, versionID int) error {
	_, err := g.apiDelete("/user/packages/" + packageType + "/" + packageName + "/versions/" + strconv.Itoa(versionID))
	return err
}

func (g *GitHubCore) RestoreUserPackageVersion(packageType, packageName string, versionID int) (json.RawMessage, error) {
	return g.apiPost("/user/packages/" + packageType + "/" + packageName + "/versions/" + strconv.Itoa(versionID) + "/restore", nil)
}

// ── Dependency Graph ─────────────────────────────────────────────────────────

func (g *GitHubCore) GetDependencyDiff(owner, repo, basehead string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependency-graph/compare/" + basehead, nil)
}

func (g *GitHubCore) ExportSBOM(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/dependency-graph/sbom", nil)
}

func (g *GitHubCore) CreateDependencySnapshot(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/dependency-graph/snapshots", payload)
}

// ── Interactions ─────────────────────────────────────────────────────────────

func (g *GitHubCore) GetOrgInteractionLimits(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/interaction-limits", nil)
}

func (g *GitHubCore) SetOrgInteractionLimits(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/interaction-limits", payload)
}

func (g *GitHubCore) RemoveOrgInteractionLimits(org string) error {
	_, err := g.apiDelete("/orgs/" + org + "/interaction-limits")
	return err
}

func (g *GitHubCore) GetRepoInteractionLimits(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/interaction-limits", nil)
}

func (g *GitHubCore) SetRepoInteractionLimits(owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/interaction-limits", payload)
}

func (g *GitHubCore) RemoveRepoInteractionLimits(owner, repo string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/interaction-limits")
	return err
}

func (g *GitHubCore) GetUserInteractionLimits() (json.RawMessage, error) {
	return g.apiGet("/user/interaction-limits", nil)
}

func (g *GitHubCore) SetUserInteractionLimits(payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/user/interaction-limits", payload)
}

func (g *GitHubCore) RemoveUserInteractionLimits() error {
	_, err := g.apiDelete("/user/interaction-limits")
	return err
}

// ── Billing ──────────────────────────────────────────────────────────────────

func (g *GitHubCore) ListOrgBudgets(org string) (json.RawMessage, error) {
	return g.apiGet("/organizations/" + org + "/settings/billing/budgets", nil)
}

func (g *GitHubCore) GetOrgBudget(org string, budgetID int) (json.RawMessage, error) {
	return g.apiGet("/organizations/" + org + "/settings/billing/budgets/" + strconv.Itoa(budgetID), nil)
}

func (g *GitHubCore) UpdateOrgBudget(org string, budgetID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPatch("/organizations/" + org + "/settings/billing/budgets/" + strconv.Itoa(budgetID), payload)
}

func (g *GitHubCore) DeleteOrgBudget(org string, budgetID int) error {
	_, err := g.apiDelete("/organizations/" + org + "/settings/billing/budgets/" + strconv.Itoa(budgetID))
	return err
}

func (g *GitHubCore) GetOrgBillingUsage(org string) (json.RawMessage, error) {
	return g.apiGet("/organizations/" + org + "/settings/billing/usage", nil)
}

func (g *GitHubCore) GetOrgBillingUsageSummary(org string) (json.RawMessage, error) {
	return g.apiGet("/organizations/" + org + "/settings/billing/usage/summary", nil)
}

// ── Licenses ─────────────────────────────────────────────────────────────────

func (g *GitHubCore) ListLicenses() (json.RawMessage, error) {
	return g.apiGet("/licenses", nil)
}

func (g *GitHubCore) GetLicense(license string) (json.RawMessage, error) {
	return g.apiGet("/licenses/" + license, nil)
}

func (g *GitHubCore) GetRepoLicense(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/license", nil)
}

// ── Meta / Server Info ───────────────────────────────────────────────────────

func (g *GitHubCore) GetAPIRoot() (json.RawMessage, error) {
	return g.apiGet("/", nil)
}

func (g *GitHubCore) GetMeta() (json.RawMessage, error) {
	return g.apiGet("/meta", nil)
}

func (g *GitHubCore) GetAPIVersions() (json.RawMessage, error) {
	return g.apiGet("/versions", nil)
}

// ── Gitignore Templates ──────────────────────────────────────────────────────

func (g *GitHubCore) ListGitignoreTemplates() (json.RawMessage, error) {
	return g.apiGet("/gitignore/templates", nil)
}

func (g *GitHubCore) GetGitignoreTemplate(name string) (json.RawMessage, error) {
	return g.apiGet("/gitignore/templates/" + name, nil)
}

// ── Codes of Conduct ─────────────────────────────────────────────────────────

func (g *GitHubCore) ListCodesOfConduct() (json.RawMessage, error) {
	return g.apiGet("/codes_of_conduct", nil)
}

func (g *GitHubCore) GetCodeOfConduct(key string) (json.RawMessage, error) {
	return g.apiGet("/codes_of_conduct/" + key, nil)
}

// ── Projects V2 — GraphQL-based ──────────────────────────────────────────────

func (g *GitHubCore) ListOrgProjectsV2(org string) (json.RawMessage, error) {
	query := `query($org:String!){organization(login:$org){projectsV2(first:100){nodes{id title number}}}}`
	return g.ghGraphQL(query, map[string]any{"org": org})
}

func (g *GitHubCore) GetProjectV2(projectID string) (json.RawMessage, error) {
	query := `query($id:ID!){node(id:$id){...on ProjectV2{id title number}}}`
	return g.ghGraphQL(query, map[string]any{"id": projectID})
}

func (g *GitHubCore) CreateProjectV2DraftItem(projectID string, payload map[string]any) (json.RawMessage, error) {
	mutation := `mutation($input:AddProjectV2DraftIssueInput!){addProjectV2DraftIssue(input:$input){projectItem{id}}}`
	payload["projectId"] = projectID
	return g.ghGraphQL(mutation, map[string]any{"input": payload})
}

func (g *GitHubCore) ListProjectV2Fields(projectID string) (json.RawMessage, error) {
	query := `query($id:ID!){node(id:$id){...on ProjectV2{fields(first:100){nodes{...on ProjectV2Field{id name}...on ProjectV2IterationField{id name}...on ProjectV2SingleSelectField{id name options{id name}}}}}}}`
	return g.ghGraphQL(query, map[string]any{"id": projectID})
}

func (g *GitHubCore) ListProjectV2Items(projectID string) (json.RawMessage, error) {
	query := `query($id:ID!){node(id:$id){...on ProjectV2{items(first:100){nodes{id content{...on Issue{title number}...on PullRequest{title number}...on DraftIssue{title}}}}}}}`
	return g.ghGraphQL(query, map[string]any{"id": projectID})
}

func (g *GitHubCore) AddProjectV2Item(projectID, contentID string) (json.RawMessage, error) {
	mutation := `mutation($input:AddProjectV2ItemByIdInput!){addProjectV2ItemById(input:$input){item{id}}}`
	return g.ghGraphQL(mutation, map[string]any{"input": map[string]any{"projectId": projectID, "contentId": contentID}})
}

func (g *GitHubCore) UpdateProjectV2Item(projectID, itemID, fieldID string, value any) (json.RawMessage, error) {
	mutation := `mutation($input:UpdateProjectV2ItemFieldValueInput!){updateProjectV2ItemFieldValue(input:$input){projectV2Item{id}}}`
	return g.ghGraphQL(mutation, map[string]any{"input": map[string]any{"projectId": projectID, "itemId": itemID, "fieldId": fieldID, "value": value}})
}

func (g *GitHubCore) DeleteProjectV2Item(projectID, itemID string) (json.RawMessage, error) {
	mutation := `mutation($input:DeleteProjectV2ItemInput!){deleteProjectV2Item(input:$input){deletedItemId}}`
	return g.ghGraphQL(mutation, map[string]any{"input": map[string]any{"projectId": projectID, "itemId": itemID}})
}

func (g *GitHubCore) CreateProjectV2View(projectID string, payload map[string]any) (json.RawMessage, error) {
	mutation := `mutation($input:CreateProjectV2ViewInput!){createProjectV2View(input:$input){projectView{id name}}}`
	payload["projectId"] = projectID
	return g.ghGraphQL(mutation, map[string]any{"input": payload})
}

func (g *GitHubCore) UpdateProjectV2(projectID string, payload map[string]any) (json.RawMessage, error) {
	mutation := `mutation($input:UpdateProjectV2Input!){updateProjectV2(input:$input){projectV2{id title}}}`
	payload["projectId"] = projectID
	return g.ghGraphQL(mutation, map[string]any{"input": payload})
}

func (g *GitHubCore) DeleteProjectV2(projectID string) (json.RawMessage, error) {
	mutation := `mutation($input:DeleteProjectV2Input!){deleteProjectV2(input:$input){projectV2{id}}}`
	return g.ghGraphQL(mutation, map[string]any{"input": map[string]any{"projectId": projectID}})
}

func (g *GitHubCore) CopyProjectV2(projectID, ownerID, title string) (json.RawMessage, error) {
	mutation := `mutation($input:CopyProjectV2Input!){copyProjectV2(input:$input){projectV2{id title}}}`
	return g.ghGraphQL(mutation, map[string]any{"input": map[string]any{"projectId": projectID, "ownerId": ownerID, "title": title}})
}

// ── Classroom ────────────────────────────────────────────────────────────────

func (g *GitHubCore) GetAssignment(assignmentID int) (json.RawMessage, error) {
	return g.apiGet("/assignments/" + strconv.Itoa(assignmentID), nil)
}

func (g *GitHubCore) ListAcceptedAssignments(assignmentID int) (json.RawMessage, error) {
	return g.apiGet("/assignments/" + strconv.Itoa(assignmentID) + "/accepted_assignments", nil)
}

func (g *GitHubCore) GetAssignmentGrades(assignmentID int) (json.RawMessage, error) {
	return g.apiGet("/assignments/" + strconv.Itoa(assignmentID) + "/grades", nil)
}

func (g *GitHubCore) ListClassrooms() (json.RawMessage, error) {
	return g.apiGet("/classrooms", nil)
}

func (g *GitHubCore) GetClassroom(classroomID int) (json.RawMessage, error) {
	return g.apiGet("/classrooms/" + strconv.Itoa(classroomID), nil)
}

func (g *GitHubCore) ListClassroomAssignments(classroomID int) (json.RawMessage, error) {
	return g.apiGet("/classrooms/" + strconv.Itoa(classroomID) + "/assignments", nil)
}

// ── OIDC (Org-level) ─────────────────────────────────────────────────────────

func (g *GitHubCore) GetOrgOIDCSubjectClaim(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/oidc/customization/sub", nil)
}

func (g *GitHubCore) SetOrgOIDCSubjectClaim(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/actions/oidc/customization/sub", payload)
}

func (g *GitHubCore) GetOrgOIDCProperties(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/actions/oidc/customization/properties/repo", nil)
}

func (g *GitHubCore) SetOrgOIDCProperties(org string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost("/orgs/" + org + "/actions/oidc/customization/properties/repo", payload)
}

func (g *GitHubCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	return nil, fmt.Errorf("%w: %s does not support send location", ErrNotSupported, ghPlatform)
}
