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

	// Polling intervals — tiered strategy (all use conditional requests; 304s are FREE)
	ghPollActiveFast = 3 * time.Second  // per-issue polling for the actively viewed conversation
	ghPollRecent     = 15 * time.Second // recently active chats (last 5 min)
	ghPollIdle       = 60 * time.Second // no activity in 30 min — notifications only
	ghPollBG         = 5 * time.Minute  // background / not visible
	ghNotifPoll      = 10 * time.Second // notifications endpoint (304s are free)

	// Budget protection thresholds (X-RateLimit-Remaining)
	ghBudgetCautionThreshold  = 500 // <10% of 5000 → slow all polling to 30s
	ghBudgetCriticalThreshold = 100 // <2% of 5000 → slow all polling to 120s
	ghBudgetCautionInterval   = 30 * time.Second
	ghBudgetCriticalInterval  = 120 * time.Second

	// Deduplication
	ghSeenIDsCapacity = 1000 // max number of comment IDs to track for dedup

	// Recently-active window: chats with activity in this window get polled at ghPollRecent
	ghRecentWindow = 5 * time.Minute

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

	// Active chat: the conversation currently open in the GUI (fast-polled at 2-3s)
	activeChatID     string
	activeChatCancel context.CancelFunc // cancels the per-chat fast poll goroutine
	activeChatMu     sync.Mutex

	// Deduplication: bounded set of recently seen comment IDs to prevent duplicate UpdateNewMessage
	seenCommentIDs   []string // ring buffer of comment IDs
	seenCommentIdx   int      // next write position in the ring buffer
	seenCommentSet   map[string]bool
	seenCommentMu    sync.Mutex

	// Per-thread If-Modified-Since timestamps (complement ETags)
	threadLastMod   map[string]string // chatID → Last-Modified timestamp
	threadLastModMu sync.RWMutex

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

	// Marked-unread state (local, per-chat)
	markedUnread   map[string]bool // chatID → true if marked unread
	markedUnreadMu sync.RWMutex

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
	Token        string                     `json:"token"`
	Username     string                     `json:"username"`
	UserID       int64                      `json:"user_id"`
	Blocked      []string                   `json:"blocked,omitempty"`
	Pinned       map[string][]string        `json:"pinned,omitempty"`
	MarkedUnread map[string]bool            `json:"marked_unread,omitempty"`
	ReadState    map[string]*ReadState      `json:"read_state,omitempty"`
	DMIssues     map[string]*ghDMIssueInfo  `json:"dm_issues,omitempty"`   // persistent DM cache
	GroupRepos   map[string]int             `json:"group_repos,omitempty"` // persistent group cache
	ThreadETags  map[string]string          `json:"thread_etags,omitempty"` // per-chat ETag cache (avoids re-fetch on restart)
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
		cache:          &ghCache{items: make(map[string]*ghCacheItem)},
		dialogs:        make(map[string]*ghDialog),
		messages:       make(map[string][]*Message),
		threadETags:    make(map[string]string),
		activeThreads:  make(map[string]time.Time),
		dmIssues:       make(map[string]*ghDMIssueInfo),
		groupRepos:     make(map[string]int),
		blocked:        make(map[string]bool),
		pinned:         make(map[string]map[string]bool),
		markedUnread:   make(map[string]bool),
		readState:      make(map[string]*ReadState),
		seenCommentIDs: make([]string, ghSeenIDsCapacity),
		seenCommentSet: make(map[string]bool, ghSeenIDsCapacity),
		threadLastMod:  make(map[string]string),
		sessionPath:    sessionPath,
		ctx:            ctx,
		cancel:         cancel,
	}
}

// ════════════════════════════════════════════════════════════════════════════════
// Core Interface: Identity
// ════════════════════════════════════════════════════════════════════════════════

func (g *GitHubCore) Name() string { return ghPlatform }

func (g *GitHubCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapTopics, CapThreads, CapReactions,
		CapSearch, CapAdmin, CapFolders, CapFileTransfer, CapBase64Image, CapBlocking,
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
	// Stop active chat fast poll goroutine first
	g.activeChatMu.Lock()
	if g.activeChatCancel != nil {
		g.activeChatCancel()
		g.activeChatCancel = nil
	}
	g.activeChatID = ""
	g.activeChatMu.Unlock()

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

	notifTicker := time.NewTicker(ghNotifPoll)
	recentTicker := time.NewTicker(ghPollRecent)
	defer notifTicker.Stop()
	defer recentTicker.Stop()

	notifInterval := ghNotifPoll
	recentInterval := ghPollRecent

	for {
		select {
		case <-g.ctx.Done():
			return

		case <-notifTicker.C:
			// Budget-aware interval adjustment for notification polling
			newInterval := g.budgetAdjustedInterval(ghNotifPoll)
			if newInterval != notifInterval {
				notifInterval = newInterval
				notifTicker.Reset(notifInterval)
			}
			g.pollNotifications()

		case <-recentTicker.C:
			// Poll recently active chats (ones with activity in the last 5 minutes)
			newInterval := g.budgetAdjustedInterval(ghPollRecent)
			if newInterval != recentInterval {
				recentInterval = newInterval
				recentTicker.Reset(recentInterval)
			}
			g.pollRecentChats()
		}
	}
}

// budgetAdjustedInterval returns the polling interval adjusted for rate limit budget.
// Even though 304s are free, 200 responses (new data) cost budget. When budget is low,
// we slow down all polling to avoid exhausting the limit.
func (g *GitHubCore) budgetAdjustedInterval(base time.Duration) time.Duration {
	remaining := g.rl.getRemaining()
	switch {
	case remaining > 0 && remaining < ghBudgetCriticalThreshold:
		// Critical: <2% budget — slow everything to 120s
		if base < ghBudgetCriticalInterval {
			return ghBudgetCriticalInterval
		}
	case remaining > 0 && remaining < ghBudgetCautionThreshold:
		// Caution: <10% budget — slow everything to 30s
		if base < ghBudgetCautionInterval {
			return ghBudgetCautionInterval
		}
	}
	return base
}

// pollRecentChats polls issue comment endpoints for recently active conversations.
// These are chats that had activity in the last ghRecentWindow (5 min) but are NOT
// the actively viewed chat (that one has its own faster goroutine).
func (g *GitHubCore) pollRecentChats() {
	g.activeThreadsMu.RLock()
	now := time.Now()
	var toCheck []string
	for chatID, lastActive := range g.activeThreads {
		if now.Sub(lastActive) < ghRecentWindow {
			toCheck = append(toCheck, chatID)
		}
	}
	g.activeThreadsMu.RUnlock()

	// Don't poll the active chat here — it has its own fast goroutine
	g.activeChatMu.Lock()
	activeID := g.activeChatID
	g.activeChatMu.Unlock()

	for _, chatID := range toCheck {
		if chatID == activeID {
			continue
		}
		select {
		case <-g.ctx.Done():
			return
		default:
		}
		g.pollThreadForUpdates(chatID)
	}
}

// pollThreadForUpdates polls a single thread's comments endpoint with ETag.
// On 304: free, no action. On 200: parse new comments, fire UpdateNewMessage (with dedup).
func (g *GitHubCore) pollThreadForUpdates(chatID string) {
	owner, repo, numStr := g.parseChatOwnerRepo(chatID)
	if owner == "" || repo == "" {
		return
	}

	// For DM chats, numStr is empty — we need the issue number from the cache
	if strings.HasPrefix(chatID, "dm:") {
		peerUser := strings.TrimPrefix(chatID, "dm:")
		g.dmIssuesMu.RLock()
		info, ok := g.dmIssues[peerUser]
		g.dmIssuesMu.RUnlock()
		if !ok {
			return
		}
		owner = info.RepoOwner
		repo = info.RepoName
		numStr = strconv.Itoa(info.IssueNum)
	} else if strings.HasPrefix(chatID, "issue:") {
		// parseIssueChat returns the right parts
		owner, repo, numStr = g.parseIssueChat(chatID)
	} else if strings.HasPrefix(chatID, "repo:") {
		// For repo chats, poll the General issue
		g.groupReposMu.RLock()
		generalNum := g.groupRepos[owner+"/"+repo]
		g.groupReposMu.RUnlock()
		if generalNum == 0 {
			return
		}
		numStr = strconv.Itoa(generalNum)
	}

	if numStr == "" {
		return
	}

	path := ghRepoPath(owner, repo) + "/issues/" + numStr + "/comments"
	params := map[string]string{
		"per_page":  "10",
		"sort":      "created",
		"direction": "desc",
	}

	resp, err := g.apiGetConditional(path, params, chatID)
	if err != nil {
		return // 304 (errNotModified) or real error — either way, nothing to do
	}

	// 200 — new comments exist
	var comments []json.RawMessage
	if err := json.Unmarshal(resp, &comments); err != nil {
		return
	}

	for _, raw := range comments {
		msg := g.commentToMessage(chatID, raw)
		if msg.SenderID == g.username {
			continue // skip our own messages
		}
		if g.markCommentSeen(msg.ID) {
			continue // already delivered this comment
		}
		g.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  msg,
			Platform: ghPlatform,
		})
	}
}

// SetActiveChat sets the conversation currently viewed in the GUI.
// The active chat gets fast-polled at ghPollActiveFast (2-3s) with conditional requests.
// Pass empty string to stop fast polling (e.g., user navigated away from any chat).
func (g *GitHubCore) SetActiveChat(chatID string) {
	g.activeChatMu.Lock()
	defer g.activeChatMu.Unlock()

	// If same chat is already active, no-op
	if g.activeChatID == chatID {
		return
	}

	// Stop the old active chat poll goroutine
	if g.activeChatCancel != nil {
		g.activeChatCancel()
		g.activeChatCancel = nil
	}

	g.activeChatID = chatID

	// Track this chat as recently active
	if chatID != "" {
		g.activeThreadsMu.Lock()
		g.activeThreads[chatID] = time.Now()
		g.activeThreadsMu.Unlock()
	}

	// Start a new fast poll goroutine for the active chat
	if chatID != "" {
		ctx, cancel := context.WithCancel(g.ctx)
		g.activeChatCancel = cancel
		g.wg.Add(1)
		go g.pollActiveChatLoop(ctx, chatID)
	}
}

// pollActiveChatLoop fast-polls a single conversation at ghPollActiveFast (2-3s).
// Runs in its own goroutine, cancelled when SetActiveChat is called with a different chat.
func (g *GitHubCore) pollActiveChatLoop(ctx context.Context, chatID string) {
	defer g.wg.Done()

	// Poll immediately on open, then at interval
	g.pollThreadForUpdates(chatID)

	interval := ghPollActiveFast
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Budget protection applies even to the active chat
			newInterval := g.budgetAdjustedInterval(ghPollActiveFast)
			if newInterval != interval {
				interval = newInterval
				ticker.Reset(interval)
			} else if interval != ghPollActiveFast {
				// Budget recovered — resume fast polling
				interval = ghPollActiveFast
				ticker.Reset(interval)
			}

			g.pollThreadForUpdates(chatID)

			// Update last-active time so pollRecentChats keeps it warm after we leave
			g.activeThreadsMu.Lock()
			g.activeThreads[chatID] = time.Now()
			g.activeThreadsMu.Unlock()
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

	// Track this chat as recently active (for tiered polling)
	g.activeThreadsMu.Lock()
	g.activeThreads[chatID] = time.Now()
	g.activeThreadsMu.Unlock()

	// Fetch the latest comment if URL available
	if subjectURL != "" {
		data, err := g.apiGetRaw(subjectURL)
		if err == nil {
			msg := g.commentToMessage(chatID, data)
			if msg.SenderID != g.username && !g.markCommentSeen(msg.ID) {
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

// getRemaining returns the current X-RateLimit-Remaining value.
// Returns -1 if we haven't received any rate limit headers yet (assume healthy).
func (rl *ghRateLimiter) getRemaining() int {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	if rl.remaining == 0 && rl.resetAt.IsZero() {
		return -1 // no data yet
	}
	return rl.remaining
}

// ════════════════════════════════════════════════════════════════════════════════
// Comment Deduplication
// ════════════════════════════════════════════════════════════════════════════════

// markCommentSeen checks if a comment ID was already seen. If not, adds it and returns false.
// If already seen, returns true. Uses a bounded ring buffer (ghSeenIDsCapacity) to cap memory.
// Thread-safe.
func (g *GitHubCore) markCommentSeen(commentID string) bool {
	g.seenCommentMu.Lock()
	defer g.seenCommentMu.Unlock()

	if g.seenCommentSet[commentID] {
		return true // already seen
	}

	// Evict the oldest entry from the ring buffer
	if old := g.seenCommentIDs[g.seenCommentIdx]; old != "" {
		delete(g.seenCommentSet, old)
	}

	// Insert the new entry
	g.seenCommentIDs[g.seenCommentIdx] = commentID
	g.seenCommentSet[commentID] = true
	g.seenCommentIdx = (g.seenCommentIdx + 1) % ghSeenIDsCapacity

	return false
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
	if sess.MarkedUnread != nil {
		g.markedUnread = sess.MarkedUnread
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
	// Restore per-thread ETags so we can resume conditional polling without re-fetching
	if sess.ThreadETags != nil {
		g.threadETags = sess.ThreadETags
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

	g.markedUnreadMu.RLock()
	if len(g.markedUnread) > 0 {
		sess.MarkedUnread = make(map[string]bool, len(g.markedUnread))
		for k, v := range g.markedUnread {
			sess.MarkedUnread[k] = v
		}
	}
	g.markedUnreadMu.RUnlock()

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

	// Persist per-thread ETags so we resume conditional polling on restart
	g.threadETagsMu.RLock()
	if len(g.threadETags) > 0 {
		sess.ThreadETags = make(map[string]string, len(g.threadETags))
		for k, v := range g.threadETags {
			sess.ThreadETags[k] = v
		}
	}
	g.threadETagsMu.RUnlock()

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





// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Utility (3)
// ══════════════════════════════════════════════════════════════════════════════


// CheckRateLimit checks the current rate limit status.
func (g *GitHubCore) CheckRateLimit() (json.RawMessage, error) {
	return g.apiGet("/rate_limit", nil)
}


// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Branches & Branch Protection (6)
// ══════════════════════════════════════════════════════════════════════════════




// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Git References / Tags (6)
// ══════════════════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Commits (3)
// ══════════════════════════════════════════════════════════════════════════════




// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Actions / Workflows (10)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Checks / Statuses (6)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Projects (7)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Deployments (4)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Repository Contents (5)
// ══════════════════════════════════════════════════════════════════════════════






// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Forks (1)
// ══════════════════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Collaborator Permissions (2)
// ══════════════════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Code Scanning / Security (4)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Pages (3)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Packages (4)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — SSH / GPG Keys (6)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Rulesets (5)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Autolinks (3)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Environments (4)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — New Methods (~800 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ── Actions — Runners ────────────────────────────────────────────────────────

// ── Actions — Runner Groups ─────────────────────────────────────────────────

// ── Actions — Hosted Runners ─────────────────────────────────────────────────

// ── Actions — Permissions ────────────────────────────────────────────────────

// ── Actions — Variables ──────────────────────────────────────────────────────

// ── Actions — Org Secrets ────────────────────────────────────────────────────

// ── Actions — Caches ─────────────────────────────────────────────────────────

// ── Actions — Workflow Runs Details ──────────────────────────────────────────

// ── Actions — Workflow Management ────────────────────────────────────────────

// ── Actions — Environment Secrets & Variables ────────────────────────────────

// ── Actions — OIDC ───────────────────────────────────────────────────────────

// ── GitHub Apps ───────────────────────────────────────────────────────────────

// ── Repos — Collaborators ────────────────────────────────────────────────────

func (g *GitHubCore) ListCollaborators(owner, repo string) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/collaborators", nil)
}


func (g *GitHubCore) AddCollaborator(owner, repo, username string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut(ghRepoPath(owner, repo) + "/collaborators/" + username, payload)
}

func (g *GitHubCore) RemoveCollaborator(owner, repo, username string) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/collaborators/" + username)
	return err
}

// ── Repos — Deploy Keys ─────────────────────────────────────────────────────

// ── Repos — Statistics ───────────────────────────────────────────────────────

// ── Repos — Traffic ──────────────────────────────────────────────────────────

// ── Repos — Community & README ───────────────────────────────────────────────




// ── Repos — Git Objects ──────────────────────────────────────────────────────

// ── Repos — Misc Missing ────────────────────────────────────────────────────









// ── Repos — Branch Protection Details ────────────────────────────────────────

// ── Repos — Pages Extras ────────────────────────────────────────────────────

// ── Repos — Webhook Extras ───────────────────────────────────────────────────

// ── Repos — Ruleset Extras ───────────────────────────────────────────────────

// ── Repos — Commits Extras ───────────────────────────────────────────────────


// ── Repos — Environment Deployment Policies ──────────────────────────────────

// ── Pull Requests — Missing ──────────────────────────────────────────────────

func (g *GitHubCore) CreatePRCommentReply(owner, repo string, prNumber, commentID int, payload map[string]any) (json.RawMessage, error) {
	return g.apiPost(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/comments/" + strconv.Itoa(commentID) + "/replies", payload)
}




func (g *GitHubCore) GetRequestedReviewers(owner, repo string, prNumber int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/requested_reviewers", nil)
}

func (g *GitHubCore) RemoveRequestedReviewers(owner, repo string, prNumber int, payload map[string]any) error {
	_, err := g.apiDelete(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/requested_reviewers")
	return err
}




func (g *GitHubCore) ListPRReviewComments(owner, repo string, prNumber, reviewID int) (json.RawMessage, error) {
	return g.apiGet(ghRepoPath(owner, repo) + "/pulls/" + strconv.Itoa(prNumber) + "/reviews/" + strconv.Itoa(reviewID) + "/comments", nil)
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









func (g *GitHubCore) ListAuthenticatedUserIssues() (json.RawMessage, error) {
	return g.apiGet("/issues", nil)
}

func (g *GitHubCore) ListOrgIssues(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/issues", nil)
}


// ── Codespaces ───────────────────────────────────────────────────────────────

// ── Copilot ──────────────────────────────────────────────────────────────────

// ── Migrations ───────────────────────────────────────────────────────────────

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

// ── Code Scanning — Extended ─────────────────────────────────────────────────

// ── Dependabot — Extended ────────────────────────────────────────────────────

// ── Secret Scanning — Extended ───────────────────────────────────────────────

// ── Organizations — Webhooks ─────────────────────────────────────────────────

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

// ── Organizations — PAT Management ───────────────────────────────────────────

// ── Organizations — Security Managers ────────────────────────────────────────

// ── Organizations — Public Members ───────────────────────────────────────────

func (g *GitHubCore) ListPublicMembers(org string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/public_members", nil)
}




// ── Teams — Extended ─────────────────────────────────────────────────────────

func (g *GitHubCore) ListTeamInvitations(org, teamSlug string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams/" + teamSlug + "/invitations", nil)
}

func (g *GitHubCore) ListTeamRepos(org, teamSlug string) (json.RawMessage, error) {
	return g.apiGet("/orgs/" + org + "/teams/" + teamSlug + "/repos", nil)
}


func (g *GitHubCore) AddTeamRepo(org, teamSlug, owner, repo string, payload map[string]any) (json.RawMessage, error) {
	return g.apiPut("/orgs/" + org + "/teams/" + teamSlug + "/repos/" + owner + "/" + repo, payload)
}

func (g *GitHubCore) RemoveTeamRepo(org, teamSlug, owner, repo string) error {
	_, err := g.apiDelete("/orgs/" + org + "/teams/" + teamSlug + "/repos/" + owner + "/" + repo)
	return err
}


func (g *GitHubCore) ListUserTeams() (json.RawMessage, error) {
	return g.apiGet("/user/teams", nil)
}

// ── Users — Extended ─────────────────────────────────────────────────────────



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

// ── Gists — Extended ─────────────────────────────────────────────────────────








// ── Packages — Extended ─────────────────────────────────────────────────────

// ── Dependency Graph ─────────────────────────────────────────────────────────

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

// ── Licenses ─────────────────────────────────────────────────────────────────

// ── Meta / Server Info ───────────────────────────────────────────────────────

// ── Gitignore Templates ──────────────────────────────────────────────────────

// ── Codes of Conduct ─────────────────────────────────────────────────────────

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

// ── OIDC (Org-level) ─────────────────────────────────────────────────────────

func (g *GitHubCore) MuteChat(chatID string, muted bool) error {
	if !g.authed {
		return ErrAuth
	}

	switch {
	case strings.HasPrefix(chatID, "repo:"):
		owner, repo, err := g.parseRepoChat(chatID)
		if err != nil {
			return err
		}
		if muted {
			_, err = g.apiPut(ghRepoPath(owner, repo)+"/subscription", map[string]any{"ignored": true})
		} else {
			_, err = g.apiPut(ghRepoPath(owner, repo)+"/subscription", map[string]any{"subscribed": true, "ignored": false})
		}
		return err

	case strings.HasPrefix(chatID, "issue:") || strings.HasPrefix(chatID, "dm:"):
		// For issue/DM chats, use the notification thread subscription.
		// We need to find the notification thread ID. Use local mute state as fallback.
		g.dialogsMu.Lock()
		if d, ok := g.dialogs[chatID]; ok {
			d.IsMuted = muted
		}
		g.dialogsMu.Unlock()
		return nil

	default:
		return fmt.Errorf("%w: unknown chat ID format: %s", ErrInvalidInput, chatID)
	}
}

func (g *GitHubCore) ArchiveChat(chatID string, archived bool) error {
	if !g.authed {
		return ErrAuth
	}

	switch {
	case strings.HasPrefix(chatID, "repo:"):
		owner, repo, err := g.parseRepoChat(chatID)
		if err != nil {
			return err
		}
		_, err = g.apiPatch(ghRepoPath(owner, repo), map[string]any{"archived": archived})
		return err

	case strings.HasPrefix(chatID, "issue:"):
		owner, repo, num := g.parseIssueChat(chatID)
		state := "open"
		if archived {
			state = "closed"
		}
		_, err := g.apiPatch(ghRepoPath(owner, repo)+"/issues/"+num, map[string]any{"state": state})
		return err

	case strings.HasPrefix(chatID, "dm:"):
		peerUser := strings.TrimPrefix(chatID, "dm:")
		g.dmIssuesMu.RLock()
		info, ok := g.dmIssues[peerUser]
		g.dmIssuesMu.RUnlock()
		if !ok {
			return fmt.Errorf("%w: no DM issue found for %s", ErrNotFound, peerUser)
		}
		state := "open"
		if archived {
			state = "closed"
		}
		_, err := g.apiPatch(ghRepoPath(info.RepoOwner, info.RepoName)+"/issues/"+strconv.Itoa(info.IssueNum), map[string]any{"state": state})
		return err

	default:
		return fmt.Errorf("%w: unknown chat ID format: %s", ErrInvalidInput, chatID)
	}
}

func (g *GitHubCore) MarkUnread(chatID string, unread bool) error {
	if !g.authed {
		return ErrAuth
	}

	g.markedUnreadMu.Lock()
	if unread {
		g.markedUnread[chatID] = true
	} else {
		delete(g.markedUnread, chatID)
	}
	g.markedUnreadMu.Unlock()

	g.saveSession()
	return nil
}

func (g *GitHubCore) UnpinAllMessages(chatID string) error {
	if !g.authed {
		return ErrAuth
	}

	g.pinnedMu.Lock()
	delete(g.pinned, chatID)
	g.pinnedMu.Unlock()

	g.saveSession()
	return nil
}

func (g *GitHubCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, ghPlatform)
}

func (g *GitHubCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	if !g.authed {
		return nil, ErrAuth
	}
	text := fmt.Sprintf("\U0001f4cd [Location](https://www.google.com/maps?q=%f,%f)", lat, lon)
	return g.SendMessage(chatID, OutgoingMessage{Text: text})
}
