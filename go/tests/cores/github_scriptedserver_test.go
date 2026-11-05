package tests

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"

	. "uniclient/cores"
	"uniclient/utils"
)

type ghServedReq struct {
	Method string
	Path   string
	Query  string
	Auth   string
	Accept string
	APIVer string
	Body   string
}

type ghScripted struct {
	mu   sync.Mutex
	reqs []ghServedReq
	srv  *httptest.Server
}

func newGhScripted(t *testing.T, h func(w http.ResponseWriter, r *http.Request, body []byte)) *ghScripted {
	t.Helper()
	s := &ghScripted{}
	s.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
		r.Body.Close()
		s.mu.Lock()
		s.reqs = append(s.reqs, ghServedReq{
			Method: r.Method,
			Path:   r.URL.Path,
			Query:  r.URL.RawQuery,
			Auth:   r.Header.Get("Authorization"),
			Accept: r.Header.Get("Accept"),
			APIVer: r.Header.Get("X-GitHub-Api-Version"),
			Body:   string(body),
		})
		s.mu.Unlock()
		h(w, r, body)
	}))
	t.Cleanup(s.srv.Close)
	return s
}

func (s *ghScripted) served() []ghServedReq {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]ghServedReq(nil), s.reqs...)
}

func (s *ghScripted) cfg(token string) AuthConfig {
	return AuthConfig{BotToken: token, Extra: map[string]string{"api_base": s.srv.URL}}
}

func (s *ghScripted) authed(t *testing.T, token string) *GitHubCore {
	t.Helper()
	g := NewGitHubCore(nil)
	if err := g.Authenticate(s.cfg(token)); err != nil {
		t.Fatalf("Authenticate: %v", err)
	}
	t.Cleanup(func() { g.Close() })
	return g
}

func ghOctoHandler(t *testing.T) func(w http.ResponseWriter, r *http.Request, body []byte) {
	return func(w http.ResponseWriter, r *http.Request, _ []byte) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/user", "/users/octocat":
			io.WriteString(w, `{"login":"octocat","id":5823,"name":"Octo Cat","type":"User"}`)
		case "/repos/octocat/octocat":
			io.WriteString(w, `{"full_name":"octocat/octocat"}`)
		case "/notifications":
			io.WriteString(w, `[]`)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(404)
		}
	}
}

func newGhOctoCore(t *testing.T) *GitHubCore {
	t.Helper()
	s := newGhScripted(t, ghOctoHandler(t))
	return s.authed(t, "ghp_octo")
}

func TestGitHubAuthenticateWhoamiOnTheWire(t *testing.T) {
	s := newGhScripted(t, ghOctoHandler(t))
	g := s.authed(t, "ghp_wire123")

	reqs := s.served()
	if len(reqs) == 0 || reqs[0].Method != "GET" || reqs[0].Path != "/user" {
		t.Fatalf("first request = %+v, want GET /user", reqs[0])
	}
	if reqs[0].Auth != "Bearer ghp_wire123" {
		t.Errorf("Authorization = %q, want the configured token", reqs[0].Auth)
	}
	if reqs[0].Accept != "application/vnd.github+json" {
		t.Errorf("Accept = %q", reqs[0].Accept)
	}
	if reqs[0].APIVer != "2022-11-28" {
		t.Errorf("X-GitHub-Api-Version = %q", reqs[0].APIVer)
	}
	for _, r := range reqs {
		if r.Path == "/user/repos" {
			t.Errorf("profile repo existed, but a bootstrap POST was sent: %+v", r)
		}
	}

	self, err := g.GetProfile("")
	if err != nil {
		t.Fatalf("GetProfile(self): %v", err)
	}
	if self.Username != "octocat" || self.DisplayName != "Octo Cat" || self.IsBot {
		t.Errorf("whoami projection = %+v", self)
	}
	reqs = s.served()
	last := reqs[len(reqs)-1]
	if last.Method != "GET" || last.Path != "/users/octocat" {
		t.Errorf("GetProfile request = %s %s, want GET /users/octocat (username-driven)", last.Method, last.Path)
	}
}

func TestGitHubProfileRepoBootstrapOnTheWire(t *testing.T) {
	s := newGhScripted(t, func(w http.ResponseWriter, r *http.Request, _ []byte) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/user":
			io.WriteString(w, `{"login":"octocat","id":5823,"type":"User"}`)
		case "/repos/octocat/octocat":
			w.WriteHeader(404)
			io.WriteString(w, `{"message":"Not Found"}`)
		case "/user/repos":
			w.WriteHeader(201)
			io.WriteString(w, `{"full_name":"octocat/octocat"}`)
		case "/notifications":
			io.WriteString(w, `[]`)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(404)
		}
	})
	s.authed(t, "ghp_boot")

	reqs := s.served()
	var post *ghServedReq
	for i := range reqs {
		if reqs[i].Path == "/user/repos" {
			post = &reqs[i]
		}
	}
	if post == nil {
		t.Fatal("no POST /user/repos after the 404 — profile repo never bootstrapped")
	}
	if post.Method != "POST" {
		t.Errorf("/user/repos method = %s", post.Method)
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(post.Body), &payload); err != nil {
		t.Fatalf("bootstrap body not JSON: %q", post.Body)
	}
	want := map[string]any{
		"name":        "octocat",
		"description": "My GitHub profile",
		"has_issues":  true,
		"auto_init":   true,
	}
	if len(payload) != len(want) {
		t.Errorf("bootstrap body = %v, want exactly %v", payload, want)
	}
	for k, v := range want {
		if payload[k] != v {
			t.Errorf("bootstrap body[%q] = %v, want %v", k, payload[k], v)
		}
	}
}

func TestGitHubSessionResumeOnTheWire(t *testing.T) {
	dir := t.TempDir()
	vault, err := utils.CreateVault(filepath.Join(dir, "resume.vault"), "pw")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	defer vault.Close()
	store := utils.NewSessionStore(vault, "gh-resume")

	s := newGhScripted(t, ghOctoHandler(t))

	first := NewGitHubCore(store)
	if err := first.Authenticate(s.cfg("ghp_resume")); err != nil {
		t.Fatalf("initial Authenticate: %v", err)
	}
	if err := first.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	second := NewGitHubCore(store)
	if err := second.Authenticate(AuthConfig{Extra: map[string]string{"api_base": s.srv.URL}}); err != nil {
		t.Fatalf("resume Authenticate without a token: %v", err)
	}
	t.Cleanup(func() { second.Close() })

	reqs := s.served()
	var userReqs []ghServedReq
	for _, r := range reqs {
		if r.Path == "/user" {
			userReqs = append(userReqs, r)
		}
		if r.Path == "/user/repos" {
			t.Errorf("profile repo existed, but a bootstrap POST was sent during resume")
		}
	}
	if len(userReqs) != 2 {
		t.Fatalf("GET /user seen %d times, want 2 (initial + resume): %+v", len(userReqs), reqs)
	}
	if userReqs[0].Auth != "Bearer ghp_resume" || userReqs[1].Auth != "Bearer ghp_resume" {
		t.Errorf("saved token not reused on the wire: %q then %q", userReqs[0].Auth, userReqs[1].Auth)
	}
}

func TestGitHubBadTokenRejectedOnTheWire(t *testing.T) {
	s := newGhScripted(t, func(w http.ResponseWriter, r *http.Request, _ []byte) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/user" {
			w.WriteHeader(401)
			io.WriteString(w, `{"message":"Bad credentials"}`)
			return
		}
		w.WriteHeader(404)
	})
	g := NewGitHubCore(nil)
	err := g.Authenticate(s.cfg("ghp_bad"))
	if err == nil {
		t.Fatal("invalid token accepted")
	}
	if !errors.Is(err, ErrAuth) {
		t.Errorf("Authenticate error = %v, want ErrAuth", err)
	}
	if _, derr := g.GetDialogs(PaginationOpts{}); !errors.Is(derr, ErrAuth) {
		t.Errorf("GetDialogs after rejected auth = %v, want ErrAuth", derr)
	}
	if reqs := s.served(); len(reqs) != 1 {
		t.Errorf("requests = %d, want exactly 1 (401 is terminal, no retry): %+v", len(reqs), reqs)
	}
}

func TestGitHub429RetryOnTheWire(t *testing.T) {
	var hits atomic.Int32
	s := newGhScripted(t, func(w http.ResponseWriter, r *http.Request, _ []byte) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/user":
			if hits.Add(1) == 1 {
				w.Header().Set("Retry-After", "0")
				w.WriteHeader(429)
				io.WriteString(w, `{"message":"API rate limit exceeded"}`)
				return
			}
			io.WriteString(w, `{"login":"octocat","id":5823,"type":"User"}`)
		case "/repos/octocat/octocat":
			io.WriteString(w, `{"full_name":"octocat/octocat"}`)
		case "/notifications":
			io.WriteString(w, `[]`)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(404)
		}
	})
	s.authed(t, "ghp_429")

	var userReqs []ghServedReq
	for _, r := range s.served() {
		if r.Path == "/user" {
			userReqs = append(userReqs, r)
		}
	}
	if len(userReqs) != 2 {
		t.Fatalf("GET /user seen %d times, want 2 (429 then retried): %+v", len(userReqs), s.served())
	}
	if userReqs[1].Auth != "Bearer ghp_429" {
		t.Errorf("retry Authorization = %q", userReqs[1].Auth)
	}
}
