package cores

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"mime/multipart"
	"net"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	lksdk "github.com/livekit/server-sdk-go/v2"
	"github.com/pion/webrtc/v4"
	"github.com/pion/webrtc/v4/pkg/media"
)

// baleFallbackIPs maps Bale domains to their origin server IPs.
// ArvanCloud CDN resolves most *.bale.ai to 2.189.68.110, which may be
// blocked on restricted networks.
//
// VERIFIED by full scan: 27,807 probes across 370+ IPs (2026-04-06).
// Only domains with CONFIRMED correct responses are listed here —
// a generic nginx 404 from a wildcard vhost is NOT a valid fallback.
//
// Scan results: go/tests/bale_scan_results.txt
var baleFallbackIPs = map[string][]string{
	// --- Confirmed correct: app-specific responses (not wildcard 404) ---
	"tapi.bale.ai":         {"2.189.68.126"}, // HTTP 403 {"ok":false,"error_code":403} — Bot API ✓
	"next-ws.bale.ai":      {"2.189.68.126"}, // HTTP 401 — WebSocket auth gate ✓
	"bale.ai":              {"2.189.68.126"}, // HTTP 200 — Bale landing page ✓
	"www.bale.ai":          {"2.189.68.126"}, // HTTP 308 → bale.ai ✓
	"beta.bale.ai":         {"2.189.68.126"}, // HTTP 200 — Bale Web app ✓
	"business.bale.ai":     {"2.189.68.126"}, // HTTP 200 — Business portal ✓
	"docs.bale.ai":         {"2.189.68.126"}, // HTTP 200 — Docs (مستندات) ✓
	"maviz.bale.ai":        {"2.189.68.126"}, // HTTP 200 — Bale Web app ✓
	"meet.bale.ai":         {"2.189.68.126"}, // HTTP 200 — Meet app ✓
	"ble.ir":               {"2.189.68.126"}, // HTTP 200 — Short domain ✓
	"www.ble.ir":           {"2.189.68.126"}, // HTTP 200 — Short domain ✓
	"l.ble.ir":             {"2.189.68.126"}, // HTTP 200 — Link shortener ✓
	"contest.bale.ai":      {"2.189.68.126"}, // HTTP 301 — Contest redirect ✓

	// --- Probable correct: same nginx, app-specific 503 (backend down, right vhost) ---
	"api.bale.ai":          {"2.189.68.126"}, // HTTP 503 — API backend unavailable ✓
	"meetbm.bale.ai":       {"2.189.68.126"}, // HTTP 503 — Meet backend unavailable ✓

	// --- CDN file servers: 185.166.104.0/24 (whole range responds) ---
	"cdn-siloo.ble.ir":       {"185.166.104.6"},  // HTTP 503 — CDN, needs file path ✓
	"video-cdn-siloo.ble.ir": {"185.166.104.6"},  // Same range ✓
	"bale.sh":                {"185.166.104.6"},  // HTTP 404 ✓
	"sentry.bale.sh":         {"185.166.104.6"},  // HTTP 404 ✓

	// --- Removed: .126 responds to TCP but doesn't actually serve these domains ---
	// siloo.bale.ai (.94), next-api.bale.ai (.118), gateway-sabz.bale.ai,
	// meet-gw.bale.ai (.115), meet-gw3.bale.ai (.115), signaling.bale.ai (79.127.55.164),
	// api.ble.ir — all unreachable from abroad, .126 returns 404 for their paths
}

// BaleCore implements the Core interface for Bale via its Bot API (Telegram Bot API-compatible).
type BaleCore struct {
	mu sync.RWMutex
	wg sync.WaitGroup

	// Auth state
	botToken string
	botInfo  *User
	authed   bool
	isBot    bool

	// Network
	httpClient *http.Client
	baseURL    string // https://tapi.bale.ai

	// Session
	sessionPath string

	// Update polling (bot mode)
	updateOffset   int64
	updateHandlers []func(Update)
	updateMu       sync.RWMutex
	pollCtx        context.Context
	pollCancel     context.CancelFunc

	// User mode (gRPC-Web/Protobuf over WebSocket)
	userToken  string // JWT access token
	userID     int64
	userPhone  string
	wsConn     *websocket.Conn
	wsCtx      context.Context
	wsCancel   context.CancelFunc
	wsIndex    int64                                  // auto-incrementing request index
	wsPending  map[int64]chan map[string]interface{}   // index → response channel
	wsPendMu   sync.Mutex
	wsPingID   int64
	wsSessionID string

	// Context
	ctx    context.Context
	cancel context.CancelFunc

	// Group ID cache: peer ID → internal group ID (for Groups service)
	// Peer ID is used in Messaging (Peer{type, id}), internal ID in Groups (ShortPeer{id})
	groupIDCache   map[int64]int64
	groupIDCacheMu sync.RWMutex

	// Active call (LiveKit-based)
	activeCall   *baleActiveCall
	activeCallMu sync.Mutex
}

var _ Core = (*BaleCore)(nil)

// baleActiveCall holds state for an active LiveKit call connection.
// UNTESTED: meet-em.ble.ir is geo-restricted to Iran. This entire subsystem
// was implemented from the Python reference (bale.py) and LiveKit SDK docs
// but has never been tested against a live server.
type baleActiveCall struct {
	session  *CallSession
	room     *lksdk.Room
	audioPub *lksdk.LocalTrackPublication // our published silent/mic audio track
	muted    bool
}

type baleSession struct {
	BotToken  string `json:"bot_token,omitempty"`
	BotID     string `json:"bot_id,omitempty"`
	UserToken string `json:"user_token,omitempty"` // JWT for user mode
	UserID    int64  `json:"user_id,omitempty"`
	Phone     string `json:"phone,omitempty"`
}

// newBaleHTTPClient creates an http.Client with DNS fallback.
// The problem: blocked IPs may accept TCP but hang on TLS, so a simple
// DialContext fallback isn't enough — the Transport does TLS separately.
// Solution: use DialTLSContext to do TCP+TLS together with a short probe
// timeout, then fall back to origin IPs if the whole handshake fails.
func newBaleHTTPClient(timeout time.Duration) *http.Client {
	probeTimeout := 5 * time.Second

	transport := &http.Transport{
		DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(addr)
			if err != nil {
				host = addr
				port = "443"
			}

			// Try DNS-resolved address first (TCP + TLS within probeTimeout)
			conn, firstErr := dialTLS(host, addr, probeTimeout)
			if firstErr == nil {
				return conn, nil
			}

			// DNS address failed — try fallback IPs
			fallbacks, ok := baleFallbackIPs[host]
			if !ok {
				return nil, firstErr
			}

			for _, ip := range fallbacks {
				fallbackAddr := net.JoinHostPort(ip, port)
				conn, err = dialTLS(host, fallbackAddr, probeTimeout)
				if err == nil {
					return conn, nil
				}
			}

			return nil, fmt.Errorf("all addresses failed for %s (dns: %v)", host, firstErr)
		},
	}

	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
	}
}

// dialTLS does TCP connect + TLS handshake in one step with a single timeout.
// sniHost is used for TLS ServerName; addr is the IP:port to connect to.
func dialTLS(sniHost string, addr string, timeout time.Duration) (net.Conn, error) {
	dialer := &net.Dialer{Timeout: timeout}
	conn, err := dialer.Dial("tcp", addr)
	if err != nil {
		return nil, err
	}

	tlsConn := tls.Client(conn, &tls.Config{
		ServerName: sniHost,
	})

	// TLS handshake with timeout
	if err := tlsConn.SetDeadline(time.Now().Add(timeout)); err != nil {
		conn.Close()
		return nil, err
	}
	if err := tlsConn.Handshake(); err != nil {
		conn.Close()
		return nil, err
	}
	// Clear deadline — let the HTTP client manage timeouts from here
	tlsConn.SetDeadline(time.Time{})

	return tlsConn, nil
}

// NewBaleCore creates a new Bale core instance.
func NewBaleCore(sessionPath string) *BaleCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &BaleCore{
		httpClient:   newBaleHTTPClient(60 * time.Second),
		baseURL:      "https://tapi.bale.ai",
		sessionPath:  sessionPath,
		groupIDCache: make(map[int64]int64),
		ctx:          ctx,
		cancel:      cancel,
	}
}

const balePlatform = "bale"

// --- Core Interface: Identity ---

func (b *BaleCore) Name() string { return balePlatform }

// GetUserID returns the authenticated user's ID (user mode only).
func (b *BaleCore) GetUserID() int64 { return b.userID }

// Exported protobuf helpers for debugging/testing.
func PbEncode(fields map[string]interface{}) []byte                    { return pbEncode(fields) }

// UserHTTPPost sends an RPC via gRPC-Web HTTP POST (bypasses WebSocket).
func (b *BaleCore) UserHTTPPost(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	return b.wsPost(service, method, payload, b.userToken)
}
func PbGetInt64(m map[string]interface{}, field string) int64          { return pbGetInt64(m, field) }
func PbGetString(m map[string]interface{}, field string) string       { return pbGetString(m, field) }
func PbGetMsg(m map[string]interface{}, field string) map[string]interface{} { return pbGetMsg(m, field) }
func PbGetList(m map[string]interface{}, field string) []interface{}  { return pbGetList(m, field) }
func ParseMsgIDFullExported(msgID string) (int64, int64, int64)      { return parseMsgIDFull(msgID) }
func PbDecode(data []byte) map[string]interface{}                    { return pbDecode(data) }
func (b *BaleCore) UserSendRaw(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	return b.userSend(service, method, payload)
}
func (b *BaleCore) ResolveGroupID(peerID int64) (int64, error) {
	return b.resolveGroupInternalID(peerID)
}
func (b *BaleCore) UploadRawPUT(url string, data []byte) error {
	req, err := http.NewRequestWithContext(b.ctx, "PUT", url, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "multipart/form-data")
	req.Header.Set("Origin", "https://web.bale.ai")
	req.Header.Set("Cookie", "access_token="+b.userToken)
	req.ContentLength = int64(len(data))
	resp, err := b.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return nil
}

// resolveGroupInternalID converts a peer ID to the internal group ID used by Groups service.
// The Groups service (pin, kick, admin, etc.) uses a different ID than Messaging (send, edit, etc.).
// Result is cached after first lookup.
func (b *BaleCore) resolveGroupInternalID(peerID int64) (int64, error) {
	b.groupIDCacheMu.RLock()
	if cached, ok := b.groupIDCache[peerID]; ok {
		b.groupIDCacheMu.RUnlock()
		return cached, nil
	}
	b.groupIDCacheMu.RUnlock()

	// Fetch via GetFullGroup
	resp, err := b.UserGetFullGroup(peerID)
	if err != nil {
		return 0, fmt.Errorf("resolveGroupInternalID: %w", err)
	}
	groupData := pbGetMsg(resp, "1")
	internalID := pbGetInt64(groupData, "1")
	if internalID == 0 {
		// Fallback: use peer ID as-is
		return peerID, nil
	}

	b.groupIDCacheMu.Lock()
	b.groupIDCache[peerID] = internalID
	b.groupIDCacheMu.Unlock()

	return internalID, nil
}

func (b *BaleCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapReactions, CapPolls, CapStickers,
		CapAdmin, CapFolders, CapTyping, CapSearch, CapLocation,
		CapFileTransfer,
	}
}

// --- Core Interface: Auth ---

func (b *BaleCore) Authenticate(cfg AuthConfig) error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if cfg.Mode == AuthModeBot {
		return b.authBot(cfg.BotToken)
	}
	return b.authUser(cfg)
}

func (b *BaleCore) authBot(token string) error {
	if token == "" {
		return fmt.Errorf("%w: bot token is required", ErrInvalidInput)
	}

	b.botToken = token

	// Verify token with getMe
	resp, err := b.apiRequest("getMe", nil)
	if err != nil {
		b.botToken = ""
		return fmt.Errorf("%w: %v", ErrAuth, err)
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		b.botToken = ""
		return fmt.Errorf("%w: unexpected getMe response", ErrAuth)
	}

	b.botInfo = b.mapUser(result)
	b.isBot = true
	b.authed = true

	// Save session
	if err := b.saveSession(); err != nil {
		fmt.Fprintf(os.Stderr, "bale: warning: could not save session: %v\n", err)
	}

	// Start update polling
	b.startPolling()

	return nil
}

func (b *BaleCore) loadSession() error {
	if b.sessionPath == "" {
		return nil
	}
	data, err := os.ReadFile(b.sessionPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var sess baleSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return err
	}
	if sess.BotToken != "" {
		b.botToken = sess.BotToken
	}
	if sess.UserToken != "" {
		b.userToken = sess.UserToken
		b.userID = sess.UserID
		b.userPhone = sess.Phone
	}
	return nil
}

func (b *BaleCore) saveSession() error {
	if b.sessionPath == "" {
		return nil
	}
	sess := baleSession{
		BotToken:  b.botToken,
		UserToken: b.userToken,
		UserID:    b.userID,
		Phone:     b.userPhone,
	}
	if b.botInfo != nil {
		sess.BotID = b.botInfo.ID
	}
	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(b.sessionPath, data, 0600)
}

func (b *BaleCore) Logout() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if !b.authed {
		return nil
	}

	// Stop polling
	if b.pollCancel != nil {
		b.pollCancel()
	}

	// Delete webhook if any, and clear session
	b.apiRequest("deleteWebhook", nil)

	b.botToken = ""
	b.botInfo = nil
	b.authed = false

	// Remove session file
	if b.sessionPath != "" {
		os.Remove(b.sessionPath)
	}

	return nil
}

// --- HTTP API Layer ---

// apiRequest makes a request to the Bale Bot API.
func (b *BaleCore) apiRequest(method string, params map[string]interface{}) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/bot%s/%s", b.baseURL, b.botToken, method)

	var body io.Reader
	var contentType string

	if params != nil {
		jsonData, err := json.Marshal(params)
		if err != nil {
			return nil, fmt.Errorf("marshal params: %w", err)
		}
		body = bytes.NewReader(jsonData)
		contentType = "application/json"
	}

	req, err := http.NewRequestWithContext(b.ctx, "POST", url, body)
	if err != nil {
		return nil, err
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNetwork, err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("%w: read response: %v", ErrNetwork, err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("decode response: %w (body: %s)", err, string(respBody))
	}

	okVal, _ := result["ok"].(bool)
	if !okVal {
		errCode, _ := result["error_code"].(float64)
		desc, _ := result["description"].(string)

		// Check for rate limiting
		if params2, ok := result["parameters"].(map[string]interface{}); ok {
			if retryAfter, ok := params2["retry_after"].(float64); ok {
				return nil, fmt.Errorf("%w: retry after %d seconds: %s", ErrRateLimit, int(retryAfter), desc)
			}
		}

		switch int(errCode) {
		case 401:
			return nil, fmt.Errorf("%w: %s", ErrAuth, desc)
		case 403:
			return nil, fmt.Errorf("%w: %s", ErrPermission, desc)
		case 404:
			return nil, fmt.Errorf("%w: %s", ErrNotFound, desc)
		case 429:
			return nil, fmt.Errorf("%w: %s", ErrRateLimit, desc)
		default:
			return nil, fmt.Errorf("bale API error %d: %s", int(errCode), desc)
		}
	}

	return result, nil
}

// apiRequestMultipart makes a multipart/form-data request for file uploads.
func (b *BaleCore) apiRequestMultipart(method string, fields map[string]string, fileField string, fileName string, fileReader io.Reader) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/bot%s/%s", b.baseURL, b.botToken, method)

	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	// Write text fields
	for k, v := range fields {
		if err := writer.WriteField(k, v); err != nil {
			return nil, fmt.Errorf("write field %s: %w", k, err)
		}
	}

	// Write file field
	if fileField != "" && fileReader != nil {
		part, err := writer.CreateFormFile(fileField, fileName)
		if err != nil {
			return nil, fmt.Errorf("create form file: %w", err)
		}
		if _, err := io.Copy(part, fileReader); err != nil {
			return nil, fmt.Errorf("copy file data: %w", err)
		}
	}

	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(b.ctx, "POST", url, &buf)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNetwork, err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("%w: read response: %v", ErrNetwork, err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("decode response: %w (body: %s)", err, string(respBody))
	}

	okVal, _ := result["ok"].(bool)
	if !okVal {
		errCode, _ := result["error_code"].(float64)
		desc, _ := result["description"].(string)
		return nil, fmt.Errorf("bale API error %d: %s", int(errCode), desc)
	}

	return result, nil
}

// --- Update Polling ---

func (b *BaleCore) startPolling() {
	b.pollCtx, b.pollCancel = context.WithCancel(b.ctx)
	b.wg.Add(1)
	go b.pollLoop()
}

func (b *BaleCore) pollLoop() {
	defer b.wg.Done()
	for {
		select {
		case <-b.pollCtx.Done():
			return
		default:
		}

		params := map[string]interface{}{
			"offset":  b.updateOffset,
			"limit":   100,
			"timeout": 30,
		}

		// Use a longer timeout for long-polling, with fallback dialer
		client := newBaleHTTPClient(40 * time.Second)
		url := fmt.Sprintf("%s/bot%s/getUpdates", b.baseURL, b.botToken)

		jsonData, err := json.Marshal(params)
		if err != nil {
			time.Sleep(1 * time.Second)
			continue
		}

		req, err := http.NewRequestWithContext(b.pollCtx, "POST", url, bytes.NewReader(jsonData))
		if err != nil {
			time.Sleep(1 * time.Second)
			continue
		}
		req.Header.Set("Content-Type", "application/json")

		resp, err := client.Do(req)
		if err != nil {
			// Context cancelled = shutting down
			if b.pollCtx.Err() != nil {
				return
			}
			time.Sleep(2 * time.Second)
			continue
		}

		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			time.Sleep(1 * time.Second)
			continue
		}

		var result map[string]interface{}
		if err := json.Unmarshal(body, &result); err != nil {
			time.Sleep(1 * time.Second)
			continue
		}

		okVal, _ := result["ok"].(bool)
		if !okVal {
			time.Sleep(2 * time.Second)
			continue
		}

		updates, _ := result["result"].([]interface{})
		for _, u := range updates {
			uMap, ok := u.(map[string]interface{})
			if !ok {
				continue
			}

			updateID := jsonInt64(uMap, "update_id")
			if updateID >= b.updateOffset {
				b.updateOffset = updateID + 1
			}

			b.processUpdate(uMap)
		}
	}
}

func (b *BaleCore) processUpdate(u map[string]interface{}) {
	b.updateMu.RLock()
	handlers := make([]func(Update), len(b.updateHandlers))
	copy(handlers, b.updateHandlers)
	b.updateMu.RUnlock()

	if len(handlers) == 0 {
		return
	}

	var update Update
	update.Platform = "bale"

	if msg, ok := u["message"].(map[string]interface{}); ok {
		update.Type = UpdateNewMessage
		parsed := b.mapMessage(msg)
		update.Message = &parsed
		update.ChatID = parsed.ChatID
	} else if msg, ok := u["edited_message"].(map[string]interface{}); ok {
		update.Type = UpdateEditMessage
		parsed := b.mapMessage(msg)
		update.Message = &parsed
		update.ChatID = parsed.ChatID
	} else if cb, ok := u["callback_query"].(map[string]interface{}); ok {
		update.Type = UpdateNewMessage
		// Map callback query as a special message with the callback data
		parsed := b.mapCallbackQuery(cb)
		update.Message = &parsed
		update.ChatID = parsed.ChatID
	} else {
		// Unknown update type, skip
		return
	}

	for _, h := range handlers {
		h(update)
	}
}

// --- Core Interface: Dialogs ---

func (b *BaleCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bots do not have a dialog list", ErrNotSupported)
	}
	// User mode: LoadDialogs via gRPC
	offsetDate := int64(0)
	if opts.Offset != "" {
		offsetDate, _ = strconv.ParseInt(opts.Offset, 10, 64)
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 100
	}
	resp, err := b.UserLoadDialogs(offsetDate, limit)
	if err != nil {
		return nil, err
	}
	// Response field 3 = repeated PeerData (dialogs)
	var dialogs []Dialog
	for _, item := range pbGetList(resp, "3") {
		pd, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		d := Dialog{Platform: "bale"}
		// Field 1 = Peer{1=type, 2=id}
		if peer := pbGetMsg(pd, "1"); peer != nil {
			peerID := pbGetInt64(peer, "2")
			peerType := pbGetInt64(peer, "1")
			d.ID = fmt.Sprintf("%d|%d", peerID, peerType)
			switch peerType {
			case balePeerPrivate:
				d.Type = ChatTypeDM
			case balePeerGroup, balePeerSupergroup:
				d.Type = ChatTypeGroup
			case balePeerChannel:
				d.Type = ChatTypeChannel
			default:
				d.Type = ChatTypeDM
			}
		}
		d.UnreadCount = int(pbGetInt64(pd, "2"))
		// Field 3 = sortDate, field 6 = last message date
		// Field 7 = MessageContent (last message content)
		if content := pbGetMsg(pd, "7"); content != nil {
			lastMsg := &Message{Platform: "bale"}
			b.mapUserMessageContent(pd, "7", lastMsg)
			if lastMsg.Text != "" {
				lastMsg.Text = truncateText(lastMsg.Text, 100)
			}
			lastMsg.SenderID = strconv.FormatInt(pbGetInt64(pd, "4"), 10) // field 4 = senderUid
			dateMs := pbGetInt64(pd, "6")
			if dateMs > 1e12 {
				lastMsg.Timestamp = time.UnixMilli(dateMs)
			}
			d.LastMessage = lastMsg
		}
		// Field 17 = markedAsUnread, field 18 = isMute
		dialogs = append(dialogs, d)
	}
	return dialogs, nil
}

func (b *BaleCore) CreateGroup(name string, members []string) (*Dialog, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bots cannot create groups", ErrNotSupported)
	}
	var userIDs []int64
	for _, m := range members {
		id, _ := strconv.ParseInt(m, 10, 64)
		if id > 0 {
			userIDs = append(userIDs, id)
		}
	}
	resp, err := b.UserCreateGroup(name, userIDs)
	if err != nil {
		return nil, err
	}
	_ = resp
	return &Dialog{
		Title:    name,
		Type:     ChatTypeGroup,
		Platform: "bale",
	}, nil
}

func (b *BaleCore) CreateChannel(name string, description string) (*Dialog, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bots cannot create channels", ErrNotSupported)
	}
	// Bale creates channels as groups with channel type — use CreateGroup then SetRestriction
	return nil, fmt.Errorf("%w: use CreateGroup + SetRestriction for channels", ErrNotSupported)
}

func (b *BaleCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	return nil, fmt.Errorf("%w: bale does not support topics", ErrNotSupported)
}

func (b *BaleCore) GetFolders() ([]Folder, error) {
	return nil, fmt.Errorf("%w: bale bot API does not support folders", ErrNotSupported)
}

func (b *BaleCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bale bot API does not support folders", ErrNotSupported)
	}
	resp, err := b.CreateFolderReal(name, chatIDs)
	if err != nil {
		return nil, err
	}
	folderID := pbGetInt64(resp, "1")
	return &Folder{
		ID:   fmt.Sprintf("%d", folderID),
		Name: name,
	}, nil
}

// --- Core Interface: Messages ---

func (b *BaleCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		// User mode — parse reply info if present
		var replyRID, replyDate int64
		if msg.ReplyToID != "" {
			replyRID, _ = strconv.ParseInt(msg.ReplyToID, 10, 64)
			// We need the date too for Bale reply — try parsing from ReplyToID format "rid:date"
			if parts := strings.SplitN(msg.ReplyToID, ":", 2); len(parts) == 2 {
				replyRID, _ = strconv.ParseInt(parts[0], 10, 64)
				replyDate, _ = strconv.ParseInt(parts[1], 10, 64)
			}
		}
		resp, err := b.UserSendMessage(chatID, msg.Text, replyRID, replyDate)
		if err != nil {
			return nil, err
		}
		// Response: {1: mid (server sequential), 2: date (millis), __rid: our random ID}
		mid := pbGetInt64(resp, "1")
		dateMs := pbGetInt64(resp, "2")
		ourRID, _ := resp["__rid"].(int64)
		// Message ID format: "rid:dateMs:mid"
		// - rid: client random ID, used for edit/delete (UpdateMessage field 2)
		// - dateMs: server timestamp in millis, used for pin/read/reactions
		// - mid: server sequential ID, used for group pin (PinMessage field 4)
		msgID := fmt.Sprintf("%d:%d:%d", ourRID, dateMs, mid)
		return &Message{
			ID:        msgID,
			ChatID:    chatID,
			Text:      msg.Text,
			Timestamp: time.Now(),
			Status:    MessageStatusSent,
			Platform:  "bale",
		}, nil
	}

	// Bot mode
	params := map[string]interface{}{
		"chat_id": chatID,
		"text":    msg.Text,
	}

	if msg.ReplyToID != "" {
		replyID, err := strconv.ParseInt(msg.ReplyToID, 10, 64)
		if err == nil {
			params["reply_to_message_id"] = replyID
		}
	}

	resp, err := b.apiRequest("sendMessage", params)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected sendMessage response")
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

func (b *BaleCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bale bot API does not support fetching message history", ErrNotSupported)
	}
	// User mode: LoadHistory
	// loadMode=2 (BACKWARD) with current time as offset loads from latest backwards
	date := time.Now().UnixMilli()
	if opts.Offset != "" {
		date, _ = strconv.ParseInt(opts.Offset, 10, 64)
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	resp, err := b.UserLoadHistory(chatID, date, limit, 2) // loadMode=2 (BACKWARD)
	if err != nil {
		return nil, err
	}
	// Response field 1 = repeated MessageContainer
	var messages []Message
	for _, item := range pbGetList(resp, "1") {
		mc, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		msg := b.mapHistoryMessage(mc)
		msg.ChatID = chatID
		messages = append(messages, msg)
	}
	return messages, nil
}

func (b *BaleCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		rid, _ := parseMsgIDWithDate(msgID)
		_, err := b.UserUpdateMessage(chatID, rid, 0, text)
		if err != nil {
			return nil, err
		}
		return &Message{ID: msgID, ChatID: chatID, Text: text, Platform: "bale"}, nil
	}

	messageID, err := strconv.ParseInt(msgID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid message ID: %v", ErrInvalidInput, err)
	}

	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": messageID,
		"text":       text,
	}

	resp, err := b.apiRequest("editMessageText", params)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return &Message{ID: msgID, ChatID: chatID, Text: text, Platform: "bale"}, nil
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

func (b *BaleCore) DeleteMessage(chatID string, msgID string) error {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		rid, dateMs := parseMsgIDWithDate(msgID)
		_, err := b.UserDeleteMessage(chatID, []int64{rid}, []int64{dateMs})
		return err
	}

	messageID, err := strconv.ParseInt(msgID, 10, 64)
	if err != nil {
		return fmt.Errorf("%w: invalid message ID: %v", ErrInvalidInput, err)
	}

	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": messageID,
	}

	_, err = b.apiRequest("deleteMessage", params)
	return err
}

func (b *BaleCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	msg.ReplyToID = replyToMsgID
	return b.SendMessage(chatID, msg)
}

func (b *BaleCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		rid, dateMs := parseMsgIDWithDate(msgID)
		fromPeerID, fromPeerType := parsePeerID(fromChatID)
		fromPeer := balePeer(fromPeerType, fromPeerID)
		_, err := b.UserForwardMessages(toChatID, fromPeer, []int64{rid}, []int64{dateMs})
		if err != nil {
			return nil, err
		}
		return &Message{ChatID: toChatID, Platform: "bale", Status: MessageStatusSent}, nil
	}

	messageID, err := strconv.ParseInt(msgID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid message ID: %v", ErrInvalidInput, err)
	}

	params := map[string]interface{}{
		"chat_id":      toChatID,
		"from_chat_id": fromChatID,
		"message_id":   messageID,
	}

	resp, err := b.apiRequest("forwardMessage", params)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected forwardMessage response")
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

// ReactToMessage reacts to a message. msgID format: "rid:dateMs" for user mode.
func (b *BaleCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	if b.isBot {
		return fmt.Errorf("%w: bale bot API does not support reactions", ErrNotSupported)
	}
	// Parse "rid:dateMs" or just "rid"
	rid, dateMs := parseMsgIDWithDate(msgID)
	_, err := b.UserSetReaction(chatID, rid, emoji, dateMs)
	return err
}

func (b *BaleCore) PinMessage(chatID string, msgID string) error {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		rid, dateMs, mid := parseMsgIDFull(msgID)
		// Group pin uses mid (server sequential ID), DM pin uses rid
		_, err := b.UserPinMessage(chatID, rid, dateMs, mid)
		return err
	}

	messageID, err := strconv.ParseInt(msgID, 10, 64)
	if err != nil {
		return fmt.Errorf("%w: invalid message ID: %v", ErrInvalidInput, err)
	}

	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": messageID,
	}

	_, err = b.apiRequest("pinChatMessage", params)
	return err
}

func (b *BaleCore) UnpinMessage(chatID string, msgID string) error {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		rid, dateMs := parseMsgIDWithDate(msgID)
		msgs := []map[string]interface{}{{"1": dateMs, "2": rid}}
		_, err := b.UserUnPinMessages(chatID, msgs, false)
		return err
	}

	messageID, err := strconv.ParseInt(msgID, 10, 64)
	if err != nil {
		return fmt.Errorf("%w: invalid message ID: %v", ErrInvalidInput, err)
	}

	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": messageID,
	}

	_, err = b.apiRequest("unPinChatMessage", params)
	return err
}

// --- Core Interface: Read State ---

func (b *BaleCore) MarkAsRead(chatID string, upToMsgID string) error {
	if b.isBot {
		return fmt.Errorf("%w: bale bot API does not support read state", ErrNotSupported)
	}
	date, _ := strconv.ParseInt(upToMsgID, 10, 64)
	_, err := b.UserMessageRead(chatID, date)
	return err
}

func (b *BaleCore) GetReadState(chatID string) (*ReadState, error) {
	return nil, fmt.Errorf("%w: bale does not expose read state", ErrNotSupported)
}

// --- Core Interface: Files ---

func (b *BaleCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		return b.userUploadFile(chatID, file, progress)
	}

	// Bot mode: use Bot API multipart upload
	method, fieldName := b.detectSendMethod(file.MimeType, file.Name)

	fields := map[string]string{
		"chat_id": chatID,
	}

	// Wrap reader with progress tracking
	var reader io.Reader = file.Reader
	if progress != nil {
		reader = &progressReader{
			reader: file.Reader,
			total:  file.Size,
			onProgress: progress,
		}
	}

	resp, err := b.apiRequestMultipart(method, fields, fieldName, file.Name, reader)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected %s response", method)
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

// userUploadFile uploads a file in user mode:
// 1. GetNasimFileUploadUrl → get upload URL + file_id + chunk_size
// 2. HTTP PUT file data to the URL
// 3. SendMessage with DocumentMessage content
func (b *BaleCore) userUploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	// Step 1: Get upload URL
	uploadInfo, err := b.UserGetFileUploadURL(file.Size, file.Name, file.MimeType)
	if err != nil {
		return nil, fmt.Errorf("GetNasimFileUploadUrl: %w", err)
	}
	fileID := pbGetInt64(uploadInfo, "1")
	uploadURL := pbGetString(uploadInfo, "2")
	if uploadURL == "" {
		// Try raw bytes for URL field
		if raw, ok := uploadInfo["__raw_2"]; ok {
			if bs, ok := raw.([]byte); ok {
				uploadURL = string(bs)
			}
		}
	}
	if uploadURL == "" || fileID == 0 {
		return nil, fmt.Errorf("invalid upload info: fileID=%d url=%q", fileID, uploadURL)
	}

	// Step 2: HTTP PUT the file data
	var reader io.Reader = file.Reader
	if progress != nil {
		reader = &progressReader{reader: file.Reader, total: file.Size, onProgress: progress}
	}

	req, err := http.NewRequestWithContext(b.ctx, "PUT", uploadURL, reader)
	if err != nil {
		return nil, fmt.Errorf("create upload request: %w", err)
	}
	req.Header.Set("Content-Type", "multipart/form-data")
	req.Header.Set("Origin", "https://web.bale.ai")
	req.Header.Set("Cookie", "access_token="+b.userToken)
	req.ContentLength = file.Size

	uploadResp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("upload PUT: %w", err)
	}
	defer uploadResp.Body.Close()
	io.ReadAll(uploadResp.Body)

	if uploadResp.StatusCode >= 400 {
		return nil, fmt.Errorf("upload failed: HTTP %d", uploadResp.StatusCode)
	}

	// Step 3: SendMessage with DocumentMessage
	// MessageContent{4: DocumentMessage{1: file_id, 2: access_hash (user ID), 3: size, 4: name, 5: mime_type}}
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	docMsg := map[string]interface{}{
		"1": fileID,
		"2": b.userID,  // access_hash = our user ID
		"3": file.Size,
		"4": file.Name,  // plain string, NOT StringValue
		"5": file.MimeType,
	}
	content := map[string]interface{}{
		"4": docMsg, // DocumentMessage at field 4
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": content,
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	resp, err := b.userSend(baleServiceMessaging, "SendMessage", payload)
	if err != nil {
		return nil, fmt.Errorf("SendMessage with file: %w", err)
	}

	mid := pbGetInt64(resp, "1")
	dateMs := pbGetInt64(resp, "2")
	msgID := fmt.Sprintf("%d:%d:%d", rid, dateMs, mid)

	return &Message{
		ID:       msgID,
		ChatID:   chatID,
		Platform: "bale",
		Status:   MessageStatusSent,
	}, nil
}

func (b *BaleCore) detectSendMethod(mimeType string, name string) (method string, field string) {
	mime := strings.ToLower(mimeType)
	nameLower := strings.ToLower(name)

	switch {
	case strings.HasPrefix(mime, "image/") && !strings.Contains(mime, "gif"):
		return "sendPhoto", "photo"
	case strings.Contains(mime, "gif"):
		return "sendAnimation", "animation"
	case strings.HasPrefix(mime, "video/"):
		return "sendVideo", "video"
	case strings.HasPrefix(mime, "audio/"):
		if strings.HasSuffix(nameLower, ".ogg") || mime == "audio/ogg" {
			return "sendVoice", "voice"
		}
		return "sendAudio", "audio"
	default:
		return "sendDocument", "document"
	}
}

func (b *BaleCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return ErrAuth
	}
	b.mu.RUnlock()

	// Step 1: get file path via getFile
	params := map[string]interface{}{
		"file_id": fileRef.ID,
	}

	resp, err := b.apiRequest("getFile", params)
	if err != nil {
		return err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return fmt.Errorf("unexpected getFile response")
	}

	filePath, _ := result["file_path"].(string)
	if filePath == "" {
		return fmt.Errorf("%w: file_path not returned", ErrNotFound)
	}

	// Step 2: download from file URL
	fileURL := fmt.Sprintf("%s/file/bot%s/%s", b.baseURL, b.botToken, filePath)

	req, err := http.NewRequestWithContext(b.ctx, "GET", fileURL, nil)
	if err != nil {
		return err
	}

	dlResp, err := b.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrNetwork, err)
	}
	defer dlResp.Body.Close()

	if dlResp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed: HTTP %d", dlResp.StatusCode)
	}

	outFile, err := os.Create(dest)
	if err != nil {
		return fmt.Errorf("create file: %w", err)
	}
	defer outFile.Close()

	var reader io.Reader = dlResp.Body
	if progress != nil {
		reader = &progressReader{
			reader:     dlResp.Body,
			total:      dlResp.ContentLength,
			onProgress: progress,
		}
	}

	_, err = io.Copy(outFile, reader)
	return err
}

// --- Core Interface: Media ---

func (b *BaleCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	return nil, fmt.Errorf("%w: use UploadFile instead", ErrNotSupported)
}

// --- Core Interface: Calls ---

// --- Calling: bale.meet.v1.Meet (LiveKit-based, discovered via mitmproxy 2026-04-07) ---
// UNTESTED: meet-em.ble.ir is geo-restricted to Iran. This entire call subsystem was
// implemented from the Python reference (bale.py) and LiveKit SDK echo example
// but has never been tested against a live Bale server.
//
// Flow: StartGroupCall/JoinGroupCall → get LiveKit JWT + ws_url → connect to LiveKit SFU → WebRTC
// Server: wss://meet-em.ble.ir (geo-restricted to Iran)
// TURN: turns:meet-turn.ble.ir:443?transport=tcp
// STUN: stun:2.189.68.115:443, stun:stun.l.google.com:19302
// LiveKit server version: 1.9.11
// Codecs: VP8, VP9, H264, AV1, opus
//
// Known issue: The Go LiveKit SDK sends sdk=go&os=linux in the WebSocket URL.
// Bale may expect sdk=js&version=2.15.2 with browser User-Agent. If the connection
// is rejected, we may need a WebSocket URL rewrite or a patched SDK.

const baleServiceMeet = "bale.meet.v1.Meet"

// baleExtractCallData extracts call credentials from a StartGroupCall/JoinGroupCall response.
// Response structure: {1: call_id, 2: room, 3: livekit_jwt, 4: {1: ws_url}, 8: admin_uid}
// OR nested: {1: {1: call_id, 2: room, 3: livekit_jwt, 4: {1: ws_url}}}
func baleExtractCallData(resp map[string]interface{}) (callID int64, room, token, wsURL string) {
	// Try direct fields first (WS path may return flat)
	callID = pbGetInt64(resp, "1")
	room = pbGetString(resp, "2")
	token = pbGetString(resp, "3")
	if urlMsg := pbGetMsg(resp, "4"); urlMsg != nil {
		wsURL = pbGetString(urlMsg, "1")
	}

	// If field "1" is a nested message (gRPC-Web response wraps under field 1), extract from it
	if token == "" {
		if inner := pbGetMsg(resp, "1"); inner != nil {
			callID = pbGetInt64(inner, "1")
			room = pbGetString(inner, "2")
			token = pbGetString(inner, "3")
			if urlMsg := pbGetMsg(inner, "4"); urlMsg != nil {
				wsURL = pbGetString(urlMsg, "1")
			}
		}
	}
	return
}

// baleCallSession builds a CallSession with LiveKit transport metadata.
func baleCallSession(callID int64, chatID string, isGroup bool, room, token, wsURL string) *CallSession {
	meta := map[string]string{
		"room": room,
	}
	if token != "" {
		meta["livekit_token"] = token
	}
	if wsURL != "" {
		meta["livekit_url"] = wsURL
	}
	return &CallSession{
		ID:      fmt.Sprintf("%d", callID),
		ChatID:  chatID,
		IsGroup: isGroup,
		State:   CallStateActive,
		Meta:    meta,
	}
}

// baleConnectLiveKit connects to the LiveKit SFU room using the credentials from CallSession.Meta.
// It publishes a silent audio track (required for the SFU to treat us as a real participant)
// and subscribes to all remote tracks. Audio from remote participants is forwarded to
// the update handler as UpdateCallState events.
//
// UNTESTED: meet-em.ble.ir is geo-restricted to Iran.
func (b *BaleCore) baleConnectLiveKit(session *CallSession) error {
	lkURL := session.Meta["livekit_url"]
	lkToken := session.Meta["livekit_token"]
	if lkURL == "" || lkToken == "" {
		return fmt.Errorf("missing LiveKit credentials (url=%q token=%v)", lkURL, lkToken != "")
	}

	// Create a silent opus audio track — the SFU needs at least one published audio track
	// to treat the connection as a real call participant (affects bandwidth allocation,
	// triggers connection_quality_changed events).
	silenceTrack, err := lksdk.NewLocalSampleTrack(webrtc.RTPCodecCapability{
		MimeType:  webrtc.MimeTypeOpus,
		ClockRate: 48000,
		Channels:  1,
	})
	if err != nil {
		return fmt.Errorf("create silent audio track: %w", err)
	}

	cb := &lksdk.RoomCallback{
		ParticipantCallback: lksdk.ParticipantCallback{
			OnTrackSubscribed: func(track *webrtc.TrackRemote, pub *lksdk.RemoteTrackPublication, rp *lksdk.RemoteParticipant) {
				fmt.Fprintf(os.Stderr, "bale: track subscribed: kind=%s from %s\n", track.Kind(), rp.Identity())
				if track.Kind() == webrtc.RTPCodecTypeAudio {
					// Read and discard audio RTP packets to keep the stream alive.
					// In a full implementation, these would be decoded and forwarded
					// to the Dart UI for playback via the bridge's audio callback.
					go func() {
						buf := make([]byte, 1500)
						for {
							_, _, err := track.Read(buf)
							if err != nil {
								return
							}
						}
					}()
				}
			},
			OnTrackUnsubscribed: func(track *webrtc.TrackRemote, pub *lksdk.RemoteTrackPublication, rp *lksdk.RemoteParticipant) {
				fmt.Fprintf(os.Stderr, "bale: track unsubscribed: kind=%s from %s\n", track.Kind(), rp.Identity())
			},
		},
		OnDisconnected: func() {
			fmt.Fprintf(os.Stderr, "bale: LiveKit disconnected\n")
			b.activeCallMu.Lock()
			b.activeCall = nil
			b.activeCallMu.Unlock()
			b.updateMu.RLock()
			for _, h := range b.updateHandlers {
				go h(Update{Type: UpdateCallState})
			}
			b.updateMu.RUnlock()
		},
		OnReconnecting: func() {
			fmt.Fprintf(os.Stderr, "bale: LiveKit reconnecting...\n")
		},
		OnReconnected: func() {
			fmt.Fprintf(os.Stderr, "bale: LiveKit reconnected\n")
		},
		OnParticipantConnected: func(p *lksdk.RemoteParticipant) {
			fmt.Fprintf(os.Stderr, "bale: participant joined: %s (sid=%s)\n", p.Identity(), p.SID())
		},
		OnParticipantDisconnected: func(p *lksdk.RemoteParticipant) {
			fmt.Fprintf(os.Stderr, "bale: participant left: %s\n", p.Identity())
		},
	}

	room, err := lksdk.ConnectToRoomWithToken(lkURL, lkToken, cb,
		lksdk.WithAutoSubscribe(true),
	)
	if err != nil {
		return fmt.Errorf("LiveKit connect to %s: %w", lkURL, err)
	}

	fmt.Fprintf(os.Stderr, "bale: connected to LiveKit room %s\n", room.Name())

	// Publish silent audio track — feed one frame of silence then rely on DTX
	// Source auto-detected as MICROPHONE for audio tracks when Source == UNKNOWN
	audioPub, err := room.LocalParticipant.PublishTrack(silenceTrack, &lksdk.TrackPublicationOptions{
		Name: "mic",
	})
	if err != nil {
		room.Disconnect()
		return fmt.Errorf("publish audio track: %w", err)
	}

	// Write one frame of silence to initialize the encoder, then DTX handles the rest
	silence := make([]byte, 960*2) // 20ms at 48kHz, 16-bit mono = 960 samples * 2 bytes
	_ = silenceTrack.WriteSample(media.Sample{
		Data:     silence,
		Duration: 20 * time.Millisecond,
	}, nil)

	fmt.Fprintf(os.Stderr, "bale: audio track published (silent, DTX)\n")

	b.activeCallMu.Lock()
	b.activeCall = &baleActiveCall{
		session:  session,
		room:     room,
		audioPub: audioPub,
	}
	b.activeCallMu.Unlock()

	return nil
}

// baleDisconnectLiveKit disconnects from the active LiveKit room.
func (b *BaleCore) baleDisconnectLiveKit() {
	b.activeCallMu.Lock()
	call := b.activeCall
	b.activeCall = nil
	b.activeCallMu.Unlock()

	if call != nil && call.room != nil {
		call.room.Disconnect()
		fmt.Fprintf(os.Stderr, "bale: LiveKit disconnected\n")
	}
}

func (b *BaleCore) StartCall(chatID string, video bool) (*CallSession, error) {
	// 1:1 calls: StartCall {1: OutPeer{1:1, 2:peer_id}, 2: rid}
	// UNTESTED: 1:1 calls may require access_hash which is hard to obtain.
	// The Python reference notes: "use group calls instead for reliability."
	if b.isBot {
		return nil, fmt.Errorf("%w: bots cannot make calls", ErrNotSupported)
	}

	b.activeCallMu.Lock()
	if b.activeCall != nil {
		b.activeCallMu.Unlock()
		return nil, fmt.Errorf("already in a call (callID=%s)", b.activeCall.session.ID)
	}
	b.activeCallMu.Unlock()

	peerID, _ := parsePeerID(chatID)

	rid := baleRID()
	resp, err := b.userSend(baleServiceMeet, "StartCall", map[string]interface{}{
		"1": map[string]interface{}{"1": int64(1), "2": peerID}, // type=1 (PRIVATE)
		"2": rid,
	})
	if err != nil {
		return nil, fmt.Errorf("StartCall: %w", err)
	}

	callID, room, token, wsURL := baleExtractCallData(resp)
	if callID == 0 {
		return nil, fmt.Errorf("StartCall: no call_id in response")
	}

	// If we didn't get a ws_url from the response, try GetWssURL
	if wsURL == "" && callID != 0 {
		if u, err := b.GetWssURL(fmt.Sprintf("%d", callID)); err == nil && u != "" {
			wsURL = u
		}
	}

	fmt.Fprintf(os.Stderr, "bale: 1:1 call started: callID=%d room=%s ws=%s\n", callID, room, wsURL)

	session := baleCallSession(callID, chatID, false, room, token, wsURL)
	session.IsVideo = video

	// Connect to LiveKit SFU
	if err := b.baleConnectLiveKit(session); err != nil {
		// Signaling succeeded but LiveKit connection failed — try to end the call
		fmt.Fprintf(os.Stderr, "bale: LiveKit connect failed: %v (call signaling was OK)\n", err)
		_ = b.baleEndCallSignaling(callID)
		return nil, fmt.Errorf("StartCall: LiveKit connect: %w", err)
	}

	return session, nil
}

func (b *BaleCore) JoinGroupCall(chatID string) (*CallSession, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bots cannot join calls", ErrNotSupported)
	}

	b.activeCallMu.Lock()
	if b.activeCall != nil {
		b.activeCallMu.Unlock()
		return nil, fmt.Errorf("already in a call (callID=%s)", b.activeCall.session.ID)
	}
	b.activeCallMu.Unlock()

	peerID, peerType := parsePeerID(chatID)

	// Resolve internal group ID for the Peer
	internalID := peerID
	if peerType == balePeerGroup || peerType == balePeerSupergroup {
		if resolved, err := b.resolveGroupInternalID(peerID); err == nil {
			internalID = resolved
		}
	}

	var session *CallSession

	// First try to find and join an existing call in this group
	ongoingCallID := b.baleFindOngoingCallID()
	if ongoingCallID != 0 {
		resp, err := b.userSend(baleServiceMeet, "JoinGroupCall", map[string]interface{}{
			"1": ongoingCallID,
		})
		if err == nil {
			cid, room, token, wsURL := baleExtractCallData(resp)
			if cid == 0 {
				cid = ongoingCallID
			}
			fmt.Fprintf(os.Stderr, "bale: joined existing group call: callID=%d room=%s ws=%s\n", cid, room, wsURL)
			session = baleCallSession(cid, chatID, true, room, token, wsURL)
		}
		// Join failed — fall through to start a new call
	}

	if session == nil {
		// No existing call found — start a new group call
		// StartGroupCall: {1: Peer{1: type, 2: internalID}}
		resp, err := b.userSend(baleServiceMeet, "StartGroupCall", map[string]interface{}{
			"1": map[string]interface{}{"1": int64(peerType), "2": internalID},
		})
		if err != nil {
			return nil, fmt.Errorf("StartGroupCall: %w", err)
		}

		cid, room, token, wsURL := baleExtractCallData(resp)
		if cid == 0 {
			return nil, fmt.Errorf("StartGroupCall: no call_id in response")
		}

		fmt.Fprintf(os.Stderr, "bale: group call started: callID=%d room=%s ws=%s\n", cid, room, wsURL)
		session = baleCallSession(cid, chatID, true, room, token, wsURL)
	}

	// If we didn't get a ws_url, try GetWssURL
	if session.Meta["livekit_url"] == "" {
		if u, err := b.GetWssURL(session.ID); err == nil && u != "" {
			session.Meta["livekit_url"] = u
		}
	}

	// Connect to LiveKit SFU
	if err := b.baleConnectLiveKit(session); err != nil {
		fmt.Fprintf(os.Stderr, "bale: LiveKit connect failed: %v (call signaling was OK)\n", err)
		cid, _ := strconv.ParseInt(session.ID, 10, 64)
		_ = b.baleEndCallSignaling(cid)
		return nil, fmt.Errorf("JoinGroupCall: LiveKit connect: %w", err)
	}

	return session, nil
}

// baleFindOngoingCallID checks GetOngoingCalls and extracts the call_id.
// Response: {1: {1: caller_peer, 2: group_peer, 10: {1: call_id}, ...}}
func (b *BaleCore) baleFindOngoingCallID() int64 {
	resp, err := b.userSend(baleServiceMeet, "GetOngoingCalls", map[string]interface{}{})
	if err != nil {
		return 0
	}
	// call_id is in field 1.10.1
	callObj := pbGetMsg(resp, "1")
	if callObj == nil {
		return 0
	}
	f10 := pbGetMsg(callObj, "10")
	if f10 == nil {
		return 0
	}
	return pbGetInt64(f10, "1")
}

// GetOngoingCalls returns currently active calls.
func (b *BaleCore) GetOngoingCalls() (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "GetOngoingCalls", map[string]interface{}{})
}

// GetWssURL retrieves the LiveKit WebSocket URL for an active call.
func (b *BaleCore) GetWssURL(callID string) (string, error) {
	cid, _ := strconv.ParseInt(callID, 10, 64)
	if cid == 0 {
		return "", fmt.Errorf("%w: invalid call ID", ErrInvalidInput)
	}
	resp, err := b.userSend(baleServiceMeet, "GetWssURL", map[string]interface{}{
		"1": cid,
	})
	if err != nil {
		return "", err
	}
	url := pbGetString(resp, "1")
	if url == "" {
		// Try nested
		if inner := pbGetMsg(resp, "1"); inner != nil {
			url = pbGetString(inner, "1")
		}
	}
	return url, nil
}

// GetGroupCall checks if a group call is active.
func (b *BaleCore) GetGroupCall(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	internalID := peerID
	if peerType == balePeerGroup || peerType == balePeerSupergroup {
		if resolved, err := b.resolveGroupInternalID(peerID); err == nil {
			internalID = resolved
		}
	}
	return b.userSend(baleServiceMeet, "GetGroupCall", map[string]interface{}{
		"1": map[string]interface{}{"1": int64(peerType), "2": internalID},
	})
}

// GetCallLogs returns call history.
func (b *BaleCore) GetCallLogs(page, count int) (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "GetCallLogs", map[string]interface{}{
		"1": int64(page),
		"2": int64(count),
	})
}

func (b *BaleCore) EndCall(callID string) error {
	// Disconnect from LiveKit first
	b.baleDisconnectLiveKit()

	// Then tell Bale's server we're leaving
	cid, _ := strconv.ParseInt(callID, 10, 64)
	if cid == 0 {
		return fmt.Errorf("%w: invalid call ID", ErrInvalidInput)
	}
	return b.baleEndCallSignaling(cid)
}

// baleEndCallSignaling sends the leave/discard RPC to Bale's server.
func (b *BaleCore) baleEndCallSignaling(callID int64) error {
	// Try LeaveGroupCall first (works for group calls): {1: call_id, 2: reason(0)}
	_, err := b.userSend(baleServiceMeet, "LeaveGroupCall", map[string]interface{}{
		"1": callID,
		"2": int64(0),
	})
	if err == nil {
		return nil
	}
	// Fallback to DiscardCall (for private 1:1 calls): {1: call_id, 2: reason(1)}
	_, err2 := b.userSend(baleServiceMeet, "DiscardCall", map[string]interface{}{
		"1": callID,
		"2": int64(1),
	})
	if err2 != nil {
		return fmt.Errorf("EndCall: LeaveGroupCall: %v, DiscardCall: %w", err, err2)
	}
	return nil
}

func (b *BaleCore) SetCallMuted(callID string, muted bool) error {
	b.activeCallMu.Lock()
	call := b.activeCall
	b.activeCallMu.Unlock()

	if call == nil || call.audioPub == nil {
		return fmt.Errorf("%w: no active call", ErrNotSupported)
	}
	if call.session.ID != callID {
		return fmt.Errorf("%w: call ID mismatch (active=%s, requested=%s)", ErrInvalidInput, call.session.ID, callID)
	}

	call.audioPub.SetMuted(muted)
	call.muted = muted
	fmt.Fprintf(os.Stderr, "bale: call muted=%v\n", muted)
	return nil
}

// --- Core Interface: Profile ---

func (b *BaleCore) GetProfile(userID string) (*User, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	isBot := b.isBot
	b.mu.RUnlock()

	if !isBot {
		// User mode: use LoadFullUsers
		uid, _ := strconv.ParseInt(userID, 10, 64)
		if uid == 0 {
			return nil, fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
		}
		resp, err := b.UserLoadFullUsers([]int64{uid})
		if err != nil {
			return nil, err
		}
		// Response: {1: repeated FullUser}
		users := pbGetList(resp, "1")
		if len(users) == 0 {
			return nil, fmt.Errorf("%w: user not found", ErrNotFound)
		}
		fu, _ := users[0].(map[string]interface{})
		if fu == nil {
			return nil, fmt.Errorf("%w: user not found", ErrNotFound)
		}
		// FullUser: {1: id, 2: access_hash, 3: name, 5: nick_name, 9: about, ...}
		name := pbGetString(fu, "3")
		nick := pbGetString(fu, "5")
		about := pbGetString(fu, "9")
		_ = about // User struct doesn't have Bio field
		return &User{
			ID:          userID,
			DisplayName: name,
			Username:    nick,
			Platform:    "bale",
		}, nil
	}

	// Bot API: use getChat for user profiles
	params := map[string]interface{}{
		"chat_id": userID,
	}

	resp, err := b.apiRequest("getChat", params)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected getChat response")
	}

	return b.mapChatToUser(result), nil
}

// --- Core Interface: Real-time ---

func (b *BaleCore) OnUpdate(handler func(Update)) {
	b.updateMu.Lock()
	defer b.updateMu.Unlock()
	b.updateHandlers = append(b.updateHandlers, handler)
}

func (b *BaleCore) Close() error {
	if b.pollCancel != nil {
		b.pollCancel()
	}
	b.cancel()
	b.wg.Wait()
	b.mu.Lock()
	b.saveSession()
	b.authed = false
	b.mu.Unlock()
	return nil
}

// --- Chat Management (Bale-specific convenience methods) ---

// GetChat retrieves full chat info.
func (b *BaleCore) GetChat(chatID string) (map[string]interface{}, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	resp, err := b.apiRequest("getChat", params)
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// GetChatAdministrators returns list of chat admins.
func (b *BaleCore) GetChatAdministrators(chatID string) ([]map[string]interface{}, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	resp, err := b.apiRequest("getChatAdministrators", params)
	if err != nil {
		return nil, err
	}
	results, _ := resp["result"].([]interface{})
	var admins []map[string]interface{}
	for _, r := range results {
		if m, ok := r.(map[string]interface{}); ok {
			admins = append(admins, m)
		}
	}
	return admins, nil
}

// GetChatMembersCount returns the number of members in a chat.
func (b *BaleCore) GetChatMembersCount(chatID string) (int, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	resp, err := b.apiRequest("getChatMembersCount", params)
	if err != nil {
		return 0, err
	}
	count, _ := resp["result"].(float64)
	return int(count), nil
}

// GetChatMember returns info about a specific chat member.
func (b *BaleCore) GetChatMember(chatID string, userID int64) (map[string]interface{}, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	}
	resp, err := b.apiRequest("getChatMember", params)
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// BanChatMember bans a user from a group/channel.
func (b *BaleCore) BanChatMember(chatID string, userID int64) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	}
	_, err := b.apiRequest("banChatMember", params)
	return err
}

// UnbanChatMember unbans a user.
func (b *BaleCore) UnbanChatMember(chatID string, userID int64, onlyIfBanned bool) error {
	params := map[string]interface{}{
		"chat_id":        chatID,
		"user_id":        userID,
		"only_if_banned": onlyIfBanned,
	}
	_, err := b.apiRequest("unbanChatMember", params)
	return err
}

// PromoteChatMember promotes or demotes a user in a group/channel.
func (b *BaleCore) PromoteChatMember(chatID string, userID int64, perms map[string]bool) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	}
	for k, v := range perms {
		params[k] = v
	}
	_, err := b.apiRequest("promoteChatMember", params)
	return err
}

// SetChatTitle sets the chat title.
func (b *BaleCore) SetChatTitle(chatID string, title string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"title":   title,
	}
	_, err := b.apiRequest("setChatTitle", params)
	return err
}

// SetChatDescription sets the chat description.
func (b *BaleCore) SetChatDescription(chatID string, description string) error {
	params := map[string]interface{}{
		"chat_id":     chatID,
		"description": description,
	}
	_, err := b.apiRequest("setChatDescription", params)
	return err
}

// SetChatPhoto sets a new chat photo.
func (b *BaleCore) SetChatPhoto(chatID string, photo io.Reader, fileName string) error {
	fields := map[string]string{
		"chat_id": chatID,
	}
	_, err := b.apiRequestMultipart("setChatPhoto", fields, "photo", fileName, photo)
	return err
}

// DeleteChatPhoto deletes the chat photo.
func (b *BaleCore) DeleteChatPhoto(chatID string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	_, err := b.apiRequest("deleteChatPhoto", params)
	return err
}

// LeaveChat makes the bot leave a chat.
func (b *BaleCore) LeaveChat(chatID string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	_, err := b.apiRequest("leaveChat", params)
	return err
}

// CreateChatInviteLink creates a new invite link.
func (b *BaleCore) CreateChatInviteLink(chatID string) (string, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	resp, err := b.apiRequest("createChatInviteLink", params)
	if err != nil {
		return "", err
	}
	result, _ := resp["result"].(map[string]interface{})
	link, _ := result["invite_link"].(string)
	return link, nil
}

// ExportChatInviteLink exports (or creates new) invite link.
func (b *BaleCore) ExportChatInviteLink(chatID string) (string, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	resp, err := b.apiRequest("exportChatInviteLink", params)
	if err != nil {
		return "", err
	}
	link, _ := resp["result"].(string)
	return link, nil
}

// UnpinAllChatMessages unpins all messages in a chat.
func (b *BaleCore) UnpinAllChatMessages(chatID string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	_, err := b.apiRequest("unpinAllChatMessages", params)
	return err
}

// SendChatAction sends a chat action (typing indicator etc).
func (b *BaleCore) SendChatAction(chatID string, action string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"action":  action,
	}
	_, err := b.apiRequest("sendChatAction", params)
	return err
}

// AnswerCallbackQuery responds to an inline button callback.
func (b *BaleCore) AnswerCallbackQuery(callbackQueryID string, text string, showAlert bool) error {
	params := map[string]interface{}{
		"callback_query_id": callbackQueryID,
	}
	if text != "" {
		params["text"] = text
	}
	if showAlert {
		params["show_alert"] = true
	}
	_, err := b.apiRequest("answerCallbackQuery", params)
	return err
}

// CopyMessage copies a message without the forward header.
func (b *BaleCore) CopyMessage(chatID string, fromChatID string, msgID int64) (int64, error) {
	params := map[string]interface{}{
		"chat_id":      chatID,
		"from_chat_id": fromChatID,
		"message_id":   msgID,
	}
	resp, err := b.apiRequest("copyMessage", params)
	if err != nil {
		return 0, err
	}
	result, _ := resp["result"].(map[string]interface{})
	newMsgID := jsonInt64(result, "message_id")
	return newMsgID, nil
}

// EditMessageCaption edits the caption of a media message.
func (b *BaleCore) EditMessageCaption(chatID string, msgID int64, caption string) error {
	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": msgID,
		"caption":    caption,
	}
	_, err := b.apiRequest("editMessageCaption", params)
	return err
}

// SendMessageWithKeyboard sends a message with an inline keyboard.
func (b *BaleCore) SendMessageWithKeyboard(chatID string, text string, keyboard [][]map[string]string) (*Message, error) {
	// Build InlineKeyboardMarkup
	var rows [][]map[string]interface{}
	for _, row := range keyboard {
		var btnRow []map[string]interface{}
		for _, btn := range row {
			button := map[string]interface{}{}
			for k, v := range btn {
				button[k] = v
			}
			btnRow = append(btnRow, button)
		}
		rows = append(rows, btnRow)
	}

	params := map[string]interface{}{
		"chat_id": chatID,
		"text":    text,
		"reply_markup": map[string]interface{}{
			"inline_keyboard": rows,
		},
	}

	resp, err := b.apiRequest("sendMessage", params)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected sendMessage response")
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

// SendLocation sends a location point.
func (b *BaleCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	params := map[string]interface{}{
		"chat_id":   chatID,
		"latitude":  lat,
		"longitude": lon,
	}
	resp, err := b.apiRequest("sendLocation", params)
	if err != nil {
		return nil, err
	}
	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected sendLocation response")
	}
	parsed := b.mapMessage(result)
	return &parsed, nil
}

// SendContact sends a phone contact.
func (b *BaleCore) SendContact(chatID string, phone string, firstName string, lastName string) (*Message, error) {
	params := map[string]interface{}{
		"chat_id":      chatID,
		"phone_number": phone,
		"first_name":   firstName,
	}
	if lastName != "" {
		params["last_name"] = lastName
	}
	resp, err := b.apiRequest("sendContact", params)
	if err != nil {
		return nil, err
	}
	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected sendContact response")
	}
	parsed := b.mapMessage(result)
	return &parsed, nil
}

// --- Sticker Methods ---

// GetStickerSet gets a sticker set by name.
func (b *BaleCore) GetStickerSet(name string) (map[string]interface{}, error) {
	params := map[string]interface{}{
		"name": name,
	}
	resp, err := b.apiRequest("getStickerSet", params)
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// SendSticker sends a sticker.
// Bale quirk: sticker file_ids contain colons which break JSON encoding.
// Must use multipart/form-data instead of application/json.
func (b *BaleCore) SendSticker(chatID string, stickerFileID string) (*Message, error) {
	fields := map[string]string{
		"chat_id": chatID,
		"sticker": stickerFileID,
	}
	resp, err := b.apiRequestMultipart("sendSticker", fields, "", "", nil)
	if err != nil {
		return nil, err
	}
	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected sendSticker response")
	}
	parsed := b.mapMessage(result)
	return &parsed, nil
}

// --- Data Mapping Helpers ---

func (b *BaleCore) mapMessage(m map[string]interface{}) Message {
	msg := Message{
		Platform: "bale",
	}

	msg.ID = strconv.FormatInt(jsonInt64(m, "message_id"), 10)

	// Chat
	if chat, ok := m["chat"].(map[string]interface{}); ok {
		msg.ChatID = strconv.FormatInt(jsonInt64(chat, "id"), 10)
	}

	// Sender
	if from, ok := m["from"].(map[string]interface{}); ok {
		msg.SenderID = strconv.FormatInt(jsonInt64(from, "id"), 10)
		msg.SenderName = b.buildDisplayName(from)
	}

	// Text (could be in text or caption)
	if text, ok := m["text"].(string); ok {
		msg.Text = text
	} else if caption, ok := m["caption"].(string); ok {
		msg.Text = caption
	}

	// Timestamp
	if date, ok := m["date"].(float64); ok {
		msg.Timestamp = time.Unix(int64(date), 0)
	}

	// Edit date
	if editDate, ok := m["edit_date"].(float64); ok {
		t := time.Unix(int64(editDate), 0)
		msg.EditedAt = &t
	}

	// Reply
	if reply, ok := m["reply_to_message"].(map[string]interface{}); ok {
		msg.ReplyToID = strconv.FormatInt(jsonInt64(reply, "message_id"), 10)
		if txt, ok := reply["text"].(string); ok {
			msg.ReplyPreview = truncateText(txt, 100)
		}
	}

	// Forward
	if fwdFrom, ok := m["forward_from"].(map[string]interface{}); ok {
		msg.ForwardFrom = b.buildDisplayName(fwdFrom)
	} else if fwdChat, ok := m["forward_from_chat"].(map[string]interface{}); ok {
		if title, ok := fwdChat["title"].(string); ok {
			msg.ForwardFrom = title
		}
	}

	// Attachments
	msg.Attachments = b.extractAttachments(m)

	msg.Status = MessageStatusSent
	return msg
}

func (b *BaleCore) mapCallbackQuery(cb map[string]interface{}) Message {
	msg := Message{
		Platform: "bale",
		Status:   MessageStatusSent,
	}

	// The callback_query has an "id" field and optional "message"
	if cbMsg, ok := cb["message"].(map[string]interface{}); ok {
		msg = b.mapMessage(cbMsg)
	}

	// Override text with callback data
	if data, ok := cb["data"].(string); ok {
		msg.Text = data
	}

	// Sender is from the callback query, not the original message
	if from, ok := cb["from"].(map[string]interface{}); ok {
		msg.SenderID = strconv.FormatInt(jsonInt64(from, "id"), 10)
		msg.SenderName = b.buildDisplayName(from)
	}

	return msg
}

func (b *BaleCore) mapUser(u map[string]interface{}) *User {
	user := &User{
		Platform: "bale",
	}

	user.ID = strconv.FormatInt(jsonInt64(u, "id"), 10)
	user.DisplayName = b.buildDisplayName(u)
	if username, ok := u["username"].(string); ok {
		user.Username = username
	}
	if isBot, ok := u["is_bot"].(bool); ok {
		user.IsBot = isBot
	}

	return user
}

func (b *BaleCore) mapChatToUser(chat map[string]interface{}) *User {
	user := &User{
		Platform: "bale",
	}

	user.ID = strconv.FormatInt(jsonInt64(chat, "id"), 10)
	user.DisplayName = b.buildDisplayName(chat)
	if username, ok := chat["username"].(string); ok {
		user.Username = username
	}
	if bio, ok := chat["bio"].(string); ok {
		// Store bio in display name if no name set
		_ = bio
	}

	return user
}

func (b *BaleCore) extractAttachments(m map[string]interface{}) []FileRef {
	var attachments []FileRef

	// Photo (array of PhotoSize, pick largest)
	if photos, ok := m["photo"].([]interface{}); ok && len(photos) > 0 {
		largest := photos[len(photos)-1].(map[string]interface{})
		attachments = append(attachments, FileRef{
			ID:       jsonString(largest, "file_id"),
			Name:     "photo.jpg",
			MimeType: "image/jpeg",
			Size:     jsonInt64(largest, "file_size"),
		})
	}

	// Document
	if doc, ok := m["document"].(map[string]interface{}); ok {
		attachments = append(attachments, FileRef{
			ID:       jsonString(doc, "file_id"),
			Name:     jsonString(doc, "file_name"),
			MimeType: jsonString(doc, "mime_type"),
			Size:     jsonInt64(doc, "file_size"),
		})
	}

	// Audio
	if audio, ok := m["audio"].(map[string]interface{}); ok {
		name := jsonString(audio, "file_name")
		if name == "" {
			name = jsonString(audio, "title")
		}
		if name == "" {
			name = "audio"
		}
		attachments = append(attachments, FileRef{
			ID:       jsonString(audio, "file_id"),
			Name:     name,
			MimeType: jsonString(audio, "mime_type"),
			Size:     jsonInt64(audio, "file_size"),
		})
	}

	// Video
	if video, ok := m["video"].(map[string]interface{}); ok {
		name := jsonString(video, "file_name")
		if name == "" {
			name = "video.mp4"
		}
		attachments = append(attachments, FileRef{
			ID:       jsonString(video, "file_id"),
			Name:     name,
			MimeType: jsonString(video, "mime_type"),
			Size:     jsonInt64(video, "file_size"),
		})
	}

	// Voice
	if voice, ok := m["voice"].(map[string]interface{}); ok {
		attachments = append(attachments, FileRef{
			ID:       jsonString(voice, "file_id"),
			Name:     "voice.ogg",
			MimeType: "audio/ogg",
			Size:     jsonInt64(voice, "file_size"),
		})
	}

	// Animation
	if anim, ok := m["animation"].(map[string]interface{}); ok {
		name := jsonString(anim, "file_name")
		if name == "" {
			name = "animation.gif"
		}
		attachments = append(attachments, FileRef{
			ID:       jsonString(anim, "file_id"),
			Name:     name,
			MimeType: jsonString(anim, "mime_type"),
			Size:     jsonInt64(anim, "file_size"),
		})
	}

	// Sticker
	if sticker, ok := m["sticker"].(map[string]interface{}); ok {
		attachments = append(attachments, FileRef{
			ID:       jsonString(sticker, "file_id"),
			Name:     "sticker.webp",
			MimeType: "image/webp",
			Size:     jsonInt64(sticker, "file_size"),
		})
	}

	return attachments
}

func (b *BaleCore) buildDisplayName(u map[string]interface{}) string {
	first, _ := u["first_name"].(string)
	last, _ := u["last_name"].(string)
	title, _ := u["title"].(string)

	if title != "" {
		return title
	}
	name := strings.TrimSpace(first + " " + last)
	if name == "" {
		if username, ok := u["username"].(string); ok {
			return username
		}
	}
	return name
}

// --- Utility Helpers ---

// jsonInt64 extracts an integer from a JSON object (handles float64 from json.Unmarshal).
func jsonInt64(m map[string]interface{}, key string) int64 {
	if m == nil {
		return 0
	}
	switch v := m[key].(type) {
	case float64:
		return int64(v)
	case json.Number:
		n, _ := v.Int64()
		return n
	case int64:
		return v
	case int:
		return int64(v)
	case string:
		n, _ := strconv.ParseInt(v, 10, 64)
		return n
	}
	return 0
}

// jsonString extracts a string from a JSON object.
func jsonString(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	s, _ := m[key].(string)
	return s
}

// truncateText truncates text to maxLen characters.
func truncateText(text string, maxLen int) string {
	runes := []rune(text)
	if len(runes) <= maxLen {
		return text
	}
	return string(runes[:maxLen]) + "..."
}

// progressReader wraps an io.Reader to report progress.
type progressReader struct {
	reader     io.Reader
	total      int64
	read       int64
	onProgress func(sent, total int64)
}

func (pr *progressReader) Read(p []byte) (int, error) {
	n, err := pr.reader.Read(p)
	pr.read += int64(n)
	if pr.onProgress != nil {
		pr.onProgress(pr.read, pr.total)
	}
	return n, err
}

// =============================================================================
// BALE USER MODE — gRPC-Web/Protobuf over WebSocket
// Protocol reverse-engineered from aiobale + Balethon (2026-04-06)
// =============================================================================

// --- Protobuf Wire Format Codec ---
// Minimal encoder/decoder for protobuf wire format.
// Fields are keyed by field number (string). Values can be:
//   int/int64/uint64 → varint (wire type 0)
//   bool → varint 0/1 (wire type 0)
//   string → length-delimited (wire type 2)
//   []byte → length-delimited (wire type 2)
//   map[string]interface{} → nested message, length-delimited (wire type 2)
//   []interface{} → repeated field (each element encoded with same field number)
//   pbFixed64 → fixed 64-bit (wire type 1)

// pbFixed64 wraps a uint64 to encode as fixed64 (wire type 1) instead of varint.
type pbFixed64 uint64

// pbUint32 wraps a uint32 to encode as fixed32 (wire type 5).
type pbUint32 uint32

func pbEncodeVarint(n uint64) []byte {
	var buf [10]byte
	i := 0
	for n >= 0x80 {
		buf[i] = byte(n) | 0x80
		n >>= 7
		i++
	}
	buf[i] = byte(n)
	return buf[:i+1]
}

func pbDecodeVarint(data []byte, pos int) (uint64, int) {
	var result uint64
	shift := 0
	for i := pos; i < len(data); i++ {
		b := data[i]
		result |= uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			return result, i + 1 - pos
		}
		shift += 7
	}
	return result, len(data) - pos
}

func pbEncodeTag(fieldNum int, wireType int) []byte {
	return pbEncodeVarint(uint64(fieldNum<<3 | wireType))
}

func pbEncodeField(fieldNum int, val interface{}) []byte {
	switch v := val.(type) {
	case bool:
		tag := pbEncodeTag(fieldNum, 0)
		if v {
			return append(tag, 1)
		}
		return append(tag, 0)
	case int:
		tag := pbEncodeTag(fieldNum, 0)
		return append(tag, pbEncodeVarint(uint64(v))...)
	case int32:
		tag := pbEncodeTag(fieldNum, 0)
		return append(tag, pbEncodeVarint(uint64(v))...)
	case int64:
		tag := pbEncodeTag(fieldNum, 0)
		return append(tag, pbEncodeVarint(uint64(v))...)
	case uint64:
		tag := pbEncodeTag(fieldNum, 0)
		return append(tag, pbEncodeVarint(v)...)
	case pbFixed64:
		tag := pbEncodeTag(fieldNum, 1) // wire type 1 = 64-bit
		buf := make([]byte, 8)
		binary.LittleEndian.PutUint64(buf, uint64(v))
		return append(tag, buf...)
	case pbUint32:
		tag := pbEncodeTag(fieldNum, 5) // wire type 5 = 32-bit
		buf := make([]byte, 4)
		binary.LittleEndian.PutUint32(buf, uint32(v))
		return append(tag, buf...)
	case string:
		tag := pbEncodeTag(fieldNum, 2)
		data := []byte(v)
		tag = append(tag, pbEncodeVarint(uint64(len(data)))...)
		return append(tag, data...)
	case []byte:
		tag := pbEncodeTag(fieldNum, 2)
		tag = append(tag, pbEncodeVarint(uint64(len(v)))...)
		return append(tag, v...)
	case map[string]interface{}:
		nested := pbEncode(v)
		tag := pbEncodeTag(fieldNum, 2)
		tag = append(tag, pbEncodeVarint(uint64(len(nested)))...)
		return append(tag, nested...)
	case []interface{}:
		var out []byte
		for _, elem := range v {
			out = append(out, pbEncodeField(fieldNum, elem)...)
		}
		return out
	}
	return nil
}

func pbEncode(fields map[string]interface{}) []byte {
	// Sort field numbers for deterministic output
	keys := make([]int, 0, len(fields))
	for k := range fields {
		n, _ := strconv.Atoi(k)
		keys = append(keys, n)
	}
	sort.Ints(keys)

	var out []byte
	for _, fieldNum := range keys {
		val := fields[strconv.Itoa(fieldNum)]
		if val == nil {
			continue
		}
		out = append(out, pbEncodeField(fieldNum, val)...)
	}
	return out
}

func pbDecode(data []byte) map[string]interface{} {
	return pbDecodeDepth(data, 0)
}

func pbDecodeDepth(data []byte, depth int) map[string]interface{} {
	result := make(map[string]interface{})
	if depth > 8 {
		return result
	}
	pos := 0
	for pos < len(data) {
		tag, n := pbDecodeVarint(data[pos:], 0)
		if n == 0 {
			return result
		}
		pos += n
		fieldNum := int(tag >> 3)
		wireType := int(tag & 0x7)
		key := strconv.Itoa(fieldNum)

		switch wireType {
		case 0: // varint
			val, n := pbDecodeVarint(data[pos:], 0)
			pos += n
			// Check if field already exists (repeated varint)
			if existing, ok := result[key]; ok {
				switch ev := existing.(type) {
				case []interface{}:
					result[key] = append(ev, int64(val))
				default:
					result[key] = []interface{}{ev, int64(val)}
				}
			} else {
				result[key] = int64(val)
			}
		case 1: // 64-bit fixed
			if pos+8 > len(data) {
				return result
			}
			val := binary.LittleEndian.Uint64(data[pos : pos+8])
			pos += 8
			result[key] = int64(val)
		case 2: // length-delimited
			length, n := pbDecodeVarint(data[pos:], 0)
			if n == 0 || length > uint64(len(data)-pos-n) || length > 10*1024*1024 {
				return result // invalid or too large
			}
			pos += n
			end := pos + int(length)
			if end > len(data) {
				return result
			}
			payload := make([]byte, end-pos)
			copy(payload, data[pos:end])
			pos = end
			// Try to decode as nested message; if it fails, store as string/bytes.
			// IMPORTANT: also store raw bytes so pbGetString can recover strings
			// that were mis-decoded as nested messages (protobuf wire type 2 is
			// ambiguous between strings and embedded messages).
			nested := pbTryDecodeMessageDepth(payload, depth+1)
			var value interface{}
			if nested != nil {
				// Store as nested but keep raw bytes accessible via __raw_N key
				value = nested
				result["__raw_"+key] = payload
			} else {
				// Could be string or bytes — store as string if valid UTF-8
				value = string(payload)
			}
			// Handle repeated fields
			if existing, ok := result[key]; ok {
				switch ev := existing.(type) {
				case []interface{}:
					result[key] = append(ev, value)
				default:
					result[key] = []interface{}{ev, value}
				}
			} else {
				result[key] = value
			}
		case 5: // 32-bit fixed
			if pos+4 > len(data) {
				return result
			}
			val := binary.LittleEndian.Uint32(data[pos : pos+4])
			pos += 4
			result[key] = int64(val)
		default:
			return result // unknown wire type, stop
		}
	}
	return result
}

// pbTryDecodeMessage attempts to decode bytes as a protobuf message.
// Returns nil if the bytes don't look like valid protobuf.
func pbTryDecodeMessage(data []byte) map[string]interface{} {
	return pbTryDecodeMessageDepth(data, 0)
}

func pbTryDecodeMessageDepth(data []byte, depth int) map[string]interface{} {
	if len(data) == 0 || depth > 8 {
		return nil
	}
	// Quick heuristic: first byte should be a valid tag (field 1-536870911, wire type 0-5)
	tag, n := pbDecodeVarint(data, 0)
	wireType := tag & 0x7
	fieldNum := tag >> 3
	if n == 0 || fieldNum == 0 || fieldNum > 10000 || wireType > 5 || wireType == 3 || wireType == 4 {
		return nil
	}
	// Try full decode
	result := pbDecodeDepth(data, depth)
	if len(result) == 0 {
		return nil
	}
	return result
}

// pbGetInt64 extracts an int64 from a decoded protobuf field map.
func pbGetInt64(m map[string]interface{}, field string) int64 {
	if m == nil {
		return 0
	}
	switch v := m[field].(type) {
	case int64:
		return v
	case float64:
		return int64(v)
	case int:
		return int64(v)
	}
	return 0
}

// pbGetString extracts a string from a decoded protobuf field map.
// If the field was mis-decoded as a nested message (protobuf wire type 2
// ambiguity), falls back to the raw bytes stored in __raw_N.
func pbGetString(m map[string]interface{}, field string) string {
	if m == nil {
		return ""
	}
	switch v := m[field].(type) {
	case string:
		return v
	case []byte:
		return string(v)
	case map[string]interface{}:
		// Field was decoded as nested message — try raw bytes fallback
		if raw, ok := m["__raw_"+field]; ok {
			switch r := raw.(type) {
			case []byte:
				return string(r)
			case string:
				return r
			}
		}
	}
	return ""
}

// pbGetMsg extracts a nested message (map) from a decoded protobuf field map.
func pbGetMsg(m map[string]interface{}, field string) map[string]interface{} {
	if m == nil {
		return nil
	}
	if sub, ok := m[field].(map[string]interface{}); ok {
		return sub
	}
	return nil
}

// pbGetList extracts a repeated field as a slice.
func pbGetList(m map[string]interface{}, field string) []interface{} {
	if m == nil {
		return nil
	}
	switch v := m[field].(type) {
	case []interface{}:
		return v
	case nil:
		return nil
	default:
		return []interface{}{v}
	}
}

// --- gRPC-Web Framing ---

func grpcWebEncode(payload []byte) []byte {
	header := make([]byte, 5)
	header[0] = 0x00 // not compressed
	binary.BigEndian.PutUint32(header[1:], uint32(len(payload)))
	return append(header, payload...)
}

func grpcWebDecode(data []byte) []byte {
	if len(data) < 5 {
		return data
	}
	// Strip 5-byte header
	payload := data[5:]
	// Strip grpc-status trailer if present
	if idx := bytes.Index(payload, []byte("grpc-status")); idx != -1 {
		payload = payload[:idx]
	}
	return payload
}

// --- Bale User Mode Services ---

const (
	baleServiceAuth      = "bale.auth.v1.Auth"
	baleServiceMessaging = "bale.messaging.v2.Messaging"
	baleServiceUsers     = "bale.users.v1.Users"
	baleServiceGroups    = "bale.groups.v1.Groups"
	baleServiceFiles     = "ai.bale.server.Files"
	baleServicePresence  = "bale.presence.v1.Presence"
	baleServiceConfigs   = "bale.v1.Configs"
	baleServiceAbacus    = "bale.abacus.v1.Abacus"

	// New services from web.bale.ai v4.17.0 JS scrape (2026-04-13)
	baleServicePoll          = "bale.poll.v1.Poll"
	baleServiceSearch        = "bale.search.v1.Search"
	baleServiceStory         = "bale.story.v1.Story"
	baleServiceMsgStream     = "bale.message_stream.v1.MessageStream"
	baleServiceScheduler     = "bale.schedule.v1.Scheduler"
	baleServiceTLDR          = "bale.tldr.v1.TLDR"
	baleServiceAnonContact   = "bale.anonymous_contact.v1.AnonymousContact"
	baleServiceMaviz         = "bale.maviz.v1.MavizStream"
	baleServiceFalake        = "bale.falake.v1.Falake"
	baleServiceNegah         = "bale.negah.v1.Negah"
	baleServiceLLMAuth       = "bale.llm_auth.v1.LLMAuthService"
	baleServiceAppzar        = "bale.appzar.v1.Appzar"
	baleServiceTopPeer       = "bale.top_peer.v1.TopPeer"
	baleServiceOrgs          = "bale.organizations.v1.Organizations"
	baleServiceRecommender   = "bale.recommender.v1.Recommender"
	baleServiceSharedMedia   = "bale.shared_media.v1.SharedMediaService"
	baleServiceKetf          = "bale.ketf.v1.Ketf"
	baleServiceTuringAI      = "bale.turing.v1.AI"

	baleWSURL   = "wss://next-ws.bale.ai/ws/"
	balePostURL = "https://next-ws.bale.ai"

	baleAppVersion    = "113466"
	baleBrowserType   = "1"
	baleBrowserVer    = 3471765337684194354
	baleOSType        = "3"
	baleUserAgent     = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
)

// Peer type constants (ExPeerType enum)
const (
	balePeerPrivate    = 1
	balePeerGroup      = 2
	balePeerChannel    = 3
	balePeerBot        = 4
	balePeerSupergroup = 5
)

// --- WebSocket Client ---

func (b *BaleCore) wsConnect() error {
	if b.userToken == "" {
		return fmt.Errorf("%w: no user token", ErrAuth)
	}

	ctx, cancel := context.WithCancel(b.ctx)
	b.wsCtx = ctx
	b.wsCancel = cancel
	b.wsSessionID = fmt.Sprintf("%d", time.Now().UnixMilli())
	b.wsPending = make(map[int64]chan map[string]interface{})
	b.wsIndex = 1

	headers := http.Header{}
	headers.Set("Cookie", "access_token="+b.userToken)
	headers.Set("User-Agent", baleUserAgent)
	headers.Set("Origin", "https://web.bale.ai")

	conn, _, err := websocket.Dial(ctx, baleWSURL, &websocket.DialOptions{
		HTTPClient: newBaleHTTPClient(30 * time.Second),
		HTTPHeader: headers,
	})
	if err != nil {
		cancel()
		return fmt.Errorf("%w: websocket dial: %v", ErrNetwork, err)
	}
	conn.SetReadLimit(4 * 1024 * 1024) // 4MB max message size
	b.wsConn = conn

	// Start receive loop and ping loop
	b.wg.Add(2)
	go b.wsRecvLoop()
	go b.wsPingLoop()

	// Send initial handshake: Request{handshake: {1: 1, 2: 1}} (authorized=1, ready=1)
	handshake := pbEncode(map[string]interface{}{
		"3": map[string]interface{}{
			"1": int64(1), // authorized
			"2": int64(1), // ready
		},
	})
	b.wsConn.Write(ctx, websocket.MessageBinary, handshake)

	// Set online
	go func() {
		time.Sleep(500 * time.Millisecond)
		b.UserSetOnline(true, 300)
	}()

	return nil
}

func (b *BaleCore) wsRecvLoop() {
	defer b.wg.Done()
	for {
		_, data, err := b.wsConn.Read(b.wsCtx)
		if err != nil {
			if b.wsCtx.Err() != nil {
				return // context cancelled, shutting down
			}
			// Connection lost — exponential backoff reconnect
			b.fireConnState("disconnected")
			backoff := 3 * time.Second
			const maxBackoff = 60 * time.Second
			const maxRetries = 10
			for attempt := 0; attempt < maxRetries; attempt++ {
				if b.ctx.Err() != nil {
					return // main context cancelled
				}
				b.fireConnState("reconnecting")
				time.Sleep(backoff)
				if err := b.wsConnect(); err == nil {
					b.fireConnState("connected")
					return // reconnected, new loop started
				}
				backoff *= 2
				if backoff > maxBackoff {
					backoff = maxBackoff
				}
			}
			// All retries exhausted
			b.fireConnState("disconnected")
			return
		}
		go b.wsHandleMessage(data)
	}
}

func (b *BaleCore) fireConnState(state string) {
	b.updateMu.RLock()
	handlers := make([]func(Update), len(b.updateHandlers))
	copy(handlers, b.updateHandlers)
	b.updateMu.RUnlock()
	u := Update{Type: UpdateConnectivity, ConnState: state, Platform: "bale"}
	for _, h := range handlers {
		go h(u)
	}
}

func (b *BaleCore) wsHandleMessage(data []byte) {
	decoded := pbDecode(data)

	// Check for response (field 1 = ws_response)
	if wsResp := pbGetMsg(decoded, "1"); wsResp != nil {
		idx := pbGetInt64(wsResp, "3") // index
		b.wsPendMu.Lock()
		ch, ok := b.wsPending[idx]
		if ok {
			delete(b.wsPending, idx)
		}
		b.wsPendMu.Unlock()
		if ok {
			ch <- wsResp
		}
		return
	}

	// Check for pong (field 4 in aiobale Response)
	// Balethon doesn't have explicit pong handling, just ignore

	// Check for update (field 2 = ws_update)
	if wsUpdate := pbGetMsg(decoded, "2"); wsUpdate != nil {
		b.wsHandleUpdate(wsUpdate)
		return
	}
}

func (b *BaleCore) wsHandleUpdate(wsUpdate map[string]interface{}) {
	// ws_update → field 1: update → field 1: composed_update
	update := pbGetMsg(wsUpdate, "1")
	if update == nil {
		return
	}
	composed := pbGetMsg(update, "1")
	if composed == nil {
		return
	}

	b.updateMu.RLock()
	handlers := make([]func(Update), len(b.updateHandlers))
	copy(handlers, b.updateHandlers)
	b.updateMu.RUnlock()

	if len(handlers) == 0 {
		return
	}

	dispatch := func(u Update) {
		for _, h := range handlers {
			go h(u)
		}
	}

	// Field 55 = new message
	if msgUpdate := pbGetMsg(composed, "55"); msgUpdate != nil {
		msg := b.mapUserMessage(msgUpdate)
		dispatch(Update{Type: UpdateNewMessage, ChatID: msg.ChatID, Message: &msg, Platform: "bale"})
	}

	// Field 162 = message edited (UpdatedMessage)
	if editUpdate := pbGetMsg(composed, "162"); editUpdate != nil {
		msg := b.mapUpdatedMessage(editUpdate)
		dispatch(Update{Type: UpdateEditMessage, ChatID: msg.ChatID, Message: &msg, Platform: "bale"})
	}

	// Field 46 = message deleted (SelectedMessages)
	if delUpdate := pbGetMsg(composed, "46"); delUpdate != nil {
		chatID := ""
		if peer := pbGetMsg(delUpdate, "1"); peer != nil {
			peerID := pbGetInt64(peer, "2")
			peerType := pbGetInt64(peer, "1")
			chatID = fmt.Sprintf("%d|%d", peerID, peerType)
		}
		dispatch(Update{Type: UpdateDeleteMessage, ChatID: chatID, Platform: "bale"})
	}

	// Field 4 = message sent confirmation (InfoMessage)
	// Field 47 = chat cleared
	// Field 48 = chat deleted
}

func (b *BaleCore) wsPingLoop() {
	defer b.wg.Done()
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-b.wsCtx.Done():
			return
		case <-ticker.C:
			b.wsPingID++
			// KeepAliveRequest: field 2 = KeepAlive{field 1 = value}
			ping := pbEncode(map[string]interface{}{
				"2": map[string]interface{}{
					"1": b.wsPingID,
				},
			})
			b.wsConn.Write(b.wsCtx, websocket.MessageBinary, ping)
		}
	}
}

// wsSend sends a request over WebSocket and waits for the correlated response.
func (b *BaleCore) wsSend(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	b.wsPendMu.Lock()
	idx := b.wsIndex
	b.wsIndex++
	ch := make(chan map[string]interface{}, 1)
	b.wsPending[idx] = ch
	b.wsPendMu.Unlock()

	// Encode inner payload
	var payloadBytes []byte
	if payload != nil {
		payloadBytes = pbEncode(payload)
	}

	// Build metadata
	meta := b.buildMetadata()

	// Build WsRequest: field 1 of Request
	wsReq := map[string]interface{}{
		"1": service,
		"2": method,
		"3": payloadBytes,
		"4": meta,
		"5": idx,
	}

	// Build Request: field 1 = ws_request
	request := pbEncode(map[string]interface{}{
		"1": wsReq,
	})

	if err := b.wsConn.Write(b.wsCtx, websocket.MessageBinary, request); err != nil {
		b.wsPendMu.Lock()
		delete(b.wsPending, idx)
		b.wsPendMu.Unlock()
		return nil, fmt.Errorf("%w: ws write: %v", ErrNetwork, err)
	}

	// Wait for response
	select {
	case resp := <-ch:
		// Check for error (field 1 = error bytes)
		if errBytes := pbGetString(resp, "1"); errBytes != "" {
			return nil, fmt.Errorf("bale RPC error: %s", errBytes)
		}
		// Field 2 = response bytes → decode as protobuf
		if respData := resp["2"]; respData != nil {
			switch v := respData.(type) {
			case string:
				return pbDecode([]byte(v)), nil
			case []byte:
				return pbDecode(v), nil
			case map[string]interface{}:
				return v, nil
			}
		}
		return resp, nil
	case <-time.After(20 * time.Second):
		b.wsPendMu.Lock()
		delete(b.wsPending, idx)
		b.wsPendMu.Unlock()
		return nil, fmt.Errorf("%w: RPC timeout for %s/%s", ErrNetwork, service, method)
	case <-b.wsCtx.Done():
		return nil, fmt.Errorf("%w: connection closed", ErrNetwork)
	}
}

// wsPost sends a gRPC-Web HTTP POST request (used for auth before WebSocket is established).
func (b *BaleCore) wsPost(service, method string, payload map[string]interface{}, token string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/%s/%s", balePostURL, service, method)

	payloadBytes := pbEncode(payload)
	body := grpcWebEncode(payloadBytes)

	req, err := http.NewRequestWithContext(b.ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/grpc-web+proto")
	req.Header.Set("User-Agent", baleUserAgent)
	req.Header.Set("Origin", "https://web.bale.ai")
	req.Header.Set("App_version", baleAppVersion)
	req.Header.Set("Browser_type", baleBrowserType)
	req.Header.Set("Os_type", baleOSType)
	if token != "" {
		req.Header.Set("Cookie", "access_token="+token)
	}

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNetwork, err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("%w: read response: %v", ErrNetwork, err)
	}

	// Check for gRPC error in headers
	if grpcMsg := resp.Header.Get("grpc-message"); grpcMsg != "" {
		return nil, fmt.Errorf("bale gRPC error: %s", grpcMsg)
	}

	decoded := grpcWebDecode(respBody)
	if len(decoded) == 0 {
		return map[string]interface{}{}, nil
	}
	return pbDecode(decoded), nil
}

func (b *BaleCore) buildMetadata() map[string]interface{} {
	// Metadata: field 1 = repeated MetadataKeyValues
	// aiobale sends both plain and mt_ prefixed versions
	kvs := []interface{}{
		map[string]interface{}{"1": "app_version", "2": map[string]interface{}{"1": baleAppVersion}},
		map[string]interface{}{"1": "browser_type", "2": map[string]interface{}{"1": baleBrowserType}},
		map[string]interface{}{"1": "browser_version", "2": map[string]interface{}{"2": map[string]interface{}{"6": pbFixed64(baleBrowserVer)}}},
		map[string]interface{}{"1": "os_type", "2": map[string]interface{}{"1": baleOSType}},
		map[string]interface{}{"1": "session_id", "2": map[string]interface{}{"1": b.wsSessionID}},
		map[string]interface{}{"1": "mt_app_version", "2": map[string]interface{}{"1": baleAppVersion}},
		map[string]interface{}{"1": "mt_browser_type", "2": map[string]interface{}{"1": baleBrowserType}},
		map[string]interface{}{"1": "mt_browser_version", "2": map[string]interface{}{"1": "138.0.0.0"}},
		map[string]interface{}{"1": "mt_os_type", "2": map[string]interface{}{"1": baleOSType}},
		map[string]interface{}{"1": "mt_session_id", "2": map[string]interface{}{"1": b.wsSessionID}},
	}
	return map[string]interface{}{"1": kvs}
}

// --- User Auth Flow ---

func (b *BaleCore) authUser(cfg AuthConfig) error {
	// Try loading existing session
	if err := b.loadSession(); err == nil && b.userToken != "" {
		// Verify token is still valid by connecting WebSocket
		if err := b.wsConnect(); err == nil {
			b.isBot = false
			b.authed = true
			return nil
		}
		// Token expired, need re-auth
		b.userToken = ""
	}

	phone := cfg.Phone
	if phone == "" {
		return fmt.Errorf("%w: phone number is required for user auth", ErrInvalidInput)
	}

	// Parse phone to int
	phoneClean := strings.ReplaceAll(strings.ReplaceAll(phone, "+", ""), " ", "")
	phoneInt, err := strconv.ParseInt(phoneClean, 10, 64)
	if err != nil {
		return fmt.Errorf("%w: invalid phone number: %v", ErrInvalidInput, err)
	}

	// Step 1: StartPhoneAuth
	// Field numbers from aiobale: 1=phone, 2=app_id, 3=app_key, 4=device_hash,
	// 5=device_title, 9=send_code_type (NOT 8!), 10=options (REQUIRED: {"0":1})
	deviceHash := fmt.Sprintf("uniclient_%d", rand.Int63())
	startReq := map[string]interface{}{
		"1":  phoneInt,                                                                    // phone_number
		"2":  int64(4),                                                                    // app_id
		"3":  "C28D46DC4C3A7A26564BFCC48B929086A95C93C98E789A19847BEE8627DE4E7D",          // app_key (api_key)
		"4":  deviceHash,                                                                  // device_hash
		"5":  "Chrome_138.0.0.0, Windows",                                                 // device_title
		"9":  int64(3),                                // send_code_type = SMS
		"10": map[string]interface{}{"0": int64(1)},   // options (required!)
	}

	startResp, err := b.wsPost(baleServiceAuth, "StartPhoneAuth", startReq, "")
	if err != nil {
		return fmt.Errorf("%w: StartPhoneAuth: %v", ErrAuth, err)
	}

	transactionHash := pbGetString(startResp, "1")
	if transactionHash == "" {
		return fmt.Errorf("%w: no transaction_hash in StartPhoneAuth response: %v", ErrAuth, startResp)
	}

	// Step 2: Get OTP from user
	otp := cfg.OTP
	if otp == "" {
		// Poll for OTP from file (same pattern as Telegram)
		otpPath := "../../auth/otp_code.txt"
		os.Remove(otpPath) // Clear any stale OTP
		fmt.Fprintf(os.Stderr, "bale: OTP sent to %s. Write code to %s\n", phone, otpPath)

		for i := 0; i < 120; i++ { // wait up to 2 minutes
			time.Sleep(1 * time.Second)
			data, err := os.ReadFile(otpPath)
			if err == nil && len(strings.TrimSpace(string(data))) > 0 {
				otp = strings.TrimSpace(string(data))
				os.Remove(otpPath)
				break
			}
		}
		if otp == "" {
			return fmt.Errorf("%w: OTP not provided within timeout", ErrAuth)
		}
	}

	// Step 3: ValidateCode
	validateReq := map[string]interface{}{
		"1": transactionHash, // transaction_hash
		"2": otp,             // code
		"3": map[string]interface{}{"1": int64(1)}, // is_jwt = {1: 1}
	}

	validateResp, err := b.wsPost(baleServiceAuth, "ValidateCode", validateReq, "")
	if err != nil {
		// Check for PASSWORD_NEEDED (error code 4)
		if strings.Contains(err.Error(), "4") || strings.Contains(err.Error(), "PASSWORD") {
			// 2FA required
			pwd := cfg.Password2F
			if pwd == "" {
				return fmt.Errorf("%w: 2FA password required but not provided", ErrAuth)
			}
			validateResp, err = b.UserValidatePassword(transactionHash, pwd)
			if err != nil {
				return fmt.Errorf("%w: ValidatePassword: %v", ErrAuth, err)
			}
		} else {
			return fmt.Errorf("%w: ValidateCode: %v", ErrAuth, err)
		}
	}

	// Extract JWT token from response
	// aiobale: ValidateCodeResponse.jwt is a StringValue at field 4
	// JWT is wrapped: field 4 → StringValue → field 1 = actual token string
	var token string

	// Try field 4 (jwt as StringValue)
	if jwtField := pbGetMsg(validateResp, "4"); jwtField != nil {
		token = pbGetString(jwtField, "1") // StringValue.value
	}
	// Fallback: try field 1 directly
	if token == "" {
		token = pbGetString(validateResp, "1")
	}
	// Fallback: try field 1 as nested
	if token == "" {
		if nested := pbGetMsg(validateResp, "1"); nested != nil {
			token = pbGetString(nested, "1")
		}
	}
	if token == "" {
		return fmt.Errorf("%w: no token in ValidateCode response: %v", ErrAuth, validateResp)
	}

	// Extract user ID from field 2 (UserAuth)
	if userAuth := pbGetMsg(validateResp, "2"); userAuth != nil {
		b.userID = pbGetInt64(userAuth, "1") // UserAuth.id
	}

	b.userToken = token
	b.userPhone = phone
	b.isBot = false
	b.authed = true

	// Connect WebSocket with the new token
	if err := b.wsConnect(); err != nil {
		return fmt.Errorf("websocket connect after auth: %w", err)
	}

	// Save session
	if err := b.saveSession(); err != nil {
		fmt.Fprintf(os.Stderr, "bale: warning: could not save session: %v\n", err)
	}

	return nil
}

// --- User Mode Core Interface Methods ---
// These override the bot-mode methods when b.isBot == false

// userSend is the common pattern for user-mode API calls.
func (b *BaleCore) userSend(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	if b.wsConn == nil {
		return nil, fmt.Errorf("%w: not connected", ErrNetwork)
	}
	return b.wsSend(service, method, payload)
}

// baleRID generates a random request ID (16-digit number).
func baleRID() int64 {
	return rand.Int63n(9000000000000000) + 1000000000000000
}

// balePeer builds a Peer protobuf: {1: type, 2: id}
func balePeer(peerType int, peerID int64) map[string]interface{} {
	return map[string]interface{}{"1": int64(peerType), "2": peerID}
}

// baleShortPeer builds a ShortPeer: {1: id, 2: access_hash (default 1)}
func baleShortPeer(id int64) map[string]interface{} {
	return map[string]interface{}{"1": id, "2": int64(1)}
}

// baleInfoPeer builds an InfoPeer: {1: id, 2: type}
func baleInfoPeer(id int64, peerType int) map[string]interface{} {
	return map[string]interface{}{"1": id, "2": int64(peerType)}
}

// baleGroupOutPeer builds a GroupOutPeer (alias for ShortPeer): {1: group_id, 2: access_hash}
func baleGroupOutPeer(groupID int64) map[string]interface{} {
	return baleShortPeer(groupID)
}

// baleUserOutPeer builds a UserOutPeer (alias for ShortPeer): {1: uid, 2: access_hash}
func baleUserOutPeer(uid int64) map[string]interface{} {
	return baleShortPeer(uid)
}

// parseMsgIDWithDate parses "rid:dateMs:mid" or "rid:dateMs" or just "rid".
// Returns (rid, dateMs).
func parseMsgIDWithDate(msgID string) (int64, int64) {
	parts := strings.Split(msgID, ":")
	if len(parts) >= 2 {
		rid, _ := strconv.ParseInt(parts[0], 10, 64)
		dateMs, _ := strconv.ParseInt(parts[1], 10, 64)
		return rid, dateMs
	}
	rid, _ := strconv.ParseInt(msgID, 10, 64)
	return rid, 0
}

// parseMsgIDFull parses "rid:dateMs:mid" returning all three parts.
func parseMsgIDFull(msgID string) (rid, dateMs, mid int64) {
	parts := strings.Split(msgID, ":")
	if len(parts) >= 1 {
		rid, _ = strconv.ParseInt(parts[0], 10, 64)
	}
	if len(parts) >= 2 {
		dateMs, _ = strconv.ParseInt(parts[1], 10, 64)
	}
	if len(parts) >= 3 {
		mid, _ = strconv.ParseInt(parts[2], 10, 64)
	}
	return
}

// parsePeerID parses "peerID|peerType" or just numeric chatID.
func parsePeerID(chatID string) (int64, int) {
	if parts := strings.SplitN(chatID, "|", 2); len(parts) == 2 {
		id, _ := strconv.ParseInt(parts[0], 10, 64)
		pt, _ := strconv.Atoi(parts[1])
		return id, pt
	}
	id, _ := strconv.ParseInt(chatID, 10, 64)
	// Guess type: negative = group, positive = user
	if id < 0 {
		return -id, balePeerGroup
	}
	return id, balePeerPrivate
}

// --- Messaging Methods ---

// UserSendMessage sends a message in user mode.
// replyToRID and replyToDate: if both non-zero, the message is a reply.
// InfoMessage (field 5): {1: Peer, 2: message_id(RID), 3: IntValue{1: date_ms}}
func (b *BaleCore) UserSendMessage(chatID string, text string, replyToRID int64, replyToDate int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	peer := balePeer(peerType, peerID)
	payload := map[string]interface{}{
		"1": peer,
		"2": rid,
		"3": map[string]interface{}{
			"15": map[string]interface{}{"1": text},
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	if replyToRID != 0 {
		replyInfo := map[string]interface{}{
			"1": peer,
			"2": replyToRID,
		}
		if replyToDate != 0 {
			replyInfo["3"] = map[string]interface{}{"1": replyToDate} // IntValue
		}
		payload["5"] = replyInfo
	}
	resp, err := b.userSend(baleServiceMessaging, "SendMessage", payload)
	if resp != nil {
		resp["__rid"] = rid // Stash our rid for the caller
	}
	return resp, err
}

// UserUpdateMessage edits a message in user mode.
// Spec: {1: Peer, 2: message_id, 3: MessageContent} — only 3 fields.
func (b *BaleCore) UserUpdateMessage(chatID string, msgRID int64, dateMs int64, newText string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": msgRID,
		"3": map[string]interface{}{
			"15": map[string]interface{}{"1": newText},
		},
	}
	return b.userSend(baleServiceMessaging, "UpdateMessage", payload)
}

// UserDeleteMessage deletes messages in user mode.
// Spec: {1: Peer, 2: repeated int message_ids, 3: IntListValue{1: [dates]}, 4: IntValue{1: just_me}}
// All fields are required per aiobale.
func (b *BaleCore) UserDeleteMessage(chatID string, rids []int64, dates []int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	ridList := make([]interface{}, len(rids))
	for i, r := range rids {
		ridList[i] = r
	}
	dateList := make([]interface{}, len(dates))
	for i, d := range dates {
		dateList[i] = d
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": ridList,
		"3": map[string]interface{}{"1": dateList}, // IntListValue
		"4": map[string]interface{}{"1": int64(0)}, // IntValue: just_me=false
	}
	return b.userSend(baleServiceMessaging, "DeleteMessage", payload)
}

// UserForwardMessages forwards messages in user mode.
// Spec: {1: Peer(target), 2: repeated int(NEW random IDs), 3: repeated InfoMessage(forwarded_messages)}
func (b *BaleCore) UserForwardMessages(toChatID string, fromPeer map[string]interface{}, rids []int64, dates []int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(toChatID)
	// Field 2: new random IDs for each forwarded message (NOT the originals)
	newIDs := make([]interface{}, len(rids))
	for i := range rids {
		newIDs[i] = baleRID()
	}
	// Field 3: InfoMessage for each original message
	var fwdMsgs []interface{}
	for i, r := range rids {
		fwd := map[string]interface{}{
			"1": fromPeer, // Peer of original
			"2": r,        // original message_id
		}
		if i < len(dates) {
			fwd["3"] = map[string]interface{}{"1": dates[i]} // IntValue{date}
		}
		fwdMsgs = append(fwdMsgs, fwd)
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID), // target peer
		"2": newIDs,                     // new IDs for forwarded copies
		"3": fwdMsgs,                    // InfoMessage list
	}
	return b.userSend(baleServiceMessaging, "ForwardMessages", payload)
}

// UserLoadHistory loads message history.
// load_mode: 1=FORWARD, 2=BACKWARD, 3=BOTH. offset_date: -1 for latest.
func (b *BaleCore) UserLoadHistory(chatID string, date int64, limit int, loadMode int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": date, // 0 works as "latest" despite spec saying -1
		"4": int64(loadMode),
		"5": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadHistory", payload)
}

// UserLoadDialogs loads the dialog list.
// Fields: 1=offset_date (0 for latest), 2=limit, 5=exclude_pinned (NOT 3 or 4!)
func (b *BaleCore) UserLoadDialogs(offsetDate int64, limit int) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": offsetDate,
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadDialogs", payload)
}

// UserMessageRead marks messages as read.
func (b *BaleCore) UserMessageRead(chatID string, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": date,
	}
	return b.userSend(baleServiceMessaging, "MessageRead", payload)
}

// UserPinMessage pins a message. Uses DM pin (Messaging) for private, Group pin (Groups) for groups.
func (b *BaleCore) UserPinMessage(chatID string, msgRID int64, date int64, mid int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	if peerType == balePeerGroup || peerType == balePeerSupergroup || peerType == balePeerChannel {
		// Group pin: bale.groups.v1.Groups/PinMessage {2: ShortPeer{1: internalID}, 3: date, 4: rid}
		// Groups service uses internal group ID (from GetFullGroup field 1), NOT the peer ID
		internalID, err := b.resolveGroupInternalID(peerID)
		if err != nil {
			return nil, err
		}
		payload := map[string]interface{}{
			"2": map[string]interface{}{"1": internalID}, // ShortPeer with internal ID only
			"3": date,
			"4": msgRID,
		}
		return b.userSend(baleServiceGroups, "PinMessage", payload)
	}
	// DM pin: bale.messaging.v2.Messaging/PinMessage {1: Peer, 2: OtherMessage, 3: IntBool}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": date, "2": msgRID}, // OtherMessage
		"3": int64(0), // just_me (IntBool)
	}
	return b.userSend(baleServiceMessaging, "PinMessage", payload)
}

// UserUnPinMessages unpins messages. msgs is a list of OtherMessage {1: dateMs, 2: msgRID}.
// If all=true, unpins all (still needs at least one msg ref).
func (b *BaleCore) UserUnPinMessages(chatID string, msgs []map[string]interface{}, all bool) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	msgList := make([]interface{}, len(msgs))
	for i, m := range msgs {
		msgList[i] = m
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID), // Peer (no access_hash)
		"2": msgList,                    // repeated OtherMessage
	}
	if all {
		payload["3"] = int64(1) // IntBool
	}
	return b.userSend(baleServiceMessaging, "UnPinMessages", payload)
}

// UserLoadPinnedMessages loads pinned messages.
func (b *BaleCore) UserLoadPinnedMessages(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
	}
	return b.userSend(baleServiceMessaging, "LoadPinnedMessages", payload)
}

// UserClearChat clears all messages in a chat.
func (b *BaleCore) UserClearChat(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
	}
	return b.userSend(baleServiceMessaging, "ClearChat", payload)
}

// UserDeleteChat deletes a chat entirely.
func (b *BaleCore) UserDeleteChat(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
	}
	return b.userSend(baleServiceMessaging, "DeleteChat", payload)
}

// --- User Methods ---

// UserLoadUsers loads user info by ID.
// Spec: {1: repeated InfoPeer{1: id, 2: type}}
func (b *BaleCore) UserLoadUsers(userIDs []int64) (map[string]interface{}, error) {
	var peers []interface{}
	for _, uid := range userIDs {
		peers = append(peers, baleInfoPeer(uid, balePeerPrivate))
	}
	payload := map[string]interface{}{"1": peers}
	return b.userSend(baleServiceUsers, "LoadUsers", payload)
}

// UserLoadFullUsers loads full user info.
// Spec: {1: repeated InfoPeer{1: id, 2: type}}
func (b *BaleCore) UserLoadFullUsers(userIDs []int64) (map[string]interface{}, error) {
	var peers []interface{}
	for _, uid := range userIDs {
		peers = append(peers, baleInfoPeer(uid, balePeerPrivate))
	}
	payload := map[string]interface{}{"1": peers}
	return b.userSend(baleServiceUsers, "LoadFullUsers", payload)
}

// UserEditName changes the user's display name.
func (b *BaleCore) UserEditName(name string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditName", map[string]interface{}{"1": name})
}

// UserEditNickName changes the user's nickname (username).
// Spec: {1: StringValue{1: nick}}
func (b *BaleCore) UserEditNickName(nick string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditNickName", map[string]interface{}{"1": map[string]interface{}{"1": nick}})
}

// UserCheckNickName checks if a nickname is available.
func (b *BaleCore) UserCheckNickName(nick string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "CheckNickName", map[string]interface{}{"1": nick})
}

// UserEditAbout changes the user's about/bio.
func (b *BaleCore) UserEditAbout(about string) (map[string]interface{}, error) {
	// About is wrapped in a StringValue: {1: {1: text}}
	return b.userSend(baleServiceUsers, "EditAbout", map[string]interface{}{"1": map[string]interface{}{"1": about}})
}

// UserEditLocalName sets a local name for another user.
// Spec: {1: user_id, 2: access_hash, 3: name}
func (b *BaleCore) UserEditLocalName(userID int64, localName string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": userID,
		"2": int64(1), // access_hash (default 1)
		"3": localName,
	}
	return b.userSend(baleServiceUsers, "EditUserLocalName", payload)
}

// UserBlockUser blocks a user.
// Spec: {1: InfoPeer{1: id, 2: type}}
func (b *BaleCore) UserBlockUser(userID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "BlockUser", map[string]interface{}{"1": baleInfoPeer(userID, balePeerPrivate)})
}

// UserUnblockUser unblocks a user.
// Spec: {1: InfoPeer{1: id, 2: type}}
func (b *BaleCore) UserUnblockUser(userID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "UnblockUser", map[string]interface{}{"1": baleInfoPeer(userID, balePeerPrivate)})
}

// UserLoadBlockedUsers loads the blocked users list.
func (b *BaleCore) UserLoadBlockedUsers() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "LoadBlockedUsers", map[string]interface{}{})
}

// UserSearchContacts searches for contacts/users.
func (b *BaleCore) UserSearchContacts(query string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": query}
	return b.userSend(baleServiceUsers, "SearchContacts", payload)
}

// UserImportContacts imports phone contacts.
// UserImportContacts imports contacts. Each contact: {1: phone (int64), 2: StringValue{1: name}}.
func (b *BaleCore) UserImportContacts(contacts []map[string]interface{}) (map[string]interface{}, error) {
	var cl []interface{}
	for _, c := range contacts {
		cl = append(cl, c)
	}
	return b.userSend(baleServiceUsers, "ImportContacts", map[string]interface{}{"1": cl})
}

// UserAddContact adds a contact.
// Spec: {1: user_id, 2: type (default 1=PRIVATE)}
func (b *BaleCore) UserAddContact(userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": userID,
		"2": int64(1), // type = PRIVATE
	}
	return b.userSend(baleServiceUsers, "AddContact", payload)
}

// UserRemoveContact removes a contact.
// Spec: {1: user_id, 2: type (default 1=PRIVATE)}
func (b *BaleCore) UserRemoveContact(userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": userID,
		"2": int64(1),
	}
	return b.userSend(baleServiceUsers, "RemoveContact", payload)
}

// UserGetContacts gets the contact list.
func (b *BaleCore) UserGetContacts() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "GetContacts", map[string]interface{}{})
}

// UserResetContacts resets all contacts.
func (b *BaleCore) UserResetContacts() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "ResetContacts", map[string]interface{}{})
}

// --- Group Methods ---

// UserCreateGroup creates a new group/channel/supergroup.
// groupType: 0=GROUP, 1=CHANNEL, 2=SUPERGROUP. restriction: 0=PRIVATE, 1=PUBLIC.
// Spec: {1: random_id, 2: title, 3: repeated ShortPeer users, 6: group_type, 8: StringValue username, 9: restriction}
func (b *BaleCore) UserCreateGroup(title string, userIDs []int64) (map[string]interface{}, error) {
	return b.UserCreateGroupFull(title, userIDs, 0, "", 0)
}

func (b *BaleCore) UserCreateGroupFull(title string, userIDs []int64, groupType int, username string, restriction int) (map[string]interface{}, error) {
	var users []interface{}
	for _, uid := range userIDs {
		users = append(users, baleUserOutPeer(uid))
	}
	payload := map[string]interface{}{
		"1": baleRID(),
		"2": title,
		"6": int64(groupType),
		"9": int64(restriction),
	}
	if len(users) > 0 {
		payload["3"] = users
	}
	if username != "" {
		payload["8"] = map[string]interface{}{"1": username} // StringValue
	}
	return b.userSend(baleServiceGroups, "CreateGroup", payload)
}

// UserEditGroupTitle changes a group's title.
func (b *BaleCore) UserEditGroupTitle(groupID int64, title string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"3": title,
		"4": baleRID(),
	}
	return b.userSend(baleServiceGroups, "EditGroupTitle", payload)
}

// UserEditGroupAbout changes a group's description.
// Spec: {1: ShortPeer, 2: random_id, 3: StringValue{1: about}}
func (b *BaleCore) UserEditGroupAbout(groupID int64, about string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
		"3": map[string]interface{}{"1": about}, // StringValue
	}
	return b.userSend(baleServiceGroups, "EditGroupAbout", payload)
}

// UserInviteUsers invites users to a group.
func (b *BaleCore) UserInviteUsers(groupID int64, userIDs []int64) (map[string]interface{}, error) {
	var users []interface{}
	for _, uid := range userIDs {
		users = append(users, baleUserOutPeer(uid))
	}
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
		"3": users,
	}
	return b.userSend(baleServiceGroups, "InviteUsers", payload)
}

// UserKickUser kicks a user from a group.
// Spec: {1: ShortPeer group, 2: random_id, 3: ShortPeer user}
func (b *BaleCore) UserKickUser(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
		"3": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "KickUser", payload)
}

// UserMakeUserAdmin promotes a user to admin.
func (b *BaleCore) UserMakeUserAdmin(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "MakeUserAdmin", payload)
}

// UserRemoveUserAdmin demotes an admin.
func (b *BaleCore) UserRemoveUserAdmin(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "RemoveUserAdmin", payload)
}

// UserSetMemberPermissions sets permissions for a group member.
func (b *BaleCore) UserSetMemberPermissions(groupID int64, userID int64, perms map[string]interface{}) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
		"3": perms,
	}
	return b.userSend(baleServiceGroups, "SetMemberPermissions", payload)
}

// UserSetGroupDefaultPermissions sets default permissions for a group.
func (b *BaleCore) UserSetGroupDefaultPermissions(groupID int64, perms map[string]interface{}) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": perms,
	}
	return b.userSend(baleServiceGroups, "SetGroupDefaultPermissions", payload)
}

// UserGetMemberPermissions gets permissions for a group member.
func (b *BaleCore) UserGetMemberPermissions(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "GetMemberPermissions", payload)
}

// UserGetFullGroup gets full group info.
func (b *BaleCore) UserGetFullGroup(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetFullGroup", payload)
}

// UserLoadMembers loads group members.
func (b *BaleCore) UserLoadMembers(groupID int64, limit int, next []byte) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": int64(limit),
	}
	if len(next) > 0 {
		payload["3"] = next
	}
	return b.userSend(baleServiceGroups, "LoadMembers", payload)
}

// UserGetGroupMembersCount gets group member count.
func (b *BaleCore) UserGetGroupMembersCount(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetGroupMembersCount", payload)
}

// UserGetGroupInviteURL gets the group invite URL.
func (b *BaleCore) UserGetGroupInviteURL(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetGroupInviteURL", payload)
}

// UserRevokeInviteURL revokes and regenerates the invite URL.
func (b *BaleCore) UserRevokeInviteURL(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "RevokeInviteURL", payload)
}

// UserJoinGroup joins a group by invite token.
func (b *BaleCore) UserJoinGroup(token string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": token}
	return b.userSend(baleServiceGroups, "JoinGroup", payload)
}

// UserJoinPublicGroup joins a public group.
func (b *BaleCore) UserJoinPublicGroup(peerID int64, peerType int) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": balePeer(peerType, peerID)}
	return b.userSend(baleServiceGroups, "JoinPublicGroup", payload)
}

// UserLeaveGroup leaves a group.
func (b *BaleCore) UserLeaveGroup(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
	}
	return b.userSend(baleServiceGroups, "LeaveGroup", payload)
}

// UserGetBannedUsers gets banned users in a group.
func (b *BaleCore) UserGetBannedUsers(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetBannedUsers", payload)
}

// UserUnBanUser unbans a user from a group.
func (b *BaleCore) UserUnBanUser(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "UnBanUser", payload)
}

// UserSetRestriction sets group restriction (public/private).
// UserSetRestriction sets group visibility. 0=PRIVATE, 1=PUBLIC.
// PUBLIC requires a username string. groupID must be the internal group ID.
func (b *BaleCore) UserSetRestriction(groupID int64, restriction int, username ...string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": map[string]interface{}{"1": groupID}, // ShortPeer, no access_hash
		"2": int64(restriction),
	}
	if restriction == 1 && len(username) > 0 && username[0] != "" {
		payload["3"] = map[string]interface{}{"1": username[0]} // StringValue
	}
	return b.userSend(baleServiceGroups, "SetRestriction", payload)
}

// UserTransferOwnership transfers group ownership.
// Spec: {1: ShortPeer group, 2: new_owner_id (plain int64)}
func (b *BaleCore) UserTransferOwnership(groupID int64, newOwnerID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": newOwnerID,
	}
	return b.userSend(baleServiceGroups, "TransferOwnership", payload)
}

// UserEditChannelNick sets a channel's public username.
// Spec: {1: ShortPeer group, 2: username, 3: random_id}
func (b *BaleCore) UserEditChannelNick(groupID int64, nick string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": nick,
		"3": baleRID(),
	}
	return b.userSend(baleServiceGroups, "EditChannelNick", payload)
}

// UserGetPins gets pinned messages in a group.
// Spec: {1: ShortPeer group, 2: page, 3: limit}
func (b *BaleCore) UserGetPins(groupID int64, page int, limit int) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": int64(page),
		"3": int64(limit),
	}
	return b.userSend(baleServiceGroups, "GetPins", payload)
}

// UserRemovePin removes a specific pin.
// Spec: {1: ShortPeer group, 2: message_id, 3: date}
func (b *BaleCore) UserRemovePin(groupID int64, msgRID int64, date int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": msgRID,
		"3": date,
	}
	return b.userSend(baleServiceGroups, "RemoveSinglePin", payload)
}

// UserRemoveAllPins removes all pins.
func (b *BaleCore) UserRemoveAllPins(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "RemovePin", payload)
}

// UserGetGroupPreview gets a group preview.
func (b *BaleCore) UserGetGroupPreview(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetGroupPreview", payload)
}

// UserEditGroupAvatar sets a group avatar.
func (b *BaleCore) UserEditGroupAvatar(groupID int64, fileID int64, accessHash int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"3": map[string]interface{}{"1": fileID, "2": accessHash}, // FileLocation
		"4": baleRID(),
	}
	return b.userSend(baleServiceGroups, "EditGroupAvatar", payload)
}

// UserRemoveGroupAvatar removes a group avatar.
func (b *BaleCore) UserRemoveGroupAvatar(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"4": baleRID(),
	}
	return b.userSend(baleServiceGroups, "RemoveGroupAvatar", payload)
}

// --- File Methods ---

// UserGetFileUploadURL gets a presigned upload URL.
func (b *BaleCore) UserGetFileUploadURL(size int64, name string, mimeType string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": size,     // expected_size
		"3": b.userID, // uid
		"4": name,
		"5": mimeType,
	}
	return b.userSend(baleServiceFiles, "GetNasimFileUploadUrl", payload)
}

// UserGetFileURL gets a download URL for a file.
// Spec: {1: FileInfo{1: file_id, 2: access_hash, 3: IntValue{1: 1}(file_storage_version)}}
func (b *BaleCore) UserGetFileURL(fileID int64, accessHash int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": map[string]interface{}{
			"1": fileID,
			"2": accessHash,
			"3": map[string]interface{}{"1": int64(1)}, // file_storage_version
		},
	}
	return b.userSend(baleServiceFiles, "GetNasimFileUrl", payload)
}

// --- Presence Methods ---

// UserSetOnline sets online status.
func (b *BaleCore) UserSetOnline(isOnline bool, duration int) (map[string]interface{}, error) {
	online := int64(0)
	if isOnline {
		online = 1
	}
	payload := map[string]interface{}{
		"1": online,
		"2": int64(duration),
	}
	return b.userSend(baleServicePresence, "SetOnline", payload)
}

// UserTyping sends typing indicator.
// Spec: {1: Peer, 3: typing_type} — field 3 NOT 2!
// TypingMode: 0=UNKNOWN, 1=TEXT, 2=VOICERECORDING, 3=SENDINGVOICE, 4=SENDINGFILE, 5=SENDINGPHOTO, 6=SENDINGVIDEO
func (b *BaleCore) UserTyping(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"3": int64(1), // TEXT
	}
	return b.userSend(baleServicePresence, "Typing", payload)
}

// UserStopTyping stops typing indicator.
// Spec: {1: Peer, 2: typing_type} — field 2 NOT 3!
func (b *BaleCore) UserStopTyping(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": int64(1), // TEXT
	}
	return b.userSend(baleServicePresence, "StopTyping", payload)
}

// --- Abacus Methods (Reactions/Views) ---

// UserSetReaction sets a reaction on a message.
func (b *BaleCore) UserSetReaction(chatID string, rid int64, emoji string, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": emoji,
		"4": date,
	}
	return b.userSend(baleServiceAbacus, "MessageSetReaction", payload)
}

// UserRemoveReaction removes a reaction from a message.
func (b *BaleCore) UserRemoveReaction(chatID string, rid int64, emoji string, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": emoji,
		"4": date,
	}
	return b.userSend(baleServiceAbacus, "MessageRemoveReaction", payload)
}

// UserGetReactions gets reactions on messages.
// Spec: {1: Peer, 2: repeated OtherMessage{1:date, 2:msgID}, 3: Peer(origin), 4: repeated OtherMessage(origin)}
func (b *BaleCore) UserGetReactions(chatID string, rids []int64, dates []int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	peer := balePeer(peerType, peerID)
	var msgList []interface{}
	for i, r := range rids {
		msg := map[string]interface{}{"2": r}
		if i < len(dates) {
			msg["1"] = dates[i]
		}
		msgList = append(msgList, msg)
	}
	payload := map[string]interface{}{
		"1": peer,
		"2": msgList,
		"3": peer,
		"4": msgList,
	}
	return b.userSend(baleServiceAbacus, "GetMessagesReactions", payload)
}

// UserGetReactionsList gets detailed reaction info.
// Spec: {1: Peer, 2: message_id, 3: date, 4: emoji, 5: page, 6: limit}
func (b *BaleCore) UserGetReactionsList(chatID string, rid int64, dateMs int64, emoji string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": dateMs,
	}
	if emoji != "" {
		payload["4"] = emoji
	}
	return b.userSend(baleServiceAbacus, "GetMessageReactionsList", payload)
}

// UserGetMessageViews gets view counts for messages.
func (b *BaleCore) UserGetMessageViews(chatID string, dates []int64, rids []int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	var mids []interface{}
	for i, d := range dates {
		mid := map[string]interface{}{"1": d}
		if i < len(rids) {
			mid["2"] = rids[i]
		}
		mids = append(mids, mid)
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": mids,
		"3": true, // increment
	}
	return b.userSend(baleServiceAbacus, "GetMessagesViews", payload)
}

// --- Config Methods ---

// UserGetParameters gets platform config parameters.
func (b *BaleCore) UserGetParameters() (map[string]interface{}, error) {
	return b.userSend(baleServiceConfigs, "GetParameters", map[string]interface{}{})
}

// UserEditParameter edits a config parameter.
func (b *BaleCore) UserEditParameter(key string, value string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": key,
		"2": map[string]interface{}{"1": value}, // StringValue wrapper
	}
	return b.userSend(baleServiceConfigs, "EditParameter", payload)
}

// --- Other Methods ---

// UserSignOut signs out and invalidates the session.
func (b *BaleCore) UserSignOut() (map[string]interface{}, error) {
	return b.wsPost(baleServiceAuth, "SignOut", map[string]interface{}{}, b.userToken)
}

// UserReportContent reports inappropriate content.
// --- Auth Methods ---

// UserValidatePassword validates 2FA password during auth.
func (b *BaleCore) UserValidatePassword(transactionHash string, password string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": transactionHash,
		"2": password,
	}
	return b.wsPost(baleServiceAuth, "ValidatePassword", payload, "")
}

// UserSignUp registers a new account.
func (b *BaleCore) UserSignUp(transactionHash string, name string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": transactionHash,
		"2": name,
	}
	return b.wsPost(baleServiceAuth, "SignUp", payload, "")
}

// --- User Message Mapping ---

// mapUserMessage maps a protobuf UpdateMessage to a cores.Message.
// UpdateMessage fields: 1=peer, 2=sender_uid, 3=date(ms), 4=rid, 5=message, 7=quoted_message
func (b *BaleCore) mapUserMessage(um map[string]interface{}) Message {
	msg := Message{
		Platform: "bale",
		Status:   MessageStatusSent,
	}

	// RID + date as message ID (format: "rid:dateMs" for Bale user mode)
	rid := pbGetInt64(um, "4")
	dateMs := pbGetInt64(um, "3")
	msg.ID = fmt.Sprintf("%d:%d", rid, dateMs)

	// Peer → ChatID (format: "peerID|peerType")
	if peer := pbGetMsg(um, "1"); peer != nil {
		peerID := pbGetInt64(peer, "2")
		peerType := pbGetInt64(peer, "1")
		msg.ChatID = fmt.Sprintf("%d|%d", peerID, peerType)
	}

	// Sender
	senderUID := pbGetInt64(um, "2")
	msg.SenderID = strconv.FormatInt(senderUID, 10)

	// Date — ALL Bale timestamps are in MILLISECONDS
	if dateMs > 1e12 {
		msg.Timestamp = time.UnixMilli(dateMs)
	} else if dateMs > 0 {
		msg.Timestamp = time.Unix(dateMs, 0)
	}

	// Message content (field 5 = Message{4=DocumentMessage, 15=TextMessage, 11=service, 13=bot, 17=gift})
	b.mapUserMessageContent(um, "5", &msg)

	// Quoted message (reply, field 7)
	if quoted := pbGetMsg(um, "7"); quoted != nil {
		// field 1 = Int64Value{1: message_id}
		if qMsgID := pbGetMsg(quoted, "1"); qMsgID != nil {
			msg.ReplyToID = strconv.FormatInt(pbGetInt64(qMsgID, "1"), 10)
		}
		// field 3 = sender_user_id
		// field 5 = quoted_message_content (Message)
		if qContent := pbGetMsg(quoted, "5"); qContent != nil {
			if qText := pbGetMsg(qContent, "15"); qText != nil {
				msg.ReplyPreview = truncateText(pbGetString(qText, "1"), 100)
			}
		}
	}

	return msg
}

// mapUpdatedMessage maps an UpdatedMessage (field 162) to a cores.Message.
// UpdatedMessage: 1=Peer, 2=message_id, 3=MessageContent, 4=IntValue{date}, 5=IntValue{sender_id}
func (b *BaleCore) mapUpdatedMessage(um map[string]interface{}) Message {
	msg := Message{
		Platform: "bale",
		Status:   MessageStatusSent,
	}
	rid := pbGetInt64(um, "2")
	var editDateMs int64
	if dateVal := pbGetMsg(um, "4"); dateVal != nil {
		editDateMs = pbGetInt64(dateVal, "1")
		if editDateMs > 1e12 {
			msg.Timestamp = time.UnixMilli(editDateMs)
		}
	}
	msg.ID = fmt.Sprintf("%d:%d", rid, editDateMs)
	if peer := pbGetMsg(um, "1"); peer != nil {
		peerID := pbGetInt64(peer, "2")
		peerType := pbGetInt64(peer, "1")
		msg.ChatID = fmt.Sprintf("%d|%d", peerID, peerType)
	}
	if senderVal := pbGetMsg(um, "5"); senderVal != nil {
		msg.SenderID = strconv.FormatInt(pbGetInt64(senderVal, "1"), 10)
	}
	b.mapUserMessageContent(um, "3", &msg)
	return msg
}

// mapUserMessageContent extracts content from a MessageContent protobuf into a cores.Message.
// MessageContent fields (from web.bale.ai JS): 1=BankMessage, 2=BinaryMessage, 3=DeletedMessage,
// 4=DocumentMessage, 5=EmptyMessage, 7=JsonMessage, 8=NasimEncryptedMessage, 9=OrderMessage,
// 10=PurchaseMessage, 11=ServiceMessage, 12=StickerMessage, 13=TemplateMessage,
// 14=TemplateMessageResponse, 15=TextMessage, 16=UnsupportedMessage, 17=GiftPacketMessage,
// 23=CrowdFundingMessage, 24=AnimatedStickerMessage, 25=BannedMessage, 26=LiveMessage,
// 27=ProtectedMessage, 28=GoldGiftPacketMessage, 29=PollMessage, 30=LongTextMessage, 31=StreamedMessage
func (b *BaleCore) mapUserMessageContent(parent map[string]interface{}, field string, msg *Message) {
	content := pbGetMsg(parent, field)
	if content == nil {
		return
	}

	// Text message (field 15 → TextMessage{1=text, 3=ext, 4=messageTag})
	if textMsg := pbGetMsg(content, "15"); textMsg != nil {
		msg.Text = pbGetString(textMsg, "1")
	}

	// Long text message (field 30 → LongTextMessage — same structure as TextMessage)
	if longText := pbGetMsg(content, "30"); longText != nil && msg.Text == "" {
		msg.Text = pbGetString(longText, "1")
	}

	// Document message (field 4 → DocumentMessage)
	// 1=file_id, 2=access_hash, 3=file_size, 4=name, 5=mime_type, 6=thumb, 7=ext, 8=caption, 9=checkSum
	if docMsg := pbGetMsg(content, "4"); docMsg != nil {
		fileID := pbGetInt64(docMsg, "1")
		accessHash := pbGetInt64(docMsg, "2")
		name := pbGetString(docMsg, "4")
		if name == "" {
			if nameMap := pbGetMsg(docMsg, "4"); nameMap != nil {
				name = pbGetString(nameMap, "1")
			}
		}
		msg.Attachments = append(msg.Attachments, FileRef{
			ID:       fmt.Sprintf("%d:%d", fileID, accessHash),
			Name:     name,
			MimeType: pbGetString(docMsg, "5"),
			Size:     pbGetInt64(docMsg, "3"),
		})
		if caption := pbGetMsg(docMsg, "8"); caption != nil {
			if capText := pbGetString(caption, "1"); capText != "" {
				msg.Text = capText
			}
		}
	}

	// Service message (field 11 → ServiceMessage, sub-ext has 26 types)
	if svcMsg := pbGetMsg(content, "11"); svcMsg != nil {
		msg.Text = "[service message]"
		if text := pbGetString(svcMsg, "1"); text != "" {
			msg.Text = text
		}
	}

	// Sticker message (field 12 → StickerMessage{1=stickerId, 5=collectionId})
	if stickerMsg := pbGetMsg(content, "12"); stickerMsg != nil {
		if msg.Text == "" {
			msg.Text = "[sticker]"
		}
		if idVal := pbGetMsg(stickerMsg, "1"); idVal != nil {
			stickerID := pbGetInt64(idVal, "1")
			msg.Text = fmt.Sprintf("[sticker:%d]", stickerID)
		}
	}

	// Animated sticker (field 24)
	if pbGetMsg(content, "24") != nil && msg.Text == "" {
		msg.Text = "[animated sticker]"
	}

	// Template/bot message (field 13 → TemplateMessage{1=message, 5=keyboard})
	if tmplMsg := pbGetMsg(content, "13"); tmplMsg != nil {
		b.mapUserMessageContent(tmplMsg, "1", msg) // recurse into inner message
	}

	// Poll message (field 29)
	if pollMsg := pbGetMsg(content, "29"); pollMsg != nil && msg.Text == "" {
		msg.Text = "[poll]"
	}

	// Gift packet (field 17)
	if pbGetMsg(content, "17") != nil && msg.Text == "" {
		msg.Text = "[gift packet]"
	}

	// Gold gift (field 28)
	if pbGetMsg(content, "28") != nil && msg.Text == "" {
		msg.Text = "[gold gift]"
	}

	// Deleted message (field 3)
	if pbGetMsg(content, "3") != nil && msg.Text == "" {
		msg.Text = "[deleted]"
	}

	// Empty/forwarded stub (field 5)
	if content["5"] != nil && msg.Text == "" {
		msg.Text = "[forwarded]"
	}

	// Live message (field 26)
	if pbGetMsg(content, "26") != nil && msg.Text == "" {
		msg.Text = "[live]"
	}

	// Banned (field 25)
	if pbGetMsg(content, "25") != nil && msg.Text == "" {
		msg.Text = "[content removed]"
	}
}

// mapHistoryMessage maps a HistoryMessage from LoadHistory to a cores.Message.
// HistoryMessage (from web.bale.ai JS): 1=senderUid, 2=rid, 3=date(ms), 4=MessageContent,
// 5=state(MESSAGESTATE: 0=SENT,1=RECEIVED,2=READ), 6=repeated Reaction,
// 7=MessageAttribute, 8=QuotedMessage, 9=Int64Value(seq), 10=OtherMessage(prev),
// 11=OtherMessage(next), 12=Int64Value(editedAt), 13=Int32Value(editorUserId),
// 14=Int64Value(groupedId), 15=BoolValue(hasComment), 16=RepliesInfo, 17=Int64Value(replyToTopId)
func (b *BaleCore) mapHistoryMessage(mc map[string]interface{}) Message {
	msg := Message{
		Platform: "bale",
		Status:   MessageStatusSent,
	}

	msg.SenderID = strconv.FormatInt(pbGetInt64(mc, "1"), 10)
	rid := pbGetInt64(mc, "2")
	dateMs := pbGetInt64(mc, "3")
	// Message ID format: "rid:dateMs" so Core methods can parse both values
	msg.ID = fmt.Sprintf("%d:%d", rid, dateMs)

	if dateMs > 1e12 {
		msg.Timestamp = time.UnixMilli(dateMs)
	} else if dateMs > 0 {
		msg.Timestamp = time.Unix(dateMs, 0)
	}

	// Message state: 0=SENT, 1=RECEIVED, 2=READ
	state := pbGetInt64(mc, "5")
	switch state {
	case 2:
		msg.Status = MessageStatusRead
	case 1:
		msg.Status = MessageStatusDelivered
	default:
		msg.Status = MessageStatusSent
	}

	// Edited at (field 12 = Int64Value{1: timestamp})
	if editedAt := pbGetMsg(mc, "12"); editedAt != nil {
		editMs := pbGetInt64(editedAt, "1")
		if editMs > 1e12 {
			t := time.UnixMilli(editMs)
			msg.EditedAt = &t
		}
	}

	// Content (field 4 = MessageContent)
	b.mapUserMessageContent(mc, "4", &msg)

	// Quoted message / reply (field 8)
	// QuotedMessage: 1=OtherMessage(msgId), 3=senderUserId, 4=messageDate, 5=MessageContent, 6=OutPeer
	if quoted := pbGetMsg(mc, "8"); quoted != nil {
		if qMsgID := pbGetMsg(quoted, "1"); qMsgID != nil {
			msg.ReplyToID = strconv.FormatInt(pbGetInt64(qMsgID, "1"), 10)
		}
		// Extract reply preview from quoted content
		if qContent := pbGetMsg(quoted, "5"); qContent != nil {
			if qText := pbGetMsg(qContent, "15"); qText != nil {
				msg.ReplyPreview = truncateText(pbGetString(qText, "1"), 100)
			}
		}
	}

	return msg
}

// --- Unified Core interface adapters ---

func (b *BaleCore) GetChatInfo(chatID string) (*Dialog, error) {
	if b.isBot {
		raw, err := b.GetChat(chatID)
		if err != nil {
			return nil, err
		}
		d := &Dialog{Platform: "bale", ID: chatID}
		if t, ok := raw["title"].(string); ok {
			d.Title = t
		}
		if fn, ok := raw["first_name"].(string); ok {
			d.Title = fn
			if ln, ok := raw["last_name"].(string); ok {
				d.Title += " " + ln
			}
		}
		switch raw["type"].(string) {
		case "private":
			d.Type = ChatTypeDM
		case "group", "supergroup":
			d.Type = ChatTypeGroup
		case "channel":
			d.Type = ChatTypeChannel
		}
		return d, nil
	}
	// User mode — no direct GetChat, return basic dialog from ID
	return &Dialog{Platform: "bale", ID: chatID}, nil
}

func (b *BaleCore) EditChatTitle(chatID string, title string) error {
	if b.isBot {
		return b.SetChatTitle(chatID, title)
	}
	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return err
	}
	gid, err := b.ResolveGroupID(id)
	if err != nil {
		return err
	}
	_, err = b.UserEditGroupTitle(gid, title)
	return err
}

func (b *BaleCore) EditChatDescription(chatID string, description string) error {
	if b.isBot {
		return b.SetChatDescription(chatID, description)
	}
	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return err
	}
	gid, err := b.ResolveGroupID(id)
	if err != nil {
		return err
	}
	_, err = b.UserEditGroupAbout(gid, description)
	return err
}

// LeaveChat is already implemented with the correct unified signature (bot mode).
// For user mode, add support:
// Note: LeaveChat already exists with correct signature for bot mode.

func (b *BaleCore) GetInviteLink(chatID string) (string, error) {
	if b.isBot {
		return b.ExportChatInviteLink(chatID)
	}
	return "", fmt.Errorf("%w: bale user mode does not support invite links", ErrNotSupported)
}

func (b *BaleCore) AddMembers(chatID string, userIDs []string) error {
	if b.isBot {
		return fmt.Errorf("%w: bale bots cannot add members", ErrNotSupported)
	}
	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return err
	}
	gid, err := b.ResolveGroupID(id)
	if err != nil {
		return err
	}
	var uids []int64
	for _, uid := range userIDs {
		u, _ := strconv.ParseInt(uid, 10, 64)
		uids = append(uids, u)
	}
	_, err = b.UserInviteUsers(gid, uids)
	return err
}

func (b *BaleCore) RemoveMember(chatID string, userID string) error {
	if b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		return b.BanChatMember(chatID, uid)
	}
	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return err
	}
	gid, err := b.ResolveGroupID(id)
	if err != nil {
		return err
	}
	uid, _ := strconv.ParseInt(userID, 10, 64)
	_, err = b.UserKickUser(gid, uid)
	return err
}

func (b *BaleCore) BanMember(chatID string, userID string) error {
	if b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		return b.BanChatMember(chatID, uid)
	}
	return b.RemoveMember(chatID, userID) // Bale user mode: kick = ban
}

func (b *BaleCore) UnbanMember(chatID string, userID string) error {
	if b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		return b.UnbanChatMember(chatID, uid, false)
	}
	return fmt.Errorf("%w: bale user mode does not support unbanning", ErrNotSupported)
}

func (b *BaleCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	if b.isBot {
		admins, err := b.GetChatAdministrators(chatID)
		if err != nil {
			return nil, err
		}
		var users []User
		for _, a := range admins {
			u := User{Platform: "bale"}
			if user, ok := a["user"].(map[string]interface{}); ok {
				u.ID = strconv.FormatInt(jsonInt64(user, "id"), 10)
				u.DisplayName = jsonString(user, "first_name")
				if ln := jsonString(user, "last_name"); ln != "" {
					u.DisplayName += " " + ln
				}
				u.Username = jsonString(user, "username")
				u.IsBot, _ = user["is_bot"].(bool)
			}
			users = append(users, u)
		}
		return users, nil
	}
	return nil, fmt.Errorf("%w: bale user mode does not support member listing", ErrNotSupported)
}

func (b *BaleCore) SetAdmin(chatID string, userID string, admin bool) error {
	if b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		perms := map[string]bool{
			"can_change_info":      admin,
			"can_delete_messages":  admin,
			"can_invite_users":     admin,
			"can_restrict_members": admin,
			"can_pin_messages":     admin,
			"can_promote_members":  false,
		}
		return b.PromoteChatMember(chatID, uid, perms)
	}
	return fmt.Errorf("%w: bale user mode does not support admin management", ErrNotSupported)
}

func (b *BaleCore) GetContacts() ([]User, error) {
	if !b.isBot {
		raw, err := b.UserGetContacts()
		if err != nil {
			return nil, err
		}
		var users []User
		if userList, ok := raw["1"].([]interface{}); ok {
			for _, item := range userList {
				if u, ok := item.(map[string]interface{}); ok {
					user := User{Platform: "bale"}
					if id, ok := u["1"].(float64); ok {
						user.ID = strconv.FormatInt(int64(id), 10)
					}
					if name, ok := u["2"].(map[string]interface{}); ok {
						if n, ok := name["1"].(string); ok {
							user.DisplayName = n
						}
					}
					users = append(users, user)
				}
			}
		}
		return users, nil
	}
	return nil, fmt.Errorf("%w: bale bots cannot list contacts", ErrNotSupported)
}

func (b *BaleCore) AddContact(phone string, firstName string, lastName string) error {
	if !b.isBot {
		contacts := []map[string]interface{}{
			{"1": phone, "2": map[string]interface{}{"1": firstName + " " + lastName}},
		}
		_, err := b.UserImportContacts(contacts)
		return err
	}
	return fmt.Errorf("%w: bale bots cannot manage contacts", ErrNotSupported)
}

func (b *BaleCore) DeleteContact(userID string) error {
	if !b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		_, err := b.UserRemoveContact(uid)
		return err
	}
	return fmt.Errorf("%w: bale bots cannot manage contacts", ErrNotSupported)
}

func (b *BaleCore) BlockUser(userID string) error {
	if !b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		_, err := b.UserBlockUser(uid)
		return err
	}
	return fmt.Errorf("%w: bale bots cannot block users", ErrNotSupported)
}

func (b *BaleCore) UnblockUser(userID string) error {
	if !b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		_, err := b.UserUnblockUser(uid)
		return err
	}
	return fmt.Errorf("%w: bale bots cannot unblock users", ErrNotSupported)
}

func (b *BaleCore) GetBlockedUsers() ([]User, error) {
	if !b.isBot {
		raw, err := b.UserLoadBlockedUsers()
		if err != nil {
			return nil, err
		}
		var users []User
		if userList, ok := raw["1"].([]interface{}); ok {
			for _, item := range userList {
				if u, ok := item.(map[string]interface{}); ok {
					user := User{Platform: "bale"}
					if id, ok := u["1"].(float64); ok {
						user.ID = strconv.FormatInt(int64(id), 10)
					}
					users = append(users, user)
				}
			}
		}
		return users, nil
	}
	return nil, fmt.Errorf("%w: bale bots cannot list blocked users", ErrNotSupported)
}

func (b *BaleCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	return nil, fmt.Errorf("%w: bale does not support message search", ErrNotSupported)
}

func (b *BaleCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	if !b.isBot {
		raw, err := b.UserSearchContacts(query)
		if err != nil {
			return nil, err
		}
		var dialogs []Dialog
		if userList, ok := raw["1"].([]interface{}); ok {
			for _, item := range userList {
				if u, ok := item.(map[string]interface{}); ok {
					d := Dialog{Platform: "bale", Type: ChatTypeDM}
					if id, ok := u["1"].(float64); ok {
						d.ID = strconv.FormatInt(int64(id), 10)
					}
					if name, ok := u["2"].(map[string]interface{}); ok {
						if n, ok := name["1"].(string); ok {
							d.Title = n
						}
					}
					dialogs = append(dialogs, d)
				}
			}
		}
		return dialogs, nil
	}
	return nil, fmt.Errorf("%w: bale bots cannot search globally", ErrNotSupported)
}

func (b *BaleCore) SendTyping(chatID string) error {
	if b.isBot {
		return b.SendChatAction(chatID, "typing")
	}
	_, err := b.UserTyping(chatID)
	return err
}

func (b *BaleCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	return nil, fmt.Errorf("%w: bale does not support polls", ErrNotSupported)
}

func (b *BaleCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	return fmt.Errorf("%w: bale does not support polls", ErrNotSupported)
}

// SendSticker is already implemented with the correct unified signature (bot mode).

func (b *BaleCore) GetSessions() ([]Session, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bale bot API does not support session management", ErrNotSupported)
	}
	resp, err := b.GetAuthSessions()
	if err != nil {
		return nil, err
	}
	// Parse session list from response
	var sessions []Session
	for _, item := range pbGetList(resp, "1") {
		s, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		sessions = append(sessions, Session{
			ID:       fmt.Sprintf("%d", pbGetInt64(s, "1")),
			Platform: "bale",
		})
	}
	return sessions, nil
}

func (b *BaleCore) TerminateSession(sessionID string) error {
	if b.isBot {
		return fmt.Errorf("%w: bale bot API does not support session management", ErrNotSupported)
	}
	sid, err := strconv.ParseInt(sessionID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid session ID: %w", err)
	}
	_, err = b.TerminateSessionReal(sid)
	return err
}

// mapBotMessage extracts "result" from an apiRequest response and maps it to a Message.
func (b *BaleCore) mapBotMessage(resp map[string]interface{}) *Message {
	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil
	}
	m := b.mapMessage(result)
	return &m
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Bot API (27 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetUpdates fetches updates via long-polling (bot mode).
func (b *BaleCore) GetUpdates(offset int64, limit int, timeout int) ([]map[string]interface{}, error) {
	params := map[string]interface{}{
		"offset":  offset,
		"limit":   limit,
		"timeout": timeout,
	}
	resp, err := b.apiRequest("getUpdates", params)
	if err != nil {
		return nil, err
	}
	results, _ := resp["result"].([]interface{})
	var out []map[string]interface{}
	for _, r := range results {
		if m, ok := r.(map[string]interface{}); ok {
			out = append(out, m)
		}
	}
	return out, nil
}

// SetWebhook sets a webhook URL for receiving updates.
func (b *BaleCore) SetWebhook(url string, maxConnections int) error {
	params := map[string]interface{}{"url": url}
	if maxConnections > 0 {
		params["max_connections"] = maxConnections
	}
	_, err := b.apiRequest("setWebhook", params)
	return err
}

// DeleteWebhook removes the webhook integration.
func (b *BaleCore) DeleteWebhook() error {
	_, err := b.apiRequest("deleteWebhook", nil)
	return err
}

// GetWebhookInfo returns current webhook status.
func (b *BaleCore) GetWebhookInfo() (map[string]interface{}, error) {
	resp, err := b.apiRequest("getWebhookInfo", nil)
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// SendPhoto sends a photo by file_id or URL (bot mode).
func (b *BaleCore) SendPhoto(chatID string, photo string, caption string) (*Message, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
		"photo":   photo,
	}
	if caption != "" {
		params["caption"] = caption
	}
	resp, err := b.apiRequest("sendPhoto", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendAudio sends an audio file by file_id or URL (bot mode).
func (b *BaleCore) SendAudio(chatID string, audio string, caption string, duration int) (*Message, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
		"audio":   audio,
	}
	if caption != "" {
		params["caption"] = caption
	}
	if duration > 0 {
		params["duration"] = duration
	}
	resp, err := b.apiRequest("sendAudio", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendDocument sends a document by file_id or URL (bot mode).
func (b *BaleCore) SendDocument(chatID string, document string, caption string) (*Message, error) {
	params := map[string]interface{}{
		"chat_id":  chatID,
		"document": document,
	}
	if caption != "" {
		params["caption"] = caption
	}
	resp, err := b.apiRequest("sendDocument", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendVideo sends a video by file_id or URL (bot mode).
func (b *BaleCore) SendVideo(chatID string, video string, caption string, duration int) (*Message, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
		"video":   video,
	}
	if caption != "" {
		params["caption"] = caption
	}
	if duration > 0 {
		params["duration"] = duration
	}
	resp, err := b.apiRequest("sendVideo", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendAnimation sends an animation (GIF) by file_id or URL (bot mode).
func (b *BaleCore) SendAnimation(chatID string, animation string, caption string) (*Message, error) {
	params := map[string]interface{}{
		"chat_id":   chatID,
		"animation": animation,
	}
	if caption != "" {
		params["caption"] = caption
	}
	resp, err := b.apiRequest("sendAnimation", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendVoice sends a voice message by file_id or URL (bot mode).
func (b *BaleCore) SendVoice(chatID string, voice string, caption string, duration int) (*Message, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
		"voice":   voice,
	}
	if caption != "" {
		params["caption"] = caption
	}
	if duration > 0 {
		params["duration"] = duration
	}
	resp, err := b.apiRequest("sendVoice", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendVideoNote sends a video note (round video) by file_id or URL (bot mode).
func (b *BaleCore) SendVideoNote(chatID string, videoNote string, duration int, length int) (*Message, error) {
	params := map[string]interface{}{
		"chat_id":    chatID,
		"video_note": videoNote,
	}
	if duration > 0 {
		params["duration"] = duration
	}
	if length > 0 {
		params["length"] = length
	}
	resp, err := b.apiRequest("sendVideoNote", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// SendMediaGroup sends a group of photos or videos as an album (bot mode).
func (b *BaleCore) SendMediaGroup(chatID string, media []map[string]interface{}) ([]map[string]interface{}, error) {
	mediaJSON, err := json.Marshal(media)
	if err != nil {
		return nil, fmt.Errorf("marshal media: %w", err)
	}
	params := map[string]interface{}{
		"chat_id": chatID,
		"media":   string(mediaJSON),
	}
	resp, err := b.apiRequest("sendMediaGroup", params)
	if err != nil {
		return nil, err
	}
	results, _ := resp["result"].([]interface{})
	var out []map[string]interface{}
	for _, r := range results {
		if m, ok := r.(map[string]interface{}); ok {
			out = append(out, m)
		}
	}
	return out, nil
}

// SendVenue sends a venue with location (bot mode).
func (b *BaleCore) SendVenue(chatID string, lat, lon float64, title, address string) (*Message, error) {
	params := map[string]interface{}{
		"chat_id":   chatID,
		"latitude":  lat,
		"longitude": lon,
		"title":     title,
		"address":   address,
	}
	resp, err := b.apiRequest("sendVenue", params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

// EditMessageReplyMarkup edits the reply markup of a message (bot mode).
func (b *BaleCore) EditMessageReplyMarkup(chatID string, msgID int64, replyMarkup interface{}) error {
	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": msgID,
	}
	if replyMarkup != nil {
		markupJSON, err := json.Marshal(replyMarkup)
		if err != nil {
			return fmt.Errorf("marshal reply_markup: %w", err)
		}
		params["reply_markup"] = string(markupJSON)
	}
	_, err := b.apiRequest("editMessageReplyMarkup", params)
	return err
}

// GetFile gets info about a file by file_id (bot mode).
func (b *BaleCore) GetFile(fileID string) (map[string]interface{}, error) {
	resp, err := b.apiRequest("getFile", map[string]interface{}{"file_id": fileID})
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// RestrictChatMember restricts a user in a supergroup (bot mode).
func (b *BaleCore) RestrictChatMember(chatID string, userID int64, permissions map[string]bool) error {
	params := map[string]interface{}{
		"chat_id":     chatID,
		"user_id":     userID,
		"permissions": permissions,
	}
	_, err := b.apiRequest("restrictChatMember", params)
	return err
}

// UploadStickerFile uploads a sticker file (bot mode).
func (b *BaleCore) UploadStickerFile(userID int64, sticker io.Reader, stickerFormat string) (map[string]interface{}, error) {
	fields := map[string]string{
		"user_id":        strconv.FormatInt(userID, 10),
		"sticker_format": stickerFormat,
	}
	resp, err := b.apiRequestMultipart("uploadStickerFile", fields, "sticker", "sticker.webp", sticker)
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// CreateNewStickerSet creates a new sticker set (bot mode).
func (b *BaleCore) CreateNewStickerSet(userID int64, name, title string, stickers []map[string]interface{}) error {
	stickersJSON, _ := json.Marshal(stickers)
	params := map[string]interface{}{
		"user_id":  userID,
		"name":     name,
		"title":    title,
		"stickers": string(stickersJSON),
	}
	_, err := b.apiRequest("createNewStickerSet", params)
	return err
}

// AddStickerToSet adds a sticker to an existing set (bot mode).
func (b *BaleCore) AddStickerToSet(userID int64, name string, sticker map[string]interface{}) error {
	stickerJSON, _ := json.Marshal(sticker)
	params := map[string]interface{}{
		"user_id": userID,
		"name":    name,
		"sticker": string(stickerJSON),
	}
	_, err := b.apiRequest("addStickerToSet", params)
	return err
}

// DeleteStickerFromSet deletes a sticker from a set (bot mode).
func (b *BaleCore) DeleteStickerFromSet(sticker string) error {
	_, err := b.apiRequest("deleteStickerFromSet", map[string]interface{}{"sticker": sticker})
	return err
}

// GetUserProfilePhotos gets a user's profile photos (bot mode).
func (b *BaleCore) GetUserProfilePhotos(userID int64, offset, limit int) (map[string]interface{}, error) {
	params := map[string]interface{}{
		"user_id": userID,
	}
	if offset > 0 {
		params["offset"] = offset
	}
	if limit > 0 {
		params["limit"] = limit
	}
	resp, err := b.apiRequest("getUserProfilePhotos", params)
	if err != nil {
		return nil, err
	}
	result, _ := resp["result"].(map[string]interface{})
	return result, nil
}

// AnswerInlineQuery answers an inline query with results (bot mode).
func (b *BaleCore) AnswerInlineQuery(inlineQueryID string, results []map[string]interface{}, cacheTime int) error {
	params := map[string]interface{}{
		"inline_query_id": inlineQueryID,
		"results":         results,
	}
	if cacheTime >= 0 {
		params["cache_time"] = cacheTime
	}
	_, err := b.apiRequest("answerInlineQuery", params)
	return err
}

// InviteUser sends an invite to a user (Bale-specific bot method).
func (b *BaleCore) InviteUser(chatID string, userID int64) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	}
	_, err := b.apiRequest("inviteUser", params)
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Auth Service (17 methods)
// ══════════════════════════════════════════════════════════════════════════════

// DeleteAccount permanently deletes the user's account.
func (b *BaleCore) DeleteAccount(reason string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "DeleteAccount", map[string]interface{}{"1": reason})
}

// ChangePhone initiates a phone number change.
func (b *BaleCore) ChangePhone(newPhone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "ChangePhone", map[string]interface{}{"1": newPhone})
}

// SendDeleteAccountVerificationCode requests a verification code for account deletion.
func (b *BaleCore) SendDeleteAccountVerificationCode() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "SendDeleteAccountVerificationCode", map[string]interface{}{})
}

// SendChangePhoneVerificationCode requests a verification code for phone change.
func (b *BaleCore) SendChangePhoneVerificationCode(newPhone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "SendChangePhoneVerificationCode", map[string]interface{}{"1": newPhone})
}

// EnableTwoFactorAuthentication enables 2FA with a password.
func (b *BaleCore) EnableTwoFactorAuthentication(password string, hint string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": password}
	if hint != "" {
		payload["2"] = hint
	}
	return b.userSend(baleServiceAuth, "EnableTwoFactorAuthentication", payload)
}

// DisableTwoFactorAuthentication disables 2FA.
func (b *BaleCore) DisableTwoFactorAuthentication(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "DisableTwoFactorAuthentication", map[string]interface{}{"1": password})
}

// IsTwoFactorAuthenticationEnabled checks if 2FA is enabled.
func (b *BaleCore) IsTwoFactorAuthenticationEnabled() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "IsTwoFactorAuthenticationEnabled", map[string]interface{}{})
}

// VerifyEmail verifies an email address.
func (b *BaleCore) VerifyEmail(email string, code string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "VerifyEmail", map[string]interface{}{"1": email, "2": code})
}

// RecoverPassword initiates password recovery.
func (b *BaleCore) RecoverPassword() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "RecoverPassword", map[string]interface{}{})
}

// VerifyPasswordRecovery verifies a password recovery code.
func (b *BaleCore) VerifyPasswordRecovery(code string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "VerifyPasswordRecovery", map[string]interface{}{"1": code})
}

// SetNewPassword sets a new password after recovery.
func (b *BaleCore) SetNewPassword(transactionHash, newPassword, hint string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": transactionHash, "2": newPassword}
	if hint != "" {
		payload["3"] = hint
	}
	return b.userSend(baleServiceAuth, "SetNewPassword", payload)
}

// TerminateAllSessions terminates all other sessions.
func (b *BaleCore) TerminateAllSessions() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "TerminateAllSessions", map[string]interface{}{})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Users Service (19 methods)
// ══════════════════════════════════════════════════════════════════════════════

// EditSex changes the user's gender. Values: 1=male, 2=female, 3=other.
func (b *BaleCore) EditSex(sex int) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditSex", map[string]interface{}{"1": int64(sex)})
}

// EditBirthDate changes the user's birth date. Format: "YYYY-MM-DD".
func (b *BaleCore) EditBirthDate(birthDate string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditBirthDate", map[string]interface{}{"1": birthDate})
}

// EditAvatarGRPC changes the user's avatar via gRPC user API.
// fileID is from a prior file upload.
func (b *BaleCore) EditAvatarGRPC(fileID int64, accessHash int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": map[string]interface{}{"1": fileID, "2": accessHash},
	}
	return b.userSend(baleServiceUsers, "EditAvatar", payload)
}

// RemoveAvatar removes the user's avatar.
func (b *BaleCore) RemoveAvatar() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "RemoveAvatar", map[string]interface{}{})
}

// EditMyTimeZone changes the user's timezone.
func (b *BaleCore) EditMyTimeZone(timezone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditMyTimeZone", map[string]interface{}{"1": timezone})
}

// EditMyPreferredLanguages changes the user's preferred languages.
func (b *BaleCore) EditMyPreferredLanguages(langs []string) (map[string]interface{}, error) {
	// Repeated string field
	langList := make([]interface{}, len(langs))
	for i, l := range langs {
		langList[i] = l
	}
	return b.userSend(baleServiceUsers, "EditMyPreferredLanguages", map[string]interface{}{"1": langList})
}

// LoadAvatars loads avatars for a user.
func (b *BaleCore) LoadAvatars(userID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "LoadAvatars", map[string]interface{}{"1": baleUserOutPeer(userID)})
}

// NotifyAboutDeviceInfo sends device info to the server.
func (b *BaleCore) NotifyAboutDeviceInfo(deviceModel, osVersion, appVersion string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": deviceModel,
		"2": osVersion,
		"3": appVersion,
	}
	return b.userSend(baleServiceUsers, "NotifyAboutDeviceInfo", payload)
}

// GetUserPrivacyStatus gets privacy settings status.
func (b *BaleCore) GetUserPrivacyStatus() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "GetUserPrivacyStatus", map[string]interface{}{})
}

// SetUserPrivacyStatus sets a privacy setting. key: "phone", "about", "avatar", etc.
// value: 1=everyone, 2=contacts, 3=nobody.
func (b *BaleCore) SetUserPrivacyStatus(key string, value int) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "SetUserPrivacyStatus", map[string]interface{}{"1": key, "2": int64(value)})
}

// GetUserFullPrivacy gets all privacy settings.
func (b *BaleCore) GetUserFullPrivacy() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "GetUserFullPrivacy", map[string]interface{}{})
}

// IsNameAllowed checks if a display name is allowed.
func (b *BaleCore) IsNameAllowed(name string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "IsNameAllowed", map[string]interface{}{"1": name})
}

// ChangePhoneNumber initiates phone number change (user service).
func (b *BaleCore) ChangePhoneNumber(newPhone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "ChangePhoneNumber", map[string]interface{}{"1": newPhone})
}

// ConfirmPhoneNumber confirms a phone number change with verification code.
func (b *BaleCore) ConfirmPhoneNumber(transactionHash, code string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "ConfirmPhoneNumber", map[string]interface{}{"1": transactionHash, "2": code})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Meet Service (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ReceiveCall accepts an incoming call.
func (b *BaleCore) ReceiveCall(callID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "ReceiveCall", map[string]interface{}{"1": callID})
}

// DiscardCall rejects/discards a call.
func (b *BaleCore) DiscardCall(callID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "DiscardCall", map[string]interface{}{"1": callID})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — GiftPacket Service (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Magazine Service (3 methods)
// ══════════════════════════════════════════════════════════════════════════════

const baleServiceMagazine = "bale.magazine.v1.Magazine"

// UpvotePost upvotes a post.
func (b *BaleCore) UpvotePost(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMagazine, "UpvotePost", payload)
}

// RevokeUpvotedPost removes an upvote from a post.
func (b *BaleCore) RevokeUpvotedPost(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMagazine, "RevokeUpvotedPost", payload)
}

// GetMessageUpvoters gets the list of upvoters for a post.
func (b *BaleCore) GetMessageUpvoters(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMagazine, "GetMessageUpvoters", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Kifpool Service (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Push Service (5 methods)
// ══════════════════════════════════════════════════════════════════════════════

const baleServicePush = "bale.push.v1.Push"

// RegisterPush registers for push notifications (generic).
func (b *BaleCore) RegisterPush(token string, platform int) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "RegisterPush", map[string]interface{}{"1": token, "2": int64(platform)})
}

// UnregisterPush unregisters from push notifications.
func (b *BaleCore) UnregisterPush(token string) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "UnregisterPush", map[string]interface{}{"1": token})
}

// RegisterGooglePush registers for Google/FCM push notifications.
func (b *BaleCore) RegisterGooglePush(token string) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "RegisterGooglePush", map[string]interface{}{"1": token})
}

// UnregisterGooglePush unregisters from Google/FCM push notifications.
func (b *BaleCore) UnregisterGooglePush(token string) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "UnregisterGooglePush", map[string]interface{}{"1": token})
}

// UnregisterAllPushCredentials removes all push notification registrations.
func (b *BaleCore) UnregisterAllPushCredentials() (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "UnregisterAllPushCredentials", map[string]interface{}{})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Ramz / App Lock (7 methods)
// ══════════════════════════════════════════════════════════════════════════════

const baleServiceRamz = "bale.ramz.v1.Ramz"

// SetRamzPassword sets the app lock password.
func (b *BaleCore) SetRamzPassword(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "SetPassword", map[string]interface{}{"1": password})
}

// DeleteRamzPassword removes the app lock password.
func (b *BaleCore) DeleteRamzPassword(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "DeletePassword", map[string]interface{}{"1": password})
}

// SendRamzOTP sends an OTP for app lock recovery.
func (b *BaleCore) SendRamzOTP() (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "SendOTP", map[string]interface{}{})
}

// ForgetRamzPassword initiates password forget flow.
func (b *BaleCore) ForgetRamzPassword(otp string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "ForgetPassword", map[string]interface{}{"1": otp})
}

// ValidateRamzOTP validates an OTP.
func (b *BaleCore) ValidateRamzOTP(otp string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "ValidateOTP", map[string]interface{}{"1": otp})
}

// CheckRamzPasswordSet checks if app lock password is set.
func (b *BaleCore) CheckRamzPasswordSet() (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "CheckPasswordSet", map[string]interface{}{})
}

// CheckRamzPassword checks if the provided password is correct.
func (b *BaleCore) CheckRamzPassword(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "CheckPassword", map[string]interface{}{"1": password})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Report Service (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

const baleServiceReport = "bale.report.v1.Report"

// ReportInappropriateContent reports content as inappropriate.
func (b *BaleCore) ReportInappropriateContent(chatID string, rid int64, reason string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": reason,
	}
	return b.userSend(baleServiceReport, "ReportInappropriateContent", payload)
}

// ReportDismiss dismisses a report prompt.
func (b *BaleCore) ReportDismiss(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceReport, "ReportDismiss", map[string]interface{}{"1": balePeer(peerType, peerID)})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Feedback (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Search (5 methods)
// ══════════════════════════════════════════════════════════════════════════════

// SearchPeerMessages searches messages within a specific chat.
func (b *BaleCore) SearchPeerMessages(chatID string, query string, limit int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": query,
		"3": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "SearchPeerMessages", payload)
}

// SearchPeerMedia searches media in a specific chat.
func (b *BaleCore) SearchPeerMedia(chatID string, mediaType int, limit int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": int64(mediaType),
		"3": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "SearchPeerMedia", payload)
}

// SearchMembers searches group members by name.
func (b *BaleCore) SearchMembers(chatID string, query string) (map[string]interface{}, error) {
	peerID, _ := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(peerID),
		"2": query,
	}
	return b.userSend(baleServiceGroups, "SearchMembers", payload)
}

// SearchLinks searches shared links in a chat.
func (b *BaleCore) SearchLinks(chatID string, limit int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "SearchLinks", payload)
}

// GlobalChannelSearch searches public channels globally.
func (b *BaleCore) GlobalChannelSearch(query string, limit int) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": query,
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "GlobalChannelSearch", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Topics (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// EditTopic edits a topic in a group.
func (b *BaleCore) EditTopic(chatID string, topicID int64, title string) (map[string]interface{}, error) {
	peerID, _ := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(peerID),
		"2": topicID,
		"3": title,
	}
	return b.userSend(baleServiceMessaging, "EditTopic", payload)
}

// DeleteTopic deletes a topic from a group.
func (b *BaleCore) DeleteTopic(chatID string, topicID int64) (map[string]interface{}, error) {
	peerID, _ := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(peerID),
		"2": topicID,
	}
	return b.userSend(baleServiceMessaging, "DeleteTopic", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Folders (3 methods)
// ══════════════════════════════════════════════════════════════════════════════

// EditFolder edits a dialog folder.
func (b *BaleCore) EditFolder(folderID int64, title string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": folderID,
		"2": title,
	}
	return b.userSend(baleServiceMessaging, "EditFolder", payload)
}

// DeleteFolder deletes a dialog folder.
func (b *BaleCore) DeleteFolder(folderID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMessaging, "DeleteFolder", map[string]interface{}{"1": folderID})
}

// ReorderFolders reorders dialog folders.
func (b *BaleCore) ReorderFolders(folderIDs []int64) (map[string]interface{}, error) {
	ids := make([]interface{}, len(folderIDs))
	for i, id := range folderIDs {
		ids[i] = id
	}
	return b.userSend(baleServiceMessaging, "ReorderFolders", map[string]interface{}{"1": ids})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Polls (3 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ClosePoll closes an active poll.
func (b *BaleCore) ClosePoll(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMessaging, "ClosePoll", payload)
}

// GetPollResults gets results summary for a poll.
func (b *BaleCore) GetPollResults(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMessaging, "GetPollResults", payload)
}

// GetFullPollResult gets detailed poll results including per-option voters.
func (b *BaleCore) GetFullPollResult(chatID string, rid int64, date int64, optionIndex int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
		"4": int64(optionIndex),
	}
	return b.userSend(baleServiceMessaging, "GetFullPollResult", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Mini Apps / Bots (3 methods)
// ══════════════════════════════════════════════════════════════════════════════

// GetMiniAppUrl gets the URL for a mini app (web app inside Bale).
func (b *BaleCore) GetMiniAppUrl(botID int64, shortName string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": shortName,
	}
	return b.userSend(baleServiceMessaging, "GetMiniAppUrl", payload)
}

// GetBotMenuButtons gets a bot's menu buttons.
func (b *BaleCore) GetBotMenuButtons(botID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMessaging, "GetBotMenuButtons", map[string]interface{}{"1": baleUserOutPeer(botID)})
}

// InvokeCustomMethod invokes a custom bot method.
func (b *BaleCore) InvokeCustomMethod(botID int64, method string, params string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": method,
		"3": params,
	}
	return b.userSend(baleServiceMessaging, "InvokeCustomMethod", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — AI / Transcription (1 method)
// ══════════════════════════════════════════════════════════════════════════════

const baleServiceAI = "bale.ai.v1.AI"

// GetTranscript gets a voice-to-text transcription.
func (b *BaleCore) GetTranscript(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceAI, "GetTranscript", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Configs (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// GetInAppUpdate checks for app updates.
func (b *BaleCore) GetInAppUpdate() (map[string]interface{}, error) {
	return b.userSend(baleServiceConfigs, "GetInAppUpdate", map[string]interface{}{})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Analytics (1 method)
// ══════════════════════════════════════════════════════════════════════════════

const baleServiceFanoos = "bale.fanoos.v1.Fanoos"

// FanoosSend sends an analytics event.
func (b *BaleCore) FanoosSend(eventName string, eventData map[string]string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": eventName,
	}
	if len(eventData) > 0 {
		// Convert to repeated key-value pairs
		pairs := make([]interface{}, 0, len(eventData))
		for k, v := range eventData {
			pairs = append(pairs, map[string]interface{}{"1": k, "2": v})
		}
		payload["2"] = pairs
	}
	return b.userSend(baleServiceFanoos, "FanoosSend", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Bot Commands (3 methods)
// ══════════════════════════════════════════════════════════════════════════════

// SetMyCommands sets the bot's command list. commands is a list of {command, description}.
func (b *BaleCore) SetMyCommands(commands []map[string]string) (map[string]interface{}, error) {
	cmds := make([]interface{}, len(commands))
	for i, c := range commands {
		cmds[i] = map[string]interface{}{
			"command":     c["command"],
			"description": c["description"],
		}
	}
	return b.apiRequest("setMyCommands", map[string]interface{}{"commands": cmds})
}

// DeleteMyCommands deletes the bot's command list.
func (b *BaleCore) DeleteMyCommands() (map[string]interface{}, error) {
	return b.apiRequest("deleteMyCommands", nil)
}

// GetMyCommands returns the bot's current command list.
func (b *BaleCore) GetMyCommands() ([]map[string]string, error) {
	resp, err := b.apiRequest("getMyCommands", nil)
	if err != nil {
		return nil, err
	}
	result, ok := resp["result"].([]interface{})
	if !ok {
		return nil, nil
	}
	var cmds []map[string]string
	for _, item := range result {
		cmd, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		cmds = append(cmds, map[string]string{
			"command":     fmt.Sprintf("%v", cmd["command"]),
			"description": fmt.Sprintf("%v", cmd["description"]),
		})
	}
	return cmds, nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Auth Sessions (2 methods, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// GetAuthSessions returns the user's active sessions.
// Service: bale.auth.v1.Auth/GetAuthSessions
func (b *BaleCore) GetAuthSessions() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "GetAuthSessions", map[string]interface{}{})
}

// TerminateSessionReal terminates a specific auth session by ID.
// Service: bale.auth.v1.Auth/TerminateSession
func (b *BaleCore) TerminateSessionReal(sessionID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "TerminateSession", map[string]interface{}{"1": sessionID})
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Folders (2 methods, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// LoadFolders loads the user's dialog folders.
// Service: bale.messaging.v2.Messaging/LoadFolders
func (b *BaleCore) LoadFolders() (map[string]interface{}, error) {
	return b.userSend(baleServiceMessaging, "LoadFolders", map[string]interface{}{})
}

// CreateFolderReal creates a new dialog folder with the given title and included peers.
// Service: bale.messaging.v2.Messaging/CreateFolder
func (b *BaleCore) CreateFolderReal(title string, peerIDs []string) (map[string]interface{}, error) {
	var peers []interface{}
	for _, id := range peerIDs {
		peerID, peerType := parsePeerID(id)
		peers = append(peers, balePeer(peerType, peerID))
	}
	payload := map[string]interface{}{
		"1": title,
	}
	if len(peers) > 0 {
		payload["2"] = peers
	}
	return b.userSend(baleServiceMessaging, "CreateFolder", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Users (1 method, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// GetFullUser loads a single user's full profile.
// Service: bale.users.v1.Users/GetFullUser
func (b *BaleCore) GetFullUser(userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleInfoPeer(userID, balePeerPrivate),
	}
	return b.userSend(baleServiceUsers, "GetFullUser", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Dialogs (1 method, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// LoadDialogsFiltered loads dialogs with folder/archive/mute filters.
// Service: bale.messaging.v2.Messaging/LoadDialogs
// Fields: 1=offset_date, 2=limit, 3=folder_id, 4=archived (bool), 5=exclude_pinned
func (b *BaleCore) LoadDialogsFiltered(offsetDate int64, limit int, folderID int64, archived bool, excludePinned bool) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": offsetDate,
		"2": int64(limit),
	}
	if folderID != 0 {
		payload["3"] = folderID
	}
	if archived {
		payload["4"] = int64(1)
	}
	if excludePinned {
		payload["5"] = int64(1)
	}
	return b.userSend(baleServiceMessaging, "LoadDialogs", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Push Config (1 method, user mode)
// ══════════════════════════════════════════════════════════════════════════════

const baleServicePushak = "ai.bale.pushak.Push"

// PushSetConfig configures push notification settings.
// Service: ai.bale.pushak.Push/SetConfig
func (b *BaleCore) PushSetConfig(config map[string]interface{}) (map[string]interface{}, error) {
	return b.userSend(baleServicePushak, "SetConfig", config)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Chat Management (5 methods, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// MarkAsUnread — Bale server returns "unknown method" for MarkAsUnread.
// The web client has stub code for it but the server doesn't implement it.
func (b *BaleCore) MarkAsUnread(chatID string) (map[string]interface{}, error) {
	return nil, fmt.Errorf("%w: %s server does not implement MarkAsUnread", ErrNotSupported, balePlatform)
}

// MuteChat mutes/unmutes a dialog via ArchiveDialogs (Bale has no separate mute RPC).
// Uses the MentionRead approach: setting "2" field as mute duration.
func (b *BaleCore) MuteChat(chatID string, muted bool) error {
	// Bale doesn't have a dedicated MuteDialog RPC.
	// The web client handles mute via client-side notification settings.
	return fmt.Errorf("%w: %s does not support server-side mute", ErrNotSupported, balePlatform)
}

// ArchiveChat archives/unarchives a dialog.
// Service: bale.messaging.v2.Messaging/ArchiveDialogs or UnArchiveDialogs
func (b *BaleCore) ArchiveChat(chatID string, archived bool) error {
	peerID, peerType := parsePeerID(chatID)
	peer := balePeer(peerType, peerID)
	peers := []map[string]interface{}{peer}
	method := "ArchiveDialogs"
	if !archived {
		method = "UnArchiveDialogs"
	}
	_, err := b.userSend(baleServiceMessaging, method, map[string]interface{}{"1": peers})
	return err
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Message Features (3 methods, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// SendScheduledMessage sends a message scheduled for a future time.
// Sends via Messaging/SendMessage with an additional schedule_date field.
func (b *BaleCore) SendScheduledMessage(chatID string, text string, scheduleDate int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"15": map[string]interface{}{"1": text},
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
		"7": scheduleDate, // schedule_date in millis
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// SendProtectedMessage sends a self-destructing/view-once message (MessageContent field 27).
func (b *BaleCore) SendProtectedMessage(chatID string, text string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"27": map[string]interface{}{"1": text}, // ProtectedMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// SendLongTextMessage sends a message with text exceeding the normal limit (MessageContent field 30).
func (b *BaleCore) SendLongTextMessage(chatID string, text string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"30": map[string]interface{}{"1": text}, // LongTextMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// ══════════════════════════════════════════════════════════════════════════════
// Extended Methods — Exotic Content Types (5 methods, user mode)
// ══════════════════════════════════════════════════════════════════════════════

// SendBankMessage sends a banking/payment content message (MessageContent field 1).
func (b *BaleCore) SendBankMessage(chatID string, bankData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"1": bankData, // BankMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// SendJsonMessage sends a JSON payload message (MessageContent field 7).
func (b *BaleCore) SendJsonMessage(chatID string, jsonData string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"7": map[string]interface{}{"1": jsonData}, // JsonMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// SendOrderMessage sends an order-related content message (MessageContent field 9).
func (b *BaleCore) SendOrderMessage(chatID string, orderData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"9": orderData, // OrderMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// SendAnimatedSticker sends an animated sticker (TGS/Lottie, MessageContent field 24).
func (b *BaleCore) SendAnimatedSticker(chatID string, stickerData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"24": stickerData, // AnimatedStickerMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

// SendLiveMessage sends a live stream content message (MessageContent field 26).
func (b *BaleCore) SendLiveMessage(chatID string, liveData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"26": liveData, // LiveMessage
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, balePlatform)
}

func (b *BaleCore) UnpinAllMessages(chatID string) error {
	return b.UnpinAllChatMessages(chatID)
}

func (b *BaleCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, balePlatform)
}

func (b *BaleCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, balePlatform)
}

// =============================================================================
// Missing Messaging methods (bale.messaging.v2.Messaging)
// Discovered from web.bale.ai v4.17.0+151668 JS scrape, 2026-04-13
// =============================================================================

func (b *BaleCore) UserSendMultiMediaMessage(chatID string, mediaMessages []map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": mediaMessages,
	}
	return b.userSend(baleServiceMessaging, "SendMultiMediaMessage", payload)
}

func (b *BaleCore) UserLoadFolderDialogs(folderID int64, offsetDate int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	payload := map[string]interface{}{
		"1": folderID,
		"2": offsetDate,
		"3": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadFolderDialogs", payload)
}

func (b *BaleCore) UserLoadGroupedDialogs(offsetDate int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	payload := map[string]interface{}{
		"1": offsetDate,
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadGroupedDialogs", payload)
}

func (b *BaleCore) UserLoadPeerDialogs(peerIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(peerIDs))
	for i, pid := range peerIDs {
		id, pt := parsePeerID(pid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "LoadPeerDialogs", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserLoadPeers(peerIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(peerIDs))
	for i, pid := range peerIDs {
		id, pt := parsePeerID(pid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "LoadPeers", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserLoadPinnedDialogs() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "LoadPinnedDialogs", map[string]interface{}{})
}

func (b *BaleCore) UserLoadReplies(chatID string, msgID string, offsetDate int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
		"3": offsetDate,
		"4": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadReplies", payload)
}

func (b *BaleCore) UserCreateReservedFolder(title string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "CreateReservedFolder", map[string]interface{}{"1": title})
}

func (b *BaleCore) UserArchiveDialogs(chatIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(chatIDs))
	for i, cid := range chatIDs {
		id, pt := parsePeerID(cid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "ArchiveDialogs", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserUnArchiveDialogs(chatIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(chatIDs))
	for i, cid := range chatIDs {
		id, pt := parsePeerID(cid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "UnArchiveDialogs", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserPinDialogs(chatIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(chatIDs))
	for i, cid := range chatIDs {
		id, pt := parsePeerID(cid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "PinDialogs", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserUnpinDialogs(chatIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(chatIDs))
	for i, cid := range chatIDs {
		id, pt := parsePeerID(cid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "UnpinDialogs", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserReorderPinnedDialogs(chatIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(chatIDs))
	for i, cid := range chatIDs {
		id, pt := parsePeerID(cid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "ReorderPinnedDialogs", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserMarkDialogsAsRead(chatIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(chatIDs))
	for i, cid := range chatIDs {
		id, pt := parsePeerID(cid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "MarkDialogsAsRead", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserMentionRead(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceMessaging, "MentionRead", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

func (b *BaleCore) UserMessageReceived(chatID string, dateMs int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "MessageReceived", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": dateMs,
	})
}

func (b *BaleCore) UserFetchProtectedMessage(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceMessaging, "FetchProtectedMessage", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

func (b *BaleCore) UserGetMessagesRepliesInfo(chatID string, msgIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	msgs := make([]map[string]interface{}, len(msgIDs))
	for i, mid := range msgIDs {
		rid, dateMs := parseMsgIDWithDate(mid)
		msgs[i] = map[string]interface{}{"1": dateMs, "2": rid}
	}
	return b.userSend(baleServiceMessaging, "GetMessagesRepliesInfo", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": msgs,
	})
}

func (b *BaleCore) UserGetDiscussionMessage(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceMessaging, "GetDiscussionMessage", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

func (b *BaleCore) UserCreateThread(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceMessaging, "CreateThread", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

func (b *BaleCore) UserCreateTopic(chatID string, title string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "CreateTopic", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": title,
	})
}

func (b *BaleCore) UserGetTopics(chatID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "GetTopics", map[string]interface{}{
		"1": balePeer(peerType, peerID),
	})
}

func (b *BaleCore) UserGetTopicByID(chatID string, topicID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "GetTopicByID", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": topicID,
	})
}

// =============================================================================
// Missing Groups methods (bale.groups.v1.Groups)
// =============================================================================

func (b *BaleCore) UserLoadFullGroups(groupIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(groupIDs))
	for i, gid := range groupIDs {
		peers[i] = baleGroupOutPeer(gid)
	}
	return b.userSend(baleServiceGroups, "LoadFullGroups", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserGetMyGroups() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceGroups, "GetMyGroups", map[string]interface{}{})
}

func (b *BaleCore) UserLoadGroupAvatars(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceGroups, "LoadGroupAvatars", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

func (b *BaleCore) UserEditGroupDefaultCardNumber(groupID int64, cardNumber string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "EditGroupDefaultCardNumber", map[string]interface{}{
		"1": baleShortPeer(gid),
		"2": cardNumber,
	})
}

func (b *BaleCore) UserGetGroupDefaultCardNumber(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "GetGroupDefaultCardNumber", map[string]interface{}{
		"1": baleShortPeer(gid),
	})
}

func (b *BaleCore) UserInviteUser(groupID int64, userID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "InviteUser", map[string]interface{}{
		"1": baleShortPeer(gid),
		"2": baleUserOutPeer(userID),
	})
}

func (b *BaleCore) UserSetCanSeeMessages(groupID int64, canSee bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "SetCanSeeMessages", map[string]interface{}{
		"1": baleShortPeer(gid),
		"2": canSee,
	})
}

func (b *BaleCore) UserGetCanSeeMessages(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "GetCanSeeMessages", map[string]interface{}{
		"1": baleShortPeer(gid),
	})
}

func (b *BaleCore) UserFetchGroupAdmins(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "FetchGroupAdmins", map[string]interface{}{
		"1": baleShortPeer(gid),
	})
}

func (b *BaleCore) UserLoadGroups(groupIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(groupIDs))
	for i, gid := range groupIDs {
		peers[i] = baleGroupOutPeer(gid)
	}
	return b.userSend(baleServiceGroups, "LoadGroups", map[string]interface{}{"1": peers})
}

func (b *BaleCore) UserSetAvailableReactions(groupID int64, reactions []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "SetAvailableReactions", map[string]interface{}{
		"1": baleShortPeer(gid),
		"2": reactions,
	})
}

func (b *BaleCore) UserGetMutualGroups(userID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceGroups, "GetMutualGroups", map[string]interface{}{
		"1": baleUserOutPeer(userID),
	})
}

func (b *BaleCore) UserSetDiscussionGroup(channelID int64, groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	chID, err := b.resolveGroupInternalID(channelID)
	if err != nil {
		return nil, err
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "SetDiscussionGroup", map[string]interface{}{
		"1": baleShortPeer(chID),
		"2": baleShortPeer(gid),
	})
}

func (b *BaleCore) UserRemoveDiscussionGroup(channelID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	chID, err := b.resolveGroupInternalID(channelID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "RemoveDiscussionGroup", map[string]interface{}{
		"1": baleShortPeer(chID),
	})
}

func (b *BaleCore) UserAddDiscussionGroupAdmin(channelID int64, userID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	chID, err := b.resolveGroupInternalID(channelID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "AddDiscussionGroupAdmin", map[string]interface{}{
		"1": baleShortPeer(chID),
		"2": baleUserOutPeer(userID),
	})
}

func (b *BaleCore) UserSetCanSeeHistory(groupID int64, canSee bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "SetCanSeeHistory", map[string]interface{}{
		"1": baleShortPeer(gid),
		"2": canSee,
	})
}

func (b *BaleCore) UserGetGroupRecommendations(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceGroups, "GetGroupRecommendations", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

func (b *BaleCore) UserSetMemberCustomTitle(groupID int64, userID int64, title string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	gid, err := b.resolveGroupInternalID(groupID)
	if err != nil {
		return nil, err
	}
	return b.userSend(baleServiceGroups, "SetMemberCustomTitle", map[string]interface{}{
		"1": baleShortPeer(gid),
		"2": baleUserOutPeer(userID),
		"3": title,
	})
}

// =============================================================================
// Missing Meet methods (bale.meet.v1.Meet)
// =============================================================================

func (b *BaleCore) UserAcceptCallMeet(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "AcceptCall", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserGetCallState(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "GetCallState", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserDeleteCallLogs(callIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "DeleteCallLogs", map[string]interface{}{"1": callIDs})
}

func (b *BaleCore) UserInviteToCall(callID int64, userIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	users := make([]map[string]interface{}, len(userIDs))
	for i, uid := range userIDs {
		users[i] = baleUserOutPeer(uid)
	}
	return b.userSend(baleServiceMeet, "InviteToCall", map[string]interface{}{
		"1": callID,
		"2": users,
	})
}

func (b *BaleCore) UserAskToJoinCall(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "AskToJoinCall", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserAnswerCallJoinRequest(callID int64, userID int64, accept bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "AnswerCallJoinRequest", map[string]interface{}{
		"1": callID,
		"2": baleUserOutPeer(userID),
		"3": accept,
	})
}

func (b *BaleCore) UserSendCallReaction(callID int64, reaction string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "SendCallReaction", map[string]interface{}{
		"1": callID,
		"2": reaction,
	})
}

func (b *BaleCore) UserSubmitCallFeedback(callID int64, rating int, comment string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "SubmitCallFeedback", map[string]interface{}{
		"1": callID,
		"2": int64(rating),
		"3": comment,
	})
}

func (b *BaleCore) UserMuteCallParticipant(callID int64, userID int64, muted bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "MuteParticipant", map[string]interface{}{
		"1": callID,
		"2": baleUserOutPeer(userID),
		"3": muted,
	})
}

func (b *BaleCore) UserRemoveCallParticipant(callID int64, userID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "RemoveParticipant", map[string]interface{}{
		"1": callID,
		"2": baleUserOutPeer(userID),
	})
}

func (b *BaleCore) UserStartRecording(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "StartRecording", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserStopRecording(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "StopRecording", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserStartStream(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "StartStream", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserDeleteStream(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "DeleteStream", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserUpdateCallLayout(callID int64, layout int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "UpdateLayout", map[string]interface{}{
		"1": callID,
		"2": int64(layout),
	})
}

func (b *BaleCore) UserGenerateCallLink(callID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "GenerateCallLink", map[string]interface{}{"1": callID})
}

func (b *BaleCore) UserGetCallLinkDetails(link string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "GetCallLinkDetails", map[string]interface{}{"1": link})
}

func (b *BaleCore) UserSetCallLinkTitle(callID int64, title string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "SetLinkTitle", map[string]interface{}{
		"1": callID,
		"2": title,
	})
}

func (b *BaleCore) UserSendCallFanoosEvent(callID int64, eventName string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "SendFanoosEvent", map[string]interface{}{
		"1": callID,
		"2": eventName,
	})
}

func (b *BaleCore) UserTakeCallAction(callID int64, action int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMeet, "TakeCallAction", map[string]interface{}{
		"1": callID,
		"2": int64(action),
	})
}

// =============================================================================
// Missing Presence methods (bale.presence.v1.Presence)
// =============================================================================

func (b *BaleCore) UserGetContactsPresences() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServicePresence, "GetContactsPresences", map[string]interface{}{})
}

func (b *BaleCore) UserGetGroupMembersPresences(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServicePresence, "GetGroupMembersPresences", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

func (b *BaleCore) UserGetGroupOnlineCount(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServicePresence, "GetGroupOnlineCount", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

func (b *BaleCore) UserGetUsersPresence(userIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	users := make([]map[string]interface{}, len(userIDs))
	for i, uid := range userIDs {
		users[i] = baleUserOutPeer(uid)
	}
	return b.userSend(baleServicePresence, "GetUsersPresence", map[string]interface{}{"1": users})
}

func (b *BaleCore) UserSubscribeToOnline(userIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	users := make([]map[string]interface{}, len(userIDs))
	for i, uid := range userIDs {
		users[i] = baleUserOutPeer(uid)
	}
	return b.userSend(baleServicePresence, "SubscribeToOnline", map[string]interface{}{"1": users})
}

func (b *BaleCore) UserSubscribeFromOnline(userIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	users := make([]map[string]interface{}, len(userIDs))
	for i, uid := range userIDs {
		users[i] = baleUserOutPeer(uid)
	}
	return b.userSend(baleServicePresence, "SubscribeFromOnline", map[string]interface{}{"1": users})
}

func (b *BaleCore) UserSubscribeToGroupOnline(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServicePresence, "SubscribeToGroupOnline", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

func (b *BaleCore) UserSubscribeFromGroupOnline(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServicePresence, "SubscribeFromGroupOnline", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

// =============================================================================
// Missing Abacus methods (bale.abacus.v1.Abacus)
// =============================================================================

func (b *BaleCore) UserEnableShowReactionFlag(enabled bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAbacus, "EnableShowReactionFlag", map[string]interface{}{"1": enabled})
}

func (b *BaleCore) UserGetShowReactionFlag() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAbacus, "GetShowReactionFlag", map[string]interface{}{})
}

func (b *BaleCore) UserLoadReactions() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAbacus, "LoadReactions", map[string]interface{}{})
}

func (b *BaleCore) UserMessageReactionsRead(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceAbacus, "MessageReactionsRead", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

// =============================================================================
// New service: Poll (bale.poll.v1.Poll)
// =============================================================================

func (b *BaleCore) UserCreatePoll(chatID string, question string, options []string, multipleChoice bool, anonymous bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	optionMsgs := make([]map[string]interface{}, len(options))
	for i, opt := range options {
		optionMsgs[i] = map[string]interface{}{"1": opt}
	}
	return b.userSend(baleServicePoll, "CreatePoll", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": question,
		"3": optionMsgs,
		"4": multipleChoice,
		"5": anonymous,
		"6": baleRID(),
	})
}

func (b *BaleCore) UserClosePollService(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServicePoll, "ClosePoll", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": dateMs,
	})
}

func (b *BaleCore) UserVotePollService(chatID string, msgID string, optionIndices []int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	indices := make([]int64, len(optionIndices))
	for i, idx := range optionIndices {
		indices[i] = int64(idx)
	}
	return b.userSend(baleServicePoll, "Vote", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": dateMs,
		"4": indices,
	})
}

func (b *BaleCore) UserGetPollResultsService(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServicePoll, "GetPollResults", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": dateMs,
	})
}

func (b *BaleCore) UserGetFullPollResultService(chatID string, msgID string, optionIndex int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServicePoll, "GetFullPollResult", map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": dateMs,
		"4": int64(optionIndex),
	})
}

// =============================================================================
// New service: Search (bale.search.v1.Search)
// =============================================================================

func (b *BaleCore) UserSearchMessages(query string, chatID string, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	payload := map[string]interface{}{
		"1": query,
		"3": int64(limit),
	}
	if chatID != "" {
		id, pt := parsePeerID(chatID)
		payload["2"] = balePeer(pt, id)
	}
	return b.userSend(baleServiceSearch, "SearchMessages", payload)
}

func (b *BaleCore) UserSearchMessageMore(query string, chatID string, offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	payload := map[string]interface{}{
		"1": query,
		"3": int64(limit),
		"4": offset,
	}
	if chatID != "" {
		id, pt := parsePeerID(chatID)
		payload["2"] = balePeer(pt, id)
	}
	return b.userSend(baleServiceSearch, "SearchMessageMore", payload)
}

func (b *BaleCore) UserSearchPeer(query string, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceSearch, "SearchPeer", map[string]interface{}{
		"1": query,
		"2": int64(limit),
	})
}

func (b *BaleCore) UserSearchMediaService(chatID string, mediaType int, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceSearch, "SearchMedia", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": int64(mediaType),
		"3": int64(limit),
	})
}

func (b *BaleCore) UserSearchMembersService(chatID string, query string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceSearch, "SearchMembers", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": query,
	})
}

func (b *BaleCore) UserSearchDialog(query string, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceSearch, "SearchDialog", map[string]interface{}{
		"1": query,
		"2": int64(limit),
	})
}

func (b *BaleCore) UserSearchContent(query string, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceSearch, "SearchContent", map[string]interface{}{
		"1": query,
		"2": int64(limit),
	})
}

func (b *BaleCore) UserUpdateSearchContentClick(contentID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceSearch, "UpdateSearchContentClick", map[string]interface{}{"1": contentID})
}

// =============================================================================
// New service: Story (bale.story.v1.Story)
// =============================================================================

func (b *BaleCore) UserAddStory(content map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "AddStory", content)
}

func (b *BaleCore) UserAddChannelStory(channelID int64, content map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	content["1"] = baleGroupOutPeer(channelID)
	return b.userSend(baleServiceStory, "AddChannelStory", content)
}

func (b *BaleCore) UserAddBotStory(botID int64, content map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	content["1"] = baleUserOutPeer(botID)
	return b.userSend(baleServiceStory, "AddBotStory", content)
}

func (b *BaleCore) UserCanAddBotStory(botID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "CanAddBotStory", map[string]interface{}{
		"1": baleUserOutPeer(botID),
	})
}

func (b *BaleCore) UserRemoveStory(storyID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "RemoveStory", map[string]interface{}{"1": storyID})
}

func (b *BaleCore) UserGetStoryViewers(storyID int64, offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetViewers", map[string]interface{}{
		"1": storyID,
		"2": offset,
		"3": int64(limit),
	})
}

func (b *BaleCore) UserGetStoryViewersCount(storyID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetViewersCount", map[string]interface{}{"1": storyID})
}

func (b *BaleCore) UserGetStories(peerID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetStories", map[string]interface{}{
		"1": baleUserOutPeer(peerID),
	})
}

func (b *BaleCore) UserGetChannelStories(channelID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetChannelStories", map[string]interface{}{
		"1": baleGroupOutPeer(channelID),
	})
}

func (b *BaleCore) UserGetBotStories(botID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetBotStories", map[string]interface{}{
		"1": baleUserOutPeer(botID),
	})
}

func (b *BaleCore) UserReactToStory(storyID int64, reaction string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "ReactToStory", map[string]interface{}{
		"1": storyID,
		"2": reaction,
	})
}

func (b *BaleCore) UserGetStoryByID(storyID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetStoryById", map[string]interface{}{"1": storyID})
}

func (b *BaleCore) UserGetStoryPrivacyConfig() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetUserPrivacyConfig", map[string]interface{}{})
}

func (b *BaleCore) UserSetStoryPrivacyConfig(config map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "SetUserPrivacyConfig", config)
}

func (b *BaleCore) UserGetDefaultStoryBackgrounds() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetDefaultStoryBackgrounds", map[string]interface{}{})
}

func (b *BaleCore) UserGetMostPopularStories() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetMostPopularStories", map[string]interface{}{})
}

func (b *BaleCore) UserGetStoryWidgets() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetStoryWidgets", map[string]interface{}{})
}

func (b *BaleCore) UserGetUserStoryConfig() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetUserStoryConfig", map[string]interface{}{})
}

func (b *BaleCore) UserSetUserStoryConfig(config map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "SetUserStoryConfig", config)
}

func (b *BaleCore) UserGetStoriesByList(storyIDs []int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetStoriesByList", map[string]interface{}{"1": storyIDs})
}

func (b *BaleCore) UserGetStoryReactionEmojis() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetStoryReactionEmojis", map[string]interface{}{})
}

func (b *BaleCore) UserGetStoryTags() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "GetStoryTags", map[string]interface{}{})
}

func (b *BaleCore) UserCheckStoryLinkValidity(link string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceStory, "CheckLinkValidity", map[string]interface{}{"1": link})
}

// =============================================================================
// New service: Ketf/Bots (bale.ketf.v1.Ketf)
// =============================================================================

func (b *BaleCore) UserAddGif(fileID int64, accessHash int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "AddGif", map[string]interface{}{
		"1": fileID, "2": accessHash,
	})
}

func (b *BaleCore) UserRemoveGif(fileID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "RemoveGif", map[string]interface{}{"1": fileID})
}

func (b *BaleCore) UserUseGif(fileID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "UseGif", map[string]interface{}{"1": fileID})
}

func (b *BaleCore) UserGetSavedGifs() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetSavedGifs", map[string]interface{}{})
}

func (b *BaleCore) UserAddStickerCollection(collectionID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "AddStickerCollection", map[string]interface{}{"1": collectionID})
}

func (b *BaleCore) UserRemoveStickerCollection(collectionID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "RemoveStickerCollection", map[string]interface{}{"1": collectionID})
}

func (b *BaleCore) UserAddStickerPack(packID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "AddStickerPack", map[string]interface{}{"1": packID})
}

func (b *BaleCore) UserRemoveStickerPack(packID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "RemoveStickerPack", map[string]interface{}{"1": packID})
}

func (b *BaleCore) UserLoadOwnStickers() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "LoadOwnStickers", map[string]interface{}{})
}

func (b *BaleCore) UserLoadStickerCollection(collectionID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "LoadStickerCollection", map[string]interface{}{"1": collectionID})
}

func (b *BaleCore) UserSendInlineCallBackData(botID int64, queryID string, data string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "SendInlineCallBackData", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": queryID,
		"3": data,
	})
}

func (b *BaleCore) UserSendInlineCallback(botID int64, queryID string, data string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "SendInlineCallback", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": queryID,
		"3": data,
	})
}

func (b *BaleCore) UserSendAuthenticatedInlineCallBackData(botID int64, queryID string, data string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "SendAuthenticatedInlineCallBackData", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": queryID,
		"3": data,
	})
}

func (b *BaleCore) UserSendMiniAppData(botID int64, data string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "SendMiniAppData", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": data,
	})
}

func (b *BaleCore) UserGetBotWhiteList() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetBotWhiteList", map[string]interface{}{})
}

func (b *BaleCore) UserGetUserContext(botID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetUserContext", map[string]interface{}{
		"1": baleUserOutPeer(botID),
	})
}

func (b *BaleCore) UserGetWebappHash(botID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetWebappHash", map[string]interface{}{
		"1": baleUserOutPeer(botID),
	})
}

func (b *BaleCore) UserGetBots() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetBots", map[string]interface{}{})
}

func (b *BaleCore) UserGetBotInfo(botID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetBotInfo", map[string]interface{}{
		"1": baleUserOutPeer(botID),
	})
}

func (b *BaleCore) UserGetInlineBotResults(botID int64, query string, offset string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetInlineBotResults", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": query,
		"3": offset,
	})
}

func (b *BaleCore) UserGetBotGroupPermissions(botID int64, groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetBotGroupPermissions", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": baleGroupOutPeer(groupID),
	})
}

func (b *BaleCore) UserGetPaymentDetails(paymentID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "GetPaymentDetails", map[string]interface{}{"1": paymentID})
}

func (b *BaleCore) UserMakePayment(paymentID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "MakePayment", map[string]interface{}{"1": paymentID})
}

func (b *BaleCore) UserInvokeCustomAction(botID int64, action string, data string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceKetf, "InvokeCustomAction", map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": action,
		"3": data,
	})
}

// =============================================================================
// New service: MavizStream (bale.maviz.v1.MavizStream)
// =============================================================================

func (b *BaleCore) UserSubscribeToUpdates() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMaviz, "SubscribeToUpdates", map[string]interface{}{})
}

func (b *BaleCore) UserGetDifference(seq int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMaviz, "GetDifference", map[string]interface{}{"1": seq})
}

func (b *BaleCore) UserSubscribeToThreadUpdates(chatID string, threadID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceMaviz, "SubscribeToThreadUpdates", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": threadID,
	})
}

func (b *BaleCore) UserUnsubscribeFromThreadUpdates(chatID string, threadID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceMaviz, "UnsubscribeFromThreadUpdates", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": threadID,
	})
}

// =============================================================================
// New service: MessageStream (bale.message_stream.v1.MessageStream)
// =============================================================================

func (b *BaleCore) UserCancelMessageStream(streamID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMsgStream, "CancelMessageStream", map[string]interface{}{"1": streamID})
}

func (b *BaleCore) UserReceiveMessageStream(streamID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMsgStream, "ReceiveMessageStream", map[string]interface{}{"1": streamID})
}

// =============================================================================
// New service: Scheduler (bale.schedule.v1.Scheduler)
// =============================================================================

func (b *BaleCore) UserScheduleTask(chatID string, task map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	task["1"] = balePeer(pt, id)
	return b.userSend(baleServiceScheduler, "ScheduleTask", task)
}

func (b *BaleCore) UserUnScheduleTask(taskID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceScheduler, "UnScheduleTask", map[string]interface{}{"1": taskID})
}

func (b *BaleCore) UserListScheduledTasks(chatID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceScheduler, "ListTasks", map[string]interface{}{
		"1": balePeer(pt, id),
	})
}

func (b *BaleCore) UserExecuteTaskNow(taskID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceScheduler, "ExecuteTaskNow", map[string]interface{}{"1": taskID})
}

func (b *BaleCore) UserReScheduleTask(taskID int64, newDate int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceScheduler, "ReScheduleTask", map[string]interface{}{
		"1": taskID,
		"2": newDate,
	})
}

func (b *BaleCore) UserPeersWithScheduleTask() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceScheduler, "PeersWithScheduleTask", map[string]interface{}{})
}

// =============================================================================
// New service: TLDR (bale.tldr.v1.TLDR)
// =============================================================================

func (b *BaleCore) UserGetLinkSummary(url string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceTLDR, "GetLinkSummary", map[string]interface{}{"1": url})
}

func (b *BaleCore) UserGetLinkPreview(url string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceTLDR, "GetLinkPreview", map[string]interface{}{"1": url})
}

// =============================================================================
// New service: Negah (bale.negah.v1.Negah)
// =============================================================================

func (b *BaleCore) UserGetMessageSeenList(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceNegah, "GetMessageSeenList", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

// =============================================================================
// New service: SharedMedia (bale.shared_media.v1.SharedMediaService)
// =============================================================================

func (b *BaleCore) UserLoadSharedMedia(chatID string, mediaType int, offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceSharedMedia, "LoadMedia", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": int64(mediaType),
		"3": offset,
		"4": int64(limit),
	})
}

func (b *BaleCore) UserGetActiveSharedMedia(chatID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	return b.userSend(baleServiceSharedMedia, "GetActiveSharedMedia", map[string]interface{}{
		"1": balePeer(pt, id),
	})
}

// =============================================================================
// New service: TopPeer (bale.top_peer.v1.TopPeer)
// =============================================================================

func (b *BaleCore) UserGetTopPeer() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceTopPeer, "GetTopPeer", map[string]interface{}{})
}

func (b *BaleCore) UserRemoveTopPeer(peerID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(peerID)
	return b.userSend(baleServiceTopPeer, "RemovePeer", map[string]interface{}{
		"1": balePeer(pt, id),
	})
}

// =============================================================================
// New service: Recommender (bale.recommender.v1.Recommender)
// =============================================================================

func (b *BaleCore) UserGetChannelRecommendations(channelID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceRecommender, "GetChannelRecommendations", map[string]interface{}{
		"1": baleGroupOutPeer(channelID),
	})
}

func (b *BaleCore) UserGetRelatedChannels(channelID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceRecommender, "GetRelatedChannels", map[string]interface{}{
		"1": baleGroupOutPeer(channelID),
	})
}

func (b *BaleCore) UserGetGroupsRecommendation() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceRecommender, "GetGroupsRecommendation", map[string]interface{}{})
}

func (b *BaleCore) UserGetRelatedGroups(groupID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceRecommender, "GetRelatedGroups", map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
	})
}

// =============================================================================
// New service: AnonymousContact (bale.anonymous_contact.v1.AnonymousContact)
// =============================================================================

func (b *BaleCore) UserGetAnonymousContactPage() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAnonContact, "GetUserAnonymousContactPage", map[string]interface{}{})
}

// =============================================================================
// New service: Falake (bale.falake.v1.Falake)
// =============================================================================

func (b *BaleCore) UserGetLinkStatus(link string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceFalake, "GetLinkStatus", map[string]interface{}{"1": link})
}

// =============================================================================
// New service: LLMAuth (bale.llm_auth.v1.LLMAuthService)
// =============================================================================

func (b *BaleCore) UserGetLLMAuthToken() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceLLMAuth, "GetAuthToken", map[string]interface{}{})
}

// =============================================================================
// New service: Organizations (bale.organizations.v1.Organizations)
// =============================================================================

func (b *BaleCore) UserGetOrganizationalContacts() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceOrgs, "GetUserOrganizationalContacts", map[string]interface{}{})
}

func (b *BaleCore) UserGetOrganizationInfo() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceOrgs, "GetUserOrganizationInfo", map[string]interface{}{})
}

// =============================================================================
// New service: Appzar (bale.appzar.v1.Appzar)
// =============================================================================

func (b *BaleCore) UserGetMiniAppUrlAppzar(botID int64, shortName string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAppzar, "GetMiniAppUrl", map[string]interface{}{
		"1": botID,
		"2": shortName,
	})
}

func (b *BaleCore) UserGetMenuButton(botID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAppzar, "GetMenuButton", map[string]interface{}{"1": botID})
}

func (b *BaleCore) UserInvokeCustomMethodAppzar(botID int64, method string, params string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAppzar, "InvokeCustomMethod", map[string]interface{}{
		"1": botID,
		"2": method,
		"3": params,
	})
}

// =============================================================================
// New service: AI (bale.turing.v1.AI)
// =============================================================================

func (b *BaleCore) UserAISendEvent(eventData map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceTuringAI, "SendEvent", eventData)
}

func (b *BaleCore) UserAIGetTranscript(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceTuringAI, "GetTranscript", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

// =============================================================================
// New service: CrowdFunding (bale.crowdfunding.v1.CrowdFunding)
// =============================================================================

// =============================================================================
// Missing GiftPacket method
// =============================================================================

// =============================================================================
// Missing Magazine methods
// =============================================================================

func (b *BaleCore) UserGetMyUpvotes(offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMagazine, "GetMyUpvotes", map[string]interface{}{
		"1": offset, "2": int64(limit),
	})
}

func (b *BaleCore) UserLoadFeedMessages(offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMagazine, "LoadFeedMessages", map[string]interface{}{
		"1": offset, "2": int64(limit),
	})
}

func (b *BaleCore) UserLoadInternalFeedMessages(offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMagazine, "LoadInternalFeedMessages", map[string]interface{}{
		"1": offset, "2": int64(limit),
	})
}

func (b *BaleCore) UserLoadCategoryFeedMessages(categoryID int64, offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMagazine, "LoadCategoryFeedMessages", map[string]interface{}{
		"1": categoryID, "2": offset, "3": int64(limit),
	})
}

func (b *BaleCore) UserLoadMagazineCategories() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMagazine, "LoadCategories", map[string]interface{}{})
}

func (b *BaleCore) UserGetSimilarPosts(chatID string, msgID string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	id, pt := parsePeerID(chatID)
	rid, dateMs := parseMsgIDWithDate(msgID)
	return b.userSend(baleServiceMagazine, "GetSimilarPosts", map[string]interface{}{
		"1": balePeer(pt, id),
		"2": map[string]interface{}{"1": dateMs, "2": rid},
	})
}

// =============================================================================
// Missing Files methods
// =============================================================================

func (b *BaleCore) UserGetNasimFileUrls(fileIDs []map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceFiles, "GetNasimFileUrls", map[string]interface{}{"1": fileIDs})
}

func (b *BaleCore) UserGetNasimFileUploadResume(fileID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceFiles, "GetNasimFileUploadResume", map[string]interface{}{"1": fileID})
}

func (b *BaleCore) UserFileUploadCancel(fileID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceFiles, "FileUploadCancel", map[string]interface{}{"1": fileID})
}

func (b *BaleCore) UserGetNasimFilePublicUrl(fileID int64, accessHash int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceFiles, "GetNasimFilePublicUrl", map[string]interface{}{
		"1": fileID, "2": accessHash,
	})
}

// =============================================================================
// Advertisement — bale.advertisement.v1.Advertisement (108 methods)
// =============================================================================

// =============================================================================
// Arbaeen — bale.arbaeen.v1.Arbaeen (19 methods)
// =============================================================================

// =============================================================================
// Evex — bale.evex.v1.Evex (8 methods)
// =============================================================================

// =============================================================================
// Exchange — bale.exchange.v1.Exchange (10 methods)
// =============================================================================

// =============================================================================
// Sarrafi — bale.sarrafi.v1.Sarrafi (9 methods)
// =============================================================================

// =============================================================================
// Miscellaneous missing from existing services
// =============================================================================

func (b *BaleCore) UserSetMyCommands(commands []map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	return b.userSend(baleServiceMessaging, "SetMyCommands", map[string]interface{}{"1": commands})
}

func (b *BaleCore) UserDeleteMyCommands() (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	return b.userSend(baleServiceMessaging, "DeleteMyCommands", map[string]interface{}{})
}

func (b *BaleCore) UserGetMyCommands() (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	return b.userSend(baleServiceMessaging, "GetMyCommands", map[string]interface{}{})
}

func (b *BaleCore) UserTerminateSession(sessionID int64) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	return b.userSend(baleServiceMessaging, "TerminateSession", map[string]interface{}{"1": sessionID})
}

func (b *BaleCore) UserCreateFolder(title string, peerIDs []string) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peers := make([]map[string]interface{}, len(peerIDs))
	for i, pid := range peerIDs {
		id, pt := parsePeerID(pid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "CreateFolder", map[string]interface{}{"1": title, "2": peers})
}

func (b *BaleCore) UserLoadDialogsFiltered(filterType int, offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	return b.userSend(baleServiceMessaging, "LoadDialogsFiltered", map[string]interface{}{
		"1": int64(filterType), "2": offset, "3": int64(limit),
	})
}

func (b *BaleCore) UserPushSetConfig(config map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	return b.userSend(baleServiceMessaging, "PushSetConfig", config)
}

func (b *BaleCore) UserMarkAsUnread(chatID string, unread bool) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "MarkAsUnread", map[string]interface{}{
		"1": balePeer(peerType, peerID), "2": unread,
	})
}

func (b *BaleCore) UserSendScheduledMessage(chatID string, date int64, msg map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	msg["1"] = balePeer(peerType, peerID)
	msg["2"] = date
	return b.userSend(baleServiceMessaging, "SendScheduledMessage", msg)
}

func (b *BaleCore) UserSendProtectedMessage(chatID string, msg map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	msg["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendProtectedMessage", msg)
}

func (b *BaleCore) UserSendLongTextMessage(chatID string, text string) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "SendLongTextMessage", map[string]interface{}{
		"1": balePeer(peerType, peerID), "2": text,
	})
}

func (b *BaleCore) UserSendBankMessage(chatID string, bankMsg map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	bankMsg["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendBankMessage", bankMsg)
}

func (b *BaleCore) UserSendJsonMessage(chatID string, jsonData string) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "SendJsonMessage", map[string]interface{}{
		"1": balePeer(peerType, peerID), "2": jsonData,
	})
}

func (b *BaleCore) UserSendOrderMessage(chatID string, order map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	order["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendOrderMessage", order)
}

func (b *BaleCore) UserSendAnimatedSticker(chatID string, stickerData map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	stickerData["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendAnimatedSticker", stickerData)
}

func (b *BaleCore) UserSendLiveMessage(chatID string, liveData map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed { return nil, ErrAuth }
	peerID, peerType := parsePeerID(chatID)
	liveData["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendLiveMessage", liveData)
}
