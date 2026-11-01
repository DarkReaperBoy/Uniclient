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
	"net/http/cookiejar"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"uniclient/utils"

	"github.com/coder/websocket"
)

var baleFallbackIPs = map[string][]string{
	"tapi.bale.ai":     {"2.189.68.126"},
	"next-ws.bale.ai":  {"2.189.68.126"},
	"bale.ai":          {"2.189.68.126"},
	"www.bale.ai":      {"2.189.68.126"},
	"beta.bale.ai":     {"2.189.68.126"},
	"business.bale.ai": {"2.189.68.126"},
	"docs.bale.ai":     {"2.189.68.126"},
	"maviz.bale.ai":    {"2.189.68.126"},
	"meet.bale.ai":     {"2.189.68.126"},
	"ble.ir":           {"2.189.68.126"},
	"www.ble.ir":       {"2.189.68.126"},
	"l.ble.ir":         {"2.189.68.126"},
	"contest.bale.ai":  {"2.189.68.126"},

	"api.bale.ai":    {"2.189.68.126"},
	"meetbm.bale.ai": {"2.189.68.126"},

	"cdn-siloo.ble.ir":       {"185.166.104.6"},
	"video-cdn-siloo.ble.ir": {"185.166.104.6"},
	"bale.sh":                {"185.166.104.6"},
	"sentry.bale.sh":         {"185.166.104.6"},
}

type BaleCore struct {
	mu sync.RWMutex
	wg sync.WaitGroup

	botToken string
	botInfo  *User
	authed   bool
	isBot    bool

	httpClient *http.Client
	baseURL    string

	session *utils.SessionStore

	updateOffset   int64
	updateHandlers []func(Update)
	updateMu       sync.RWMutex
	pollCtx        context.Context
	pollCancel     context.CancelFunc

	userToken   string
	userID      int64
	userPhone   string
	wsConn      *websocket.Conn
	wsCtx       context.Context
	wsCancel    context.CancelFunc
	wsIndex     int64
	wsPending   map[int64]chan map[string]interface{}
	wsPendMu    sync.Mutex
	wsPingID    int64
	wsSessionID string
	wsMeta      map[string]interface{}
	wsReady     chan struct{}

	ctx    context.Context
	cancel context.CancelFunc

	groupIDCache   map[int64]int64
	groupIDCacheMu sync.RWMutex

	activeCall   *baleActiveCall
	activeCallMu sync.Mutex

	authCodeCh    chan string
	authCodeReady chan struct{}
	authPwdCh     chan string
	authPwdReady  chan struct{}
	authDoneCh    chan struct{}
	authErrCh     chan error
	authSetupDone chan struct{}
}

var _ Core = (*BaleCore)(nil)

type baleActiveCall struct {
	session *CallSession
	muted   bool
	done    chan struct{}
	impl    any
}

type baleSession struct {
	BotToken  string `json:"bot_token,omitempty"`
	BotID     string `json:"bot_id,omitempty"`
	UserToken string `json:"user_token,omitempty"`
	UserID    int64  `json:"user_id,omitempty"`
	Phone     string `json:"phone,omitempty"`
}

type BaleChatInfo struct {
	ID        int64  `json:"id"`
	Type      string `json:"type"`
	Title     string `json:"title,omitempty"`
	Username  string `json:"username,omitempty"`
	FirstName string `json:"first_name,omitempty"`
	LastName  string `json:"last_name,omitempty"`
}

type BaleChatMember struct {
	User   BaleUserInfo `json:"user"`
	Status string       `json:"status"`
}

type BaleUserInfo struct {
	ID        int64  `json:"id"`
	IsBot     bool   `json:"is_bot"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name,omitempty"`
	Username  string `json:"username,omitempty"`
}

type BaleFileInfo struct {
	FileID   string `json:"file_id"`
	FileSize int64  `json:"file_size"`
	FilePath string `json:"file_path"`
}

type BaleWebhookInfo struct {
	URL                  string `json:"url"`
	HasCustomCertificate bool   `json:"has_custom_certificate"`
	PendingUpdateCount   int    `json:"pending_update_count"`
}

type BaleStickerSet struct {
	Name       string `json:"name"`
	Title      string `json:"title"`
	IsAnimated bool   `json:"is_animated"`
}

type BaleUserProfilePhotos struct {
	TotalCount int `json:"total_count"`
}

func baleParseResult[T any](data map[string]interface{}) (T, error) {
	var result T
	raw, ok := data["result"]
	if !ok {
		raw = data
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return result, err
	}
	err = json.Unmarshal(b, &result)
	return result, err
}

func newBaleHTTPClient(timeout time.Duration) *http.Client {
	probeTimeout := 5 * time.Second

	transport := &http.Transport{
		DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(addr)
			if err != nil {
				host = addr
				port = "443"
			}

			conn, firstErr := dialTLS(host, addr, probeTimeout)
			if firstErr == nil {
				return conn, nil
			}

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

	jar, _ := cookiejar.New(nil)
	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
		Jar:       jar,
	}
}

func dialTLS(sniHost string, addr string, timeout time.Duration) (net.Conn, error) {
	dialer := &net.Dialer{Timeout: timeout}
	conn, err := dialer.Dial("tcp", addr)
	if err != nil {
		return nil, err
	}

	tlsConn := tls.Client(conn, &tls.Config{
		ServerName: sniHost,
	})

	if err := tlsConn.SetDeadline(time.Now().Add(timeout)); err != nil {
		conn.Close()
		return nil, err
	}
	if err := tlsConn.Handshake(); err != nil {
		conn.Close()
		return nil, err
	}
	tlsConn.SetDeadline(time.Time{})

	return tlsConn, nil
}

func NewBaleCore(session *utils.SessionStore) *BaleCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &BaleCore{
		httpClient:    newBaleHTTPClient(60 * time.Second),
		baseURL:       "https://tapi.bale.ai",
		session:       session,
		groupIDCache:  make(map[int64]int64),
		ctx:           ctx,
		cancel:        cancel,
		authSetupDone: make(chan struct{}),
	}
}

const balePlatform = "bale"

func (b *BaleCore) Name() string { return balePlatform }

func (b *BaleCore) GetUserID() int64 { return b.userID }

func PbEncode(fields map[string]interface{}) []byte { return pbEncode(fields) }

func (b *BaleCore) UserHTTPPost(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	return b.wsPost(service, method, payload, b.userToken)
}
func PbGetInt64(m map[string]interface{}, field string) int64   { return pbGetInt64(m, field) }
func PbGetString(m map[string]interface{}, field string) string { return pbGetString(m, field) }
func PbGetMsg(m map[string]interface{}, field string) map[string]interface{} {
	return pbGetMsg(m, field)
}
func PbGetList(m map[string]interface{}, field string) []interface{} { return pbGetList(m, field) }
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
	DrainBodyLimited(resp.Body)
	if resp.StatusCode >= 400 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return nil
}

func (b *BaleCore) resolveGroupInternalID(peerID int64) (int64, error) {
	b.groupIDCacheMu.RLock()
	if cached, ok := b.groupIDCache[peerID]; ok {
		b.groupIDCacheMu.RUnlock()
		return cached, nil
	}
	b.groupIDCacheMu.RUnlock()

	resp, err := b.UserGetFullGroup(peerID)
	if err != nil {
		return 0, fmt.Errorf("resolveGroupInternalID: %w", err)
	}
	groupData := pbGetMsg(resp, "1")
	internalID := pbGetInt64(groupData, "1")
	if internalID == 0 {
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

func (b *BaleCore) Authenticate(cfg AuthConfig) error {
	b.mu.Lock()

	if cfg.Mode == AuthModeBot {
		defer b.mu.Unlock()
		close(b.authSetupDone)
		return b.authBot(cfg.BotToken)
	}

	if cfg.OTP == "" {
		b.authCodeCh = make(chan string, 1)
		b.authCodeReady = make(chan struct{})
	}
	if cfg.Password2F == "" {
		b.authPwdCh = make(chan string, 1)
		b.authPwdReady = make(chan struct{})
	}
	close(b.authSetupDone)
	b.mu.Unlock()

	authDone := make(chan struct{})
	errCh := make(chan error, 1)

	b.wg.Add(1)
	go func() {
		defer b.wg.Done()
		errCh <- b.authUser(cfg)
		close(authDone)
	}()

	if cfg.OTP == "" {
		b.mu.Lock()
		b.authDoneCh = authDone
		b.authErrCh = errCh
		b.mu.Unlock()

		select {
		case <-authDone:
			return <-errCh
		case <-b.authCodeReady:
			return fmt.Errorf("otp_required")
		case err := <-errCh:
			return err
		case <-time.After(30 * time.Second):
			return fmt.Errorf("%w: timeout connecting to Bale", ErrAuth)
		}
	}

	return <-errCh
}

func (b *BaleCore) authBot(token string) error {
	if token == "" {
		return fmt.Errorf("%w: bot token is required", ErrInvalidInput)
	}

	b.botToken = token

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

	if err := b.saveSession(); err != nil {
		fmt.Fprintf(os.Stderr, "bale: warning: could not save session: %v\n", err)
	}

	b.startPolling()

	return nil
}

func (b *BaleCore) loadSession() error {
	if b.session == nil {
		return nil
	}
	var sess baleSession
	if err := b.session.Load(&sess); err != nil {
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
	if b.session == nil {
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
	return b.session.Save(sess)
}

func (b *BaleCore) Logout() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if !b.authed {
		return nil
	}

	if b.pollCancel != nil {
		b.pollCancel()
	}

	b.apiRequest("deleteWebhook", nil)

	b.botToken = ""
	b.botInfo = nil
	b.authed = false

	if b.session != nil {
		b.session.Delete()
	}

	return nil
}

func (b *BaleCore) apiRequest(method string, params map[string]interface{}) (map[string]interface{}, error) {
	url := b.baseURL + "/bot" + b.botToken + "/" + method

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

	respBody, err := ReadBodyCapped(resp.Body, ApiBodyCeiling)
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

func (b *BaleCore) apiRequestMultipart(method string, fields map[string]string, fileField string, fileName string, fileReader io.Reader) (map[string]interface{}, error) {
	url := b.baseURL + "/bot" + b.botToken + "/" + method

	var buf bytes.Buffer
	writer := multipart.NewWriter(&buf)

	for k, v := range fields {
		if err := writer.WriteField(k, v); err != nil {
			return nil, fmt.Errorf("write field %s: %w", k, err)
		}
	}

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

	respBody, err := ReadBodyCapped(resp.Body, ApiBodyCeiling)
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

func (b *BaleCore) startPolling() {
	b.pollCtx, b.pollCancel = context.WithCancel(b.ctx)
	b.wg.Add(1)
	go b.pollLoop()
}

func (b *BaleCore) pollLoop() {
	defer b.wg.Done()
	pollClient := newBaleHTTPClient(40 * time.Second)
	pollURL := b.baseURL + "/bot" + b.botToken + "/getUpdates"
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

		url := pollURL

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

		resp, err := pollClient.Do(req)
		if err != nil {
			if b.pollCtx.Err() != nil {
				return
			}
			time.Sleep(2 * time.Second)
			continue
		}

		body, err := ReadBodyCapped(resp.Body, ApiBodyCeiling)
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
	if len(b.updateHandlers) == 0 {
		b.updateMu.RUnlock()
		return
	}
	handlers := make([]func(Update), len(b.updateHandlers))
	copy(handlers, b.updateHandlers)
	b.updateMu.RUnlock()

	var update Update
	update.Platform = balePlatform

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
		parsed := b.mapCallbackQuery(cb)
		update.Message = &parsed
		update.ChatID = parsed.ChatID
	} else {
		return
	}

	for _, h := range handlers {
		h(update)
	}
}

func (b *BaleCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bots do not have a dialog list", ErrNotSupported)
	}
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
	userNames := map[int64]string{}
	groupNames := map[int64]string{}

	var userIDs []int64
	for _, item := range pbGetList(resp, "4") {
		u, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		uid := pbGetInt64(u, "1")
		if uid != 0 {
			userIDs = append(userIDs, uid)
		}
	}
	var groupIDs []int64
	groupAccessHash := map[int64]int64{}
	for _, item := range pbGetList(resp, "5") {
		g, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		gid := pbGetInt64(g, "1")
		if gid != 0 {
			groupIDs = append(groupIDs, gid)
			ah := pbGetInt64(g, "2")
			if ah != 0 {
				groupAccessHash[gid] = ah
			}
		}
	}

	if len(userIDs) > 0 {
		if uresp, uerr := b.UserLoadUsers(userIDs); uerr == nil {
			for _, fu := range pbGetList(uresp, "1") {
				fm, ok := fu.(map[string]interface{})
				if !ok {
					continue
				}
				uid := pbGetInt64(fm, "1")
				name := baleExtractName(fm)
				if name != "" {
					userNames[uid] = name
				}
			}
		}
		if len(userNames) < len(userIDs) {
			var missing []int64
			for _, uid := range userIDs {
				if _, ok := userNames[uid]; !ok {
					missing = append(missing, uid)
				}
			}
			if len(missing) > 0 {
				if uresp, uerr := b.UserLoadFullUsers(missing); uerr == nil {
					for _, fu := range pbGetList(uresp, "1") {
						fm, ok := fu.(map[string]interface{})
						if !ok {
							continue
						}
						uid := pbGetInt64(fm, "1")
						name := baleExtractName(fm)
						if name != "" {
							userNames[uid] = name
						}
					}
				}
			}
		}
	}

	if len(groupIDs) > 0 {
		groupPeers := make([]map[string]interface{}, 0, len(groupIDs))
		for _, gid := range groupIDs {
			ah := groupAccessHash[gid]
			if ah == 0 {
				ah = 1
			}
			groupPeers = append(groupPeers, map[string]interface{}{"1": gid, "2": ah})
		}
		if gresp, gerr := b.userSend(baleServiceGroups, "LoadGroups", map[string]interface{}{"1": groupPeers}); gerr == nil {
			for _, fg := range pbGetList(gresp, "1") {
				fm, ok := fg.(map[string]interface{})
				if !ok {
					continue
				}
				gid := pbGetInt64(fm, "1")
				title := baleExtractName(fm)
				if title != "" {
					groupNames[gid] = title
				}
			}
		}
		for _, gid := range groupIDs {
			if _, ok := groupNames[gid]; ok {
				continue
			}
			if gresp, gerr := b.UserGetFullGroup(gid); gerr == nil {
				gdata := pbGetMsg(gresp, "1")
				if gdata != nil {
					title := baleExtractName(gdata)
					if title != "" {
						groupNames[gid] = title
					}
				}
			}
		}
	}

	dialogs := []Dialog{}
	for _, item := range pbGetList(resp, "3") {
		pd, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		d := Dialog{Platform: balePlatform}
		var peerID, peerType int64
		if peer := pbGetMsg(pd, "1"); peer != nil {
			peerID = pbGetInt64(peer, "2")
			peerType = pbGetInt64(peer, "1")
			d.ID = int64Pair(peerID, peerType, '|')
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
		if d.Type == ChatTypeDM {
			d.Title = userNames[peerID]
		} else {
			d.Title = groupNames[peerID]
		}
		d.UnreadCount = int(pbGetInt64(pd, "2"))
		if content := pbGetMsg(pd, "7"); content != nil {
			lastMsg := &Message{Platform: balePlatform}
			b.mapUserMessageContent(pd, "7", lastMsg)
			if lastMsg.Text != "" {
				lastMsg.Text = truncateText(lastMsg.Text, 100)
			}
			lastMsg.SenderID = strconv.FormatInt(pbGetInt64(pd, "4"), 10)
			lastMsg.IsOutgoing = pbGetInt64(pd, "4") == b.userID
			dateMs := pbGetInt64(pd, "6")
			if dateMs > 1e12 {
				lastMsg.Timestamp = time.UnixMilli(dateMs)
			}
			d.LastMessage = lastMsg
		}
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
		Platform: balePlatform,
	}, nil
}

func (b *BaleCore) CreateChannel(name string, description string) (*Dialog, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bots cannot create channels", ErrNotSupported)
	}
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
	resp, err := b.UserCreateFolder(name, chatIDs)
	if err != nil {
		return nil, err
	}
	folderID := pbGetInt64(resp, "1")
	return &Folder{
		ID:   fmt.Sprintf("%d", folderID),
		Name: name,
	}, nil
}

func (b *BaleCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	b.mu.RUnlock()

	if !b.isBot {
		var replyRID, replyDate int64
		if msg.ReplyToID != "" {
			replyRID, _ = strconv.ParseInt(msg.ReplyToID, 10, 64)
			if parts := strings.SplitN(msg.ReplyToID, ":", 2); len(parts) == 2 {
				replyRID, _ = strconv.ParseInt(parts[0], 10, 64)
				replyDate, _ = strconv.ParseInt(parts[1], 10, 64)
			}
		}
		resp, err := b.UserSendMessage(chatID, msg.Text, replyRID, replyDate)
		if err != nil {
			return nil, err
		}
		mid := pbGetInt64(resp, "1")
		dateMs := pbGetInt64(resp, "2")
		ourRID, _ := resp["__rid"].(int64)
		msgID := int64Triple(ourRID, dateMs, mid, ':')
		return &Message{
			ID:         msgID,
			ChatID:     chatID,
			Text:       msg.Text,
			Timestamp:  time.Now(),
			Status:     MessageStatusSent,
			SenderID:   strconv.FormatInt(b.userID, 10),
			SenderName: b.userPhone,
			Platform:   balePlatform,
			IsOutgoing: true,
		}, nil
	}

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
		return nil, fmt.Errorf("%w: unexpected sendMessage response", ErrNetwork)
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

func (b *BaleCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bale bot API does not support fetching message history", ErrNotSupported)
	}
	date := time.Now().UnixMilli()
	if opts.Offset != "" {
		date, _ = strconv.ParseInt(opts.Offset, 10, 64)
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	resp, err := b.UserLoadHistory(chatID, date, limit, 2)
	if err != nil {
		return nil, err
	}
	messages := []Message{}
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
		return &Message{ID: msgID, ChatID: chatID, Text: text, Platform: balePlatform, IsOutgoing: true}, nil
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
		return &Message{ID: msgID, ChatID: chatID, Text: text, Platform: balePlatform, IsOutgoing: true}, nil
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
		return &Message{ChatID: toChatID, Platform: balePlatform, Status: MessageStatusSent, IsOutgoing: true}, nil
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
		return nil, fmt.Errorf("%w: unexpected forwardMessage response", ErrNetwork)
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

func (b *BaleCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	if b.isBot {
		return fmt.Errorf("%w: bale bot API does not support reactions", ErrNotSupported)
	}
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

	method, fieldName := b.detectSendMethod(file.MimeType, file.Name)

	fields := map[string]string{
		"chat_id": chatID,
	}

	var reader io.Reader = file.Reader
	if progress != nil {
		reader = &progressReader{
			reader:     file.Reader,
			total:      file.Size,
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

var BaleDrainMax int64 = 64 * 1024

func DrainBodyLimited(rc io.ReadCloser) {
	_, _ = io.Copy(io.Discard, io.LimitReader(rc, BaleDrainMax))
}

func (b *BaleCore) userUploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	uploadInfo, err := b.UserGetFileUploadURL(file.Size, file.Name, file.MimeType)
	if err != nil {
		return nil, fmt.Errorf("GetNasimFileUploadUrl: %w", err)
	}
	fileID := pbGetInt64(uploadInfo, "1")
	uploadURL := pbGetString(uploadInfo, "2")
	if uploadURL == "" {
		if raw, ok := uploadInfo["__raw_2"]; ok {
			if bs, ok := raw.([]byte); ok {
				uploadURL = string(bs)
			}
		}
	}
	if uploadURL == "" || fileID == 0 {
		return nil, fmt.Errorf("invalid upload info: fileID=%d url=%q", fileID, uploadURL)
	}

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
	DrainBodyLimited(uploadResp.Body)

	if uploadResp.StatusCode >= 400 {
		return nil, fmt.Errorf("upload failed: HTTP %d", uploadResp.StatusCode)
	}

	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	docMsg := map[string]interface{}{
		"1": fileID,
		"2": b.userID,
		"3": file.Size,
		"4": file.Name,
		"5": file.MimeType,
	}
	content := map[string]interface{}{
		"4": docMsg,
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
	msgID := int64Triple(rid, dateMs, mid, ':')

	return &Message{
		ID:         msgID,
		ChatID:     chatID,
		Platform:   balePlatform,
		Status:     MessageStatusSent,
		IsOutgoing: true,
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

	fileURL := b.baseURL + "/file/bot" + b.botToken + "/" + filePath

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

	if _, err := BoundedCopy(outFile, reader, DownloadCeiling); err != nil {
		outFile.Close()
		os.Remove(dest)
		return err
	}
	return nil
}

func (b *BaleCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	return nil, fmt.Errorf("%w: use UploadFile instead", ErrNotSupported)
}

const baleServiceMeet = "bale.meet.v1.Meet"

func baleExtractCallData(resp map[string]interface{}) (callID int64, room, token, wsURL string) {
	callID = pbGetInt64(resp, "1")
	room = pbGetString(resp, "2")
	token = pbGetString(resp, "3")
	if urlMsg := pbGetMsg(resp, "4"); urlMsg != nil {
		wsURL = pbGetString(urlMsg, "1")
	}

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

func (b *BaleCore) StartCall(chatID string, video bool) (*CallSession, error) {
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
		"1": map[string]interface{}{"1": int64(1), "2": peerID},
		"2": rid,
	})
	if err != nil {
		return nil, fmt.Errorf("StartCall: %w", err)
	}

	callID, room, token, wsURL := baleExtractCallData(resp)
	if callID == 0 {
		return nil, fmt.Errorf("%w: StartCall: no call_id in response", ErrNetwork)
	}

	if wsURL == "" && callID != 0 {
		if u, err := b.GetWssURL(fmt.Sprintf("%d", callID)); err == nil && u != "" {
			wsURL = u
		}
	}

	fmt.Fprintf(os.Stderr, "bale: 1:1 call started: callID=%d room=%s ws=%s\n", callID, room, wsURL)

	session := baleCallSession(callID, chatID, false, room, token, wsURL)
	session.IsVideo = video

	if err := b.baleConnectLiveKit(session); err != nil {
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

	internalID := peerID
	if peerType == balePeerGroup || peerType == balePeerSupergroup {
		if resolved, err := b.resolveGroupInternalID(peerID); err == nil {
			internalID = resolved
		}
	}

	var session *CallSession

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
	}

	if session == nil {
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

	if session.Meta["livekit_url"] == "" {
		if u, err := b.GetWssURL(session.ID); err == nil && u != "" {
			session.Meta["livekit_url"] = u
		}
	}

	if err := b.baleConnectLiveKit(session); err != nil {
		fmt.Fprintf(os.Stderr, "bale: LiveKit connect failed: %v (call signaling was OK)\n", err)
		cid, _ := strconv.ParseInt(session.ID, 10, 64)
		_ = b.baleEndCallSignaling(cid)
		return nil, fmt.Errorf("JoinGroupCall: LiveKit connect: %w", err)
	}

	return session, nil
}

func (b *BaleCore) baleFindOngoingCallID() int64 {
	resp, err := b.userSend(baleServiceMeet, "GetOngoingCalls", map[string]interface{}{})
	if err != nil {
		return 0
	}
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

func (b *BaleCore) GetOngoingCalls() (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "GetOngoingCalls", map[string]interface{}{})
}

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
		if inner := pbGetMsg(resp, "1"); inner != nil {
			url = pbGetString(inner, "1")
		}
	}
	return url, nil
}

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

func (b *BaleCore) GetCallLogs(page, count int) (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "GetCallLogs", map[string]interface{}{
		"1": int64(page),
		"2": int64(count),
	})
}

func (b *BaleCore) EndCall(callID string) error {
	b.baleDisconnectLiveKit()

	cid, _ := strconv.ParseInt(callID, 10, 64)
	if cid == 0 {
		return fmt.Errorf("%w: invalid call ID", ErrInvalidInput)
	}
	return b.baleEndCallSignaling(cid)
}

func (b *BaleCore) baleEndCallSignaling(callID int64) error {
	_, err := b.userSend(baleServiceMeet, "LeaveGroupCall", map[string]interface{}{
		"1": callID,
		"2": int64(0),
	})
	if err == nil {
		return nil
	}
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

	if call == nil {
		return fmt.Errorf("%w: no active call", ErrNotSupported)
	}
	if call.session.ID != callID {
		return fmt.Errorf("%w: call ID mismatch (active=%s, requested=%s)", ErrInvalidInput, call.session.ID, callID)
	}

	call.audioPubSetMuted(muted)
	call.muted = muted
	fmt.Fprintf(os.Stderr, "bale: call muted=%v\n", muted)
	return nil
}

func (b *BaleCore) ToggleCamera(_ string, _ bool) error {
	return fmt.Errorf("%w: bale does not support camera toggle", ErrNotSupported)
}

func (b *BaleCore) GetProfile(userID string) (*User, error) {
	b.mu.RLock()
	if !b.authed {
		b.mu.RUnlock()
		return nil, ErrAuth
	}
	isBot := b.isBot
	myUserID := b.userID
	b.mu.RUnlock()

	if userID == "" {
		if isBot && b.botInfo != nil {
			return b.botInfo, nil
		}
		userID = fmt.Sprintf("%d", myUserID)
	}

	if !isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		if uid == 0 {
			return nil, fmt.Errorf("%w: invalid user ID", ErrInvalidInput)
		}
		resp, err := b.UserLoadFullUsers([]int64{uid})
		if err != nil {
			return nil, err
		}
		users := pbGetList(resp, "1")
		if len(users) == 0 {
			return nil, fmt.Errorf("%w: user not found", ErrNotFound)
		}
		fu, _ := users[0].(map[string]interface{})
		if fu == nil {
			return nil, fmt.Errorf("%w: user not found", ErrNotFound)
		}
		name := baleExtractName(fu)
		nick := pbGetString(fu, "5")
		about := pbGetString(fu, "9")
		_ = about
		return &User{
			ID:          userID,
			DisplayName: name,
			Username:    nick,
			Platform:    balePlatform,
		}, nil
	}

	params := map[string]interface{}{
		"chat_id": userID,
	}

	resp, err := b.apiRequest("getChat", params)
	if err != nil {
		return nil, err
	}

	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("%w: unexpected getChat response", ErrNetwork)
	}

	return b.mapChatToUser(result), nil
}

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

func (b *BaleCore) GetChat(chatID string) (BaleChatInfo, error) {
	resp, err := b.apiRequest("getChat", map[string]interface{}{"chat_id": chatID})
	if err != nil {
		return BaleChatInfo{}, err
	}
	return baleParseResult[BaleChatInfo](resp)
}

func (b *BaleCore) GetChatAdministrators(chatID string) ([]BaleChatMember, error) {
	resp, err := b.apiRequest("getChatAdministrators", map[string]interface{}{"chat_id": chatID})
	if err != nil {
		return nil, err
	}
	results, _ := resp["result"].([]interface{})
	admins := make([]BaleChatMember, 0, len(results))
	for _, r := range results {
		b2, _ := json.Marshal(r)
		var m BaleChatMember
		if json.Unmarshal(b2, &m) == nil {
			admins = append(admins, m)
		}
	}
	return admins, nil
}

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

func (b *BaleCore) GetChatMember(chatID string, userID int64) (BaleChatMember, error) {
	resp, err := b.apiRequest("getChatMember", map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	})
	if err != nil {
		return BaleChatMember{}, err
	}
	return baleParseResult[BaleChatMember](resp)
}

func (b *BaleCore) banChatMember(chatID string, userID int64) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	}
	_, err := b.apiRequest("banChatMember", params)
	return err
}

func (b *BaleCore) unbanChatMember(chatID string, userID int64, onlyIfBanned bool) error {
	params := map[string]interface{}{
		"chat_id":        chatID,
		"user_id":        userID,
		"only_if_banned": onlyIfBanned,
	}
	_, err := b.apiRequest("unbanChatMember", params)
	return err
}

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

func (b *BaleCore) setChatTitle(chatID string, title string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"title":   title,
	}
	_, err := b.apiRequest("setChatTitle", params)
	return err
}

func (b *BaleCore) setChatDescription(chatID string, description string) error {
	params := map[string]interface{}{
		"chat_id":     chatID,
		"description": description,
	}
	_, err := b.apiRequest("setChatDescription", params)
	return err
}

func (b *BaleCore) SetChatPhoto(chatID string, photo io.Reader, fileName string) error {
	fields := map[string]string{
		"chat_id": chatID,
	}
	_, err := b.apiRequestMultipart("setChatPhoto", fields, "photo", fileName, photo)
	return err
}

func (b *BaleCore) DeleteChatPhoto(chatID string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	_, err := b.apiRequest("deleteChatPhoto", params)
	return err
}

func (b *BaleCore) LeaveChat(chatID string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	_, err := b.apiRequest("leaveChat", params)
	return err
}

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

func (b *BaleCore) unpinAllChatMessages(chatID string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
	}
	_, err := b.apiRequest("unpinAllChatMessages", params)
	return err
}

func (b *BaleCore) SendChatAction(chatID string, action string) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"action":  action,
	}
	_, err := b.apiRequest("sendChatAction", params)
	return err
}

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

func (b *BaleCore) EditMessageCaption(chatID string, msgID int64, caption string) error {
	params := map[string]interface{}{
		"chat_id":    chatID,
		"message_id": msgID,
		"caption":    caption,
	}
	_, err := b.apiRequest("editMessageCaption", params)
	return err
}

func (b *BaleCore) SendMessageWithKeyboard(chatID string, text string, keyboard [][]map[string]string) (*Message, error) {
	rows := make([][]map[string]interface{}, len(keyboard))
	for i, row := range keyboard {
		btnRow := make([]map[string]interface{}, len(row))
		for j, btn := range row {
			button := make(map[string]interface{}, len(btn))
			for k, v := range btn {
				button[k] = v
			}
			btnRow[j] = button
		}
		rows[i] = btnRow
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
		return nil, fmt.Errorf("%w: unexpected sendMessage response", ErrNetwork)
	}

	parsed := b.mapMessage(result)
	return &parsed, nil
}

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

func (b *BaleCore) GetStickerSet(name string) (BaleStickerSet, error) {
	resp, err := b.apiRequest("getStickerSet", map[string]interface{}{"name": name})
	if err != nil {
		return BaleStickerSet{}, err
	}
	return baleParseResult[BaleStickerSet](resp)
}

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

func (b *BaleCore) mapMessage(m map[string]interface{}) Message {
	msg := Message{
		Platform: balePlatform,
	}

	msg.ID = strconv.FormatInt(jsonInt64(m, "message_id"), 10)

	if chat, ok := m["chat"].(map[string]interface{}); ok {
		msg.ChatID = strconv.FormatInt(jsonInt64(chat, "id"), 10)
	}

	if from, ok := m["from"].(map[string]interface{}); ok {
		senderUID := jsonInt64(from, "id")
		msg.SenderID = strconv.FormatInt(senderUID, 10)
		msg.SenderName = b.buildDisplayName(from)
		msg.IsOutgoing = senderUID == b.userID
	}

	if text, ok := m["text"].(string); ok {
		msg.Text = text
	} else if caption, ok := m["caption"].(string); ok {
		msg.Text = caption
	}

	if date, ok := m["date"].(float64); ok {
		msg.Timestamp = time.Unix(int64(date), 0)
	}

	if editDate, ok := m["edit_date"].(float64); ok {
		t := time.Unix(int64(editDate), 0)
		msg.EditedAt = &t
	}

	if reply, ok := m["reply_to_message"].(map[string]interface{}); ok {
		msg.ReplyToID = strconv.FormatInt(jsonInt64(reply, "message_id"), 10)
		if txt, ok := reply["text"].(string); ok {
			msg.ReplyPreview = truncateText(txt, 100)
		}
	}

	if fwdFrom, ok := m["forward_from"].(map[string]interface{}); ok {
		msg.ForwardFrom = b.buildDisplayName(fwdFrom)
	} else if fwdChat, ok := m["forward_from_chat"].(map[string]interface{}); ok {
		if title, ok := fwdChat["title"].(string); ok {
			msg.ForwardFrom = title
		}
	}

	msg.Attachments = b.ExtractAttachments(m)

	msg.Status = MessageStatusSent
	return msg
}

func (b *BaleCore) mapCallbackQuery(cb map[string]interface{}) Message {
	msg := Message{
		Platform: balePlatform,
		Status:   MessageStatusSent,
	}

	if cbMsg, ok := cb["message"].(map[string]interface{}); ok {
		msg = b.mapMessage(cbMsg)
	}

	if data, ok := cb["data"].(string); ok {
		msg.Text = data
	}

	if from, ok := cb["from"].(map[string]interface{}); ok {
		senderUID := jsonInt64(from, "id")
		msg.SenderID = strconv.FormatInt(senderUID, 10)
		msg.SenderName = b.buildDisplayName(from)
		msg.IsOutgoing = senderUID == b.userID
	}

	return msg
}

func (b *BaleCore) mapUser(u map[string]interface{}) *User {
	user := &User{
		Platform: balePlatform,
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
		Platform: balePlatform,
	}

	user.ID = strconv.FormatInt(jsonInt64(chat, "id"), 10)
	user.DisplayName = b.buildDisplayName(chat)
	if username, ok := chat["username"].(string); ok {
		user.Username = username
	}
	if bio, ok := chat["bio"].(string); ok {
		_ = bio
	}

	return user
}

func (b *BaleCore) ExtractAttachments(m map[string]interface{}) []FileRef {
	var attachments []FileRef

	if photos, ok := m["photo"].([]interface{}); ok && len(photos) > 0 {
		largest, isMap := photos[len(photos)-1].(map[string]interface{})
		if isMap {
			attachments = append(attachments, FileRef{
				ID:       jsonString(largest, "file_id"),
				Name:     "photo.jpg",
				MimeType: "image/jpeg",
				Size:     jsonInt64(largest, "file_size"),
				Width:    int(jsonInt64(largest, "width")),
				Height:   int(jsonInt64(largest, "height")),
			})
		}
	}

	if doc, ok := m["document"].(map[string]interface{}); ok {
		attachments = append(attachments, FileRef{
			ID:       jsonString(doc, "file_id"),
			Name:     jsonString(doc, "file_name"),
			MimeType: jsonString(doc, "mime_type"),
			Size:     jsonInt64(doc, "file_size"),
		})
	}

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
			Duration: int(jsonInt64(audio, "duration")),
		})
	}

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
			Width:    int(jsonInt64(video, "width")),
			Height:   int(jsonInt64(video, "height")),
			Duration: int(jsonInt64(video, "duration")),
		})
	}

	if voice, ok := m["voice"].(map[string]interface{}); ok {
		attachments = append(attachments, FileRef{
			ID:       jsonString(voice, "file_id"),
			Name:     "voice.ogg",
			MimeType: "audio/ogg",
			Size:     jsonInt64(voice, "file_size"),
			Duration: int(jsonInt64(voice, "duration")),
		})
	}

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
			Width:    int(jsonInt64(anim, "width")),
			Height:   int(jsonInt64(anim, "height")),
			Duration: int(jsonInt64(anim, "duration")),
		})
	}

	if sticker, ok := m["sticker"].(map[string]interface{}); ok {
		attachments = append(attachments, FileRef{
			ID:       jsonString(sticker, "file_id"),
			Name:     "sticker.webp",
			MimeType: "image/webp",
			Size:     jsonInt64(sticker, "file_size"),
			Width:    int(jsonInt64(sticker, "width")),
			Height:   int(jsonInt64(sticker, "height")),
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

func jsonString(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	s, _ := m[key].(string)
	return s
}

func truncateText(text string, maxLen int) string {
	if len(text) <= maxLen {
		return text
	}
	runes := []rune(text)
	if len(runes) <= maxLen {
		return text
	}
	return string(runes[:maxLen]) + "..."
}

func int64Pair(a, b int64, sep byte) string {
	sa := strconv.FormatInt(a, 10)
	sb := strconv.FormatInt(b, 10)
	buf := make([]byte, len(sa)+1+len(sb))
	copy(buf, sa)
	buf[len(sa)] = sep
	copy(buf[len(sa)+1:], sb)
	return string(buf)
}

func int64Triple(a, b, c int64, sep byte) string {
	sa := strconv.FormatInt(a, 10)
	sb := strconv.FormatInt(b, 10)
	sc := strconv.FormatInt(c, 10)
	buf := make([]byte, len(sa)+1+len(sb)+1+len(sc))
	copy(buf, sa)
	buf[len(sa)] = sep
	copy(buf[len(sa)+1:], sb)
	buf[len(sa)+1+len(sb)] = sep
	copy(buf[len(sa)+1+len(sb)+1:], sc)
	return string(buf)
}

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

type pbFixed64 uint64

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
		tag := pbEncodeTag(fieldNum, 1)
		var buf [8]byte
		binary.LittleEndian.PutUint64(buf[:], uint64(v))
		return append(tag, buf[:]...)
	case pbUint32:
		tag := pbEncodeTag(fieldNum, 5)
		var buf [4]byte
		binary.LittleEndian.PutUint32(buf[:], uint32(v))
		return append(tag, buf[:]...)
	case string:
		tag := pbEncodeTag(fieldNum, 2)
		tag = append(tag, pbEncodeVarint(uint64(len(v)))...)
		return append(tag, v...)
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
	if len(fields) == 0 {
		return nil
	}
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
		case 0:
			val, n := pbDecodeVarint(data[pos:], 0)
			pos += n
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
		case 1:
			if pos+8 > len(data) {
				return result
			}
			val := binary.LittleEndian.Uint64(data[pos : pos+8])
			pos += 8
			result[key] = int64(val)
		case 2:
			length, n := pbDecodeVarint(data[pos:], 0)
			if n == 0 || length > uint64(len(data)-pos-n) || length > 10*1024*1024 {
				return result
			}
			pos += n
			end := pos + int(length)
			if end > len(data) {
				return result
			}
			payload := data[pos:end]
			pos = end
			nested := pbTryDecodeMessageDepth(payload, depth+1)
			var value interface{}
			if nested != nil {
				value = nested
				result["__raw_"+key] = payload
			} else {
				value = string(payload)
			}
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
		case 5:
			if pos+4 > len(data) {
				return result
			}
			val := binary.LittleEndian.Uint32(data[pos : pos+4])
			pos += 4
			result[key] = int64(val)
		default:
			return result
		}
	}
	return result
}

func pbTryDecodeMessageDepth(data []byte, depth int) map[string]interface{} {
	if len(data) == 0 || depth > 8 {
		return nil
	}
	tag, n := pbDecodeVarint(data, 0)
	wireType := tag & 0x7
	fieldNum := tag >> 3
	if n == 0 || fieldNum == 0 || fieldNum > 10000 || wireType > 5 || wireType == 3 || wireType == 4 {
		return nil
	}
	result := pbDecodeDepth(data, depth)
	if len(result) == 0 {
		return nil
	}
	return result
}

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

func pbGetMsg(m map[string]interface{}, field string) map[string]interface{} {
	if m == nil {
		return nil
	}
	if sub, ok := m[field].(map[string]interface{}); ok {
		return sub
	}
	return nil
}

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

func grpcWebEncode(payload []byte) []byte {
	var header [5]byte
	binary.BigEndian.PutUint32(header[1:], uint32(len(payload)))
	out := make([]byte, 0, 5+len(payload))
	out = append(out, header[:]...)
	return append(out, payload...)
}

func grpcWebDecode(data []byte) []byte {
	if len(data) < 5 {
		return data
	}
	payload := data[5:]
	if idx := bytes.Index(payload, []byte("grpc-status")); idx != -1 {
		payload = payload[:idx]
	}
	return payload
}

const (
	baleServiceAuth      = "bale.auth.v1.Auth"
	baleServiceMessaging = "bale.messaging.v2.Messaging"
	baleServiceUsers     = "bale.users.v1.Users"
	baleServiceGroups    = "bale.groups.v1.Groups"
	baleServiceFiles     = "ai.bale.server.Files"
	baleServicePresence  = "bale.presence.v1.Presence"
	baleServiceConfigs   = "bale.v1.Configs"
	baleServiceAbacus    = "bale.abacus.v1.Abacus"

	baleServicePoll        = "bale.poll.v1.Poll"
	baleServiceSearch      = "bale.search.v1.Search"
	baleServiceStory       = "bale.story.v1.Story"
	baleServiceMsgStream   = "bale.message_stream.v1.MessageStream"
	baleServiceScheduler   = "bale.schedule.v1.Scheduler"
	baleServiceTLDR        = "bale.tldr.v1.TLDR"
	baleServiceAnonContact = "bale.anonymous_contact.v1.AnonymousContact"
	baleServiceMaviz       = "bale.maviz.v1.MavizStream"
	baleServiceFalake      = "bale.falake.v1.Falake"
	baleServiceNegah       = "bale.negah.v1.Negah"
	baleServiceLLMAuth     = "bale.llm_auth.v1.LLMAuthService"
	baleServiceAppzar      = "bale.appzar.v1.Appzar"
	baleServiceTopPeer     = "bale.top_peer.v1.TopPeer"
	baleServiceOrgs        = "bale.organizations.v1.Organizations"
	baleServiceRecommender = "bale.recommender.v1.Recommender"
	baleServiceSharedMedia = "bale.shared_media.v1.SharedMediaService"
	baleServiceKetf        = "bale.ketf.v1.Ketf"
	baleServiceTuringAI    = "bale.turing.v1.AI"

	baleWSURL   = "wss://next-ws.bale.ai/ws/"
	balePostURL = "https://next-ws.bale.ai"

	baleAppVersion  = "113466"
	baleBrowserType = "1"
	baleBrowserVer  = 3471765337684194354
	baleOSType      = "3"
	baleUserAgent   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
)

const (
	balePeerPrivate    = 1
	balePeerGroup      = 2
	balePeerChannel    = 3
	balePeerBot        = 4
	balePeerSupergroup = 5
)

func (b *BaleCore) wsConnect() error {
	if b.userToken == "" {
		return fmt.Errorf("%w: no user token", ErrAuth)
	}

	ctx, cancel := context.WithCancel(b.ctx)
	b.wsCtx = ctx
	b.wsCancel = cancel
	b.wsSessionID = strconv.FormatInt(time.Now().UnixMilli(), 10)
	b.wsMeta = nil
	b.wsPending = make(map[int64]chan map[string]interface{})
	b.wsIndex = 0
	b.wsReady = make(chan struct{})

	conn, err := baleWSDial(ctx, baleWSURL, b.userToken)
	if err != nil {
		cancel()
		return fmt.Errorf("%w: websocket dial: %v", ErrNetwork, err)
	}
	conn.SetReadLimit(4 * 1024 * 1024)
	b.wsConn = conn

	b.wg.Add(2)
	go b.wsRecvLoop()
	go b.wsPingLoop()

	handshake := pbEncode(map[string]interface{}{
		"3": map[string]interface{}{
			"1": int64(1),
			"2": int64(1),
		},
	})
	b.wsConn.Write(ctx, websocket.MessageBinary, handshake)

	select {
	case <-b.wsReady:
	case <-time.After(10 * time.Second):
		return fmt.Errorf("%w: websocket handshake timeout", ErrNetwork)
	}

	go func() {
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
				return
			}
			b.fireConnState("disconnected")
			retryErr := utils.Retry(b.ctx, 10, 3*time.Second, 60*time.Second, nil, func() error {
				b.fireConnState("reconnecting")
				return b.wsConnect()
			})
			if retryErr == nil {
				b.fireConnState("connected")
				return
			}
			b.fireConnState("disconnected")
			return
		}
		go b.wsHandleMessage(data)
	}
}

func (b *BaleCore) fireConnState(state string) {
	b.updateMu.RLock()
	if len(b.updateHandlers) == 0 {
		b.updateMu.RUnlock()
		return
	}
	handlers := make([]func(Update), len(b.updateHandlers))
	copy(handlers, b.updateHandlers)
	b.updateMu.RUnlock()
	u := Update{Type: UpdateConnectivity, ConnState: state, Platform: balePlatform}
	for _, h := range handlers {
		go h(u)
	}
}

func (b *BaleCore) wsHandleMessage(data []byte) {
	decoded := pbDecode(data)

	if hsResp := decoded["5"]; hsResp != nil {
		select {
		case <-b.wsReady:
		default:
			close(b.wsReady)
		}
		return
	}

	if wsResp := pbGetMsg(decoded, "1"); wsResp != nil {
		idx := pbGetInt64(wsResp, "3")
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

	if decoded["4"] != nil {
		return
	}

	if decoded["3"] != nil {
		return
	}

	if wsUpdate := pbGetMsg(decoded, "2"); wsUpdate != nil {
		b.wsHandleUpdate(wsUpdate)
		return
	}
}

func (b *BaleCore) wsHandleUpdate(wsUpdate map[string]interface{}) {
	update := pbGetMsg(wsUpdate, "1")
	if update == nil {
		return
	}
	composed := pbGetMsg(update, "1")
	if composed == nil {
		return
	}

	b.updateMu.RLock()
	if len(b.updateHandlers) == 0 {
		b.updateMu.RUnlock()
		return
	}
	handlers := make([]func(Update), len(b.updateHandlers))
	copy(handlers, b.updateHandlers)
	b.updateMu.RUnlock()

	dispatch := func(u Update) {
		for _, h := range handlers {
			go h(u)
		}
	}

	if msgUpdate := pbGetMsg(composed, "55"); msgUpdate != nil {
		msg := b.mapUserMessage(msgUpdate)
		dispatch(Update{Type: UpdateNewMessage, ChatID: msg.ChatID, Message: &msg, Platform: balePlatform})
	}

	if editUpdate := pbGetMsg(composed, "162"); editUpdate != nil {
		msg := b.mapUpdatedMessage(editUpdate)
		dispatch(Update{Type: UpdateEditMessage, ChatID: msg.ChatID, Message: &msg, Platform: balePlatform})
	}

	if delUpdate := pbGetMsg(composed, "46"); delUpdate != nil {
		chatID := ""
		if peer := pbGetMsg(delUpdate, "1"); peer != nil {
			peerID := pbGetInt64(peer, "2")
			peerType := pbGetInt64(peer, "1")
			chatID = int64Pair(peerID, peerType, '|')
		}
		dispatch(Update{Type: UpdateDeleteMessage, ChatID: chatID, Platform: balePlatform})
	}

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
			ping := pbEncode(map[string]interface{}{
				"2": map[string]interface{}{
					"1": b.wsPingID,
				},
			})
			b.wsConn.Write(b.wsCtx, websocket.MessageBinary, ping)
		}
	}
}

func (b *BaleCore) wsSend(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	b.wsPendMu.Lock()
	idx := b.wsIndex
	b.wsIndex++
	ch := make(chan map[string]interface{}, 1)
	b.wsPending[idx] = ch
	b.wsPendMu.Unlock()

	var payloadBytes []byte
	if payload != nil {
		payloadBytes = pbEncode(payload)
	}

	meta := b.buildMetadata()

	wsReq := map[string]interface{}{
		"1": service,
		"2": method,
		"3": payloadBytes,
		"4": meta,
		"5": idx,
	}

	request := pbEncode(map[string]interface{}{
		"1": wsReq,
	})

	if err := b.wsConn.Write(b.wsCtx, websocket.MessageBinary, request); err != nil {
		b.wsPendMu.Lock()
		delete(b.wsPending, idx)
		b.wsPendMu.Unlock()
		return nil, fmt.Errorf("%w: ws write: %v", ErrNetwork, err)
	}

	select {
	case resp := <-ch:
		if errMsg := pbGetMsg(resp, "1"); errMsg != nil {
			code := pbGetInt64(errMsg, "1")
			msg := pbGetString(errMsg, "2")
			if msg == "" {
				msg = fmt.Sprintf("code %d", code)
			}
			return nil, fmt.Errorf("bale RPC error: %s (code=%d)", msg, code)
		}
		if errStr := pbGetString(resp, "1"); errStr != "" {
			return nil, fmt.Errorf("bale RPC error: %s", errStr)
		}
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

func (b *BaleCore) wsPost(service, method string, payload map[string]interface{}, token string) (map[string]interface{}, error) {
	url := balePostURL + "/" + service + "/" + method

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

	respBody, err := ReadBodyCapped(resp.Body, ApiBodyCeiling)
	if err != nil {
		return nil, fmt.Errorf("%w: read response: %v", ErrNetwork, err)
	}

	if grpcMsg := resp.Header.Get("grpc-message"); grpcMsg != "" {
		return nil, fmt.Errorf("bale gRPC error: %s", grpcMsg)
	}

	if idx := bytes.Index(respBody, []byte("grpc-status:")); idx != -1 {
		trailer := string(respBody[idx:])
		for _, line := range strings.Split(trailer, "\r\n") {
			if strings.HasPrefix(line, "grpc-status:") {
				status := strings.TrimSpace(strings.TrimPrefix(line, "grpc-status:"))
				if status != "0" && status != "" {
					msg := "unknown gRPC error"
					for _, l2 := range strings.Split(trailer, "\r\n") {
						if strings.HasPrefix(l2, "grpc-message:") {
							msg = strings.TrimSpace(strings.TrimPrefix(l2, "grpc-message:"))
							break
						}
					}
					return nil, fmt.Errorf("bale gRPC error (status %s): %s", status, msg)
				}
			}
		}
	}

	decoded := grpcWebDecode(respBody)
	if len(decoded) == 0 {
		return map[string]interface{}{}, nil
	}
	return pbDecode(decoded), nil
}

func (b *BaleCore) buildMetadata() map[string]interface{} {
	if b.wsMeta != nil {
		return b.wsMeta
	}
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
	b.wsMeta = map[string]interface{}{"1": kvs}
	return b.wsMeta
}

func (b *BaleCore) authUser(cfg AuthConfig) error {
	if err := b.loadSession(); err == nil && b.userToken != "" {
		if err := b.wsConnect(); err == nil {
			b.isBot = false
			b.authed = true
			return nil
		}
		b.userToken = ""
	}

	phone := cfg.Phone
	if phone == "" {
		return fmt.Errorf("%w: phone number is required for user auth", ErrInvalidInput)
	}

	phoneClean := strings.ReplaceAll(strings.ReplaceAll(phone, "+", ""), " ", "")
	phoneInt, err := strconv.ParseInt(phoneClean, 10, 64)
	if err != nil {
		return fmt.Errorf("%w: invalid phone number: %v", ErrInvalidInput, err)
	}

	deviceHash := fmt.Sprintf("uniclient_%d", rand.Int63())
	startReq := map[string]interface{}{
		"1":  phoneInt,
		"2":  int64(4),
		"3":  "C28D46DC4C3A7A26564BFCC48B929086A95C93C98E789A19847BEE8627DE4E7D",
		"4":  deviceHash,
		"5":  "Chrome_138.0.0.0, Windows",
		"9":  int64(1),
		"10": map[string]interface{}{"0": int64(1)},
	}

	startResp, err := b.wsPost(baleServiceAuth, "StartPhoneAuth", startReq, "")
	if err != nil {
		return fmt.Errorf("%w: StartPhoneAuth: %v", ErrAuth, err)
	}

	transactionHash := pbGetString(startResp, "1")
	if transactionHash == "" {
		return fmt.Errorf("%w: no transaction_hash in StartPhoneAuth response: %v", ErrAuth, startResp)
	}
	otp := cfg.OTP
	if otp == "" {
		if b.authCodeCh != nil {
			close(b.authCodeReady)
			otp = <-b.authCodeCh
		} else {
			return fmt.Errorf("%w: OTP not provided", ErrAuth)
		}
	}

	validateReq := map[string]interface{}{
		"1": transactionHash,
		"2": otp,
		"3": map[string]interface{}{"1": int64(1)},
	}

	validateResp, err := b.wsPost(baleServiceAuth, "ValidateCode", validateReq, "")
	if err != nil {
		if strings.Contains(err.Error(), "4") || strings.Contains(err.Error(), "PASSWORD") {
			pwd := cfg.Password2F
			if pwd == "" {
				if b.authPwdCh != nil {
					close(b.authPwdReady)
					pwd = <-b.authPwdCh
				} else {
					return fmt.Errorf("2fa_required")
				}
			}
			validateResp, err = b.UserValidatePassword(transactionHash, pwd)
			if err != nil {
				return fmt.Errorf("%w: ValidatePassword: %v", ErrAuth, err)
			}
		} else {
			return fmt.Errorf("%w: ValidateCode: %v", ErrAuth, err)
		}
	}

	var token string

	if jwtField := pbGetMsg(validateResp, "4"); jwtField != nil {
		token = pbGetString(jwtField, "1")
	}
	if token == "" {
		token = pbGetString(validateResp, "1")
	}
	if token == "" {
		if nested := pbGetMsg(validateResp, "1"); nested != nil {
			token = pbGetString(nested, "1")
		}
	}
	if token == "" {
		return fmt.Errorf("%w: no token in ValidateCode response: %v", ErrAuth, validateResp)
	}

	if userAuth := pbGetMsg(validateResp, "2"); userAuth != nil {
		b.userID = pbGetInt64(userAuth, "1")
	}

	b.userToken = token
	b.userPhone = phone
	b.isBot = false
	b.authed = true

	if err := b.wsConnect(); err != nil {
		return fmt.Errorf("websocket connect after auth: %w", err)
	}

	if err := b.saveSession(); err != nil {
		fmt.Fprintf(os.Stderr, "bale: warning: could not save session: %v\n", err)
	}

	return nil
}

func (b *BaleCore) SubmitOTP(code string) error {
	if b.authCodeCh != nil {
		b.authCodeCh <- code
	}
	if b.authDoneCh != nil {
		select {
		case <-b.authDoneCh:
			if b.authErrCh != nil {
				return <-b.authErrCh
			}
			return nil
		case <-time.After(30 * time.Second):
			return fmt.Errorf("timeout waiting for OTP validation")
		}
	}
	return nil
}

func (b *BaleCore) Submit2FA(password string) error {
	if b.authPwdCh != nil {
		b.authPwdCh <- password
	}
	if b.authDoneCh != nil {
		select {
		case <-b.authDoneCh:
			if b.authErrCh != nil {
				return <-b.authErrCh
			}
			return nil
		case <-time.After(30 * time.Second):
			return fmt.Errorf("timeout waiting for 2FA validation")
		}
	}
	return nil
}

func (b *BaleCore) userSend(service, method string, payload map[string]interface{}) (map[string]interface{}, error) {
	if b.wsConn == nil {
		return nil, fmt.Errorf("%w: not connected", ErrNetwork)
	}
	return b.wsSend(service, method, payload)
}

func baleRID() int64 {
	return rand.Int63n(9000000000000000) + 1000000000000000
}

func balePeer(peerType int, peerID int64) map[string]interface{} {
	return map[string]interface{}{"1": int64(peerType), "2": peerID}
}

func baleExtractName(m map[string]interface{}) string {
	name := pbGetString(m, "3")
	if name != "" {
		if len(name) > 2 && name[0] == '\n' {
			if nested := pbGetMsg(m, "3"); nested != nil {
				if inner := pbGetString(nested, "1"); inner != "" {
					return inner
				}
			}
			raw := []byte(name)
			pos := 1
			for pos < len(raw) && raw[pos] >= 0x80 {
				pos++
			}
			pos++
			if pos < len(raw) {
				return string(raw[pos:])
			}
		}
		return name
	}
	if nick := pbGetString(m, "5"); nick != "" {
		return nick
	}
	if f4 := pbGetString(m, "4"); f4 != "" {
		return f4
	}
	return ""
}

func baleShortPeer(id int64) map[string]interface{} {
	return map[string]interface{}{"1": id, "2": int64(1)}
}

func baleInfoPeer(id int64, peerType int) map[string]interface{} {
	return map[string]interface{}{"1": id, "2": int64(peerType)}
}

func baleGroupOutPeer(groupID int64) map[string]interface{} {
	return baleShortPeer(groupID)
}

func baleUserOutPeer(uid int64) map[string]interface{} {
	return baleShortPeer(uid)
}

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

func parsePeerID(chatID string) (int64, int) {
	if parts := strings.SplitN(chatID, "|", 2); len(parts) == 2 {
		id, _ := strconv.ParseInt(parts[0], 10, 64)
		pt, _ := strconv.Atoi(parts[1])
		return id, pt
	}
	id, _ := strconv.ParseInt(chatID, 10, 64)
	if id < 0 {
		return -id, balePeerGroup
	}
	return id, balePeerPrivate
}

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
			replyInfo["3"] = map[string]interface{}{"1": replyToDate}
		}
		payload["5"] = replyInfo
	}
	resp, err := b.userSend(baleServiceMessaging, "SendMessage", payload)
	if resp != nil {
		resp["__rid"] = rid
	}
	return resp, err
}

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
		"3": map[string]interface{}{"1": dateList},
		"4": map[string]interface{}{"1": int64(0)},
	}
	return b.userSend(baleServiceMessaging, "DeleteMessage", payload)
}

func (b *BaleCore) UserForwardMessages(toChatID string, fromPeer map[string]interface{}, rids []int64, dates []int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(toChatID)
	newIDs := make([]interface{}, len(rids))
	for i := range rids {
		newIDs[i] = baleRID()
	}
	var fwdMsgs []interface{}
	for i, r := range rids {
		fwd := map[string]interface{}{
			"1": fromPeer,
			"2": r,
		}
		if i < len(dates) {
			fwd["3"] = map[string]interface{}{"1": dates[i]}
		}
		fwdMsgs = append(fwdMsgs, fwd)
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": newIDs,
		"3": fwdMsgs,
	}
	return b.userSend(baleServiceMessaging, "ForwardMessages", payload)
}

func (b *BaleCore) UserLoadHistory(chatID string, date int64, limit int, loadMode int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": date,
		"4": int64(loadMode),
		"5": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadHistory", payload)
}

func (b *BaleCore) UserLoadDialogs(offsetDate int64, limit int) (map[string]interface{}, error) {
	if offsetDate == 0 {
		offsetDate = time.Now().UnixMilli()
	}
	payload := map[string]interface{}{
		"1": offsetDate,
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "LoadDialogs", payload)
}

func (b *BaleCore) UserMessageRead(chatID string, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": date,
	}
	return b.userSend(baleServiceMessaging, "MessageRead", payload)
}

func (b *BaleCore) UserPinMessage(chatID string, msgRID int64, date int64, mid int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	if peerType == balePeerGroup || peerType == balePeerSupergroup || peerType == balePeerChannel {
		internalID, err := b.resolveGroupInternalID(peerID)
		if err != nil {
			return nil, err
		}
		payload := map[string]interface{}{
			"2": map[string]interface{}{"1": internalID},
			"3": date,
			"4": msgRID,
		}
		return b.userSend(baleServiceGroups, "PinMessage", payload)
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": map[string]interface{}{"1": date, "2": msgRID},
		"3": int64(0),
	}
	return b.userSend(baleServiceMessaging, "PinMessage", payload)
}

func (b *BaleCore) UserUnPinMessages(chatID string, msgs []map[string]interface{}, all bool) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	msgList := make([]interface{}, len(msgs))
	for i, m := range msgs {
		msgList[i] = m
	}
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": msgList,
	}
	if all {
		payload["3"] = int64(1)
	}
	return b.userSend(baleServiceMessaging, "UnPinMessages", payload)
}

func (b *BaleCore) UserLoadPinnedMessages(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
	}
	return b.userSend(baleServiceMessaging, "LoadPinnedMessages", payload)
}

func (b *BaleCore) UserClearChat(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
	}
	return b.userSend(baleServiceMessaging, "ClearChat", payload)
}

func (b *BaleCore) UserDeleteChat(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
	}
	return b.userSend(baleServiceMessaging, "DeleteChat", payload)
}

func (b *BaleCore) UserLoadUsers(userIDs []int64) (map[string]interface{}, error) {
	var peers []interface{}
	for _, uid := range userIDs {
		peers = append(peers, baleInfoPeer(uid, balePeerPrivate))
	}
	payload := map[string]interface{}{"1": peers}
	return b.userSend(baleServiceUsers, "LoadUsers", payload)
}

func (b *BaleCore) UserLoadFullUsers(userIDs []int64) (map[string]interface{}, error) {
	var peers []interface{}
	for _, uid := range userIDs {
		peers = append(peers, baleInfoPeer(uid, balePeerPrivate))
	}
	payload := map[string]interface{}{"1": peers}
	return b.userSend(baleServiceUsers, "LoadFullUsers", payload)
}

func (b *BaleCore) UserEditName(name string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditName", map[string]interface{}{"1": name})
}

func (b *BaleCore) UserEditNickName(nick string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditNickName", map[string]interface{}{"1": map[string]interface{}{"1": nick}})
}

func (b *BaleCore) UserCheckNickName(nick string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "CheckNickName", map[string]interface{}{"1": nick})
}

func (b *BaleCore) UserEditAbout(about string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditAbout", map[string]interface{}{"1": map[string]interface{}{"1": about}})
}

func (b *BaleCore) UserEditLocalName(userID int64, localName string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": userID,
		"2": int64(1),
		"3": localName,
	}
	return b.userSend(baleServiceUsers, "EditUserLocalName", payload)
}

func (b *BaleCore) UserBlockUser(userID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "BlockUser", map[string]interface{}{"1": baleInfoPeer(userID, balePeerPrivate)})
}

func (b *BaleCore) UserUnblockUser(userID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "UnblockUser", map[string]interface{}{"1": baleInfoPeer(userID, balePeerPrivate)})
}

func (b *BaleCore) UserLoadBlockedUsers() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "LoadBlockedUsers", map[string]interface{}{})
}

func (b *BaleCore) UserSearchContacts(query string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": query}
	return b.userSend(baleServiceUsers, "SearchContacts", payload)
}

func (b *BaleCore) UserImportContacts(contacts []map[string]interface{}) (map[string]interface{}, error) {
	var cl []interface{}
	for _, c := range contacts {
		cl = append(cl, c)
	}
	return b.userSend(baleServiceUsers, "ImportContacts", map[string]interface{}{"1": cl})
}

func (b *BaleCore) UserAddContact(userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": userID,
		"2": int64(1),
	}
	return b.userSend(baleServiceUsers, "AddContact", payload)
}

func (b *BaleCore) UserRemoveContact(userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": userID,
		"2": int64(1),
	}
	return b.userSend(baleServiceUsers, "RemoveContact", payload)
}

func (b *BaleCore) UserGetContacts() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "GetContacts", map[string]interface{}{})
}

func (b *BaleCore) UserResetContacts() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "ResetContacts", map[string]interface{}{})
}

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
		payload["8"] = map[string]interface{}{"1": username}
	}
	return b.userSend(baleServiceGroups, "CreateGroup", payload)
}

func (b *BaleCore) UserEditGroupTitle(groupID int64, title string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"3": title,
		"4": baleRID(),
	}
	return b.userSend(baleServiceGroups, "EditGroupTitle", payload)
}

func (b *BaleCore) UserEditGroupAbout(groupID int64, about string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
		"3": map[string]interface{}{"1": about},
	}
	return b.userSend(baleServiceGroups, "EditGroupAbout", payload)
}

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

func (b *BaleCore) UserKickUser(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
		"3": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "KickUser", payload)
}

func (b *BaleCore) UserMakeUserAdmin(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "MakeUserAdmin", payload)
}

func (b *BaleCore) UserRemoveUserAdmin(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "RemoveUserAdmin", payload)
}

func (b *BaleCore) UserSetMemberPermissions(groupID int64, userID int64, perms map[string]interface{}) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
		"3": perms,
	}
	return b.userSend(baleServiceGroups, "SetMemberPermissions", payload)
}

func (b *BaleCore) UserSetGroupDefaultPermissions(groupID int64, perms map[string]interface{}) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": perms,
	}
	return b.userSend(baleServiceGroups, "SetGroupDefaultPermissions", payload)
}

func (b *BaleCore) UserGetMemberPermissions(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "GetMemberPermissions", payload)
}

func (b *BaleCore) UserGetFullGroup(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetFullGroup", payload)
}

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

func (b *BaleCore) UserGetGroupMembersCount(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetGroupMembersCount", payload)
}

func (b *BaleCore) UserGetGroupInviteURL(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetGroupInviteURL", payload)
}

func (b *BaleCore) UserRevokeInviteURL(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "RevokeInviteURL", payload)
}

func (b *BaleCore) UserJoinGroup(token string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": token}
	return b.userSend(baleServiceGroups, "JoinGroup", payload)
}

func (b *BaleCore) UserJoinPublicGroup(peerID int64, peerType int) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": balePeer(peerType, peerID)}
	return b.userSend(baleServiceGroups, "JoinPublicGroup", payload)
}

func (b *BaleCore) UserLeaveGroup(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleRID(),
	}
	return b.userSend(baleServiceGroups, "LeaveGroup", payload)
}

func (b *BaleCore) UserGetBannedUsers(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetBannedUsers", payload)
}

func (b *BaleCore) UserUnBanUser(groupID int64, userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": baleUserOutPeer(userID),
	}
	return b.userSend(baleServiceGroups, "UnBanUser", payload)
}

func (b *BaleCore) UserSetRestriction(groupID int64, restriction int, username ...string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": map[string]interface{}{"1": groupID},
		"2": int64(restriction),
	}
	if restriction == 1 && len(username) > 0 && username[0] != "" {
		payload["3"] = map[string]interface{}{"1": username[0]}
	}
	return b.userSend(baleServiceGroups, "SetRestriction", payload)
}

func (b *BaleCore) UserTransferOwnership(groupID int64, newOwnerID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": newOwnerID,
	}
	return b.userSend(baleServiceGroups, "TransferOwnership", payload)
}

func (b *BaleCore) UserEditChannelNick(groupID int64, nick string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": nick,
		"3": baleRID(),
	}
	return b.userSend(baleServiceGroups, "EditChannelNick", payload)
}

func (b *BaleCore) UserGetPins(groupID int64, page int, limit int) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": int64(page),
		"3": int64(limit),
	}
	return b.userSend(baleServiceGroups, "GetPins", payload)
}

func (b *BaleCore) UserRemovePin(groupID int64, msgRID int64, date int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"2": msgRID,
		"3": date,
	}
	return b.userSend(baleServiceGroups, "RemoveSinglePin", payload)
}

func (b *BaleCore) UserRemoveAllPins(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "RemovePin", payload)
}

func (b *BaleCore) UserGetGroupPreview(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": baleGroupOutPeer(groupID)}
	return b.userSend(baleServiceGroups, "GetGroupPreview", payload)
}

func (b *BaleCore) UserEditGroupAvatar(groupID int64, fileID int64, accessHash int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"3": map[string]interface{}{"1": fileID, "2": accessHash},
		"4": baleRID(),
	}
	return b.userSend(baleServiceGroups, "EditGroupAvatar", payload)
}

func (b *BaleCore) UserRemoveGroupAvatar(groupID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(groupID),
		"4": baleRID(),
	}
	return b.userSend(baleServiceGroups, "RemoveGroupAvatar", payload)
}

func (b *BaleCore) UserGetFileUploadURL(size int64, name string, mimeType string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": size,
		"3": b.userID,
		"4": name,
		"5": mimeType,
	}
	return b.userSend(baleServiceFiles, "GetNasimFileUploadUrl", payload)
}

func (b *BaleCore) UserGetFileURL(fileID int64, accessHash int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": map[string]interface{}{
			"1": fileID,
			"2": accessHash,
			"3": map[string]interface{}{"1": int64(1)},
		},
	}
	return b.userSend(baleServiceFiles, "GetNasimFileUrl", payload)
}

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

func (b *BaleCore) UserTyping(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"3": int64(1),
	}
	return b.userSend(baleServicePresence, "Typing", payload)
}

func (b *BaleCore) UserStopTyping(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": int64(1),
	}
	return b.userSend(baleServicePresence, "StopTyping", payload)
}

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
		"3": true,
	}
	return b.userSend(baleServiceAbacus, "GetMessagesViews", payload)
}

func (b *BaleCore) UserGetParameters() (map[string]interface{}, error) {
	return b.userSend(baleServiceConfigs, "GetParameters", map[string]interface{}{})
}

func (b *BaleCore) UserEditParameter(key string, value string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": key,
		"2": map[string]interface{}{"1": value},
	}
	return b.userSend(baleServiceConfigs, "EditParameter", payload)
}

func (b *BaleCore) UserSignOut() (map[string]interface{}, error) {
	return b.wsPost(baleServiceAuth, "SignOut", map[string]interface{}{}, b.userToken)
}

func (b *BaleCore) UserValidatePassword(transactionHash string, password string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": transactionHash,
		"2": password,
	}
	return b.wsPost(baleServiceAuth, "ValidatePassword", payload, "")
}

func (b *BaleCore) UserSignUp(transactionHash string, name string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": transactionHash,
		"2": name,
	}
	return b.wsPost(baleServiceAuth, "SignUp", payload, "")
}

func (b *BaleCore) mapUserMessage(um map[string]interface{}) Message {
	msg := Message{
		Platform: balePlatform,
		Status:   MessageStatusSent,
	}

	rid := pbGetInt64(um, "4")
	dateMs := pbGetInt64(um, "3")
	msg.ID = int64Pair(rid, dateMs, ':')

	if peer := pbGetMsg(um, "1"); peer != nil {
		peerID := pbGetInt64(peer, "2")
		peerType := pbGetInt64(peer, "1")
		msg.ChatID = int64Pair(peerID, peerType, '|')
	}

	senderUID := pbGetInt64(um, "2")
	msg.SenderID = strconv.FormatInt(senderUID, 10)
	msg.IsOutgoing = senderUID == b.userID

	if dateMs > 1e12 {
		msg.Timestamp = time.UnixMilli(dateMs)
	} else if dateMs > 0 {
		msg.Timestamp = time.Unix(dateMs, 0)
	}

	b.mapUserMessageContent(um, "5", &msg)

	if quoted := pbGetMsg(um, "7"); quoted != nil {
		if qMsgID := pbGetMsg(quoted, "1"); qMsgID != nil {
			msg.ReplyToID = strconv.FormatInt(pbGetInt64(qMsgID, "1"), 10)
		}
		if qContent := pbGetMsg(quoted, "5"); qContent != nil {
			if qText := pbGetMsg(qContent, "15"); qText != nil {
				msg.ReplyPreview = truncateText(pbGetString(qText, "1"), 100)
			}
		}
	}

	return msg
}

func (b *BaleCore) mapUpdatedMessage(um map[string]interface{}) Message {
	msg := Message{
		Platform: balePlatform,
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
	msg.ID = int64Pair(rid, editDateMs, ':')
	if peer := pbGetMsg(um, "1"); peer != nil {
		peerID := pbGetInt64(peer, "2")
		peerType := pbGetInt64(peer, "1")
		msg.ChatID = int64Pair(peerID, peerType, '|')
	}
	if senderVal := pbGetMsg(um, "5"); senderVal != nil {
		senderUID := pbGetInt64(senderVal, "1")
		msg.SenderID = strconv.FormatInt(senderUID, 10)
		msg.IsOutgoing = senderUID == b.userID
	}
	b.mapUserMessageContent(um, "3", &msg)
	return msg
}

func (b *BaleCore) mapUserMessageContent(parent map[string]interface{}, field string, msg *Message) {
	content := pbGetMsg(parent, field)
	if content == nil {
		return
	}

	if textMsg := pbGetMsg(content, "15"); textMsg != nil {
		msg.Text = pbGetString(textMsg, "1")
	}

	if longText := pbGetMsg(content, "30"); longText != nil && msg.Text == "" {
		msg.Text = pbGetString(longText, "1")
	}

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
			ID:       int64Pair(fileID, accessHash, ':'),
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

	if svcMsg := pbGetMsg(content, "11"); svcMsg != nil {
		msg.Text = "[service message]"
		if text := pbGetString(svcMsg, "1"); text != "" {
			msg.Text = text
		}
	}

	if stickerMsg := pbGetMsg(content, "12"); stickerMsg != nil {
		if msg.Text == "" {
			msg.Text = "[sticker]"
		}
		if idVal := pbGetMsg(stickerMsg, "1"); idVal != nil {
			stickerID := pbGetInt64(idVal, "1")
			msg.Text = fmt.Sprintf("[sticker:%d]", stickerID)
		}
	}

	if pbGetMsg(content, "24") != nil && msg.Text == "" {
		msg.Text = "[animated sticker]"
	}

	if tmplMsg := pbGetMsg(content, "13"); tmplMsg != nil {
		b.mapUserMessageContent(tmplMsg, "1", msg)
	}

	if pollMsg := pbGetMsg(content, "29"); pollMsg != nil && msg.Text == "" {
		msg.Text = "[poll]"
	}

	if pbGetMsg(content, "17") != nil && msg.Text == "" {
		msg.Text = "[gift packet]"
	}

	if pbGetMsg(content, "28") != nil && msg.Text == "" {
		msg.Text = "[gold gift]"
	}

	if pbGetMsg(content, "3") != nil && msg.Text == "" {
		msg.Text = "[deleted]"
	}

	if content["5"] != nil && msg.Text == "" {
		msg.Text = "[forwarded]"
	}

	if pbGetMsg(content, "26") != nil && msg.Text == "" {
		msg.Text = "[live]"
	}

	if pbGetMsg(content, "25") != nil && msg.Text == "" {
		msg.Text = "[content removed]"
	}
}

func (b *BaleCore) mapHistoryMessage(mc map[string]interface{}) Message {
	msg := Message{
		Platform: balePlatform,
		Status:   MessageStatusSent,
	}

	senderUID := pbGetInt64(mc, "1")
	msg.SenderID = strconv.FormatInt(senderUID, 10)
	msg.IsOutgoing = senderUID == b.userID
	rid := pbGetInt64(mc, "2")
	dateMs := pbGetInt64(mc, "3")
	msg.ID = int64Pair(rid, dateMs, ':')

	if dateMs > 1e12 {
		msg.Timestamp = time.UnixMilli(dateMs)
	} else if dateMs > 0 {
		msg.Timestamp = time.Unix(dateMs, 0)
	}

	state := pbGetInt64(mc, "5")
	switch state {
	case 2:
		msg.Status = MessageStatusRead
	case 1:
		msg.Status = MessageStatusDelivered
	default:
		msg.Status = MessageStatusSent
	}

	if editedAt := pbGetMsg(mc, "12"); editedAt != nil {
		editMs := pbGetInt64(editedAt, "1")
		if editMs > 1e12 {
			t := time.UnixMilli(editMs)
			msg.EditedAt = &t
		}
	}

	b.mapUserMessageContent(mc, "4", &msg)

	if quoted := pbGetMsg(mc, "8"); quoted != nil {
		if qMsgID := pbGetMsg(quoted, "1"); qMsgID != nil {
			msg.ReplyToID = strconv.FormatInt(pbGetInt64(qMsgID, "1"), 10)
		}
		if qContent := pbGetMsg(quoted, "5"); qContent != nil {
			if qText := pbGetMsg(qContent, "15"); qText != nil {
				msg.ReplyPreview = truncateText(pbGetString(qText, "1"), 100)
			}
		}
	}

	return msg
}

func (b *BaleCore) GetChatInfo(chatID string) (*Dialog, error) {
	if b.isBot {
		info, err := b.GetChat(chatID)
		if err != nil {
			return nil, err
		}
		d := &Dialog{Platform: balePlatform, ID: chatID}
		d.Title = info.Title
		if d.Title == "" {
			d.Title = info.FirstName
			if info.LastName != "" {
				d.Title += " " + info.LastName
			}
		}
		switch info.Type {
		case "private":
			d.Type = ChatTypeDM
		case "group", "supergroup":
			d.Type = ChatTypeGroup
		case "channel":
			d.Type = ChatTypeChannel
		}
		return d, nil
	}
	return &Dialog{Platform: balePlatform, ID: chatID}, nil
}

func (b *BaleCore) EditChatTitle(chatID string, title string) error {
	if b.isBot {
		return b.setChatTitle(chatID, title)
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
		return b.setChatDescription(chatID, description)
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
		return b.banChatMember(chatID, uid)
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
		return b.banChatMember(chatID, uid)
	}
	return b.RemoveMember(chatID, userID)
}

func (b *BaleCore) UnbanMember(chatID string, userID string) error {
	if b.isBot {
		uid, _ := strconv.ParseInt(userID, 10, 64)
		return b.unbanChatMember(chatID, uid, false)
	}
	return fmt.Errorf("%w: bale user mode does not support unbanning", ErrNotSupported)
}

func (b *BaleCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	if b.isBot {
		admins, err := b.GetChatAdministrators(chatID)
		if err != nil {
			return nil, err
		}
		users := make([]User, 0, len(admins))
		for _, a := range admins {
			name := a.User.FirstName
			if a.User.LastName != "" {
				name += " " + a.User.LastName
			}
			users = append(users, User{
				ID:          strconv.FormatInt(a.User.ID, 10),
				DisplayName: name,
				Username:    a.User.Username,
				IsBot:       a.User.IsBot,
				Platform:    balePlatform,
			})
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
		users := []User{}
		if userList, ok := raw["1"].([]interface{}); ok {
			for _, item := range userList {
				if u, ok := item.(map[string]interface{}); ok {
					user := User{Platform: balePlatform}
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
		users := []User{}
		if userList, ok := raw["1"].([]interface{}); ok {
			for _, item := range userList {
				if u, ok := item.(map[string]interface{}); ok {
					user := User{Platform: balePlatform}
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
					d := Dialog{Platform: balePlatform, Type: ChatTypeDM}
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

func (b *BaleCore) GetSessions() ([]Session, error) {
	if b.isBot {
		return nil, fmt.Errorf("%w: bale bot API does not support session management", ErrNotSupported)
	}
	resp, err := b.getAuthSessions()
	if err != nil {
		return nil, err
	}
	var sessions []Session
	for _, item := range pbGetList(resp, "1") {
		s, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		sessions = append(sessions, Session{
			ID:       fmt.Sprintf("%d", pbGetInt64(s, "1")),
			Platform: balePlatform,
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
	_, err = b.terminateSessionReal(sid)
	return err
}

func (b *BaleCore) mapBotMessage(resp map[string]interface{}) *Message {
	result, ok := resp["result"].(map[string]interface{})
	if !ok {
		return nil
	}
	m := b.mapMessage(result)
	return &m
}

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

func (b *BaleCore) SetWebhook(url string, maxConnections int) error {
	params := map[string]interface{}{"url": url}
	if maxConnections > 0 {
		params["max_connections"] = maxConnections
	}
	_, err := b.apiRequest("setWebhook", params)
	return err
}

func (b *BaleCore) DeleteWebhook() error {
	_, err := b.apiRequest("deleteWebhook", nil)
	return err
}

func (b *BaleCore) GetWebhookInfo() (BaleWebhookInfo, error) {
	resp, err := b.apiRequest("getWebhookInfo", nil)
	if err != nil {
		return BaleWebhookInfo{}, err
	}
	return baleParseResult[BaleWebhookInfo](resp)
}

func (b *BaleCore) sendBotMedia(method, chatID, mediaKey, mediaVal, caption string, duration, length int) (*Message, error) {
	params := map[string]interface{}{
		"chat_id": chatID,
		mediaKey:  mediaVal,
	}
	if caption != "" {
		params["caption"] = caption
	}
	if duration > 0 {
		params["duration"] = duration
	}
	if length > 0 {
		params["length"] = length
	}
	resp, err := b.apiRequest(method, params)
	if err != nil {
		return nil, err
	}
	return b.mapBotMessage(resp), nil
}

func (b *BaleCore) SendPhoto(chatID, photo, caption string) (*Message, error) {
	return b.sendBotMedia("sendPhoto", chatID, "photo", photo, caption, 0, 0)
}

func (b *BaleCore) SendAudio(chatID, audio, caption string, duration int) (*Message, error) {
	return b.sendBotMedia("sendAudio", chatID, "audio", audio, caption, duration, 0)
}

func (b *BaleCore) SendDocument(chatID, document, caption string) (*Message, error) {
	return b.sendBotMedia("sendDocument", chatID, "document", document, caption, 0, 0)
}

func (b *BaleCore) SendVideo(chatID, video, caption string, duration int) (*Message, error) {
	return b.sendBotMedia("sendVideo", chatID, "video", video, caption, duration, 0)
}

func (b *BaleCore) SendAnimation(chatID, animation, caption string) (*Message, error) {
	return b.sendBotMedia("sendAnimation", chatID, "animation", animation, caption, 0, 0)
}

func (b *BaleCore) SendVoice(chatID, voice, caption string, duration int) (*Message, error) {
	return b.sendBotMedia("sendVoice", chatID, "voice", voice, caption, duration, 0)
}

func (b *BaleCore) SendVideoNote(chatID, videoNote string, duration, length int) (*Message, error) {
	return b.sendBotMedia("sendVideoNote", chatID, "video_note", videoNote, "", duration, length)
}

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

func (b *BaleCore) GetFile(fileID string) (BaleFileInfo, error) {
	resp, err := b.apiRequest("getFile", map[string]interface{}{"file_id": fileID})
	if err != nil {
		return BaleFileInfo{}, err
	}
	return baleParseResult[BaleFileInfo](resp)
}

func (b *BaleCore) RestrictChatMember(chatID string, userID int64, permissions map[string]bool) error {
	params := map[string]interface{}{
		"chat_id":     chatID,
		"user_id":     userID,
		"permissions": permissions,
	}
	_, err := b.apiRequest("restrictChatMember", params)
	return err
}

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

func (b *BaleCore) DeleteStickerFromSet(sticker string) error {
	_, err := b.apiRequest("deleteStickerFromSet", map[string]interface{}{"sticker": sticker})
	return err
}

func (b *BaleCore) GetUserProfilePhotos(userID int64, offset, limit int) (BaleUserProfilePhotos, error) {
	params := map[string]interface{}{"user_id": userID}
	if offset > 0 {
		params["offset"] = offset
	}
	if limit > 0 {
		params["limit"] = limit
	}
	resp, err := b.apiRequest("getUserProfilePhotos", params)
	if err != nil {
		return BaleUserProfilePhotos{}, err
	}
	return baleParseResult[BaleUserProfilePhotos](resp)
}

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

func (b *BaleCore) InviteUser(chatID string, userID int64) error {
	params := map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	}
	_, err := b.apiRequest("inviteUser", params)
	return err
}

func (b *BaleCore) DeleteAccount(reason string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "DeleteAccount", map[string]interface{}{"1": reason})
}

func (b *BaleCore) ChangePhone(newPhone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "ChangePhone", map[string]interface{}{"1": newPhone})
}

func (b *BaleCore) SendDeleteAccountVerificationCode() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "SendDeleteAccountVerificationCode", map[string]interface{}{})
}

func (b *BaleCore) SendChangePhoneVerificationCode(newPhone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "SendChangePhoneVerificationCode", map[string]interface{}{"1": newPhone})
}

func (b *BaleCore) EnableTwoFactorAuthentication(password string, hint string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": password}
	if hint != "" {
		payload["2"] = hint
	}
	return b.userSend(baleServiceAuth, "EnableTwoFactorAuthentication", payload)
}

func (b *BaleCore) DisableTwoFactorAuthentication(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "DisableTwoFactorAuthentication", map[string]interface{}{"1": password})
}

func (b *BaleCore) IsTwoFactorAuthenticationEnabled() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "IsTwoFactorAuthenticationEnabled", map[string]interface{}{})
}

func (b *BaleCore) VerifyEmail(email string, code string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "VerifyEmail", map[string]interface{}{"1": email, "2": code})
}

func (b *BaleCore) RecoverPassword() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "RecoverPassword", map[string]interface{}{})
}

func (b *BaleCore) VerifyPasswordRecovery(code string) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "VerifyPasswordRecovery", map[string]interface{}{"1": code})
}

func (b *BaleCore) SetNewPassword(transactionHash, newPassword, hint string) (map[string]interface{}, error) {
	payload := map[string]interface{}{"1": transactionHash, "2": newPassword}
	if hint != "" {
		payload["3"] = hint
	}
	return b.userSend(baleServiceAuth, "SetNewPassword", payload)
}

func (b *BaleCore) TerminateAllSessions() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "TerminateAllSessions", map[string]interface{}{})
}

func (b *BaleCore) EditSex(sex int) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditSex", map[string]interface{}{"1": int64(sex)})
}

func (b *BaleCore) EditBirthDate(birthDate string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditBirthDate", map[string]interface{}{"1": birthDate})
}

func (b *BaleCore) EditAvatarGRPC(fileID int64, accessHash int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": map[string]interface{}{"1": fileID, "2": accessHash},
	}
	return b.userSend(baleServiceUsers, "EditAvatar", payload)
}

func (b *BaleCore) RemoveAvatar() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "RemoveAvatar", map[string]interface{}{})
}

func (b *BaleCore) EditMyTimeZone(timezone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "EditMyTimeZone", map[string]interface{}{"1": timezone})
}

func (b *BaleCore) EditMyPreferredLanguages(langs []string) (map[string]interface{}, error) {
	langList := make([]interface{}, len(langs))
	for i, l := range langs {
		langList[i] = l
	}
	return b.userSend(baleServiceUsers, "EditMyPreferredLanguages", map[string]interface{}{"1": langList})
}

func (b *BaleCore) LoadAvatars(userID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "LoadAvatars", map[string]interface{}{"1": baleUserOutPeer(userID)})
}

func (b *BaleCore) NotifyAboutDeviceInfo(deviceModel, osVersion, appVersion string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": deviceModel,
		"2": osVersion,
		"3": appVersion,
	}
	return b.userSend(baleServiceUsers, "NotifyAboutDeviceInfo", payload)
}

func (b *BaleCore) GetUserPrivacyStatus() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "GetUserPrivacyStatus", map[string]interface{}{})
}

func (b *BaleCore) SetUserPrivacyStatus(key string, value int) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "SetUserPrivacyStatus", map[string]interface{}{"1": key, "2": int64(value)})
}

func (b *BaleCore) GetUserFullPrivacy() (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "GetUserFullPrivacy", map[string]interface{}{})
}

func (b *BaleCore) IsNameAllowed(name string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "IsNameAllowed", map[string]interface{}{"1": name})
}

func (b *BaleCore) ChangePhoneNumber(newPhone string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "ChangePhoneNumber", map[string]interface{}{"1": newPhone})
}

func (b *BaleCore) ConfirmPhoneNumber(transactionHash, code string) (map[string]interface{}, error) {
	return b.userSend(baleServiceUsers, "ConfirmPhoneNumber", map[string]interface{}{"1": transactionHash, "2": code})
}

func (b *BaleCore) ReceiveCall(callID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "ReceiveCall", map[string]interface{}{"1": callID})
}

func (b *BaleCore) DiscardCall(callID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMeet, "DiscardCall", map[string]interface{}{"1": callID})
}

const baleServiceMagazine = "bale.magazine.v1.Magazine"

func (b *BaleCore) UpvotePost(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMagazine, "UpvotePost", payload)
}

func (b *BaleCore) RevokeUpvotedPost(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMagazine, "RevokeUpvotedPost", payload)
}

func (b *BaleCore) GetMessageUpvoters(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMagazine, "GetMessageUpvoters", payload)
}

const baleServicePush = "bale.push.v1.Push"

func (b *BaleCore) RegisterPush(token string, platform int) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "RegisterPush", map[string]interface{}{"1": token, "2": int64(platform)})
}

func (b *BaleCore) UnregisterPush(token string) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "UnregisterPush", map[string]interface{}{"1": token})
}

func (b *BaleCore) RegisterGooglePush(token string) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "RegisterGooglePush", map[string]interface{}{"1": token})
}

func (b *BaleCore) UnregisterGooglePush(token string) (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "UnregisterGooglePush", map[string]interface{}{"1": token})
}

func (b *BaleCore) UnregisterAllPushCredentials() (map[string]interface{}, error) {
	return b.userSend(baleServicePush, "UnregisterAllPushCredentials", map[string]interface{}{})
}

const baleServiceRamz = "bale.ramz.v1.Ramz"

func (b *BaleCore) SetRamzPassword(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "SetPassword", map[string]interface{}{"1": password})
}

func (b *BaleCore) DeleteRamzPassword(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "DeletePassword", map[string]interface{}{"1": password})
}

func (b *BaleCore) SendRamzOTP() (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "SendOTP", map[string]interface{}{})
}

func (b *BaleCore) ForgetRamzPassword(otp string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "ForgetPassword", map[string]interface{}{"1": otp})
}

func (b *BaleCore) ValidateRamzOTP(otp string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "ValidateOTP", map[string]interface{}{"1": otp})
}

func (b *BaleCore) CheckRamzPasswordSet() (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "CheckPasswordSet", map[string]interface{}{})
}

func (b *BaleCore) CheckRamzPassword(password string) (map[string]interface{}, error) {
	return b.userSend(baleServiceRamz, "CheckPassword", map[string]interface{}{"1": password})
}

const baleServiceReport = "bale.report.v1.Report"

func (b *BaleCore) ReportInappropriateContent(chatID string, rid int64, reason string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": reason,
	}
	return b.userSend(baleServiceReport, "ReportInappropriateContent", payload)
}

func (b *BaleCore) ReportDismiss(chatID string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceReport, "ReportDismiss", map[string]interface{}{"1": balePeer(peerType, peerID)})
}

func (b *BaleCore) SearchPeerMessages(chatID string, query string, limit int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": query,
		"3": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "SearchPeerMessages", payload)
}

func (b *BaleCore) SearchPeerMedia(chatID string, mediaType int, limit int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": int64(mediaType),
		"3": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "SearchPeerMedia", payload)
}

func (b *BaleCore) SearchMembers(chatID string, query string) (map[string]interface{}, error) {
	peerID, _ := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(peerID),
		"2": query,
	}
	return b.userSend(baleServiceGroups, "SearchMembers", payload)
}

func (b *BaleCore) SearchLinks(chatID string, limit int) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "SearchLinks", payload)
}

func (b *BaleCore) GlobalChannelSearch(query string, limit int) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": query,
		"2": int64(limit),
	}
	return b.userSend(baleServiceMessaging, "GlobalChannelSearch", payload)
}

func (b *BaleCore) EditTopic(chatID string, topicID int64, title string) (map[string]interface{}, error) {
	peerID, _ := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(peerID),
		"2": topicID,
		"3": title,
	}
	return b.userSend(baleServiceMessaging, "EditTopic", payload)
}

func (b *BaleCore) DeleteTopic(chatID string, topicID int64) (map[string]interface{}, error) {
	peerID, _ := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": baleGroupOutPeer(peerID),
		"2": topicID,
	}
	return b.userSend(baleServiceMessaging, "DeleteTopic", payload)
}

func (b *BaleCore) EditFolder(folderID int64, title string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": folderID,
		"2": title,
	}
	return b.userSend(baleServiceMessaging, "EditFolder", payload)
}

func (b *BaleCore) DeleteFolder(folderID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMessaging, "DeleteFolder", map[string]interface{}{"1": folderID})
}

func (b *BaleCore) ReorderFolders(folderIDs []int64) (map[string]interface{}, error) {
	ids := make([]interface{}, len(folderIDs))
	for i, id := range folderIDs {
		ids[i] = id
	}
	return b.userSend(baleServiceMessaging, "ReorderFolders", map[string]interface{}{"1": ids})
}

func (b *BaleCore) ClosePoll(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMessaging, "ClosePoll", payload)
}

func (b *BaleCore) GetPollResults(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceMessaging, "GetPollResults", payload)
}

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

func (b *BaleCore) GetMiniAppUrl(botID int64, shortName string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": shortName,
	}
	return b.userSend(baleServiceMessaging, "GetMiniAppUrl", payload)
}

func (b *BaleCore) GetBotMenuButtons(botID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceMessaging, "GetBotMenuButtons", map[string]interface{}{"1": baleUserOutPeer(botID)})
}

func (b *BaleCore) InvokeCustomMethod(botID int64, method string, params string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleUserOutPeer(botID),
		"2": method,
		"3": params,
	}
	return b.userSend(baleServiceMessaging, "InvokeCustomMethod", payload)
}

const baleServiceAI = "bale.ai.v1.AI"

func (b *BaleCore) GetTranscript(chatID string, rid int64, date int64) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": date,
	}
	return b.userSend(baleServiceAI, "GetTranscript", payload)
}

func (b *BaleCore) GetInAppUpdate() (map[string]interface{}, error) {
	return b.userSend(baleServiceConfigs, "GetInAppUpdate", map[string]interface{}{})
}

const baleServiceFanoos = "bale.fanoos.v1.Fanoos"

func (b *BaleCore) FanoosSend(eventName string, eventData map[string]string) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": eventName,
	}
	if len(eventData) > 0 {
		pairs := make([]interface{}, 0, len(eventData))
		for k, v := range eventData {
			pairs = append(pairs, map[string]interface{}{"1": k, "2": v})
		}
		payload["2"] = pairs
	}
	return b.userSend(baleServiceFanoos, "FanoosSend", payload)
}

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

func (b *BaleCore) DeleteMyCommands() (map[string]interface{}, error) {
	return b.apiRequest("deleteMyCommands", nil)
}

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

func (b *BaleCore) getAuthSessions() (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "GetAuthSessions", map[string]interface{}{})
}

func (b *BaleCore) terminateSessionReal(sessionID int64) (map[string]interface{}, error) {
	return b.userSend(baleServiceAuth, "TerminateSession", map[string]interface{}{"1": sessionID})
}

func (b *BaleCore) LoadFolders() (map[string]interface{}, error) {
	return b.userSend(baleServiceMessaging, "LoadFolders", map[string]interface{}{})
}

func (b *BaleCore) GetFullUser(userID int64) (map[string]interface{}, error) {
	payload := map[string]interface{}{
		"1": baleInfoPeer(userID, balePeerPrivate),
	}
	return b.userSend(baleServiceUsers, "GetFullUser", payload)
}

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

const baleServicePushak = "ai.bale.pushak.Push"

func (b *BaleCore) PushSetConfig(config map[string]interface{}) (map[string]interface{}, error) {
	return b.userSend(baleServicePushak, "SetConfig", config)
}

func (b *BaleCore) MarkAsUnread(chatID string) (map[string]interface{}, error) {
	return nil, fmt.Errorf("%w: %s server does not implement MarkAsUnread", ErrNotSupported, balePlatform)
}

func (b *BaleCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support server-side mute", ErrNotSupported, balePlatform)
}

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
		"7": scheduleDate,
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendProtectedMessage(chatID string, text string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"27": map[string]interface{}{"1": text},
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendLongTextMessage(chatID string, text string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"30": map[string]interface{}{"1": text},
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendBankMessage(chatID string, bankData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"1": bankData,
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendJsonMessage(chatID string, jsonData string) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"7": map[string]interface{}{"1": jsonData},
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendOrderMessage(chatID string, orderData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"9": orderData,
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendAnimatedSticker(chatID string, stickerData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"24": stickerData,
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) SendLiveMessage(chatID string, liveData map[string]interface{}) (map[string]interface{}, error) {
	peerID, peerType := parsePeerID(chatID)
	rid := baleRID()
	payload := map[string]interface{}{
		"1": balePeer(peerType, peerID),
		"2": rid,
		"3": map[string]interface{}{
			"26": liveData,
		},
		"6": map[string]interface{}{"1": int64(peerType), "2": peerID},
	}
	return b.userSend(baleServiceMessaging, "SendMessage", payload)
}

func (b *BaleCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, balePlatform)
}

func (b *BaleCore) UnpinAllMessages(chatID string) error {
	return b.unpinAllChatMessages(chatID)
}

func (b *BaleCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, balePlatform)
}

func (b *BaleCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, balePlatform)
}

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

func (b *BaleCore) UserGetAnonymousContactPage() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceAnonContact, "GetUserAnonymousContactPage", map[string]interface{}{})
}

func (b *BaleCore) UserGetLinkStatus(link string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceFalake, "GetLinkStatus", map[string]interface{}{"1": link})
}

func (b *BaleCore) UserGetLLMAuthToken() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceLLMAuth, "GetAuthToken", map[string]interface{}{})
}

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

func (b *BaleCore) UserSetMyCommands(commands []map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "SetMyCommands", map[string]interface{}{"1": commands})
}

func (b *BaleCore) UserDeleteMyCommands() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "DeleteMyCommands", map[string]interface{}{})
}

func (b *BaleCore) UserGetMyCommands() (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "GetMyCommands", map[string]interface{}{})
}

func (b *BaleCore) UserTerminateSession(sessionID int64) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "TerminateSession", map[string]interface{}{"1": sessionID})
}

func (b *BaleCore) UserCreateFolder(title string, peerIDs []string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peers := make([]map[string]interface{}, len(peerIDs))
	for i, pid := range peerIDs {
		id, pt := parsePeerID(pid)
		peers[i] = balePeer(pt, id)
	}
	return b.userSend(baleServiceMessaging, "CreateFolder", map[string]interface{}{"1": title, "2": peers})
}

func (b *BaleCore) UserLoadDialogsFiltered(filterType int, offset int64, limit int) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "LoadDialogsFiltered", map[string]interface{}{
		"1": int64(filterType), "2": offset, "3": int64(limit),
	})
}

func (b *BaleCore) UserPushSetConfig(config map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	return b.userSend(baleServiceMessaging, "PushSetConfig", config)
}

func (b *BaleCore) UserMarkAsUnread(chatID string, unread bool) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "MarkAsUnread", map[string]interface{}{
		"1": balePeer(peerType, peerID), "2": unread,
	})
}

func (b *BaleCore) UserSendScheduledMessage(chatID string, date int64, msg map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	msg["1"] = balePeer(peerType, peerID)
	msg["2"] = date
	return b.userSend(baleServiceMessaging, "SendScheduledMessage", msg)
}

func (b *BaleCore) UserSendProtectedMessage(chatID string, msg map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	msg["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendProtectedMessage", msg)
}

func (b *BaleCore) UserSendLongTextMessage(chatID string, text string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "SendLongTextMessage", map[string]interface{}{
		"1": balePeer(peerType, peerID), "2": text,
	})
}

func (b *BaleCore) UserSendBankMessage(chatID string, bankMsg map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	bankMsg["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendBankMessage", bankMsg)
}

func (b *BaleCore) UserSendJsonMessage(chatID string, jsonData string) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	return b.userSend(baleServiceMessaging, "SendJsonMessage", map[string]interface{}{
		"1": balePeer(peerType, peerID), "2": jsonData,
	})
}

func (b *BaleCore) UserSendOrderMessage(chatID string, order map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	order["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendOrderMessage", order)
}

func (b *BaleCore) UserSendAnimatedSticker(chatID string, stickerData map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	stickerData["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendAnimatedSticker", stickerData)
}

func (b *BaleCore) UserSendLiveMessage(chatID string, liveData map[string]interface{}) (map[string]interface{}, error) {
	if !b.authed {
		return nil, ErrAuth
	}
	peerID, peerType := parsePeerID(chatID)
	liveData["1"] = balePeer(peerType, peerID)
	return b.userSend(baleServiceMessaging, "SendLiveMessage", liveData)
}
