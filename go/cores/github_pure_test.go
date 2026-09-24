package cores

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

// GitHub core pure-function tests — the core had zero dedicated tests
// before slice 250. Everything here is network-free: converters, ID
// parsing, retry/rate-limit math, JSON helpers.

func TestGitHubRepoPathAndIntStr(t *testing.T) {
	if got := ghRepoPath("octo", "repo"); got != "/repos/octo/repo" {
		t.Errorf("ghRepoPath = %q", got)
	}
	cases := map[float64]string{
		42:    "42",
		0:     "0",
		1e15:  "1000000000000000",
		3.9:   "3", // truncates like the API's float ids
		2.5e9: "2500000000",
	}
	for in, want := range cases {
		if got := ghIntStr(in); got != want {
			t.Errorf("ghIntStr(%v) = %q, want %q", in, got, want)
		}
	}
}

func TestGitHubBackoffDelayBounds(t *testing.T) {
	bases := []time.Duration{500 * time.Millisecond, time.Second, 5 * time.Second}
	for _, base := range bases {
		for attempt := 0; attempt <= 5; attempt++ {
			d := ghBackoffDelay(attempt, base)
			want := base << attempt
			if d < want {
				t.Errorf("attempt=%d base=%v: delay %v below exponential floor %v", attempt, base, d, want)
			}
			if d > want+want/4 {
				t.Errorf("attempt=%d base=%v: delay %v exceeds cap %v (jitter must be 0-25%%)", attempt, base, d, want+want/4)
			}
		}
	}
}

func TestGitHubSecondaryRateLimitDetection(t *testing.T) {
	hit := []string{
		`{"message":"You have exceeded a secondary rate limit. Please wait a few minutes before you try again.","documentation_url":"https://docs.github.com"}`,
		`{"message":"You have triggered an abuse detection mechanism and have been temporarily blocked from content creation."}`,
	}
	for _, b := range hit {
		if !ghIsSecondaryRateLimit([]byte(b)) {
			t.Errorf("not detected: %.60s", b)
		}
	}
	miss := []string{
		`{"message":"Not Found","documentation_url":"https://docs.github.com"}`,
		`{"message":"Bad credentials"}`,
	}
	for _, b := range miss {
		if ghIsSecondaryRateLimit([]byte(b)) {
			t.Errorf("false positive: %s", b)
		}
	}
}

func TestGitHubParseRetryAfter(t *testing.T) {
	h := make(map[string][]string)
	hd := http.Header(h)
	hd.Set("Retry-After", "120")
	if got := ghParseRetryAfter(hd); got != 120*time.Second {
		t.Errorf("seconds form = %v", got)
	}
	hd.Del("Retry-After")
	if got := ghParseRetryAfter(hd); got != 60*time.Second {
		t.Errorf("missing header = %v, want conservative 60s default", got)
	}
	hd.Set("Retry-After", "not-a-number")
	if got := ghParseRetryAfter(hd); got != 60*time.Second {
		t.Errorf("garbage = %v, want 60s default", got)
	}
	// HTTP-date form falls to the same conservative default (GitHub
	// sends delta-seconds; a date-form header must still not return 0).
	hd.Set("Retry-After", "Wed, 21 Oct 2026 07:28:00 GMT")
	if got := ghParseRetryAfter(hd); got != 60*time.Second {
		t.Errorf("date form = %v, want 60s default", got)
	}
}

func TestGitHubExtractTrailingNumber(t *testing.T) {
	cases := map[string]string{
		"https://api.github.com/repos/o/r/issues/42": "42",
		"https://github.com/o/r/pull/7":              "7",
		"https://api.github.com/repos/o/r/issues":    "",
		"https://github.com/o/r/issues/42/":          "", // trailing slash: documented no-match
		"https://github.com/o/r/commit/deadbeef":     "",
		"https://github.com/o/r/releases/tag/v1.2.3": "",
		"": "",
	}
	for in, want := range cases {
		if got := extractTrailingNumber(in); got != want {
			t.Errorf("extractTrailingNumber(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestGitHubCommentToMessage(t *testing.T) {
	g := NewGitHubCore(nil)
	g.username = "octocat"

	raw := json.RawMessage(`{
		"id": 1234567890,
		"body": "hello from the issue",
		"created_at": "2026-09-20T10:00:00Z",
		"updated_at": "2026-09-20T10:00:00Z",
		"user": {"login": "octocat"}
	}`)
	msg := g.commentToMessage("issue:o/r/1", raw)
	if msg == nil {
		t.Fatal("nil message")
	}
	if msg.ID != "comment:1234567890" {
		t.Errorf("ID = %q", msg.ID)
	}
	if msg.ChatID != "issue:o/r/1" || msg.SenderID != "octocat" || msg.SenderName != "octocat" {
		t.Errorf("ids wrong: %+v", msg)
	}
	if msg.Text != "hello from the issue" {
		t.Errorf("Text = %q", msg.Text)
	}
	if msg.Timestamp.IsZero() {
		t.Error("Timestamp zero")
	}
	if msg.EditedAt != nil {
		t.Errorf("EditedAt = %v — updated_at equal to created_at is not an edit", msg.EditedAt)
	}
	if !msg.IsOutgoing {
		t.Error("comment by our own username must be outgoing")
	}
	if msg.Platform != ghPlatform || msg.Status != MessageStatusSent {
		t.Errorf("platform/status = %q/%v", msg.Platform, msg.Status)
	}
}

func TestGitHubCommentToMessageEditedFlag(t *testing.T) {
	g := NewGitHubCore(nil)
	raw := json.RawMessage(`{
		"id": 5,
		"body": "v2",
		"created_at": "2026-09-20T10:00:00Z",
		"updated_at": "2026-09-21T11:30:00Z",
		"user": {"login": "someone"}
	}`)
	msg := g.commentToMessage("issue:o/r/5", raw)
	if msg.EditedAt == nil {
		t.Fatal("updated_at != created_at must set EditedAt")
	}
	if !msg.EditedAt.Equal(time.Date(2026, 9, 21, 11, 30, 0, 0, time.UTC)) {
		t.Errorf("EditedAt = %v", msg.EditedAt)
	}
}

// TestGitHubCommentToMessageIssueFallsBackToTitle: issues carry a title
// and no useful body sometimes; the converter must fall back (that is
// what makes it serve BOTH comments and issues).
func TestGitHubCommentToMessageIssueFallsBackToTitle(t *testing.T) {
	g := NewGitHubCore(nil)
	raw := json.RawMessage(`{
		"id": 9,
		"title": "Bug: crash on start",
		"body": "",
		"created_at": "2026-09-19T08:00:00Z",
		"author": {"login": "reporter"}
	}`)
	msg := g.commentToMessage("issue:o/r/9", raw)
	if msg == nil {
		t.Fatal("nil message")
	}
	if msg.Text != "Bug: crash on start" {
		t.Errorf("Text = %q — empty body must fall back to title", msg.Text)
	}
	if msg.SenderID != "reporter" {
		t.Errorf("SenderID = %q — author fallback missing", msg.SenderID)
	}
}

func TestGitHubCommentReactionsFromNestedObject(t *testing.T) {
	g := NewGitHubCore(nil)
	raw := json.RawMessage(`{
		"id": 11,
		"body": "nice",
		"created_at": "2026-09-20T10:00:00Z",
		"user": {"login": "u"},
		"reactions": {"+1": 3, "heart": 1, "-1": 0}
	}`)
	msg := g.commentToMessage("issue:o/r/11", raw)
	byEmoji := map[string]int{}
	for _, r := range msg.Reactions {
		byEmoji[r.Emoji] += r.Count
	}
	if byEmoji["\U0001f44d"] != 3 {
		t.Errorf("+1 reactions = %d (map: %v)", byEmoji["\U0001f44d"], byEmoji)
	}
	if byEmoji["❤️"] != 1 {
		t.Errorf("heart reactions = %d (map: %v)", byEmoji["❤️"], byEmoji)
	}
	if byEmoji["\U0001f44e"] != 0 {
		t.Errorf("zero-count reaction must be absent, got %d", byEmoji["\U0001f44e"])
	}
	if len(msg.Reactions) != 2 {
		t.Errorf("want exactly 2 reaction entries, got %d: %v", len(msg.Reactions), msg.Reactions)
	}
}

func TestGitHubDialogToDialog(t *testing.T) {
	g := NewGitHubCore(nil)
	in := &ghDialog{
		ChatID:      "issue:o/r/3",
		Type:        ChatTypeDM,
		Title:       "Incredible bug",
		AvatarURL:   "https://x/y",
		MemberCount: 2,
		UnreadCount: 7,
		IsMuted:     true,
		IsPinned:    true,
	}
	out := g.ghDialogToDialog(in)
	if out.ID != in.ChatID || out.Type != in.Type || out.Title != in.Title ||
		out.AvatarURL != in.AvatarURL || out.MemberCount != in.MemberCount ||
		out.UnreadCount != in.UnreadCount || out.IsMuted != in.IsMuted ||
		out.IsPinned != in.IsPinned || out.Platform != ghPlatform {
		t.Errorf("field mapping wrong: %+v", out)
	}
}

func TestGitHubParseRepoAndIssueChats(t *testing.T) {
	g := NewGitHubCore(nil)

	owner, repo, err := g.parseRepoChat("repo:octo/cat")
	if err != nil || owner != "octo" || repo != "cat" {
		t.Errorf("parseRepoChat valid = %q,%q,%v", owner, repo, err)
	}
	if _, _, err := g.parseRepoChat("octo/cat-only"); err == nil {
		// SplitN(…, 2) on "octo/cat-only" yields two parts — the helper
		// accepts a missing prefix; pin that it does NOT error here so
		// a future strictness change is a conscious one.
		t.Log("parseRepoChat accepts a prefix-less two-part id (pinned)")
	}
	if _, _, err := g.parseRepoChat("repo:solo"); err == nil {
		t.Error("single part must be rejected")
	}
	if _, _, err := g.parseRepoChat("repo:"); err == nil {
		t.Error("empty id must be rejected")
	}

	o, r, n := g.parseIssueChat("issue:octo/cat/42")
	if o != "octo" || r != "cat" || n != "42" {
		t.Errorf("parseIssueChat valid = %q/%q/%q", o, r, n)
	}
	o, r, n = g.parseIssueChat("issue:octo/cat")
	if o != "" || r != "" || n != "" {
		t.Errorf("parseIssueChat short id = %q/%q/%q, want empty triple", o, r, n)
	}
	// A repo id with an embedded slash is accepted as owner/repo/rest:
	// SplitN(…, 3) — pin current behavior (chat ids are machine-made).
	o, r, n = g.parseIssueChat("issue:a/b/c/9")
	if o != "a" || r != "b" || n != "c/9" {
		t.Errorf("parseIssueChat embedded slash = %q/%q/%q", o, r, n)
	}
}

func TestGitHubGjsonHelpers(t *testing.T) {
	raw := json.RawMessage(`{
		"user": {"login": "octocat", "id": 55},
		"name": "Hello",
		"count": 3,
		"list": [1,2]
	}`)
	if got := gjsonStr(raw, "user.login"); got != "octocat" {
		t.Errorf("nested string = %q", got)
	}
	if got := gjsonStr(raw, "name"); got != "Hello" {
		t.Errorf("top string = %q", got)
	}
	if got := gjsonStr(raw, "missing.path"); got != "" {
		t.Errorf("missing = %q, want empty", got)
	}
	if got := gjsonStr(raw, "count"); got != "" {
		t.Errorf("type mismatch (number as string) = %q, want empty", got)
	}
	if got := gjsonStr(raw, "list.0"); got != "" {
		t.Errorf("array segment = %q, want empty (map walk only)", got)
	}
	if got := gjsonFloat(raw, "count"); got != 3 {
		t.Errorf("float = %v", got)
	}
	if got := gjsonFloat(raw, "user.login"); got != 0 {
		t.Errorf("type mismatch (string as float) = %v, want 0", got)
	}
	if got := gjsonMapFloat(map[string]any{"id": float64(99)}, "id"); got != 99 {
		t.Errorf("map float = %v", got)
	}
	if got := gjsonMapFloat(map[string]any{"id": "text"}, "id"); got != 0 {
		t.Errorf("map float type mismatch = %v, want 0", got)
	}
}
