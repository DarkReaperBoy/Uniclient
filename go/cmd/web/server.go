package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strconv"
	"sync"

	"github.com/coder/websocket"
	"rsc.io/qr"

	"uniclient/engine"
)

// server hosts the local HTTP + WebSocket API and the embedded web UI.
//
// Security model: the listener binds 127.0.0.1 only, so the API is reachable
// from the local machine alone. There is no auth token because there is no
// remote surface.
type server struct {
	eng *engine.Engine
	ln  net.Listener
	hub *wsHub
}

func newServer(eng *engine.Engine, ln net.Listener) *server {
	hub := newHub()

	// The engine emits JSON EngineEvent envelopes (auth states, connection
	// states, new messages, chat updates) — forward them verbatim to every
	// connected browser. We hook the engine directly (not the bridge's proto
	// pump): this host has no other FFI consumer, and the browser speaks JSON.
	eng.SetEventCallback(hub.broadcast)

	return &server{eng: eng, ln: ln, hub: hub}
}

// routes builds the HTTP mux: /api/* JSON API, /ws events, / embedded UI.
func (s *server) routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", s.handleHealth)

	// Accounts.
	mux.HandleFunc("GET /api/accounts", s.handleAccountsList)
	mux.HandleFunc("POST /api/accounts", s.handleAccountAdd)
	mux.HandleFunc("DELETE /api/accounts/{id}", s.handleAccountRemove)
	mux.HandleFunc("POST /api/accounts/{id}/connect", s.handleAccountConnect)
	mux.HandleFunc("POST /api/accounts/{id}/disconnect", s.handleAccountDisconnect)
	mux.HandleFunc("GET /api/accounts/{id}/profile", s.handleAccountProfile)

	// Interactive auth flow (works for every platform the engine knows).
	mux.HandleFunc("GET /api/accounts/{id}/auth", s.handleAuthState)
	mux.HandleFunc("POST /api/accounts/{id}/auth/start", s.handleAuthStart)
	mux.HandleFunc("POST /api/accounts/{id}/auth/input", s.handleAuthInput)
	mux.HandleFunc("POST /api/accounts/{id}/auth/back", s.handleAuthBack)
	mux.HandleFunc("POST /api/accounts/{id}/auth/cancel", s.handleAuthCancel)

	// Chats (cache reads; the engine keeps them warm in the background).
	mux.HandleFunc("GET /api/chats", s.handleChatsUnified)
	mux.HandleFunc("GET /api/accounts/{id}/chats", s.handleChatsForAccount)

	// Messages (chat IDs can contain slashes and '#', so they travel in the
	// query string or JSON body — never as raw path segments).
	mux.HandleFunc("GET /api/messages", s.handleMessages)
	mux.HandleFunc("POST /api/messages/live", s.handleMessagesLive)
	mux.HandleFunc("POST /api/messages/send", s.handleMessageSend)
	mux.HandleFunc("POST /api/chats/read", s.handleChatRead)
	mux.HandleFunc("POST /api/chats/join", s.handleChatJoin)

	// Events.
	mux.HandleFunc("GET /ws", s.handleWS)

	// QR rendering for login flows (Telegram QR login etc.)
	mux.HandleFunc("POST /api/qr", s.handleQR)

	// Embedded UI.
	mux.HandleFunc("/", handleStatic)

	return mux
}

// ── Handlers ──────────────────────────────────────────────────────────────

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "app": "uniclient-web"})
}

func (s *server) handleAccountsList(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.eng.ListAccounts())
}

func (s *server) handleAccountAdd(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Platform string `json:"platform"`
		TestMode bool   `json:"test_mode"`
	}
	if err := readJSON(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Platform == "" {
		writeErr(w, http.StatusBadRequest, "platform is required")
		return
	}
	id, err := s.eng.AddAccount(req.Platform, req.TestMode)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"account_id": id})
}

func (s *server) handleAccountRemove(w http.ResponseWriter, r *http.Request) {
	if err := s.eng.RemoveAccount(r.PathValue("id")); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// handleAccountConnect reconnects an existing account. Authentication is
// network I/O, so it runs in the background — the UI follows progress via
// conn_state events on the WebSocket.
func (s *server) handleAccountConnect(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	go func() {
		_ = s.eng.ConnectAccount(id)
	}()
	writeJSON(w, http.StatusAccepted, map[string]bool{"ok": true})
}

func (s *server) handleAccountDisconnect(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	go func() {
		_ = s.eng.DisconnectAccount(id)
	}()
	writeJSON(w, http.StatusAccepted, map[string]bool{"ok": true})
}

func (s *server) handleAccountProfile(w http.ResponseWriter, r *http.Request) {
	core := s.eng.GetAccountCore(r.PathValue("id"))
	if core == nil {
		writeErr(w, http.StatusConflict, "account not connected")
		return
	}
	profile, err := core.GetProfile("")
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

func (s *server) handleAuthStart(w http.ResponseWriter, r *http.Request) {
	state, err := s.eng.StartAuth(r.PathValue("id"))
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, state)
}

// handleAuthState returns the live auth flow state (nil → null) so hosts can
// re-sync after async auth_state events (QR refreshes).
func (s *server) handleAuthState(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, engine.CurrentAuthState(r.PathValue("id")))
}

func (s *server) handleAuthInput(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Input string `json:"input"`
	}
	if err := readJSON(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	state, err := s.eng.SubmitAuthInput(r.PathValue("id"), req.Input)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, state)
}

func (s *server) handleAuthBack(w http.ResponseWriter, r *http.Request) {
	state, ok := s.eng.GoBackAuth(r.PathValue("id"))
	if !ok {
		writeErr(w, http.StatusConflict, "no earlier auth step")
		return
	}
	writeJSON(w, http.StatusOK, state)
}

func (s *server) handleAuthCancel(w http.ResponseWriter, r *http.Request) {
	s.eng.CancelAuth(r.PathValue("id"))
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *server) handleChatsUnified(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	chats, err := s.eng.GetUnifiedChatList(limit, offset)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, chats)
}

func (s *server) handleChatsForAccount(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	archived := boolParam(r, "archived")
	chats, err := s.eng.GetChatList(r.PathValue("id"), archived, limit, offset)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, chats)
}

func (s *server) handleMessages(w http.ResponseWriter, r *http.Request) {
	accountID, chatID := r.URL.Query().Get("account"), r.URL.Query().Get("chat")
	if accountID == "" || chatID == "" {
		writeErr(w, http.StatusBadRequest, "account and chat are required")
		return
	}
	limit, _ := pagination(r)
	beforeMs := int64Param(r, "before_ms")
	msgs, err := s.eng.GetMessages(accountID, chatID, beforeMs, 0, limit)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, msgs)
}

// handleChatJoin joins a channel/room by name (IRC #channel, Mumble channel).
func (s *server) handleChatJoin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AccountID string `json:"account_id"`
		Name      string `json:"name"`
	}
	if err := readJSON(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.AccountID == "" || req.Name == "" {
		writeErr(w, http.StatusBadRequest, "account_id and name are required")
		return
	}
	if err := s.eng.JoinChat(req.AccountID, req.Name); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// handleMessagesLive pulls a page of messages straight from the network and
// refreshes the cache — used when a chat is opened for the first time.
func (s *server) handleMessagesLive(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AccountID string `json:"account_id"`
		ChatID    string `json:"chat_id"`
		Limit     int    `json:"limit"`
	}
	if err := readJSON(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Limit <= 0 {
		req.Limit = 50
	}
	msgs, err := s.eng.FetchLiveMessages(req.AccountID, req.ChatID, req.Limit)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, msgs)
}

func (s *server) handleMessageSend(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AccountID string `json:"account_id"`
		ChatID    string `json:"chat_id"`
		Text      string `json:"text"`
		ReplyToID string `json:"reply_to_id"`
	}
	if err := readJSON(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.AccountID == "" || req.ChatID == "" || req.Text == "" {
		writeErr(w, http.StatusBadRequest, "account_id, chat_id and text are required")
		return
	}
	localID, err := s.eng.SendMessage(
		req.AccountID, req.ChatID, req.Text, req.ReplyToID,
		nil, false, 0, "", "", false, false, false, false,
	)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"local_id": localID})
}

func (s *server) handleChatRead(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AccountID string `json:"account_id"`
		ChatID    string `json:"chat_id"`
		UpToMsgID string `json:"up_to_msg_id"`
	}
	if err := readJSON(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := s.eng.MarkChatRead(req.AccountID, req.ChatID, req.UpToMsgID); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// handleQR renders a QR code PNG for login URLs (Telegram QR login).
func (s *server) handleQR(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Text string `json:"text"`
	}
	if err := readJSON(r, &req); err != nil || req.Text == "" {
		writeErr(w, http.StatusBadRequest, "text is required")
		return
	}
	code, err := qr.Encode(req.Text, qr.M)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "cannot encode: "+err.Error())
		return
	}
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "no-store")
	_ = writePNGWithMargin(w, code)
}

// ── WebSocket hub ─────────────────────────────────────────────────────────

type wsHub struct {
	mu    sync.Mutex
	conns map[chan []byte]struct{}
}

func newHub() *wsHub {
	return &wsHub{conns: make(map[chan []byte]struct{})}
}

// broadcast fans an engine event out to every connected browser.
func (h *wsHub) broadcast(data []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for ch := range h.conns {
		select {
		case ch <- data:
		default: // slow client — drop the event rather than block the engine
		}
	}
}

func (s *server) handleWS(w http.ResponseWriter, r *http.Request) {
	c, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}

	ch := make(chan []byte, 128)
	s.hub.mu.Lock()
	s.hub.conns[ch] = struct{}{}
	s.hub.mu.Unlock()

	// Writer: push events as they arrive.
	go func() {
		defer func() {
			s.hub.mu.Lock()
			delete(s.hub.conns, ch)
			s.hub.mu.Unlock()
			c.Close(websocket.StatusNormalClosure, "")
		}()
		for msg := range ch {
			ctx, cancel := writeTimeout(r.Context())
			if err := c.Write(ctx, websocket.MessageText, msg); err != nil {
				cancel()
				return
			}
			cancel()
		}
	}()

	// Reader: keep the connection alive; the browser only sends pings/none.
	ctx, cancel := readTimeout(r.Context())
	defer cancel()
	for {
		if _, _, err := c.Read(ctx); err != nil {
			return
		}
	}
}

// ── Small helpers ─────────────────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func readJSON(r *http.Request, v any) error {
	defer r.Body.Close()
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		return err
	}
	if len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, v)
}

func pagination(r *http.Request) (limit, offset int) {
	limit = intParam(r, "limit", 50)
	offset = intParam(r, "offset", 0)
	if limit <= 0 || limit > 500 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	return limit, offset
}

func intParam(r *http.Request, key string, def int) int {
	v := r.URL.Query().Get(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func int64Param(r *http.Request, key string) int64 {
	v := r.URL.Query().Get(key)
	if v == "" {
		return 0
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return 0
	}
	return n
}

func boolParam(r *http.Request, key string) bool {
	v := r.URL.Query().Get(key)
	b, _ := strconv.ParseBool(v)
	return b
}
