package cores

import (
	"bytes"
	"context"
	"crypto"
	"crypto/aes"
	"crypto/cipher"
	"hash"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	mrand "math/rand"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
)

// RubikaCore implements the Core interface for Rubika.
type RubikaCore struct {
	mu sync.RWMutex
	wg sync.WaitGroup

	// Auth state
	auth       string // 32-char auth key
	key        string // 32-char passphrase (AES key)
	decodeAuth string // substitution-ciphered auth for wire format
	guid       string // current user GUID
	phone      string // phone number for session save
	privateKey *rsa.PrivateKey
	authed     bool
	isBot      bool
	botToken   string

	// Network
	httpClient  *http.Client
	apiURL      string              // current best API endpoint
	wssURL      string              // WebSocket endpoint
	apiMap      map[string]string   // DC code → API URL
	storageMap  map[string]string   // DC code → storage/file URL
	apiPriority []string            // ordered DC codes
	userAgent   string
	platform    rubikaPlatformConfig

	// WebSocket
	wsConn   *websocket.Conn
	wsCtx    context.Context
	wsCancel context.CancelFunc

	// Session file
	sessionPath string

	// Update handlers
	updateHandlers       []func(Update)
	chatUpdateHandlers   []func(map[string]interface{})
	activityHandlers     []func(map[string]interface{})
	notificationHandlers []func(map[string]interface{})
	removeNotifHandlers  []func(map[string]interface{})
	updateMu             sync.RWMutex

	// Context
	ctx    context.Context
	cancel context.CancelFunc

	// Active voice chat / call
	activeCall   *rubikaActiveCall
	activeCallMu sync.Mutex
}

var _ Core = (*RubikaCore)(nil)

// rubikaActiveCall holds state for an active voice chat session.
type rubikaActiveCall struct {
	session    *CallSession
	chatGUID   string
	vcID       string // voice_chat_id
	pc         *webrtc.PeerConnection
	audioTrack *webrtc.TrackLocalStaticRTP
	muted      bool
	cancel     context.CancelFunc
	rtpRecv    atomic.Int64 // count of received RTP packets (from Janus mix)
	rtpSent    atomic.Int64 // count of sent RTP packets

	// Audio I/O
	audioInCh   chan []byte     // channel to feed Opus frames for sending
	onAudioRecv func([]byte)   // callback for received Opus frames from Janus mix
}

type rubikaPlatformConfig struct {
	AppName    string `json:"app_name"`
	AppVersion string `json:"app_version"`
	Platform   string `json:"platform"`
	Package    string `json:"package"`
	LangCode   string `json:"lang_code"`
}

type rubikaSession struct {
	Phone      string `json:"phone"`
	Auth       string `json:"auth"`
	GUID       string `json:"guid"`
	UserAgent  string `json:"user_agent"`
	PrivateKey string `json:"private_key"` // PEM
}

// ══════════════════════════════════════════════════════════════════════════════
// Typed response/request structs (Step 13.0 — protobuf-ready)
// ══════════════════════════════════════════════════════════════════════════════

// RubikaGroupInfo represents group information from getGroupInfo.
type RubikaGroupInfo struct {
	GroupGUID        string `json:"group_guid"`
	GroupTitle       string `json:"group_title"`
	CountMembers     int    `json:"count_members"`
	Description      string `json:"description"`
	SlowMode         int    `json:"slow_mode"`
	ChatHistoryForNewMembers string `json:"chat_history_for_new_members"`
	EventMessages    bool   `json:"event_messages"`
	GroupType        string `json:"group_type"`
	Username         string `json:"username"`
	AvatarThumbnail  string `json:"avatar_thumbnail"`
	GroupVoiceChatID string `json:"group_voice_chat_id"`
}

// RubikaChannelInfo represents channel information from getChannelInfo.
type RubikaChannelInfo struct {
	ChannelGUID        string `json:"channel_guid"`
	ChannelTitle       string `json:"channel_title"`
	CountMembers       int    `json:"count_members"`
	Description        string `json:"description"`
	Username           string `json:"username"`
	ChannelType        string `json:"channel_type"`
	AvatarThumbnail    string `json:"avatar_thumbnail"`
	IsVerified         bool   `json:"is_verified"`
	SignMessages       bool   `json:"sign_messages"`
	ChannelVoiceChatID string `json:"channel_voice_chat_id"`
}

// RubikaUserInfo represents user information from getUserInfo.
type RubikaUserInfo struct {
	UserGUID        string `json:"user_guid"`
	FirstName       string `json:"first_name"`
	LastName        string `json:"last_name"`
	Username        string `json:"username"`
	Phone           string `json:"phone"`
	Bio             string `json:"bio"`
	AvatarThumbnail string `json:"avatar_thumbnail"`
	IsVerified      bool   `json:"is_verified"`
	IsDeleted       bool   `json:"is_deleted"`
	LastOnline      int64  `json:"last_online"`
	OnlineStatus    string `json:"online_time_status"`
}

// RubikaMember represents a group/channel member entry.
type RubikaMember struct {
	MemberGUID string `json:"member_guid"`
	FirstName  string `json:"first_name"`
	LastName   string `json:"last_name"`
	Username   string `json:"username"`
}

// RubikaMemberList is a paginated list of members.
type RubikaMemberList struct {
	Members     []RubikaMember `json:"in_chat_members"`
	HasContinue bool           `json:"has_continue"`
	NextStartID string         `json:"next_start_id"`
}

// RubikaAccessEntry represents an admin access permission.
type RubikaAccessEntry struct {
	Access string `json:"access"`
}

// RubikaAvatar represents a single avatar entry.
type RubikaAvatar struct {
	AvatarID  string `json:"avatar_id"`
	MainFileID string `json:"main_file_id"`
	ThumbFileID string `json:"thumb_file_id"`
}

// RubikaAvatarList is the response for GetAvatars.
type RubikaAvatarList struct {
	Avatars []RubikaAvatar `json:"avatars"`
}

// RubikaStickerSet represents a sticker set.
type RubikaStickerSet struct {
	StickerSetID string `json:"sticker_set_id"`
	Title        string `json:"title"`
	Count        int    `json:"count"`
}

// RubikaPollStatus represents poll status info.
type RubikaPollStatus struct {
	State          string          `json:"state"`
	SelectionCount map[string]int  `json:"selection_count"`
	TotalCount     int             `json:"total_count"`
}

// RubikaPollVoters represents voters for a poll option.
type RubikaPollVoters struct {
	Voters      []RubikaMember `json:"voters"`
	HasContinue bool           `json:"has_continue"`
	NextStartID string         `json:"next_start_id"`
}

// RubikaReactionInfo represents reactions on a message.
type RubikaReactionInfo struct {
	Reactions []struct {
		Emoji string `json:"emoji"`
		Count int    `json:"count"`
	} `json:"reactions"`
}

// RubikaPrivacySettings represents privacy setting values.
type RubikaPrivacySettings struct {
	Settings map[string]string `json:"settings"`
}

// RubikaTwoStepInfo represents 2FA status.
type RubikaTwoStepInfo struct {
	HasPassword   bool   `json:"has_password"`
	PasswordHint  string `json:"password_hint"`
}

// RubikaFolderInfo represents a folder returned by addFolder.
type RubikaFolderInfo struct {
	FolderID          string   `json:"folder_id"`
	Name              string   `json:"name"`
	IncludeChatTypes  []string `json:"include_chat_types"`
	IncludeObjectGUIDs []string `json:"include_object_guids"`
	ExcludeTypes      []string `json:"exclude_chat_types"`
}

// RubikaSessionInfo represents a logged-in session.
type RubikaSessionInfo struct {
	SessionKey  string `json:"session_key"`
	DeviceModel string `json:"device_model"`
	Platform    string `json:"platform"`
	AppVersion  string `json:"app_version"`
	IP          string `json:"ip"`
	Country     string `json:"country"`
	IsCurrent   bool   `json:"is_current"`
}

// RubikaVoiceChatInfo represents voice chat response data.
type RubikaVoiceChatInfo struct {
	VoiceChatID string `json:"voice_chat_id"`
	SDPAnswer   string `json:"sdp_answer_data"`
}

// RubikaUploadInfo represents file upload request response.
type RubikaUploadInfo struct {
	ID             string `json:"id"`
	UploadURL      string `json:"upload_url"`
	AccessHashSend string `json:"access_hash_send"`
	DCID           int    `json:"dc_id"`
}

// RubikaBotInfo represents BotGetMe response.
type RubikaBotInfo struct {
	UserGUID  string `json:"user_guid"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	Username  string `json:"username"`
	IsBot     bool   `json:"is_bot"`
}

// RubikaBotChatInfo represents BotGetChat response.
type RubikaBotChatInfo struct {
	ChatGUID    string `json:"chat_guid"`
	Title       string `json:"title"`
	ChatType    string `json:"chat_type"`
	CountMembers int   `json:"count_members"`
}

// RubikaBotJoinStatus represents BotCheckJoin response.
type RubikaBotJoinStatus struct {
	IsMember bool `json:"is_member"`
}

// RubikaLinkInfo represents a join link response.
type RubikaLinkInfo struct {
	JoinLink string `json:"join_link"`
}

// RubikaGroupEdit represents editable group fields.
type RubikaGroupEdit struct {
	Title       string `json:"title,omitempty"`
	Description string `json:"description,omitempty"`
	SlowMode    *int   `json:"slow_mode,omitempty"`
	ChatHistory string `json:"chat_history_for_new_members,omitempty"`
}

// RubikaChannelEdit represents editable channel fields.
type RubikaChannelEdit struct {
	Title        string `json:"title,omitempty"`
	Description  string `json:"description,omitempty"`
	SignMessages *bool  `json:"sign_messages,omitempty"`
}

// RubikaKeypadRow represents one row of an inline keypad.
type RubikaKeypadRow struct {
	Buttons []RubikaKeypadButton `json:"buttons"`
}

// RubikaKeypadButton represents a single keypad button.
type RubikaKeypadButton struct {
	ID           string `json:"id"`
	Type         string `json:"type"` // "Simple", "TextInline", "RequestPhone", etc.
	ButtonText   string `json:"button_text"`
	ButtonURL    string `json:"button_url,omitempty"`
	ButtonQuery  string `json:"button_query,omitempty"`
}

// RubikaBotSendOpts represents optional parameters for bot send methods.
type RubikaBotSendOpts struct {
	ReplyToMessageID string            `json:"reply_to_message_id,omitempty"`
	InlineKeypad     []RubikaKeypadRow `json:"inline_keypad,omitempty"`
}

// RubikaFileInline represents file metadata for upload/avatar operations.
type RubikaFileInline struct {
	FileID        string `json:"file_id"`
	FileName      string `json:"file_name"`
	Mime          string `json:"mime"`
	Size          int64  `json:"size"`
	DCID          int    `json:"dc_id"`
	AccessHashRec string `json:"access_hash_rec"`
	ThumbInline   string `json:"thumb_inline,omitempty"`
	Width         int    `json:"width,omitempty"`
	Height        int    `json:"height,omitempty"`
}

// RubikaMessageShareInfo represents a shared message URL.
type RubikaMessageShareInfo struct {
	Link string `json:"link"`
}

// RubikaContactImportResult represents the result of importing contacts.
type RubikaContactImportResult struct {
	Users []RubikaUserInfo `json:"users"`
}

// rubikaParseData is a helper to extract and parse a JSON sub-object from an API response map.
func rubikaParseData[T any](data map[string]interface{}, key string) (T, error) {
	var result T
	raw, ok := data[key]
	if !ok {
		return result, fmt.Errorf("rubika: missing %q in response", key)
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return result, err
	}
	err = json.Unmarshal(b, &result)
	return result, err
}

// rubikaParseFlat parses the entire response map directly into a struct.
func rubikaParseFlat[T any](data map[string]interface{}) (T, error) {
	var result T
	b, err := json.Marshal(data)
	if err != nil {
		return result, err
	}
	err = json.Unmarshal(b, &result)
	return result, err
}

// NewRubikaCore creates a new Rubika core instance.
func NewRubikaCore(sessionPath string) *RubikaCore {
	ctx, cancel := context.WithCancel(context.Background())
	return &RubikaCore{
		httpClient: &http.Client{Timeout: 20 * time.Second},
		userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
			"AppleWebKit/537.36 (KHTML, like Gecko) " +
			"Chrome/102.0.0.0 Safari/537.36",
		platform: rubikaPlatformConfig{
			AppName:    "Main",
			AppVersion: "2.5.4",
			Platform:   "PWA",
			Package:    "m.rubika.ir",
			LangCode:   "fa",
		},
		apiMap:      make(map[string]string),
		storageMap:  make(map[string]string),
		sessionPath: sessionPath,
		ctx:         ctx,
		cancel:      cancel,
	}
}

const rubikaPlatform = "rubika"

// --- Core Interface: Identity ---

// Name returns the platform identifier for Rubika.
func (r *RubikaCore) Name() string { return rubikaPlatform }

// Capabilities returns the list of supported features for Rubika.
func (r *RubikaCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapReactions, CapPolls, CapStickers,
		CapFolders, CapAdmin, CapSessions, CapTyping, CapLocation,
		CapFileTransfer,
	}
}

// --- Crypto helpers ---

// decodeAuthStr applies Rubika's substitution cipher to the auth string.
func decodeAuthStr(auth string) string {
	result := make([]byte, len(auth))
	for i := 0; i < len(auth); i++ {
		c := auth[i]
		switch {
		case c >= 'a' && c <= 'z':
			result[i] = byte(((32-(int(c)-97))%26)+97)
		case c >= 'A' && c <= 'Z':
			result[i] = byte(((29-(int(c)-65))%26)+65)
		case c >= '0' && c <= '9':
			result[i] = byte(((13-(int(c)-48))%10)+48)
		default:
			result[i] = c
		}
	}
	return string(result)
}

// passphrase derives the AES key from the 32-char auth string.
// Handles both lowercase letters (+9 mod 26) and digits (+5 mod 10).
// Verified against official Rubika JS web client (2026-04-05).
func passphrase(auth string) string {
	if len(auth) != 32 {
		return auth
	}
	result := make([]byte, 32)
	copy(result[0:8], auth[16:24])
	copy(result[8:16], auth[0:8])
	copy(result[16:24], auth[24:32])
	copy(result[24:32], auth[8:16])
	for i, c := range result {
		if c >= '0' && c <= '9' {
			result[i] = byte(((int(c)-'0'+5)%10)+'0')
		} else {
			result[i] = byte(((int(c)-'a'+9)%26)+'a')
		}
	}
	return string(result)
}

// rubikaEncrypt encrypts data using AES-256-CBC with zero IV.
var rubikaZeroIV [aes.BlockSize]byte

func rubikaEncrypt(data interface{}, key string) (string, error) {
	var plaintext []byte
	switch v := data.(type) {
	case string:
		plaintext = []byte(v)
	case []byte:
		plaintext = v
	default:
		j, err := json.Marshal(v)
		if err != nil {
			return "", fmt.Errorf("json marshal: %w", err)
		}
		plaintext = j
	}

	block, err := aes.NewCipher([]byte(key))
	if err != nil {
		return "", fmt.Errorf("aes cipher: %w", err)
	}

	padLen := aes.BlockSize - (len(plaintext) % aes.BlockSize)
	padded := make([]byte, len(plaintext)+padLen)
	copy(padded, plaintext)
	for i := len(plaintext); i < len(padded); i++ {
		padded[i] = byte(padLen)
	}

	ciphertext := make([]byte, len(padded))
	mode := cipher.NewCBCEncrypter(block, rubikaZeroIV[:])
	mode.CryptBlocks(ciphertext, padded)

	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// rubikaDecrypt decrypts AES-256-CBC data with zero IV.
func rubikaDecrypt(encrypted string, key string) (map[string]interface{}, error) {
	data, err := base64.StdEncoding.DecodeString(encrypted)
	if err != nil {
		data, err = base64.URLEncoding.DecodeString(encrypted)
		if err != nil {
			return nil, fmt.Errorf("base64 decode: %w", err)
		}
	}

	block, err := aes.NewCipher([]byte(key))
	if err != nil {
		return nil, fmt.Errorf("aes cipher: %w", err)
	}

	if len(data)%aes.BlockSize != 0 {
		return nil, fmt.Errorf("ciphertext not multiple of block size")
	}

	mode := cipher.NewCBCDecrypter(block, rubikaZeroIV[:])
	mode.CryptBlocks(data, data)

	if len(data) == 0 {
		return nil, fmt.Errorf("empty plaintext")
	}
	padLen := int(data[len(data)-1])
	if padLen > aes.BlockSize || padLen == 0 {
		return nil, fmt.Errorf("invalid padding")
	}
	for i := len(data) - padLen; i < len(data); i++ {
		if data[i] != byte(padLen) {
			return nil, fmt.Errorf("invalid padding bytes")
		}
	}
	data = data[:len(data)-padLen]

	var result map[string]interface{}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("json unmarshal: %w", err)
	}
	return result, nil
}

// rsaSign signs data_enc with RSA PKCS1v15 + SHA256.
func rsaSign(privKey *rsa.PrivateKey, dataEnc string) (string, error) {
	if privKey == nil {
		return "", nil
	}
	hash := sha256.Sum256([]byte(dataEnc))
	sig, err := rsa.SignPKCS1v15(rand.Reader, privKey, crypto.SHA256, hash[:])
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(sig), nil
}

// --- Network: DC discovery ---

func (r *RubikaCore) getDCs() error {
	req, err := http.NewRequestWithContext(r.ctx, "GET", "https://getdcmess.iranlms.ir/", nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", r.userAgent)

	resp, err := r.httpClient.Do(req)
	if err != nil {
		// DC discovery failed (DNS blocked outside Iran) — use hardcoded fallbacks
		return r.useFallbackDCs()
	}
	defer resp.Body.Close()

	var result struct {
		Data struct {
			API           map[string]string `json:"API"`
			Socket        map[string]string `json:"socket"`
			Storage       map[string]string `json:"storage"`
			DefaultAPI    interface{}       `json:"default_api"`
			DefaultAPIs   []interface{}     `json:"default_apis"`
			DefaultSocket interface{}       `json:"default_socket"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return r.useFallbackDCs()
	}

	r.apiMap = make(map[string]string)
	for code, url := range result.Data.API {
		if url != "" {
			if !strings.HasSuffix(url, "/") {
				url += "/"
			}
			r.apiMap[code] = url
		}
	}

	// Parse storage URLs for file upload/download
	r.storageMap = make(map[string]string)
	for code, url := range result.Data.Storage {
		if url != "" {
			if !strings.HasSuffix(url, "/") {
				url += "/"
			}
			r.storageMap[code] = url
		}
	}

	// Build priority list
	r.apiPriority = nil
	for _, code := range result.Data.DefaultAPIs {
		cs := fmt.Sprintf("%v", code)
		if _, ok := r.apiMap[cs]; ok {
			r.apiPriority = append(r.apiPriority, cs)
		}
	}
	if defAPI := fmt.Sprintf("%v", result.Data.DefaultAPI); defAPI != "" {
		found := false
		for _, p := range r.apiPriority {
			if p == defAPI {
				found = true
				break
			}
		}
		if !found {
			if _, ok := r.apiMap[defAPI]; ok {
				r.apiPriority = append([]string{defAPI}, r.apiPriority...)
			}
		}
	}
	if len(r.apiPriority) == 0 {
		for code := range r.apiMap {
			r.apiPriority = append(r.apiPriority, code)
		}
	}

	if len(r.apiPriority) > 0 {
		r.apiURL = r.apiMap[r.apiPriority[0]]
	}

	// Socket URL
	defSocket := fmt.Sprintf("%v", result.Data.DefaultSocket)
	if url, ok := result.Data.Socket[defSocket]; ok {
		r.wssURL = url
	} else {
		for _, url := range result.Data.Socket {
			r.wssURL = url
			break
		}
	}

	if r.apiURL == "" || r.wssURL == "" {
		// Incomplete DC data — try fallbacks
		return r.useFallbackDCs()
	}
	return nil
}

// useFallbackDCs sets hardcoded API and WebSocket endpoints for when DC discovery
// DNS (getdcmess.iranlms.ir) is blocked outside Iran.
func (r *RubikaCore) useFallbackDCs() error {
	// Known Rubika messenger API subdomains (messenger1-10.iranlms.ir)
	fallbackAPIs := []string{
		"https://messengerg2c1.iranlms.ir/",
		"https://messengerg2c2.iranlms.ir/",
		"https://messengerg2c3.iranlms.ir/",
		"https://messengerg2c4.iranlms.ir/",
		"https://messengerg2c5.iranlms.ir/",
		"https://messengerg2c6.iranlms.ir/",
		"https://messengerg2c7.iranlms.ir/",
		"https://messengerg2c8.iranlms.ir/",
		"https://messengerg2c9.iranlms.ir/",
		"https://messengerg2c10.iranlms.ir/",
	}
	fallbackSockets := []string{
		"wss://nsocket1.iranlms.ir/",
		"wss://nsocket2.iranlms.ir/",
		"wss://nsocket3.iranlms.ir/",
		"wss://nsocket4.iranlms.ir/",
		"wss://nsocket5.iranlms.ir/",
	}
	fallbackStorages := []string{
		"https://shadow1.iranlms.ir/",
		"https://shadow2.iranlms.ir/",
		"https://shadow3.iranlms.ir/",
		"https://shadow4.iranlms.ir/",
	}

	// Try each API endpoint until one responds
	for i, url := range fallbackAPIs {
		ctx, cancel := context.WithTimeout(r.ctx, 5*time.Second)
		req, err := http.NewRequestWithContext(ctx, "HEAD", url, nil)
		if err != nil {
			cancel()
			continue
		}
		req.Header.Set("User-Agent", r.userAgent)
		resp, err := r.httpClient.Do(req)
		cancel()
		if err == nil {
			resp.Body.Close()
			r.apiURL = url
			r.apiMap = make(map[string]string)
			r.apiMap[fmt.Sprintf("%d", i+1)] = url
			r.apiPriority = []string{fmt.Sprintf("%d", i+1)}
			break
		}
	}
	if r.apiURL == "" {
		// None reachable — set first as default, will fail on actual use
		r.apiURL = fallbackAPIs[0]
		r.apiMap = map[string]string{"1": fallbackAPIs[0]}
		r.apiPriority = []string{"1"}
	}

	// Set WebSocket URL — try first available
	for _, url := range fallbackSockets {
		r.wssURL = url
		break
	}

	// Set storage URLs
	r.storageMap = make(map[string]string)
	for i, url := range fallbackStorages {
		r.storageMap[fmt.Sprintf("%d", i+1)] = url
	}

	return nil
}

// --- Network: API request ---

// api sends an authenticated API request (tmpSession=false).
func (r *RubikaCore) api(method string, input map[string]interface{}) (map[string]interface{}, error) {
	return r.apiRequest(method, input, false)
}

// apiTmp sends a temporary-session API request (tmpSession=true).
func (r *RubikaCore) apiTmp(method string, input map[string]interface{}) (map[string]interface{}, error) {
	return r.apiRequest(method, input, true)
}

// apiRequest sends an encrypted API request and returns the decrypted response data.
func (r *RubikaCore) apiRequest(method string, input map[string]interface{}, tmpSession bool) (map[string]interface{}, error) {
	if r.apiURL == "" {
		if err := r.getDCs(); err != nil {
			return nil, err
		}
	}

	payload := map[string]interface{}{
		"client": r.platform,
		"method": method,
		"input":  input,
	}

	dataEnc, err := rubikaEncrypt(payload, r.key)
	if err != nil {
		return nil, fmt.Errorf("encrypt request: %w", err)
	}

	reqBody := map[string]interface{}{
		"api_version": "6",
		"data_enc":    dataEnc,
	}

	if tmpSession {
		reqBody["tmp_session"] = r.auth
	} else {
		reqBody["auth"] = r.decodeAuth
		// Sign if we have a private key
		if r.privateKey != nil {
			sig, err := rsaSign(r.privateKey, dataEnc)
			if err != nil {
				return nil, fmt.Errorf("sign request: %w", err)
			}
			if sig != "" {
				reqBody["sign"] = sig
			}
		}
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, err
	}

	// Try API endpoints with failover
	var lastErr error
	candidates := r.candidateAPIURLs()
	for _, url := range candidates {
		result, err := r.doHTTPPost(url, bodyBytes)
		if err != nil {
			lastErr = err
			continue
		}

		// Decrypt response
		dataEncResp, ok := result["data_enc"].(string)
		if !ok {
			// Response might be unencrypted
			return result, nil
		}

		decrypted, err := rubikaDecrypt(dataEncResp, r.key)
		if err != nil {
			return nil, fmt.Errorf("decrypt response: %w", err)
		}

		status, _ := decrypted["status"].(string)
		statusDet, _ := decrypted["status_det"].(string)

		if status == "OK" && statusDet == "OK" {
			data, _ := decrypted["data"].(map[string]interface{})
			return data, nil
		}

		return nil, r.mapError(statusDet, decrypted)
	}

	if lastErr != nil {
		return nil, fmt.Errorf("all API endpoints failed: %w", lastErr)
	}
	return nil, fmt.Errorf("no API endpoints available")
}

func (r *RubikaCore) candidateAPIURLs() []string {
	urls := make([]string, 0, 1+len(r.apiPriority))
	if r.apiURL != "" {
		urls = append(urls, r.apiURL)
	}
	for _, code := range r.apiPriority {
		u := r.apiMap[code]
		dup := false
		for _, existing := range urls {
			if existing == u {
				dup = true
				break
			}
		}
		if !dup {
			urls = append(urls, u)
		}
	}
	return urls
}

func (r *RubikaCore) doHTTPPost(url string, body []byte) (map[string]interface{}, error) {
	req, err := http.NewRequestWithContext(r.ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	// Real web client sends text/plain, NOT application/json
	req.Header.Set("Content-Type", "text/plain")
	req.Header.Set("User-Agent", r.userAgent)
	req.Header.Set("Origin", "https://web.rubika.ir")
	req.Header.Set("Referer", "https://web.rubika.ir/")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")
	req.Header.Set("Connection", "keep-alive")

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		resp, err := r.httpClient.Do(req)
		if err != nil {
			lastErr = err
			time.Sleep(time.Duration(1<<attempt) * time.Second)
			req, _ = http.NewRequestWithContext(r.ctx, "POST", url, bytes.NewReader(body))
			req.Header.Set("Content-Type", "text/plain")
			req.Header.Set("User-Agent", r.userAgent)
			req.Header.Set("Origin", "https://web.rubika.ir")
			req.Header.Set("Referer", "https://web.rubika.ir/")
			req.Header.Set("Accept", "application/json, text/plain, */*")
			req.Header.Set("Accept-Language", "en-US,en;q=0.9")
			req.Header.Set("Connection", "keep-alive")
			continue
		}

		var result map[string]interface{}
		decErr := json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		if decErr != nil {
			lastErr = decErr
			continue
		}
		return result, nil
	}
	return nil, lastErr
}

func (r *RubikaCore) mapError(statusDet string, resp map[string]interface{}) error {
	switch statusDet {
	case "InvalidAuth", "NotRegistered":
		return fmt.Errorf("%w: %s", ErrAuth, statusDet)
	case "TooRequests":
		return fmt.Errorf("%w: %s", ErrRateLimit, statusDet)
	case "InvalidInput":
		return fmt.Errorf("%w: %s", ErrInvalidInput, statusDet)
	case "InvalidMethod":
		return fmt.Errorf("%w: %s", ErrNotSupported, statusDet)
	case "CodeIsUsed", "CodeIsExpired":
		return fmt.Errorf("%w: %s", ErrAuth, statusDet)
	default:
		return fmt.Errorf("rubika API error: status_det=%s resp=%v", statusDet, resp)
	}
}

// --- Bot API request (no encryption) ---

func (r *RubikaCore) botAPIRequest(method string, input map[string]interface{}) (map[string]interface{}, error) {
	url := fmt.Sprintf("https://botapi.rubika.ir/v3/%s/%s", r.botToken, method)
	if input == nil {
		input = map[string]interface{}{}
	}
	bodyBytes, err := json.Marshal(input)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(r.ctx, "POST", url, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := r.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("bot API %s: %w", method, err)
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode bot API response: %w", err)
	}

	// Check status
	status, _ := result["status"].(string)
	if status != "" && status != "OK" {
		statusDet, _ := result["status_det"].(string)
		return nil, fmt.Errorf("bot API %s: status=%s det=%s", method, status, statusDet)
	}

	// Extract data if present
	if data, ok := result["data"].(map[string]interface{}); ok {
		return data, nil
	}
	return result, nil
}

// --- Bot API methods (official docs: rubika.ir/botapi) ---

// BotGetMe retrieves bot information.
func (r *RubikaCore) BotGetMe() (RubikaBotInfo, error) {
	data, err := r.botAPIRequest("getMe", nil)
	if err != nil {
		return RubikaBotInfo{}, err
	}
	return rubikaParseFlat[RubikaBotInfo](data)
}

// BotSendMessage sends a text message with optional keypads.
func (r *RubikaCore) BotSendMessage(chatID string, text string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"text":    text,
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendMessage", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendFile sends a previously uploaded file.
func (r *RubikaCore) BotSendFile(chatID string, fileID string, text string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
	}
	if text != "" {
		input["text"] = text
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendPoll sends a poll.
func (r *RubikaCore) BotSendPoll(chatID string, question string, options []string) (string, error) {
	data, err := r.botAPIRequest("sendPoll", map[string]interface{}{
		"chat_id":  chatID,
		"question": question,
		"options":  options,
	})
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendLocation sends a location.
func (r *RubikaCore) BotSendLocation(chatID string, lat string, lon string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id":   chatID,
		"latitude":  lat,
		"longitude": lon,
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendLocation", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendContact sends a contact card.
func (r *RubikaCore) BotSendContact(chatID string, phone string, firstName string, lastName string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id":      chatID,
		"phone_number": phone,
		"first_name":   firstName,
		"last_name":    lastName,
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendContact", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotEditMessageText edits a message's text.
func (r *RubikaCore) BotEditMessageText(chatID string, msgID string, text string) error {
	_, err := r.botAPIRequest("editMessageText", map[string]interface{}{
		"chat_id":    chatID,
		"message_id": msgID,
		"text":       text,
	})
	return err
}

// BotEditMessageKeypad edits a message's inline keypad.
func (r *RubikaCore) BotEditMessageKeypad(chatID string, msgID string, inlineKeypad map[string]interface{}) error {
	_, err := r.botAPIRequest("editMessageKeypad", map[string]interface{}{
		"chat_id":        chatID,
		"message_id":     msgID,
		"inline_keypad":  inlineKeypad,
	})
	return err
}

// BotEditChatKeypad updates or removes a chat keyboard.
func (r *RubikaCore) BotEditChatKeypad(chatID string, chatKeypad map[string]interface{}, keypadType string) error {
	input := map[string]interface{}{
		"chat_id":           chatID,
		"chat_keypad_type":  keypadType, // "New" or "Remove"
	}
	if chatKeypad != nil {
		input["chat_keypad"] = chatKeypad
	}
	_, err := r.botAPIRequest("editChatKeypad", input)
	return err
}

// BotDeleteMessage deletes a message.
func (r *RubikaCore) BotDeleteMessage(chatID string, msgID string) error {
	_, err := r.botAPIRequest("deleteMessage", map[string]interface{}{
		"chat_id":    chatID,
		"message_id": msgID,
	})
	return err
}

// BotForwardMessage forwards a message.
func (r *RubikaCore) BotForwardMessage(fromChatID string, msgID string, toChatID string) (string, error) {
	data, err := r.botAPIRequest("forwardMessage", map[string]interface{}{
		"from_chat_id":        fromChatID,
		"message_id":          msgID,
		"to_chat_id":          toChatID,
		"disable_notification": false,
	})
	if err != nil {
		return "", err
	}
	newMsgID, _ := mapGetString(data, "new_message_id")
	return newMsgID, nil
}

// BotGetChat retrieves chat information.
func (r *RubikaCore) BotGetChat(chatID string) (RubikaBotChatInfo, error) {
	data, err := r.botAPIRequest("getChat", map[string]interface{}{"chat_id": chatID})
	if err != nil {
		return RubikaBotChatInfo{}, err
	}
	return rubikaParseFlat[RubikaBotChatInfo](data)
}

// BotGetUpdates polls for new updates.
func (r *RubikaCore) BotGetUpdates(offsetID string, limit int) (map[string]interface{}, error) {
	input := map[string]interface{}{}
	if offsetID != "" {
		input["offset_id"] = offsetID
	}
	if limit > 0 {
		input["limit"] = limit
	}
	return r.botAPIRequest("getUpdates", input)
}

// BotSetCommands sets bot commands.
func (r *RubikaCore) BotSetCommands(commands []map[string]string) error {
	_, err := r.botAPIRequest("setCommands", map[string]interface{}{
		"bot_commands": commands,
	})
	return err
}

// BotUpdateEndpoints sets webhook endpoints.
func (r *RubikaCore) BotUpdateEndpoints(url string, endpointType string) error {
	_, err := r.botAPIRequest("updateBotEndpoints", map[string]interface{}{
		"url":  url,
		"type": endpointType, // "ReceiveUpdate", "ReceiveInlineMessage", "ReceiveQuery", "GetSelectionItem", "SearchSelectionItems"
	})
	return err
}

// BotRequestSendFile requests a file upload URL.
func (r *RubikaCore) BotRequestSendFile(fileType string) (string, error) {
	data, err := r.botAPIRequest("requestSendFile", map[string]interface{}{
		"type": fileType, // "File", "Image", "Voice", "Video", "Music", "Gif"
	})
	if err != nil {
		return "", err
	}
	url, _ := mapGetString(data, "upload_url")
	return url, nil
}

// BotGetFile retrieves a file download URL.
func (r *RubikaCore) BotGetFile(fileID string) (string, error) {
	data, err := r.botAPIRequest("getFile", map[string]interface{}{
		"file_id": fileID,
	})
	if err != nil {
		return "", err
	}
	url, _ := mapGetString(data, "download_url")
	return url, nil
}

// BotBanChatMember bans a user from a group/channel.
func (r *RubikaCore) BotBanChatMember(chatID string, userID string) error {
	_, err := r.botAPIRequest("banChatMember", map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	})
	return err
}

// BotUnbanChatMember unbans a user from a group/channel.
func (r *RubikaCore) BotUnbanChatMember(chatID string, userID string) error {
	_, err := r.botAPIRequest("unbanChatMember", map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	})
	return err
}

// BotUploadFile uploads a file to Rubika's bot API and returns the file_id.
// Uses multipart/form-data with a "file" field.
func (r *RubikaCore) BotUploadFile(fileType string, fileName string, data []byte) (string, error) {
	uploadURL, err := r.BotRequestSendFile(fileType)
	if err != nil {
		return "", fmt.Errorf("request upload URL: %w", err)
	}

	// Build multipart form
	var buf bytes.Buffer
	boundary := fmt.Sprintf("----UniclientBoundary%d", time.Now().UnixNano())
	buf.WriteString("--" + boundary + "\r\n")
	buf.WriteString(fmt.Sprintf("Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n", fileName))
	buf.WriteString("Content-Type: application/octet-stream\r\n\r\n")
	buf.Write(data)
	buf.WriteString("\r\n--" + boundary + "--\r\n")

	req, err := http.NewRequestWithContext(r.ctx, "POST", uploadURL, &buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "multipart/form-data; boundary="+boundary)

	resp, err := r.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("upload: %w", err)
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read upload response: %w", err)
	}

	// Check for HTML error responses (upload domain may be unreachable from outside Iran)
	if len(bodyBytes) > 0 && bodyBytes[0] == '<' {
		return "", fmt.Errorf("upload endpoint returned HTML (upload domain %s may be unreachable)", uploadURL)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(bodyBytes, &result); err != nil {
		return "", fmt.Errorf("decode upload response: %w", err)
	}

	// Extract file_id from nested data
	if d, ok := result["data"].(map[string]interface{}); ok {
		if fid, ok := mapGetString(d, "file_id"); ok {
			return fid, nil
		}
	}
	fid, _ := mapGetString(result, "file_id")
	return fid, nil
}

// --- Session management ---

func (r *RubikaCore) loadSession() error {
	data, err := os.ReadFile(r.sessionPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // no session yet
		}
		return err
	}
	var sess rubikaSession
	if err := json.Unmarshal(data, &sess); err != nil {
		return err
	}
	if sess.Auth == "" {
		return nil
	}

	r.auth = sess.Auth
	r.key = passphrase(sess.Auth)
	r.decodeAuth = decodeAuthStr(sess.Auth)
	r.guid = sess.GUID
	r.phone = sess.Phone
	if sess.UserAgent != "" {
		r.userAgent = sess.UserAgent
	}

	// Parse private key
	if sess.PrivateKey != "" {
		block, _ := pem.Decode([]byte(sess.PrivateKey))
		if block != nil {
			key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
			if err == nil {
				r.privateKey = key
			}
		}
	}

	r.authed = true
	return nil
}

func (r *RubikaCore) saveSession(phone string) error {
	var privKeyPEM string
	if r.privateKey != nil {
		privBytes := x509.MarshalPKCS1PrivateKey(r.privateKey)
		privKeyPEM = string(pem.EncodeToMemory(&pem.Block{
			Type:  "RSA PRIVATE KEY",
			Bytes: privBytes,
		}))
	}

	sess := rubikaSession{
		Phone:      phone,
		Auth:       r.auth,
		GUID:       r.guid,
		UserAgent:  r.userAgent,
		PrivateKey: privKeyPEM,
	}
	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return err
	}

	dir := filepath.Dir(r.sessionPath)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	return os.WriteFile(r.sessionPath, data, 0600)
}

// --- Auth ---

// Authenticate performs bot or user authentication against the Rubika API.
func (r *RubikaCore) Authenticate(cfg AuthConfig) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if err := r.getDCs(); err != nil {
		return fmt.Errorf("get DCs: %w", err)
	}

	if cfg.Mode == AuthModeBot {
		return r.authBot(cfg.BotToken)
	}
	return r.authUser(cfg)
}

func (r *RubikaCore) authBot(token string) error {
	r.isBot = true
	r.botToken = token
	r.authed = true

	// Verify bot token
	result, err := r.botAPIRequest("getMe", nil)
	if err != nil {
		r.authed = false
		return fmt.Errorf("%w: %v", ErrAuth, err)
	}
	if result == nil {
		r.authed = false
		return fmt.Errorf("%w: empty response from getMe", ErrAuth)
	}
	return nil
}

// SendCode sends the verification code to a phone number.
// Returns the phone_code_hash needed for SignIn.
// If 2FA is required, returns an error containing "SendPassKey".
func (r *RubikaCore) SendCode(phone string, passKey string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.apiURL == "" {
		if err := r.getDCs(); err != nil {
			return "", fmt.Errorf("get DCs: %w", err)
		}
	}

	// Generate temporary auth
	r.auth = rubikaSecret(32)
	r.key = passphrase(r.auth)
	r.decodeAuth = decodeAuthStr(r.auth)

	// Register device
	r.apiTmp("registerDevice", r.buildDeviceInfo())

	// Normalize phone
	phone = normalizeRubikaPhone(phone)

	input := map[string]interface{}{
		"phone_number": phone,
		"send_type":    "SMS",
	}
	if passKey != "" {
		input["pass_key"] = passKey
	}

	result, err := r.apiTmp("sendCode", input)
	if err != nil {
		return "", err
	}

	hash, _ := mapGetString(result, "phone_code_hash")
	if hash == "" {
		return "", fmt.Errorf("no phone_code_hash in response: %v", result)
	}
	return hash, nil
}

// SignIn completes authentication with the OTP code.
func (r *RubikaCore) SignIn(phone string, otp string, phoneCodeHash string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.signInInternal(normalizeRubikaPhone(phone), otp, phoneCodeHash)
}

// signInInternal implements the exact rubpy signIn flow. Caller must hold r.mu.
func (r *RubikaCore) signInInternal(phone string, otp string, phoneCodeHash string) error {
	// Generate RSA 1024-bit keypair (same as rubpy Crypto.create_keys)
	privKey, err := rsa.GenerateKey(rand.Reader, 1024)
	if err != nil {
		return fmt.Errorf("generate RSA key: %w", err)
	}

	// rubpy: base64.b64encode(keys.publickey().export_key()).decode()
	// export_key() returns PEM format (-----BEGIN PUBLIC KEY-----\n...),
	// then the ENTIRE PEM string is base64-encoded, then decode_auth is applied.
	pubKeyDER, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	if err != nil {
		return fmt.Errorf("marshal public key: %w", err)
	}
	pubKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: pubKeyDER})
	// base64 of the full PEM string (including headers), then decode_auth
	pubKeyB64 := base64.StdEncoding.EncodeToString(pubKeyPEM)
	pubKeyEncoded := decodeAuthStr(pubKeyB64)

	signResult, err := r.apiRequestRaw("signIn", map[string]interface{}{
		"phone_code":      otp,
		"phone_number":    phone,
		"phone_code_hash": phoneCodeHash,
		"public_key":      pubKeyEncoded,
	}, true)
	if err != nil {
		return fmt.Errorf("signIn: %w", err)
	}

	// Response: {status: "OK", status_det: "OK", data: {status: "OK", auth: "...", user: {...}}}
	// Or: {status: "OK", status_det: "OK", data: {status: "CodeIsExpired"}}
	outerStatus, _ := signResult["status"].(string)
	if outerStatus != "OK" {
		return fmt.Errorf("%w: signIn outer status=%s", ErrAuth, outerStatus)
	}

	data, _ := signResult["data"].(map[string]interface{})
	if data == nil {
		return fmt.Errorf("%w: no data in signIn response", ErrAuth)
	}

	innerStatus, _ := data["status"].(string)
	if innerStatus != "" && innerStatus != "OK" {
		return fmt.Errorf("%w: signIn status=%s", ErrAuth, innerStatus)
	}

	encryptedAuth, _ := data["auth"].(string)
	if encryptedAuth == "" {
		return fmt.Errorf("%w: no auth in signIn response", ErrAuth)
	}

	authCiphertext, err := base64.StdEncoding.DecodeString(encryptedAuth)
	if err != nil {
		return fmt.Errorf("decode auth ciphertext: %w", err)
	}

	// rubpy: PKCS1_OAEP.new(key).decrypt(...) — default hash is SHA1
	authPlaintext, err := rsa.DecryptOAEP(sha1New(), rand.Reader, privKey, authCiphertext, nil)
	if err != nil {
		// Fallback to PKCS1v15
		authPlaintext, err = rsa.DecryptPKCS1v15(rand.Reader, privKey, authCiphertext)
		if err != nil {
			return fmt.Errorf("decrypt auth: %w", err)
		}
	}

	r.auth = string(authPlaintext)
	r.key = passphrase(r.auth)
	r.decodeAuth = decodeAuthStr(r.auth)
	r.privateKey = privKey

	if userData, ok := data["user"].(map[string]interface{}); ok {
		r.guid, _ = userData["user_guid"].(string)
	}

	r.phone = phone
	r.authed = true

	// Save session BEFORE registerDevice (rubpy saves then registers)
	if err := r.saveSession(phone); err != nil {
		return fmt.Errorf("save session: %w", err)
	}

	// rubpy: registerDevice(device_model=self.name) after signIn
	r.api("registerDevice", r.buildDeviceInfo())
	return nil
}

func sha1New() hash.Hash { return sha1.New() }

func normalizeRubikaPhone(phone string) string {
	phone = strings.ReplaceAll(phone, " ", "")
	phone = strings.ReplaceAll(phone, "-", "")
	phone = strings.TrimPrefix(phone, "+")
	if strings.HasPrefix(phone, "0") {
		phone = "98" + phone[1:]
	}
	return phone
}

func (r *RubikaCore) authUser(cfg AuthConfig) error {
	// Try loading existing session first
	if err := r.loadSession(); err == nil && r.authed {
		result, err := r.api("getUserInfo", map[string]interface{}{})
		if err == nil && result != nil {
			return nil // session valid
		}
		r.authed = false
	}

	// Full auth flow: SendCode → get OTP → SignIn
	if r.apiURL == "" {
		if err := r.getDCs(); err != nil {
			return fmt.Errorf("get DCs: %w", err)
		}
	}

	r.auth = rubikaSecret(32)
	r.key = passphrase(r.auth)
	r.decodeAuth = decodeAuthStr(r.auth)

	r.apiTmp("registerDevice", r.buildDeviceInfo())

	phone := normalizeRubikaPhone(cfg.Phone)

	sendCodeInput := map[string]interface{}{
		"phone_number": phone,
		"send_type":    "SMS",
	}

	sendResult, err := r.apiTmp("sendCode", sendCodeInput)
	if err != nil {
		if strings.Contains(err.Error(), "SendPassKey") {
			if cfg.Password2F == "" {
				return fmt.Errorf("%w: 2FA password required", ErrAuth)
			}
			sendCodeInput["pass_key"] = cfg.Password2F
			sendResult, err = r.apiTmp("sendCode", sendCodeInput)
			if err != nil {
				return fmt.Errorf("sendCode with passkey: %w", err)
			}
		} else {
			return fmt.Errorf("sendCode: %w", err)
		}
	}

	phoneCodeHash, _ := mapGetString(sendResult, "phone_code_hash")
	if phoneCodeHash == "" {
		return fmt.Errorf("%w: no phone_code_hash in sendCode response", ErrAuth)
	}

	// Get OTP: use provided value, or poll from file
	otp := cfg.OTP
	if otp == "" {
		otpPath := filepath.Join(filepath.Dir(r.sessionPath), "otp_code.txt")
		os.Remove(otpPath)
		fmt.Fprintf(os.Stderr, "rubika: OTP sent to %s. Write code to %s\n", phone, otpPath)

		for i := 0; i < 120; i++ {
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

	// Delegate to signInInternal (same logic as SignIn but without locking)
	return r.signInInternal(phone, otp, phoneCodeHash)
}

// apiRequestRaw returns the full decrypted response (not just data).
func (r *RubikaCore) apiRequestRaw(method string, input map[string]interface{}, tmpSession bool) (map[string]interface{}, error) {
	if r.apiURL == "" {
		if err := r.getDCs(); err != nil {
			return nil, err
		}
	}

	payload := map[string]interface{}{
		"client": r.platform,
		"method": method,
		"input":  input,
	}

	dataEnc, err := rubikaEncrypt(payload, r.key)
	if err != nil {
		return nil, err
	}

	reqBody := map[string]interface{}{
		"api_version": "6",
		"data_enc":    dataEnc,
	}
	if tmpSession {
		reqBody["tmp_session"] = r.auth
	} else {
		reqBody["auth"] = r.decodeAuth
		if r.privateKey != nil {
			sig, _ := rsaSign(r.privateKey, dataEnc)
			if sig != "" {
				reqBody["sign"] = sig
			}
		}
	}

	bodyBytes, _ := json.Marshal(reqBody)

	result, err := r.doHTTPPost(r.apiURL, bodyBytes)
	if err != nil {
		return nil, err
	}

	dataEncResp, ok := result["data_enc"].(string)
	if !ok {
		return result, nil
	}

	return rubikaDecrypt(dataEncResp, r.key)
}

func (r *RubikaCore) buildDeviceInfo() map[string]interface{} {
	return map[string]interface{}{
		"token":          "",
		"lang_code":      r.platform.LangCode,
		"token_type":     "Firebase",
		"app_version":    "PW_" + r.platform.AppVersion,
		"system_version": "Windows 10",
		"device_model":   "Chrome 102",
		"device_hash":    "21020050",
	}
}

func rubikaSecret(length int) string {
	const chars = "abcdefghijklmnopqrstuvwxyz"
	raw := make([]byte, length)
	rand.Read(raw)
	for i, b := range raw {
		raw[i] = chars[int(b)%len(chars)]
	}
	return string(raw)
}

// --- Logout ---

// Logout clears the session and disconnects from Rubika.
func (r *RubikaCore) Logout() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.wsCancel != nil {
		r.wsCancel()
	}

	// Remove session file
	if r.sessionPath != "" {
		os.Remove(r.sessionPath)
	}

	r.authed = false
	r.auth = ""
	r.key = ""
	r.decodeAuth = ""
	r.guid = ""
	r.privateKey = nil

	return nil
}

// --- Dialogs ---

// GetDialogs retrieves the user's chat list with pagination support.
func (r *RubikaCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return nil, ErrAuth
	}

	if r.isBot {
		return nil, fmt.Errorf("%w: rubika bots do not support dialog listing", ErrNotSupported)
	}

	input := map[string]interface{}{
		"start_id": nil,
	}
	if opts.Offset != "" {
		input["start_id"] = opts.Offset
	}

	data, err := r.api("getChats", input)
	if err != nil {
		return nil, err
	}

	dialogs := []Dialog{}
	if chats, ok := data["chats"].([]interface{}); ok {
		for _, c := range chats {
			chatMap, ok := c.(map[string]interface{})
			if !ok {
				continue
			}
			d := r.mapChatToDialog(chatMap)
			dialogs = append(dialogs, d)
		}
	}

	if opts.Limit > 0 && len(dialogs) > opts.Limit {
		dialogs = dialogs[:opts.Limit]
	}

	return dialogs, nil
}

func (r *RubikaCore) mapChatToDialog(chatMap map[string]interface{}) Dialog {
	guid, _ := chatMap["object_guid"].(string)
	title, _ := chatMap["title"].(string)
	if title == "" {
		title, _ = chatMap["first_name"].(string)
		if last, ok := chatMap["last_name"].(string); ok && last != "" {
			title += " " + last
		}
	}

	unread := 0
	if u, ok := chatMap["count_unseen"].(float64); ok {
		unread = int(u)
	}

	isPinned := false
	if p, ok := chatMap["is_pinned"].(bool); ok {
		isPinned = p
	}

	isMuted := false
	if m, ok := chatMap["is_mute"].(bool); ok {
		isMuted = m
	}

	chatType := r.guidToChatType(guid)

	return Dialog{
		ID:          guid,
		Type:        chatType,
		Title:       title,
		UnreadCount: unread,
		IsPinned:    isPinned,
		IsMuted:     isMuted,
		Platform:    rubikaPlatform,
	}
}

func (r *RubikaCore) guidToChatType(guid string) ChatType {
	if strings.HasPrefix(guid, "u0") || strings.HasPrefix(guid, "b0") {
		return ChatTypeDM
	}
	if strings.HasPrefix(guid, "g0") {
		return ChatTypeGroup
	}
	if strings.HasPrefix(guid, "c0") {
		return ChatTypeChannel
	}
	return ChatTypeDM
}

// CreateGroup creates a new group with the given name and initial members.
func (r *RubikaCore) CreateGroup(name string, members []string) (*Dialog, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return nil, ErrAuth
	}

	if members == nil {
		members = []string{}
	}
	// Rubika may require at least the creator's GUID in member_guids
	if len(members) == 0 && r.guid != "" {
		members = []string{r.guid}
	}
	input := map[string]interface{}{
		"title":        name,
		"member_guids": members,
	}

	data, err := r.api("addGroup", input)
	if err != nil {
		return nil, err
	}

	groupInfo, _ := data["group"].(map[string]interface{})
	guid, _ := mapGetString(groupInfo, "group_guid")
	if guid == "" {
		guid, _ = mapGetString(data, "group_guid")
	}

	return &Dialog{
		ID:       guid,
		Type:     ChatTypeGroup,
		Title:    name,
		Platform: rubikaPlatform,
	}, nil
}

// CreateChannel creates a new channel with the given name and description.
func (r *RubikaCore) CreateChannel(name string, description string) (*Dialog, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return nil, ErrAuth
	}

	input := map[string]interface{}{
		"title":       name,
		"description": description,
	}

	data, err := r.api("addChannel", input)
	if err != nil {
		return nil, err
	}

	channelInfo, _ := data["channel"].(map[string]interface{})
	guid, _ := mapGetString(channelInfo, "channel_guid")
	if guid == "" {
		guid, _ = mapGetString(data, "channel_guid")
	}

	return &Dialog{
		ID:       guid,
		Type:     ChatTypeChannel,
		Title:    name,
		Platform: rubikaPlatform,
	}, nil
}

// CreateTopic returns an error because Rubika does not support forum topics.
func (r *RubikaCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	return nil, fmt.Errorf("%w: rubika does not support forum topics", ErrNotSupported)
}

// GetFolders retrieves the user's chat folders.
func (r *RubikaCore) GetFolders() ([]Folder, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return nil, ErrAuth
	}

	input := map[string]interface{}{
		"last_state": time.Now().Unix() - 150,
	}

	data, err := r.api("getFolders", input)
	if err != nil {
		return nil, err
	}

	var folders []Folder
	if folderList, ok := data["folders"].([]interface{}); ok {
		for _, f := range folderList {
			fm, ok := f.(map[string]interface{})
			if !ok {
				continue
			}
			id, _ := mapGetString(fm, "folder_id")
			name, _ := mapGetString(fm, "name")
			var chatIDs []string
			if include, ok := fm["include_chat_types"].([]interface{}); ok {
				for _, c := range include {
					if s, ok := c.(string); ok {
						chatIDs = append(chatIDs, s)
					}
				}
			}
			folders = append(folders, Folder{
				ID:      id,
				Name:    name,
				ChatIDs: chatIDs,
			})
		}
	}

	return folders, nil
}

// CreateFolder creates a new folder with the given name and included chat IDs.
func (r *RubikaCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	info, err := r.AddFolder(name, chatIDs)
	if err != nil {
		return nil, err
	}
	return &Folder{ID: info.FolderID, Name: name}, nil
}

// --- Messages ---

// SendMessage sends a text message to the specified chat.
func (r *RubikaCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return nil, ErrAuth
	}

	if r.isBot {
		return r.botSendMessage(chatID, msg)
	}

	input := map[string]interface{}{
		"object_guid": chatID,
		"text":        msg.Text,
		"rnd":         mrand.Intn(1000000) + 1,
	}
	if msg.ReplyToID != "" {
		input["reply_to_message_id"] = msg.ReplyToID
	}

	data, err := r.api("sendMessage", input)
	if err != nil {
		return nil, err
	}

	return r.mapResponseToMessage(data, chatID), nil
}

func (r *RubikaCore) botSendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"text":    msg.Text,
	}
	if msg.ReplyToID != "" {
		input["reply_to_message_id"] = msg.ReplyToID
	}

	data, err := r.botAPIRequest("sendMessage", input)
	if err != nil {
		return nil, err
	}

	return r.mapBotResponseToMessage(data, chatID), nil
}

func (r *RubikaCore) botUploadAndSendFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	// Determine file type for bot API
	fileType := "File"
	if strings.HasPrefix(file.MimeType, "image/") {
		fileType = "Image"
	} else if strings.HasPrefix(file.MimeType, "video/") {
		fileType = "Video"
	} else if strings.HasPrefix(file.MimeType, "audio/") {
		fileType = "Music"
	}

	fileData, err := io.ReadAll(file.Reader)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	if progress != nil {
		progress(int64(len(fileData)), file.Size)
	}

	fileID, err := r.BotUploadFile(fileType, file.Name, fileData)
	if err != nil {
		return nil, err
	}

	msgID, err := r.BotSendFile(chatID, fileID, "", nil)
	if err != nil {
		return nil, err
	}

	return &Message{
		ID:        msgID,
		ChatID:    chatID,
		Timestamp: time.Now(),
		Attachments: []FileRef{{
			ID:       fileID,
			Name:     file.Name,
			MimeType: file.MimeType,
			Size:     file.Size,
		}},
		Platform: rubikaPlatform,
	}, nil
}

// GetMessages retrieves messages from a chat with pagination support.
func (r *RubikaCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return nil, ErrAuth
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}

	input := map[string]interface{}{
		"object_guid": chatID,
		"sort":        "FromMax",
		"limit":       strconv.Itoa(limit),
	}
	if opts.Offset != "" {
		input["max_id"] = opts.Offset
	} else {
		input["max_id"] = "0"
	}

	data, err := r.api("getMessages", input)
	if err != nil {
		return nil, err
	}

	messages := []Message{}
	if msgList, ok := data["messages"].([]interface{}); ok {
		for _, m := range msgList {
			mm, ok := m.(map[string]interface{})
			if !ok {
				continue
			}
			messages = append(messages, r.mapDataToMessage(mm, chatID))
		}
	}

	return messages, nil
}

// EditMessage edits the text of an existing message.
func (r *RubikaCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return nil, ErrAuth
	}

	if r.isBot {
		err := r.BotEditMessageText(chatID, msgID, text)
		if err != nil {
			return nil, err
		}
		return &Message{ID: msgID, ChatID: chatID, Text: text, Timestamp: time.Now(), Platform: rubikaPlatform}, nil
	}

	input := map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
		"text":        text,
	}

	data, err := r.api("editMessage", input)
	if err != nil {
		return nil, err
	}

	return r.mapResponseToMessage(data, chatID), nil
}

// DeleteMessage deletes a message from a chat globally.
func (r *RubikaCore) DeleteMessage(chatID string, msgID string) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return ErrAuth
	}

	if r.isBot {
		return r.BotDeleteMessage(chatID, msgID)
	}

	input := map[string]interface{}{
		"object_guid": chatID,
		"message_ids": []string{msgID},
		"type":        "Global",
	}

	_, err := r.api("deleteMessages", input)
	return err
}

// ReplyToMessage sends a message as a reply to an existing message.
func (r *RubikaCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	msg.ReplyToID = replyToMsgID
	return r.SendMessage(chatID, msg)
}

// ForwardMessage forwards a message from one chat to another.
func (r *RubikaCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return nil, ErrAuth
	}

	if r.isBot {
		newMsgID, err := r.BotForwardMessage(fromChatID, msgID, toChatID)
		if err != nil {
			return nil, err
		}
		return &Message{ID: newMsgID, ChatID: toChatID, Timestamp: time.Now(), Platform: rubikaPlatform}, nil
	}

	input := map[string]interface{}{
		"from_object_guid": fromChatID,
		"to_object_guid":   toChatID,
		"message_ids":      []string{msgID},
		"rnd":              mrand.Intn(1000000) + 1,
	}

	data, err := r.api("forwardMessages", input)
	if err != nil {
		return nil, err
	}

	return r.mapResponseToMessage(data, toChatID), nil
}

// ReactToMessage adds an emoji reaction to a message.
func (r *RubikaCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return ErrAuth
	}

	// Rubika uses reaction_id (int), not emoji string.
	// Map common emoji to IDs (this mapping may need discovery)
	reactionID := 1 // default: thumbs up
	switch emoji {
	case "👍":
		reactionID = 1
	case "❤️", "❤":
		reactionID = 2
	case "😂":
		reactionID = 3
	case "😮":
		reactionID = 4
	case "😢":
		reactionID = 5
	case "🔥":
		reactionID = 6
	}

	input := map[string]interface{}{
		"object_guid":  chatID,
		"message_id":   msgID,
		"action":       "Add",
		"reaction_id":  reactionID,
	}

	_, err := r.api("actionOnMessageReaction", input)
	return err
}

// PinMessage pins a message in a chat.
func (r *RubikaCore) PinMessage(chatID string, msgID string) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return ErrAuth
	}

	input := map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
		"action":      "Pin",
	}

	_, err := r.api("setPinMessage", input)
	return err
}

// UnpinMessage unpins a message in a chat.
func (r *RubikaCore) UnpinMessage(chatID string, msgID string) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return ErrAuth
	}

	input := map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
		"action":      "Unpin",
	}

	_, err := r.api("setPinMessage", input)
	return err
}

// --- Read State ---

// MarkAsRead marks messages in a chat as read up to the specified message ID.
func (r *RubikaCore) MarkAsRead(chatID string, upToMsgID string) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed || r.isBot {
		return ErrAuth
	}

	input := map[string]interface{}{
		"seen_list": map[string]string{
			chatID: upToMsgID,
		},
	}

	_, err := r.api("seenChats", input)
	return err
}

// GetReadState returns an error because Rubika does not expose read state.
func (r *RubikaCore) GetReadState(chatID string) (*ReadState, error) {
	return nil, fmt.Errorf("%w: rubika does not expose read state", ErrNotSupported)
}

// --- Files ---

// UploadFile uploads a file and sends it as a message in the specified chat.
func (r *RubikaCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return nil, ErrAuth
	}

	if r.isBot {
		return r.botUploadAndSendFile(chatID, file, progress)
	}

	// Read all file data (for chunked upload)
	fileData, err := io.ReadAll(file.Reader)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}
	fileSize := int64(len(fileData))

	// Step 1: requestSendFile
	mime := file.MimeType
	if idx := strings.LastIndex(file.Name, "."); idx >= 0 {
		mime = file.Name[idx+1:]
	}

	reqInput := map[string]interface{}{
		"file_name": file.Name,
		"size":      fileSize,
		"mime":      mime,
	}

	reqResult, err := r.api("requestSendFile", reqInput)
	if err != nil {
		return nil, fmt.Errorf("requestSendFile: %w", err)
	}

	fileID, _ := mapGetString(reqResult, "id")
	dcID, _ := reqResult["dc_id"]
	uploadURL, _ := mapGetString(reqResult, "upload_url")
	accessHashSend, _ := mapGetString(reqResult, "access_hash_send")

	if fileID == "" || uploadURL == "" {
		return nil, fmt.Errorf("invalid requestSendFile response")
	}

	// Step 2: Upload chunks
	chunkSize := 1048576 // 1MB
	totalParts := (int(fileSize) + chunkSize - 1) / chunkSize
	var accessHashRec string

	for i := 0; i < totalParts; i++ {
		start := i * chunkSize
		end := start + chunkSize
		if end > len(fileData) {
			end = len(fileData)
		}
		chunk := fileData[start:end]

		uploadReq, err := http.NewRequestWithContext(r.ctx, "POST", uploadURL, bytes.NewReader(chunk))
		if err != nil {
			return nil, err
		}
		uploadReq.Header.Set("auth", r.auth) // raw auth, NOT decode_auth
		uploadReq.Header.Set("file-id", fileID)
		uploadReq.Header.Set("total-part", strconv.Itoa(totalParts))
		uploadReq.Header.Set("part-number", strconv.Itoa(i+1))
		uploadReq.Header.Set("chunk-size", strconv.Itoa(len(chunk)))
		uploadReq.Header.Set("access-hash-send", accessHashSend)

		resp, err := r.httpClient.Do(uploadReq)
		if err != nil {
			return nil, fmt.Errorf("upload chunk %d: %w", i+1, err)
		}

		var uploadResult map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&uploadResult)
		resp.Body.Close()

		if status, _ := uploadResult["status"].(string); status == "ERROR_TRY_AGAIN" {
			// Restart
			reqResult, err = r.api("requestSendFile", reqInput)
			if err != nil {
				return nil, err
			}
			fileID, _ = mapGetString(reqResult, "id")
			uploadURL, _ = mapGetString(reqResult, "upload_url")
			accessHashSend, _ = mapGetString(reqResult, "access_hash_send")
			i = -1 // restart loop
			continue
		}

		if resultData, ok := uploadResult["data"].(map[string]interface{}); ok {
			if ahr, ok := resultData["access_hash_rec"].(string); ok {
				accessHashRec = ahr
			}
		}

		if progress != nil {
			progress(int64(end), fileSize)
		}
	}

	// Step 3: Send message with file_inline
	dcIDStr := "0"
	switch v := dcID.(type) {
	case float64:
		dcIDStr = strconv.Itoa(int(v))
	case string:
		dcIDStr = v
	}
	dcIDInt, _ := strconv.Atoi(dcIDStr)

	fileType := "File"
	mimeType := file.MimeType
	if strings.HasPrefix(mimeType, "image/") {
		fileType = "Image"
	} else if strings.HasPrefix(mimeType, "video/") {
		fileType = "Video"
	} else if strings.HasPrefix(mimeType, "audio/") {
		fileType = "Music"
	}

	fileInline := map[string]interface{}{
		"file_id":         fileID,
		"dc_id":           dcIDInt,
		"size":            fileSize,
		"type":            fileType,
		"mime":            mime,
		"access_hash_rec": accessHashRec,
		"file_name":       file.Name,
	}
	// Rubika requires width/height for Image/Video/Gif, time for Video/Music/Voice
	// rubpy defaults: width=200, height=200, time=1
	// For Image/Video/Gif: thumb_inline (base64 thumbnail) is required
	if fileType == "Image" || fileType == "Video" || fileType == "Gif" {
		fileInline["width"] = 200
		fileInline["height"] = 200
		thumbData := fileData
		if len(thumbData) > 40960 {
			thumbData = thumbData[:40960]
		}
		fileInline["thumb_inline"] = base64.StdEncoding.EncodeToString(thumbData)
	}
	if fileType == "Video" || fileType == "Music" || fileType == "Voice" {
		fileInline["time"] = 1
	}

	sendInput := map[string]interface{}{
		"object_guid": chatID,
		"rnd":         mrand.Intn(1000000) + 1,
		"file_inline": fileInline,
	}

	data, err := r.api("sendMessage", sendInput)
	if err != nil {
		return nil, err
	}

	return r.mapResponseToMessage(data, chatID), nil
}

// DownloadFile downloads a file by its reference and saves it to the destination path.
func (r *RubikaCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return ErrAuth
	}

	// Parse file ref: we need dc_id, file_id, access_hash_rec
	// FileRef.ID format: "dcID:fileID:accessHashRec"
	parts := strings.SplitN(fileRef.ID, ":", 3)
	if len(parts) < 3 {
		return fmt.Errorf("%w: invalid file ref format, expected dcID:fileID:accessHashRec", ErrInvalidInput)
	}
	dcID, fileID, accessHashRec := parts[0], parts[1], parts[2]

	// Use storage URL from DC discovery if available, fallback to hardcoded pattern
	downloadBase := ""
	if url, ok := r.storageMap[dcID]; ok {
		downloadBase = strings.TrimSuffix(url, "/")
	} else {
		downloadBase = fmt.Sprintf("https://messenger%s.iranlms.ir", dcID)
	}
	downloadURL := downloadBase + "/GetFile.ashx"

	chunkSize := int64(131072) // 128KB
	totalSize := fileRef.Size
	if totalSize <= 0 {
		totalSize = chunkSize // unknown size, download one chunk
	}

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()

	var downloaded int64
	for start := int64(0); start < totalSize; start += chunkSize {
		end := start + chunkSize - 1
		if end >= totalSize {
			end = totalSize - 1
		}

		req, err := http.NewRequestWithContext(r.ctx, "POST", downloadURL, nil)
		if err != nil {
			return err
		}
		req.Header.Set("auth", r.auth)
		req.Header.Set("access-hash-rec", accessHashRec)
		req.Header.Set("file-id", fileID)
		req.Header.Set("user-agent", r.userAgent)
		req.Header.Set("start-index", strconv.FormatInt(start, 10))
		req.Header.Set("last-index", strconv.FormatInt(end, 10))

		resp, err := r.httpClient.Do(req)
		if err != nil {
			return fmt.Errorf("download chunk: %w", err)
		}

		n, err := io.Copy(f, resp.Body)
		resp.Body.Close()
		if err != nil {
			return fmt.Errorf("write chunk: %w", err)
		}

		downloaded += n
		if progress != nil {
			progress(downloaded, totalSize)
		}
	}

	return nil
}

// --- Media ---

// SendImageBase64 returns an error because Rubika does not support base64 image sending.
func (r *RubikaCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	return nil, fmt.Errorf("%w: rubika does not support base64 image sending", ErrNotSupported)
}

// --- Calls ---

// StartCall creates a voice chat in the specified group or channel and joins it via WebRTC.
func (r *RubikaCore) StartCall(chatID string, video bool) (*CallSession, error) {
	r.activeCallMu.Lock()
	if r.activeCall != nil {
		r.activeCallMu.Unlock()
		return nil, fmt.Errorf("already in a voice chat (id=%s)", r.activeCall.vcID)
	}
	r.activeCallMu.Unlock()

	// 1. Create voice chat
	var resp map[string]interface{}
	var err error
	if strings.HasPrefix(chatID, "c0") {
		resp, err = r.CreateChannelVoiceChat(chatID)
	} else {
		resp, err = r.CreateGroupVoiceChat(chatID)
	}
	if err != nil {
		return nil, fmt.Errorf("create voice chat: %w", err)
	}

	// Extract voice_chat_id from response — two possible formats:
	// 1. New VC: {group_voice_chat_update: {voice_chat_id: "..."}, chat_update: {chat: {group_voice_chat_id: "..."}}}
	// 2. Existing VC: {status: "VoiceChatExist", exist_group_voice_chat: {voice_chat_id: "..."}}
	vcID := ""
	if existing, ok := resp["exist_group_voice_chat"].(map[string]interface{}); ok {
		vcID, _ = existing["voice_chat_id"].(string)
	}
	if vcID == "" {
		if update, ok := resp["group_voice_chat_update"].(map[string]interface{}); ok {
			vcID, _ = update["voice_chat_id"].(string)
		}
	}
	if vcID == "" {
		if chatUpdate, ok := resp["chat_update"].(map[string]interface{}); ok {
			if chat, ok := chatUpdate["chat"].(map[string]interface{}); ok {
				vcID, _ = chat["group_voice_chat_id"].(string)
			}
		}
	}
	if vcID == "" {
		return nil, fmt.Errorf("no voice_chat_id in create response")
	}

	return r.joinVoiceChatWebRTC(chatID, vcID)
}

// JoinGroupCall joins an existing voice chat in a group or channel via WebRTC.
func (r *RubikaCore) JoinGroupCall(chatID string) (*CallSession, error) {
	r.activeCallMu.Lock()
	if r.activeCall != nil {
		r.activeCallMu.Unlock()
		return nil, fmt.Errorf("already in a voice chat (id=%s)", r.activeCall.vcID)
	}
	r.activeCallMu.Unlock()

	// Discover active voice_chat_id from chat info
	// The voice_chat_id is in the "chat" dict (not "group"/"channel")
	var vcID string
	if strings.HasPrefix(chatID, "g0") {
		info, err := r.GetGroupInfo(chatID)
		if err == nil {
			vcID = info.GroupVoiceChatID
		}
	} else if strings.HasPrefix(chatID, "c0") {
		info, err := r.GetChannelInfo(chatID)
		if err == nil {
			vcID = info.ChannelVoiceChatID
		}
	}

	// Fallback: try getGroupVoiceChatUpdates with state=0
	if vcID == "" {
		resp, err := r.GetGroupVoiceChatUpdates(chatID, "", 0)
		if err == nil {
			if vc, ok := resp["group_voice_chat"].(map[string]interface{}); ok {
				vcID, _ = vc["voice_chat_id"].(string)
			}
		}
	}

	if vcID == "" {
		return nil, fmt.Errorf("%w: no active voice chat in this group", ErrNotFound)
	}

	return r.joinVoiceChatWebRTC(chatID, vcID)
}

// EndCall leaves and discards the active voice chat.
func (r *RubikaCore) EndCall(callID string) error {
	r.activeCallMu.Lock()
	call := r.activeCall
	r.activeCall = nil
	r.activeCallMu.Unlock()

	if call == nil {
		return fmt.Errorf("%w: no active call", ErrNotFound)
	}
	call.cancel()
	call.pc.Close()

	// Leave, then discard (creator ends the whole chat, participant just leaves)
	r.LeaveGroupVoiceChat(call.chatGUID, call.vcID)
	r.DiscardGroupVoiceChat(call.chatGUID, call.vcID)
	return nil
}

// SendAudioOpus sends a pre-encoded Opus frame to the voice chat.
// If no call is active, this is a no-op.
func (r *RubikaCore) SendAudioOpus(opusFrame []byte) {
	r.activeCallMu.Lock()
	call := r.activeCall
	r.activeCallMu.Unlock()
	if call == nil || call.audioInCh == nil {
		return
	}
	select {
	case call.audioInCh <- opusFrame:
	default: // drop if channel full
	}
}

// OnAudioReceived sets a callback for received Opus frames from the Janus mix.
// Each invocation receives one Opus frame (the raw payload from an RTP packet).
func (r *RubikaCore) OnAudioReceived(cb func(opusFrame []byte)) {
	r.activeCallMu.Lock()
	if r.activeCall != nil {
		r.activeCall.onAudioRecv = cb
	}
	r.activeCallMu.Unlock()
}

// GetCallStats returns RTP packet counts for the active call.
func (r *RubikaCore) GetCallStats() (sent, recv int64) {
	r.activeCallMu.Lock()
	call := r.activeCall
	r.activeCallMu.Unlock()
	if call == nil {
		return 0, 0
	}
	return call.rtpSent.Load(), call.rtpRecv.Load()
}

// SetCallMuted sets the mute state for the active voice chat.
func (r *RubikaCore) SetCallMuted(callID string, muted bool) error {
	r.activeCallMu.Lock()
	call := r.activeCall
	r.activeCallMu.Unlock()

	if call == nil {
		return fmt.Errorf("%w: no active call", ErrNotFound)
	}
	call.muted = muted
	return nil
}

// joinVoiceChatWebRTC creates a WebRTC PeerConnection, joins the voice chat,
// and starts background heartbeat/updates loops.
func (r *RubikaCore) joinVoiceChatWebRTC(chatGUID string, vcID string) (*CallSession, error) {
	// 1. Create PeerConnection with Opus audio
	pc, err := webrtc.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("PeerConnection: %w", err)
	}

	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{
			MimeType:    webrtc.MimeTypeOpus,
			ClockRate:   48000,
			Channels:    2,
			SDPFmtpLine: "minptime=10;useinbandfec=1",
		},
		"audio", "uniclient-rubika-audio",
	)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("audio track: %w", err)
	}

	sender, err := pc.AddTrack(audioTrack)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("add track: %w", err)
	}
	// Drain RTCP from sender
	go func() {
		b := make([]byte, 1500)
		for {
			if _, _, e := sender.Read(b); e != nil {
				return
			}
		}
	}()

	// Receive incoming audio from Janus mix, count packets and pass Opus frames to callback
	var rtpRecvCounter atomic.Int64
	var audioRecvCb func([]byte)
	var audioRecvMu sync.Mutex
	setAudioRecvCb := func(cb func([]byte)) {
		audioRecvMu.Lock()
		audioRecvCb = cb
		audioRecvMu.Unlock()
	}
	pc.OnTrack(func(track *webrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		for {
			pkt, _, err := track.ReadRTP()
			if err != nil {
				return
			}
			rtpRecvCounter.Add(1)
			audioRecvMu.Lock()
			cb := audioRecvCb
			audioRecvMu.Unlock()
			if cb != nil && len(pkt.Payload) > 0 {
				cb(pkt.Payload)
			}
		}
	})

	// 2. Create SDP offer
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create offer: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set local desc: %w", err)
	}

	// Wait for ICE gathering
	gatherDone := webrtc.GatheringCompletePromise(pc)
	select {
	case <-gatherDone:
	case <-time.After(10 * time.Second):
		pc.Close()
		return nil, fmt.Errorf("ICE gathering timeout")
	}

	localDesc := pc.LocalDescription()
	if localDesc == nil {
		pc.Close()
		return nil, fmt.Errorf("no local description")
	}

	// 3. Join voice chat with SDP offer
	joinResp, err := r.JoinVoiceChat(chatGUID, vcID, localDesc.SDP)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("join voice chat: %w", err)
	}

	sdpAnswer, _ := joinResp["sdp_answer_data"].(string)
	if sdpAnswer == "" {
		pc.Close()
		return nil, fmt.Errorf("no sdp_answer_data in join response")
	}

	// 4. Set remote description
	err = pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeAnswer,
		SDP:  sdpAnswer,
	})
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("set remote desc: %w", err)
	}

	// 5. Wait for connection
	connReady := make(chan struct{})
	var connOnce sync.Once
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		fmt.Fprintf(os.Stderr, "rubika-vc: peer state: %s\n", state)
		if state == webrtc.PeerConnectionStateConnected ||
			state == webrtc.PeerConnectionStateFailed ||
			state == webrtc.PeerConnectionStateClosed {
			connOnce.Do(func() { close(connReady) })
		}
	})

	select {
	case <-connReady:
	case <-time.After(15 * time.Second):
	}

	if pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
		pc.Close()
		return nil, fmt.Errorf("WebRTC connection failed (state=%s)", pc.ConnectionState())
	}

	// 6. Start background loops
	ctx, cancel := context.WithCancel(r.ctx)
	audioInCh := make(chan []byte, 100)
	call := &rubikaActiveCall{
		chatGUID:   chatGUID,
		vcID:       vcID,
		pc:         pc,
		audioTrack: audioTrack,
		muted:      true, // start muted
		cancel:     cancel,
		audioInCh:  audioInCh,
		session: &CallSession{
			ID:      vcID,
			ChatID:  chatGUID,
			IsGroup: true,
			State:   CallStateActive,
		},
	}
	// Wire the OnTrack counter + audio callback into the call
	r.wg.Add(1)
	go func() {
		defer r.wg.Done()
		for {
			time.Sleep(500 * time.Millisecond)
			call.rtpRecv.Store(rtpRecvCounter.Load())
			// Sync callback reference
			if call.onAudioRecv != nil {
				setAudioRecvCb(call.onAudioRecv)
			}
			if ctx.Err() != nil {
				return
			}
		}
	}()

	r.activeCallMu.Lock()
	r.activeCall = call
	r.activeCallMu.Unlock()

	r.wg.Add(3)
	go r.rubikaHeartbeatLoop(ctx, chatGUID, vcID)
	go r.rubikaUpdatesLoop(ctx, chatGUID, vcID)
	go r.rubikaSilenceSender(ctx, call)

	return call.session, nil
}

// rubikaHeartbeatLoop sends speaking activity every 1s to keep the voice chat alive.
func (r *RubikaCore) rubikaHeartbeatLoop(ctx context.Context, chatGUID, vcID string) {
	defer r.wg.Done()
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = r.SendGroupVoiceChatActivity(chatGUID, vcID, "Speaking")
		}
	}
}

// rubikaUpdatesLoop polls for voice chat updates every 3s.
func (r *RubikaCore) rubikaUpdatesLoop(ctx context.Context, chatGUID, vcID string) {
	defer r.wg.Done()
	var state int64
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			resp, err := r.GetGroupVoiceChatUpdates(chatGUID, vcID, state)
			if err != nil {
				continue
			}
			if newState, ok := resp["new_state"].(float64); ok {
				state = int64(newState)
			}
			// Update participants in session
			r.activeCallMu.Lock()
			if r.activeCall != nil && r.activeCall.vcID == vcID {
				r.activeCall.session.Participants = r.parseVoiceChatParticipants(resp)
			}
			r.activeCallMu.Unlock()
		}
	}
}

// rubikaSilenceSender sends audio frames every 20ms.
// Uses real Opus frames from audioInCh when available, falls back to silence.
func (r *RubikaCore) rubikaSilenceSender(ctx context.Context, call *rubikaActiveCall) {
	defer r.wg.Done()
	silencePayload := []byte{0xF8, 0xFF, 0xFE}
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()

	var seq uint16
	var ts uint32
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Use real audio from channel if available, else silence
			payload := silencePayload
			if !call.muted {
				select {
				case frame := <-call.audioInCh:
					if len(frame) > 0 {
						payload = frame
					}
				default:
					// No audio queued — send silence
				}
			}

			pkt := &rtp.Packet{
				Header: rtp.Header{
					Version:        2,
					PayloadType:    111, // Opus
					SequenceNumber: seq,
					Timestamp:      ts,
					SSRC:           0,
				},
				Payload: payload,
			}
			b, err := pkt.Marshal()
			if err == nil {
				if _, err := call.audioTrack.Write(b); err == nil {
					call.rtpSent.Add(1)
				}
			}
			seq++
			ts += 960 // 20ms at 48kHz
		}
	}
}

// parseVoiceChatParticipants extracts participants from a getGroupVoiceChatUpdates response.
func (r *RubikaCore) parseVoiceChatParticipants(resp map[string]interface{}) []CallParticipant {
	var participants []CallParticipant
	updates, _ := resp["group_voice_chat_participant_updates"].([]interface{})
	for _, u := range updates {
		update, ok := u.(map[string]interface{})
		if !ok {
			continue
		}
		p, ok := update["group_voice_chat_participant"].(map[string]interface{})
		if !ok {
			continue
		}
		cp := CallParticipant{}
		cp.UserID, _ = p["user_guid"].(string)
		cp.IsMuted, _ = p["is_mute"].(bool)
		participants = append(participants, cp)
	}
	return participants
}

// --- Profile ---

// GetProfile retrieves profile information for a user by their GUID.
func (r *RubikaCore) GetProfile(userID string) (*User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if !r.authed {
		return nil, ErrAuth
	}

	if r.isBot {
		info, err := r.BotGetChat(userID)
		if err != nil {
			return nil, err
		}
		return &User{
			ID:          info.ChatGUID,
			DisplayName: info.Title,
			Platform:    rubikaPlatform,
		}, nil
	}

	guid := userID
	if guid == "" || guid == "me" {
		guid = ""
	}
	info, err := r.GetUserInfo(guid)
	if err != nil {
		return nil, err
	}

	displayName := info.FirstName
	if info.LastName != "" {
		displayName += " " + info.LastName
	}

	return &User{
		ID:          info.UserGUID,
		Username:    info.Username,
		DisplayName: displayName,
		Phone:       info.Phone,
		Platform:    rubikaPlatform,
	}, nil
}

// --- Real-time ---

// OnUpdate registers a handler for real-time update events.
func (r *RubikaCore) OnUpdate(handler func(Update)) {
	r.updateMu.Lock()
	defer r.updateMu.Unlock()
	r.updateHandlers = append(r.updateHandlers, handler)
}

// RawAPI exposes the encrypted API for debugging/testing.
func (r *RubikaCore) RawAPI(method string, input map[string]interface{}) (map[string]interface{}, error) {
	return r.api(method, input)
}

// GetGUID returns the authenticated user's GUID.
func (r *RubikaCore) GetGUID() string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.guid
}

// Close shuts down the Rubika core, ending active calls and saving the session.
func (r *RubikaCore) Close() error {
	// Clean up active call
	r.activeCallMu.Lock()
	if r.activeCall != nil {
		r.activeCall.cancel()
		r.activeCall.pc.Close()
		r.activeCall = nil
	}
	r.activeCallMu.Unlock()

	r.cancel()
	if r.wsCancel != nil {
		r.wsCancel()
	}
	if r.wsConn != nil {
		r.wsConn.Close(websocket.StatusNormalClosure, "closing")
	}
	r.wg.Wait()
	r.mu.Lock()
	if r.sessionPath != "" {
		r.saveSession(r.phone)
	}
	r.authed = false
	r.mu.Unlock()
	return nil
}

// StartWebSocket connects to the Rubika WebSocket for real-time updates.
func (r *RubikaCore) StartWebSocket() error {
	if r.wssURL == "" {
		if err := r.getDCs(); err != nil {
			return err
		}
	}

	r.wg.Add(1)
	go r.wsLoop()
	return nil
}

func (r *RubikaCore) wsLoop() {
	defer r.wg.Done()
	backoff := 3 * time.Second
	const maxBackoff = 60 * time.Second
	const maxRetries = 10
	retries := 0
	for {
		select {
		case <-r.ctx.Done():
			return
		default:
		}

		err := r.wsConnect()
		if err != nil {
			if r.ctx.Err() != nil {
				return
			}
			retries++
			if retries == 1 {
				r.fireConnState("disconnected")
			}
			if retries > maxRetries {
				r.fireConnState("disconnected")
				return
			}
			r.fireConnState("reconnecting")
			time.Sleep(backoff)
			backoff *= 2
			if backoff > maxBackoff {
				backoff = maxBackoff
			}
			continue
		}
		// Connected successfully — reset backoff
		backoff = 3 * time.Second
		retries = 0
		r.fireConnState("connected")
	}
}

func (r *RubikaCore) fireConnState(state string) {
	r.updateMu.RLock()
	handlers := make([]func(Update), len(r.updateHandlers))
	copy(handlers, r.updateHandlers)
	r.updateMu.RUnlock()
	u := Update{Type: UpdateConnectivity, ConnState: state, Platform: rubikaPlatform}
	for _, h := range handlers {
		go h(u)
	}
}

func (r *RubikaCore) wsConnect() error {
	wsCtx, wsCancel := context.WithCancel(r.ctx)
	r.wsCtx = wsCtx
	r.wsCancel = wsCancel

	conn, _, err := websocket.Dial(wsCtx, r.wssURL, &websocket.DialOptions{
		HTTPHeader: http.Header{
			"User-Agent": []string{r.userAgent},
			"Origin":     []string{"https://web.rubika.ir"},
		},
	})
	if err != nil {
		wsCancel()
		return fmt.Errorf("ws dial: %w", err)
	}
	r.wsConn = conn

	// Send handshake
	handshake := map[string]interface{}{
		"method":      "handShake",
		"auth":        r.auth,
		"api_version": "6",
		"data":        "",
	}
	hsBytes, _ := json.Marshal(handshake)
	if err := conn.Write(wsCtx, websocket.MessageText, hsBytes); err != nil {
		wsCancel()
		return fmt.Errorf("ws handshake: %w", err)
	}

	// Start keepalive
	go r.wsKeepAlive(wsCtx, conn)

	// Read loop
	for {
		select {
		case <-wsCtx.Done():
			return nil
		default:
		}

		_, data, err := conn.Read(wsCtx)
		if err != nil {
			return fmt.Errorf("ws read: %w", err)
		}

		go r.handleWSMessage(data)
	}
}

func (r *RubikaCore) wsKeepAlive(ctx context.Context, conn *websocket.Conn) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			conn.Write(ctx, websocket.MessageText, []byte("{}"))
		}
	}
}

func (r *RubikaCore) handleWSMessage(data []byte) {
	var msg map[string]interface{}
	if err := json.Unmarshal(data, &msg); err != nil {
		return
	}

	dataEnc, ok := msg["data_enc"].(string)
	if !ok || dataEnc == "" {
		return
	}

	decrypted, err := rubikaDecrypt(dataEnc, r.key)
	if err != nil {
		return
	}

	r.updateMu.RLock()
	hasUpdateHandlers := len(r.updateHandlers) > 0
	var handlers []func(Update)
	if hasUpdateHandlers {
		handlers = make([]func(Update), len(r.updateHandlers))
		copy(handlers, r.updateHandlers)
	}
	r.updateMu.RUnlock()

	if messages, ok := decrypted["message"].([]interface{}); ok && hasUpdateHandlers {
		for _, m := range messages {
			mm, ok := m.(map[string]interface{})
			if !ok {
				continue
			}

			chatID, _ := mm["object_guid"].(string)
			parsedMsg := r.mapDataToMessage(mm, chatID)

			update := Update{
				Type:     UpdateNewMessage,
				ChatID:   chatID,
				Message:  &parsedMsg,
				Platform: rubikaPlatform,
			}

			for _, h := range handlers {
				h(update)
			}
		}
	}

	if chats, ok := decrypted["chat"].([]interface{}); ok {
		if hasUpdateHandlers {
			for _, c := range chats {
				cm, ok := c.(map[string]interface{})
				if !ok {
					continue
				}
				chatID, _ := cm["object_guid"].(string)
				update := Update{
					Type:     UpdateReadState,
					ChatID:   chatID,
					Platform: rubikaPlatform,
				}
				for _, h := range handlers {
					h(update)
				}
			}
		}

		r.updateMu.RLock()
		hasChatHandlers := len(r.chatUpdateHandlers) > 0
		var chatHandlers []func(map[string]interface{})
		if hasChatHandlers {
			chatHandlers = make([]func(map[string]interface{}), len(r.chatUpdateHandlers))
			copy(chatHandlers, r.chatUpdateHandlers)
		}
		r.updateMu.RUnlock()
		if hasChatHandlers {
			for _, c := range chats {
				if cm, ok := c.(map[string]interface{}); ok {
					for _, h := range chatHandlers {
						h(cm)
					}
				}
			}
		}
	}

	if activities, ok := decrypted["show_activity"].([]interface{}); ok {
		r.updateMu.RLock()
		hasActHandlers := len(r.activityHandlers) > 0
		var actHandlers []func(map[string]interface{})
		if hasActHandlers {
			actHandlers = make([]func(map[string]interface{}), len(r.activityHandlers))
			copy(actHandlers, r.activityHandlers)
		}
		r.updateMu.RUnlock()
		if hasActHandlers {
			for _, a := range activities {
				if am, ok := a.(map[string]interface{}); ok {
					for _, h := range actHandlers {
						h(am)
					}
				}
			}
		}
	}

	if notifs, ok := decrypted["show_notification"].([]interface{}); ok {
		r.updateMu.RLock()
		hasNotifHandlers := len(r.notificationHandlers) > 0
		var notifHandlers []func(map[string]interface{})
		if hasNotifHandlers {
			notifHandlers = make([]func(map[string]interface{}), len(r.notificationHandlers))
			copy(notifHandlers, r.notificationHandlers)
		}
		r.updateMu.RUnlock()
		if hasNotifHandlers {
			for _, n := range notifs {
				if nm, ok := n.(map[string]interface{}); ok {
					for _, h := range notifHandlers {
						h(nm)
					}
				}
			}
		}
	}

	if removeNotifs, ok := decrypted["remove_notification"].([]interface{}); ok {
		r.updateMu.RLock()
		hasRmHandlers := len(r.removeNotifHandlers) > 0
		var rmHandlers []func(map[string]interface{})
		if hasRmHandlers {
			rmHandlers = make([]func(map[string]interface{}), len(r.removeNotifHandlers))
			copy(rmHandlers, r.removeNotifHandlers)
		}
		r.updateMu.RUnlock()
		if hasRmHandlers {
			for _, rn := range removeNotifs {
				if rnm, ok := rn.(map[string]interface{}); ok {
					for _, h := range rmHandlers {
						h(rnm)
					}
				}
			}
		}
	}
}

// --- Message mapping helpers ---

func (r *RubikaCore) mapResponseToMessage(data map[string]interface{}, chatID string) *Message {
	if data == nil {
		return &Message{ChatID: chatID, Platform: rubikaPlatform, Timestamp: time.Now(), Status: MessageStatusSent}
	}

	// Response structure: {message_update: {message_id, message: {...}}, chat_update: {...}}
	// or for forward: {message_updates: [{message_id, message: {...}}]}
	msgID := ""
	text := ""
	authorGUID := ""
	ts := time.Now()

	// Try message_update (single message ops: send, edit)
	if mu, ok := data["message_update"].(map[string]interface{}); ok {
		msgID, _ = mapGetString(mu, "message_id")
		if msg, ok := mu["message"].(map[string]interface{}); ok {
			text, _ = mapGetString(msg, "text")
			authorGUID, _ = mapGetString(msg, "author_object_guid")
			if t, ok := msg["time"].(string); ok {
				if ts2, err := strconv.ParseInt(t, 10, 64); err == nil {
					ts = time.Unix(ts2, 0)
				}
			}
		}
	}

	// Try message_updates (forward returns array)
	if mus, ok := data["message_updates"].([]interface{}); ok && len(mus) > 0 {
		if mu, ok := mus[0].(map[string]interface{}); ok {
			msgID, _ = mapGetString(mu, "message_id")
			if msg, ok := mu["message"].(map[string]interface{}); ok {
				text, _ = mapGetString(msg, "text")
				authorGUID, _ = mapGetString(msg, "author_object_guid")
			}
		}
	}

	// Fallback to flat fields
	if msgID == "" {
		msgID, _ = mapGetString(data, "message_id")
	}
	if text == "" {
		text, _ = mapGetString(data, "text")
	}

	return &Message{
		ID:        msgID,
		ChatID:    chatID,
		SenderID:  authorGUID,
		Text:      text,
		Timestamp: ts,
		Status:    MessageStatusSent,
		Platform:  rubikaPlatform,
	}
}

func (r *RubikaCore) mapDataToMessage(mm map[string]interface{}, chatID string) Message {
	msgID, _ := mapGetString(mm, "message_id")
	text, _ := mapGetString(mm, "text")
	authorGUID, _ := mapGetString(mm, "author_guid")
	authorName, _ := mapGetString(mm, "author_name")

	ts := time.Now()
	if t, ok := mm["time"].(float64); ok {
		ts = time.Unix(int64(t), 0)
	}

	replyToID := ""
	if r, ok := mm["reply_to_message_id"].(string); ok {
		replyToID = r
	}

	forwardFrom := ""
	if fwd, ok := mm["forwarded_from"].(map[string]interface{}); ok {
		forwardFrom, _ = fwd["type_from"].(string)
	}

	// Parse file attachments
	var attachments []FileRef
	if fi, ok := mm["file_inline"].(map[string]interface{}); ok {
		fID, _ := mapGetString(fi, "file_id")
		fName, _ := mapGetString(fi, "file_name")
		fMime, _ := mapGetString(fi, "mime")
		fSize := int64(0)
		if s, ok := fi["size"].(float64); ok {
			fSize = int64(s)
		}
		dcID := "0"
		if d, ok := fi["dc_id"].(float64); ok {
			dcID = strconv.Itoa(int(d))
		}
		accessHash, _ := mapGetString(fi, "access_hash_rec")
		thumbB64, _ := mapGetString(fi, "thumb_inline")

		// Compose file ref ID as dcID:fileID:accessHashRec for download
		refID := fmt.Sprintf("%s:%s:%s", dcID, fID, accessHash)

		attachments = append(attachments, FileRef{
			ID:       refID,
			Name:     fName,
			MimeType: fMime,
			Size:     fSize,
			ThumbB64: thumbB64,
		})
	}

	return Message{
		ID:          msgID,
		ChatID:      chatID,
		SenderID:    authorGUID,
		SenderName:  authorName,
		Text:        text,
		Timestamp:   ts,
		ReplyToID:   replyToID,
		ForwardFrom: forwardFrom,
		Attachments: attachments,
		Status:      MessageStatusSent,
		Platform:    rubikaPlatform,
	}
}

func (r *RubikaCore) mapBotResponseToMessage(data map[string]interface{}, chatID string) *Message {
	if data == nil {
		return &Message{ChatID: chatID, Platform: rubikaPlatform, Timestamp: time.Now(), Status: MessageStatusSent}
	}

	result, _ := data["result"].(map[string]interface{})
	if result == nil {
		result = data
	}

	msgID := ""
	if id, ok := result["message_id"].(float64); ok {
		msgID = strconv.FormatInt(int64(id), 10)
	} else if id, ok := result["message_id"].(string); ok {
		msgID = id
	}

	text, _ := mapGetString(result, "text")

	return &Message{
		ID:        msgID,
		ChatID:    chatID,
		Text:      text,
		Timestamp: time.Now(),
		Status:    MessageStatusSent,
		Platform:  rubikaPlatform,
	}
}

// --- Rubika-specific methods (beyond Core interface) ---

// GetGroupInfo retrieves information about a group.
func (r *RubikaCore) GetGroupInfo(groupGUID string) (RubikaGroupInfo, error) {
	data, err := r.api("getGroupInfo", map[string]interface{}{"group_guid": groupGUID})
	if err != nil {
		return RubikaGroupInfo{}, err
	}
	return rubikaParseData[RubikaGroupInfo](data, "group")
}

// GetChannelInfo retrieves information about a channel.
func (r *RubikaCore) GetChannelInfo(channelGUID string) (RubikaChannelInfo, error) {
	data, err := r.api("getChannelInfo", map[string]interface{}{"channel_guid": channelGUID})
	if err != nil {
		return RubikaChannelInfo{}, err
	}
	return rubikaParseData[RubikaChannelInfo](data, "channel")
}

// GetObjectByUsername resolves a username to its object info.
func (r *RubikaCore) GetObjectByUsername(username string) (map[string]interface{}, error) {
	return r.api("getObjectByUsername", map[string]interface{}{
		"username": username,
	})
}

// searchGlobalObjects searches for objects globally.
func (r *RubikaCore) searchGlobalObjects(searchText string) (map[string]interface{}, error) {
	return r.api("searchGlobalObjects", map[string]interface{}{
		"search_text": searchText,
	})
}

// searchChatMessages searches messages within a chat.
func (r *RubikaCore) searchChatMessages(chatID string, searchText string) (map[string]interface{}, error) {
	return r.api("searchChatMessages", map[string]interface{}{
		"object_guid": chatID,
		"search_text": searchText,
		"type":        "Text",
	})
}

// SendChatActivity sends typing/recording indicator.
func (r *RubikaCore) SendChatActivity(chatID string, activity string) error {
	_, err := r.api("sendChatActivity", map[string]interface{}{
		"object_guid": chatID,
		"activity":    activity, // "Typing", "Recording", "Uploading"
	})
	return err
}

// getContactsRaw retrieves user's contacts (raw API response).
func (r *RubikaCore) getContactsRaw() (map[string]interface{}, error) {
	return r.api("getContacts", map[string]interface{}{})
}

// getMySessions retrieves active sessions.
func (r *RubikaCore) getMySessions() (map[string]interface{}, error) {
	return r.api("getMySessions", map[string]interface{}{})
}

// TerminateSession terminates a specific session.
func (r *RubikaCore) TerminateSession(sessionKey string) error {
	_, err := r.api("terminateSession", map[string]interface{}{
		"session_key": sessionKey,
	})
	return err
}

// createPollRaw creates a poll in a chat (raw API response).
func (r *RubikaCore) createPollRaw(chatID string, question string, options []string) (map[string]interface{}, error) {
	return r.api("createPoll", map[string]interface{}{
		"object_guid":             chatID,
		"question":                question,
		"options":                 options,
		"type":                    "Regular",
		"is_anonymous":            true,
		"allows_multiple_answers": false,
		"rnd":                     mrand.Intn(1000000) + 1,
	})
}

// votePollRaw votes in a poll (raw API response).
func (r *RubikaCore) votePollRaw(pollID string, optionIndex int) (map[string]interface{}, error) {
	return r.api("votePoll", map[string]interface{}{
		"poll_id":      pollID,
		"option_index": optionIndex,
	})
}

// GetGroupAllMembers retrieves all members of a group.
func (r *RubikaCore) GetGroupAllMembers(groupGUID string) (RubikaMemberList, error) {
	data, err := r.api("getGroupAllMembers", map[string]interface{}{"group_guid": groupGUID, "start_id": nil})
	if err != nil {
		return RubikaMemberList{}, err
	}
	return rubikaParseFlat[RubikaMemberList](data)
}

// GetChannelAllMembers retrieves all members of a channel.
func (r *RubikaCore) GetChannelAllMembers(channelGUID string) (RubikaMemberList, error) {
	data, err := r.api("getChannelAllMembers", map[string]interface{}{"channel_guid": channelGUID, "start_id": nil})
	if err != nil {
		return RubikaMemberList{}, err
	}
	return rubikaParseFlat[RubikaMemberList](data)
}

// SetGroupAdmin sets or removes admin for a group member.
func (r *RubikaCore) SetGroupAdmin(groupGUID string, memberGUID string, accessList []string) error {
	_, err := r.api("setGroupAdmin", map[string]interface{}{
		"group_guid":  groupGUID,
		"member_guid": memberGUID,
		"access_list": accessList,
		"action":      "SetAdmin",
	})
	return err
}

// BanGroupMember bans or unbans a member from a group.
func (r *RubikaCore) BanGroupMember(groupGUID string, memberGUID string, ban bool) error {
	action := "Set"
	if !ban {
		action = "Unset"
	}
	_, err := r.api("banGroupMember", map[string]interface{}{
		"group_guid":  groupGUID,
		"member_guid": memberGUID,
		"action":      action,
	})
	return err
}

// JoinGroup joins a group by GUID.
func (r *RubikaCore) JoinGroup(groupGUID string) error {
	_, err := r.api("joinGroup", map[string]interface{}{
		"group_guid": groupGUID,
	})
	return err
}

// LeaveGroup leaves a group.
func (r *RubikaCore) LeaveGroup(groupGUID string) error {
	_, err := r.api("leaveGroup", map[string]interface{}{
		"group_guid": groupGUID,
	})
	return err
}

// JoinChannelAction joins a channel.
func (r *RubikaCore) JoinChannelAction(channelGUID string, action string) error {
	_, err := r.api("joinChannelAction", map[string]interface{}{
		"channel_guid": channelGUID,
		"action":       action, // "Join" or "Leave"
	})
	return err
}

// GetAvatars retrieves avatars for an object.
func (r *RubikaCore) GetAvatars(objectGUID string) (RubikaAvatarList, error) {
	data, err := r.api("getAvatars", map[string]interface{}{"object_guid": objectGUID})
	if err != nil {
		return RubikaAvatarList{}, err
	}
	return rubikaParseFlat[RubikaAvatarList](data)
}

// DeleteAvatar deletes an avatar.
func (r *RubikaCore) DeleteAvatar(objectGUID string, avatarID string) error {
	_, err := r.api("deleteAvatar", map[string]interface{}{
		"object_guid": objectGUID,
		"avatar_id":   avatarID,
	})
	return err
}

// GetMyGifSet retrieves the user's saved GIFs.
func (r *RubikaCore) GetMyGifSet() (map[string]interface{}, error) {
	return r.api("getMyGifSet", map[string]interface{}{})
}

// GetMyStickerSets retrieves the user's sticker sets.
func (r *RubikaCore) GetMyStickerSets() (map[string]interface{}, error) {
	return r.api("getMyStickerSets", map[string]interface{}{})
}

// GetBlockedUsers retrieves the list of blocked users.
func (r *RubikaCore) getBlockedUsersRaw() (map[string]interface{}, error) {
	return r.api("getBlockedUsers", map[string]interface{}{})
}

// SetBlockUser blocks or unblocks a user.
func (r *RubikaCore) SetBlockUser(userGUID string, block bool) error {
	action := "Block"
	if !block {
		action = "Unblock"
	}
	_, err := r.api("setBlockUser", map[string]interface{}{
		"user_guid": userGUID,
		"action":    action,
	})
	return err
}

// --- Messages (extended) ---

// GetMessagesByID retrieves specific messages by their IDs.
func (r *RubikaCore) GetMessagesByID(chatID string, messageIDs []string) (map[string]interface{}, error) {
	return r.api("getMessagesByID", map[string]interface{}{
		"object_guid":  chatID,
		"message_ids":  messageIDs,
	})
}

// GetMessagesInterval retrieves messages around a specific message.
func (r *RubikaCore) GetMessagesInterval(chatID string, middleMsgID string) (map[string]interface{}, error) {
	return r.api("getMessagesInterval", map[string]interface{}{
		"object_guid":       chatID,
		"middle_message_id": middleMsgID,
	})
}

// GetMessagesUpdates retrieves message updates since a state.
func (r *RubikaCore) GetMessagesUpdates(chatID string, state int64) (map[string]interface{}, error) {
	if state == 0 {
		state = time.Now().Unix() - 150
	}
	return r.api("getMessagesUpdates", map[string]interface{}{
		"object_guid": chatID,
		"state":       state,
	})
}

// GetChatsUpdates retrieves chat list updates since a state.
func (r *RubikaCore) GetChatsUpdates(state int64) (map[string]interface{}, error) {
	if state == 0 {
		state = time.Now().Unix() - 150
	}
	return r.api("getChatsUpdates", map[string]interface{}{
		"state": state,
	})
}

// GetMessageReactions retrieves reactions for a message.
func (r *RubikaCore) GetMessageReactions(chatID string, msgID string) (map[string]interface{}, error) {
	return r.api("getMessageReactions", map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
	})
}

// RemoveReaction removes a reaction from a message.
func (r *RubikaCore) RemoveReaction(chatID string, msgID string, reactionID int) error {
	_, err := r.api("actionOnMessageReaction", map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
		"action":      "Remove",
		"reaction_id": reactionID,
	})
	return err
}

// GetMessageShareURL gets a share URL for a message.
func (r *RubikaCore) GetMessageShareURL(chatID string, msgID string) (map[string]interface{}, error) {
	return r.api("getMessageShareUrl", map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
	})
}

// GetPollStatus retrieves poll status.
func (r *RubikaCore) GetPollStatus(pollID string) (map[string]interface{}, error) {
	return r.api("getPollStatus", map[string]interface{}{
		"poll_id": pollID,
	})
}

// GetPollOptionVoters retrieves voters for a poll option.
func (r *RubikaCore) GetPollOptionVoters(pollID string, selectionIndex int, startID string) (map[string]interface{}, error) {
	return r.api("getPollOptionVoters", map[string]interface{}{
		"poll_id":         pollID,
		"selection_index": selectionIndex,
		"start_id":        startID,
	})
}

// DeleteChatHistory deletes chat history up to a message.
func (r *RubikaCore) DeleteChatHistory(chatID string, lastMessageID string) error {
	_, err := r.api("deleteChatHistory", map[string]interface{}{
		"object_guid":     chatID,
		"last_message_id": lastMessageID,
	})
	return err
}

// SetActionChat mutes/unmutes a chat.
func (r *RubikaCore) SetActionChat(chatID string, action string) error {
	_, err := r.api("setActionChat", map[string]interface{}{
		"object_guid": chatID,
		"action":      action, // "Mute" or "Unmute"
	})
	return err
}

// GetAbsObjects resolves multiple GUIDs to their info.
func (r *RubikaCore) GetAbsObjects(guids []string) (map[string]interface{}, error) {
	return r.api("getAbsObjects", map[string]interface{}{
		"objects_guids": guids,
	})
}

// GetLinkFromAppUrl resolves a Rubika app URL.
func (r *RubikaCore) GetLinkFromAppUrl(appURL string) (map[string]interface{}, error) {
	return r.api("getLinkFromAppUrl", map[string]interface{}{
		"app_url": appURL,
	})
}

// --- Groups (extended) ---

// AddGroupMembers adds members to a group.
func (r *RubikaCore) AddGroupMembers(groupGUID string, memberGUIDs []string) error {
	_, err := r.api("addGroupMembers", map[string]interface{}{
		"group_guid":   groupGUID,
		"member_guids": memberGUIDs,
	})
	return err
}

// EditGroupInfo edits group information.
func (r *RubikaCore) EditGroupInfo(groupGUID string, updates map[string]interface{}) error {
	input := map[string]interface{}{
		"group_guid": groupGUID,
	}
	var updatedParams []string
	for k, v := range updates {
		input[k] = v
		updatedParams = append(updatedParams, k)
	}
	input["updated_parameters"] = updatedParams
	_, err := r.api("editGroupInfo", input)
	return err
}

// GetGroupLink retrieves a group's invite link.
func (r *RubikaCore) GetGroupLink(groupGUID string) (RubikaLinkInfo, error) {
	data, err := r.api("getGroupLink", map[string]interface{}{"group_guid": groupGUID})
	if err != nil {
		return RubikaLinkInfo{}, err
	}
	return rubikaParseFlat[RubikaLinkInfo](data)
}

// SetGroupLink resets a group's invite link.
func (r *RubikaCore) SetGroupLink(groupGUID string) (RubikaLinkInfo, error) {
	data, err := r.api("setGroupLink", map[string]interface{}{"group_guid": groupGUID})
	if err != nil {
		return RubikaLinkInfo{}, err
	}
	return rubikaParseFlat[RubikaLinkInfo](data)
}

// GetGroupAdminMembers retrieves group admin members.
func (r *RubikaCore) GetGroupAdminMembers(groupGUID string, startID string) (RubikaMemberList, error) {
	input := map[string]interface{}{"group_guid": groupGUID}
	if startID != "" {
		input["start_id"] = startID
	}
	data, err := r.api("getGroupAdminMembers", input)
	if err != nil {
		return RubikaMemberList{}, err
	}
	return rubikaParseFlat[RubikaMemberList](data)
}

// GetGroupAdminAccessList retrieves admin access list for a member.
func (r *RubikaCore) GetGroupAdminAccessList(groupGUID string, memberGUID string) ([]string, error) {
	data, err := r.api("getGroupAdminAccessList", map[string]interface{}{
		"group_guid":  groupGUID,
		"member_guid": memberGUID,
	})
	if err != nil {
		return nil, err
	}
	if list, ok := data["access_list"].([]interface{}); ok {
		result := make([]string, 0, len(list))
		for _, v := range list {
			if s, ok := v.(string); ok {
				result = append(result, s)
			}
		}
		return result, nil
	}
	return []string{}, nil
}

// GetBannedGroupMembers retrieves banned group members.
func (r *RubikaCore) GetBannedGroupMembers(groupGUID string, startID string) (RubikaMemberList, error) {
	input := map[string]interface{}{"group_guid": groupGUID}
	if startID != "" {
		input["start_id"] = startID
	}
	data, err := r.api("getBannedGroupMembers", input)
	if err != nil {
		return RubikaMemberList{}, err
	}
	return rubikaParseFlat[RubikaMemberList](data)
}

// GetGroupDefaultAccess retrieves default member permissions.
func (r *RubikaCore) GetGroupDefaultAccess(groupGUID string) ([]string, error) {
	data, err := r.api("getGroupDefaultAccess", map[string]interface{}{"group_guid": groupGUID})
	if err != nil {
		return nil, err
	}
	if list, ok := data["access_list"].([]interface{}); ok {
		result := make([]string, 0, len(list))
		for _, v := range list {
			if s, ok := v.(string); ok {
				result = append(result, s)
			}
		}
		return result, nil
	}
	return []string{}, nil
}

// SetGroupDefaultAccess sets default member permissions.
func (r *RubikaCore) SetGroupDefaultAccess(groupGUID string, accessList []string) error {
	_, err := r.api("setGroupDefaultAccess", map[string]interface{}{
		"group_guid":  groupGUID,
		"access_list": accessList,
	})
	return err
}

// GetGroupMentionList retrieves mentionable members.
func (r *RubikaCore) GetGroupMentionList(groupGUID string, searchText string) (map[string]interface{}, error) {
	input := map[string]interface{}{"group_guid": groupGUID}
	if searchText != "" {
		input["search_mention"] = searchText
	}
	return r.api("getGroupMentionList", input)
}

// GetGroupOnlineCount retrieves online member count.
func (r *RubikaCore) GetGroupOnlineCount(groupGUID string) (int, error) {
	data, err := r.api("getGroupOnlineCount", map[string]interface{}{"group_guid": groupGUID})
	if err != nil {
		return 0, err
	}
	if count, ok := data["online_count"].(float64); ok {
		return int(count), nil
	}
	return 0, nil
}

// RemoveGroup removes/deletes a group.
func (r *RubikaCore) RemoveGroup(groupGUID string) error {
	_, err := r.api("removeGroup", map[string]interface{}{
		"group_guid": groupGUID,
	})
	return err
}

// DeleteNoAccessGroupChat deletes a group chat from the list when you don't have access.
func (r *RubikaCore) DeleteNoAccessGroupChat(groupGUID string) error {
	_, err := r.api("deleteNoAccessGroupChat", map[string]interface{}{
		"group_guid": groupGUID,
	})
	return err
}

// GroupPreviewByJoinLink previews a group by its invite link hash.
func (r *RubikaCore) GroupPreviewByJoinLink(hashLink string) (map[string]interface{}, error) {
	return r.api("groupPreviewByJoinLink", map[string]interface{}{
		"hash_link": hashLink,
	})
}

// --- Channels (extended) ---

// AddChannelMembers adds members to a channel.
func (r *RubikaCore) AddChannelMembers(channelGUID string, memberGUIDs []string) error {
	_, err := r.api("addChannelMembers", map[string]interface{}{
		"channel_guid": channelGUID,
		"member_guids": memberGUIDs,
	})
	return err
}

// BanChannelMember bans or unbans a channel member.
func (r *RubikaCore) BanChannelMember(channelGUID string, memberGUID string, ban bool) error {
	action := "Set"
	if !ban {
		action = "Unset"
	}
	_, err := r.api("banChannelMember", map[string]interface{}{
		"channel_guid": channelGUID,
		"member_guid":  memberGUID,
		"action":       action,
	})
	return err
}

// EditChannelInfo edits channel information.
func (r *RubikaCore) EditChannelInfo(channelGUID string, updates map[string]interface{}) error {
	input := map[string]interface{}{
		"channel_guid": channelGUID,
	}
	var updatedParams []string
	for k, v := range updates {
		input[k] = v
		updatedParams = append(updatedParams, k)
	}
	input["updated_parameters"] = updatedParams
	_, err := r.api("editChannelInfo", input)
	return err
}

// GetChannelLink retrieves a channel's invite link.
func (r *RubikaCore) GetChannelLink(channelGUID string) (RubikaLinkInfo, error) {
	data, err := r.api("getChannelLink", map[string]interface{}{"channel_guid": channelGUID})
	if err != nil {
		return RubikaLinkInfo{}, err
	}
	return rubikaParseFlat[RubikaLinkInfo](data)
}

// SetChannelLink resets a channel's invite link.
func (r *RubikaCore) SetChannelLink(channelGUID string) (RubikaLinkInfo, error) {
	data, err := r.api("setChannelLink", map[string]interface{}{"channel_guid": channelGUID})
	if err != nil {
		return RubikaLinkInfo{}, err
	}
	return rubikaParseFlat[RubikaLinkInfo](data)
}

// GetChannelAdminMembers retrieves channel admin members.
func (r *RubikaCore) GetChannelAdminMembers(channelGUID string, startID string) (RubikaMemberList, error) {
	data, err := r.api("getChannelAdminMembers", map[string]interface{}{
		"channel_guid": channelGUID,
		"start_id":     startID,
	})
	if err != nil {
		return RubikaMemberList{}, err
	}
	return rubikaParseFlat[RubikaMemberList](data)
}

// GetChannelAdminAccessList retrieves admin access list for a channel member.
func (r *RubikaCore) GetChannelAdminAccessList(channelGUID string, memberGUID string) ([]string, error) {
	data, err := r.api("getChannelAdminAccessList", map[string]interface{}{
		"channel_guid": channelGUID,
		"member_guid":  memberGUID,
	})
	if err != nil {
		return nil, err
	}
	if list, ok := data["access_list"].([]interface{}); ok {
		result := make([]string, 0, len(list))
		for _, v := range list {
			if s, ok := v.(string); ok {
				result = append(result, s)
			}
		}
		return result, nil
	}
	return []string{}, nil
}

// RemoveChannel removes/deletes a channel.
func (r *RubikaCore) RemoveChannel(channelGUID string) error {
	_, err := r.api("removeChannel", map[string]interface{}{
		"channel_guid": channelGUID,
	})
	return err
}

// ChannelPreviewByJoinLink previews a channel by its invite link hash.
func (r *RubikaCore) ChannelPreviewByJoinLink(hashLink string) (map[string]interface{}, error) {
	return r.api("channelPreviewByJoinLink", map[string]interface{}{
		"hash_link": hashLink,
	})
}

// JoinChannelByLink joins a channel by invite link hash.
func (r *RubikaCore) JoinChannelByLink(hashLink string) error {
	_, err := r.api("joinChannelByLink", map[string]interface{}{
		"hash_link": hashLink,
	})
	return err
}

// SeenChannelMessages marks channel messages as seen.
func (r *RubikaCore) SeenChannelMessages(channelGUID string, minID string, maxID string) error {
	_, err := r.api("seenChannelMessages", map[string]interface{}{
		"channel_guid": channelGUID,
		"min_id":       minID,
		"max_id":       maxID,
	})
	return err
}

// UpdateChannelUsername updates a channel's username.
func (r *RubikaCore) UpdateChannelUsername(channelGUID string, username string) error {
	_, err := r.api("updateChannelUsername", map[string]interface{}{
		"channel_guid": channelGUID,
		"username":     strings.TrimPrefix(username, "@"),
	})
	return err
}

// CheckChannelUsername checks username availability for a channel.
func (r *RubikaCore) CheckChannelUsername(username string) (map[string]interface{}, error) {
	return r.api("checkChannelUsername", map[string]interface{}{
		"username": strings.TrimPrefix(username, "@"),
	})
}

// --- Users (extended) ---

// CheckUserUsername checks username availability.
func (r *RubikaCore) CheckUserUsername(username string) (map[string]interface{}, error) {
	return r.api("checkUserUsername", map[string]interface{}{
		"username": strings.TrimPrefix(username, "@"),
	})
}

// UpdateUsername updates the current user's username.
func (r *RubikaCore) UpdateUsername(username string) error {
	_, err := r.api("updateUsername", map[string]interface{}{
		"username": strings.TrimPrefix(username, "@"),
	})
	return err
}

// UpdateProfile updates the current user's profile.
func (r *RubikaCore) UpdateProfile(firstName string, lastName string, bio string) error {
	input := map[string]interface{}{}
	var updatedParams []string
	if firstName != "" {
		input["first_name"] = firstName
		updatedParams = append(updatedParams, "first_name")
	}
	if lastName != "" {
		input["last_name"] = lastName
		updatedParams = append(updatedParams, "last_name")
	}
	if bio != "" {
		input["bio"] = bio
		updatedParams = append(updatedParams, "bio")
	}
	input["updated_parameters"] = updatedParams
	_, err := r.api("updateProfile", input)
	return err
}

// DeleteUserChat deletes a DM chat.
func (r *RubikaCore) DeleteUserChat(userGUID string, lastDeletedMsgID string) error {
	_, err := r.api("deleteUserChat", map[string]interface{}{
		"user_guid":              userGUID,
		"last_deleted_message_id": lastDeletedMsgID,
	})
	return err
}

// --- Contacts ---

// AddAddressBook imports contacts.
func (r *RubikaCore) addAddressBook(phone string, firstName string, lastName string) (map[string]interface{}, error) {
	return r.api("addAddressBook", map[string]interface{}{
		"phone":      phone,
		"first_name": firstName,
		"last_name":  lastName,
	})
}

// DeleteContact deletes a contact.
func (r *RubikaCore) DeleteContact(userGUID string) error {
	_, err := r.api("deleteContact", map[string]interface{}{
		"user_guid": userGUID,
	})
	return err
}

// GetContactsUpdates retrieves contact updates.
func (r *RubikaCore) GetContactsUpdates(state int64) (map[string]interface{}, error) {
	if state == 0 {
		state = time.Now().Unix() - 150
	}
	return r.api("getContactsUpdates", map[string]interface{}{
		"state": state,
	})
}

// ResetContacts resets all contacts.
func (r *RubikaCore) ResetContacts() error {
	_, err := r.api("resetContacts", map[string]interface{}{})
	return err
}

// --- Settings ---

// GetPrivacySetting retrieves privacy settings.
func (r *RubikaCore) GetPrivacySetting() (RubikaPrivacySettings, error) {
	data, err := r.api("getPrivacySetting", map[string]interface{}{})
	if err != nil {
		return RubikaPrivacySettings{}, err
	}
	return rubikaParseFlat[RubikaPrivacySettings](data)
}

// GetTwoPasscodeStatus retrieves 2FA status.
func (r *RubikaCore) GetTwoPasscodeStatus() (RubikaTwoStepInfo, error) {
	data, err := r.api("getTwoPasscodeStatus", map[string]interface{}{})
	if err != nil {
		return RubikaTwoStepInfo{}, err
	}
	return rubikaParseFlat[RubikaTwoStepInfo](data)
}

// GetSuggestedFolders retrieves suggested folders.
func (r *RubikaCore) GetSuggestedFolders() (map[string]interface{}, error) {
	return r.api("getSuggestedFolders", map[string]interface{}{})
}

// TerminateOtherSessions terminates all other sessions.
func (r *RubikaCore) TerminateOtherSessions() error {
	_, err := r.api("terminateOtherSessions", map[string]interface{}{})
	return err
}

// DeleteFolder deletes a folder.
func (r *RubikaCore) DeleteFolder(folderID string) error {
	_, err := r.api("deleteFolder", map[string]interface{}{
		"folder_id": folderID,
	})
	return err
}

// GetProfileLinkItems retrieves profile link items for an object.
func (r *RubikaCore) GetProfileLinkItems(objectGUID ...string) (map[string]interface{}, error) {
	input := map[string]interface{}{}
	if len(objectGUID) > 0 && objectGUID[0] != "" {
		input["object_guid"] = objectGUID[0]
	}
	return r.api("getProfileLinkItems", input)
}

// --- Stickers (extended) ---

// SearchStickers searches for stickers.
func (r *RubikaCore) SearchStickers(searchText string, startID string) (map[string]interface{}, error) {
	input := map[string]interface{}{
		"search_text": searchText,
	}
	if startID != "" {
		input["start_id"] = startID
	}
	return r.api("searchStickers", input)
}

// GetStickerSetByID retrieves a sticker set by ID.
func (r *RubikaCore) GetStickerSetByID(stickerSetID string) (map[string]interface{}, error) {
	return r.api("getStickerSetById", map[string]interface{}{
		"sticker_set_id": stickerSetID,
	})
}

// GetStickersByEmoji retrieves stickers matching an emoji.
func (r *RubikaCore) GetStickersByEmoji(emoji string) (map[string]interface{}, error) {
	return r.api("getStickersByEmoji", map[string]interface{}{
		"emoji_character": emoji,
		"suggest_by":      "All",
	})
}

// GetStickersBySetIDs retrieves stickers by set IDs.
func (r *RubikaCore) GetStickersBySetIDs(stickerSetIDs []string) (map[string]interface{}, error) {
	return r.api("getStickersBySetIds", map[string]interface{}{
		"sticker_set_ids": stickerSetIDs,
	})
}

// GetTrendStickerSets retrieves trending sticker sets.
func (r *RubikaCore) GetTrendStickerSets() (map[string]interface{}, error) {
	return r.api("getTrendStickerSets", map[string]interface{}{})
}

// ActionOnStickerSet adds or removes a sticker set.
func (r *RubikaCore) ActionOnStickerSet(stickerSetID string, action string) error {
	_, err := r.api("actionOnStickerSet", map[string]interface{}{
		"sticker_set_id": stickerSetID,
		"action":         action, // "Add" or "Remove"
	})
	return err
}

// --- GIFs ---

// AddToMyGifSet saves a GIF to the user's collection.
func (r *RubikaCore) AddToMyGifSet(chatID string, msgID string) error {
	_, err := r.api("addToMyGifSet", map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
	})
	return err
}

// RemoveFromMyGifSet removes a GIF from the user's collection.
func (r *RubikaCore) RemoveFromMyGifSet(fileID string) error {
	_, err := r.api("removeFromMyGifSet", map[string]interface{}{
		"file_id": fileID,
	})
	return err
}

// --- Join Requests ---

// ActionOnJoinRequest accepts or rejects a join request.
func (r *RubikaCore) ActionOnJoinRequest(chatID string, chatType string, userGUID string, action string) error {
	_, err := r.api("actionOnJoinRequest", map[string]interface{}{
		"object_guid": chatID,
		"object_type": chatType,
		"user_guid":   userGUID,
		"action":      action, // "Accept" or "Reject"
	})
	return err
}

// CreateJoinLink creates a join link for a chat.
func (r *RubikaCore) CreateJoinLink(chatID string) (map[string]interface{}, error) {
	return r.api("createJoinLink", map[string]interface{}{
		"object_guid": chatID,
	})
}

// GetJoinLinks retrieves join links for a chat.
func (r *RubikaCore) GetJoinLinks(chatID string) (map[string]interface{}, error) {
	return r.api("getJoinLinks", map[string]interface{}{
		"object_guid": chatID,
	})
}

// GetJoinRequests retrieves pending join requests.
func (r *RubikaCore) GetJoinRequests(chatID string) (map[string]interface{}, error) {
	return r.api("getJoinRequests", map[string]interface{}{
		"object_guid": chatID,
	})
}

// --- Voice Chat ---

// CreateGroupVoiceChat creates a voice chat in a group.
func (r *RubikaCore) CreateGroupVoiceChat(groupGUID string) (map[string]interface{}, error) {
	return r.api("createGroupVoiceChat", map[string]interface{}{
		"chat_guid": groupGUID,
	})
}

// CreateChannelVoiceChat creates a voice chat in a channel.
func (r *RubikaCore) CreateChannelVoiceChat(channelGUID string) (map[string]interface{}, error) {
	return r.api("createChannelVoiceChat", map[string]interface{}{
		"channel_guid": channelGUID,
	})
}

// LeaveGroupVoiceChat leaves a group voice chat.
func (r *RubikaCore) LeaveGroupVoiceChat(chatGUID string, voiceChatID string) error {
	_, err := r.api("leaveGroupVoiceChat", map[string]interface{}{
		"chat_guid":     chatGUID,
		"voice_chat_id": voiceChatID,
	})
	return err
}

// DiscardGroupVoiceChat ends/discards a group voice chat.
func (r *RubikaCore) DiscardGroupVoiceChat(chatGUID string, voiceChatID string) error {
	_, err := r.api("discardGroupVoiceChat", map[string]interface{}{
		"chat_guid":     chatGUID,
		"voice_chat_id": voiceChatID,
	})
	return err
}

// LoadMoreParticipants loads more participants in a voice chat.
func (r *RubikaCore) LoadMoreParticipants(chatID string, voiceChatID string, startID string) (map[string]interface{}, error) {
	return r.api("loadMoreParticipantsApi", map[string]interface{}{
		"object_guid":    chatID,
		"voice_chat_id":  voiceChatID,
		"start_id":       startID,
	})
}

// LeaveChannelVoiceChat leaves a channel voice chat.
func (r *RubikaCore) LeaveChannelVoiceChat(channelGUID string, voiceChatID string) error {
	_, err := r.api("leaveChannelVoiceChat", map[string]interface{}{
		"channel_guid":  channelGUID,
		"voice_chat_id": voiceChatID,
	})
	return err
}

// DiscardChannelVoiceChat discards a channel voice chat.
func (r *RubikaCore) DiscardChannelVoiceChat(channelGUID string, voiceChatID string) error {
	_, err := r.api("discardChannelVoiceChat", map[string]interface{}{
		"channel_guid":  channelGUID,
		"voice_chat_id": voiceChatID,
	})
	return err
}

// SetGroupVoiceChatSetting updates group voice chat settings.
func (r *RubikaCore) SetGroupVoiceChatSetting(groupGUID string, voiceChatID string, settings map[string]interface{}) error {
	input := map[string]interface{}{
		"group_guid":    groupGUID,
		"voice_chat_id": voiceChatID,
	}
	var updatedParams []string
	for k, v := range settings {
		input[k] = v
		updatedParams = append(updatedParams, k)
	}
	input["updated_parameters"] = updatedParams
	_, err := r.api("setGroupVoiceChatSetting", input)
	return err
}

// SetChannelVoiceChatSetting updates channel voice chat settings.
func (r *RubikaCore) SetChannelVoiceChatSetting(channelGUID string, voiceChatID string, settings map[string]interface{}) error {
	input := map[string]interface{}{
		"channel_guid":  channelGUID,
		"voice_chat_id": voiceChatID,
	}
	var updatedParams []string
	for k, v := range settings {
		input[k] = v
		updatedParams = append(updatedParams, k)
	}
	input["updated_parameters"] = updatedParams
	_, err := r.api("setChannelVoiceChatSetting", input)
	return err
}

// GetGroupVoiceChatUpdates retrieves voice chat updates.
func (r *RubikaCore) GetGroupVoiceChatUpdates(chatGUID string, voiceChatID string, state int64) (map[string]interface{}, error) {
	return r.api("getGroupVoiceChatUpdates", map[string]interface{}{
		"chat_guid":     chatGUID,
		"voice_chat_id": voiceChatID,
		"state":         state,
	})
}

// GetGroupVoiceChatParticipants retrieves current participants in a voice chat.
func (r *RubikaCore) GetGroupVoiceChatParticipants(chatGUID string, voiceChatID string) (map[string]interface{}, error) {
	return r.api("getGroupVoiceChatParticipants", map[string]interface{}{
		"chat_guid":     chatGUID,
		"voice_chat_id": voiceChatID,
	})
}

// --- Reporting ---

// ReportObject reports a user/group/channel.
func (r *RubikaCore) ReportObject(chatID string, reportType int, description string) error {
	_, err := r.api("reportObject", map[string]interface{}{
		"object_guid":       chatID,
		"report_type":       reportType,
		"report_description": description,
	})
	return err
}

// --- Auto-delete ---

// AutoDeleteMessage schedules a message for auto-deletion.
func (r *RubikaCore) AutoDeleteMessage(chatID string, msgID string, seconds float64) error {
	_, err := r.api("autoDeleteMessage", map[string]interface{}{
		"object_guid":  chatID,
		"message_id":   msgID,
		"count_delete": seconds,
	})
	return err
}

// --- Avatar upload ---

// UploadAvatar uploads an avatar for a user/group/channel.
func (r *RubikaCore) UploadAvatar(objectGUID string, fileInline map[string]interface{}) error {
	_, err := r.api("uploadAvatar", map[string]interface{}{
		"object_guid": objectGUID,
		"thumbnail":   fileInline,
		"main":        fileInline,
	})
	return err
}

// --- Voice Chat (extended) ---

// JoinVoiceChat joins a voice chat with an SDP offer.
// Returns the SDP answer for WebRTC connection.
// Uses joinGroupVoiceChat for groups (g0), joinChannelVoiceChat for channels (c0).
func (r *RubikaCore) JoinVoiceChat(chatID string, voiceChatID string, sdpOffer string) (map[string]interface{}, error) {
	method := "joinGroupVoiceChat"
	if strings.HasPrefix(chatID, "c0") {
		method = "joinChannelVoiceChat"
	}
	return r.api(method, map[string]interface{}{
		"chat_guid":        chatID,
		"voice_chat_id":    voiceChatID,
		"sdp_offer_data":   sdpOffer,
		"self_object_guid": r.guid,
	})
}

// SetVoiceChatState sets the voice chat state (e.g., paused/playing).
func (r *RubikaCore) SetVoiceChatState(chatID string, voiceChatID string, state string) error {
	_, err := r.api("setVoiceChatState", map[string]interface{}{
		"object_guid":  chatID,
		"voice_chat_id": voiceChatID,
		"state":         state,
	})
	return err
}

// SendGroupVoiceChatActivity sends activity in a group voice chat.
func (r *RubikaCore) SendGroupVoiceChatActivity(groupGUID string, voiceChatID string, activity string) error {
	_, err := r.api("sendGroupVoiceChatActivity", map[string]interface{}{
		"group_guid":    groupGUID,
		"voice_chat_id": voiceChatID,
		"activity":      activity,
	})
	return err
}

// --- Transcription ---

// TranscribeVoice requests voice message transcription.
func (r *RubikaCore) TranscribeVoice(chatID string, msgID string) (map[string]interface{}, error) {
	return r.api("transcribeVoice", map[string]interface{}{
		"object_guid": chatID,
		"message_id":  msgID,
	})
}

// GetTranscription retrieves a transcription result.
func (r *RubikaCore) GetTranscription(transcriptionID string) (map[string]interface{}, error) {
	return r.api("getTranscription", map[string]interface{}{
		"transcription_id": transcriptionID,
	})
}

// --- Extras ---

// GetRelatedObjects retrieves related objects for a GUID.
func (r *RubikaCore) GetRelatedObjects(objectGUID string) (map[string]interface{}, error) {
	return r.api("getRelatedObjects", map[string]interface{}{
		"object_guid": objectGUID,
	})
}

// UserIsAdmin checks if the current user is admin in a chat.
func (r *RubikaCore) UserIsAdmin(chatID string) (map[string]interface{}, error) {
	// userIsAdmin is not a real Rubika API method — it's a helper in rubpy
	// that pages through admin members and checks if self is in the list.
	var method string
	if strings.HasPrefix(chatID, "c0") {
		method = "getChannelAdminMembers"
	} else {
		method = "getGroupAdminMembers"
	}

	selfGUID := r.guid
	startID := ""
	for {
		input := map[string]interface{}{"group_guid": chatID}
		if strings.HasPrefix(chatID, "c0") {
			input = map[string]interface{}{"channel_guid": chatID}
		}
		if startID != "" {
			input["start_id"] = startID
		}
		data, err := r.api(method, input)
		if err != nil {
			return nil, err
		}
		members, _ := data["in_chat_members"].([]interface{})
		for _, m := range members {
			mm, _ := m.(map[string]interface{})
			if mm != nil {
				guid, _ := mm["member_guid"].(string)
				if guid == selfGUID {
					return map[string]interface{}{"is_admin": true}, nil
				}
			}
		}
		hasContinue, _ := data["has_continue"].(bool)
		if !hasContinue {
			break
		}
		nextID, _ := mapGetString(data, "next_start_id")
		if nextID == "" {
			break
		}
		startID = nextID
	}
	return map[string]interface{}{"is_admin": false}, nil
}

// GetMyStickers retrieves the user's stickers.
// Uses getMyStickerSets under the hood (getMyStickers doesn't exist in Rubika API).
func (r *RubikaCore) GetMyStickers() (map[string]interface{}, error) {
	return r.api("getMyStickerSets", map[string]interface{}{})
}

// --- Settings (extended) ---

// SetSetting updates a setting value.
func (r *RubikaCore) SetSetting(settings map[string]interface{}) error {
	_, err := r.api("setSetting", settings)
	return err
}

// SetupTwoStepVerification sets up or modifies 2FA.
func (r *RubikaCore) SetupTwoStepVerification(password string, hint string, recoveryEmail string) error {
	input := map[string]interface{}{}
	if password != "" {
		input["password"] = password
	}
	if hint != "" {
		input["hint"] = hint
	}
	if recoveryEmail != "" {
		input["recovery_email"] = recoveryEmail
	}
	_, err := r.api("setupTwoStepVerification", input)
	return err
}

// TurnOffTwoStep disables two-step verification.
func (r *RubikaCore) TurnOffTwoStep(password string) error {
	_, err := r.api("turnOffTwoStep", map[string]interface{}{
		"password": password,
	})
	return err
}

// LoginTwoStepForgetPassword initiates 2FA password recovery.
func (r *RubikaCore) LoginTwoStepForgetPassword(phoneNumber string, phoneCodeHash string) (map[string]interface{}, error) {
	return r.apiTmp("loginTwoStepForgetPassword", map[string]interface{}{
		"phone_number":    phoneNumber,
		"phone_code_hash": phoneCodeHash,
	})
}

// RequestDeleteAccount requests account deletion.
func (r *RubikaCore) RequestDeleteAccount() (map[string]interface{}, error) {
	return r.api("requestDeleteAccount", map[string]interface{}{})
}

// --- Group Management (extended) ---

// EditGroupHistoryForNewMembers toggles chat history visibility for new members.
func (r *RubikaCore) EditGroupHistoryForNewMembers(groupGUID string, visible bool) error {
	action := "Hidden"
	if visible {
		action = "Visible"
	}
	_, err := r.api("editGroupInfo", map[string]interface{}{
		"group_guid":                    groupGUID,
		"chat_history_for_new_members":  action,
		"updated_parameters":            []string{"chat_history_for_new_members"},
	})
	return err
}

// SetGroupEventMessages configures join/leave event messages for a group.
func (r *RubikaCore) SetGroupEventMessages(groupGUID string, enabled bool) error {
	return r.EditGroupInfo(groupGUID, map[string]interface{}{
		"event_messages": enabled,
	})
}

// SetGroupSlowModeTime sets slow mode interval (seconds) for a group. 0 to disable.
func (r *RubikaCore) SetGroupSlowModeTime(groupGUID string, seconds int) error {
	return r.EditGroupInfo(groupGUID, map[string]interface{}{
		"slow_mode": seconds,
	})
}

// SetGroupReactions configures allowed reactions for a group.
// reactionType is "All", "Selected", or "Disabled".
// selectedReactions is used only when reactionType is "Selected" (reaction IDs as strings).
func (r *RubikaCore) SetGroupReactions(groupGUID string, reactionType string, selectedReactions []string) error {
	setting := map[string]interface{}{
		"reaction_type": reactionType,
	}
	if reactionType == "Selected" && len(selectedReactions) > 0 {
		setting["selected_reactions"] = selectedReactions
	}
	_, err := r.api("editGroupInfo", map[string]interface{}{
		"group_guid":             groupGUID,
		"chat_reaction_setting":  setting,
		"updated_parameters":     []string{"chat_reaction_setting"},
	})
	return err
}

// --- Channel Management (extended) ---

// GetBannedChannelMembers retrieves banned channel members.
func (r *RubikaCore) GetBannedChannelMembers(channelGUID string, startID string) (RubikaMemberList, error) {
	input := map[string]interface{}{"channel_guid": channelGUID}
	if startID != "" {
		input["start_id"] = startID
	}
	data, err := r.api("getBannedChannelMembers", input)
	if err != nil {
		return RubikaMemberList{}, err
	}
	return rubikaParseFlat[RubikaMemberList](data)
}

// --- Ownership Transfer ---

// RequestChangeObjectOwner initiates ownership transfer for a group or channel.
func (r *RubikaCore) RequestChangeObjectOwner(objectGUID string, newOwnerGUID string) (map[string]interface{}, error) {
	return r.api("requestChangeObjectOwner", map[string]interface{}{
		"object_guid":    objectGUID,
		"new_owner_guid": newOwnerGUID,
	})
}

// AcceptRequestObjectOwning accepts an incoming ownership transfer.
func (r *RubikaCore) AcceptRequestObjectOwning(objectGUID string) error {
	_, err := r.api("acceptRequestObjectOwning", map[string]interface{}{
		"object_guid": objectGUID,
	})
	return err
}

// RejectRequestObjectOwning rejects an incoming ownership transfer.
func (r *RubikaCore) RejectRequestObjectOwning(objectGUID string) error {
	_, err := r.api("rejectRequestObjectOwning", map[string]interface{}{
		"object_guid": objectGUID,
	})
	return err
}

// --- Folder Management (extended) ---

// AddFolder creates a new folder with the given name and included chat GUIDs.
func (r *RubikaCore) AddFolder(name string, includeObjectGUIDs []string) (RubikaFolderInfo, error) {
	input := map[string]interface{}{"name": name}
	if len(includeObjectGUIDs) > 0 {
		input["include_object_guids"] = includeObjectGUIDs
	}
	data, err := r.api("addFolder", input)
	if err != nil {
		return RubikaFolderInfo{}, err
	}
	return rubikaParseFlat[RubikaFolderInfo](data)
}

// --- Messaging (extended) ---

// SendContact sends a contact card message.
func (r *RubikaCore) SendContact(chatGUID string, firstName string, lastName string, phone string) (map[string]interface{}, error) {
	return r.api("sendMessage", map[string]interface{}{
		"object_guid": chatGUID,
		"rnd":         mrand.Intn(1000000) + 1,
		"message_contact": map[string]interface{}{
			"first_name":   firstName,
			"last_name":    lastName,
			"phone_number": phone,
		},
	})
}

// SendLocation sends a location message.
func (r *RubikaCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	r.mu.RLock()
	if !r.authed {
		r.mu.RUnlock()
		return nil, ErrAuth
	}
	r.mu.RUnlock()

	resp, err := r.api("sendMessage", map[string]interface{}{
		"object_guid": chatID,
		"rnd":         mrand.Intn(1000000) + 1,
		"location": map[string]interface{}{
			"latitude":  lat,
			"longitude": lon,
		},
	})
	if err != nil {
		return nil, err
	}
	// Extract message_update from response if available
	if mu, ok := resp["message_update"].(map[string]interface{}); ok {
		msgID, _ := mu["message_id"].(string)
		return &Message{
			ID:       msgID,
			ChatID:   chatID,
			Platform: rubikaPlatform,
		}, nil
	}
	return &Message{ChatID: chatID, Platform: rubikaPlatform}, nil
}

// SeenChats marks multiple chats as seen. seenList maps chat GUID → last seen message ID.
func (r *RubikaCore) SeenChats(seenList map[string]string) error {
	_, err := r.api("seenChats", map[string]interface{}{
		"seen_list": seenList,
	})
	return err
}

// --- Helpers ---

func mapGetString(m map[string]interface{}, key string) (string, bool) {
	if m == nil {
		return "", false
	}
	v, ok := m[key]
	if !ok {
		return "", false
	}
	s, ok := v.(string)
	return s, ok
}

// --- Unified Core interface adapters ---

// GetChatInfo retrieves information about a chat by its GUID.
func (r *RubikaCore) GetChatInfo(chatID string) (*Dialog, error) {
	ct := r.guidToChatType(chatID)
	d := &Dialog{Platform: rubikaPlatform, ID: chatID, Type: ct}
	switch ct {
	case ChatTypeGroup:
		info, err := r.GetGroupInfo(chatID)
		if err != nil {
			return nil, err
		}
		d.Title = info.GroupTitle
		d.MemberCount = info.CountMembers
	case ChatTypeChannel:
		info, err := r.GetChannelInfo(chatID)
		if err != nil {
			return nil, err
		}
		d.Title = info.ChannelTitle
		d.MemberCount = info.CountMembers
	default:
		// DM — use GetProfile
		user, err := r.GetProfile(chatID)
		if err == nil && user != nil {
			d.Title = user.DisplayName
		}
	}
	return d, nil
}

// EditChatTitle updates the title of a group or channel.
func (r *RubikaCore) EditChatTitle(chatID string, title string) error {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		return r.EditGroupInfo(chatID, map[string]interface{}{"title": title})
	case ChatTypeChannel:
		return r.EditChannelInfo(chatID, map[string]interface{}{"title": title})
	}
	return fmt.Errorf("%w: rubika does not support editing title for this chat type", ErrNotSupported)
}

// EditChatDescription updates the description of a group or channel.
func (r *RubikaCore) EditChatDescription(chatID string, description string) error {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		return r.EditGroupInfo(chatID, map[string]interface{}{"description": description})
	case ChatTypeChannel:
		return r.EditChannelInfo(chatID, map[string]interface{}{"description": description})
	}
	return fmt.Errorf("%w: rubika does not support editing description for this chat type", ErrNotSupported)
}

// LeaveChat leaves a group or channel.
func (r *RubikaCore) LeaveChat(chatID string) error {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		return r.LeaveGroup(chatID)
	case ChatTypeChannel:
		_, err := r.api("leaveChannel", map[string]interface{}{"channel_guid": chatID})
		return err
	}
	return fmt.Errorf("%w: rubika does not support leaving this chat type", ErrNotSupported)
}

// GetInviteLink retrieves the invite link for a group or channel.
func (r *RubikaCore) GetInviteLink(chatID string) (string, error) {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		info, err := r.GetGroupLink(chatID)
		if err != nil {
			return "", err
		}
		return info.JoinLink, nil
	case ChatTypeChannel:
		info, err := r.GetChannelLink(chatID)
		if err != nil {
			return "", err
		}
		return info.JoinLink, nil
	}
	return "", fmt.Errorf("%w: rubika does not support invite links for this chat type", ErrNotSupported)
}

// AddMembers adds members to a group or channel.
func (r *RubikaCore) AddMembers(chatID string, userIDs []string) error {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		return r.AddGroupMembers(chatID, userIDs)
	case ChatTypeChannel:
		return r.AddChannelMembers(chatID, userIDs)
	}
	return fmt.Errorf("%w: rubika does not support adding members to this chat type", ErrNotSupported)
}

// RemoveMember removes a member from a group or channel by banning them.
func (r *RubikaCore) RemoveMember(chatID string, userID string) error {
	return r.BanMember(chatID, userID)
}

// BanMember bans a member from a group or channel.
func (r *RubikaCore) BanMember(chatID string, userID string) error {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		return r.BanGroupMember(chatID, userID, true)
	case ChatTypeChannel:
		return r.BanChannelMember(chatID, userID, true)
	}
	return fmt.Errorf("%w: rubika does not support banning in this chat type", ErrNotSupported)
}

// UnbanMember unbans a member from a group or channel.
func (r *RubikaCore) UnbanMember(chatID string, userID string) error {
	ct := r.guidToChatType(chatID)
	switch ct {
	case ChatTypeGroup:
		return r.BanGroupMember(chatID, userID, false)
	case ChatTypeChannel:
		return r.BanChannelMember(chatID, userID, false)
	}
	return fmt.Errorf("%w: rubika does not support unbanning in this chat type", ErrNotSupported)
}

// GetMembers retrieves all members of a group or channel.
func (r *RubikaCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	ct := r.guidToChatType(chatID)
	var ml RubikaMemberList
	var err error
	switch ct {
	case ChatTypeGroup:
		ml, err = r.GetGroupAllMembers(chatID)
	case ChatTypeChannel:
		ml, err = r.GetChannelAllMembers(chatID)
	default:
		return nil, fmt.Errorf("%w: rubika does not support member listing for this chat type", ErrNotSupported)
	}
	if err != nil {
		return nil, err
	}
	users := make([]User, 0, len(ml.Members))
	for _, m := range ml.Members {
		name := m.FirstName
		if m.LastName != "" {
			if name != "" {
				name += " "
			}
			name += m.LastName
		}
		users = append(users, User{
			ID:          m.MemberGUID,
			DisplayName: name,
			Username:    m.Username,
			Platform:    rubikaPlatform,
		})
	}
	return users, nil
}

// SetAdmin grants or revokes admin privileges for a group member.
func (r *RubikaCore) SetAdmin(chatID string, userID string, admin bool) error {
	ct := r.guidToChatType(chatID)
	if ct == ChatTypeGroup {
		if admin {
			return r.SetGroupAdmin(chatID, userID, []string{
				"ChangeInfo", "DeleteGlobalAllMessages", "BanMember",
				"SetAdmin", "SetJoinLink", "PinMessages",
			})
		}
		return r.SetGroupAdmin(chatID, userID, []string{})
	}
	return fmt.Errorf("%w: rubika does not support admin management for this chat type", ErrNotSupported)
}

// GetContacts retrieves the user's contact list.
func (r *RubikaCore) GetContacts() ([]User, error) {
	raw, err := r.getContactsRaw()
	if err != nil {
		return nil, err
	}
	users := []User{}
	if contacts, ok := raw["users"].([]interface{}); ok {
		for _, c := range contacts {
			if cu, ok := c.(map[string]interface{}); ok {
				u := User{Platform: rubikaPlatform}
				if guid, ok := cu["user_guid"].(string); ok {
					u.ID = guid
				}
				if fn, ok := cu["first_name"].(string); ok {
					u.DisplayName = fn
				}
				if ln, ok := cu["last_name"].(string); ok {
					if u.DisplayName != "" {
						u.DisplayName += " "
					}
					u.DisplayName += ln
				}
				if un, ok := cu["username"].(string); ok {
					u.Username = un
				}
				if ph, ok := cu["phone"].(string); ok {
					u.Phone = ph
				}
				users = append(users, u)
			}
		}
	}
	return users, nil
}

// AddContact adds a contact to the user's address book.
func (r *RubikaCore) AddContact(phone string, firstName string, lastName string) error {
	_, err := r.addAddressBook(phone, firstName, lastName)
	return err
}

// DeleteContact is already implemented with the correct unified signature.

// BlockUser blocks a user.
func (r *RubikaCore) BlockUser(userID string) error {
	return r.SetBlockUser(userID, true)
}

// UnblockUser unblocks a user.
func (r *RubikaCore) UnblockUser(userID string) error {
	return r.SetBlockUser(userID, false)
}

// GetBlockedUsers retrieves the list of blocked users.
func (r *RubikaCore) GetBlockedUsers() ([]User, error) {
	raw, err := r.getBlockedUsersRaw()
	if err != nil {
		return nil, err
	}
	users := []User{}
	if blocked, ok := raw["users"].([]interface{}); ok {
		for _, b := range blocked {
			if bu, ok := b.(map[string]interface{}); ok {
				u := User{Platform: rubikaPlatform}
				if guid, ok := bu["user_guid"].(string); ok {
					u.ID = guid
				}
				if fn, ok := bu["first_name"].(string); ok {
					u.DisplayName = fn
				}
				if ln, ok := bu["last_name"].(string); ok {
					if u.DisplayName != "" {
						u.DisplayName += " "
					}
					u.DisplayName += ln
				}
				users = append(users, u)
			}
		}
	}
	return users, nil
}

// SearchMessages searches for messages matching a query within a chat.
func (r *RubikaCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	raw, err := r.searchChatMessages(chatID, query)
	if err != nil {
		return nil, err
	}
	msgs := []Message{}
	if messages, ok := raw["messages"].([]interface{}); ok {
		for _, m := range messages {
			if mm, ok := m.(map[string]interface{}); ok {
				msg := Message{Platform: rubikaPlatform, ChatID: chatID}
				if id, ok := mm["message_id"].(string); ok {
					msg.ID = id
				}
				if text, ok := mm["text"].(string); ok {
					msg.Text = text
				}
				if sender, ok := mm["author_object_guid"].(string); ok {
					msg.SenderID = sender
				}
				msgs = append(msgs, msg)
			}
		}
	}
	return msgs, nil
}

// SearchGlobal searches for users, groups, and channels globally.
func (r *RubikaCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	raw, err := r.searchGlobalObjects(query)
	if err != nil {
		return nil, err
	}
	dialogs := []Dialog{}
	if objects, ok := raw["objects"].([]interface{}); ok {
		for _, o := range objects {
			if obj, ok := o.(map[string]interface{}); ok {
				d := Dialog{Platform: rubikaPlatform}
				if guid, ok := obj["object_guid"].(string); ok {
					d.ID = guid
					d.Type = r.guidToChatType(guid)
				}
				if title, ok := obj["title"].(string); ok {
					d.Title = title
				} else if fn, ok := obj["first_name"].(string); ok {
					d.Title = fn
					if ln, ok := obj["last_name"].(string); ok {
						d.Title += " " + ln
					}
				}
				dialogs = append(dialogs, d)
			}
		}
	}
	return dialogs, nil
}

// SendTyping sends a typing indicator to a chat.
func (r *RubikaCore) SendTyping(chatID string) error {
	return r.SendChatActivity(chatID, "Typing")
}

// CreatePoll creates a poll in the specified chat.
func (r *RubikaCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	raw, err := r.createPollRaw(chatID, question, options)
	if err != nil {
		return nil, err
	}
	msg := &Message{Platform: rubikaPlatform, ChatID: chatID}
	if msgData, ok := raw["message"].(map[string]interface{}); ok {
		if id, ok := msgData["message_id"].(string); ok {
			msg.ID = id
		}
	}
	return msg, nil
}

// VotePoll votes on a poll option by index.
func (r *RubikaCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	// Rubika VotePoll uses poll_id, not chatID+msgID — pass msgID as poll ID
	_, err := r.votePollRaw(msgID, optionIndex)
	return err
}

// SendSticker returns an error because Rubika stickers use file-based sending.
func (r *RubikaCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	return nil, fmt.Errorf("%w: rubika stickers use file-based sending, not sticker IDs", ErrNotSupported)
}

// GetSessions retrieves all active login sessions.
func (r *RubikaCore) GetSessions() ([]Session, error) {
	raw, err := r.getMySessions()
	if err != nil {
		return nil, err
	}
	var sessions []Session
	if sessionList, ok := raw["sessions"].([]interface{}); ok {
		for _, s := range sessionList {
			if sess, ok := s.(map[string]interface{}); ok {
				session := Session{Platform: rubikaPlatform}
				if key, ok := sess["session_key"].(string); ok {
					session.ID = key
				}
				if device, ok := sess["device_model"].(string); ok {
					session.Device = device
				}
				if platform, ok := sess["platform"].(string); ok {
					session.Platform = platform
				}
				if app, ok := sess["app_version"].(string); ok {
					session.AppVersion = app
				}
				if ip, ok := sess["ip"].(string); ok {
					session.IP = ip
				}
				if loc, ok := sess["country"].(string); ok {
					session.Location = loc
				}
				if isCurrent, ok := sess["is_current"].(bool); ok {
					session.IsCurrent = isCurrent
				}
				sessions = append(sessions, session)
			}
		}
	}
	return sessions, nil
}

// TerminateSession is already implemented with the correct unified signature.

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Auth / Device (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// LoginDisableTwoStep bypasses 2FA when the password is forgotten (phone + phone_code_hash).
func (r *RubikaCore) LoginDisableTwoStep(phoneNumber string, phoneCodeHash string) (map[string]interface{}, error) {
	return r.api("loginDisableTwoStep", map[string]interface{}{
		"phone_number":    phoneNumber,
		"phone_code_hash": phoneCodeHash,
	})
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Messages (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// SearchGlobalMessages searches messages across all chats.
func (r *RubikaCore) SearchGlobalMessages(text string, startID string, limit int) (map[string]interface{}, error) {
	// searchGlobalMessages doesn't exist in Rubika API.
	// Use searchGlobalObjects which searches users/groups/channels globally.
	input := map[string]interface{}{
		"search_text": text,
	}
	if startID != "" {
		input["start_id"] = startID
	}
	return r.api("searchGlobalObjects", input)
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Chat Management
// ══════════════════════════════════════════════════════════════════════════════

// SetPrivacySetting sets an individual privacy setting with granular control.
func (r *RubikaCore) SetPrivacySetting(settingType string, value string) error {
	_, err := r.api("setPrivacySetting", map[string]interface{}{
		"setting_type":  settingType,
		"setting_value": value,
	})
	return err
}

// GetChatInfoByUsername resolves a chat by username and returns full info.
// Uses getObjectByUsername under the hood (getChatInfoByUsername doesn't exist in Rubika API).
func (r *RubikaCore) GetChatInfoByUsername(username string) (map[string]interface{}, error) {
	return r.api("getObjectByUsername", map[string]interface{}{
		"username": username,
	})
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Settings / Folders (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// EditFolder edits an existing folder's properties.
func (r *RubikaCore) EditFolder(folderID string, name string, includedChatGUIDs []string, excludedTypes []string) (map[string]interface{}, error) {
	input := map[string]interface{}{
		"folder_id": folderID,
	}
	if name != "" {
		input["name"] = name
	}
	if len(includedChatGUIDs) > 0 {
		input["include_object_guids"] = includedChatGUIDs
	}
	if len(excludedTypes) > 0 {
		input["exclude_chat_types"] = excludedTypes
	}
	return r.api("editFolder", input)
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Users (1 method)
// ══════════════════════════════════════════════════════════════════════════════

// GetUserInfo gets detailed user info by user GUID.
func (r *RubikaCore) GetUserInfo(userGUID string) (RubikaUserInfo, error) {
	data, err := r.api("getUserInfo", map[string]interface{}{"user_guid": userGUID})
	if err != nil {
		return RubikaUserInfo{}, err
	}
	return rubikaParseData[RubikaUserInfo](data, "user")
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Groups (4 methods)
// ══════════════════════════════════════════════════════════════════════════════

// RemoveGroupAdmin explicitly removes admin status from a user.
func (r *RubikaCore) RemoveGroupAdmin(groupGUID string, memberGUID string) error {
	_, err := r.api("removeGroupAdmin", map[string]interface{}{
		"group_guid":  groupGUID,
		"member_guid": memberGUID,
	})
	return err
}

// DeleteGroupAvatar deletes the group avatar.
func (r *RubikaCore) DeleteGroupAvatar(groupGUID string, avatarID string) error {
	_, err := r.api("deleteGroupAvatar", map[string]interface{}{
		"group_guid": groupGUID,
		"avatar_id":  avatarID,
	})
	return err
}

// GetNewGroupLink resets and generates a new group invite link.
func (r *RubikaCore) GetNewGroupLink(groupGUID string) (RubikaLinkInfo, error) {
	data, err := r.api("getNewGroupLink", map[string]interface{}{"group_guid": groupGUID})
	if err != nil {
		return RubikaLinkInfo{}, err
	}
	return rubikaParseFlat[RubikaLinkInfo](data)
}

// GetGroupMemberCount returns the member count for a group.
func (r *RubikaCore) GetGroupMemberCount(groupGUID string) (int, error) {
	info, err := r.GetGroupInfo(groupGUID)
	if err != nil {
		return 0, err
	}
	return info.CountMembers, nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Contacts (2 methods)
// ══════════════════════════════════════════════════════════════════════════════

// ImportContacts bulk-imports contacts from phone address book.
func (r *RubikaCore) ImportContacts(contacts []map[string]string) (map[string]interface{}, error) {
	return r.api("importContacts", map[string]interface{}{
		"contacts": contacts,
	})
}

// SearchContacts searches within the user's contact list by name or phone.
// searchContacts doesn't exist in Rubika API — falls back to getContacts and filters client-side.
func (r *RubikaCore) SearchContacts(query string) (map[string]interface{}, error) {
	data, err := r.api("getContacts", map[string]interface{}{})
	if err != nil {
		return nil, err
	}
	if query == "" {
		return data, nil
	}
	q := strings.ToLower(query)
	users, _ := data["users"].([]interface{})
	var matched []interface{}
	for _, u := range users {
		um, _ := u.(map[string]interface{})
		if um == nil {
			continue
		}
		fn, _ := um["first_name"].(string)
		ln, _ := um["last_name"].(string)
		ph, _ := um["phone"].(string)
		un, _ := um["username"].(string)
		if strings.Contains(strings.ToLower(fn), q) ||
			strings.Contains(strings.ToLower(ln), q) ||
			strings.Contains(strings.ToLower(ph), q) ||
			strings.Contains(strings.ToLower(un), q) {
			matched = append(matched, u)
		}
	}
	return map[string]interface{}{"users": matched}, nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Typed Media Senders (7 methods)
// High-level helpers: requestSendFile + upload + sendMessage in one call.
// ══════════════════════════════════════════════════════════════════════════════

// rubikaUploadAndSend is the shared upload+send logic for typed media senders.
func (r *RubikaCore) rubikaUploadAndSend(chatID string, data []byte, fileName string, mimeType string, fileType string, caption string) (map[string]interface{}, error) {
	if !r.authed {
		return nil, ErrAuth
	}
	fileSize := int64(len(data))

	// Extension for mime field
	mime := mimeType
	if idx := strings.LastIndex(fileName, "."); idx >= 0 {
		mime = fileName[idx+1:]
	}

	// Step 1: requestSendFile
	reqResult, err := r.api("requestSendFile", map[string]interface{}{
		"file_name": fileName,
		"size":      fileSize,
		"mime":      mime,
	})
	if err != nil {
		return nil, fmt.Errorf("requestSendFile: %w", err)
	}

	fileID, _ := mapGetString(reqResult, "id")
	uploadURL, _ := mapGetString(reqResult, "upload_url")
	accessHashSend, _ := mapGetString(reqResult, "access_hash_send")
	if fileID == "" || uploadURL == "" {
		return nil, fmt.Errorf("invalid requestSendFile response")
	}

	// Step 2: Upload chunks (1MB)
	chunkSize := 1048576
	totalParts := (len(data) + chunkSize - 1) / chunkSize
	var accessHashRec string

	for i := 0; i < totalParts; i++ {
		start := i * chunkSize
		end := start + chunkSize
		if end > len(data) {
			end = len(data)
		}
		chunk := data[start:end]

		uploadReq, err := http.NewRequestWithContext(r.ctx, "POST", uploadURL, bytes.NewReader(chunk))
		if err != nil {
			return nil, err
		}
		uploadReq.Header.Set("auth", r.auth)
		uploadReq.Header.Set("file-id", fileID)
		uploadReq.Header.Set("total-part", strconv.Itoa(totalParts))
		uploadReq.Header.Set("part-number", strconv.Itoa(i+1))
		uploadReq.Header.Set("chunk-size", strconv.Itoa(len(chunk)))
		uploadReq.Header.Set("access-hash-send", accessHashSend)

		resp, err := r.httpClient.Do(uploadReq)
		if err != nil {
			return nil, fmt.Errorf("upload chunk %d: %w", i+1, err)
		}
		var uploadResult map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&uploadResult)
		resp.Body.Close()

		if resultData, ok := uploadResult["data"].(map[string]interface{}); ok {
			if ahr, ok := resultData["access_hash_rec"].(string); ok {
				accessHashRec = ahr
			}
		}
	}

	// Step 3: sendMessage with file_inline
	dcID := 0
	if d, ok := reqResult["dc_id"]; ok {
		switch v := d.(type) {
		case float64:
			dcID = int(v)
		case string:
			dcID, _ = strconv.Atoi(v)
		}
	}

	fileInline := map[string]interface{}{
		"file_id":         fileID,
		"dc_id":           dcID,
		"size":            fileSize,
		"type":            fileType,
		"mime":            mime,
		"access_hash_rec": accessHashRec,
		"file_name":       fileName,
	}
	// Rubika requires width/height for Image/Video/Gif, time for Video/Music/Voice
	// rubpy defaults: width=200, height=200, time=1
	// For Image/Video/Gif: thumb_inline is required (base64 of image data as thumbnail)
	switch fileType {
	case "Image", "Video", "Gif":
		fileInline["width"] = 200
		fileInline["height"] = 200
		// Generate a minimal base64 thumbnail from the data itself (Rubika requires thumb_inline for images)
		thumbData := data
		if len(thumbData) > 40960 { // cap thumbnail at ~40KB
			thumbData = thumbData[:40960]
		}
		fileInline["thumb_inline"] = base64.StdEncoding.EncodeToString(thumbData)
	}
	switch fileType {
	case "Video", "Music", "Voice":
		fileInline["time"] = 1
	}

	sendInput := map[string]interface{}{
		"object_guid": chatID,
		"rnd":         mrand.Intn(1000000) + 1,
		"file_inline": fileInline,
	}
	if caption != "" {
		sendInput["text"] = caption
	}

	return r.api("sendMessage", sendInput)
}

// SendPhoto uploads and sends a photo (Image type).
func (r *RubikaCore) SendPhoto(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "image/jpeg", "Image", caption)
}

// SendVideo uploads and sends a video (Video type).
func (r *RubikaCore) SendVideo(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "video/mp4", "Video", caption)
}

// SendGif uploads and sends a GIF (Gif type).
func (r *RubikaCore) SendGif(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "image/gif", "Gif", caption)
}

// SendMusic uploads and sends audio/music (Music type).
func (r *RubikaCore) SendMusic(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "audio/mpeg", "Music", caption)
}

// SendVoice uploads and sends a voice message (Voice type).
func (r *RubikaCore) SendVoice(chatID string, data []byte, fileName string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "audio/ogg", "Voice", "")
}

// SendDocument uploads and sends a document (File type).
func (r *RubikaCore) SendDocument(chatID string, data []byte, fileName string, caption string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "application/octet-stream", "File", caption)
}

// SendVideoMessage uploads and sends a video note/round video (VideoMessage type).
func (r *RubikaCore) SendVideoMessage(chatID string, data []byte, fileName string) (map[string]interface{}, error) {
	return r.rubikaUploadAndSend(chatID, data, fileName, "video/mp4", "VideoMessage", "")
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Bot API (10 methods)
// ══════════════════════════════════════════════════════════════════════════════

// BotSendSticker sends a sticker via bot API.
func (r *RubikaCore) BotSendSticker(chatID string, fileID string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "Sticker",
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendImage sends an image via bot API.
func (r *RubikaCore) BotSendImage(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "Image",
	}
	if caption != "" {
		input["text"] = caption
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendDocument sends a document via bot API.
func (r *RubikaCore) BotSendDocument(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "File",
	}
	if caption != "" {
		input["text"] = caption
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendVoice sends a voice message via bot API.
func (r *RubikaCore) BotSendVoice(chatID string, fileID string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "Voice",
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendVideo sends a video via bot API.
func (r *RubikaCore) BotSendVideo(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "Video",
	}
	if caption != "" {
		input["text"] = caption
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendGif sends a GIF via bot API.
func (r *RubikaCore) BotSendGif(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "Gif",
	}
	if caption != "" {
		input["text"] = caption
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotSendMusic sends audio/music via bot API.
func (r *RubikaCore) BotSendMusic(chatID string, fileID string, caption string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id": chatID,
		"file_id": fileID,
		"type":    "Music",
	}
	if caption != "" {
		input["text"] = caption
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendFile", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// BotCheckJoin checks if a user has joined a channel/group (forced-join verification).
func (r *RubikaCore) BotCheckJoin(chatID string, userID string) (RubikaBotJoinStatus, error) {
	data, err := r.botAPIRequest("checkChatMember", map[string]interface{}{
		"chat_id": chatID,
		"user_id": userID,
	})
	if err != nil {
		return RubikaBotJoinStatus{}, err
	}
	return rubikaParseFlat[RubikaBotJoinStatus](data)
}

// BotRemoveKeypad removes the chat keypad from a conversation.
func (r *RubikaCore) BotRemoveKeypad(chatID string) error {
	_, err := r.botAPIRequest("editChatKeypad", map[string]interface{}{
		"chat_id":      chatID,
		"chat_keypad":  nil,
		"keypad_type":  "Remove",
	})
	return err
}

// BotReplyMessage replies to a specific message (with reply_to_message_id).
func (r *RubikaCore) BotReplyMessage(chatID string, text string, replyToMsgID string, opts map[string]interface{}) (string, error) {
	input := map[string]interface{}{
		"chat_id":             chatID,
		"text":                text,
		"reply_to_message_id": replyToMsgID,
	}
	for k, v := range opts {
		input[k] = v
	}
	data, err := r.botAPIRequest("sendMessage", input)
	if err != nil {
		return "", err
	}
	msgID, _ := mapGetString(data, "message_id")
	return msgID, nil
}

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — WebSocket Event Handlers (4 event types)
// ══════════════════════════════════════════════════════════════════════════════

// OnChatUpdates registers a handler specifically for chat list changes.
func (r *RubikaCore) OnChatUpdates(handler func(map[string]interface{})) {
	r.updateMu.Lock()
	r.chatUpdateHandlers = append(r.chatUpdateHandlers, handler)
	r.updateMu.Unlock()
}

// OnShowActivities registers a handler for typing/recording activity events.
func (r *RubikaCore) OnShowActivities(handler func(map[string]interface{})) {
	r.updateMu.Lock()
	r.activityHandlers = append(r.activityHandlers, handler)
	r.updateMu.Unlock()
}

// OnShowNotifications registers a handler for notification events.
func (r *RubikaCore) OnShowNotifications(handler func(map[string]interface{})) {
	r.updateMu.Lock()
	r.notificationHandlers = append(r.notificationHandlers, handler)
	r.updateMu.Unlock()
}

// OnRemoveNotifications registers a handler for notification dismissal events.
func (r *RubikaCore) OnRemoveNotifications(handler func(map[string]interface{})) {
	r.updateMu.Lock()
	r.removeNotifHandlers = append(r.removeNotifHandlers, handler)
	r.updateMu.Unlock()
}

// MuteChat returns an error because Rubika does not support muting chats via this method.
func (r *RubikaCore) MuteChat(chatID string, muted bool) error {
	return fmt.Errorf("%w: %s does not support mute chat", ErrNotSupported, rubikaPlatform)
}

// ArchiveChat returns an error because Rubika does not support archiving chats.
func (r *RubikaCore) ArchiveChat(chatID string, archived bool) error {
	return fmt.Errorf("%w: %s does not support archive chat", ErrNotSupported, rubikaPlatform)
}

// MarkUnread returns an error because Rubika does not support marking chats as unread.
func (r *RubikaCore) MarkUnread(chatID string, unread bool) error {
	return fmt.Errorf("%w: %s does not support mark unread", ErrNotSupported, rubikaPlatform)
}

// UnpinAllMessages returns an error because Rubika does not support unpinning all messages.
func (r *RubikaCore) UnpinAllMessages(chatID string) error {
	return fmt.Errorf("%w: %s does not support unpin all messages", ErrNotSupported, rubikaPlatform)
}

// AcceptCall returns an error because Rubika does not support accepting individual calls.
func (r *RubikaCore) AcceptCall(callID string) (*CallSession, error) {
	return nil, fmt.Errorf("%w: %s does not support accept call", ErrNotSupported, rubikaPlatform)
}

// DeclineCall returns an error because Rubika does not support declining individual calls.
func (r *RubikaCore) DeclineCall(callID string) error {
	return fmt.Errorf("%w: %s does not support decline call", ErrNotSupported, rubikaPlatform)
}
