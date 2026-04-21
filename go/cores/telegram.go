package cores

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"net"

	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/telegram/dcs"
	"github.com/gotd/td/telegram/downloader"
	"github.com/gotd/td/telegram/message"
	"github.com/gotd/td/telegram/uploader"
	"github.com/gotd/td/tg"
	"github.com/pion/ice/v4"
	"github.com/pion/interceptor"
	pionlogging "github.com/pion/logging"
	"github.com/pion/rtcp"
	pionrtp "github.com/pion/rtp"
	"github.com/pion/sctp"
	"github.com/pion/stun/v3"
	"github.com/pion/webrtc/v4"


	pionmedia "github.com/pion/webrtc/v4/pkg/media"
)

const tgPlatform = "telegram"

// TelegramCore implements the Core interface for Telegram via gotd/td (pure Go MTProto).
type TelegramCore struct {
	mu sync.RWMutex
	wg sync.WaitGroup

	client  *telegram.Client
	api     *tg.Client
	sender  *message.Sender
	ctx     context.Context
	cancel  context.CancelFunc

	// Config
	apiID         int
	apiHash       string
	useTestDC     bool
	forceRelayICE    bool
	forceV2Sig       bool
	forceV2Impl      bool
	forceV2Ref       bool
	forceV1Framing   bool
	forceInstanceImpl bool
	noOwnOffer       bool
	maxCallVersion   string
	minCallVersion   string
	botToken      string
	phone         string
	isBot         bool
	authed        bool

	// Session storage
	sessionStorage telegram.SessionStorage

	// Custom dialer for proxy support
	dialFunc dcs.DialFunc

	// Update handler
	dispatcher     *tg.UpdateDispatcher
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	// Peer cache — stores access hashes for users and channels
	// Populated from dialog results, updates, and explicit resolves
	userAccessHash    map[int64]int64  // userID → accessHash
	channelAccessHash map[int64]int64  // channelID → accessHash
	fileAccessHash    map[int64]int64  // fileID → accessHash
	fileReference     map[int64][]byte // fileID → fileReference
	userNames         map[int64]string // userID → display name (first + last)
	userUsernames     map[int64]string // userID → @username (for via-bot labels etc.)
	userColorIDs      map[int64]int    // userID → name color_id (0..63, from User.Color.Color)
	channelNames      map[int64]string // channelID → channel/chat title
	peerPhotoID       map[int64]int64  // peerID → profile photo ID (for avatar downloads)
	peerMu            sync.RWMutex

	// Self user info (populated after auth)
	selfID   int64
	selfName string

	// Interactive auth support (user mode)
	// When OTP/2FA aren't provided upfront, the auth flow blocks on these channels.
	authCodeCh    chan string   // caller sends OTP code here
	authPwdCh     chan string   // caller sends 2FA password here
	authCodeReady chan struct{} // closed when auth flow needs OTP (signals caller)
	authPwdReady  chan struct{} // closed when auth flow needs 2FA password
	authSetupDone chan struct{} // closed after interactive auth channels are initialized
	authDoneCh    chan struct{} // closed when auth completes (for interactive flow)
	authErrCh     chan error    // auth error channel (for interactive flow)

	// Call state
	activeCalls map[int64]*tgCall       // callID → active call
	pendingDH   map[int64]*pendingDHState // callID → DH exchange state

	// Admin rank cache — chatID → userID → custom rank title (e.g. "admin", "owner", "Head Mod")
	adminRanks        map[int64]map[int64]string
	adminRanksFetched map[int64]bool // tracks which chats we've fetched admin ranks for
	adminRanksMu      sync.RWMutex

	// Raw signaling interceptors — used by test harnesses (e.g., ntgcalls)
	rawSigInInterceptors  map[int64]func([]byte) // incoming: handleSignalingData
	rawSigOutInterceptors map[int64]func([]byte) // outgoing: sendCallSignaling
	rawSigInterceptorsMu  sync.RWMutex

	// Forum topic cache — chatID:topicID → {title, iconColor}
	forumTopics   map[string]forumTopicInfo
	forumTopicsMu sync.RWMutex

	// Video codec factories — set via SetVideoEncoderFactory/SetVideoDecoderFactory.
	// Keeps telegram.go pure Go: the implementation (e.g. vpx package) is injected by bridge/tests.
	newVideoEncoder func(width, height, bitrate int) (VideoEncoder, error)
	newVideoDecoder func() (VideoDecoder, error)
}

var _ Core = (*TelegramCore)(nil)

// VideoEncoder encodes raw YUV420P frames to VP8.
type VideoEncoder interface {
	Encode(yuv420p []byte, width, height int) (vp8Frame []byte, err error)
	ForceKeyframe()
	Close()
}

// VideoDecoder decodes VP8 frames to raw YUV420P.
type VideoDecoder interface {
	Decode(vp8Frame []byte) (yuv420p []byte, width, height int, err error)
	Close()
}

// TelegramConfig holds configuration for creating a TelegramCore.
type TelegramConfig struct {
	APIID          int
	APIHash        string
	UseTestDC      bool
	SessionStorage telegram.SessionStorage
	DialFunc       dcs.DialFunc // custom dialer for proxy support
	ForceRelayICE  bool         // force relay-only ICE (needed for same-machine two-user tests)
	ForceV2Sig     bool         // force SCTP/V2 signaling regardless of negotiated version
	ForceV2Impl    bool         // force V2Impl signaling (InitialSetup+NegotiateChannels) regardless of version
	ForceV2Ref     bool         // force V2Reference SDP signaling WITHOUT SCTP (override V2Impl auto-detection)
	ForceV1Framing    bool         // force V1 encryption framing ([seq][payload] instead of [seq|flags][0x7F][len][payload])
	ForceInstanceImpl bool         // force InstanceImpl (binary protocol, raw ICE) regardless of version
	NoOwnOffer        bool         // don't send our own SDP offer — wait for remote's (official client interop)
	MaxCallVersion    string       // limit protocol versions in call requests (e.g., "9.0.0" → only advertise ≤9.x)
	MinCallVersion    string       // minimum protocol version (e.g., "9.0.0" → only advertise ≥9.x)
}

func NewTelegramCore(cfg TelegramConfig) *TelegramCore {
	if cfg.SessionStorage == nil {
		cfg.SessionStorage = &session.StorageMemory{}
	}
	return &TelegramCore{
		apiID:             cfg.APIID,
		apiHash:           cfg.APIHash,
		useTestDC:         cfg.UseTestDC,
		forceRelayICE:     cfg.ForceRelayICE,
		forceV2Sig:        cfg.ForceV2Sig,
		forceV2Impl:       cfg.ForceV2Impl,
		forceV2Ref:        cfg.ForceV2Ref,
		forceV1Framing:    cfg.ForceV1Framing,
		forceInstanceImpl: cfg.ForceInstanceImpl,
		noOwnOffer:        cfg.NoOwnOffer,
		maxCallVersion:    cfg.MaxCallVersion,
		minCallVersion:    cfg.MinCallVersion,
		sessionStorage:    cfg.SessionStorage,
		dialFunc:          cfg.DialFunc,
		authSetupDone:     make(chan struct{}),
		userAccessHash:    make(map[int64]int64),
		channelAccessHash: make(map[int64]int64),
		fileAccessHash:    make(map[int64]int64),
		fileReference:     make(map[int64][]byte),
		userNames:         make(map[int64]string),
		userUsernames:     make(map[int64]string),
		userColorIDs:      make(map[int64]int),
		channelNames:      make(map[int64]string),
		peerPhotoID:       make(map[int64]int64),
		adminRanks:         make(map[int64]map[int64]string),
		adminRanksFetched:  make(map[int64]bool),
		activeCalls:        make(map[int64]*tgCall),
		pendingDH:          make(map[int64]*pendingDHState),
		rawSigInInterceptors:  make(map[int64]func([]byte)),
		rawSigOutInterceptors: make(map[int64]func([]byte)),
	}
}

// Name returns the platform identifier for Telegram.
func (t *TelegramCore) Name() string { return tgPlatform }

// Capabilities returns the list of features supported by the Telegram core.
func (t *TelegramCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapTopics, CapCalls, CapGroupCalls,
		CapReactions, CapReadReceipts, CapTyping, CapPolls, CapStickers,
		CapFolders, CapAdmin, CapSessions, CapBase64Image, CapScheduled,
		CapSearch, CapBlocking, CapFileTransfer,
	}
}

// initClient creates the gotd client with configured options.
func (t *TelegramCore) initClient() {
	dispatcher := tg.NewUpdateDispatcher()
	t.dispatcher = &dispatcher

	opts := telegram.Options{
		SessionStorage: t.sessionStorage,
		UpdateHandler:  dispatcher,
	}

	// Custom resolver for proxy support
	if t.dialFunc != nil {
		opts.Resolver = dcs.Plain(dcs.PlainOptions{
			Dial: t.dialFunc,
		})
	}

	// Test server
	if t.useTestDC {
		opts.DCList = dcs.Test()
		opts.DC = 2
	}

	t.client = telegram.NewClient(t.apiID, t.apiHash, opts)

	// Register update dispatcher for new messages
	dispatcher.OnNewMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewMessage) error {
		var converted *Message
		switch msg := u.Message.(type) {
		case *tg.Message:
			converted = t.convertMessage(msg)
		case *tg.MessageService:
			if _, ok := msg.Action.(*tg.MessageActionEmpty); ok {
				return nil
			}
			if _, ok := msg.Action.(*tg.MessageActionHistoryClear); ok {
				return nil
			}
			converted = t.convertServiceMessage(msg)
		default:
			return nil
		}
		t.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   converted.ChatID,
			Message:  converted,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnEditMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateEditMessage) error {
		msg, ok := u.Message.(*tg.Message)
		if !ok {
			return nil
		}
		converted := t.convertMessage(msg)
		t.fireUpdate(Update{
			Type:     UpdateEditMessage,
			ChatID:   converted.ChatID,
			Message:  converted,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnDeleteMessages(func(ctx context.Context, e tg.Entities, u *tg.UpdateDeleteMessages) error {
		for _, msgID := range u.Messages {
			t.fireUpdate(Update{
				Type:      UpdateDeleteMessage,
				MessageID: strconv.Itoa(msgID),
				Platform:  tgPlatform,
			})
		}
		return nil
	})

	// Channel/supergroup message handlers (supergroups use different update types)
	dispatcher.OnNewChannelMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewChannelMessage) error {
		var converted *Message
		switch msg := u.Message.(type) {
		case *tg.Message:
			converted = t.convertMessage(msg)
		case *tg.MessageService:
			if _, ok := msg.Action.(*tg.MessageActionEmpty); ok {
				return nil
			}
			if _, ok := msg.Action.(*tg.MessageActionHistoryClear); ok {
				return nil
			}
			converted = t.convertServiceMessage(msg)
		default:
			return nil
		}
		t.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   converted.ChatID,
			Message:  converted,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnEditChannelMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateEditChannelMessage) error {
		msg, ok := u.Message.(*tg.Message)
		if !ok {
			return nil
		}
		converted := t.convertMessage(msg)
		t.fireUpdate(Update{
			Type:     UpdateEditMessage,
			ChatID:   converted.ChatID,
			Message:  converted,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnDeleteChannelMessages(func(ctx context.Context, e tg.Entities, u *tg.UpdateDeleteChannelMessages) error {
		if len(u.Messages) == 0 {
			return nil
		}
		chatID := strconv.FormatInt(int64(-1000000000000-u.ChannelID), 10)
		for _, msgID := range u.Messages {
			t.fireUpdate(Update{
				Type:      UpdateDeleteMessage,
				ChatID:    chatID,
				MessageID: strconv.Itoa(msgID),
				Platform:  tgPlatform,
			})
		}
		return nil
	})

	// Call update handlers
	dispatcher.OnPhoneCall(func(ctx context.Context, e tg.Entities, u *tg.UpdatePhoneCall) error {
		fmt.Printf("[tg-call] UpdatePhoneCall: %T\n", u.PhoneCall)
		switch c := u.PhoneCall.(type) {
		case *tg.PhoneCallAccepted:
			fmt.Printf("[tg-call] Accepted! id=%d g_b=%d bytes, completing DH...\n", c.ID, len(c.GB))
			go func() {
				if err := t.handleCallAccepted(c.ID, c.GB, c.Protocol); err != nil {
					fmt.Printf("[tg-call] handleCallAccepted ERROR: %v\n", err)
				} else {
					fmt.Printf("[tg-call] handleCallAccepted OK — WebRTC starting\n")
				}
			}()
		case *tg.PhoneCall:
			fmt.Printf("[tg-call] PhoneCall update: %d connections, fp=%d\n", len(c.Connections), c.KeyFingerprint)
			// For incoming calls: complete DH and start WebRTC
			go func() {
				if err := t.handleIncomingCallConfirmed(c); err != nil {
					fmt.Printf("[tg-call] handleIncomingCallConfirmed ERROR: %v\n", err)
				}
			}()
		case *tg.PhoneCallDiscarded:
			fmt.Printf("[tg-call] Discarded! id=%d reason=%T needRating=%v needDebug=%v\n", c.ID, c.Reason, c.NeedRating, c.NeedDebug)
			// Call ended — clean up SCTP + WebRTC
			var accessHash int64
			t.mu.Lock()
			if call := t.activeCalls[c.ID]; call != nil {
				accessHash = call.accessHash
				call.state = CallStateEnded
				if call.done != nil {
					select {
					case <-call.done:
					default:
						close(call.done)
					}
				}
				if call.cancel != nil {
					call.cancel()
				}
				if call.sctpStream != nil {
					call.sctpStream.Close()
				}
				if call.sctpAssoc != nil {
					call.sctpAssoc.Abort("call discarded")
				}
				call.closeVideoCodecs()
				if call.sctpConn != nil {
					call.sctpConn.Close()
				}
				if call.pc != nil {
					call.pc.Close()
				}
				delete(t.activeCalls, c.ID)
			}
			t.mu.Unlock()
			meta := map[string]string{
				"need_rating": strconv.FormatBool(c.NeedRating),
				"need_debug":  strconv.FormatBool(c.NeedDebug),
				"access_hash": strconv.FormatInt(accessHash, 10),
			}
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call:     &CallSession{ID: strconv.FormatInt(c.ID, 10), State: CallStateEnded, Meta: meta},
			})
		case *tg.PhoneCallWaiting:
			fmt.Printf("[tg-call] Waiting: id=%d receiveDate=%d\n", c.ID, c.ReceiveDate)
		case *tg.PhoneCallRequested:
			// Store incoming call state for later AcceptCall
			t.mu.Lock()
			if t.activeCalls == nil {
				t.activeCalls = make(map[int64]*tgCall)
			}
			t.activeCalls[c.ID] = &tgCall{
				id:         c.ID,
				accessHash: c.AccessHash,
				peerID:     c.AdminID,
				isOutgoing: false,
				isVideo:    c.Video,
				state:      CallStateRinging,
				done:       make(chan struct{}),
			}
			t.mu.Unlock()
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call: &CallSession{
					ID:      strconv.FormatInt(c.ID, 10),
					IsVideo: c.Video,
					State:   CallStateRinging,
				},
			})
		}
		return nil
	})

	dispatcher.OnPhoneCallSignalingData(func(ctx context.Context, e tg.Entities, u *tg.UpdatePhoneCallSignalingData) error {
		fmt.Printf("[tg-call] SignalingData received: callID=%d, %d bytes\n", u.PhoneCallID, len(u.Data))
		go t.handleSignalingData(u.PhoneCallID, u.Data)
		return nil
	})

	// Group call SFU transport response
	dispatcher.OnGroupCallConnection(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCallConnection) error {
		fmt.Printf("[tg-group] UpdateGroupCallConnection: presentation=%v params=%d bytes\n",
			u.Presentation, len(u.Params.Data))
		go t.handleGroupCallConnection(u.Params.Data, u.Presentation)
		return nil
	})

	// Group call state updates (participant join/leave, title change, ended, etc.)
	dispatcher.OnGroupCall(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCall) error {
		switch gc := u.Call.(type) {
		case *tg.GroupCall:
			fmt.Printf("[tg-group] UpdateGroupCall: id=%d participants=%d title=%q\n",
				gc.ID, gc.ParticipantsCount, gc.Title)
			t.mu.RLock()
			call := t.activeCalls[gc.ID]
			t.mu.RUnlock()
			if call != nil {
				t.fireUpdate(Update{
					Type:     UpdateCallState,
					Platform: tgPlatform,
					Call: &CallSession{
						ID:    strconv.FormatInt(gc.ID, 10),
						State: CallStateActive,
						IsGroup: true,
						Meta: map[string]string{
							"title":             gc.Title,
							"participants_count": strconv.Itoa(gc.ParticipantsCount),
						},
					},
				})
			}
		case *tg.GroupCallDiscarded:
			fmt.Printf("[tg-group] UpdateGroupCall: DISCARDED id=%d\n", gc.ID)
			t.mu.Lock()
			if call := t.activeCalls[gc.ID]; call != nil {
				call.state = CallStateEnded
				if call.pc != nil {
					call.pc.Close()
				}
				delete(t.activeCalls, gc.ID)
			}
			t.mu.Unlock()
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call:     &CallSession{ID: strconv.FormatInt(gc.ID, 10), State: CallStateEnded, IsGroup: true},
			})
		}
		return nil
	})

	// Group call participant updates (join, leave, mute, SSRC changes)
	dispatcher.OnGroupCallParticipants(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCallParticipants) error {
		inputGC, ok := u.Call.(*tg.InputGroupCall)
		if !ok {
			return nil
		}
		gcID := inputGC.ID
		fmt.Printf("[tg-group] UpdateGroupCallParticipants: gcID=%d count=%d\n", gcID, len(u.Participants))

		t.mu.RLock()
		call := t.activeCalls[gcID]
		t.mu.RUnlock()
		if call == nil {
			return nil
		}

		var participants []CallParticipant
		videoEndpointsChanged := false
		for _, p := range u.Participants {
			userID := ""
			displayName := ""
			if peer, ok := p.Peer.(*tg.PeerUser); ok {
				userID = strconv.FormatInt(peer.UserID, 10)
			}
			if p.Left {
				fmt.Printf("[tg-group]   participant LEFT: userID=%s ssrc=%d\n", userID, p.Source)
				// Remove from video endpoints
				call.sfuRemoteVideoMu.Lock()
				for eid, uid := range call.sfuRemoteVideoEndpts {
					if uid == userID {
						delete(call.sfuRemoteVideoEndpts, eid)
						videoEndpointsChanged = true
					}
				}
				call.sfuRemoteVideoMu.Unlock()
			} else {
				fmt.Printf("[tg-group]   participant: userID=%s ssrc=%d muted=%v canSelfUnmute=%v videoJoined=%v\n",
					userID, p.Source, p.Muted, p.CanSelfUnmute, p.VideoJoined)
				// Track remote participant video endpoint for SFU subscription
				if !p.Self {
					if vid, ok := p.GetVideo(); ok && p.VideoJoined {
						fmt.Printf("[tg-group]   video endpoint=%s sourceGroups=%d audioSource=%d\n",
							vid.Endpoint, len(vid.SourceGroups), vid.AudioSource)
						for _, sg := range vid.SourceGroups {
							fmt.Printf("[tg-group]     ssrcGroup: semantics=%s sources=%v\n", sg.Semantics, sg.Sources)
						}
						call.sfuRemoteVideoMu.Lock()
						if _, exists := call.sfuRemoteVideoEndpts[vid.Endpoint]; !exists {
							call.sfuRemoteVideoEndpts[vid.Endpoint] = userID
							videoEndpointsChanged = true
						}
						call.sfuRemoteVideoMu.Unlock()
					}
				}
			}
			participants = append(participants, CallParticipant{
				UserID:      userID,
				DisplayName: displayName,
				IsMuted:     p.Muted,
				HasVideo:    p.VideoJoined,
			})
		}
		// If video endpoints changed, update SFU subscription
		if videoEndpointsChanged {
			go t.sendSFUVideoConstraints(call)
		}

		t.fireUpdate(Update{
			Type:     UpdateCallState,
			Platform: tgPlatform,
			Call: &CallSession{
				ID:           strconv.FormatInt(gcID, 10),
				State:        call.state,
				IsGroup:      true,
				Participants: participants,
			},
		})
		return nil
	})
	// User status updates (online/offline + coarse last-seen kinds).
	dispatcher.OnUserStatus(func(ctx context.Context, e tg.Entities, u *tg.UpdateUserStatus) error {
		userID := strconv.FormatInt(u.UserID, 10)
		var isOnline bool
		var kind string
		var lastSeen *time.Time
		switch s := u.Status.(type) {
		case *tg.UserStatusOnline:
			isOnline = true
			kind = "online"
		case *tg.UserStatusOffline:
			isOnline = false
			kind = "exact"
			ts := time.Unix(int64(s.WasOnline), 0)
			lastSeen = &ts
		case *tg.UserStatusRecently:
			kind = "recently"
		case *tg.UserStatusLastWeek:
			kind = "within_week"
		case *tg.UserStatusLastMonth:
			kind = "within_month"
		case *tg.UserStatusEmpty:
			kind = "long_ago"
		default:
			return nil
		}
		t.fireUpdate(Update{
			Type:         UpdateUserStatus,
			UserID:       userID,
			IsOnline:     &isOnline,
			LastSeenKind: kind,
			LastSeen:     lastSeen,
			Platform:     tgPlatform,
		})
		return nil
	})
	// following the tgcalls protocol spec in docs/tgcalls_protocol.md
}

// Authenticate connects to Telegram and authenticates as a bot or user.
func (t *TelegramCore) Authenticate(cfg AuthConfig) error {
	// Setup phase — exclusive access
	t.mu.Lock()

	// Override API ID/Hash from config if provided
	if v, ok := cfg.Extra["api_id"]; ok {
		if id, err := strconv.Atoi(v); err == nil {
			t.apiID = id
		}
	}
	if v, ok := cfg.Extra["api_hash"]; ok {
		t.apiHash = v
	}
	if v, ok := cfg.Extra["test_server"]; ok && v == "true" {
		t.useTestDC = true
	}
	t.initClient()
	t.ctx, t.cancel = context.WithCancel(context.Background())

	// Set up interactive auth channels for user mode before releasing lock
	if cfg.Mode == AuthModeUser {
		if cfg.OTP == "" {
			t.authCodeCh = make(chan string, 1)
			t.authCodeReady = make(chan struct{})
		}
		if cfg.Password2F == "" {
			t.authPwdCh = make(chan string, 1)
			t.authPwdReady = make(chan struct{})
		}
	}
	close(t.authSetupDone)

	// Release lock before blocking wait — the goroutine needs to write t.authed
	t.mu.Unlock()

	authDone := make(chan struct{})
	errCh := make(chan error, 1)

	t.wg.Add(1)
	go func() {
		defer t.wg.Done()
		errCh <- t.client.Run(t.ctx, func(ctx context.Context) error {
			api := tg.NewClient(t.client)
			up := uploader.NewUploader(api)
			sndr := message.NewSender(api).WithUploader(up)

			switch cfg.Mode {
			case AuthModeBot:
				t.isBot = true
				t.botToken = cfg.BotToken
				status, err := t.client.Auth().Status(ctx)
				if err != nil {
					return fmt.Errorf("auth status: %w", err)
				}
				if !status.Authorized {
					if _, err := t.client.Auth().Bot(ctx, cfg.BotToken); err != nil {
						return fmt.Errorf("bot auth: %w", err)
					}
				}

			case AuthModeUser:
				t.isBot = false
				t.phone = cfg.Phone

				authFlow := &telegramAuthFlow{
					phone:    cfg.Phone,
					code:     cfg.OTP,
					password: cfg.Password2F,
				}

				// If OTP not provided upfront, set up interactive channels
				if cfg.OTP == "" {
					authFlow.codeCh = t.authCodeCh
					authFlow.codeReady = t.authCodeReady
				}
				if cfg.Password2F == "" {
					authFlow.pwdCh = t.authPwdCh
					authFlow.pwdReady = t.authPwdReady
				}

				flow := auth.NewFlow(authFlow, auth.SendCodeOptions{})
				if err := t.client.Auth().IfNecessary(ctx, flow); err != nil {
					return fmt.Errorf("user auth: %w", err)
				}

			default:
				return fmt.Errorf("unknown auth mode: %s", cfg.Mode)
			}

			// Auth succeeded — store client references
			t.mu.Lock()
			t.api = api
			t.sender = sndr
			t.authed = true
			t.mu.Unlock()

			// Cache self user info for SenderName population
			if me, err := api.UsersGetUsers(ctx, []tg.InputUserClass{&tg.InputUserSelf{}}); err == nil && len(me) > 0 {
				if u, ok := me[0].(*tg.User); ok {
					t.mu.Lock()
					t.selfID = u.ID
					t.selfName = strings.TrimSpace(u.FirstName + " " + u.LastName)
					if t.selfName == "" {
						t.selfName = u.Username
					}
					t.mu.Unlock()
					t.peerMu.Lock()
					t.userAccessHash[u.ID] = u.AccessHash
					if t.selfName != "" {
						t.userNames[u.ID] = t.selfName
					}
					t.peerMu.Unlock()
				}
			}

			close(authDone)

			// Block to keep the connection alive for updates
			<-ctx.Done()
			return ctx.Err()
		})
	}()

	// For interactive user mode (no pre-provided OTP), return immediately
	// when the code is requested. The caller must then use SubmitOTP/Submit2FA.
	if cfg.Mode == AuthModeUser && cfg.OTP == "" {
		t.mu.Lock()
		t.authDoneCh = authDone
		t.authErrCh = errCh
		t.mu.Unlock()

		select {
		case <-authDone:
			// Session was already valid — no OTP needed.
			return nil
		case <-t.authCodeReady:
			// OTP code was requested — return sentinel so caller knows to ask user.
			return fmt.Errorf("otp_required")
		case err := <-errCh:
			if err != nil && !isContextErr(err) {
				return fmt.Errorf("%w: %s", ErrAuth, err)
			}
			t.mu.RLock()
			authed := t.authed
			t.mu.RUnlock()
			if authed {
				return nil
			}
			return fmt.Errorf("%w: connection closed before auth completed", ErrAuth)
		case <-time.After(30 * time.Second):
			t.cancel()
			return fmt.Errorf("%w: authentication timed out", ErrAuth)
		}
	}

	// Bot mode or user mode with pre-provided OTP — wait for completion.
	timeout := 30 * time.Second
	if cfg.Mode == AuthModeUser {
		timeout = 60 * time.Second
	}

	select {
	case <-authDone:
		return nil
	case err := <-errCh:
		if err != nil && !isContextErr(err) {
			return fmt.Errorf("%w: %s", ErrAuth, err)
		}
		t.mu.RLock()
		authed := t.authed
		t.mu.RUnlock()
		if authed {
			return nil
		}
		return fmt.Errorf("%w: connection closed before auth completed", ErrAuth)
	case <-time.After(timeout):
		t.cancel()
		return fmt.Errorf("%w: authentication timed out", ErrAuth)
	}
}

// SubmitOTP provides the OTP code to an in-progress interactive auth flow.
// Must be called after Authenticate returns "otp_required".
// Returns nil on success, "2fa_required" if 2FA password is needed next.
func (t *TelegramCore) SubmitOTP(code string) error {
	if t.authCodeCh == nil {
		return fmt.Errorf("no auth flow in progress")
	}
	t.authCodeCh <- code

	t.mu.RLock()
	doneCh := t.authDoneCh
	errCh := t.authErrCh
	t.mu.RUnlock()

	select {
	case <-doneCh:
		return nil
	case <-t.authPwdReady:
		return fmt.Errorf("2fa_required")
	case err := <-errCh:
		if err != nil && !isContextErr(err) {
			return fmt.Errorf("%w: %s", ErrAuth, err)
		}
		t.mu.RLock()
		authed := t.authed
		t.mu.RUnlock()
		if authed {
			return nil
		}
		return fmt.Errorf("%w: auth failed after OTP", ErrAuth)
	case <-time.After(30 * time.Second):
		return fmt.Errorf("%w: OTP verification timed out", ErrAuth)
	}
}

// Submit2FA provides the 2FA password to an in-progress interactive auth flow.
// Must be called after SubmitOTP returns "2fa_required".
func (t *TelegramCore) Submit2FA(password string) error {
	if t.authPwdCh == nil {
		return fmt.Errorf("no 2FA flow in progress")
	}
	t.authPwdCh <- password

	t.mu.RLock()
	doneCh := t.authDoneCh
	errCh := t.authErrCh
	t.mu.RUnlock()

	select {
	case <-doneCh:
		return nil
	case err := <-errCh:
		if err != nil && !isContextErr(err) {
			return fmt.Errorf("%w: %s", ErrAuth, err)
		}
		t.mu.RLock()
		authed := t.authed
		t.mu.RUnlock()
		if authed {
			return nil
		}
		return fmt.Errorf("%w: 2FA failed", ErrAuth)
	case <-time.After(30 * time.Second):
		return fmt.Errorf("%w: 2FA verification timed out", ErrAuth)
	}
}

func isContextErr(err error) bool {
	return err == context.Canceled || err == context.DeadlineExceeded
}

// Logout signs out of the current Telegram session and closes the connection.
func (t *TelegramCore) Logout() error {
	t.mu.Lock()
	defer t.mu.Unlock()

	if t.api != nil && t.authed {
		t.api.AuthLogOut(t.ctx)
	}
	t.authed = false
	if t.cancel != nil {
		t.cancel()
	}
	return nil
}

// GetDialogs returns the list of conversations for the authenticated user.
// Paginates automatically to fetch up to opts.Limit dialogs (default 500).
func (t *TelegramCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	totalLimit := opts.Limit
	if totalLimit <= 0 {
		totalLimit = 500
	}

	var allDialogs []Dialog
	offsetDate := 0
	offsetID := 0
	var offsetPeer tg.InputPeerClass = &tg.InputPeerEmpty{}

	if opts.Offset != "" {
		if od, err := strconv.Atoi(opts.Offset); err == nil {
			offsetDate = od
		}
	}

	for len(allDialogs) < totalLimit {
		batchLimit := 100
		if remaining := totalLimit - len(allDialogs); remaining < batchLimit {
			batchLimit = remaining
		}

		result, err := t.api.MessagesGetDialogs(t.ctx, &tg.MessagesGetDialogsRequest{
			Limit:      batchLimit,
			OffsetDate: offsetDate,
			OffsetID:   offsetID,
			OffsetPeer: offsetPeer,
		})
		if err != nil {
			if len(allDialogs) > 0 {
				return allDialogs, nil // Return what we got
			}
			return nil, fmt.Errorf("get dialogs: %w", err)
		}

		batch, err := t.convertDialogs(result)
		if err != nil {
			return allDialogs, err
		}
		if len(batch) == 0 {
			break // No more dialogs
		}

		allDialogs = append(allDialogs, batch...)

		// Check if server says we got everything (DialogsSlice has Count).
		if slice, ok := result.(*tg.MessagesDialogsSlice); ok {
			if len(allDialogs) >= slice.Count {
				break
			}
		} else {
			// Non-slice response means all dialogs fit in one response.
			break
		}

		// Advance pagination using the last dialog's date/ID/peer.
		last := batch[len(batch)-1]
		if last.LastMessage != nil {
			offsetDate = int(last.LastMessage.Timestamp.Unix())
			if id, err := strconv.Atoi(last.LastMessage.ID); err == nil {
				offsetID = id
			}
		}
		peer, _ := t.resolvePeer(last.ID)
		if peer != nil {
			if ip, err := t.toInputPeer(peer); err == nil {
				offsetPeer = ip
			}
		}
	}

	return allDialogs, nil
}

// SendMessage sends a text message to the specified chat.
func (t *TelegramCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.sender == nil {
		return nil, ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	target := t.sender.To(inputPeer)
	var result tg.UpdatesClass

	if msg.ReplyToID != "" {
		replyID, err := tgMsgID(msg.ReplyToID)
		if err != nil {
			return nil, err
		}
		result, err = target.Reply(replyID).Text(t.ctx, msg.Text)
	} else {
		result, err = target.Text(t.ctx, msg.Text)
	}
	if err != nil {
		return nil, fmt.Errorf("send message: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

// GetMessages retrieves messages from a chat with pagination support.
func (t *TelegramCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}

	offsetID := 0
	if opts.Offset != "" {
		var oerr error
		offsetID, oerr = tgMsgID(opts.Offset)
		if oerr != nil {
			return nil, oerr
		}
	}

	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	// Try getHistory first (works for user mode), fall back to search (works for bots)
	result, err := t.api.MessagesGetHistory(t.ctx, &tg.MessagesGetHistoryRequest{
		Peer:     inputPeer,
		Limit:    limit,
		OffsetID: offsetID,
	})
	if err != nil {
		// Bots get BOT_METHOD_INVALID for getHistory — fallback to search
		result, err = t.api.MessagesSearch(t.ctx, &tg.MessagesSearchRequest{
			Peer:     inputPeer,
			Q:        "",
			Filter:   &tg.InputMessagesFilterEmpty{},
			Limit:    limit,
			OffsetID: offsetID,
		})
		if err != nil {
			return nil, fmt.Errorf("get messages: %w", err)
		}
	}

	return t.convertMessages(result), nil
}

// GetPinnedMessages returns all pinned messages in a chat.
func (t *TelegramCore) GetPinnedMessages(chatID string) ([]Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	result, err := t.api.MessagesSearch(t.ctx, &tg.MessagesSearchRequest{
		Peer:   inputPeer,
		Q:      "",
		Filter: &tg.InputMessagesFilterPinned{},
		Limit:  50,
	})
	if err != nil {
		return nil, fmt.Errorf("get pinned messages: %w", err)
	}

	msgs := t.convertMessages(result)
	// Mark all as pinned since the filter guarantees it.
	for i := range msgs {
		msgs[i].IsPinned = true
	}
	return msgs, nil
}

// EditMessage modifies the text of a previously sent message.
func (t *TelegramCore) EditMessage(chatID string, msgID string, text string) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	result, err := t.api.MessagesEditMessage(t.ctx, &tg.MessagesEditMessageRequest{
		Peer:    inputPeer,
		ID:      id,
		Message: text,
	})
	if err != nil {
		return nil, fmt.Errorf("edit message: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

// DeleteMessage removes one or more messages from a chat.
func (t *TelegramCore) DeleteMessage(chatID string, msgID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}

	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}

	// Channels/supergroups need channels.deleteMessages, regular chats use messages.deleteMessages
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = t.api.ChannelsDeleteMessages(t.ctx, &tg.ChannelsDeleteMessagesRequest{
			Channel: &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash},
			ID:      []int{id},
		})
	default:
		_, err = t.api.MessagesDeleteMessages(t.ctx, &tg.MessagesDeleteMessagesRequest{
			ID:     []int{id},
			Revoke: true,
		})
	}
	return err
}

// ReplyToMessage sends a text message as a reply to a specific message.
func (t *TelegramCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	msg.ReplyToID = replyToMsgID
	return t.SendMessage(chatID, msg)
}

// ForwardMessage forwards a message from one chat to another.
func (t *TelegramCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	fromPeer, err := t.resolvePeer(fromChatID)
	if err != nil {
		return nil, err
	}
	toPeer, err := t.resolvePeer(toChatID)
	if err != nil {
		return nil, err
	}

	fromInput, _ := t.toInputPeer(fromPeer)
	toInput, _ := t.toInputPeer(toPeer)

	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	result, err := t.api.MessagesForwardMessages(t.ctx, &tg.MessagesForwardMessagesRequest{
		FromPeer: fromInput,
		ToPeer:   toInput,
		ID:       []int{id},
		RandomID: []int64{time.Now().UnixNano()},
	})
	if err != nil {
		return nil, fmt.Errorf("forward message: %w", err)
	}

	return t.extractMessageFromUpdates(result, toChatID), nil
}

// ReactToMessage adds or changes an emoji reaction on a message.
func (t *TelegramCore) ReactToMessage(chatID string, msgID string, emoji string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}

	_, err = t.api.MessagesSendReaction(t.ctx, &tg.MessagesSendReactionRequest{
		Peer:     inputPeer,
		MsgID:    id,
		Reaction: []tg.ReactionClass{&tg.ReactionEmoji{Emoticon: emoji}},
	})
	return err
}

// PinMessage pins a message in a chat.
func (t *TelegramCore) PinMessage(chatID string, msgID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}

	_, err = t.api.MessagesUpdatePinnedMessage(t.ctx, &tg.MessagesUpdatePinnedMessageRequest{
		Peer:  inputPeer,
		ID:    id,
	})
	return err
}

// UnpinMessage removes the pin from a message in a chat.
func (t *TelegramCore) UnpinMessage(chatID string, msgID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}

	_, err = t.api.MessagesUpdatePinnedMessage(t.ctx, &tg.MessagesUpdatePinnedMessageRequest{
		Peer:    inputPeer,
		ID:      id,
		Unpin:   true,
	})
	return err
}

// MarkAsRead marks all messages in a chat as read.
func (t *TelegramCore) MarkAsRead(chatID string, upToMsgID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	id, err := tgMsgID(upToMsgID)
	if err != nil {
		return err
	}

	// Channels/supergroups use channels.readHistory
	if ch, ok := peer.(*tg.PeerChannel); ok {
		hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
		_, err = t.api.ChannelsReadHistory(t.ctx, &tg.ChannelsReadHistoryRequest{
			Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
			MaxID:   id,
		})
		return err
	}

	// Regular chats/DMs use messages.readHistory
	inputPeer, _ := t.toInputPeer(peer)
	_, err = t.api.MessagesReadHistory(t.ctx, &tg.MessagesReadHistoryRequest{
		Peer:  inputPeer,
		MaxID: id,
	})
	return err
}

// GetReadState returns the read state for a chat.
func (t *TelegramCore) GetReadState(chatID string) (*ReadState, error) {
	// Telegram doesn't have a direct "who read what" API for non-group chats.
	// For groups, it's available via MessagesGetMessageReadParticipants.
	return &ReadState{
		PeerLastRead: make(map[string]string),
	}, nil
}

// UploadFile uploads a file to Telegram and sends it to the specified chat.
func (t *TelegramCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(t.api)
	if progress != nil {
		u = u.WithProgress(&uploadProgress{callback: progress, total: file.Size})
	}

	upload, err := u.Upload(t.ctx, uploader.NewUpload(file.Name, io.NopCloser(file.Reader), file.Size))
	if err != nil {
		return nil, fmt.Errorf("upload: %w", err)
	}

	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	target := t.sender.To(inputPeer)

	var result tg.UpdatesClass

	// Detect media type and send appropriately for inline preview
	switch {
	case strings.HasPrefix(file.MimeType, "image/"):
		// Send as photo — shows inline preview in Telegram
		photo := message.UploadedPhoto(upload)
		result, err = target.Media(t.ctx, photo)

	case strings.HasPrefix(file.MimeType, "video/"):
		// Send as video with attributes — plays inline in Telegram
		doc := message.UploadedDocument(upload).
			MIME(file.MimeType).
			Filename(file.Name).
			Video()
		result, err = target.Media(t.ctx, doc)

	case strings.HasPrefix(file.MimeType, "audio/"):
		// Send as audio — shows audio player in Telegram
		doc := message.UploadedDocument(upload).
			MIME(file.MimeType).
			Filename(file.Name).
			Audio()
		result, err = target.Media(t.ctx, doc)

	case file.MimeType == "audio/ogg" || strings.HasSuffix(file.Name, ".ogg"):
		// Send as voice message
		doc := message.UploadedDocument(upload).
			MIME("audio/ogg").
			Filename(file.Name).
			Voice()
		result, err = target.Media(t.ctx, doc)

	default:
		// Send as generic document/file
		doc := message.UploadedDocument(upload).
			MIME(file.MimeType).
			Filename(file.Name)
		result, err = target.Media(t.ctx, doc)
	}

	if err != nil {
		return nil, fmt.Errorf("send file: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

// DownloadFile downloads a file from Telegram by its file reference.
func (t *TelegramCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	fileID, err := tgUserID(fileRef.ID)
	if err != nil {
		return err
	}
	if fileID == 0 {
		return fmt.Errorf("%w: empty file ID", ErrInvalidInput)
	}

	// Get access hash and file reference — try in-memory cache first, then Extra field.
	accessHash := t.getCachedFileHash(fileID)
	fileReference := t.getCachedFileRef(fileID)
	if accessHash == 0 && fileRef.Extra != "" {
		accessHash, fileReference = decodeFileExtra(fileRef.Extra)
		if accessHash != 0 {
			t.cacheFileInfo(fileID, accessHash, fileReference)
		}
	}

	// Determine file location based on mime type
	var location tg.InputFileLocationClass
	if strings.HasPrefix(fileRef.MimeType, "image/") && fileRef.MimeType != "image/gif" {
		// Photos use InputPhotoFileLocation
		location = &tg.InputPhotoFileLocation{
			ID:            fileID,
			AccessHash:    accessHash,
			FileReference: fileReference,
			ThumbSize:     "y", // largest photo size
		}
	} else {
		// Documents (files, videos, audio, stickers, etc.)
		location = &tg.InputDocumentFileLocation{
			ID:            fileID,
			AccessHash:    accessHash,
			FileReference: fileReference,
		}
	}

	f, err := os.Create(dest)
	if err != nil {
		return fmt.Errorf("create file: %w", err)
	}
	defer f.Close()

	d := downloader.NewDownloader()
	_, err = d.Download(t.api, location).Stream(t.ctx, f)
	if err != nil {
		os.Remove(dest)
		return fmt.Errorf("download: %w", err)
	}

	return nil
}

// DownloadChatAvatar downloads the profile photo for a chat/user and saves it to destPath.
// Uses InputPeerPhotoFileLocation to fetch the photo from the correct DC.
func (t *TelegramCore) DownloadChatAvatar(chatID, destPath string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return fmt.Errorf("resolve peer: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return fmt.Errorf("input peer: %w", err)
	}

	// Look up cached photo ID for this peer.
	var rawID int64
	switch p := peer.(type) {
	case *tg.PeerUser:
		rawID = p.UserID
	case *tg.PeerChat:
		rawID = p.ChatID
	case *tg.PeerChannel:
		rawID = p.ChannelID
	}

	t.peerMu.RLock()
	photoID, ok := t.peerPhotoID[rawID]
	t.peerMu.RUnlock()
	if !ok || photoID == 0 {
		return fmt.Errorf("no photo for peer %s", chatID)
	}

	location := &tg.InputPeerPhotoFileLocation{
		Peer:    inputPeer,
		PhotoID: photoID,
	}

	f, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("create file: %w", err)
	}
	defer f.Close()

	d := downloader.NewDownloader()
	_, err = d.Download(t.api, location).Stream(t.ctx, f)
	if err != nil {
		os.Remove(destPath)
		return fmt.Errorf("download avatar: %w", err)
	}

	return nil
}

// SendImageBase64 sends a base64-encoded image as a photo message.
func (t *TelegramCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }

	imgData, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil { return nil, err }
	inputPeer, _ := t.toInputPeer(peer)

	u := uploader.NewUploader(t.api)
	upload, err := u.FromBytes(t.ctx, "image.png", imgData)
	if err != nil { return nil, fmt.Errorf("upload image: %w", err) }

	updates, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer:     inputPeer,
		Media:    &tg.InputMediaUploadedPhoto{File: upload},
		Message:  caption,
		RandomID: time.Now().UnixNano(),
	})
	if err != nil { return nil, err }

	msg := t.extractMessageFromUpdates(updates, chatID)
	if msg != nil { return msg, nil }
	return &Message{ChatID: chatID, Text: caption, IsOutgoing: true, Platform: tgPlatform}, nil
}


// --- Calls: V2Reference protocol (standard WebRTC SDP + encrypted signaling) ---
// By advertising versions 11.0.0/10.0.0, the remote uses InstanceV2ReferenceImpl
// which does standard SDP offer/answer over encrypted signaling — compatible with pion natively.
// See docs/tgcalls_protocol.md for full protocol spec.

// tgCall holds the state of an active call (1:1 or group/SFU).
type tgCall struct {
	id          int64
	accessHash  int64
	peerID      int64
	isOutgoing  bool
	isVideo     bool
	isGroupCall bool          // true for SFU group calls
	authKey     [256]byte     // DH shared secret (1:1 only)

	pc               *webrtc.PeerConnection
	audioTrack       *webrtc.TrackLocalStaticRTP    // stored for SendAudioFrame (1:1 + group calls)
	videoTrack       *webrtc.TrackLocalStaticSample // VP8 video (pion handles RTP packetization)
	state      CallState
	muted      bool
	cancel     context.CancelFunc
	done       chan struct{} // closed when call ends, signals all goroutines to exit
	p2pAllowed bool // from PhoneCall response — controls ICE transport policy

	// Audio receive callback (set via SetOnAudioFrame)
	onAudioFrame func(frame []byte)

	// Video receive callbacks
	onVideoFrame        func(frame []byte)                    // raw VP8 frame (reassembled)
	onDecodedVideoFrame func(yuv420p []byte, width, height int) // decoded YUV420P frame

	// Echo mode: received opus frames are forwarded back immediately
	echoMode      bool
	externalAudio bool // when true, silence sender is disabled (external code sends audio)

	// Audio send state (atomic for concurrent access from silence sender + SendAudioFrame)
	audioSeq         uint32 // atomic
	audioTS          uint32 // atomic
	audioSSRC        uint32
	audioTSIncrement uint32 // samples per frame (960=20ms, 2880=60ms, 5760=120ms at 48kHz)

	// Video send state
	videoSSRC  uint32
	videoEncoder VideoEncoder // lazy-init'd by SendVideoFrameYUV

	// Screencast (screen sharing) — separate VP8 track
	screenTrack   *webrtc.TrackLocalStaticSample // VP8 screencast
	onScreenFrame        func(frame []byte)                    // raw VP8 frame
	onDecodedScreenFrame func(yuv420p []byte, width, height int) // decoded YUV420P frame
	screenSSRC    uint32             // our screencast SSRC
	screenActive  bool               // true when we're actively sharing screen
	screenEncoder VideoEncoder       // lazy-init'd by SendScreenFrameYUV

	// VP8 frame reassembly (incoming RTP packets → complete VP8 frames)
	videoFrameBuf  []byte
	screenFrameBuf []byte

	// VP8 decoder for incoming video (lazy-init'd)
	videoDecoder VideoDecoder

	// Remote media SSRCs (for OnTrack dispatch: video vs screencast)
	remoteVideoSSRC  uint32
	remoteScreenSSRC uint32

	// Call recording (client-side — captures incoming + outgoing audio to file)
	recording     bool
	recordingFile *os.File
	recordingMu   sync.Mutex

	// Signaling encryption counter (accessed atomically via tgEncryptSignaling)
	sigCounter uint32

	// Signaling state (protected by mu)
	mu                  sync.Mutex
	localSetupSent      bool
	remoteSDPSet        bool   // true after first offer/answer is applied
	remoteOfferCount    int    // how many remote offers we've processed (usually 0 or 1)
	dtlsRole            string // our DTLS role: "active" (client) or "passive" (server)
	localSDP            string // our initial offer/answer SDP (for extracting ICE creds)
	pendingCandidates   []webrtc.ICECandidateInit
	localSDPReady       chan struct{} // Closed when PeerConnection is ready
	pcReady             chan struct{} // Closed when PeerConnection reaches Connected/Failed/Closed
	pcReadyOnce         sync.Once

	// SCTP signaling (v11.0.0) — SCTP association over MTProto signaling channel
	useV2Sig       bool                // true when negotiated version is 11.0.0 (SCTP signaling)
	sctpConn       *sctpSignalingConn  // virtual net.Conn bridging SCTP ↔ MTProto
	sctpAssoc      *sctp.Association   // SCTP association
	sctpStream     *sctp.Stream        // SCTP stream 0 for signaling
	sctpReady      chan struct{}        // closed when SCTP association + stream are ready
	v2SigCounter   uint32              // atomic counter for V2 encryption

	// Web signaling (v4.0.0/4.0.1) — InitialSetup with inline audio/video/screencast
	useWebSignaling bool

	// V2Impl signaling (v7.0.0-9.0.0, v12.0.0-13.0.0) — InitialSetup + NegotiateChannels
	useV2Impl              bool
	useV1Framing           bool                    // v7.0.0: use V1 encryption framing (simple [seq][payload], no kCustomId/ACKs)
	remoteInitialSetup     *tgInitialSetup        // stored until NegotiateChannels arrives
	remoteNegChannels      *tgNegotiateChannels   // answer to our offer (same exchangeId)
	remoteNegChannelsOffer *tgNegotiateChannels   // remote's own offer (different exchangeId, has their SSRC)
	v2ImplExchangeSeq      uint32                 // atomic counter for NegotiateChannels exchangeId
	v2ImplHandshakeDone    bool                   // true after remote InitialSetup processed
	answeredExchangeIDs    map[string]bool         // dedup: exchangeIds we've already answered (prevents retransmit storm)

	// InstanceImpl (v5.0.0, v2.7.7) — binary protocol, raw ICE, no DTLS/SRTP
	useInstanceImpl    bool
	iceAgent           *ice.Agent       // raw ICE agent (no PeerConnection)
	iceConn            *ice.Conn        // connected ICE transport
	transportCounter   uint32           // atomic: transport encryption seq counter
	sigEncCounter      uint32           // atomic: signaling encryption seq counter (InstanceImpl binary msgs)
	pendingAcks        []uint32         // incoming message seqs that need ACKing (protected by mu)
	instanceImplReady  chan struct{}     // closed when InstanceImpl ICE agent is ready
	remoteUfrag        string           // remote ICE ufrag (from CandidatesListMessage)
	remotePwd          string           // remote ICE pwd
	remoteCredsReady   chan struct{}    // closed when remote ICE ufrag/pwd received

	// V2 JSON signaling ACKs (for V2 framing over MTProto — not SCTP/V1/InstanceImpl)
	pendingV2Acks []uint32 // received seqs needing ACK (protected by mu)

	// Remote media state (updated from incoming MediaState messages)
	remoteMuted           bool
	remoteVideoState      string // "inactive", "active"
	remoteScreencastState string // "inactive", "active"
	remoteVideoRotation   int
	remoteLowBattery      bool

	// SFU (group call) transport — received via UpdateGroupCallConnection
	sfuTransportReady chan struct{} // closed when SFU transport JSON arrives
	sfuTransportJSON  string       // raw JSON from UpdateGroupCallConnection

	// SFU video subscription — data channel sends ReceiverVideoConstraints to tell SFU which video to forward
	sfuDataChannel       *webrtc.DataChannel     // data channel to SFU for video subscription
	sfuDataChannelOpen   chan struct{}            // closed when data channel opens
	sfuRemoteVideoEndpts map[string]string        // endpointID → userID (remote participants with video)
	sfuRemoteVideoMu     sync.Mutex              // protects sfuRemoteVideoEndpts

	// Test harness support — when skipWebRTC is true, DH completes but no PeerConnection is created.
	// The test reads authKey, connections, and protocol from the call state.
	skipWebRTC  bool
	connections []tg.PhoneConnectionClass // stored from PhoneCall update
	protocol    *tg.PhoneCallProtocol     // negotiated protocol from PhoneCall
	dhDone      chan struct{}              // closed when DH is complete (for test sync)
}

// tgCallSignaling types for V2 JSON signaling.
type tgInitialSetup struct {
	Type         string              `json:"@type"`
	Ufrag        string              `json:"ufrag"`
	Pwd          string              `json:"pwd"`
	Renomination bool                `json:"renomination"`
	Fingerprints []tgDTLSFingerprint `json:"fingerprints"`
	Audio        *tgMediaDesc        `json:"audio,omitempty"`
	Video        *tgMediaDesc        `json:"video,omitempty"`
	Screencast   *tgMediaDesc        `json:"screencast,omitempty"`
}

type tgMediaDesc struct {
	SSRC          string              `json:"ssrc"`
	SSRCGroups    []tgWebSSRCGroup    `json:"ssrcGroups"`
	PayloadTypes  []tgPayloadType     `json:"payloadTypes"`
	RTPExtensions []tgRTPExtension    `json:"rtpExtensions"`
}

// tgWebSSRCGroup — web uses integer SSRCs (not strings like V2Impl)
type tgWebSSRCGroup struct {
	Semantics string `json:"semantics,omitempty"`
	SSRCs     []int  `json:"ssrcs"`
}

type tgDTLSFingerprint struct {
	Hash        string `json:"hash"`
	Setup       string `json:"setup"`
	Fingerprint string `json:"fingerprint"`
}

type tgNegotiateChannels struct {
	Type       string            `json:"@type"`
	ExchangeID string            `json:"exchangeId"`
	Contents   []tgMediaContent  `json:"contents"`
}

type tgMediaContent struct {
	Type          string              `json:"type"`
	SSRC          string              `json:"ssrc"`
	SSRCGroups    []tgSSRCGroup       `json:"ssrcGroups,omitempty"`
	PayloadTypes  []tgPayloadType     `json:"payloadTypes"`
	RTPExtensions []tgRTPExtension    `json:"rtpExtensions"`
}

type tgSSRCGroup struct {
	Semantics string   `json:"semantics"`
	SSRCs     []string `json:"ssrcs"`
}

type tgPayloadType struct {
	ID            int                    `json:"id"`
	Name          string                 `json:"name"`
	Clockrate     int                    `json:"clockrate"`
	Channels      int                    `json:"channels,omitempty"`
	FeedbackTypes []tgFeedbackType       `json:"feedbackTypes,omitempty"`
	Parameters    map[string]string      `json:"parameters,omitempty"`
}

type tgFeedbackType struct {
	Type    string `json:"type"`
	Subtype string `json:"subtype"` // always serialize, even empty — matches C++ format
}

type tgRTPExtension struct {
	ID  int    `json:"id"`
	URI string `json:"uri"`
}

type tgCandidates struct {
	Type       string        `json:"@type"`
	Candidates []tgCandidate `json:"candidates"`
}

type tgCandidate struct {
	SDPString string `json:"sdpString"`
}

type tgMediaState struct {
	Type           string `json:"@type"`
	Muted          bool   `json:"muted"`
	VideoState     string `json:"videoState"`
	VideoRotation  int    `json:"videoRotation"`
	ScreencastState string `json:"screencastState"`
	LowBattery     bool   `json:"lowBattery"`
}

// applyRemoteMediaState updates a call's remote media state fields from an incoming MediaState
// and fires an UpdateCallState to notify the UI.
func (t *TelegramCore) applyRemoteMediaState(call *tgCall, ms tgMediaState) {
	call.mu.Lock()
	call.remoteMuted = ms.Muted
	if ms.VideoState != "" {
		call.remoteVideoState = ms.VideoState
	}
	if ms.ScreencastState != "" {
		call.remoteScreencastState = ms.ScreencastState
	}
	call.remoteVideoRotation = ms.VideoRotation
	call.remoteLowBattery = ms.LowBattery
	call.mu.Unlock()

	// Build meta for Dart
	meta := map[string]string{
		"remote_muted":           strconv.FormatBool(ms.Muted),
		"remote_video_state":     ms.VideoState,
		"remote_screencast_state": ms.ScreencastState,
		"remote_video_rotation":  strconv.Itoa(ms.VideoRotation),
		"remote_low_battery":     strconv.FormatBool(ms.LowBattery),
	}
	t.fireUpdate(Update{
		Type:     UpdateCallState,
		Platform: tgPlatform,
		Call: &CallSession{
			ID:    strconv.FormatInt(call.id, 10),
			State: call.state,
			Meta:  meta,
		},
	})
}

// isV2ImplVersion returns true if the negotiated version uses InstanceV2Impl signaling
// (InitialSetup + NegotiateChannels instead of SDP offer/answer).
// V2Impl versions: 7.0.0 (V1 encryption), 8.0.0-9.0.0 (V2 encryption), 12.0.0-13.0.0 (V3/SCTP).
func isV2ImplVersion(v string) bool {
	return v == "8.0.0" || v == "13.0.0"
}

// isV3Transport returns true if the version uses SCTP signaling transport.
func isV3Transport(v string) bool {
	return v == "13.0.0"
}

// filterVersions returns a filtered version list where only versions with
// major number ≤ maxVer's major number are included. Used for testing specific
// protocol versions (prevents server from negotiating a higher version).
func filterVersions(versions []string, maxVer string, minVers ...string) []string {
	var maxMajor, minMajor int
	if maxVer != "" {
		fmt.Sscanf(maxVer, "%d", &maxMajor)
	}
	if len(minVers) > 0 && minVers[0] != "" {
		fmt.Sscanf(minVers[0], "%d", &minMajor)
	}
	if maxMajor == 0 && minMajor == 0 {
		return versions
	}
	var filtered []string
	for _, v := range versions {
		var major int
		fmt.Sscanf(v, "%d", &major)
		if (maxMajor == 0 || major <= maxMajor) && (minMajor == 0 || major >= minMajor) {
			filtered = append(filtered, v)
		}
	}
	if len(filtered) == 0 {
		return versions // safety: don't return empty
	}
	return filtered
}

// isWebVersion returns true if the version uses Telegram Web signaling format
// (InitialSetup with inline audio/video/screencast, no NegotiateChannels).
func isWebVersion(v string) bool {
	switch v {
	case "4.0.0", "4.0.1":
		return true
	}
	return false
}

// =============================================================================
// InstanceImpl binary message protocol (v5.0.0 / v2.7.7)
// Binary typed messages over dual encrypted channels (signaling + transport).
// No SDP, no DTLS, no SRTP — raw ICE + AES-CTR encryption.
// =============================================================================

// InstanceImpl message type IDs (matching Message.h)
const (
	instanceMsgCandidatesList     = 1
	instanceMsgVideoFormats       = 2
	instanceMsgRequestVideo       = 3
	instanceMsgRemoteMediaState   = 4
	instanceMsgAudioData          = 5
	instanceMsgVideoData          = 6
	instanceMsgUnstructuredData   = 7
	instanceMsgVideoParameters    = 8
	instanceMsgBatteryLevelIsLow  = 9
	instanceMsgNetworkStatus      = 10
	instanceMsgAck                = 0xFF
	instanceMsgEmpty              = 0xFE
)

// Seq flag bits
const (
	seqSingleMessageBit  = uint32(1) << 31
	seqRequiresAckBit    = uint32(1) << 30
)

// InstanceImpl SSRC assignments (hardcoded in MediaManager.cpp)
const (
	instanceSSRCAudioIncoming = 1
	instanceSSRCAudioOutgoing = 2
	instanceSSRCVideoIncoming = 3
	instanceSSRCVideoOutgoing = 4
)

// serializeInstanceImplString writes [uint32 BE length][string bytes]
func serializeInstanceImplString(buf *bytes.Buffer, s string) {
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(s)))
	buf.Write(lenBuf[:])
	buf.WriteString(s)
}

// deserializeInstanceImplString reads [uint32 BE length][string bytes]
func deserializeInstanceImplString(data []byte, pos int) (string, int, error) {
	if pos+4 > len(data) {
		return "", pos, fmt.Errorf("string: not enough bytes for length at pos %d", pos)
	}
	length := int(binary.BigEndian.Uint32(data[pos : pos+4]))
	pos += 4
	if length > 65536 || pos+length > len(data) {
		return "", pos, fmt.Errorf("string: invalid length %d at pos %d", length, pos)
	}
	s := string(data[pos : pos+length])
	return s, pos + length, nil
}

// serializeCandidatesListMsg builds the binary CandidatesListMessage.
// Format: [1 byte count] [for each: [uint32 len][candidate string]] [uint32 len][ufrag] [uint32 len][pwd]
func serializeCandidatesListMsg(candidates []string, ufrag, pwd string) []byte {
	var buf bytes.Buffer
	buf.WriteByte(byte(len(candidates)))
	for _, c := range candidates {
		// JsepIceCandidate format: "candidate:..." prefix expected by tgcalls
		if !strings.HasPrefix(c, "candidate:") {
			c = "candidate:" + c
		}
		serializeInstanceImplString(&buf, c)
	}
	serializeInstanceImplString(&buf, ufrag)
	serializeInstanceImplString(&buf, pwd)
	return buf.Bytes()
}

// deserializeCandidatesListMsg parses a binary CandidatesListMessage.
func deserializeCandidatesListMsg(data []byte) (candidates []string, ufrag, pwd string, err error) {
	if len(data) < 1 {
		return nil, "", "", fmt.Errorf("CandidatesList: empty")
	}
	count := int(data[0])
	pos := 1
	for i := 0; i < count; i++ {
		var c string
		c, pos, err = deserializeInstanceImplString(data, pos)
		if err != nil {
			return nil, "", "", fmt.Errorf("CandidatesList: candidate %d: %w", i, err)
		}
		candidates = append(candidates, c)
	}
	ufrag, pos, err = deserializeInstanceImplString(data, pos)
	if err != nil {
		return nil, "", "", fmt.Errorf("CandidatesList: ufrag: %w", err)
	}
	pwd, pos, err = deserializeInstanceImplString(data, pos)
	if err != nil {
		return nil, "", "", fmt.Errorf("CandidatesList: pwd: %w", err)
	}
	return candidates, ufrag, pwd, nil
}

// serializeVideoFormatsMsg builds the binary VideoFormatsMessage.
// We send an empty list (audio-only) with encodersCount=0.
func serializeVideoFormatsMsg() []byte {
	// [1 byte: 0 formats] [1 byte: 0 encoders]
	return []byte{0, 0}
}

// serializeRemoteMediaStateMsg builds the binary RemoteMediaStateMessage.
// bit 0: audio (1=Active), bits 1-2: video state (0=Inactive)
func serializeRemoteMediaStateMsg(audioActive bool, videoState int) []byte {
	state := byte(0)
	if audioActive {
		state |= 1
	}
	state |= byte(videoState&0x03) << 1
	return []byte{state}
}

// serializeNetworkStatusMsg builds the binary RemoteNetworkStatusMessage (v5.0.0 only).
func serializeNetworkStatusMsg(isLowCost, isLowDataRequested bool) []byte {
	buf := []byte{0, 0}
	if isLowCost {
		buf[0] = 1
	}
	if isLowDataRequested {
		buf[1] = 1
	}
	return buf
}

// instanceImplSerializeMsg creates the plaintext for a single InstanceImpl message.
// Format: [4 bytes seq|flags][1 byte typeID][message data]
func instanceImplSerializeMsg(typeID byte, data []byte, counter *uint32, requiresAck bool) []byte {
	seq := atomic.AddUint32(counter, 1)

	singleMessage := !requiresAck // single-message optimization only for non-ack messages
	if singleMessage {
		seq |= seqSingleMessageBit
	}
	if requiresAck {
		seq |= seqRequiresAckBit
	}

	buf := make([]byte, 4+1+len(data))
	binary.BigEndian.PutUint32(buf[:4], seq)
	buf[4] = typeID
	copy(buf[5:], data)
	return buf
}

// instanceImplAppendAcks appends pending ACK messages to an existing serialized buffer.
// Each ACK: [4 bytes seq][1 byte 0xFF]
func instanceImplAppendAcks(buf []byte, ackSeqs []uint32) []byte {
	for _, ackSeq := range ackSeqs {
		var ackBuf [5]byte
		binary.BigEndian.PutUint32(ackBuf[:4], ackSeq)
		ackBuf[4] = instanceMsgAck
		buf = append(buf, ackBuf[:]...)
	}
	return buf
}

// tgEncryptInstanceImplSignaling encrypts an InstanceImpl binary message for the signaling channel.
// x = 128 (outgoing) or 136 (incoming). Same AES-CTR as V2, but with typed messages, not kCustomId.
func tgEncryptInstanceImplSignaling(key []byte, plaintext []byte, isOutgoing bool) ([]byte, error) {
	x := 128
	if !isOutgoing {
		x = 136
	}

	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	msgKeyLarge := h.Sum(nil)
	msgKey := msgKeyLarge[8:24]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)
	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	ciphertext := make([]byte, len(plaintext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(ciphertext, plaintext)

	packet := make([]byte, 16+len(ciphertext))
	copy(packet[:16], msgKey)
	copy(packet[16:], ciphertext)
	return packet, nil
}

// tgDecryptInstanceImplSignaling decrypts an InstanceImpl signaling packet and returns decoded messages.
// Returns: list of (typeID, data, seq) tuples.
func tgDecryptInstanceImplSignaling(key []byte, packet []byte, isOutgoing bool) ([]instanceImplMsg, error) {
	if len(packet) < 21 {
		return nil, fmt.Errorf("InstanceImpl signaling too short: %d", len(packet))
	}

	// Decrypt direction: swap for receiving
	x := 136
	if !isOutgoing {
		x = 128
	}

	msgKey := packet[:16]
	ciphertext := packet[16:]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)
	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	plaintext := make([]byte, len(ciphertext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(plaintext, ciphertext)

	// Verify msgKey
	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	check := h.Sum(nil)
	if !bytes.Equal(check[8:24], msgKey) {
		return nil, fmt.Errorf("InstanceImpl signaling: msgKey mismatch")
	}

	return parseInstanceImplMessages(plaintext)
}

// tgEncryptTransport encrypts data for the InstanceImpl transport channel (raw ICE).
// x = 0 (outgoing) or 8 (incoming).
func tgEncryptTransport(key []byte, plaintext []byte, isOutgoing bool) ([]byte, error) {
	x := 0
	if !isOutgoing {
		x = 8
	}

	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	msgKeyLarge := h.Sum(nil)
	msgKey := msgKeyLarge[8:24]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)
	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	ciphertext := make([]byte, len(plaintext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(ciphertext, plaintext)

	packet := make([]byte, 16+len(ciphertext))
	copy(packet[:16], msgKey)
	copy(packet[16:], ciphertext)
	return packet, nil
}

// tgDecryptTransport decrypts an InstanceImpl transport packet.
func tgDecryptTransport(key []byte, packet []byte, isOutgoing bool) ([]instanceImplMsg, error) {
	if len(packet) < 21 {
		return nil, fmt.Errorf("InstanceImpl transport too short: %d", len(packet))
	}

	// Decrypt direction: swap for receiving
	x := 8
	if !isOutgoing {
		x = 0
	}

	msgKey := packet[:16]
	ciphertext := packet[16:]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)
	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	plaintext := make([]byte, len(ciphertext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(plaintext, ciphertext)

	// Verify msgKey
	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	check := h.Sum(nil)
	if !bytes.Equal(check[8:24], msgKey) {
		return nil, fmt.Errorf("InstanceImpl transport: msgKey mismatch")
	}

	return parseInstanceImplMessages(plaintext)
}

type instanceImplMsg struct {
	TypeID byte
	Data   []byte
	Seq    uint32 // raw seq including flags
}

// parseInstanceImplMessages parses decrypted plaintext containing one or more binary messages.
// Format: [4 bytes seq][1 byte typeID][message data] ... (possibly bundled)
func parseInstanceImplMessages(plaintext []byte) ([]instanceImplMsg, error) {
	if len(plaintext) < 5 {
		return nil, fmt.Errorf("decrypted payload too short: %d", len(plaintext))
	}

	var messages []instanceImplMsg
	pos := 0
	first := true

	for pos < len(plaintext) {
		if pos+5 > len(plaintext) {
			break
		}

		var seq uint32
		if first {
			seq = binary.BigEndian.Uint32(plaintext[0:4])
			pos = 4
			first = false
		} else {
			seq = binary.BigEndian.Uint32(plaintext[pos : pos+4])
			pos += 4
		}

		if pos >= len(plaintext) {
			break
		}

		typeID := plaintext[pos]
		pos++

		singleMessage := (seq & seqSingleMessageBit) != 0

		switch typeID {
		case instanceMsgEmpty:
			// No payload
		case instanceMsgAck:
			// No payload — just the seq being ACKed
			messages = append(messages, instanceImplMsg{TypeID: typeID, Seq: seq})
		case instanceMsgAudioData, instanceMsgVideoData:
			// Binary data — if single message, rest of packet is data
			if singleMessage {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos:], Seq: seq})
				pos = len(plaintext)
			} else {
				// Multi-message: [uint16 length][data]
				if pos+2 > len(plaintext) {
					break
				}
				dataLen := int(binary.BigEndian.Uint16(plaintext[pos : pos+2]))
				pos += 2
				if pos+dataLen > len(plaintext) {
					dataLen = len(plaintext) - pos
				}
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+dataLen], Seq: seq})
				pos += dataLen
			}
		case instanceMsgUnstructuredData:
			// [uint16 length][data] (same as audio/video in non-single mode)
			if singleMessage {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos:], Seq: seq})
				pos = len(plaintext)
			} else {
				if pos+2 > len(plaintext) {
					break
				}
				dataLen := int(binary.BigEndian.Uint16(plaintext[pos : pos+2]))
				pos += 2
				if pos+dataLen > len(plaintext) {
					dataLen = len(plaintext) - pos
				}
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+dataLen], Seq: seq})
				pos += dataLen
			}
		case instanceMsgCandidatesList:
			// Rest of this message segment — for multi-msg, we read until we can't anymore
			// For simplicity: if single-message, rest is data. Otherwise, parse known format.
			remaining := plaintext[pos:]
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: remaining, Seq: seq})
			pos = len(plaintext) // CandidatesList is always the main message
		case instanceMsgVideoFormats:
			remaining := plaintext[pos:]
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: remaining, Seq: seq})
			pos = len(plaintext)
		case instanceMsgRemoteMediaState:
			// 1 byte state
			if pos < len(plaintext) {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+1], Seq: seq})
				pos++
			}
		case instanceMsgVideoParameters:
			// 4 bytes
			if pos+4 <= len(plaintext) {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+4], Seq: seq})
				pos += 4
			}
		case instanceMsgBatteryLevelIsLow:
			// 1 byte
			if pos < len(plaintext) {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+1], Seq: seq})
				pos++
			}
		case instanceMsgNetworkStatus:
			// 1-2 bytes
			end := pos + 2
			if end > len(plaintext) {
				end = len(plaintext)
			}
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos:end], Seq: seq})
			pos = end
		case instanceMsgRequestVideo:
			// No payload
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: nil, Seq: seq})
		default:
			// Unknown — skip to end
			pos = len(plaintext)
		}
	}

	return messages, nil
}

// sendInstanceImplSignaling sends a binary InstanceImpl message via the signaling channel (MTProto).
func (t *TelegramCore) sendInstanceImplSignaling(call *tgCall, typeID byte, data []byte, requiresAck bool) {
	// Build the message plaintext
	plaintext := instanceImplSerializeMsg(typeID, data, &call.sigEncCounter, requiresAck)

	// Append pending ACKs
	call.mu.Lock()
	acks := call.pendingAcks
	call.pendingAcks = nil
	call.mu.Unlock()
	if len(acks) > 0 {
		// Can't be single-message if we're appending ACKs — clear the bit
		if !requiresAck {
			// Clear single message bit since we're appending more messages
			seq := binary.BigEndian.Uint32(plaintext[:4])
			seq &^= seqSingleMessageBit
			binary.BigEndian.PutUint32(plaintext[:4], seq)
		}
		plaintext = instanceImplAppendAcks(plaintext, acks)
	}

	encrypted, err := tgEncryptInstanceImplSignaling(call.authKey[:], plaintext, call.isOutgoing)
	if err != nil {
		fmt.Printf("[tg-call] InstanceImpl signaling encrypt error: %v\n", err)
		return
	}

	fmt.Printf("[tg-call] InstanceImpl signaling tx: typeID=%d size=%d acks=%d\n", typeID, len(data), len(acks))

	// Check raw output interceptor
	t.rawSigInterceptorsMu.RLock()
	outInterceptor := t.rawSigOutInterceptors[call.id]
	t.rawSigInterceptorsMu.RUnlock()
	if outInterceptor != nil {
		outInterceptor(encrypted)
		return
	}

	_, err = t.api.PhoneSendSignalingData(t.ctx, &tg.PhoneSendSignalingDataRequest{
		Peer: tg.InputPhoneCall{ID: call.id, AccessHash: call.accessHash},
		Data: encrypted,
	})
	if err != nil {
		fmt.Printf("[tg-call] InstanceImpl sendSignaling error: %v\n", err)
	}
}

// sendInstanceImplTransport sends an encrypted message over the raw ICE transport channel.
func (t *TelegramCore) sendInstanceImplTransport(call *tgCall, typeID byte, data []byte) error {
	if call.iceConn == nil {
		return fmt.Errorf("ICE not connected")
	}

	// AudioDataMessage/VideoDataMessage don't require ACK — use single-message packet
	requiresAck := false
	singleMessage := true

	seq := atomic.AddUint32(&call.transportCounter, 1)
	if singleMessage {
		seq |= seqSingleMessageBit
	}
	if requiresAck {
		seq |= seqRequiresAckBit
	}

	plaintext := make([]byte, 4+1+len(data))
	binary.BigEndian.PutUint32(plaintext[:4], seq)
	plaintext[4] = typeID
	copy(plaintext[5:], data)

	encrypted, err := tgEncryptTransport(call.authKey[:], plaintext, call.isOutgoing)
	if err != nil {
		return err
	}

	_, err = call.iceConn.Write(encrypted)
	return err
}

// handleInstanceImplSignaling handles incoming signaling for an InstanceImpl call.
func (t *TelegramCore) handleInstanceImplSignaling(call *tgCall, data []byte) {
	messages, err := tgDecryptInstanceImplSignaling(call.authKey[:], data, call.isOutgoing)
	if err != nil {
		fmt.Printf("[tg-call] InstanceImpl signaling decrypt error: %v\n", err)
		return
	}

	for _, msg := range messages {
		requiresAck := (msg.Seq & seqRequiresAckBit) != 0
		counter := msg.Seq &^ seqSingleMessageBit &^ seqRequiresAckBit

		if requiresAck {
			call.mu.Lock()
			call.pendingAcks = append(call.pendingAcks, msg.Seq)
			call.mu.Unlock()
		}

		switch msg.TypeID {
		case instanceMsgCandidatesList:
			candidates, ufrag, pwd, err := deserializeCandidatesListMsg(msg.Data)
			if err != nil {
				fmt.Printf("[tg-call] InstanceImpl: bad CandidatesList: %v\n", err)
				continue
			}
			fmt.Printf("[tg-call] InstanceImpl: got CandidatesList counter=%d ufrag=%s pwd=%s candidates=%d\n",
				counter, ufrag, pwd, len(candidates))

			call.mu.Lock()
			call.remoteUfrag = ufrag
			call.remotePwd = pwd
			call.mu.Unlock()
			if call.remoteCredsReady != nil {
				select {
				case <-call.remoteCredsReady:
				default:
					close(call.remoteCredsReady)
				}
			}

			// Add remote candidates to ICE agent
			if call.iceAgent != nil {
				for _, candStr := range candidates {
					candStr = strings.TrimPrefix(candStr, "candidate:")
					c, err := ice.UnmarshalCandidate(candStr)
					if err != nil {
						fmt.Printf("[tg-call] InstanceImpl: bad candidate: %v (%s)\n", err, candStr[:min(len(candStr), 80)])
						continue
					}
					if err := call.iceAgent.AddRemoteCandidate(c); err != nil {
						fmt.Printf("[tg-call] InstanceImpl: AddRemoteCandidate error: %v\n", err)
					}
				}
			}

		case instanceMsgVideoFormats:
			fmt.Printf("[tg-call] InstanceImpl: got VideoFormats counter=%d (%d bytes)\n", counter, len(msg.Data))

		case instanceMsgRemoteMediaState:
			if len(msg.Data) >= 1 {
				audioActive := (msg.Data[0] & 1) != 0
				videoState := (msg.Data[0] >> 1) & 0x03
				fmt.Printf("[tg-call] InstanceImpl: got MediaState counter=%d audio=%v video=%d\n", counter, audioActive, videoState)
				// Map binary MediaState to tgMediaState and apply
				ms := tgMediaState{
					Muted: !audioActive,
				}
				switch videoState {
				case 0:
					ms.VideoState = "inactive"
				case 1:
					ms.VideoState = "active"
				case 2:
					ms.VideoState = "paused"
				}
				t.applyRemoteMediaState(call, ms)
			}

		case instanceMsgNetworkStatus:
			fmt.Printf("[tg-call] InstanceImpl: got NetworkStatus counter=%d (%d bytes)\n", counter, len(msg.Data))

		case instanceMsgBatteryLevelIsLow:
			fmt.Printf("[tg-call] InstanceImpl: got BatteryLevelIsLow counter=%d\n", counter)

		case instanceMsgVideoParameters:
			fmt.Printf("[tg-call] InstanceImpl: got VideoParameters counter=%d\n", counter)

		case instanceMsgAck:
			fmt.Printf("[tg-call] InstanceImpl: got ACK counter=%d\n", counter)

		default:
			fmt.Printf("[tg-call] InstanceImpl: unknown typeID=%d counter=%d (%d bytes)\n", msg.TypeID, counter, len(msg.Data))
		}
	}

	// Send pending ACKs immediately via an empty+ack packet
	call.mu.Lock()
	acks := call.pendingAcks
	call.pendingAcks = nil
	call.mu.Unlock()
	if len(acks) > 0 {
		t.sendInstanceImplAcks(call, acks)
	}
}

// sendInstanceImplAcks sends pending ACKs via a signaling empty+ack packet.
func (t *TelegramCore) sendInstanceImplAcks(call *tgCall, acks []uint32) {
	// Empty message: [seq|flags][0xFE] + appended ACKs: [ackSeq][0xFF]...
	seq := atomic.AddUint32(&call.sigEncCounter, 1)
	plaintext := make([]byte, 5)
	binary.BigEndian.PutUint32(plaintext[:4], seq)
	plaintext[4] = instanceMsgEmpty
	plaintext = instanceImplAppendAcks(plaintext, acks)

	encrypted, err := tgEncryptInstanceImplSignaling(call.authKey[:], plaintext, call.isOutgoing)
	if err != nil {
		fmt.Printf("[tg-call] InstanceImpl ACK encrypt error: %v\n", err)
		return
	}
	fmt.Printf("[tg-call] InstanceImpl: sending %d ACKs\n", len(acks))

	t.rawSigInterceptorsMu.RLock()
	outInterceptor := t.rawSigOutInterceptors[call.id]
	t.rawSigInterceptorsMu.RUnlock()
	if outInterceptor != nil {
		outInterceptor(encrypted)
		return
	}
	t.api.PhoneSendSignalingData(t.ctx, &tg.PhoneSendSignalingDataRequest{
		Peer: tg.InputPhoneCall{ID: call.id, AccessHash: call.accessHash},
		Data: encrypted,
	})
}

// parseCallConnectionsForICE converts Telegram connection objects to pion/ice TURN URIs.
func parseCallConnectionsForICE(connections []tg.PhoneConnectionClass) []*stun.URI {
	var urls []*stun.URI
	for _, conn := range connections {
		switch c := conn.(type) {
		case *tg.PhoneConnectionWebrtc:
			if c.Turn {
				uri, err := stun.ParseURI(fmt.Sprintf("turn:%s:%d?transport=udp", c.IP, c.Port))
				if err == nil {
					uri.Username = c.Username
					uri.Password = c.Password
					urls = append(urls, uri)
				}
			}
			if c.Stun {
				uri, err := stun.ParseURI(fmt.Sprintf("stun:%s:%d", c.IP, c.Port))
				if err == nil {
					urls = append(urls, uri)
				}
			}
		}
	}
	return urls
}

// startInstanceImplCall sets up an InstanceImpl call (raw ICE + binary messages).
// Used for v5.0.0 and v2.7.7.
func (t *TelegramCore) startInstanceImplCall(call *tgCall, connections []tg.PhoneConnectionClass, negotiatedVersion string) error {
	t0 := time.Now()
	iceURLs := parseCallConnectionsForICE(connections)
	fmt.Printf("[tg-call] InstanceImpl: starting (version=%s, outgoing=%v, %d ICE URLs)\n",
		negotiatedVersion, call.isOutgoing, len(iceURLs))

	// ICE role: CONTROLLING if outgoing, CONTROLLED if incoming
	// (matching tgcalls NetworkManager: ICEROLE_CONTROLLING for isOutgoing)
	iceRole := ice.AgentConfig{
		Urls:         iceURLs,
		NetworkTypes: []ice.NetworkType{ice.NetworkTypeUDP4},
	}

	// Use relay-only unless P2P allowed
	if !call.p2pAllowed || t.forceRelayICE {
		iceRole.CandidateTypes = []ice.CandidateType{ice.CandidateTypeRelay}
	}

	agent, err := ice.NewAgent(&iceRole)
	if err != nil {
		return fmt.Errorf("InstanceImpl ICE agent: %w", err)
	}
	call.iceAgent = agent
	call.instanceImplReady = make(chan struct{})

	// Gather ICE candidates and send via signaling
	var localCandidates []string
	var gatherDone = make(chan struct{})

	agent.OnCandidate(func(c ice.Candidate) {
		if c == nil {
			// Gathering complete
			close(gatherDone)
			return
		}
		candStr := c.Marshal()
		fmt.Printf("[tg-call] InstanceImpl: local candidate: %s\n", candStr[:min(len(candStr), 80)])
		localCandidates = append(localCandidates, candStr)
	})

	if err := agent.GatherCandidates(); err != nil {
		return fmt.Errorf("InstanceImpl gather: %w", err)
	}

	// Wait for gathering to complete (up to 10s)
	select {
	case <-gatherDone:
	case <-time.After(10 * time.Second):
		fmt.Printf("[tg-call] InstanceImpl: candidate gathering timeout\n")
	}
	fmt.Printf("[tg-call] InstanceImpl: gathered %d candidates (+%dms)\n",
		len(localCandidates), time.Since(t0).Milliseconds())

	// Get local ICE credentials
	localUfrag, localPwd, err := agent.GetLocalUserCredentials()
	if err != nil {
		return fmt.Errorf("InstanceImpl local creds: %w", err)
	}

	// Send CandidatesListMessage via signaling
	candidatesMsg := serializeCandidatesListMsg(localCandidates, localUfrag, localPwd)
	t.sendInstanceImplSignaling(call, instanceMsgCandidatesList, candidatesMsg, true)

	// Start ICE connection in background
	call.remoteCredsReady = make(chan struct{})
	go func() {
		// Wait for remote ufrag/pwd
		select {
		case <-call.remoteCredsReady:
		case <-call.done:
			return
		case <-time.After(10 * time.Second):
		}

		call.mu.Lock()
		remoteUfrag, remotePwd := call.remoteUfrag, call.remotePwd
		call.mu.Unlock()
		if remoteUfrag == "" {
			fmt.Printf("[tg-call] InstanceImpl: timeout waiting for remote ICE credentials\n")
			return
		}

		fmt.Printf("[tg-call] InstanceImpl: connecting ICE (remote ufrag=%s) (+%dms)\n",
			remoteUfrag, time.Since(t0).Milliseconds())

		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		var conn *ice.Conn
		if call.isOutgoing {
			conn, err = agent.Dial(ctx, remoteUfrag, remotePwd)
		} else {
			conn, err = agent.Accept(ctx, remoteUfrag, remotePwd)
		}
		if err != nil {
			fmt.Printf("[tg-call] InstanceImpl: ICE connect error: %v\n", err)
			return
		}
		call.iceConn = conn
		fmt.Printf("[tg-call] InstanceImpl: ICE CONNECTED (+%dms)\n", time.Since(t0).Milliseconds())

		// Mark call as active
		call.mu.Lock()
		call.state = CallStateActive
		call.mu.Unlock()
		t.fireUpdate(Update{
			Type:     UpdateCallState,
			Platform: tgPlatform,
			Call:     &CallSession{ID: strconv.FormatInt(call.id, 10), State: CallStateActive},
		})

		// Send initial signaling messages now that ICE is connected
		t.sendInstanceImplSignaling(call, instanceMsgRemoteMediaState,
			serializeRemoteMediaStateMsg(true, 0), true) // audio=active, video=inactive
		t.sendInstanceImplSignaling(call, instanceMsgVideoFormats,
			serializeVideoFormatsMsg(), true)
		if negotiatedVersion == "5.0.0" {
			t.sendInstanceImplSignaling(call, instanceMsgNetworkStatus,
				serializeNetworkStatusMsg(true, false), true)
		}

		// SSRC assignment based on direction
		var outSSRC, inSSRC uint32
		if call.isOutgoing {
			outSSRC = instanceSSRCAudioOutgoing // 2
			inSSRC = instanceSSRCAudioIncoming  // 1
		} else {
			outSSRC = instanceSSRCAudioIncoming // 1
			inSSRC = instanceSSRCAudioOutgoing  // 2
		}
		_ = inSSRC // used in receive loop

		// Start sending audio (opus silence) via transport
		go func() {
			silence := []byte{0xF8, 0xFF, 0xFE} // opus silence frame
			var rtpSeq uint16
			var rtpTS uint32
			tick := time.NewTicker(20 * time.Millisecond)
			defer tick.Stop()

			for {
				select {
				case <-call.done:
					return
				case <-tick.C:
				}
				if call.iceConn == nil {
					return
				}
				rtpSeq++
				rtpTS += 960

				// Build RTP packet
				rtp := &pionrtp.Packet{
					Header: pionrtp.Header{
						Version:        2,
						PayloadType:    111, // opus
						SequenceNumber: rtpSeq,
						Timestamp:      rtpTS,
						SSRC:           outSSRC,
					},
					Payload: silence,
				}
				rtpBytes, err := rtp.Marshal()
				if err != nil {
					continue
				}

				if err := t.sendInstanceImplTransport(call, instanceMsgAudioData, rtpBytes); err != nil {
					if rtpSeq%100 == 0 {
						fmt.Printf("[tg-call] InstanceImpl: transport send error: %v\n", err)
					}
					return
				}
				if rtpSeq%500 == 0 || rtpSeq == 1 {
					fmt.Printf("[tg-call] InstanceImpl: sent %d audio frames (SSRC=%d)\n", rtpSeq, outSSRC)
				}
			}
		}()

		// Receive loop — read encrypted packets from ICE transport
		go func() {
			buf := make([]byte, 2000)
			for {
				select {
				case <-call.done:
					return
				default:
				}
				n, err := conn.Read(buf)
				if err != nil {
					fmt.Printf("[tg-call] InstanceImpl: transport read error: %v\n", err)
					return
				}
				if n < 21 {
					continue
				}

				messages, err := tgDecryptTransport(call.authKey[:], buf[:n], call.isOutgoing)
				if err != nil {
					// Might be retransmitted/duplicate packet
					continue
				}

				for _, msg := range messages {
					switch msg.TypeID {
					case instanceMsgAudioData:
						if call.onAudioFrame != nil && len(msg.Data) > 0 {
							call.onAudioFrame(msg.Data)
						}
					case instanceMsgVideoData:
						// Ignore video for now
					case instanceMsgRemoteMediaState:
						if len(msg.Data) >= 1 {
							fmt.Printf("[tg-call] InstanceImpl transport: MediaState audio=%v\n", (msg.Data[0]&1) != 0)
						}
					default:
						fmt.Printf("[tg-call] InstanceImpl transport: typeID=%d (%d bytes)\n", msg.TypeID, len(msg.Data))
					}
				}
			}
		}()
	}()

	return nil
}

// extractWebInitialSetupFromSDP parses a pion SDP into a Web-style InitialSetup
// with inline audio/video/screencast media content (for Telegram Web v4.0.0 compatibility).
// Web expects all 3 media sections even if we only send audio.
func extractWebInitialSetupFromSDP(sdp string, isOutgoing bool) *tgInitialSetup {
	v2Setup, v2NC := extractV2ImplFromSDP(sdp, isOutgoing)

	// Populate media sections from parsed SDP contents
	for _, content := range v2NC.Contents {
		pts := content.PayloadTypes
		if pts == nil {
			pts = []tgPayloadType{}
		}
		exts := content.RTPExtensions
		if exts == nil {
			exts = []tgRTPExtension{}
		}

		// Convert V2Impl SSRCGroups to Web SSRCGroups
		var webGroups []tgWebSSRCGroup
		for _, g := range content.SSRCGroups {
			var intSSRCs []int
			for _, s := range g.SSRCs {
				v, verr := tgMsgID(s)
				if verr != nil {
					continue
				}
				intSSRCs = append(intSSRCs, v)
			}
			webGroups = append(webGroups, tgWebSSRCGroup{Semantics: g.Semantics, SSRCs: intSSRCs})
		}
		if webGroups == nil {
			webGroups = []tgWebSSRCGroup{}
		}

		switch content.Type {
		case "audio":
			v2Setup.Audio = &tgMediaDesc{
				SSRC:          content.SSRC,
				SSRCGroups:    webGroups,
				PayloadTypes:  pts,
				RTPExtensions: exts,
			}
		case "video":
			desc := &tgMediaDesc{
				SSRC:          content.SSRC,
				SSRCGroups:    webGroups,
				PayloadTypes:  pts,
				RTPExtensions: exts,
			}
			if v2Setup.Video == nil {
				v2Setup.Video = desc // first video → camera
			} else {
				v2Setup.Screencast = desc // second video → screencast
			}
		}
	}

	// VP8 video payload types (standard WebRTC)
	vp8PayloadTypes := []tgPayloadType{
		{
			ID: 96, Name: "VP8", Clockrate: 90000, Channels: 0,
			FeedbackTypes: []tgFeedbackType{
				{Type: "goog-remb"},
				{Type: "transport-cc"},
				{Type: "ccm", Subtype: "fir"},
				{Type: "nack"},
				{Type: "nack", Subtype: "pli"},
			},
		},
		{
			ID: 97, Name: "rtx", Clockrate: 90000, Channels: 0,
			Parameters: map[string]string{"apt": "96"},
		},
	}
	videoExtensions := []tgRTPExtension{
		{ID: 2, URI: "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time"},
		{ID: 3, URI: "http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01"},
	}

	// If no real video track in SDP, generate dummy video SSRCs (Web expects them always)
	if v2Setup.Video == nil {
		var eidBuf [4]byte
		rand.Read(eidBuf[:])
		videoSSRC := binary.BigEndian.Uint32(eidBuf[:])
		rand.Read(eidBuf[:])
		rtxSSRC := binary.BigEndian.Uint32(eidBuf[:])
		v2Setup.Video = &tgMediaDesc{
			SSRC: strconv.FormatUint(uint64(videoSSRC), 10),
			SSRCGroups: []tgWebSSRCGroup{{
				Semantics: "FID",
				SSRCs:     []int{int(videoSSRC), int(rtxSSRC)},
			}},
			PayloadTypes:  vp8PayloadTypes,
			RTPExtensions: videoExtensions,
		}
	}

	// Generate screencast SSRCs if not already populated from SDP (e.g., from a third m=video section)
	if v2Setup.Screencast == nil {
		var eidBuf [4]byte
		rand.Read(eidBuf[:])
		screenSSRC := binary.BigEndian.Uint32(eidBuf[:])
		rand.Read(eidBuf[:])
		screenRtxSSRC := binary.BigEndian.Uint32(eidBuf[:])
		v2Setup.Screencast = &tgMediaDesc{
			SSRC: strconv.FormatUint(uint64(screenSSRC), 10),
			SSRCGroups: []tgWebSSRCGroup{{
				Semantics: "FID",
				SSRCs:     []int{int(screenSSRC), int(screenRtxSSRC)},
			}},
			PayloadTypes:  vp8PayloadTypes,
			RTPExtensions: videoExtensions,
		}
	}

	return v2Setup
}

// buildSyntheticSDPFromWebSetup constructs a synthetic SDP from a Web-style InitialSetup
// (v4.0.0 format with inline audio/video/screencast media content).
func buildSyntheticSDPFromWebSetup(setup *tgInitialSetup, sdpType string) string {
	// Convert web InitialSetup to V2Impl format and reuse the existing SDP builder
	nc := &tgNegotiateChannels{
		Type: "NegotiateChannels",
	}
	if setup.Audio != nil {
		nc.Contents = append(nc.Contents, tgMediaContent{
			Type:          "audio",
			SSRC:          setup.Audio.SSRC,
			PayloadTypes:  setup.Audio.PayloadTypes,
			RTPExtensions: setup.Audio.RTPExtensions,
		})
	}
	if setup.Video != nil {
		// Convert WebSSRCGroups to V2Impl SSRCGroups
		var groups []tgSSRCGroup
		for _, wg := range setup.Video.SSRCGroups {
			var ssrcs []string
			for _, s := range wg.SSRCs {
				ssrcs = append(ssrcs, strconv.Itoa(s))
			}
			groups = append(groups, tgSSRCGroup{Semantics: wg.Semantics, SSRCs: ssrcs})
		}
		nc.Contents = append(nc.Contents, tgMediaContent{
			Type:          "video",
			SSRC:          setup.Video.SSRC,
			SSRCGroups:    groups,
			PayloadTypes:  setup.Video.PayloadTypes,
			RTPExtensions: setup.Video.RTPExtensions,
		})
	}
	if setup.Screencast != nil {
		var groups []tgSSRCGroup
		for _, wg := range setup.Screencast.SSRCGroups {
			var ssrcs []string
			for _, s := range wg.SSRCs {
				ssrcs = append(ssrcs, strconv.Itoa(s))
			}
			groups = append(groups, tgSSRCGroup{Semantics: wg.Semantics, SSRCs: ssrcs})
		}
		nc.Contents = append(nc.Contents, tgMediaContent{
			Type:          "video",
			SSRC:          setup.Screencast.SSRC,
			SSRCGroups:    groups,
			PayloadTypes:  setup.Screencast.PayloadTypes,
			RTPExtensions: setup.Screencast.RTPExtensions,
		})
	}
	sdp := buildSyntheticSDPFromV2Impl(setup, nc, sdpType)

	// Append SCTP data channel m-line for Web signaling.
	// telegram-tt creates a negotiated data channel (id=0) and expects it in the SDP.
	// Also patch the BUNDLE group to include the data channel MID.
	dcMID := strconv.Itoa(len(nc.Contents))
	// Append data channel MID to BUNDLE group line
	if i := strings.Index(sdp, "a=group:BUNDLE "); i >= 0 {
		if eol := strings.Index(sdp[i:], "\r\n"); eol >= 0 {
			pos := i + eol
			sdp = sdp[:pos] + " " + dcMID + sdp[pos:]
		}
	}
	var dcSB strings.Builder
	dcSB.WriteString("m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n")
	dcSB.WriteString("c=IN IP4 0.0.0.0\r\n")
	dcSB.WriteString("a=ice-ufrag:" + setup.Ufrag + "\r\n")
	dcSB.WriteString("a=ice-pwd:" + setup.Pwd + "\r\n")
	if len(setup.Fingerprints) > 0 {
		fp := setup.Fingerprints[0]
		dcSB.WriteString("a=fingerprint:" + fp.Hash + " " + fp.Fingerprint + "\r\n")
		dcSB.WriteString("a=setup:" + fp.Setup + "\r\n")
	}
	dcSB.WriteString("a=mid:" + dcMID + "\r\n")
	dcSB.WriteString("a=sctp-port:5000\r\n")
	dcSB.WriteString("a=max-message-size:262144\r\n")
	sdp += dcSB.String()
	return sdp
}

// extractV2ImplFromSDP parses a pion SDP into InitialSetup and NegotiateChannels messages
// for sending to a remote V2Impl client.
func extractV2ImplFromSDP(sdp string, isOutgoing bool) (*tgInitialSetup, *tgNegotiateChannels) {
	setup := &tgInitialSetup{
		Type: "InitialSetup",
	}

	// Parse ICE ufrag/pwd
	for _, line := range strings.Split(sdp, "\r\n") {
		if strings.HasPrefix(line, "a=ice-ufrag:") {
			setup.Ufrag = strings.TrimPrefix(line, "a=ice-ufrag:")
		} else if strings.HasPrefix(line, "a=ice-pwd:") {
			setup.Pwd = strings.TrimPrefix(line, "a=ice-pwd:")
		} else if strings.HasPrefix(line, "a=fingerprint:") {
			// Format: a=fingerprint:sha-256 XX:XX:XX:...
			parts := strings.SplitN(strings.TrimPrefix(line, "a=fingerprint:"), " ", 2)
			if len(parts) == 2 {
				dtlsSetup := "actpass"
				if !isOutgoing {
					dtlsSetup = "active" // pion defaults to active when answering
				}
				// Check actual setup line
				for _, l2 := range strings.Split(sdp, "\r\n") {
					if strings.HasPrefix(l2, "a=setup:") {
						dtlsSetup = strings.TrimPrefix(l2, "a=setup:")
						break
					}
				}
				setup.Fingerprints = append(setup.Fingerprints, tgDTLSFingerprint{
					Hash:        parts[0],
					Setup:       dtlsSetup,
					Fingerprint: parts[1],
				})
			}
		}
	}

	// Parse all m= sections (audio, video) into NegotiateChannels contents
	nc := &tgNegotiateChannels{
		Type:       "NegotiateChannels",
		ExchangeID: "1",
	}

	// Track current m= section and its content
	type mSection struct {
		mediaType string // "audio" or "video"
		content   tgMediaContent
		ssrcGroup []tgSSRCGroup
	}
	var sections []mSection
	currentIdx := -1

	for _, line := range strings.Split(sdp, "\r\n") {
		if strings.HasPrefix(line, "m=audio ") {
			sections = append(sections, mSection{mediaType: "audio", content: tgMediaContent{Type: "audio"}})
			currentIdx = len(sections) - 1
			continue
		} else if strings.HasPrefix(line, "m=video ") {
			sections = append(sections, mSection{mediaType: "video", content: tgMediaContent{Type: "video"}})
			currentIdx = len(sections) - 1
			continue
		} else if strings.HasPrefix(line, "m=") {
			currentIdx = -1 // data channel or other — skip
			continue
		}

		if currentIdx < 0 {
			continue
		}
		sec := &sections[currentIdx]

		if strings.HasPrefix(line, "a=ssrc-group:") {
			// a=ssrc-group:FID 12345 67890
			trimmed := strings.TrimPrefix(line, "a=ssrc-group:")
			parts := strings.SplitN(trimmed, " ", 2)
			if len(parts) == 2 {
				ssrcs := strings.Fields(parts[1])
				sec.ssrcGroup = append(sec.ssrcGroup, tgSSRCGroup{
					Semantics: parts[0],
					SSRCs:     ssrcs,
				})
			}
		} else if strings.HasPrefix(line, "a=ssrc:") {
			// a=ssrc:12345 cname:...
			parts := strings.SplitN(strings.TrimPrefix(line, "a=ssrc:"), " ", 2)
			if len(parts) >= 1 && sec.content.SSRC == "" {
				sec.content.SSRC = parts[0]
			}
		} else if strings.HasPrefix(line, "a=rtpmap:") {
			// a=rtpmap:111 opus/48000/2 or a=rtpmap:96 VP8/90000
			trimmed := strings.TrimPrefix(line, "a=rtpmap:")
			parts := strings.SplitN(trimmed, " ", 2)
			if len(parts) != 2 {
				continue
			}
			ptID := 0
			fmt.Sscanf(parts[0], "%d", &ptID)

			codecParts := strings.Split(parts[1], "/")
			name := codecParts[0]
			clockrate := 0
			channels := 0
			if len(codecParts) >= 2 {
				fmt.Sscanf(codecParts[1], "%d", &clockrate)
			}
			if len(codecParts) >= 3 {
				fmt.Sscanf(codecParts[2], "%d", &channels)
			}

			// Filter codecs: opus for audio, VP8/VP9/H264/rtx for video
			include := false
			if sec.mediaType == "audio" {
				include = strings.EqualFold(name, "opus")
			} else if sec.mediaType == "video" {
				include = strings.EqualFold(name, "VP8") || strings.EqualFold(name, "VP9") ||
					strings.EqualFold(name, "H264") || strings.EqualFold(name, "rtx")
			}
			if include {
				pt := tgPayloadType{
					ID:        ptID,
					Name:      name,
					Clockrate: clockrate,
					Channels:  channels,
				}
				sec.content.PayloadTypes = append(sec.content.PayloadTypes, pt)
			}
		} else if strings.HasPrefix(line, "a=fmtp:") {
			trimmed := strings.TrimPrefix(line, "a=fmtp:")
			parts := strings.SplitN(trimmed, " ", 2)
			if len(parts) != 2 {
				continue
			}
			ptID := 0
			fmt.Sscanf(parts[0], "%d", &ptID)
			for i := range sec.content.PayloadTypes {
				if sec.content.PayloadTypes[i].ID == ptID {
					if sec.content.PayloadTypes[i].Parameters == nil {
						sec.content.PayloadTypes[i].Parameters = make(map[string]string)
					}
					for _, param := range strings.Split(parts[1], ";") {
						kv := strings.SplitN(strings.TrimSpace(param), "=", 2)
						if len(kv) == 2 {
							sec.content.PayloadTypes[i].Parameters[kv[0]] = kv[1]
						}
					}
				}
			}
		} else if strings.HasPrefix(line, "a=rtcp-fb:") {
			trimmed := strings.TrimPrefix(line, "a=rtcp-fb:")
			parts := strings.SplitN(trimmed, " ", 3)
			if len(parts) < 2 {
				continue
			}
			ptID := 0
			fmt.Sscanf(parts[0], "%d", &ptID)
			for i := range sec.content.PayloadTypes {
				if sec.content.PayloadTypes[i].ID == ptID {
					fb := tgFeedbackType{Type: parts[1]}
					if len(parts) >= 3 {
						fb.Subtype = parts[2]
					}
					sec.content.PayloadTypes[i].FeedbackTypes = append(sec.content.PayloadTypes[i].FeedbackTypes, fb)
				}
			}
		} else if strings.HasPrefix(line, "a=extmap:") {
			trimmed := strings.TrimPrefix(line, "a=extmap:")
			parts := strings.SplitN(trimmed, " ", 2)
			if len(parts) != 2 {
				continue
			}
			extID := 0
			fmt.Sscanf(parts[0], "%d", &extID)
			uri := parts[1]
			// Only include extensions tgcalls recognizes
			switch {
			case strings.Contains(uri, "abs-send-time"),
				strings.Contains(uri, "transport-wide-cc"):
				sec.content.RTPExtensions = append(sec.content.RTPExtensions, tgRTPExtension{
					ID:  extID,
					URI: uri,
				})
			}
		}
	}

	// Build contents list, prune dangling RTX, and attach SSRC groups
	for _, sec := range sections {
		content := sec.content
		content.SSRCGroups = sec.ssrcGroup
		// Remove RTX codecs whose apt references a non-included primary codec.
		// pion may register AV1/H265 internally but we only include VP8/VP9/H264 —
		// dangling RTX entries (apt→nonexistent PT) can cause Chrome to reject the SDP.
		primaryPTs := make(map[int]bool)
		for _, pt := range content.PayloadTypes {
			if !strings.EqualFold(pt.Name, "rtx") {
				primaryPTs[pt.ID] = true
			}
		}
		var filtered []tgPayloadType
		for _, pt := range content.PayloadTypes {
			if strings.EqualFold(pt.Name, "rtx") {
				aptStr := pt.Parameters["apt"]
				aptID := 0
				fmt.Sscanf(aptStr, "%d", &aptID)
				if !primaryPTs[aptID] {
					continue // dangling RTX — skip
				}
			}
			filtered = append(filtered, pt)
		}
		content.PayloadTypes = filtered
		nc.Contents = append(nc.Contents, content)
	}
	return setup, nc
}

// buildSyntheticSDPFromV2Impl constructs a synthetic SDP from remote InitialSetup + NegotiateChannels.
// sdpType is "offer" or "answer" and determines the SDP type semantics.
// localAudioSSRC is our own SSRC — if the remote's SSRC matches, it's echoed back and should be skipped.
// extractRemoteVideoSSRCs parses a remote SDP and sets remoteVideoSSRC / remoteScreenSSRC
// on the call for incoming track dispatch. The 1st video m-line SSRC = camera, 2nd = screencast.
func extractRemoteVideoSSRCs(call *tgCall, sdp string) {
	videoIdx := 0
	inVideo := false
	for _, line := range strings.Split(sdp, "\r\n") {
		if strings.HasPrefix(line, "m=video") {
			inVideo = true
		} else if strings.HasPrefix(line, "m=") {
			inVideo = false
		}
		if inVideo && strings.HasPrefix(line, "a=ssrc:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				ssrcStr := strings.TrimPrefix(parts[0], "a=ssrc:")
				var ssrc uint32
				fmt.Sscanf(ssrcStr, "%d", &ssrc)
				if ssrc != 0 {
					if videoIdx == 0 {
						call.remoteVideoSSRC = ssrc
					} else if videoIdx == 1 && call.remoteScreenSSRC == 0 {
						call.remoteScreenSSRC = ssrc
					}
					videoIdx++
					inVideo = false // move to next m-line
				}
			}
		}
	}
	if call.remoteScreenSSRC != 0 {
		fmt.Printf("[tg-call] V2Ref: remote SSRCs: video=%d screencast=%d\n", call.remoteVideoSSRC, call.remoteScreenSSRC)
	}
}

func buildSyntheticSDPFromV2Impl(setup *tgInitialSetup, nc *tgNegotiateChannels, sdpType string, localAudioSSRC ...uint32) string {
	var sb strings.Builder

	sb.WriteString("v=0\r\n")
	sb.WriteString("o=- 0 0 IN IP4 0.0.0.0\r\n")
	sb.WriteString("s=-\r\n")
	sb.WriteString("t=0 0\r\n")

	// BUNDLE group with MIDs — include all content types
	var mids []string
	for i, content := range nc.Contents {
		if content.Type == "audio" || content.Type == "video" {
			mids = append(mids, strconv.Itoa(i))
		}
	}
	if len(mids) == 0 {
		mids = []string{"0"}
	}
	sb.WriteString("a=group:BUNDLE " + strings.Join(mids, " ") + "\r\n")
	sb.WriteString("a=ice-options:trickle\r\n")
	sb.WriteString("a=msid-semantic: WMS *\r\n")

	// ICE credentials (session-level)
	sb.WriteString("a=ice-ufrag:" + setup.Ufrag + "\r\n")
	sb.WriteString("a=ice-pwd:" + setup.Pwd + "\r\n")

	// DTLS fingerprint
	if len(setup.Fingerprints) > 0 {
		fp := setup.Fingerprints[0]
		sb.WriteString("a=fingerprint:" + fp.Hash + " " + fp.Fingerprint + "\r\n")
		sb.WriteString("a=setup:" + fp.Setup + "\r\n")
	}

	// Build m-lines from NegotiateChannels contents
	midIdx := 0
	for _, content := range nc.Contents {
		if content.Type != "audio" && content.Type != "video" {
			continue
		}

		// Collect payload type IDs
		var ptIDs []string
		for _, pt := range content.PayloadTypes {
			ptIDs = append(ptIDs, strconv.Itoa(pt.ID))
		}
		if len(ptIDs) == 0 {
			if content.Type == "audio" {
				ptIDs = []string{"111"} // fallback opus
			} else {
				ptIDs = []string{"96"} // fallback VP8
			}
		}

		sb.WriteString("m=" + content.Type + " 9 UDP/TLS/RTP/SAVPF " + strings.Join(ptIDs, " ") + "\r\n")
		sb.WriteString("c=IN IP4 0.0.0.0\r\n")
		sb.WriteString("a=rtcp:9 IN IP4 0.0.0.0\r\n")

		// ICE credentials (media-level, same as session)
		sb.WriteString("a=ice-ufrag:" + setup.Ufrag + "\r\n")
		sb.WriteString("a=ice-pwd:" + setup.Pwd + "\r\n")

		// Fingerprint at media level too
		if len(setup.Fingerprints) > 0 {
			fp := setup.Fingerprints[0]
			sb.WriteString("a=fingerprint:" + fp.Hash + " " + fp.Fingerprint + "\r\n")
			sb.WriteString("a=setup:" + fp.Setup + "\r\n")
		}

		sb.WriteString("a=mid:" + strconv.Itoa(midIdx) + "\r\n")
		midIdx++
		sb.WriteString("a=rtcp-mux\r\n")
		sb.WriteString("a=sendrecv\r\n")

		// RTP extensions
		for _, ext := range content.RTPExtensions {
			sb.WriteString("a=extmap:" + strconv.Itoa(ext.ID) + " " + ext.URI + "\r\n")
		}

		// Codec definitions
		for _, pt := range content.PayloadTypes {
			channels := ""
			if pt.Channels > 0 {
				channels = "/" + strconv.Itoa(pt.Channels)
			}
			sb.WriteString("a=rtpmap:" + strconv.Itoa(pt.ID) + " " + pt.Name + "/" + strconv.Itoa(pt.Clockrate) + channels + "\r\n")

			// fmtp parameters
			if len(pt.Parameters) > 0 {
				var params []string
				for k, v := range pt.Parameters {
					params = append(params, k+"="+v)
				}
				sb.WriteString("a=fmtp:" + strconv.Itoa(pt.ID) + " " + strings.Join(params, ";") + "\r\n")
			}

			// RTCP feedback
			for _, fb := range pt.FeedbackTypes {
				fbStr := "a=rtcp-fb:" + strconv.Itoa(pt.ID) + " " + fb.Type
				if fb.Subtype != "" {
					fbStr += " " + fb.Subtype
				}
				sb.WriteString(fbStr + "\r\n")
			}
		}

		// Include remote SSRC unless it matches our own (Desktop echoes our SSRC in answers).
		skipSSRC := false
		if len(localAudioSSRC) > 0 && content.SSRC != "" {
			remoteSSRC := uint32(0)
			fmt.Sscanf(content.SSRC, "%d", &remoteSSRC)
			if remoteSSRC == localAudioSSRC[0] {
				skipSSRC = true
				fmt.Printf("[tg-call] V2Impl: skipping echoed SSRC %s in synthetic %s SDP\n", content.SSRC, sdpType)
			}
		}
		if content.SSRC != "" && !skipSSRC {
			trackLabel := "remote-audio"
			if content.Type == "video" {
				trackLabel = "remote-video"
			}
			sb.WriteString("a=ssrc:" + content.SSRC + " cname:remote\r\n")
			sb.WriteString("a=ssrc:" + content.SSRC + " msid:remote-stream " + trackLabel + "\r\n")
			// SSRC groups (FID for RTX pairing)
			for _, group := range content.SSRCGroups {
				if len(group.SSRCs) > 0 {
					sb.WriteString("a=ssrc-group:" + group.Semantics + " " + strings.Join(group.SSRCs, " ") + "\r\n")
				}
			}
		}
	}

	return sb.String()
}

// tgcalls signaling encryption (AES-256-CTR, matching CryptoHelper.cpp).
func tgPrepareAesKeyIv(key []byte, msgKey []byte, x int) (aesKey [32]byte, aesIv [16]byte) {
	h := sha256.New()
	h.Write(msgKey[:16])
	h.Write(key[x : x+36])
	sha256a := h.Sum(nil)

	h.Reset()
	h.Write(key[40+x : 40+x+36])
	h.Write(msgKey[:16])
	sha256b := h.Sum(nil)

	copy(aesKey[0:8], sha256a[0:8])
	copy(aesKey[8:24], sha256b[8:24])
	copy(aesKey[24:32], sha256a[24:32])

	copy(aesIv[0:4], sha256b[0:4])
	copy(aesIv[4:12], sha256a[8:16])
	copy(aesIv[12:16], sha256b[24:28])
	return
}

// tgEncryptSignaling encrypts signaling data.
// Two framing modes:
//   - V2 (tgcalls C++): [4-byte seq|flags][0x7F][4-byte length][data] — used for desktop/mobile
//   - Web (gramjs):      [4-byte seq][data] — used for Telegram Web (version 4.0.x)
// Then AES-CTR encrypted with 16-byte msgKey prepended.
func tgEncryptSignaling(key []byte, data []byte, isOutgoing bool, counter *uint32, webMode bool) ([]byte, error) {
	x := 128 // signaling outgoing
	if !isOutgoing {
		x = 136
	}

	seq := atomic.AddUint32(counter, 1)

	var plaintext []byte
	if webMode {
		// Web mode: [4-byte LE seq][raw JSON data][padding to 4-byte boundary with 0x20]
		rawLen := 4 + len(data)
		padLen := 0
		if rawLen%4 != 0 {
			padLen = 4 - (rawLen % 4)
		}
		plaintext = make([]byte, rawLen+padLen)
		binary.LittleEndian.PutUint32(plaintext[:4], seq)
		copy(plaintext[4:], data)
		for i := rawLen; i < rawLen+padLen; i++ {
			plaintext[i] = 0x20
		}
	} else {
		// V2 mode: [4-byte seq|flags][0x7F type][4-byte length][data]
		seqWithFlags := seq | 0x40000000
		plaintext = make([]byte, 4+1+4+len(data))
		binary.BigEndian.PutUint32(plaintext[:4], seqWithFlags)
		plaintext[4] = 0x7F // kCustomId
		binary.BigEndian.PutUint32(plaintext[5:9], uint32(len(data)))
		copy(plaintext[9:], data)
	}

	// msgKey = SHA256(key[88+x:88+x+32] || plaintext)[8:24]
	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	msgKeyLarge := h.Sum(nil)
	msgKey := msgKeyLarge[8:24]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)

	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	ciphertext := make([]byte, len(plaintext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(ciphertext, plaintext)

	// packet = msgKey || ciphertext
	packet := make([]byte, 16+len(ciphertext))
	copy(packet[:16], msgKey)
	copy(packet[16:], ciphertext)
	return packet, nil
}

// tgDecryptSignaling decrypts incoming signaling data and extracts all messages.
// V2 packets can contain multiple messages: [seq1][type1][...][seq2][type2][...]
// Message types: 0x7F=kCustomId (data), 0xFE=kEmptyId, 0xFF=kAckId
// Returns all kCustomId message payloads and seqs needing ACK (seqRequiresAckBit set).
func tgDecryptSignaling(key []byte, packet []byte, isOutgoing bool, v1Framing ...bool) ([][]byte, []uint32, error) {
	if len(packet) < 21 { // 16 msgKey + 4 seq + at least 1 byte
		return nil, nil, fmt.Errorf("signaling packet too short: %d bytes", len(packet))
	}

	// For decryption, swap direction: our outgoing = their incoming
	x := 136 // incoming signaling for outgoing side
	if !isOutgoing {
		x = 128 // incoming signaling for incoming side
	}

	msgKey := packet[:16]
	ciphertext := packet[16:]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)

	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, nil, err
	}
	plaintext := make([]byte, len(ciphertext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(plaintext, ciphertext)

	// Verify msgKey
	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	check := h.Sum(nil)
	if !bytes.Equal(check[8:24], msgKey) {
		return nil, nil, fmt.Errorf("signaling decryption: msgKey mismatch")
	}

	if len(plaintext) < 5 {
		return nil, nil, fmt.Errorf("decrypted payload too short")
	}

	// V1 framing: [4-byte seq][raw payload] — single message, no type/length, no ACKs
	if len(v1Framing) > 0 && v1Framing[0] {
		return [][]byte{plaintext[4:]}, nil, nil
	}

	// Parse V2 multi-message packet: [seq][type][...][seq][type][...]
	var messages [][]byte
	var ackSeqs []uint32

	// First seq at offset 0
	firstSeq := binary.BigEndian.Uint32(plaintext[:4])
	if firstSeq&seqRequiresAckBit != 0 {
		ackSeqs = append(ackSeqs, firstSeq) // keep full seq including flags — C++ matches WITH flags
	}
	pos := 4

	for pos < len(plaintext) {
		if pos+1 > len(plaintext) {
			break
		}
		typeID := plaintext[pos]
		pos++

		switch typeID {
		case 0xFE: // kEmptyId — empty message, skip
			// No payload
		case 0xFF: // kAckId — ACK, skip (no payload)
			// No payload
		case 0x7F: // kCustomId — raw message with [length][data]
			if pos+4 > len(plaintext) {
				break
			}
			dataLen := int(binary.BigEndian.Uint32(plaintext[pos : pos+4]))
			pos += 4
			if pos+dataLen > len(plaintext) {
				// Truncated — take what we can
				if pos < len(plaintext) {
					messages = append(messages, plaintext[pos:])
				}
				pos = len(plaintext)
				break
			}
			messages = append(messages, plaintext[pos:pos+dataLen])
			pos += dataLen
		default:
			// Unknown type — skip to end (can't determine length)
			pos = len(plaintext)
		}

		// After processing a message, check for next seq + type
		if pos+5 <= len(plaintext) {
			// Next message has [4-byte seq][1-byte type]
			nextSeq := binary.BigEndian.Uint32(plaintext[pos : pos+4])
			if nextSeq&seqRequiresAckBit != 0 {
				ackSeqs = append(ackSeqs, nextSeq) // keep full seq including flags — C++ matches WITH flags
			}
			pos += 4
		} else {
			break
		}
	}

	if len(messages) == 0 {
		// No kCustomId messages — packet was only ACKs/empty. Return empty.
		return nil, ackSeqs, nil
	}
	return messages, ackSeqs, nil
}

// --- V2 signaling encryption (version 11.0.0) ---
// V2 uses simpler framing than V1: just [4-byte seq][data], SCTP handles reliability.

func tgEncryptV2Packet(key []byte, data []byte, isOutgoing bool, counter *uint32) ([]byte, error) {
	x := 128 // signaling
	if !isOutgoing {
		x = 136
	}

	seq := atomic.AddUint32(counter, 1)

	// Plaintext: [4-byte BE seq][data]
	plaintext := make([]byte, 4+len(data))
	binary.BigEndian.PutUint32(plaintext[:4], seq)
	copy(plaintext[4:], data)

	// msgKey = SHA256(key[88+x:88+x+32] || plaintext)[8:24]
	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	msgKeyLarge := h.Sum(nil)
	msgKey := msgKeyLarge[8:24]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)

	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	ciphertext := make([]byte, len(plaintext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(ciphertext, plaintext)

	packet := make([]byte, 16+len(ciphertext))
	copy(packet[:16], msgKey)
	copy(packet[16:], ciphertext)
	return packet, nil
}

func tgDecryptV2Packet(key []byte, packet []byte, isOutgoing bool) ([]byte, error) {
	if len(packet) < 21 { // 16 msgKey + 4 seq + at least 1 byte
		return nil, fmt.Errorf("V2 packet too short: %d bytes", len(packet))
	}

	// For decryption, swap direction
	x := 136 // incoming for outgoing side
	if !isOutgoing {
		x = 128 // incoming for incoming side
	}

	msgKey := packet[:16]
	ciphertext := packet[16:]

	aesKey, aesIv := tgPrepareAesKeyIv(key, msgKey, x)

	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		return nil, err
	}
	plaintext := make([]byte, len(ciphertext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(plaintext, ciphertext)

	// Verify msgKey
	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	check := h.Sum(nil)
	if !bytes.Equal(check[8:24], msgKey) {
		return nil, fmt.Errorf("V2 decryption: msgKey mismatch")
	}

	// Strip 4-byte seq, return payload
	return plaintext[4:], nil
}

func gzipCompress(data []byte) ([]byte, error) {
	var buf bytes.Buffer
	w := gzip.NewWriter(&buf)
	if _, err := w.Write(data); err != nil {
		return nil, err
	}
	if err := w.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// --- SCTP signaling transport (version 11.0.0) ---
// sctpSignalingConn implements net.Conn, bridging pion/sctp ↔ MTProto signaling.
// Write() sends raw SCTP packets via MTProto phone.sendSignalingData.
// Read() blocks until MTProto signaling data arrives and feeds it.

type sctpSignalingConn struct {
	packets chan []byte    // incoming SCTP packets (preserves packet boundaries)
	sendFn  func([]byte)  // sends raw SCTP packets via MTProto
	closed  int32         // atomic
}

func newSctpSignalingConn(sendFn func([]byte)) *sctpSignalingConn {
	return &sctpSignalingConn{
		packets: make(chan []byte, 256),
		sendFn:  sendFn,
	}
}

// feed is called when raw SCTP packets arrive from MTProto signaling.
func (c *sctpSignalingConn) feed(data []byte) {
	if atomic.LoadInt32(&c.closed) != 0 {
		return
	}
	cp := make([]byte, len(data))
	copy(cp, data)
	select {
	case c.packets <- cp:
	default:
		fmt.Printf("[tg-call] SCTP packet dropped (channel full)\n")
	}
}

func (c *sctpSignalingConn) Read(p []byte) (int, error) {
	pkt, ok := <-c.packets
	if !ok || atomic.LoadInt32(&c.closed) != 0 {
		return 0, io.EOF
	}
	n := copy(p, pkt)
	return n, nil
}

func (c *sctpSignalingConn) Write(p []byte) (int, error) {
	if atomic.LoadInt32(&c.closed) != 0 {
		return 0, io.EOF
	}
	cp := make([]byte, len(p))
	copy(cp, p)
	c.sendFn(cp)
	return len(p), nil
}

func (c *sctpSignalingConn) Close() error {
	if atomic.CompareAndSwapInt32(&c.closed, 0, 1) {
		close(c.packets)
	}
	return nil
}

func (c *sctpSignalingConn) LocalAddr() net.Addr               { return sctpAddr{} }
func (c *sctpSignalingConn) RemoteAddr() net.Addr              { return sctpAddr{} }
func (c *sctpSignalingConn) SetDeadline(t time.Time) error      { return nil }
func (c *sctpSignalingConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *sctpSignalingConn) SetWriteDeadline(t time.Time) error { return nil }

type sctpAddr struct{}

func (sctpAddr) Network() string { return "sctp-signaling" }
func (sctpAddr) String() string  { return "sctp-signaling" }

// setupSctpSignaling creates an SCTP association over the MTProto signaling channel.
// The outgoing (caller) side is the SCTP Client (sends INIT), incoming is Server.
func (t *TelegramCore) setupSctpSignaling(call *tgCall) {
	call.sctpReady = make(chan struct{})

	// sendFn sends raw SCTP packets directly via MTProto (no V1/V2 encryption at this layer)
	sendFn := func(data []byte) {
		// Check raw output interceptor
		t.rawSigInterceptorsMu.RLock()
		outInterceptor := t.rawSigOutInterceptors[call.id]
		t.rawSigInterceptorsMu.RUnlock()
		if outInterceptor != nil {
			outInterceptor(data)
			return
		}

		_, err := t.api.PhoneSendSignalingData(t.ctx, &tg.PhoneSendSignalingDataRequest{
			Peer: tg.InputPhoneCall{ID: call.id, AccessHash: call.accessHash},
			Data: data,
		})
		if err != nil {
			fmt.Printf("[tg-call] SCTP sendSignaling error: %v\n", err)
		}
	}

	call.sctpConn = newSctpSignalingConn(sendFn)

	go func() {
		var assoc *sctp.Association
		var err error

		sctpConfig := sctp.Config{
			NetConn:              call.sctpConn,
			MaxReceiveBufferSize: 262144, // 256KB, matches tgcalls
		}

		if call.isOutgoing {
			fmt.Printf("[tg-call] SCTP Client (caller) starting association...\n")
			assoc, err = sctp.Client(sctpConfig)
		} else {
			fmt.Printf("[tg-call] SCTP Server (callee) starting association...\n")
			assoc, err = sctp.Server(sctpConfig)
		}
		if err != nil {
			fmt.Printf("[tg-call] SCTP association failed: %v\n", err)
			return
		}
		call.sctpAssoc = assoc
		fmt.Printf("[tg-call] SCTP association established\n")

		// Open/accept stream 0
		var stream *sctp.Stream
		if call.isOutgoing {
			stream, err = assoc.OpenStream(0, sctp.PayloadTypeWebRTCBinary)
		} else {
			stream, err = assoc.AcceptStream()
		}
		if err != nil {
			fmt.Printf("[tg-call] SCTP stream failed: %v\n", err)
			return
		}
		stream.SetDefaultPayloadType(sctp.PayloadTypeWebRTCBinary)
		call.sctpStream = stream
		fmt.Printf("[tg-call] SCTP stream %d ready\n", stream.StreamIdentifier())

		close(call.sctpReady)

		// Read loop: receive V2-encrypted signaling messages from SCTP stream
		buf := make([]byte, 64*1024) // max signaling packet 16KB, but allow headroom
		for {
			select {
			case <-call.done:
				return
			default:
			}
			n, ppi, err := stream.ReadSCTP(buf)
			if err != nil {
				if atomic.LoadInt32(&call.sctpConn.closed) == 0 {
					fmt.Printf("[tg-call] SCTP read error: %v\n", err)
				}
				return
			}
			_ = ppi
			if n == 0 {
				continue
			}
			payload := buf[:n]
			fmt.Printf("[tg-call] SCTP rx: %d bytes\n", n)

			// Decrypt V2 packet
			decrypted, err := tgDecryptV2Packet(call.authKey[:], payload, call.isOutgoing)
			if err != nil {
				fmt.Printf("[tg-call] SCTP V2 decrypt error: %v\n", err)
				continue
			}

			// Decompress gzip if needed
			if len(decrypted) >= 2 && decrypted[0] == 0x1f && decrypted[1] == 0x8b {
				if decompressed, err := gzipDecompress(decrypted); err == nil {
					decrypted = decompressed
				}
			}

			fmt.Printf("[tg-call] SCTP signaling: %s\n", string(decrypted[:min(len(decrypted), 300)]))

			// Parse and handle JSON signaling message
			var msg map[string]interface{}
			if err := json.Unmarshal(decrypted, &msg); err != nil {
				fmt.Printf("[tg-call] SCTP signaling: invalid JSON: %v\n", err)
				continue
			}

			switch msg["@type"] {
			case "offer", "answer":
				sdpType := msg["@type"].(string)
				sdpStr, _ := msg["sdp"].(string)
				fmt.Printf("[tg-call] SCTP got SDP %s (%d bytes)\n", sdpType, len(sdpStr))
				for _, line := range strings.Split(sdpStr, "\r\n") {
					if strings.HasPrefix(line, "m=") || line == "a=sendrecv" || line == "a=recvonly" || line == "a=sendonly" || line == "a=inactive" || strings.HasPrefix(line, "a=mid:") || strings.HasPrefix(line, "a=msid") || strings.HasPrefix(line, "a=setup:") {
						fmt.Printf("[tg-call] SCTP SDP %s: %s\n", sdpType, line)
					}
				}
				t.handleRemoteSDP(call, sdpType, sdpStr)
			case "candidate":
				sdp, _ := msg["sdp"].(string)
				mid, _ := msg["mid"].(string)
				mline := 0
				if ml, ok := msg["mline"].(float64); ok {
					mline = int(ml)
				}
				t.handleRemoteCandidate(call, sdp, mid, mline)
			case "InitialSetup":
				if call.useV2Impl {
					var setup tgInitialSetup
					json.Unmarshal(decrypted, &setup)
					fmt.Printf("[tg-call] SCTP V2Impl: got InitialSetup (ufrag=%s)\n", setup.Ufrag)
					t.handleRemoteInitialSetupV2Impl(call, &setup)
				}
			case "NegotiateChannels":
				if call.useV2Impl {
					var nc tgNegotiateChannels
					json.Unmarshal(decrypted, &nc)
					fmt.Printf("[tg-call] SCTP V2Impl: got NegotiateChannels (exchangeId=%s)\n", nc.ExchangeID)
					t.handleRemoteNegotiateChannelsV2Impl(call, &nc)
				}
			case "Candidates":
				var candidates tgCandidates
				json.Unmarshal(decrypted, &candidates)
				for _, c := range candidates.Candidates {
					if !strings.Contains(c.SDPString, ".reflector") {
						t.handleRemoteCandidate(call, c.SDPString, "0", 0)
					}
				}
			case "MediaState":
				var ms tgMediaState
				json.Unmarshal(decrypted, &ms)
				fmt.Printf("[tg-call] SCTP MediaState: muted=%v video=%s screencast=%s rotation=%d\n",
					ms.Muted, ms.VideoState, ms.ScreencastState, ms.VideoRotation)
				t.applyRemoteMediaState(call, ms)
			default:
				fmt.Printf("[tg-call] SCTP unknown message type: %v\n", msg["@type"])
			}
		}
	}()
}

// sendCallSignalingV2 encrypts, compresses, and sends a signaling message via SCTP stream.
func (t *TelegramCore) sendCallSignalingV2(call *tgCall, v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		fmt.Printf("[tg-call] V2 marshal error: %v\n", err)
		return
	}
	fmt.Printf("[tg-call] V2 signaling tx: %s\n", string(data[:min(len(data), 300)]))

	// Gzip compress
	compressed, err := gzipCompress(data)
	if err != nil {
		fmt.Printf("[tg-call] V2 gzip error: %v\n", err)
		return
	}

	// V2 AES-CTR encrypt
	encrypted, err := tgEncryptV2Packet(call.authKey[:], compressed, call.isOutgoing, &call.v2SigCounter)
	if err != nil {
		fmt.Printf("[tg-call] V2 encrypt error: %v\n", err)
		return
	}

	// Wait for SCTP stream to be ready
	if call.sctpReady != nil {
		select {
		case <-call.sctpReady:
		case <-time.After(10 * time.Second):
			fmt.Printf("[tg-call] V2 SCTP not ready after 10s\n")
			return
		}
	}

	if call.sctpStream == nil {
		fmt.Printf("[tg-call] V2 no SCTP stream\n")
		return
	}

	// Send via SCTP stream 0
	_, err = call.sctpStream.WriteSCTP(encrypted, sctp.PayloadTypeWebRTCBinary)
	if err != nil {
		fmt.Printf("[tg-call] V2 SCTP write error: %v\n", err)
	}
}

// sendV2SignalingAcks sends an ACK-only packet for V2 JSON signaling over MTProto.
// Format: [ourSeq][0xFE empty][ackSeq1][0xFF]...[ackSeqN][0xFF]
// This stops the remote from retransmitting messages we've already received.
func (t *TelegramCore) sendV2SignalingAcks(call *tgCall, ackSeqs []uint32) {
	if len(ackSeqs) == 0 {
		return
	}
	// Build ACK-only plaintext: [ourSeq|flags][0xFE] + [ackSeq][0xFF]...
	seq := atomic.AddUint32(&call.sigCounter, 1)
	plaintext := make([]byte, 5, 5+5*len(ackSeqs))
	binary.BigEndian.PutUint32(plaintext[:4], seq)
	plaintext[4] = 0xFE // kEmptyId
	for _, ackSeq := range ackSeqs {
		var ackBuf [5]byte
		binary.BigEndian.PutUint32(ackBuf[:4], ackSeq)
		ackBuf[4] = 0xFF // kAckId
		plaintext = append(plaintext, ackBuf[:]...)
	}

	// Encrypt with same AES-CTR as tgEncryptSignaling (V2 mode)
	x := 128 // signaling outgoing
	if !call.isOutgoing {
		x = 136
	}
	h := sha256.New()
	h.Write(call.authKey[88+x : 88+x+32])
	h.Write(plaintext)
	msgKeyLarge := h.Sum(nil)
	msgKey := msgKeyLarge[8:24]
	aesKey, aesIv := tgPrepareAesKeyIv(call.authKey[:], msgKey, x)
	block, err := aes.NewCipher(aesKey[:])
	if err != nil {
		fmt.Printf("[tg-call] V2 ACK encrypt error: %v\n", err)
		return
	}
	ciphertext := make([]byte, len(plaintext))
	cipher.NewCTR(block, aesIv[:]).XORKeyStream(ciphertext, plaintext)
	packet := make([]byte, 16+len(ciphertext))
	copy(packet[:16], msgKey)
	copy(packet[16:], ciphertext)

	fmt.Printf("[tg-call] sending %d V2 signaling ACKs\n", len(ackSeqs))

	// Check raw output interceptor
	t.rawSigInterceptorsMu.RLock()
	outInterceptor := t.rawSigOutInterceptors[call.id]
	t.rawSigInterceptorsMu.RUnlock()
	if outInterceptor != nil {
		outInterceptor(packet)
		return
	}
	t.api.PhoneSendSignalingData(t.ctx, &tg.PhoneSendSignalingDataRequest{
		Peer: tg.InputPhoneCall{ID: call.id, AccessHash: call.accessHash},
		Data: packet,
	})
}

// createCallWebRTCAPI creates a pion WebRTC API configured for Telegram calls.
// Registers RED and telephone-event codecs that Desktop includes in re-offers.
func createCallWebRTCAPI(iceUfrag, icePwd string) *webrtc.API {
	me := &webrtc.MediaEngine{}
	me.RegisterDefaultCodecs()

	// Register RED (redundant encoding, PT 63) — Desktop's WebRTC adds this via EnableMedia()
	me.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:    "audio/red",
			ClockRate:   48000,
			Channels:    2,
			SDPFmtpLine: "111/111",
		},
		PayloadType: 63,
	}, webrtc.RTPCodecTypeAudio)

	// Register telephone-event (DTMF, PT 110) — Desktop's WebRTC adds this too
	me.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:  "audio/telephone-event",
			ClockRate: 48000,
		},
		PayloadType: 110,
	}, webrtc.RTPCodecTypeAudio)

	// Register RTP header extensions required for BUNDLE demuxing.
	// When Desktop sends a re-offer with multiple audio m-lines (mid=0 recvonly + mid=2 sendrecv),
	// pion needs sdes:mid to route incoming RTP packets to the correct transceiver.
	// Without this, pion logs "Could not determine PayloadType for SSRC" and drops all incoming audio.
	for _, ext := range []struct {
		uri  string
		typ  webrtc.RTPCodecType
	}{
		// sdes:mid — CRITICAL for BUNDLE demux with multiple m-lines of same media type
		{"urn:ietf:params:rtp-hdrext:sdes:mid", webrtc.RTPCodecTypeAudio},
		// sdes:rtp-stream-id — used for RID-based stream identification
		{"urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id", webrtc.RTPCodecTypeAudio},
		// abs-send-time — used by transport-cc for bandwidth estimation
		{"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time", webrtc.RTPCodecTypeAudio},
		// transport-wide-cc — transport-wide congestion control sequence numbers
		{"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01", webrtc.RTPCodecTypeAudio},
	} {
		if err := me.RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability{URI: ext.uri}, ext.typ); err != nil {
			fmt.Printf("[tg-call] Warning: failed to register header extension %s: %v\n", ext.uri, err)
		}
	}

	ir := &interceptor.Registry{}
	webrtc.RegisterDefaultInterceptors(me, ir)
	se := webrtc.SettingEngine{}
	se.SetSRTPReplayProtectionWindow(1024)
	se.SetICECredentials(iceUfrag, icePwd)
	// Fire OnTrack before first RTP — combined with deferred re-offer processing (after DTLS),
	// this ensures the SRTP read stream is opened while DTLS/SRTP is ready.
	se.SetFireOnTrackBeforeFirstRTP(true)
	logFactory := pionlogging.NewDefaultLoggerFactory()
	logFactory.DefaultLogLevel = pionlogging.LogLevelWarn
	se.LoggerFactory = logFactory
	return webrtc.NewAPI(
		webrtc.WithMediaEngine(me),
		webrtc.WithInterceptorRegistry(ir),
		webrtc.WithSettingEngine(se),
	)
}

// mergeAudioMlines rewrites an SDP that has two audio m-lines (one recvonly, one sendrecv)
// into a single audio m-line with sendrecv. This is needed because tgcalls sends a re-offer
// with separate m-lines for send and receive, but pion can't handle two audio m-lines properly.
func mergeAudioMlines(sdp string) string {
	lines := strings.Split(sdp, "\r\n")
	if len(lines) == 0 {
		lines = strings.Split(sdp, "\n")
	}

	type mlineBlock struct {
		mline     string
		attrs     []string
		direction string // sendrecv, recvonly, sendonly, inactive
		hasSSRC   bool
		ssrcLines []string
		mid       string
	}

	var blocks []mlineBlock
	var current *mlineBlock
	var sessionLines []string
	inSession := true

	for _, line := range lines {
		if strings.HasPrefix(line, "m=") {
			if current != nil {
				blocks = append(blocks, *current)
			}
			current = &mlineBlock{mline: line}
			inSession = false
		} else if current != nil {
			if line == "a=sendrecv" || line == "a=recvonly" || line == "a=sendonly" || line == "a=inactive" {
				current.direction = strings.TrimPrefix(line, "a=")
			} else if strings.HasPrefix(line, "a=ssrc:") {
				current.hasSSRC = true
				current.ssrcLines = append(current.ssrcLines, line)
			} else if strings.HasPrefix(line, "a=mid:") {
				current.mid = strings.TrimPrefix(line, "a=mid:")
			}
			current.attrs = append(current.attrs, line)
		} else if inSession {
			sessionLines = append(sessionLines, line)
		}
	}
	if current != nil {
		blocks = append(blocks, *current)
	}

	// Count audio m-lines
	audioBlocks := 0
	for _, b := range blocks {
		if strings.HasPrefix(b.mline, "m=audio ") {
			audioBlocks++
		}
	}
	if audioBlocks < 2 {
		return sdp // nothing to merge
	}

	// Find the sendrecv/sendonly audio block (the one with SSRC — tgcalls's sending audio)
	var sendBlock *mlineBlock
	var recvBlock *mlineBlock
	for i := range blocks {
		if !strings.HasPrefix(blocks[i].mline, "m=audio ") {
			continue
		}
		if blocks[i].direction == "sendrecv" || blocks[i].hasSSRC {
			sendBlock = &blocks[i]
		} else if blocks[i].direction == "recvonly" {
			recvBlock = &blocks[i]
		}
	}

	if sendBlock == nil || recvBlock == nil {
		return sdp // can't merge
	}

	// Rebuild SDP: keep session lines, change first audio to sendrecv with SSRC from sendBlock,
	// remove the second audio m-line entirely, update BUNDLE group
	var result []string
	result = append(result, sessionLines...)

	for _, b := range blocks {
		if !strings.HasPrefix(b.mline, "m=audio ") {
			// Non-audio: keep as-is
			result = append(result, b.mline)
			result = append(result, b.attrs...)
			continue
		}
		if b.mid == recvBlock.mid {
			// This is the first audio (recvonly) — change to sendrecv, add SSRC from sendBlock
			result = append(result, b.mline)
			for _, attr := range b.attrs {
				if attr == "a=recvonly" {
					result = append(result, "a=sendrecv")
				} else if strings.HasPrefix(attr, "a=ssrc:") {
					// skip existing ssrc (shouldn't be any on recvonly)
				} else {
					result = append(result, attr)
				}
			}
			// Add SSRC lines from the sendrecv block
			for _, ssrc := range sendBlock.ssrcLines {
				result = append(result, ssrc)
			}
			// Add msid if present in sendBlock
			for _, attr := range sendBlock.attrs {
				if strings.HasPrefix(attr, "a=msid:") {
					result = append(result, attr)
				}
			}
		}
		// Skip the sendrecv audio block entirely (merged into recvonly)
	}

	// Fix BUNDLE group: remove the sendBlock's mid
	merged := strings.Join(result, "\r\n")
	if sendBlock.mid != "" {
		// Remove sendBlock's mid from BUNDLE group
		merged = strings.Replace(merged, " "+sendBlock.mid, "", 1)
	}

	// Ensure SDP ends with CRLF
	if !strings.HasSuffix(merged, "\r\n") {
		merged += "\r\n"
	}

	fmt.Printf("[tg-call] Merged %d audio m-lines into 1 sendrecv (removed mid=%s)\n", audioBlocks, sendBlock.mid)
	fmt.Printf("[tg-call] MERGED SDP:\n%s\n", merged)
	return merged
}

// getDHConfig retrieves DH parameters from Telegram.
func (t *TelegramCore) getDHConfig() (p []byte, g int, err error) {
	result, err := t.api.MessagesGetDhConfig(t.ctx, &tg.MessagesGetDhConfigRequest{
		Version:      0,
		RandomLength: 256,
	})
	if err != nil {
		return nil, 0, err
	}
	switch v := result.(type) {
	case *tg.MessagesDhConfig:
		return v.P, v.G, nil
	case *tg.MessagesDhConfigNotModified:
		return nil, 0, fmt.Errorf("DH config not available (not modified)")
	default:
		return nil, 0, fmt.Errorf("unexpected DH config type")
	}
}

// StartCall initiates a one-on-one voice or video call with a user.
func (t *TelegramCore) StartCall(chatID string, video bool) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	uid, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid user ID: %w", err)
	}

	t.peerMu.RLock()
	accessHash := t.userAccessHash[uid]
	t.peerMu.RUnlock()

	// Get DH config
	p, g, err := t.getDHConfig()
	if err != nil {
		return nil, fmt.Errorf("DH config: %w", err)
	}

	// Generate random a (256 bytes)
	a := make([]byte, 256)
	if _, err := io.ReadFull(rand.Reader, a); err != nil {
		return nil, fmt.Errorf("random: %w", err)
	}

	// Compute g_a = g^a mod p
	gBig := new(big.Int).SetInt64(int64(g))
	aBig := new(big.Int).SetBytes(a)
	pBig := new(big.Int).SetBytes(p)
	gA := new(big.Int).Exp(gBig, aBig, pBig)
	gABytes := make([]byte, 256)
	gABuf := gA.Bytes()
	copy(gABytes[256-len(gABuf):], gABuf)

	// g_a_hash = SHA256(g_a)
	gaHash := sha256.Sum256(gABytes)

	// Supported call versions: 13.0.0 (V2Impl+SCTP), 8.0.0 (V2Impl), 4.0.0 (Web)
	versions := filterVersions(
		[]string{"13.0.0", "8.0.0", "4.0.0"},
		t.maxCallVersion, t.minCallVersion,
	)

	// phone.requestCall
	result, err := t.api.PhoneRequestCall(t.ctx, &tg.PhoneRequestCallRequest{
		UserID: &tg.InputUser{UserID: uid, AccessHash: accessHash},
		RandomID: int(binary.BigEndian.Uint32(gaHash[:4])),
		GAHash:   gaHash[:],
		Protocol: tg.PhoneCallProtocol{
			Flags:           0b11, // udp_p2p | udp_reflector
			MinLayer:        65,
			MaxLayer:        92,
			LibraryVersions: versions,
		},
		Video: video,
	})
	if err != nil {
		return nil, fmt.Errorf("phone.requestCall: %w", err)
	}

	// Extract call ID from response
	var callID int64
	var callAccessHash int64
	switch c := result.PhoneCall.(type) {
	case *tg.PhoneCallWaiting:
		callID = c.ID
		callAccessHash = c.AccessHash
	case *tg.PhoneCall:
		callID = c.ID
		callAccessHash = c.AccessHash
	case *tg.PhoneCallRequested:
		callID = c.ID
		callAccessHash = c.AccessHash
	}

	if callID == 0 {
		return nil, fmt.Errorf("no call ID in response")
	}

	// Store call state for DH completion when receiver accepts
	t.mu.Lock()
	if t.activeCalls == nil {
		t.activeCalls = make(map[int64]*tgCall)
	}
	call := &tgCall{
		id:         callID,
		accessHash: callAccessHash,
		peerID:     uid,
		isOutgoing: true,
		isVideo:    video,
		state:      CallStateRinging,
		done:       make(chan struct{}),
	}
	// Store DH private key for later computation (stored in a separate field)
	t.pendingDH[callID] = &pendingDHState{a: a, gA: gABytes, p: p, g: g}
	t.activeCalls[callID] = call
	t.mu.Unlock()

	return &CallSession{
		ID:      strconv.FormatInt(callID, 10),
		ChatID:  chatID,
		IsVideo: video,
		State:   CallStateRinging,
	}, nil
}

// pendingDHState stores DH key exchange state for an outgoing call.
type pendingDHState struct {
	a  []byte // private random
	gA []byte // g^a mod p
	p  []byte // prime
	g  int    // generator
}

// parseCallConnections extracts TURN/STUN ICE servers from the PhoneCall connections list.
// NOTE: Telegram's TURN may return 403 on CreatePermission for private IPs,
// but relay-to-relay (public IP) connections may work. We include TURN and let
// pion handle the 403 errors gracefully (it logs and falls back to other candidates).
func parseCallConnections(connections []tg.PhoneConnectionClass) []webrtc.ICEServer {
	var servers []webrtc.ICEServer
	for _, conn := range connections {
		switch c := conn.(type) {
		case *tg.PhoneConnectionWebrtc:
			if c.Turn {
				// TURN relay — only IPv4 (IPv6 often fails with "no suitable address found")
				urls := []string{fmt.Sprintf("turn:%s:%d", c.IP, c.Port)}
				servers = append(servers, webrtc.ICEServer{
					URLs:           urls,
					Username:       c.Username,
					Credential:     c.Password,
					CredentialType: webrtc.ICECredentialTypePassword,
				})
			}
			if c.Stun {
				servers = append(servers, webrtc.ICEServer{
					URLs: []string{fmt.Sprintf("stun:%s:%d", c.IP, c.Port)},
				})
			}
		}
	}
	return servers
}

// handleCallAccepted is called when the receiver accepts the call (outgoing side).
// CRITICAL TIMING: The remote expects our InitialSetup ASAP after confirmCall.
// Flow: DH → pre-generate ICE creds + confirmCall IN PARALLEL → fire signaling instantly → create PC with TURN.
func (t *TelegramCore) handleCallAccepted(callID int64, gB []byte, protocol tg.PhoneCallProtocol) error {
	t0 := time.Now()
	t.mu.Lock()
	dh := t.pendingDH[callID]
	call := t.activeCalls[callID]
	t.mu.Unlock()

	if dh == nil || call == nil {
		return fmt.Errorf("no pending DH for call %d", callID)
	}

	// 1. Compute auth_key = g_b^a mod p (256 bytes, zero-padded)
	gBBig := new(big.Int).SetBytes(gB)
	aBig := new(big.Int).SetBytes(dh.a)
	pBig := new(big.Int).SetBytes(dh.p)
	authKeyBig := new(big.Int).Exp(gBBig, aBig, pBig)
	authKeyBytes := make([]byte, 256)
	akBuf := authKeyBig.Bytes()
	copy(authKeyBytes[256-len(akBuf):], akBuf)
	copy(call.authKey[:], authKeyBytes)

	sha1Hash := sha1.Sum(authKeyBytes)
	fingerprint := int64(binary.LittleEndian.Uint64(sha1Hash[12:20]))
	fmt.Printf("[tg-call] DH done (+%dms): fp=%d\n", time.Since(t0).Milliseconds(), fingerprint)

	t.mu.Lock()
	delete(t.pendingDH, callID)
	call.state = CallStateConnecting
	t.mu.Unlock()

	// 2. confirmCall — returns connections list with TURN/STUN servers
	versions := filterVersions(
		[]string{"13.0.0", "8.0.0", "4.0.0"},
		t.maxCallVersion, t.minCallVersion,
	)
	confirmResult, err := t.api.PhoneConfirmCall(t.ctx, &tg.PhoneConfirmCallRequest{
		Peer:           tg.InputPhoneCall{ID: callID, AccessHash: call.accessHash},
		GA:             dh.gA,
		KeyFingerprint: fingerprint,
		Protocol: tg.PhoneCallProtocol{
			Flags:           0b11, // udp_p2p | udp_reflector
			MinLayer:        65,
			MaxLayer:        92,
			LibraryVersions: versions,
		},
	})
	if err != nil {
		return fmt.Errorf("phone.confirmCall: %w", err)
	}
	fmt.Printf("[tg-call] confirmCall OK (+%dms)\n", time.Since(t0).Milliseconds())

	pcResult, ok := confirmResult.PhoneCall.(*tg.PhoneCall)
	if !ok {
		return fmt.Errorf("confirmCall returned %T, not *tg.PhoneCall", confirmResult.PhoneCall)
	}
	if pcResult.KeyFingerprint != fingerprint {
		return fmt.Errorf("fingerprint mismatch: %d vs %d", pcResult.KeyFingerprint, fingerprint)
	}
	// Debug dump of PhoneCall response
	fmt.Printf("[tg-call] PhoneCall: id=%d admin=%d participant=%d p2p=%v video=%v conferenceSupported=%v\n",
		pcResult.ID, pcResult.AdminID, pcResult.ParticipantID, pcResult.P2PAllowed, pcResult.Video, pcResult.ConferenceSupported)
	fmt.Printf("[tg-call] Protocol: minLayer=%d maxLayer=%d versions=%v\n",
		pcResult.Protocol.MinLayer, pcResult.Protocol.MaxLayer, pcResult.Protocol.LibraryVersions)
	// Detect negotiated version — should be 10.0.0 or 11.0.0 (V2Reference = standard SDP)
	negotiatedVersion := ""
	if len(pcResult.Protocol.LibraryVersions) > 0 {
		negotiatedVersion = pcResult.Protocol.LibraryVersions[0]
	}
	fmt.Printf("[tg-call] Negotiated version: %s\n", negotiatedVersion)

	// Set up SCTP signaling for v13.0.0 or forced
	if isV3Transport(negotiatedVersion) || t.forceV2Sig {
		call.useV2Sig = true
		fmt.Printf("[tg-call] Using SCTP signaling (version %s, forced=%v)\n", negotiatedVersion, t.forceV2Sig)
		t.setupSctpSignaling(call)
	}
	// V2Impl signaling (v8, v13): InitialSetup + NegotiateChannels
	if t.forceV2Impl || (isV2ImplVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref) {
		call.useV2Impl = true
		if t.forceV1Framing {
			call.useV1Framing = true
		}
		fmt.Printf("[tg-call] Using V2Impl signaling (version %s, forced=%v, v1framing=%v)\n", negotiatedVersion, t.forceV2Impl, call.useV1Framing)
	}
	// Web signaling (v4.0.0/4.0.1): InitialSetup with inline media, V1 encryption framing
	if isWebVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref && !t.forceV2Impl {
		call.useWebSignaling = true
		call.useV1Framing = true // web uses simple [seq][JSON] framing
		fmt.Printf("[tg-call] Using Web signaling (version %s)\n", negotiatedVersion)
	}

	if cp, ok := pcResult.GetCustomParameters(); ok {
		fmt.Printf("[tg-call] CustomParameters: %s\n", cp.Data)
	}

	// Store connections and P2P flag for test harness access
	t.mu.Lock()
	call.connections = pcResult.Connections
	call.p2pAllowed = pcResult.P2PAllowed
	proto := pcResult.Protocol
	call.protocol = &proto
	t.mu.Unlock()

	for i, conn := range pcResult.Connections {
		switch c := conn.(type) {
		case *tg.PhoneConnectionWebrtc:
			fmt.Printf("[tg-call]   conn[%d] WebRTC: ip=%s:%d turn=%v stun=%v user=%s\n", i, c.IP, c.Port, c.Turn, c.Stun, c.Username)
		case *tg.PhoneConnection:
			fmt.Printf("[tg-call]   conn[%d] Reflector: ip=%s:%d tcp=%v peerTag=%d bytes\n", i, c.IP, c.Port, c.TCP, len(c.PeerTag))
		}
	}

	// If skipWebRTC is set, stop here — the test harness handles media transport
	if call.skipWebRTC {
		fmt.Printf("[tg-call] skipWebRTC mode (outgoing) — DH done, %d connections available for test harness\n", len(pcResult.Connections))
		if call.dhDone != nil {
			close(call.dhDone)
		}
		return nil
	}

	// InstanceImpl: legacy path, only reachable via ForceInstanceImpl config flag
	if t.forceInstanceImpl {
		call.useInstanceImpl = true
		fmt.Printf("[tg-call] Using InstanceImpl (forced, version %s)\n", negotiatedVersion)
		return t.startInstanceImplCall(call, pcResult.Connections, negotiatedVersion)
	}

	// 3. Create PeerConnection with TURN servers and debug logging
	iceServers := parseCallConnections(pcResult.Connections)
	fmt.Printf("[tg-call] %d connections → %d ICE servers, p2p=%v (+%dms)\n",
		len(pcResult.Connections), len(iceServers), call.p2pAllowed, time.Since(t0).Milliseconds())

	// ICE transport policy: relay-only unless P2P is allowed (and not forced relay for testing)
	icePolicy := webrtc.ICETransportPolicyRelay
	if call.p2pAllowed && !t.forceRelayICE {
		icePolicy = webrtc.ICETransportPolicyAll
	}

	// Generate static ICE credentials — prevents ICE restart when re-offer answer is created.
	// Official clients send a re-offer after answering. Without static creds, pion generates
	// new ufrag/pwd in the re-offer answer, which the client sees as ICE restart.
	iceUfrag := generateICECredential(16)
	icePwd := generateICECredential(32)

	// Full WebRTC API with RED/telephone-event codecs for Desktop interop
	callAPI := createCallWebRTCAPI(iceUfrag, icePwd)
	pc, err := callAPI.NewPeerConnection(webrtc.Configuration{
		ICEServers:         iceServers,
		ICETransportPolicy: icePolicy,
	})
	if err != nil {
		return fmt.Errorf("PeerConnection: %w", err)
	}
	call.pc = pc
	call.localSDPReady = make(chan struct{})
	call.pcReady = make(chan struct{})
	fmt.Printf("[tg-call] PeerConnection created (ufrag=%s) (+%dms)\n", iceUfrag, time.Since(t0).Milliseconds())
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		fmt.Printf("[tg-call] PeerConnection state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
		if state == webrtc.PeerConnectionStateConnected ||
			state == webrtc.PeerConnectionStateFailed ||
			state == webrtc.PeerConnectionStateClosed {
			call.pcReadyOnce.Do(func() { close(call.pcReady) })
		}
	})
	// Monitor DTLS transport state changes directly
	if dtlsT := pc.SCTP().Transport(); dtlsT != nil {
		dtlsT.OnStateChange(func(state webrtc.DTLSTransportState) {
			fmt.Printf("[tg-call] DTLS state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
		})
		fmt.Printf("[tg-call] DTLS initial state: %s\n", dtlsT.State())
	}

	// 9. Set up audio, create offer, then send InitialSetup + NegotiateChannels
	go t.finishCallSetup(call, t0)
	return nil
}

// finishCallSetup adds audio track, wires callbacks, creates SDP offer, and sends it
// as V2Reference signaling (standard SDP offer/answer over encrypted channel).
// Called as a goroutine after the PeerConnection is created.
func (t *TelegramCore) finishCallSetup(call *tgCall, t0 time.Time) {
	pc := call.pc
	if pc == nil {
		return
	}

	// Add opus audio track
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
	if err != nil {
		fmt.Printf("[tg-call] audio track error: %v\n", err)
		return
	}
	call.audioTrack = audioTrack
	sender, _ := pc.AddTrack(audioTrack)
	go func() {
		b := make([]byte, 1500)
		for {
			select {
			case <-call.done:
				return
			default:
			}
			if _, _, e := sender.Read(b); e != nil {
				return
			}
		}
	}()

	// Add VP8 video track if this is a video call
	// Uses TrackLocalStaticSample for proper VP8 RTP packetization (RFC 7741 fragmentation).
	if call.isVideo {
		videoTrack, err := webrtc.NewTrackLocalStaticSample(
			webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000},
			"video", "uniclient-video",
		)
		if err != nil {
			fmt.Printf("[tg-call] video track error: %v\n", err)
		} else {
			call.videoTrack = videoTrack
			vSender, _ := pc.AddTrack(videoTrack)
			go t.readSenderRTCP(call, vSender, false)
			fmt.Printf("[tg-call] Video track added (VP8, sample-based)\n")
		}
	}

	// Add screencast VP8 track (declared idle, activated by StartScreenShare)
	if call.useWebSignaling || call.isVideo {
		screenTrack, err := webrtc.NewTrackLocalStaticSample(
			webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000},
			"screencast", "uniclient-screencast",
		)
		if err != nil {
			fmt.Printf("[tg-call] screencast track error: %v\n", err)
		} else {
			call.screenTrack = screenTrack
			sSender, _ := pc.AddTrack(screenTrack)
			go t.readSenderRTCP(call, sSender, true)
			fmt.Printf("[tg-call] Screencast track added (VP8 sample-based, idle until StartScreenShare)\n")
		}
	}

	// Handle data channels created by remote (V2Reference uses data channel for MediaState)
	pc.OnDataChannel(func(dc *webrtc.DataChannel) {
		fmt.Printf("[tg-call] DATA CHANNEL opened: label=%s id=%d\n", dc.Label(), *dc.ID())
		dc.OnMessage(func(msg webrtc.DataChannelMessage) {
			fmt.Printf("[tg-call] DATA CHANNEL msg: %d bytes: %s\n", len(msg.Data), string(msg.Data[:min(len(msg.Data), 200)]))
		})
	})

	// Wire up callbacks — dispatch audio vs video vs screencast tracks
	pc.OnTrack(func(track *webrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		trackSSRC := uint32(track.SSRC())
		fmt.Printf("[tg-call] Incoming track: kind=%s codec=%s ssrc=%d mid=%s rid=%s streamID=%s\n",
			track.Kind(), track.Codec().MimeType, trackSSRC, track.Msid(), track.RID(), track.StreamID())
		go func() {
			isVideo := track.Kind() == webrtc.RTPCodecTypeVideo ||
				strings.Contains(strings.ToLower(track.Codec().MimeType), "vp8") ||
				strings.Contains(strings.ToLower(track.Codec().MimeType), "vp9") ||
				strings.Contains(strings.ToLower(track.Codec().MimeType), "h264")
			// Distinguish screencast from camera by matching remote SSRC
			isScreencast := isVideo && call.remoteScreenSSRC != 0 && trackSSRC == call.remoteScreenSSRC
			if isScreencast {
				fmt.Printf("[tg-call] Track ssrc=%d identified as SCREENCAST\n", trackSSRC)
			} else if isVideo {
				fmt.Printf("[tg-call] Track ssrc=%d identified as VIDEO\n", trackSSRC)
			}
			for {
				select {
				case <-call.done:
					return
				default:
				}
				pkt, _, err := track.ReadRTP()
				if err != nil {
					fmt.Printf("[tg-call] track.ReadRTP error: %v (ssrc=%d)\n", err, track.SSRC())
					return
				}
				if isScreencast {
					t.handleIncomingVideoRTP(call, pkt, true)
				} else if isVideo {
					t.handleIncomingVideoRTP(call, pkt, false)
				} else {
					if call.onAudioFrame != nil && len(pkt.Payload) > 0 {
						call.onAudioFrame(pkt.Payload)
					}
					call.writeRecordingFrame(pkt.Payload)
					// Echo mode: forward with fixed timestamp increment
					if call.echoMode && call.audioTrack != nil && len(pkt.Payload) > 0 {
						tsInc := call.audioTSIncrement
						if tsInc == 0 {
							tsInc = 2880 // 60ms at 48kHz default
						}
						seq := uint16(atomic.AddUint32(&call.audioSeq, 1))
						ts := atomic.AddUint32(&call.audioTS, tsInc)
						call.audioTrack.WriteRTP(&pionrtp.Packet{
							Header: pionrtp.Header{
								Version: 2, PayloadType: 111,
								SequenceNumber: seq, Timestamp: ts, SSRC: call.audioSSRC,
							},
							Payload: pkt.Payload,
						})
					}
				}
			}
		}()
	})

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		fmt.Printf("[tg-call] ICE state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
		call.mu.Lock()
		switch state {
		case webrtc.ICEConnectionStateConnected:
			call.state = CallStateActive
		case webrtc.ICEConnectionStateFailed, webrtc.ICEConnectionStateClosed:
			call.state = CallStateEnded
		}
		call.mu.Unlock()
		if state == webrtc.ICEConnectionStateConnected || state == webrtc.ICEConnectionStateFailed {
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call:     &CallSession{ID: strconv.FormatInt(call.id, 10), State: call.state},
			})
		}
	})

	// Send ICE candidates
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		cJSON := c.ToJSON()
		if call.useV2Impl || call.useWebSignaling {
			// V2Impl / Web: send as Candidates message with sdpString
			t.sendCallSignaling(call, &tgCandidates{
				Type: "Candidates",
				Candidates: []tgCandidate{{SDPString: cJSON.Candidate}},
			})
		} else {
			// V2Reference: individual candidate messages
			mid := ""
			if cJSON.SDPMid != nil {
				mid = *cJSON.SDPMid
			}
			mline := 0
			if cJSON.SDPMLineIndex != nil {
				mline = int(*cJSON.SDPMLineIndex)
			}
			t.sendCallSignaling(call, map[string]interface{}{
				"@type": "candidate",
				"sdp":   cJSON.Candidate,
				"mid":   mid,
				"mline": mline,
			})
		}
	})

	// Create data channel (outgoing side creates it, V2Reference matches standard WebRTC)
	if call.isOutgoing {
		dc, err := pc.CreateDataChannel("data", nil)
		if err == nil {
			dc.OnMessage(func(msg webrtc.DataChannelMessage) {
				fmt.Printf("[tg-call] DATA CHANNEL msg: %d bytes: %s\n", len(msg.Data), string(msg.Data[:min(len(msg.Data), 200)]))
			})
		}
	}

	if t.noOwnOffer {
		// NoOwnOffer mode: don't send our offer. Wait for the remote's offer and answer it.
		// Used for official client interop where sending our offer causes recvonly + re-offer mess.
		close(call.localSDPReady)
		call.localSetupSent = true
		fmt.Printf("[tg-call] NoOwnOffer mode — waiting for remote SDP offer (+%dms)\n", time.Since(t0).Milliseconds())
	} else {
		// Create SDP offer (used for both V2Reference and V2Impl to trigger ICE gathering)
		offer, err := pc.CreateOffer(nil)
		if err != nil {
			fmt.Printf("[tg-call] CreateOffer error: %v\n", err)
			return
		}
		if err := pc.SetLocalDescription(offer); err != nil {
			fmt.Printf("[tg-call] SetLocalDescription error: %v\n", err)
			return
		}
		close(call.localSDPReady)
		call.localSDP = offer.SDP
		fmt.Printf("[tg-call] SDP offer created (+%dms)\n", time.Since(t0).Milliseconds())

		// Extract SSRCs from our offer SDP (audio + video + screencast)
		currentMedia := ""
		videoSectionCount := 0
		for _, line := range strings.Split(offer.SDP, "\r\n") {
			if strings.HasPrefix(line, "m=audio") {
				currentMedia = "audio"
			} else if strings.HasPrefix(line, "m=video") {
				videoSectionCount++
				if videoSectionCount == 1 {
					currentMedia = "video"
				} else {
					currentMedia = "screencast"
				}
			} else if strings.HasPrefix(line, "m=") {
				currentMedia = "other"
			}
			if strings.HasPrefix(line, "a=ssrc:") {
				parts := strings.SplitN(strings.TrimPrefix(line, "a=ssrc:"), " ", 2)
				if len(parts) >= 1 {
					ssrcVal := uint32(0)
					fmt.Sscanf(parts[0], "%d", &ssrcVal)
					if ssrcVal != 0 {
						if currentMedia == "audio" && call.audioSSRC == 0 {
							call.audioSSRC = ssrcVal
							fmt.Printf("[tg-call] Set audioSSRC from SDP: %d\n", ssrcVal)
						} else if currentMedia == "video" && call.videoSSRC == 0 {
							call.videoSSRC = ssrcVal
							fmt.Printf("[tg-call] Set videoSSRC from SDP: %d\n", ssrcVal)
						} else if currentMedia == "screencast" && call.screenSSRC == 0 {
							call.screenSSRC = ssrcVal
							fmt.Printf("[tg-call] Set screenSSRC from SDP: %d\n", ssrcVal)
						}
					}
				}
			}
		}

		if call.useWebSignaling {
			// Web: send InitialSetup with inline audio media
			webSetup := extractWebInitialSetupFromSDP(offer.SDP, true)
			// Save declared screencast SSRC so StartScreenShare uses the same one
			if webSetup.Screencast != nil && webSetup.Screencast.SSRC != "" {
				var scrSSRC uint32
				fmt.Sscanf(webSetup.Screencast.SSRC, "%d", &scrSSRC)
				if scrSSRC != 0 {
					call.screenSSRC = scrSSRC
					fmt.Printf("[tg-call] Saved our screencast SSRC: %d\n", scrSSRC)
				}
			}
			t.sendCallSignaling(call, webSetup)
			fmt.Printf("[tg-call] Web: sent InitialSetup (ufrag=%s, audio=%v video=%v screencast=%v) (+%dms)\n",
				webSetup.Ufrag, webSetup.Audio != nil, webSetup.Video != nil, webSetup.Screencast != nil, time.Since(t0).Milliseconds())
		} else if call.useV2Impl {
			// V2Impl: send InitialSetup + NegotiateChannels instead of SDP
			v2Setup, v2NC := extractV2ImplFromSDP(offer.SDP, true)
			v2NC.ExchangeID = strconv.FormatUint(uint64(atomic.AddUint32(&call.v2ImplExchangeSeq, 1)), 10)

			t.sendCallSignaling(call, v2Setup)
			fmt.Printf("[tg-call] V2Impl: sent InitialSetup (ufrag=%s, setup=%s) (+%dms)\n",
				v2Setup.Ufrag, v2Setup.Fingerprints[0].Setup, time.Since(t0).Milliseconds())

			t.sendCallSignaling(call, v2NC)
			fmt.Printf("[tg-call] V2Impl: sent NegotiateChannels (exchangeId=%s, ssrc=%s) (+%dms)\n",
				v2NC.ExchangeID, v2NC.Contents[0].SSRC, time.Since(t0).Milliseconds())
		} else {
			// V2Reference: send standard SDP offer
			t.sendCallSignaling(call, map[string]interface{}{
				"@type": "offer",
				"sdp":   offer.SDP,
			})
			fmt.Printf("[tg-call] SDP offer sent (+%dms)\n", time.Since(t0).Milliseconds())
		}
		call.localSetupSent = true
	}

	// Send MediaState
	videoState := "inactive"
	if call.isVideo {
		videoState = "active"
	}
	t.sendCallSignaling(call, map[string]interface{}{
		"@type":          "MediaState",
		"muted":          false,
		"videoState":     videoState,
		"videoRotation":  0,
		"screencastState": "inactive",
		"lowBattery":     false,
	})

	// Silence sender — sends opus silence to keep the RTP stream alive and trigger OnTrack on remote
	go func() {
		select {
		case <-call.pcReady:
		case <-call.done:
			return
		case <-time.After(30 * time.Second):
			return
		}
		if pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
			return
		}
		fmt.Printf("[tg-call] Audio sender started\n")
		silence := []byte{0xF8, 0xFF, 0xFE}
		tick := time.NewTicker(20 * time.Millisecond)
		defer tick.Stop()
		for pc.ConnectionState() == webrtc.PeerConnectionStateConnected {
			select {
			case <-call.done:
				return
			case <-tick.C:
			}
			// Echo mode: audio is sent directly from OnTrack handler, skip here
			if call.echoMode || call.externalAudio {
				continue
			}
			seq := uint16(atomic.AddUint32(&call.audioSeq, 1))
			ts := atomic.AddUint32(&call.audioTS, 960)
			audioTrack.WriteRTP(&pionrtp.Packet{
				Header: pionrtp.Header{
					Version: 2, PayloadType: 111,
					SequenceNumber: seq, Timestamp: ts, SSRC: call.audioSSRC,
				},
				Payload: silence,
			})
		}
	}()

	// Poll PeerConnection state every 2 seconds (debug)
	go func() {
		tick := time.NewTicker(2 * time.Second)
		defer tick.Stop()
		for i := 0; i < 30; i++ {
			select {
			case <-call.done:
				return
			case <-tick.C:
			}
			if pc.ConnectionState() == webrtc.PeerConnectionStateClosed {
				return
			}
			stats := pc.GetStats()
			var inRTP, outRTP int
			for _, s := range stats {
				switch v := s.(type) {
				case webrtc.InboundRTPStreamStats:
					inRTP += int(v.PacketsReceived)
				case webrtc.OutboundRTPStreamStats:
					outRTP += int(v.PacketsSent)
				}
			}
			fmt.Printf("[tg-call] POLL pc=%s ice=%s inRTP=%d outRTP=%d (+%dms)\n",
				pc.ConnectionState(), pc.ICEConnectionState(),
				inRTP, outRTP, time.Since(t0).Milliseconds())
		}
	}()
}

// handleIncomingCallConfirmed completes DH for incoming calls when the PhoneCall update arrives.
// This happens after our phone.acceptCall and the caller's phone.confirmCall.
func (t *TelegramCore) handleIncomingCallConfirmed(pc *tg.PhoneCall) error {
	t.mu.Lock()
	dh := t.pendingDH[pc.ID]
	call := t.activeCalls[pc.ID]
	t.mu.Unlock()

	if dh == nil || call == nil {
		return nil // Not an incoming call we're handling
	}
	if call.isOutgoing {
		return nil // Outgoing calls use handleCallAccepted path
	}

	// Compute auth_key = g_a^b mod p (we stored 'b' in dh.a for incoming calls)
	gA := pc.GAOrB
	if len(gA) == 0 {
		return fmt.Errorf("PhoneCall missing g_a")
	}
	gABig := new(big.Int).SetBytes(gA)
	bBig := new(big.Int).SetBytes(dh.a)
	pBig := new(big.Int).SetBytes(dh.p)
	authKeyBig := new(big.Int).Exp(gABig, bBig, pBig)
	authKeyBytes := make([]byte, 256)
	akBuf := authKeyBig.Bytes()
	copy(authKeyBytes[256-len(akBuf):], akBuf)
	copy(call.authKey[:], authKeyBytes)

	// Verify fingerprint matches
	sha1Hash := sha1.Sum(authKeyBytes)
	fingerprint := int64(binary.LittleEndian.Uint64(sha1Hash[12:20]))
	if pc.KeyFingerprint != fingerprint {
		return fmt.Errorf("incoming call fingerprint mismatch: %d vs %d", pc.KeyFingerprint, fingerprint)
	}

	t.mu.Lock()
	delete(t.pendingDH, pc.ID)
	call.accessHash = pc.AccessHash
	call.state = CallStateConnecting
	call.connections = pc.Connections
	call.p2pAllowed = pc.P2PAllowed
	proto := pc.Protocol
	call.protocol = &proto
	t.mu.Unlock()
	fmt.Printf("[tg-call] Incoming DH done, fp=%d\n", fingerprint)

	// Signal DH completion (for test harnesses)
	if call.dhDone != nil {
		close(call.dhDone)
	}

	// If skipWebRTC is set, stop here — the test harness handles media transport
	if call.skipWebRTC {
		fmt.Printf("[tg-call] skipWebRTC mode — DH done, %d connections available for test harness\n", len(pc.Connections))
		return nil
	}

	// Detect negotiated version for incoming call
	negotiatedVersion := ""
	if len(pc.Protocol.LibraryVersions) > 0 {
		negotiatedVersion = pc.Protocol.LibraryVersions[0]
	}
	fmt.Printf("[tg-call] Incoming negotiated version: %s\n", negotiatedVersion)

	// Set up SCTP signaling for v13.0.0 or forced
	if isV3Transport(negotiatedVersion) || t.forceV2Sig {
		call.useV2Sig = true
		fmt.Printf("[tg-call] Incoming: using SCTP signaling\n")
		t.setupSctpSignaling(call)
	}
	// V2Impl signaling (v8, v13): InitialSetup + NegotiateChannels instead of SDP
	if t.forceV2Impl || (isV2ImplVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref) {
		call.useV2Impl = true
		if t.forceV1Framing {
			call.useV1Framing = true
		}
		fmt.Printf("[tg-call] Incoming: using V2Impl signaling (version %s, forced=%v, v1framing=%v)\n", negotiatedVersion, t.forceV2Impl, call.useV1Framing)
	}
	// Web signaling (v4.0.0/4.0.1)
	if isWebVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref && !t.forceV2Impl {
		call.useWebSignaling = true
		call.useV1Framing = true
		fmt.Printf("[tg-call] Incoming: using Web signaling (version %s)\n", negotiatedVersion)
	}

	fmt.Printf("[tg-call] Incoming PhoneCall: %d connections\n", len(pc.Connections))
	for i, conn := range pc.Connections {
		switch c := conn.(type) {
		case *tg.PhoneConnectionWebrtc:
			fmt.Printf("[tg-call]   conn[%d] WebRTC: ip=%s:%d turn=%v stun=%v user=%s\n", i, c.IP, c.Port, c.Turn, c.Stun, c.Username)
		case *tg.PhoneConnection:
			fmt.Printf("[tg-call]   conn[%d] Reflector: ip=%s:%d\n", i, c.IP, c.Port)
		}
	}

	// InstanceImpl: legacy path, only reachable via ForceInstanceImpl config flag
	if t.forceInstanceImpl {
		call.useInstanceImpl = true
		fmt.Printf("[tg-call] Incoming: using InstanceImpl (forced, version %s)\n", negotiatedVersion)
		return t.startInstanceImplCall(call, pc.Connections, negotiatedVersion)
	}

	iceServers := parseCallConnections(pc.Connections)
	fmt.Printf("[tg-call] Incoming: %d ICE servers, p2p=%v\n", len(iceServers), call.p2pAllowed)
	return t.startCallWebRTC(call, iceServers, time.Now())
}

// startCallWebRTC creates a PeerConnection for the INCOMING side.
// With V2Reference, the incoming side waits for the remote's SDP offer,
// then creates and sends an SDP answer. Standard WebRTC flow.
func (t *TelegramCore) startCallWebRTC(call *tgCall, iceServers []webrtc.ICEServer, t0 time.Time) error {
	// ICE transport policy: relay-only unless P2P is allowed (and not forced relay for testing)
	icePolicy := webrtc.ICETransportPolicyRelay
	if call.p2pAllowed && !t.forceRelayICE {
		icePolicy = webrtc.ICETransportPolicyAll
	}

	// Static ICE credentials — same reason as outgoing side
	iceUfrag := generateICECredential(16)
	icePwd := generateICECredential(32)

	// Create PeerConnection with RED/telephone-event codecs for Desktop interop
	callAPI := createCallWebRTCAPI(iceUfrag, icePwd)
	pc, err := callAPI.NewPeerConnection(webrtc.Configuration{
		ICEServers:         iceServers,
		ICETransportPolicy: icePolicy,
	})
	if err != nil {
		return fmt.Errorf("PeerConnection: %w", err)
	}
	call.pc = pc
	call.localSDPReady = make(chan struct{})
	call.pcReady = make(chan struct{})

	// Add opus audio track
	audioTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2},
		"audio", "uniclient-audio",
	)
	if err != nil {
		pc.Close()
		return fmt.Errorf("audio track: %w", err)
	}
	call.audioTrack = audioTrack
	sender, _ := pc.AddTrack(audioTrack)
	go func() {
		b := make([]byte, 1500)
		for {
			select {
			case <-call.done:
				return
			default:
			}
			if _, _, e := sender.Read(b); e != nil {
				return
			}
		}
	}()

	// Add VP8 video track if this is a video call
	if call.isVideo {
		videoTrack, err := webrtc.NewTrackLocalStaticSample(
			webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000},
			"video", "uniclient-video",
		)
		if err != nil {
			fmt.Printf("[tg-call] Incoming: video track error: %v\n", err)
		} else {
			call.videoTrack = videoTrack
			vSender, _ := pc.AddTrack(videoTrack)
			go t.readSenderRTCP(call, vSender, false)
			fmt.Printf("[tg-call] Incoming: video track added (VP8 sample-based)\n")
		}
	}

	// Add screencast VP8 track (declared idle, activated by StartScreenShare)
	if call.useWebSignaling || call.isVideo {
		screenTrack, err := webrtc.NewTrackLocalStaticSample(
			webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8, ClockRate: 90000},
			"screencast", "uniclient-screencast",
		)
		if err != nil {
			fmt.Printf("[tg-call] Incoming: screencast track error: %v\n", err)
		} else {
			call.screenTrack = screenTrack
			sSender, _ := pc.AddTrack(screenTrack)
			go t.readSenderRTCP(call, sSender, true)
			fmt.Printf("[tg-call] Incoming: screencast track added (VP8 sample-based, idle until StartScreenShare)\n")
		}
	}

	pc.OnTrack(func(track *webrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		trackSSRC := uint32(track.SSRC())
		fmt.Printf("[tg-call] Incoming track: kind=%s codec=%s ssrc=%d mid=%s rid=%s streamID=%s\n",
			track.Kind(), track.Codec().MimeType, trackSSRC, track.Msid(), track.RID(), track.StreamID())
		for i, tr := range call.pc.GetTransceivers() {
			mid := tr.Mid()
			dir := tr.Direction()
			var recvSSRC webrtc.SSRC
			if tr.Receiver() != nil && tr.Receiver().Track() != nil {
				recvSSRC = tr.Receiver().Track().SSRC()
			}
			fmt.Printf("[tg-call]   transceiver[%d]: mid=%s dir=%s recvSSRC=%d\n", i, mid, dir, recvSSRC)
		}
		go func() {
			isVideo := track.Kind() == webrtc.RTPCodecTypeVideo ||
				strings.Contains(strings.ToLower(track.Codec().MimeType), "vp8") ||
				strings.Contains(strings.ToLower(track.Codec().MimeType), "vp9") ||
				strings.Contains(strings.ToLower(track.Codec().MimeType), "h264")
			isScreencast := isVideo && call.remoteScreenSSRC != 0 && trackSSRC == call.remoteScreenSSRC
			if isScreencast {
				fmt.Printf("[tg-call] Track ssrc=%d identified as SCREENCAST\n", trackSSRC)
			} else if isVideo {
				fmt.Printf("[tg-call] Track ssrc=%d identified as VIDEO\n", trackSSRC)
			}
			for {
				select {
				case <-call.done:
					return
				default:
				}
				pkt, _, err := track.ReadRTP()
				if err != nil {
					fmt.Printf("[tg-call] track.ReadRTP error: %v (ssrc=%d)\n", err, track.SSRC())
					return
				}
				if isScreencast {
					t.handleIncomingVideoRTP(call, pkt, true)
				} else if isVideo {
					t.handleIncomingVideoRTP(call, pkt, false)
				} else {
					if call.onAudioFrame != nil && len(pkt.Payload) > 0 {
						call.onAudioFrame(pkt.Payload)
					}
					call.writeRecordingFrame(pkt.Payload)
					if call.echoMode && call.audioTrack != nil && len(pkt.Payload) > 0 {
						tsInc := call.audioTSIncrement
						if tsInc == 0 {
							tsInc = 2880
						}
						seq := uint16(atomic.AddUint32(&call.audioSeq, 1))
						ts := atomic.AddUint32(&call.audioTS, tsInc)
						call.audioTrack.WriteRTP(&pionrtp.Packet{
							Header: pionrtp.Header{
								Version: 2, PayloadType: 111,
								SequenceNumber: seq, Timestamp: ts, SSRC: call.audioSSRC,
							},
							Payload: pkt.Payload,
						})
					}
				}
			}
		}()
	})

	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		fmt.Printf("[tg-call] PeerConnection state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
		if state == webrtc.PeerConnectionStateConnected ||
			state == webrtc.PeerConnectionStateFailed ||
			state == webrtc.PeerConnectionStateClosed {
			call.pcReadyOnce.Do(func() { close(call.pcReady) })
		}
	})

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		fmt.Printf("[tg-call] ICE state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
		call.mu.Lock()
		switch state {
		case webrtc.ICEConnectionStateConnected:
			call.state = CallStateActive
		case webrtc.ICEConnectionStateFailed, webrtc.ICEConnectionStateClosed:
			call.state = CallStateEnded
		}
		call.mu.Unlock()
		if state == webrtc.ICEConnectionStateConnected || state == webrtc.ICEConnectionStateFailed {
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call:     &CallSession{ID: strconv.FormatInt(call.id, 10), State: call.state},
			})
		}
	})

	// Send ICE candidates
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		cJSON := c.ToJSON()
		if call.useV2Impl || call.useWebSignaling {
			// V2Impl / Web: send as Candidates message
			t.sendCallSignaling(call, &tgCandidates{
				Type: "Candidates",
				Candidates: []tgCandidate{{SDPString: cJSON.Candidate}},
			})
		} else {
			// V2Reference: individual candidate messages
			mid := ""
			if cJSON.SDPMid != nil {
				mid = *cJSON.SDPMid
			}
			mline := 0
			if cJSON.SDPMLineIndex != nil {
				mline = int(*cJSON.SDPMLineIndex)
			}
			t.sendCallSignaling(call, map[string]interface{}{
				"@type": "candidate",
				"sdp":   cJSON.Candidate,
				"mid":   mid,
				"mline": mline,
			})
		}
	})

	pc.OnDataChannel(func(dc *webrtc.DataChannel) {
		fmt.Printf("[tg-call] DATA CHANNEL opened: label=%s id=%d\n", dc.Label(), *dc.ID())
		dc.OnMessage(func(msg webrtc.DataChannelMessage) {
			fmt.Printf("[tg-call] DATA CHANNEL msg: %d bytes\n", len(msg.Data))
		})
	})

	// V2Impl incoming: do NOT create early offer — pion must be in "stable" state
	// to accept the synthetic remote offer from InitialSetup + NegotiateChannels.
	// For V2Reference: standard flow, wait for remote SDP offer.

	// Signal that PC is ready
	close(call.localSDPReady)
	waitingFor := "SDP offer"
	if call.useV2Impl {
		waitingFor = "InitialSetup+NegotiateChannels"
	} else if call.useWebSignaling {
		waitingFor = "Web InitialSetup"
	}
	fmt.Printf("[tg-call] Incoming PC ready, waiting for remote %s (+%dms)\n",
		waitingFor, time.Since(t0).Milliseconds())

	// Silence sender for incoming side — triggered after connection established
	go func() {
		select {
		case <-call.pcReady:
		case <-call.done:
			return
		case <-time.After(30 * time.Second):
			return
		}
		if pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
			return
		}
		fmt.Printf("[tg-call] Incoming: audio sender started\n")
		silence := []byte{0xF8, 0xFF, 0xFE}
		tick := time.NewTicker(20 * time.Millisecond)
		defer tick.Stop()
		for pc.ConnectionState() == webrtc.PeerConnectionStateConnected {
			select {
			case <-call.done:
				return
			case <-tick.C:
			}
			if call.echoMode || call.externalAudio {
				continue
			}
			seq := uint16(atomic.AddUint32(&call.audioSeq, 1))
			ts := atomic.AddUint32(&call.audioTS, 960)
			audioTrack.WriteRTP(&pionrtp.Packet{
				Header: pionrtp.Header{
					Version: 2, PayloadType: 111,
					SequenceNumber: seq, Timestamp: ts, SSRC: call.audioSSRC,
				},
				Payload: silence,
			})
		}
	}()

	// Poll PeerConnection state every 2 seconds (debug)
	go func() {
		tick := time.NewTicker(2 * time.Second)
		defer tick.Stop()
		for i := 0; i < 30; i++ {
			select {
			case <-call.done:
				return
			case <-tick.C:
			}
			if pc.ConnectionState() == webrtc.PeerConnectionStateClosed {
				return
			}
			stats := pc.GetStats()
			var inRTP, outRTP int
			for _, s := range stats {
				switch v := s.(type) {
				case webrtc.InboundRTPStreamStats:
					inRTP += int(v.PacketsReceived)
				case webrtc.OutboundRTPStreamStats:
					outRTP += int(v.PacketsSent)
				}
			}
			fmt.Printf("[tg-call] POLL pc=%s ice=%s inRTP=%d outRTP=%d (+%dms)\n",
				pc.ConnectionState(), pc.ICEConnectionState(),
				inRTP, outRTP, time.Since(t0).Milliseconds())
		}
	}()

	return nil
}

// sendCallSignaling encrypts and sends a signaling message for a call.
// Routes through SCTP for v11.0.0 or direct V1 encryption for v10.0.0.
func (t *TelegramCore) sendCallSignaling(call *tgCall, v interface{}) {
	if call.useV2Sig {
		t.sendCallSignalingV2(call, v)
		return
	}

	data, err := json.Marshal(v)
	if err != nil {
		fmt.Printf("[tg-call] marshal error: %v\n", err)
		return
	}
	fmt.Printf("[tg-call] signaling tx (seq=%d): %s\n", atomic.LoadUint32(&call.sigCounter)+1, string(data[:min(len(data), 300)]))
	encrypted, err := tgEncryptSignaling(call.authKey[:], data, call.isOutgoing, &call.sigCounter, call.useV1Framing)
	if err != nil {
		fmt.Printf("[tg-call] encrypt error: %v\n", err)
		return
	}

	// Check raw output interceptor — used by test harnesses for direct bridging
	t.rawSigInterceptorsMu.RLock()
	outInterceptor := t.rawSigOutInterceptors[call.id]
	t.rawSigInterceptorsMu.RUnlock()
	if outInterceptor != nil {
		outInterceptor(encrypted)
		return
	}

	_, err = t.api.PhoneSendSignalingData(t.ctx, &tg.PhoneSendSignalingDataRequest{
		Peer: tg.InputPhoneCall{ID: call.id, AccessHash: call.accessHash},
		Data: encrypted,
	})
	if err != nil {
		fmt.Printf("[tg-call] sendSignaling error: %v\n", err)
	}
}

// handleSignalingData decrypts and processes incoming signaling data for a call.
func (t *TelegramCore) handleSignalingData(callID int64, data []byte) {
	// Check raw input interceptor — used by test harnesses (ntgcalls)
	t.rawSigInterceptorsMu.RLock()
	inInterceptor := t.rawSigInInterceptors[callID]
	t.rawSigInterceptorsMu.RUnlock()
	if inInterceptor != nil {
		inInterceptor(data)
		return
	}

	t.mu.RLock()
	call := t.activeCalls[callID]
	t.mu.RUnlock()
	if call == nil {
		fmt.Printf("[tg-call] signaling: no active call %d\n", callID)
		return
	}

	// InstanceImpl (v5.0.0, v2.7.7): binary protocol signaling
	if call.useInstanceImpl {
		t.handleInstanceImplSignaling(call, data)
		return
	}

	// V2 SCTP signaling (v11.0.0): feed raw SCTP packets to the SCTP conn
	if call.useV2Sig && call.sctpConn != nil {
		fmt.Printf("[tg-call] SCTP feed: %d bytes (first4hex=%x)\n", len(data), data[:min(4, len(data))])
		call.sctpConn.feed(data)
		return
	}

	// Decrypt signaling (V1 or V2 framing depending on negotiated version)
	messages, ackSeqs, err := tgDecryptSignaling(call.authKey[:], data, call.isOutgoing, call.useV1Framing)
	if err != nil {
		fmt.Printf("[tg-call] signaling decrypt error: %v (%d bytes)\n", err, len(data))
		return
	}

	// Send ACKs immediately for V2 framing (not V1) to stop remote retransmission
	if len(ackSeqs) > 0 && !call.useV1Framing {
		go t.sendV2SignalingAcks(call, ackSeqs)
	}

	if len(messages) == 0 {
		fmt.Printf("[tg-call] signaling: ACK-only packet (%d bytes)\n", len(data))
		return
	}
	for _, plaintext := range messages {
		if len(plaintext) == 0 {
			continue
		}

		// Decompress gzip if needed (V2Reference may gzip large SDPs)
		if len(plaintext) >= 2 && plaintext[0] == 0x1f && plaintext[1] == 0x8b {
			if decompressed, err := gzipDecompress(plaintext); err == nil {
				plaintext = decompressed
				fmt.Printf("[tg-call] decompressed gzip → %d bytes\n", len(plaintext))
			}
		}

		var msg map[string]interface{}
		if err := json.Unmarshal(plaintext, &msg); err != nil {
			fmt.Printf("[tg-call] signaling: invalid JSON: %v\n", err)
			continue
		}

		switch msg["@type"] {
		case "offer", "answer":
			// V2Reference: standard SDP offer/answer
			sdpType := msg["@type"].(string)
			sdpStr, _ := msg["sdp"].(string)
			// Log direction attributes for each m-line
			for _, line := range strings.Split(sdpStr, "\r\n") {
				if strings.HasPrefix(line, "m=") || line == "a=sendrecv" || line == "a=recvonly" || line == "a=sendonly" || line == "a=inactive" || strings.HasPrefix(line, "a=msid") || strings.HasPrefix(line, "a=mid:") {
					fmt.Printf("[tg-call] SDP %s: %s\n", sdpType, line)
				}
			}
			t.handleRemoteSDP(call, sdpType, sdpStr)

		case "candidate":
			// V2Reference: standard ICE candidate
			sdp, _ := msg["sdp"].(string)
			mid, _ := msg["mid"].(string)
			mline := 0
			if ml, ok := msg["mline"].(float64); ok {
				mline = int(ml)
			}
			fmt.Printf("[tg-call] Got candidate: mid=%s mline=%d sdp=%s\n", mid, mline, sdp[:min(len(sdp), 80)])
			t.handleRemoteCandidate(call, sdp, mid, mline)

		case "MediaState":
			var ms tgMediaState
			json.Unmarshal(plaintext, &ms)
			fmt.Printf("[tg-call] Got MediaState: muted=%v video=%s screencast=%s rotation=%d\n",
				ms.Muted, ms.VideoState, ms.ScreencastState, ms.VideoRotation)
			t.applyRemoteMediaState(call, ms)

		case "InitialSetup":
			if call.useWebSignaling {
				var setup tgInitialSetup
				json.Unmarshal(plaintext, &setup)
				fmt.Printf("[tg-call] Web: got InitialSetup (ufrag=%s, setup=%s, audio=%v, video=%v, screencast=%v)\n",
					setup.Ufrag, setup.Fingerprints[0].Setup, setup.Audio != nil, setup.Video != nil, setup.Screencast != nil)
				t.handleRemoteInitialSetupWeb(call, &setup)
			} else if call.useV2Impl {
				var setup tgInitialSetup
				json.Unmarshal(plaintext, &setup)
				fmt.Printf("[tg-call] V2Impl: got InitialSetup (ufrag=%s, setup=%s)\n",
					setup.Ufrag, setup.Fingerprints[0].Setup)
				t.handleRemoteInitialSetupV2Impl(call, &setup)
			} else {
				fmt.Printf("[tg-call] Got InitialSetup (unexpected with V2Reference)\n")
			}
		case "NegotiateChannels":
			if call.useV2Impl {
				var nc tgNegotiateChannels
				json.Unmarshal(plaintext, &nc)
				ssrc := ""
				if len(nc.Contents) > 0 {
					ssrc = nc.Contents[0].SSRC
				}
				fmt.Printf("[tg-call] V2Impl: got NegotiateChannels (exchangeId=%s, contents=%d, ssrc=%s)\n",
					nc.ExchangeID, len(nc.Contents), ssrc)
				t.handleRemoteNegotiateChannelsV2Impl(call, &nc)
			} else {
				fmt.Printf("[tg-call] Got NegotiateChannels (unexpected with V2Reference)\n")
			}
		case "Candidates":
			// V2Impl candidate format — parse and forward
			var candidates tgCandidates
			json.Unmarshal(plaintext, &candidates)
			for _, c := range candidates.Candidates {
				if !strings.Contains(c.SDPString, ".reflector") {
					t.handleRemoteCandidate(call, c.SDPString, "0", 0)
				}
			}
		}
	}
}

// handleRemoteSDP processes a standard SDP offer or answer from V2Reference signaling.
func (t *TelegramCore) handleRemoteSDP(call *tgCall, sdpType string, sdp string) {
	// Wait for PC to be ready
	if call.localSDPReady != nil {
		select {
		case <-call.localSDPReady:
		case <-time.After(10 * time.Second):
			fmt.Printf("[tg-call] Timeout waiting for PC ready\n")
			return
		}
	}
	call.mu.Lock()
	defer call.mu.Unlock()

	if call.pc == nil {
		fmt.Printf("[tg-call] SDP received but no PeerConnection\n")
		return
	}

	if sdpType == "offer" {
		if !call.remoteSDPSet {
			// FIRST offer (pion↔pion: incoming side receives outgoing's offer)
			// Use pion's normal path: SetRemoteDescription + CreateAnswer
			if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
				Type: webrtc.SDPTypeOffer,
				SDP:  sdp,
			}); err != nil {
				fmt.Printf("[tg-call] SetRemoteDescription(offer) error: %v\n", err)
				return
			}
			call.remoteSDPSet = true
			fmt.Printf("[tg-call] Remote offer set (first), receivers=%d\n", len(call.pc.GetReceivers()))

			// Extract remote video/screen SSRCs from offer SDP
			extractRemoteVideoSSRCs(call, sdp)

			answer, err := call.pc.CreateAnswer(nil)
			if err != nil {
				fmt.Printf("[tg-call] CreateAnswer error: %v\n", err)
				return
			}
			if err := call.pc.SetLocalDescription(answer); err != nil {
				fmt.Printf("[tg-call] SetLocalDescription(answer) error: %v\n", err)
				return
			}
			call.localSDP = answer.SDP // store for ICE credential reuse
			// Determine our DTLS role from our answer's setup attribute
			for _, line := range strings.Split(answer.SDP, "\r\n") {
				if strings.HasPrefix(line, "a=setup:") {
					call.dtlsRole = strings.TrimPrefix(line, "a=setup:")
					fmt.Printf("[tg-call] Our DTLS role from answer: %s\n", call.dtlsRole)
					break
				}
			}
			fmt.Printf("[tg-call] SDP answer created and set\n")

			t.sendCallSignaling(call, map[string]interface{}{
				"@type": "answer",
				"sdp":   answer.SDP,
			})
			fmt.Printf("[tg-call] SDP answer sent\n")

			ansVideoState := "inactive"
			if call.isVideo {
				ansVideoState = "active"
			}
			t.sendCallSignaling(call, map[string]interface{}{
				"@type":          "MediaState",
				"muted":          false,
				"videoState":     ansVideoState,
				"videoRotation":  0,
				"screencastState": "inactive",
				"lowBattery":     false,
			})
		} else {
			// RE-OFFER (official client sends its own offer after answering ours with recvonly).
			// Process through pion's normal SetRemoteDescription + CreateAnswer.
			// IMPORTANT: static ICE credentials (SetICECredentials in SettingEngine) ensure
			// the answer uses the SAME ufrag/pwd as our original offer, preventing ICE restart.
			call.remoteOfferCount++
			fmt.Printf("[tg-call] Re-offer #%d received\n", call.remoteOfferCount)

			// Wait for DTLS to be ready before processing re-offer.
			// pion's undeclaredMediaProcessor needs an active SRTP session (from DTLS)
			// to handle incoming RTP with undeclared SSRCs. If we process the re-offer
			// before DTLS, the processor fails and incoming RTP is silently dropped.
			if call.pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
				fmt.Printf("[tg-call] Re-offer received but DTLS not ready (state=%s), deferring...\n", call.pc.ConnectionState())
				call.mu.Unlock()
				select {
				case <-call.pcReady:
				case <-time.After(15 * time.Second):
				}
				call.mu.Lock()
				if call.pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
					fmt.Printf("[tg-call] Re-offer deferred but DTLS never connected, giving up\n")
					return
				}
				fmt.Printf("[tg-call] DTLS now ready, processing deferred re-offer\n")
			}

			fmt.Printf("[tg-call] Processing re-offer via pion (%d bytes, sigState=%s)\n", len(sdp), call.pc.SignalingState())

			// Desktop/tgcalls sends a re-offer with extra audio m-lines.
			// Ensure we have enough audio transceivers for the extra m-lines.
			audioCount := strings.Count(sdp, "m=audio ")
			existingAudioTransceivers := 0
			for _, tr := range call.pc.GetTransceivers() {
				if tr.Kind() == webrtc.RTPCodecTypeAudio {
					existingAudioTransceivers++
				}
			}
			for i := existingAudioTransceivers; i < audioCount; i++ {
				fmt.Printf("[tg-call] Adding recvonly audio transceiver for re-offer (existing=%d, need=%d)\n", existingAudioTransceivers, audioCount)
				call.pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
					Direction: webrtc.RTPTransceiverDirectionRecvonly,
				})
			}

			if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
				Type: webrtc.SDPTypeOffer,
				SDP:  sdp,
			}); err != nil {
				fmt.Printf("[tg-call] SetRemoteDescription(re-offer) error: %v\n", err)
				return
			}
			answer, err := call.pc.CreateAnswer(nil)
			if err != nil {
				fmt.Printf("[tg-call] CreateAnswer(re-offer) error: %v\n", err)
				return
			}
			// Set local description with unmodified SDP (pion validates against its state)
			if err := call.pc.SetLocalDescription(answer); err != nil {
				fmt.Printf("[tg-call] SetLocalDescription(re-offer) error: %v\n", err)
				return
			}
			// Fix DTLS role in the SDP we SEND: during re-offers, the DTLS role
			// must NOT change. If we were the DTLS server (passive) in the initial
			// exchange, the sent answer must also say passive. Pion defaults to
			// active which causes "Failed to set SSL role" on the remote side.
			answerSDP := answer.SDP
			if call.dtlsRole == "passive" {
				answerSDP = strings.ReplaceAll(answerSDP, "a=setup:active\r\n", "a=setup:passive\r\n")
			} else if call.dtlsRole == "active" {
				answerSDP = strings.ReplaceAll(answerSDP, "a=setup:passive\r\n", "a=setup:active\r\n")
			}
			fmt.Printf("[tg-call] Re-offer answer created (%d bytes, dtlsRole=%s)\n", len(answerSDP), call.dtlsRole)
			// Log re-offer answer: direction + mid + setup
			for _, line := range strings.Split(answerSDP, "\r\n") {
				if strings.HasPrefix(line, "a=mid:") ||
					line == "a=sendrecv" || line == "a=recvonly" || line == "a=sendonly" || line == "a=inactive" ||
					strings.HasPrefix(line, "a=setup:") {
					fmt.Printf("[tg-call] RE-OFFER ANS: %s\n", line)
				}
			}

			t.sendCallSignaling(call, map[string]interface{}{
				"@type": "answer",
				"sdp":   answerSDP,
			})
			fmt.Printf("[tg-call] Re-offer answer sent\n")

			roVideoState := "inactive"
			if call.isVideo {
				roVideoState = "active"
			}
			t.sendCallSignaling(call, map[string]interface{}{
				"@type":          "MediaState",
				"muted":          false,
				"videoState":     roVideoState,
				"videoRotation":  0,
				"screencastState": "inactive",
				"lowBattery":     false,
			})
		}
	} else if sdpType == "answer" {
		// Ignore duplicate answers
		if call.remoteSDPSet {
			fmt.Printf("[tg-call] Ignoring duplicate SDP answer (already handled)\n")
			return
		}

		// Outgoing side: we sent the offer, set remote answer
		if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeAnswer,
			SDP:  sdp,
		}); err != nil {
			fmt.Printf("[tg-call] SetRemoteDescription(answer) error: %v\n", err)
			return
		}
		call.remoteSDPSet = true
		// Determine our DTLS role from the remote answer's setup attribute.
		// Remote active → we are passive (server). Remote passive → we are active (client).
		for _, line := range strings.Split(sdp, "\r\n") {
			if strings.HasPrefix(line, "a=setup:") {
				remoteSetup := strings.TrimPrefix(line, "a=setup:")
				if remoteSetup == "active" {
					call.dtlsRole = "passive"
				} else if remoteSetup == "passive" {
					call.dtlsRole = "active"
				}
				fmt.Printf("[tg-call] Remote DTLS setup=%s → our role=%s\n", remoteSetup, call.dtlsRole)
				break
			}
		}
		fmt.Printf("[tg-call] Remote answer set\n")

		// Extract remote video/screen SSRCs from SDP for OnTrack dispatch
		extractRemoteVideoSSRCs(call, sdp)
	}

	// Flush pending ICE candidates
	for _, c := range call.pendingCandidates {
		if err := call.pc.AddICECandidate(c); err != nil {
			fmt.Printf("[tg-call] AddICECandidate error: %v\n", err)
		}
	}
	if len(call.pendingCandidates) > 0 {
		fmt.Printf("[tg-call] Flushed %d pending candidates\n", len(call.pendingCandidates))
	}
	call.pendingCandidates = nil
}

// handleRemoteCandidate adds or queues an ICE candidate from V2Reference signaling.
func (t *TelegramCore) handleRemoteCandidate(call *tgCall, sdp string, mid string, mline int) {
	// Skip reflector candidates (non-standard format pion can't parse)
	if strings.Contains(sdp, ".reflector") {
		return
	}

	call.mu.Lock()
	defer call.mu.Unlock()

	mlineIdx := uint16(mline)
	init := webrtc.ICECandidateInit{
		Candidate:     sdp,
		SDPMid:        &mid,
		SDPMLineIndex: &mlineIdx,
	}

	// If we have remote description set, add immediately; otherwise queue
	if call.pc != nil && call.pc.RemoteDescription() != nil {
		if err := call.pc.AddICECandidate(init); err != nil {
			fmt.Printf("[tg-call] AddICECandidate error: %v\n", err)
		}
	} else {
		call.pendingCandidates = append(call.pendingCandidates, init)
	}
}

// handleRemoteInitialSetupV2Impl processes a remote InitialSetup message for V2Impl signaling.
// Stores the setup and, if NegotiateChannels is already received, triggers SDP setup.
// The callee's own InitialSetup is sent from trySetRemoteV2Impl (after CreateAnswer)
// to ensure we have the correct DTLS setup value from pion's answer.
// handleRemoteInitialSetupWeb handles InitialSetup from Telegram Web (v4.0.0).
// Web sends a single InitialSetup with inline audio/video/screencast media content.
// No NegotiateChannels exchange — simpler than V2Impl.
func (t *TelegramCore) handleRemoteInitialSetupWeb(call *tgCall, setup *tgInitialSetup) {
	// Wait for PC to be ready
	if call.localSDPReady != nil {
		select {
		case <-call.localSDPReady:
		case <-time.After(10 * time.Second):
			fmt.Printf("[tg-call] Web: timeout waiting for PC ready\n")
			return
		}
	}

	call.mu.Lock()
	alreadySet := call.remoteSDPSet
	call.mu.Unlock()
	if alreadySet {
		return // already processed
	}
	if call.pc == nil {
		fmt.Printf("[tg-call] Web: no PeerConnection\n")
		return
	}

	// Extract remote media SSRCs for OnTrack dispatch
	if setup.Video != nil && setup.Video.SSRC != "" {
		var ssrc uint32
		fmt.Sscanf(setup.Video.SSRC, "%d", &ssrc)
		call.remoteVideoSSRC = ssrc
	}
	if setup.Screencast != nil && setup.Screencast.SSRC != "" {
		var ssrc uint32
		fmt.Sscanf(setup.Screencast.SSRC, "%d", &ssrc)
		call.remoteScreenSSRC = ssrc
	}
	fmt.Printf("[tg-call] Web: remote SSRCs: video=%d screencast=%d\n", call.remoteVideoSSRC, call.remoteScreenSSRC)

	// Build synthetic SDP from the web InitialSetup
	syntheticSDP := buildSyntheticSDPFromWebSetup(setup, map[bool]string{true: "answer", false: "offer"}[call.isOutgoing])
	sdpType := webrtc.SDPTypeOffer
	if call.isOutgoing {
		sdpType = webrtc.SDPTypeAnswer
	}

	fmt.Printf("[tg-call] Web: built synthetic %s SDP (%d bytes)\n", sdpType, len(syntheticSDP))

	call.mu.Lock()
	if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: sdpType,
		SDP:  syntheticSDP,
	}); err != nil {
		call.mu.Unlock()
		fmt.Printf("[tg-call] Web: SetRemoteDescription error: %v\n", err)
		return
	}
	call.remoteSDPSet = true
	pending := call.pendingCandidates
	call.pendingCandidates = nil
	call.mu.Unlock()

	fmt.Printf("[tg-call] Web: remote %s set, flushing %d pending candidates\n", sdpType, len(pending))

	// Flush pending candidates
	for _, c := range pending {
		if err := call.pc.AddICECandidate(c); err != nil {
			fmt.Printf("[tg-call] Web: AddICECandidate error: %v\n", err)
		}
	}

	if !call.isOutgoing {
		// INCOMING: create answer and send our InitialSetup
		answer, err := call.pc.CreateAnswer(nil)
		if err != nil {
			fmt.Printf("[tg-call] Web: CreateAnswer error: %v\n", err)
			return
		}
		if err := call.pc.SetLocalDescription(answer); err != nil {
			fmt.Printf("[tg-call] Web: SetLocalDescription error: %v\n", err)
			return
		}

		call.mu.Lock()
		call.localSDP = answer.SDP
		call.mu.Unlock()

		// Send our InitialSetup with inline audio
		ourSetup := extractWebInitialSetupFromSDP(answer.SDP, false)
		// Save declared screencast SSRC so StartScreenShare uses the same one
		if ourSetup.Screencast != nil && ourSetup.Screencast.SSRC != "" {
			var scrSSRC uint32
			fmt.Sscanf(ourSetup.Screencast.SSRC, "%d", &scrSSRC)
			if scrSSRC != 0 {
				call.screenSSRC = scrSSRC
				fmt.Printf("[tg-call] Saved our screencast SSRC: %d\n", scrSSRC)
			}
		}
		t.sendCallSignaling(call, ourSetup)
		fmt.Printf("[tg-call] Web: sent InitialSetup answer (ufrag=%s, audio.ssrc=%s)\n",
			ourSetup.Ufrag, ourSetup.Audio.SSRC)

		// Extract SSRC from our answer
		for _, line := range strings.Split(answer.SDP, "\r\n") {
			if strings.HasPrefix(line, "a=ssrc:") {
				parts := strings.SplitN(strings.TrimPrefix(line, "a=ssrc:"), " ", 2)
				if len(parts) >= 1 {
					ssrcVal := uint32(0)
					fmt.Sscanf(parts[0], "%d", &ssrcVal)
					if ssrcVal != 0 && call.audioSSRC == 0 {
						call.audioSSRC = ssrcVal
					}
				}
				break
			}
		}

		// Post-DTLS reoffer for SRTP receive streams
		go func() {
			tick := time.NewTicker(100 * time.Millisecond)
			defer tick.Stop()
			for i := 0; i < 150; i++ {
				if call.pc.ConnectionState() == webrtc.PeerConnectionStateConnected {
					break
				}
				if call.pc.ConnectionState() == webrtc.PeerConnectionStateClosed ||
					call.pc.ConnectionState() == webrtc.PeerConnectionStateFailed {
					return
				}
				select {
				case <-call.done:
					return
				case <-tick.C:
				}
			}
			if call.pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
				return
			}
			fmt.Printf("[tg-call] Web incoming: DTLS ready, doing reoffer\n")
			reofferSDP := buildSyntheticSDPFromWebSetup(setup, "offer")
			call.mu.Lock()
			if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
				Type: webrtc.SDPTypeOffer,
				SDP:  reofferSDP,
			}); err != nil {
				call.mu.Unlock()
				fmt.Printf("[tg-call] Web reoffer error: %v\n", err)
				return
			}
			call.mu.Unlock()
			ans, err := call.pc.CreateAnswer(nil)
			if err != nil {
				return
			}
			call.pc.SetLocalDescription(ans)
			fmt.Printf("[tg-call] Web incoming reoffer done\n")
		}()
	}

	// Send MediaState
	v2iVideoState := "inactive"
	if call.isVideo {
		v2iVideoState = "active"
	}
	t.sendCallSignaling(call, &tgMediaState{
		Type:            "MediaState",
		Muted:           false,
		VideoState:      v2iVideoState,
		VideoRotation:   0,
		ScreencastState: "inactive",
		LowBattery:      false,
	})
}

func (t *TelegramCore) handleRemoteInitialSetupV2Impl(call *tgCall, setup *tgInitialSetup) {
	call.mu.Lock()
	call.remoteInitialSetup = setup
	call.v2ImplHandshakeDone = true
	hasNC := call.remoteNegChannels != nil
	call.mu.Unlock()

	// If both InitialSetup and NegotiateChannels received, build synthetic SDP
	if hasNC {
		t.trySetRemoteV2Impl(call)
	}
}

// handleRemoteNegotiateChannelsV2Impl processes a remote NegotiateChannels message.
// Handles two types:
// 1. Answer to our offer (same exchangeId): confirms our outgoing audio → triggers SDP setup
// 2. Remote's own offer (different exchangeId): declares remote's sending SSRC → we answer it
func (t *TelegramCore) handleRemoteNegotiateChannelsV2Impl(call *tgCall, nc *tgNegotiateChannels) {
	call.mu.Lock()
	ourExchangeID := strconv.FormatUint(uint64(call.v2ImplExchangeSeq), 10)
	alreadySet := call.remoteSDPSet
	call.mu.Unlock()

	if nc.ExchangeID == ourExchangeID {
		// Answer to our offer — store and trigger SDP setup
		call.mu.Lock()
		call.remoteNegChannels = nc
		hasSetup := call.remoteInitialSetup != nil
		call.mu.Unlock()

		if hasSetup {
			t.trySetRemoteV2Impl(call)
		}
	} else if alreadySet && call.isOutgoing {
		// Remote's own offer arrived AFTER initial SDP setup — renegotiate immediately
		t.processRemoteV2ImplOffer(call, nc)
	} else if call.isOutgoing && nc.ExchangeID != ourExchangeID {
		// Remote's own offer arrived BEFORE initial SDP setup — store for later
		call.mu.Lock()
		call.remoteNegChannelsOffer = nc
		call.mu.Unlock()
		fmt.Printf("[tg-call] V2Impl: stored remote's NegotiateChannels offer (exchangeId=%s) for later\n", nc.ExchangeID)
	} else {
		// First NegotiateChannels from remote (incoming side), not matching our exchangeId
		call.mu.Lock()
		if call.remoteNegChannels == nil {
			call.remoteNegChannels = nc
		}
		hasSetup := call.remoteInitialSetup != nil
		call.mu.Unlock()

		if hasSetup {
			t.trySetRemoteV2Impl(call)
		}
	}
}

// trySetRemoteV2Impl builds a synthetic SDP from remote InitialSetup + NegotiateChannels
// and sets it as the remote description on the PeerConnection.
func (t *TelegramCore) trySetRemoteV2Impl(call *tgCall) {
	// Wait for PC to be ready
	if call.localSDPReady != nil {
		select {
		case <-call.localSDPReady:
		case <-time.After(10 * time.Second):
			fmt.Printf("[tg-call] V2Impl: timeout waiting for PC ready\n")
			return
		}
	}

	call.mu.Lock()
	setup := call.remoteInitialSetup
	nc := call.remoteNegChannels
	alreadySet := call.remoteSDPSet
	call.mu.Unlock()

	if setup == nil || nc == nil || alreadySet {
		return
	}

	if call.pc == nil {
		fmt.Printf("[tg-call] V2Impl: no PeerConnection\n")
		return
	}

	// Extract remote video/screen SSRCs from NegotiateChannels for OnTrack dispatch
	videoIdx := 0
	for _, content := range nc.Contents {
		if content.Type == "video" && content.SSRC != "" {
			var ssrc uint32
			fmt.Sscanf(content.SSRC, "%d", &ssrc)
			if videoIdx == 0 {
				call.remoteVideoSSRC = ssrc
			} else {
				call.remoteScreenSSRC = ssrc
			}
			videoIdx++
		}
	}
	if call.remoteScreenSSRC != 0 {
		fmt.Printf("[tg-call] V2Impl: remote SSRCs: video=%d screencast=%d\n", call.remoteVideoSSRC, call.remoteScreenSSRC)
	}

	if call.isOutgoing {
		// OUTGOING: we already sent offer, remote sends answer
		// Build synthetic SDP answer from remote's InitialSetup + NegotiateChannels
		syntheticSDP := buildSyntheticSDPFromV2Impl(setup, nc, "answer", call.audioSSRC)
		fmt.Printf("[tg-call] V2Impl: built synthetic answer SDP (%d bytes)\n", len(syntheticSDP))
		fmt.Printf("[tg-call] V2Impl SYNTHETIC ANSWER:\n%s\n", syntheticSDP)

		call.mu.Lock()
		if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeAnswer,
			SDP:  syntheticSDP,
		}); err != nil {
			call.mu.Unlock()
			fmt.Printf("[tg-call] V2Impl: SetRemoteDescription(answer) error: %v\n", err)
			return
		}
		call.remoteSDPSet = true
		pending := call.pendingCandidates
		call.pendingCandidates = nil
		call.mu.Unlock()

		fmt.Printf("[tg-call] V2Impl: remote answer set (outgoing)\n")

		// Flush pending candidates
		for _, c := range pending {
			if err := call.pc.AddICECandidate(c); err != nil {
				fmt.Printf("[tg-call] V2Impl: AddICECandidate error: %v\n", err)
			}
		}
		if len(pending) > 0 {
			fmt.Printf("[tg-call] V2Impl: flushed %d pending candidates\n", len(pending))
		}

		// Send MediaState
		implInVS := "inactive"
		if call.isVideo {
			implInVS = "active"
		}
		t.sendCallSignaling(call, &tgMediaState{
			Type:            "MediaState",
			Muted:           false,
			VideoState:      implInVS,
			VideoRotation:   0,
			ScreencastState: "inactive",
			LowBattery:      false,
		})

		// Process any stored NegotiateChannels offer (remote's own offer that arrived before InitialSetup)
		call.mu.Lock()
		pendingOffer := call.remoteNegChannelsOffer
		call.remoteNegChannelsOffer = nil
		call.mu.Unlock()
		if pendingOffer != nil {
			t.processRemoteV2ImplOffer(call, pendingOffer)
		}
	} else {
		// INCOMING: remote (caller) sends offer, we create answer
		// Build synthetic SDP offer from remote's InitialSetup + NegotiateChannels
		syntheticSDP := buildSyntheticSDPFromV2Impl(setup, nc, "offer")
		fmt.Printf("[tg-call] V2Impl: built synthetic offer SDP (%d bytes)\n", len(syntheticSDP))
		fmt.Printf("[tg-call] V2Impl SYNTHETIC OFFER:\n%s\n", syntheticSDP)

		call.mu.Lock()
		if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeOffer,
			SDP:  syntheticSDP,
		}); err != nil {
			call.mu.Unlock()
			fmt.Printf("[tg-call] V2Impl: SetRemoteDescription(offer) error: %v\n", err)
			return
		}
		call.remoteSDPSet = true
		call.mu.Unlock()

		fmt.Printf("[tg-call] V2Impl: remote offer set (incoming)\n")

		// Create answer
		answer, err := call.pc.CreateAnswer(nil)
		if err != nil {
			fmt.Printf("[tg-call] V2Impl: CreateAnswer error: %v\n", err)
			return
		}
		if err := call.pc.SetLocalDescription(answer); err != nil {
			fmt.Printf("[tg-call] V2Impl: SetLocalDescription(answer) error: %v\n", err)
			return
		}

		call.mu.Lock()
		call.localSDP = answer.SDP
		call.mu.Unlock()

		fmt.Printf("[tg-call] V2Impl: answer created (%d bytes)\n", len(answer.SDP))

		// Now send our InitialSetup — extracted from the ANSWER SDP so DTLS setup is correct.
		// pion answers "actpass" with "active" (DTLS client/initiator).
		ourSetup, ourNC := extractV2ImplFromSDP(answer.SDP, false)
		t.sendCallSignaling(call, ourSetup)
		fmt.Printf("[tg-call] V2Impl: sent InitialSetup (ufrag=%s, setup=%s)\n",
			ourSetup.Ufrag, ourSetup.Fingerprints[0].Setup)

		// Send NegotiateChannels answer: echo remote's offer contents entirely.
		// Must use remote's codecs/SSRCs/ssrcGroups — NOT pion's. Pion's codec list
		// includes orphan rtx codecs (apt=116 for AV1 etc.) that C++ rejects.
		answerNC := &tgNegotiateChannels{
			Type:       "NegotiateChannels",
			ExchangeID: nc.ExchangeID,
			Contents:   nc.Contents, // echo offer contents exactly
		}
		t.sendCallSignaling(call, answerNC)
		fmt.Printf("[tg-call] V2Impl: sent NegotiateChannels answer (exchangeId=%s, ssrc=%s [echoed remote])\n",
			answerNC.ExchangeID, answerNC.Contents[0].SSRC)

		// Also send our OWN NegotiateChannels offer (new exchangeId, our SSRC).
		// This tells C++ what we'll be sending. C++ will answer with our exchangeId.
		var eidBuf [4]byte
		rand.Read(eidBuf[:])
		ownExchangeID := strconv.FormatUint(uint64(binary.BigEndian.Uint32(eidBuf[:])), 10)
		ourNC.ExchangeID = ownExchangeID
		t.sendCallSignaling(call, ourNC)
		fmt.Printf("[tg-call] V2Impl: sent NegotiateChannels own offer (exchangeId=%s, ssrc=%s)\n",
			ourNC.ExchangeID, ourNC.Contents[0].SSRC)

		// Extract SSRC from our answer
		for _, line := range strings.Split(answer.SDP, "\r\n") {
			if strings.HasPrefix(line, "a=ssrc:") {
				parts := strings.SplitN(strings.TrimPrefix(line, "a=ssrc:"), " ", 2)
				if len(parts) >= 1 {
					ssrcVal := uint32(0)
					fmt.Sscanf(parts[0], "%d", &ssrcVal)
					if ssrcVal != 0 && call.audioSSRC == 0 {
						call.audioSSRC = ssrcVal
						fmt.Printf("[tg-call] V2Impl: set audioSSRC from answer: %d\n", ssrcVal)
					}
				}
				break
			}
		}

		// Flush pending candidates
		call.mu.Lock()
		pending := call.pendingCandidates
		call.pendingCandidates = nil
		call.mu.Unlock()
		for _, c := range pending {
			if err := call.pc.AddICECandidate(c); err != nil {
				fmt.Printf("[tg-call] V2Impl: AddICECandidate error: %v\n", err)
			}
		}
		if len(pending) > 0 {
			fmt.Printf("[tg-call] V2Impl: flushed %d pending candidates\n", len(pending))
		}

		// Send MediaState
		implOutVS := "inactive"
		if call.isVideo {
			implOutVS = "active"
		}
		t.sendCallSignaling(call, &tgMediaState{
			Type:            "MediaState",
			Muted:           false,
			VideoState:      implOutVS,
			VideoRotation:   0,
			ScreencastState: "inactive",
			LowBattery:      false,
		})

		// V2Impl incoming: the initial SetRemoteDescription(offer) happens BEFORE
		// DTLS/SRTP is ready. pion's RTP receive streams fail to initialize at that
		// point and never retry. Fix: do a manual reoffer AFTER DTLS connects to
		// re-register the SRTP receive streams. Same pattern as V2Reference's
		// deferred re-offer fix.
		go func() {
			select {
			case <-call.pcReady:
			case <-call.done:
				return
			case <-time.After(15 * time.Second):
			}
			if call.pc.ConnectionState() != webrtc.PeerConnectionStateConnected {
				fmt.Printf("[tg-call] V2Impl incoming: DTLS never connected, skipping reoffer\n")
				return
			}

			fmt.Printf("[tg-call] V2Impl incoming: DTLS ready, doing reoffer to fix SRTP receive\n")
			call.mu.Lock()
			remoteSetup := call.remoteInitialSetup
			remoteNC := call.remoteNegChannels
			call.mu.Unlock()
			if remoteSetup == nil || remoteNC == nil {
				return
			}

			syntheticOffer := buildSyntheticSDPFromV2Impl(remoteSetup, remoteNC, "offer")

			// Add extra recvonly transceiver for the re-offer's audio m-line
			audioCount := strings.Count(syntheticOffer, "m=audio ")
			existingAudio := 0
			for _, tr := range call.pc.GetTransceivers() {
				if tr.Kind() == webrtc.RTPCodecTypeAudio {
					existingAudio++
				}
			}
			for i := existingAudio; i < audioCount+1; i++ {
				call.pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
					Direction: webrtc.RTPTransceiverDirectionRecvonly,
				})
			}

			call.mu.Lock()
			if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
				Type: webrtc.SDPTypeOffer,
				SDP:  syntheticOffer,
			}); err != nil {
				call.mu.Unlock()
				fmt.Printf("[tg-call] V2Impl incoming reoffer: SetRemoteDescription error: %v\n", err)
				return
			}
			call.mu.Unlock()

			answer, err := call.pc.CreateAnswer(nil)
			if err != nil {
				fmt.Printf("[tg-call] V2Impl incoming reoffer: CreateAnswer error: %v\n", err)
				return
			}
			if err := call.pc.SetLocalDescription(answer); err != nil {
				fmt.Printf("[tg-call] V2Impl incoming reoffer: SetLocalDescription error: %v\n", err)
				return
			}
			fmt.Printf("[tg-call] V2Impl incoming reoffer: done — SRTP receive streams should be active\n")
		}()
	}
}

// processRemoteV2ImplOffer handles the remote's own NegotiateChannels offer (different exchangeId).
// This contains the remote's ACTUAL sending SSRC. We answer it and do a pion renegotiation.
func (t *TelegramCore) processRemoteV2ImplOffer(call *tgCall, nc *tgNegotiateChannels) {
	remoteSSRC := ""
	if len(nc.Contents) > 0 {
		remoteSSRC = nc.Contents[0].SSRC
	}

	// Dedup: skip if we've already answered this exchangeId (retransmit from remote)
	call.mu.Lock()
	if call.answeredExchangeIDs == nil {
		call.answeredExchangeIDs = make(map[string]bool)
	}
	if call.answeredExchangeIDs[nc.ExchangeID] {
		call.mu.Unlock()
		return // already processed, skip retransmit
	}
	call.answeredExchangeIDs[nc.ExchangeID] = true
	call.mu.Unlock()

	fmt.Printf("[tg-call] V2Impl: processing remote's NegotiateChannels offer (exchangeId=%s, ssrc=%s, contents=%d)\n",
		nc.ExchangeID, remoteSSRC, len(nc.Contents))

	// NC answer: echo back the remote's offer contents entirely.
	// Must use remote's codecs/SSRCs/ssrcGroups — NOT pion's. Pion's codec list
	// includes orphan rtx codecs (apt=116 for AV1 etc.) that C++ V2Impl's
	// SetLocalContent rejects with "Failed to set local video description recv parameters".
	answerNC := &tgNegotiateChannels{
		Type:       "NegotiateChannels",
		ExchangeID: nc.ExchangeID,
		Contents:   nc.Contents, // echo offer contents exactly
	}
	t.sendCallSignaling(call, answerNC)
	fmt.Printf("[tg-call] V2Impl: sent NC answer (echo, %d contents)\n", len(answerNC.Contents))

	// Renegotiate to register remote's sending SSRC
	call.mu.Lock()
	setup := call.remoteInitialSetup
	call.mu.Unlock()

	// Renegotiate to register remote's sending SSRC
	if setup != nil && call.pc != nil && remoteSSRC != "" {
		call.mu.Lock()
		reofferCount := call.remoteOfferCount
		call.remoteOfferCount++
		call.mu.Unlock()

		if reofferCount == 0 {
			go t.handleV2ImplReoffer(call, setup, nc)
		}
	}
}

// handleV2ImplReoffer processes Desktop's own NegotiateChannels offer by doing a pion renegotiation.
// This registers Desktop's sending SSRC so pion can receive incoming audio.
// Called as a goroutine from handleRemoteNegotiateChannelsV2Impl.
func (t *TelegramCore) handleV2ImplReoffer(call *tgCall, setup *tgInitialSetup, nc *tgNegotiateChannels) {
	// Wait for PeerConnection to reach at least "connecting" state (SDP must be set first).
	// SDP renegotiation works before DTLS connects — we don't need to wait for full "connected".
	if call.localSDPReady != nil {
		select {
		case <-call.localSDPReady:
		case <-time.After(10 * time.Second):
			fmt.Printf("[tg-call] V2Impl reoffer: timeout waiting for local SDP ready\n")
			return
		}
	}

	// Build synthetic re-offer with Desktop's SSRC (this is an "offer" from the remote)
	syntheticOffer := buildSyntheticSDPFromV2Impl(setup, nc, "offer")
	fmt.Printf("[tg-call] V2Impl reoffer: built synthetic offer with remote SSRC (%d bytes)\n", len(syntheticOffer))

	// Ensure we have enough transceivers for the re-offer
	audioCount := strings.Count(syntheticOffer, "m=audio ")
	existingAudio := 0
	for _, tr := range call.pc.GetTransceivers() {
		if tr.Kind() == webrtc.RTPCodecTypeAudio {
			existingAudio++
		}
	}
	for i := existingAudio; i < audioCount+1; i++ {
		call.pc.AddTransceiverFromKind(webrtc.RTPCodecTypeAudio, webrtc.RTPTransceiverInit{
			Direction: webrtc.RTPTransceiverDirectionRecvonly,
		})
	}

	call.mu.Lock()
	if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeOffer,
		SDP:  syntheticOffer,
	}); err != nil {
		call.mu.Unlock()
		fmt.Printf("[tg-call] V2Impl reoffer: SetRemoteDescription error: %v\n", err)
		return
	}
	call.mu.Unlock()

	answer, err := call.pc.CreateAnswer(nil)
	if err != nil {
		fmt.Printf("[tg-call] V2Impl reoffer: CreateAnswer error: %v\n", err)
		return
	}
	if err := call.pc.SetLocalDescription(answer); err != nil {
		fmt.Printf("[tg-call] V2Impl reoffer: SetLocalDescription error: %v\n", err)
		return
	}

	fmt.Printf("[tg-call] V2Impl reoffer: done — remote SSRC registered for incoming audio\n")
}

// gzipDecompress decompresses gzip-compressed data.
// generateICECredential generates a random ICE credential string of the given length.
func generateICECredential(length int) string {
	const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	rand.Read(b)
	for i := range b {
		b[i] = chars[int(b[i])%len(chars)]
	}
	return string(b)
}

// replaceICECredentials replaces ICE ufrag/pwd in newSDP with those from originalSDP.
// This prevents the official client from seeing an ICE restart when we answer a re-offer.
func replaceICECredentials(newSDP, originalSDP string) string {
	origUfrag := extractSDPAttr(originalSDP, "a=ice-ufrag:")
	origPwd := extractSDPAttr(originalSDP, "a=ice-pwd:")
	if origUfrag == "" || origPwd == "" {
		return newSDP // can't replace, return as-is
	}

	// Replace all ice-ufrag and ice-pwd lines in the new SDP
	lines := strings.Split(newSDP, "\r\n")
	var result []string
	for _, line := range lines {
		if strings.HasPrefix(line, "a=ice-ufrag:") {
			result = append(result, "a=ice-ufrag:"+origUfrag)
		} else if strings.HasPrefix(line, "a=ice-pwd:") {
			result = append(result, "a=ice-pwd:"+origPwd)
		} else {
			result = append(result, line)
		}
	}
	return strings.Join(result, "\r\n")
}

// buildReofferAnswer constructs an SDP answer to the official client's re-offer,
// reusing ICE credentials and DTLS fingerprint from our initial offer SDP.
// This avoids pion generating new ICE credentials which would trigger an ICE restart.
func buildReofferAnswer(offerSDP, localSDP string) string {
	// Extract our ICE ufrag, pwd, and DTLS fingerprint from our initial offer
	localUfrag := extractSDPAttr(localSDP, "a=ice-ufrag:")
	localPwd := extractSDPAttr(localSDP, "a=ice-pwd:")
	localFingerprint := extractSDPAttr(localSDP, "a=fingerprint:")
	if localUfrag == "" || localPwd == "" || localFingerprint == "" {
		return ""
	}

	// Parse the offer's m= sections
	lines := strings.Split(offerSDP, "\r\n")
	var answer strings.Builder

	// Session-level lines
	answer.WriteString("v=0\r\n")
	answer.WriteString("o=- 1 2 IN IP4 127.0.0.1\r\n")
	answer.WriteString("s=-\r\n")
	answer.WriteString("t=0 0\r\n")

	// Find BUNDLE groups from offer
	for _, line := range lines {
		if strings.HasPrefix(line, "a=group:BUNDLE") {
			answer.WriteString(line + "\r\n")
			break
		}
	}
	answer.WriteString("a=extmap-allow-mixed\r\n")
	answer.WriteString("a=msid-semantic:WMS *\r\n")

	// Process each m= section from the offer
	inMedia := false
	mediaType := ""
	for _, line := range lines {
		if strings.HasPrefix(line, "m=") {
			inMedia = true
			if strings.HasPrefix(line, "m=audio") {
				mediaType = "audio"
				// Accept audio with opus codec (PT 111)
				answer.WriteString("m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n")
				answer.WriteString("c=IN IP4 0.0.0.0\r\n")
				answer.WriteString("a=rtcp:9 IN IP4 0.0.0.0\r\n")
				answer.WriteString("a=ice-ufrag:" + localUfrag + "\r\n")
				answer.WriteString("a=ice-pwd:" + localPwd + "\r\n")
				answer.WriteString("a=ice-options:trickle\r\n")
				answer.WriteString("a=fingerprint:" + localFingerprint + "\r\n")
				answer.WriteString("a=setup:active\r\n") // we take active DTLS role
				// Extract mid from offer
				mid := extractMediaAttr(lines, "m=audio", "a=mid:")
				if mid != "" {
					answer.WriteString("a=mid:" + mid + "\r\n")
				}
				answer.WriteString("a=rtpmap:111 opus/48000/2\r\n")
				answer.WriteString("a=fmtp:111 minptime=10;useinbandfec=1\r\n")
				answer.WriteString("a=rtcp-fb:111 transport-cc\r\n")
				answer.WriteString("a=rtcp-mux\r\n")
				answer.WriteString("a=rtcp-rsize\r\n")
				answer.WriteString("a=sendrecv\r\n")
			} else if strings.HasPrefix(line, "m=video") {
				mediaType = "video"
				// Reject video (port 0)
				answer.WriteString("m=video 0 UDP/TLS/RTP/SAVPF 0\r\n")
				answer.WriteString("c=IN IP4 0.0.0.0\r\n")
				mid := extractMediaAttr(lines, "m=video", "a=mid:")
				if mid != "" {
					answer.WriteString("a=mid:" + mid + "\r\n")
				}
			} else if strings.HasPrefix(line, "m=application") {
				mediaType = "application"
				// Accept data channel
				answer.WriteString("m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n")
				answer.WriteString("c=IN IP4 0.0.0.0\r\n")
				answer.WriteString("a=ice-ufrag:" + localUfrag + "\r\n")
				answer.WriteString("a=ice-pwd:" + localPwd + "\r\n")
				answer.WriteString("a=ice-options:trickle\r\n")
				answer.WriteString("a=fingerprint:" + localFingerprint + "\r\n")
				answer.WriteString("a=setup:active\r\n")
				mid := extractMediaAttr(lines, "m=application", "a=mid:")
				if mid != "" {
					answer.WriteString("a=mid:" + mid + "\r\n")
				}
				answer.WriteString("a=sctp-port:5000\r\n")
			}
			continue
		}
		_ = mediaType
		_ = inMedia
	}

	return answer.String()
}

// extractSDPAttr extracts a session-level attribute value from SDP.
func extractSDPAttr(sdp, prefix string) string {
	for _, line := range strings.Split(sdp, "\r\n") {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimPrefix(line, prefix)
		}
	}
	// Try \n only (pion sometimes uses just \n)
	for _, line := range strings.Split(sdp, "\n") {
		line = strings.TrimRight(line, "\r")
		if strings.HasPrefix(line, prefix) {
			return strings.TrimPrefix(line, prefix)
		}
	}
	return ""
}

// extractMediaAttr extracts a media-level attribute from the first occurrence of a media type.
func extractMediaAttr(lines []string, mediaPrefix, attrPrefix string) string {
	inTarget := false
	for _, line := range lines {
		if strings.HasPrefix(line, "m=") {
			inTarget = strings.HasPrefix(line, mediaPrefix)
		}
		if inTarget && strings.HasPrefix(line, attrPrefix) {
			return strings.TrimPrefix(line, attrPrefix)
		}
	}
	return ""
}

func gzipDecompress(data []byte) ([]byte, error) {
	r, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer r.Close()
	return io.ReadAll(r)
}

// mathRandUint32 returns a random uint32 for SSRC generation.
func mathRandUint32() uint32 {
	b := make([]byte, 4)
	rand.Read(b)
	return binary.BigEndian.Uint32(b)
}

// JoinGroupCall joins an active group call in a chat.
func (t *TelegramCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return t.joinGroupCallInternal(chatID, false)
}

// JoinGroupCallWithVideo joins a group call with video enabled.
// video=true adds a VP8 video track to the SFU PeerConnection.
func (t *TelegramCore) JoinGroupCallWithVideo(chatID string, video bool) (*CallSession, error) {
	return t.joinGroupCallInternal(chatID, video)
}

func (t *TelegramCore) joinGroupCallInternal(chatID string, video bool) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	// callDone is closed when the call ends, signaling all goroutines to exit
	callDone := make(chan struct{})

	// Resolve the chat and find the active group call
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, fmt.Errorf("resolve peer: %w", err)
	}

	// Get the full chat to find the group call
	gcID, gcAccessHash, err := t.resolveGroupCall(peer)
	if err != nil {
		return nil, err
	}

	fmt.Printf("[tg-group] Found group call: id=%d video=%v\n", gcID, video)

	// Check if already in this call WITH a PeerConnection (fully joined).
	// If only created (no PC), remove and proceed with full join.
	t.mu.Lock()
	existing := t.activeCalls[gcID]
	if existing != nil && existing.pc != nil {
		t.mu.Unlock()
		return &CallSession{
			ID:    strconv.FormatInt(gcID, 10),
			State: existing.state,
		}, nil
	}
	// Remove placeholder from CreateGroupCall
	if existing != nil {
		delete(t.activeCalls, gcID)
	}
	t.mu.Unlock()

	// Create PeerConnection with custom MediaEngine that registers header extensions
	// in the exact order the SFU expects (IDs 1=ssrc-audio-level, 2=abs-send-time,
	// 3=transport-cc). Extension IDs must match on the wire since the SFU parses
	// RTP headers by position — a mismatch means the SFU can't read our extensions.
	me := &webrtc.MediaEngine{}
	me.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2,
			SDPFmtpLine:  "minptime=10;useinbandfec=1",
			RTCPFeedback: []webrtc.RTCPFeedback{{Type: "transport-cc"}},
		},
		PayloadType: 111,
	}, webrtc.RTPCodecTypeAudio)
	for _, ext := range []string{
		"urn:ietf:params:rtp-hdrext:ssrc-audio-level",
		"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
		"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01",
	} {
		me.RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability{URI: ext}, webrtc.RTPCodecTypeAudio)
	}

	// Register VP8 video codec if joining with video.
	// PTs must match the SFU's response: VP8=100, RTX=101 (Telegram SFU standard).
	if video {
		vp8Fbs := []webrtc.RTCPFeedback{
			{Type: "goog-remb"},
			{Type: "transport-cc"},
			{Type: "ccm", Parameter: "fir"},
			{Type: "nack"},
			{Type: "nack", Parameter: "pli"},
		}
		me.RegisterCodec(webrtc.RTPCodecParameters{
			RTPCodecCapability: webrtc.RTPCodecCapability{
				MimeType: webrtc.MimeTypeVP8, ClockRate: 90000,
				RTCPFeedback: vp8Fbs,
			},
			PayloadType: 100,
		}, webrtc.RTPCodecTypeVideo)
		// RTX for VP8 retransmission
		me.RegisterCodec(webrtc.RTPCodecParameters{
			RTPCodecCapability: webrtc.RTPCodecCapability{
				MimeType: "video/rtx", ClockRate: 90000,
				SDPFmtpLine: "apt=100",
			},
			PayloadType: 101,
		}, webrtc.RTPCodecTypeVideo)
		// Video header extensions (same IDs as audio: 2=abs-send-time, 3=transport-cc, plus 13=video-orientation)
		for _, ext := range []string{
			"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
			"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01",
			"urn:3gpp:video-orientation",
		} {
			me.RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability{URI: ext}, webrtc.RTPCodecTypeVideo)
		}
	}

	ir := &interceptor.Registry{}
	// Don't use RegisterDefaultInterceptors — it calls ConfigureSimulcastExtensionHeaders
	// which registers MID/RID/repaired-RID extensions. With those registered, pion does
	// simulcast probing for unknown SSRCs (from SFU-forwarded audio), which fails because
	// audio packets don't contain MID/RID. Without them, pion falls back to PT-based
	// matching: PT 111 → audio m-line, PT 100 → video m-line.
	webrtc.ConfigureNack(me, ir)
	webrtc.ConfigureRTCPReports(ir)
	webrtc.ConfigureStatsInterceptor(ir)
	webrtc.ConfigureTWCCSender(me, ir)
	se := webrtc.SettingEngine{}
	// Filter out IPv6 — user confirmed no IPv6 connectivity, so IPv6 ICE pairs
	// waste time and cause intermittent failures when pion tries them first.
	se.SetIPFilter(func(ip net.IP) bool { return ip.To4() != nil })
	// Allow pion to create dynamic tracks for SSRCs not declared in the SDP answer.
	// The SFU forwards other participants' audio with their original SSRCs, which aren't
	// in our synthetic answer. Without this, pion drops the packets and OnTrack never fires.
	se.SetHandleUndeclaredSSRCWithoutAnswer(true)
	groupAPI := webrtc.NewAPI(
		webrtc.WithMediaEngine(me),
		webrtc.WithInterceptorRegistry(ir),
		webrtc.WithSettingEngine(se),
	)
	pc, err := groupAPI.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("create PeerConnection: %w", err)
	}

	// Add opus audio track (RTP-based — we manually construct headers with extensions.
	// The SFU requires ssrc-audio-level extension in RTP packets for routing.)
	audioRTPTrack, err := webrtc.NewTrackLocalStaticRTP(
		webrtc.RTPCodecCapability{
			MimeType: webrtc.MimeTypeOpus, ClockRate: 48000, Channels: 2,
			SDPFmtpLine:  "minptime=10;useinbandfec=1",
			RTCPFeedback: []webrtc.RTCPFeedback{{Type: "transport-cc"}},
		},
		"audio", "uniclient-group-audio",
	)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("audio track: %w", err)
	}
	sender, _ := pc.AddTrack(audioRTPTrack)
	go func() {
		b := make([]byte, 1500)
		for {
			select {
			case <-callDone:
				return
			default:
			}
			if _, _, e := sender.Read(b); e != nil {
				return
			}
		}
	}()

	// Add video track BEFORE SDP offer so the SDP has both audio + video m-lines.
	// The SFU expects the DTLS session to have video capability when VideoStopped=false.
	// Video SSRCs are extracted from the SDP (pion-assigned) for join params.
	var videoTrackLocal *webrtc.TrackLocalStaticSample
	if video {
		videoTrackLocal, err = webrtc.NewTrackLocalStaticSample(
			webrtc.RTPCodecCapability{
				MimeType:  webrtc.MimeTypeVP8,
				ClockRate: 90000,
				RTCPFeedback: []webrtc.RTCPFeedback{
					{Type: "goog-remb"}, {Type: "transport-cc"},
					{Type: "ccm", Parameter: "fir"},
					{Type: "nack"}, {Type: "nack", Parameter: "pli"},
				},
			},
			"video", "uniclient-group-video",
		)
		if err != nil {
			pc.Close()
			return nil, fmt.Errorf("video track: %w", err)
		}
		videoSender, _ := pc.AddTrack(videoTrackLocal)
		go func() {
			for {
				select {
				case <-callDone:
					return
				default:
				}
				if _, _, err := videoSender.ReadRTCP(); err != nil {
					return
				}
			}
		}()
	}

	// Create data channel for SFU video subscription (ReceiverVideoConstraints).
	// Must be created before the SDP offer so pion includes m=application in the SDP.
	var sfuDC *webrtc.DataChannel
	if video {
		ordered := true
		sfuDC, err = pc.CreateDataChannel("data", &webrtc.DataChannelInit{
			Ordered: &ordered,
		})
		if err != nil {
			pc.Close()
			return nil, fmt.Errorf("create data channel: %w", err)
		}
	}

	// Create SDP offer (includes video m-line if video=true)
	offer, err := pc.CreateOffer(nil)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create offer: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set local desc: %w", err)
	}

	// Wait for ICE gathering to complete
	gatherDone := webrtc.GatheringCompletePromise(pc)
	<-gatherDone

	localDesc := pc.LocalDescription()
	if localDesc == nil {
		pc.Close()
		return nil, fmt.Errorf("no local description after gather")
	}
	// Extract ICE credentials, audio SSRC, and video SSRCs from SDP.
	// With video=true, the SDP has two m-lines: mid=0 (audio) and mid=1 (video).
	// SSRCs appear after each m-line. We parse by tracking which m-line section we're in.
	var ufrag, pwd, fpHash, fpValue string
	var audioSSRC, videoSSRC uint32
	var videoRTXSSRC uint32
	currentMedia := "" // "audio" or "video"
	videoSSRCSet := map[uint32]bool{}
	for _, line := range strings.Split(localDesc.SDP, "\r\n") {
		if strings.HasPrefix(line, "a=ice-ufrag:") {
			ufrag = strings.TrimPrefix(line, "a=ice-ufrag:")
		} else if strings.HasPrefix(line, "a=ice-pwd:") {
			pwd = strings.TrimPrefix(line, "a=ice-pwd:")
		} else if strings.HasPrefix(line, "a=fingerprint:") {
			parts := strings.SplitN(strings.TrimPrefix(line, "a=fingerprint:"), " ", 2)
			if len(parts) == 2 {
				fpHash = parts[0]
				fpValue = parts[1]
			}
		} else if strings.HasPrefix(line, "m=audio ") {
			currentMedia = "audio"
		} else if strings.HasPrefix(line, "m=video ") {
			currentMedia = "video"
		} else if strings.HasPrefix(line, "a=ssrc:") {
			parts := strings.SplitN(strings.TrimPrefix(line, "a=ssrc:"), " ", 2)
			if len(parts) >= 1 {
				var ssrc uint32
				fmt.Sscanf(parts[0], "%d", &ssrc)
				if currentMedia == "audio" && audioSSRC == 0 {
					audioSSRC = ssrc
				} else if currentMedia == "video" && ssrc != 0 {
					videoSSRCSet[ssrc] = true
				}
			}
		} else if strings.HasPrefix(line, "a=ssrc-group:FID ") {
			// a=ssrc-group:FID <primary> <rtx> — pion generates this for RTX
			parts := strings.Fields(strings.TrimPrefix(line, "a=ssrc-group:FID "))
			if len(parts) >= 2 {
				fmt.Sscanf(parts[0], "%d", &videoSSRC)
				fmt.Sscanf(parts[1], "%d", &videoRTXSSRC)
			}
		}
	}

	// If no FID group line, fall back to first/second video SSRC
	if video && videoSSRC == 0 && len(videoSSRCSet) > 0 {
		for ssrc := range videoSSRCSet {
			if videoSSRC == 0 {
				videoSSRC = ssrc
			} else if videoRTXSSRC == 0 {
				videoRTXSSRC = ssrc
			}
		}
	}

	if ufrag == "" || pwd == "" || fpValue == "" || audioSSRC == 0 {
		pc.Close()
		return nil, fmt.Errorf("failed to extract SDP params: ufrag=%q pwd=%q fp=%q ssrc=%d", ufrag, pwd, fpValue, audioSSRC)
	}

	// Build ssrc-groups for join params from pion-assigned video SSRCs.
	ssrcGroups := []interface{}{}
	if video && videoSSRC != 0 {
		sources := []int32{int32(videoSSRC)}
		if videoRTXSSRC != 0 {
			sources = append(sources, int32(videoRTXSSRC))
		}
		ssrcGroups = append(ssrcGroups, map[string]interface{}{
			"sources":   sources,
			"semantics": "FID",
		})
		fmt.Printf("[tg-group] Video SSRCs from SDP: primary=%d rtx=%d\n", videoSSRC, videoRTXSSRC)
	}

	// Build join params JSON (matches tgcalls GroupJoinInternalPayload::serialize)
	joinParams := map[string]interface{}{
		"ufrag": ufrag,
		"pwd":   pwd,
		"fingerprints": []map[string]string{{
			"hash":        fpHash,
			"fingerprint": fpValue,
			"setup":       "active",
		}},
		"ssrc":        int32(audioSSRC), // signed int32 like tgcalls
		"ssrc-groups": ssrcGroups,
	}
	paramsJSON, _ := json.Marshal(joinParams)
	fmt.Printf("[tg-group] Join params: %s\n", string(paramsJSON))

	// Call phone.joinGroupCall (must join muted, then unmute after connecting)
	// Retry on -503 (server timeout — transient)
	inputGroupCall := &tg.InputGroupCall{ID: gcID, AccessHash: gcAccessHash}
	var joinResp tg.UpdatesClass
	for attempt := 0; attempt < 3; attempt++ {
		joinResp, err = t.api.PhoneJoinGroupCall(t.ctx, &tg.PhoneJoinGroupCallRequest{
			Muted:        true,
			VideoStopped: !video,
			Call:         inputGroupCall,
			JoinAs:       &tg.InputPeerSelf{},
			Params:       tg.DataJSON{Data: string(paramsJSON)},
		})
		if err == nil {
			break
		}
		if strings.Contains(err.Error(), "-503") && attempt < 2 {
			fmt.Printf("[tg-group] phone.joinGroupCall -503, retrying (%d/3)...\n", attempt+2)
			time.Sleep(3 * time.Second)
			continue
		}
		pc.Close()
		return nil, fmt.Errorf("phone.joinGroupCall: %w", err)
	}

	// Extract the SFU response from updates — check for UpdateGroupCallConnection inline
	var sfuTransportFromResponse string
	initialVideoEndpoints := make(map[string]string) // endpointID → userID
	switch u := joinResp.(type) {
	case *tg.Updates:
		fmt.Printf("[tg-group] JoinGroupCall response: %d updates\n", len(u.Updates))
		for i, upd := range u.Updates {
			fmt.Printf("[tg-group]   update[%d]: %T\n", i, upd)
			if gc, ok := upd.(*tg.UpdateGroupCall); ok {
				if call, ok := gc.Call.(*tg.GroupCall); ok {
					fmt.Printf("[tg-group] Joined group call: id=%d participants=%d\n", call.ID, call.ParticipantsCount)
				}
			}
			if gcp, ok := upd.(*tg.UpdateGroupCallParticipants); ok {
				for _, p := range gcp.Participants {
					userID := ""
					if peer, ok := p.Peer.(*tg.PeerUser); ok {
						userID = strconv.FormatInt(peer.UserID, 10)
					}
					if p.Self {
						fmt.Printf("[tg-group] Self participant: ssrc=%d muted=%v canSelfUnmute=%v videoJoined=%v\n",
							p.Source, p.Muted, p.CanSelfUnmute, p.VideoJoined)
					} else {
						fmt.Printf("[tg-group] Remote participant: ssrc=%d muted=%v videoJoined=%v\n",
							p.Source, p.Muted, p.VideoJoined)
						// Extract video endpoint for SFU subscription
						if vid, ok := p.GetVideo(); ok && p.VideoJoined {
							fmt.Printf("[tg-group]   video endpoint=%s sourceGroups=%d\n",
								vid.Endpoint, len(vid.SourceGroups))
							for _, sg := range vid.SourceGroups {
								fmt.Printf("[tg-group]     ssrcGroup: semantics=%s sources=%v\n", sg.Semantics, sg.Sources)
							}
							initialVideoEndpoints[vid.Endpoint] = userID
						}
					}
				}
			}
			// Check for SFU transport in response (often sent inline)
			if gcc, ok := upd.(*tg.UpdateGroupCallConnection); ok {
				sfuTransportFromResponse = gcc.Params.Data
				fmt.Printf("[tg-group] SFU transport in response: %d bytes (presentation=%v)\n",
					len(gcc.Params.Data), gcc.Presentation)
			}
		}
	}

	// Store the group call state
	call := &tgCall{
		id:                gcID,
		accessHash:        gcAccessHash,
		isGroupCall:       true,
		isVideo:           video,
		state:             CallStateConnecting,
		pc:                pc,
		audioTrack:        audioRTPTrack,
		audioSSRC:         audioSSRC,
		done:              callDone,
		sfuTransportReady: make(chan struct{}),
		sfuDataChannel:       sfuDC,
		sfuDataChannelOpen:   make(chan struct{}),
		sfuRemoteVideoEndpts: initialVideoEndpoints,
	}

	// Wire up incoming tracks from SFU (audio and video)
	pc.OnTrack(func(track *webrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		trackSSRC := uint32(track.SSRC())
		codec := track.Codec().MimeType
		fmt.Printf("[tg-group] SFU track: kind=%s codec=%s ssrc=%d\n",
			track.Kind(), codec, trackSSRC)

		if track.Kind() == webrtc.RTPCodecTypeVideo {
			// Video track from SFU (another participant's camera/screen)
			go func() {
				for {
					select {
					case <-call.done:
						return
					default:
					}
					pkt, _, err := track.ReadRTP()
					if err != nil {
						fmt.Printf("[tg-group] video track.ReadRTP error: %v (ssrc=%d)\n", err, trackSSRC)
						return
					}
					// Use the shared VP8 reassembly pipeline (strips descriptor, reassembles, delivers)
					t.handleIncomingVideoRTP(call, pkt, false)
				}
			}()
		} else {
			// Audio track from SFU
			go func() {
				for {
					select {
					case <-call.done:
						return
					default:
					}
					pkt, _, err := track.ReadRTP()
					if err != nil {
						fmt.Printf("[tg-group] track.ReadRTP error: %v (ssrc=%d)\n", err, trackSSRC)
						return
					}
					if call.onAudioFrame != nil && len(pkt.Payload) > 0 {
						call.onAudioFrame(pkt.Payload)
					}
					call.writeRecordingFrame(pkt.Payload)
				}
			}()
		}
	})

	// Data channel for SFU video subscription (ReceiverVideoConstraints)
	if sfuDC != nil {
		sfuDC.OnOpen(func() {
			fmt.Printf("[tg-group] Data channel open — ready for video subscription\n")
			close(call.sfuDataChannelOpen)
			// Send initial constraints if we already know remote endpoints
			t.sendSFUVideoConstraints(call)
		})
		sfuDC.OnMessage(func(msg webrtc.DataChannelMessage) {
			fmt.Printf("[tg-group] SFU data channel msg: %s\n", string(msg.Data))
		})
	}

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		fmt.Printf("[tg-group] ICE state: %s\n", state)
		if state == webrtc.ICEConnectionStateFailed || state == webrtc.ICEConnectionStateClosed {
			call.state = CallStateEnded
		}
	})

	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		fmt.Printf("[tg-group] PC state: %s\n", state)
		if state == webrtc.PeerConnectionStateConnected {
			call.state = CallStateActive
			fmt.Printf("[tg-group] === SFU CONNECTED ===\n")
		}
	})

	t.mu.Lock()
	t.activeCalls[gcID] = call
	t.mu.Unlock()

	// Use transport from response if available, otherwise wait for UpdateGroupCallConnection
	if sfuTransportFromResponse != "" {
		call.sfuTransportJSON = sfuTransportFromResponse
		fmt.Printf("[tg-group] Using SFU transport from JoinGroupCall response (%d bytes)\n", len(sfuTransportFromResponse))
	} else {
		fmt.Printf("[tg-group] Waiting for SFU transport (UpdateGroupCallConnection)...\n")
		select {
		case <-call.sfuTransportReady:
			fmt.Printf("[tg-group] SFU transport received async (%d bytes)\n", len(call.sfuTransportJSON))
		case <-time.After(15 * time.Second):
			pc.Close()
			t.mu.Lock()
			delete(t.activeCalls, gcID)
			t.mu.Unlock()
			return nil, fmt.Errorf("timeout waiting for SFU transport response")
		}
	}

	// Parse SFU transport and set remote SDP
	if err := t.applySFUTransport(call); err != nil {
		pc.Close()
		t.mu.Lock()
		delete(t.activeCalls, gcID)
		t.mu.Unlock()
		return nil, fmt.Errorf("SFU transport: %w", err)
	}

	// Video track was added before SDP exchange — store references in the call object.
	if video && videoTrackLocal != nil {
		call.videoTrack = videoTrackLocal
		call.videoSSRC = videoSSRC
		fmt.Printf("[tg-group] Video track ready: ssrc=%d\n", videoSSRC)
	}

	fmt.Printf("[tg-group] Join complete: id=%d audioSSRC=%d videoSSRC=%d video=%v\n",
		gcID, audioSSRC, videoSSRC, video)
	return &CallSession{
		ID:    strconv.FormatInt(gcID, 10),
		State: CallStateConnecting,
	}, nil
}

// handleGroupCallConnection processes UpdateGroupCallConnection — the SFU's transport response.
func (t *TelegramCore) handleGroupCallConnection(paramsJSON string, isPresentation bool) {
	// Find the active group call
	t.mu.RLock()
	var groupCall *tgCall
	for _, c := range t.activeCalls {
		if c.isGroupCall && c.sfuTransportReady != nil {
			groupCall = c
			break
		}
	}
	t.mu.RUnlock()

	if groupCall == nil {
		fmt.Printf("[tg-group] No active group call waiting for transport!\n")
		return
	}

	if isPresentation {
		fmt.Printf("[tg-group] Presentation transport received (%d bytes)\n", len(paramsJSON))
		// Presentation transport is for screen share — currently shares the same PC.
		// The SFU acknowledges our presentation join; the screen track is already added.
		return
	}

	groupCall.sfuTransportJSON = paramsJSON
	select {
	case <-groupCall.sfuTransportReady:
		// Already closed
	default:
		close(groupCall.sfuTransportReady)
	}
}

// sfuTransport is the parsed SFU transport response JSON.
type sfuTransport struct {
	Transport struct {
		Ufrag        string `json:"ufrag"`
		Pwd          string `json:"pwd"`
		Fingerprints []struct {
			Hash        string `json:"hash"`
			Fingerprint string `json:"fingerprint"`
			Setup       string `json:"setup"`
		} `json:"fingerprints"`
		Candidates []struct {
			Port       string `json:"port"`
			Protocol   string `json:"protocol"`
			Network    string `json:"network"`
			Generation string `json:"generation"`
			ID         string `json:"id"`
			Component  string `json:"component"`
			Foundation string `json:"foundation"`
			Priority   string `json:"priority"`
			IP         string `json:"ip"`
			Type       string `json:"type"`
			TCPType    string `json:"tcptype,omitempty"`
			RelAddr    string `json:"rel-addr,omitempty"`
			RelPort    string `json:"rel-port,omitempty"`
		} `json:"candidates"`
	} `json:"transport"`
	Audio struct {
		PayloadTypes []sfuPayloadType `json:"payload-types"`
		RTPHdrExts   []sfuHdrExt      `json:"rtp-hdrexts"`
	} `json:"audio"`
	Video *struct {
		PayloadTypes  []sfuPayloadType `json:"payload-types"`
		RTPHdrExts    []sfuHdrExt      `json:"rtp-hdrexts"`
		ServerSources []int            `json:"server_sources"`
		Endpoint      string           `json:"endpoint"`
	} `json:"video,omitempty"`
}

type sfuPayloadType struct {
	ID         int             `json:"id"`
	Name       string          `json:"name"`
	Clockrate  int             `json:"clockrate"`
	Channels   int             `json:"channels,omitempty"`
	Parameters json.RawMessage `json:"parameters,omitempty"` // can be {} or [] from SFU
	RTCPFbs    []struct {
		Type    string `json:"type"`
		Subtype string `json:"subtype,omitempty"`
	} `json:"rtcp-fbs,omitempty"`
}

type sfuHdrExt struct {
	ID  int    `json:"id"`
	URI string `json:"uri"`
}

// applySFUTransport parses the SFU transport JSON and sets the remote SDP answer.
// The SDP answer must mirror header extensions and RTCP-fb from our offer so pion
// negotiates them and includes them in outgoing RTP. The SFU needs these extensions
// (ssrc-audio-level, transport-cc, abs-send-time) to properly route audio.
func (t *TelegramCore) applySFUTransport(call *tgCall) error {
	// Log the raw SFU response for debugging
	fmt.Printf("[tg-group] Raw SFU response JSON: %s\n", call.sfuTransportJSON)

	var transport sfuTransport
	if err := json.Unmarshal([]byte(call.sfuTransportJSON), &transport); err != nil {
		return fmt.Errorf("parse SFU transport JSON: %w", err)
	}

	tr := transport.Transport
	if tr.Ufrag == "" || tr.Pwd == "" || len(tr.Fingerprints) == 0 {
		return fmt.Errorf("incomplete SFU transport: ufrag=%q pwd=%q fps=%d", tr.Ufrag, tr.Pwd, len(tr.Fingerprints))
	}

	if transport.Video != nil {
		fmt.Printf("[tg-group] SFU video: %d payload-types, %d extensions, server_sources=%v endpoint=%s\n",
			len(transport.Video.PayloadTypes), len(transport.Video.RTPHdrExts),
			transport.Video.ServerSources, transport.Video.Endpoint)
	}

	// Extract per-m-line attributes from our offer SDP so the answer mirrors them.
	// Pion negotiates extensions/RTCP-fb based on what appears in the answer.
	localDesc := call.pc.LocalDescription()
	if localDesc == nil {
		return fmt.Errorf("no local SDP offer available")
	}

	type mlineInfo struct {
		extmaps []string
		rtcpFbs []string
		fmtps   []string
	}
	var audioInfo, videoInfo mlineInfo
	var extmapAllowMixed bool
	currentMedia := ""
	for _, line := range strings.Split(localDesc.SDP, "\r\n") {
		if strings.HasPrefix(line, "m=audio ") {
			currentMedia = "audio"
		} else if strings.HasPrefix(line, "m=video ") {
			currentMedia = "video"
		} else if line == "a=extmap-allow-mixed" {
			extmapAllowMixed = true
		} else if strings.HasPrefix(line, "a=extmap:") {
			switch currentMedia {
			case "audio":
				audioInfo.extmaps = append(audioInfo.extmaps, line)
			case "video":
				videoInfo.extmaps = append(videoInfo.extmaps, line)
			}
		} else if strings.HasPrefix(line, "a=rtcp-fb:111 ") {
			audioInfo.rtcpFbs = append(audioInfo.rtcpFbs, line)
		} else if strings.HasPrefix(line, "a=fmtp:111 ") {
			audioInfo.fmtps = append(audioInfo.fmtps, line)
		} else if strings.HasPrefix(line, "a=rtcp-fb:100 ") {
			videoInfo.rtcpFbs = append(videoInfo.rtcpFbs, line)
		} else if strings.HasPrefix(line, "a=fmtp:100 ") || strings.HasPrefix(line, "a=fmtp:101 ") {
			videoInfo.fmtps = append(videoInfo.fmtps, line)
		}
	}
	fmt.Printf("[tg-group] Offer: audio extmaps=%d rtcpfb=%d, video extmaps=%d rtcpfb=%d\n",
		len(audioInfo.extmaps), len(audioInfo.rtcpFbs), len(videoInfo.extmaps), len(videoInfo.rtcpFbs))
	fmt.Printf("[tg-group] Offer SDP:\n%s\n", localDesc.SDP)

	// Build synthetic SDP answer from SFU transport
	fp := tr.Fingerprints[0]
	setup := fp.Setup
	if setup == "" {
		setup = "passive"
	}

	bundleMids := "0"
	if call.isVideo {
		bundleMids = "0 1 2" // audio + video + data channel
	}

	var sdp strings.Builder
	sdp.WriteString("v=0\r\n")
	sdp.WriteString("o=- 0 0 IN IP4 0.0.0.0\r\n")
	sdp.WriteString("s=-\r\n")
	sdp.WriteString("t=0 0\r\n")
	sdp.WriteString(fmt.Sprintf("a=group:BUNDLE %s\r\n", bundleMids))
	sdp.WriteString("a=msid-semantic: WMS *\r\n")
	if extmapAllowMixed {
		sdp.WriteString("a=extmap-allow-mixed\r\n")
	}

	// Audio m-line
	sdp.WriteString("m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n")
	sdp.WriteString("c=IN IP4 0.0.0.0\r\n")
	sdp.WriteString("a=rtcp:9 IN IP4 0.0.0.0\r\n")
	sdp.WriteString(fmt.Sprintf("a=ice-ufrag:%s\r\n", tr.Ufrag))
	sdp.WriteString(fmt.Sprintf("a=ice-pwd:%s\r\n", tr.Pwd))
	sdp.WriteString(fmt.Sprintf("a=fingerprint:%s %s\r\n", fp.Hash, fp.Fingerprint))
	sdp.WriteString(fmt.Sprintf("a=setup:%s\r\n", setup))
	sdp.WriteString("a=mid:0\r\n")
	sdp.WriteString("a=rtcp-mux\r\n")
	sdp.WriteString("a=sendrecv\r\n")
	for _, ext := range audioInfo.extmaps {
		sdp.WriteString(ext + "\r\n")
	}
	sdp.WriteString("a=rtpmap:111 opus/48000/2\r\n")
	if len(audioInfo.fmtps) > 0 {
		sdp.WriteString(audioInfo.fmtps[0] + "\r\n")
	} else {
		sdp.WriteString("a=fmtp:111 minptime=10;useinbandfec=1\r\n")
	}
	for _, fb := range audioInfo.rtcpFbs {
		sdp.WriteString(fb + "\r\n")
	}

	// Video m-line (only when video=true).
	// Direction is sendonly in the answer: we send video TO the SFU but pion doesn't
	// need to receive on this m-line. Incoming video from other participants arrives on
	// undeclared SSRCs which HandleUndeclaredSSRCWithoutAnswer routes to the audio m-line
	// (the only recvonly/sendrecv m-line). We separate audio vs video in OnTrack by codec.
	// Using sendrecv would cause simulcast probing for incoming audio SSRCs which fails.
	if call.isVideo {
		sdp.WriteString("m=video 9 UDP/TLS/RTP/SAVPF 100 101\r\n")
		sdp.WriteString("c=IN IP4 0.0.0.0\r\n")
		sdp.WriteString("a=rtcp:9 IN IP4 0.0.0.0\r\n")
		sdp.WriteString(fmt.Sprintf("a=ice-ufrag:%s\r\n", tr.Ufrag))
		sdp.WriteString(fmt.Sprintf("a=ice-pwd:%s\r\n", tr.Pwd))
		sdp.WriteString(fmt.Sprintf("a=fingerprint:%s %s\r\n", fp.Hash, fp.Fingerprint))
		sdp.WriteString(fmt.Sprintf("a=setup:%s\r\n", setup))
		sdp.WriteString("a=mid:1\r\n")
		sdp.WriteString("a=rtcp-mux\r\n")
		sdp.WriteString("a=sendrecv\r\n")
		for _, ext := range videoInfo.extmaps {
			sdp.WriteString(ext + "\r\n")
		}
		sdp.WriteString("a=rtpmap:100 VP8/90000\r\n")
		for _, fb := range videoInfo.rtcpFbs {
			sdp.WriteString(fb + "\r\n")
		}
		sdp.WriteString("a=rtpmap:101 rtx/90000\r\n")
		sdp.WriteString("a=fmtp:101 apt=100\r\n")

		// Data channel m-line (SCTP over DTLS for ReceiverVideoConstraints)
		sdp.WriteString("m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n")
		sdp.WriteString("c=IN IP4 0.0.0.0\r\n")
		sdp.WriteString(fmt.Sprintf("a=ice-ufrag:%s\r\n", tr.Ufrag))
		sdp.WriteString(fmt.Sprintf("a=ice-pwd:%s\r\n", tr.Pwd))
		sdp.WriteString(fmt.Sprintf("a=fingerprint:%s %s\r\n", fp.Hash, fp.Fingerprint))
		sdp.WriteString(fmt.Sprintf("a=setup:%s\r\n", setup))
		sdp.WriteString("a=mid:2\r\n")
		sdp.WriteString("a=sctp-port:5000\r\n")
	}

	answerSDP := sdp.String()
	fmt.Printf("[tg-group] Synthetic SDP answer (%d bytes):\n%s\n", len(answerSDP), answerSDP)

	// Set remote description
	if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeAnswer,
		SDP:  answerSDP,
	}); err != nil {
		return fmt.Errorf("SetRemoteDescription: %w", err)
	}
	fmt.Printf("[tg-group] Remote SDP answer set OK\n")

	// Add ICE candidates from SFU (skip IPv6 — no connectivity)
	for _, c := range tr.Candidates {
		if net.ParseIP(c.IP) != nil && net.ParseIP(c.IP).To4() == nil {
			fmt.Printf("[tg-group] Skipping IPv6 candidate: %s\n", c.IP)
			continue
		}
		candidateStr := fmt.Sprintf("candidate:%s %s %s %s %s %s typ %s",
			c.Foundation, c.Component, c.Protocol, c.Priority, c.IP, c.Port, c.Type)
		if c.RelAddr != "" {
			candidateStr += fmt.Sprintf(" raddr %s rport %s", c.RelAddr, c.RelPort)
		}
		candidateStr += " generation " + c.Generation
		fmt.Printf("[tg-group] Adding ICE candidate: %s\n", candidateStr)
		if err := call.pc.AddICECandidate(webrtc.ICECandidateInit{
			Candidate: candidateStr,
		}); err != nil {
			fmt.Printf("[tg-group] Warning: AddICECandidate error: %v\n", err)
		}
	}

	return nil
}

// sendSFUVideoConstraints sends ReceiverVideoConstraints over the data channel
// to tell the SFU which participants' video streams to forward to us.
// This matches tgcalls C++ GroupInstanceCustomImpl::maybeUpdateRemoteVideoConstraints.
func (t *TelegramCore) sendSFUVideoConstraints(call *tgCall) {
	if call.sfuDataChannel == nil {
		return
	}

	// Wait for data channel to be open (non-blocking check)
	select {
	case <-call.sfuDataChannelOpen:
	default:
		fmt.Printf("[tg-group] Data channel not open yet, deferring video constraints\n")
		return
	}

	call.sfuRemoteVideoMu.Lock()
	endpoints := make(map[string]string, len(call.sfuRemoteVideoEndpts))
	for k, v := range call.sfuRemoteVideoEndpts {
		endpoints[k] = v
	}
	call.sfuRemoteVideoMu.Unlock()

	if len(endpoints) == 0 {
		fmt.Printf("[tg-group] No remote video endpoints to subscribe to\n")
		return
	}

	// Build ReceiverVideoConstraints JSON (matches Obit/Colibri protocol)
	onStage := make([]interface{}, 0, len(endpoints))
	constraints := make(map[string]interface{}, len(endpoints))
	for endpointID := range endpoints {
		onStage = append(onStage, endpointID)
		constraints[endpointID] = map[string]interface{}{
			"minHeight": 180,
			"maxHeight": 720,
		}
	}

	msg := map[string]interface{}{
		"colibriClass":       "ReceiverVideoConstraints",
		"defaultConstraints": map[string]interface{}{"maxHeight": 0},
		"onStageEndpoints":   onStage,
		"constraints":        constraints,
	}

	data, err := json.Marshal(msg)
	if err != nil {
		fmt.Printf("[tg-group] Failed to marshal video constraints: %v\n", err)
		return
	}

	fmt.Printf("[tg-group] Sending ReceiverVideoConstraints: %s\n", string(data))
	if err := call.sfuDataChannel.SendText(string(data)); err != nil {
		fmt.Printf("[tg-group] Failed to send video constraints: %v\n", err)
	}
}

// EndCall terminates an active call and cleans up resources.
func (t *TelegramCore) EndCall(callID string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.Lock()
	call := t.activeCalls[cid]
	if call != nil {
		call.state = CallStateEnded
		// Signal all call goroutines to stop
		if call.done != nil {
			select {
			case <-call.done:
			default:
				close(call.done)
			}
		}
		if call.cancel != nil {
			call.cancel()
		}
		// Close SCTP resources
		if call.sctpStream != nil {
			call.sctpStream.Close()
		}
		if call.sctpAssoc != nil {
			call.sctpAssoc.Abort("call ended")
		}
		if call.sctpConn != nil {
			call.sctpConn.Close()
		}
		if call.pc != nil {
			call.pc.Close()
		}
		call.closeVideoCodecs()
		// Close InstanceImpl resources
		if call.iceConn != nil {
			call.iceConn.Close()
			call.iceConn = nil
		}
		if call.iceAgent != nil {
			call.iceAgent.Close()
			call.iceAgent = nil
		}
		delete(t.activeCalls, cid)
		delete(t.pendingDH, cid)
	}
	t.mu.Unlock()

	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}

	_, err = t.api.PhoneDiscardCall(t.ctx, &tg.PhoneDiscardCallRequest{
		Peer: tg.InputPhoneCall{
			ID:         cid,
			AccessHash: call.accessHash,
		},
		Duration:    0,
		Reason:      &tg.PhoneCallDiscardReasonHangup{},
		ConnectionID: 0,
	})
	return err
}

// DeclineCall rejects an incoming 1:1 call with "busy" reason.
// The caller sees the call as declined/busy.
func (t *TelegramCore) DeclineCall(callID string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.Lock()
	call := t.activeCalls[cid]
	if call != nil {
		call.state = CallStateEnded
	}
	t.mu.Unlock()

	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}

	_, err = t.api.PhoneDiscardCall(t.ctx, &tg.PhoneDiscardCallRequest{
		Peer: tg.InputPhoneCall{
			ID:         cid,
			AccessHash: call.accessHash,
		},
		Duration:     0,
		Reason:       &tg.PhoneCallDiscardReasonBusy{},
		ConnectionID: 0,
	})
	if err != nil {
		return fmt.Errorf("phone.discardCall (decline): %w", err)
	}

	// Clean up
	if call.done != nil {
		select {
		case <-call.done:
		default:
			close(call.done)
		}
	}
	if call.pc != nil {
		call.pc.Close()
	}
	if call.cancel != nil {
		call.cancel()
	}
	t.mu.Lock()
	delete(t.activeCalls, cid)
	t.mu.Unlock()

	fmt.Printf("[tg-call] Declined call %d\n", cid)
	return nil
}

// SetCallVideo toggles video on/off mid-call. When enabled, MediaState videoState="active"
// is signaled and SendVideoFrame writes to the video track. When disabled, videoState="inactive".
// The video transceiver stays in place — only the signaled state and frame sending change.
func (t *TelegramCore) SetCallVideo(callID string, enabled bool) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.Lock()
	call := t.activeCalls[cid]
	if call != nil {
		call.isVideo = enabled
	}
	t.mu.Unlock()

	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}

	videoState := "inactive"
	if enabled {
		videoState = "active"
	}

	ms := tgMediaState{
		Type:            "MediaState",
		Muted:           call.muted,
		VideoState:      videoState,
		ScreencastState: "inactive",
	}
	if call.screenActive {
		ms.ScreencastState = "active"
	}
	t.sendCallSignaling(call, ms)
	fmt.Printf("[tg-call] SetCallVideo: video=%v → MediaState videoState=%s\n", enabled, videoState)
	return nil
}

// SetCallMuted mutes or unmutes the microphone in an active call.
func (t *TelegramCore) SetCallMuted(callID string, muted bool) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.Lock()
	call := t.activeCalls[cid]
	if call != nil {
		call.muted = muted
	}
	t.mu.Unlock()

	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}

	// Send updated MediaState via signaling
	ms := tgMediaState{
		Type:            "MediaState",
		Muted:           muted,
		VideoState:      "inactive",
		ScreencastState: "inactive",
	}
	if call.isVideo {
		ms.VideoState = "active"
	}
	if call.screenActive {
		ms.ScreencastState = "active"
	}
	t.sendCallSignaling(call, ms)
	return nil
}

// AcceptCall accepts an incoming call and establishes the WebRTC connection.
func (t *TelegramCore) AcceptCall(callID string) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return nil, fmt.Errorf("no incoming call %s", callID)
	}
	if call.isOutgoing {
		return nil, fmt.Errorf("call %s is outgoing, not incoming", callID)
	}

	// Get DH config
	p, g, err := t.getDHConfig()
	if err != nil {
		return nil, fmt.Errorf("DH config: %w", err)
	}

	// Generate random b (256 bytes)
	b := make([]byte, 256)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return nil, fmt.Errorf("random: %w", err)
	}

	// Compute g_b = g^b mod p (256 bytes, zero-padded)
	gBig := new(big.Int).SetInt64(int64(g))
	bBig := new(big.Int).SetBytes(b)
	pBig := new(big.Int).SetBytes(p)
	gB := new(big.Int).Exp(gBig, bBig, pBig)
	gBBytes := make([]byte, 256)
	gBBuf := gB.Bytes()
	copy(gBBytes[256-len(gBBuf):], gBBuf)

	// Store DH state — 'a' field holds our private 'b' for incoming calls
	t.mu.Lock()
	if t.pendingDH == nil {
		t.pendingDH = make(map[int64]*pendingDHState)
	}
	t.pendingDH[cid] = &pendingDHState{a: b, gA: gBBytes, p: p, g: g}
	t.mu.Unlock()

	// phone.acceptCall — sends our g_b to the caller
	versions := filterVersions(
		[]string{"13.0.0", "8.0.0", "4.0.0"},
		t.maxCallVersion, t.minCallVersion,
	)
	_, err = t.api.PhoneAcceptCall(t.ctx, &tg.PhoneAcceptCallRequest{
		Peer: tg.InputPhoneCall{ID: cid, AccessHash: call.accessHash},
		GB:   gBBytes,
		Protocol: tg.PhoneCallProtocol{
			Flags:           0b11, // udp_p2p | udp_reflector
			MinLayer:        65,
			MaxLayer:        92,
			LibraryVersions: versions,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("phone.acceptCall: %w", err)
	}
	fmt.Printf("[tg-call] acceptCall OK — waiting for PhoneCall update with g_a\n")

	// The PhoneCall update handler (handleIncomingCallConfirmed) will complete
	// the DH exchange when the caller sends confirmCall with g_a.
	return &CallSession{
		ID:      callID,
		ChatID:  strconv.FormatInt(call.peerID, 10),
		IsVideo: call.isVideo,
		State:   CallStateConnecting,
	}, nil
}

// CreateGroupCall creates a new group call in a chat.
func (t *TelegramCore) CreateGroupCall(chatID string, title string) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, fmt.Errorf("resolve peer: %w", err)
	}

	req := &tg.PhoneCreateGroupCallRequest{
		Peer:     t.peerToInputPeer(peer),
		RandomID: int(time.Now().UnixNano() & 0x7FFFFFFF),
	}
	if title != "" {
		req.SetTitle(title)
	}

	updates, err := t.api.PhoneCreateGroupCall(t.ctx, req)
	if err != nil {
		return nil, fmt.Errorf("phone.createGroupCall: %w", err)
	}

	// Extract the GroupCall from the updates
	var gcID int64
	var gcAccessHash int64
	var gcTitle string
	switch u := updates.(type) {
	case *tg.Updates:
		for _, upd := range u.Updates {
			if gc, ok := upd.(*tg.UpdateGroupCall); ok {
				if call, ok := gc.Call.(*tg.GroupCall); ok {
					gcID = call.ID
					gcAccessHash = call.AccessHash
					gcTitle, _ = call.GetTitle()
					break
				}
			}
		}
	}

	if gcID == 0 {
		return nil, fmt.Errorf("no GroupCall in response updates")
	}

	// Store the group call
	call := &tgCall{
		id:          gcID,
		accessHash:  gcAccessHash,
		isGroupCall: true,
		state:       CallStateActive,
		done:        make(chan struct{}),
	}
	t.mu.Lock()
	t.activeCalls[gcID] = call
	t.mu.Unlock()

	fmt.Printf("[tg-group] Created group call: id=%d title=%q\n", gcID, gcTitle)
	return &CallSession{
		ID:    strconv.FormatInt(gcID, 10),
		State: CallStateActive,
	}, nil
}

// LeaveGroupCall leaves an active group call.
func (t *TelegramCore) LeaveGroupCall(callID string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.Lock()
	call := t.activeCalls[cid]
	if call != nil {
		delete(t.activeCalls, cid)
	}
	t.mu.Unlock()

	if call == nil {
		return fmt.Errorf("no active group call %s", callID)
	}

	// Signal all call goroutines to stop
	if call.done != nil {
		select {
		case <-call.done:
		default:
			close(call.done)
		}
	}

	// Close PeerConnection
	if call.pc != nil {
		call.pc.Close()
	}

	// Tell server we're leaving
	_, err = t.api.PhoneLeaveGroupCall(t.ctx, &tg.PhoneLeaveGroupCallRequest{
		Call:   &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Source: int(call.audioSSRC),
	})
	if err != nil {
		fmt.Printf("[tg-group] Warning: phone.leaveGroupCall: %v\n", err)
	}

	fmt.Printf("[tg-group] Left group call: id=%d\n", cid)
	return nil
}

// StartGroupCallScreenShare joins the group call presentation with a screen share track.
// Uses phone.joinGroupCallPresentation with its own SSRC+FID group.
// The SFU sends a separate UpdateGroupCallConnection(presentation=true) with transport params.
func (t *TelegramCore) StartGroupCallScreenShare(callID string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return fmt.Errorf("no active group call %s", callID)
	}

	if call.screenTrack != nil {
		return fmt.Errorf("screen share already active")
	}

	// Create a screen share VP8 track on the existing PeerConnection
	screenTrack, err := webrtc.NewTrackLocalStaticSample(
		webrtc.RTPCodecCapability{
			MimeType:     webrtc.MimeTypeVP8,
			ClockRate:    90000,
			RTCPFeedback: []webrtc.RTCPFeedback{{Type: "nack"}, {Type: "nack", Parameter: "pli"}, {Type: "ccm", Parameter: "fir"}, {Type: "goog-remb"}, {Type: "transport-cc"}},
		},
		"screencast", "uniclient-group-screen",
	)
	if err != nil {
		return fmt.Errorf("screen track: %w", err)
	}
	screenSender, err := call.pc.AddTrack(screenTrack)
	if err != nil {
		return fmt.Errorf("add screen track: %w", err)
	}
	// Drain RTCP from screen sender
	go func() {
		for {
			select {
			case <-call.done:
				return
			default:
			}
			if _, _, err := screenSender.ReadRTCP(); err != nil {
				return
			}
		}
	}()

	// Extract screen SSRC from the new track
	// We need a new offer/answer cycle to get the SSRC, but for SFU presentation
	// we actually send separate join params. Generate a random SSRC for the presentation.
	screenSSRC := uint32(time.Now().UnixNano() & 0x7FFFFFFF) // positive int32
	rtxSSRC := screenSSRC + 1

	call.screenTrack = screenTrack
	call.screenSSRC = screenSSRC
	call.screenActive = true

	// Build presentation join params (same format as regular join, but with screen SSRCs)
	localDesc := call.pc.LocalDescription()
	if localDesc == nil {
		return fmt.Errorf("no local SDP")
	}
	var ufrag, pwd, fpHash, fpValue string
	for _, line := range strings.Split(localDesc.SDP, "\r\n") {
		if strings.HasPrefix(line, "a=ice-ufrag:") {
			ufrag = strings.TrimPrefix(line, "a=ice-ufrag:")
		} else if strings.HasPrefix(line, "a=ice-pwd:") {
			pwd = strings.TrimPrefix(line, "a=ice-pwd:")
		} else if strings.HasPrefix(line, "a=fingerprint:") {
			parts := strings.SplitN(strings.TrimPrefix(line, "a=fingerprint:"), " ", 2)
			if len(parts) == 2 {
				fpHash = parts[0]
				fpValue = parts[1]
			}
		}
	}

	presParams := map[string]interface{}{
		"ufrag": ufrag,
		"pwd":   pwd,
		"fingerprints": []map[string]string{{
			"hash":        fpHash,
			"fingerprint": fpValue,
			"setup":       "active",
		}},
		"ssrc": int32(screenSSRC),
		"ssrc-groups": []interface{}{
			map[string]interface{}{
				"sources":   []int32{int32(screenSSRC), int32(rtxSSRC)},
				"semantics": "FID",
			},
		},
	}
	presJSON, _ := json.Marshal(presParams)
	fmt.Printf("[tg-group] Presentation join params: %s\n", string(presJSON))

	_, err = t.api.PhoneJoinGroupCallPresentation(t.ctx, &tg.PhoneJoinGroupCallPresentationRequest{
		Call:   &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Params: tg.DataJSON{Data: string(presJSON)},
	})
	if err != nil {
		call.screenTrack = nil
		call.screenActive = false
		return fmt.Errorf("phone.joinGroupCallPresentation: %w", err)
	}

	fmt.Printf("[tg-group] Screen share started: ssrc=%d rtx=%d\n", screenSSRC, rtxSSRC)
	return nil
}

// StopGroupCallScreenShare leaves the group call presentation.
func (t *TelegramCore) StopGroupCallScreenShare(callID string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return fmt.Errorf("no active group call %s", callID)
	}

	call.screenActive = false
	call.screenTrack = nil

	_, err = t.api.PhoneLeaveGroupCallPresentation(t.ctx,
		&tg.InputGroupCall{ID: cid, AccessHash: call.accessHash})
	if err != nil {
		return fmt.Errorf("phone.leaveGroupCallPresentation: %w", err)
	}

	fmt.Printf("[tg-group] Screen share stopped\n")
	return nil
}

// SetGroupCallParticipantVolume adjusts the volume of a specific participant in a group call.
// volume: 0-20000 (10000 = 100%, 0 = mute, 20000 = 200%).
func (t *TelegramCore) SetGroupCallParticipantVolume(callID string, userID string, volume int) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return fmt.Errorf("no active group call %s", callID)
	}

	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid user ID: %w", err)
	}

	// Clamp volume to valid range
	if volume < 0 {
		volume = 0
	}
	if volume > 20000 {
		volume = 20000
	}

	req := &tg.PhoneEditGroupCallParticipantRequest{
		Call:        &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)},
	}
	req.SetVolume(volume)
	_, err = t.api.PhoneEditGroupCallParticipant(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.editGroupCallParticipant: %w", err)
	}
	fmt.Printf("[tg-group] Set participant %s volume to %d in group call %s\n", userID, volume, callID)
	return nil
}

// ToggleGroupCallVideo enables or disables our video in a group call.
// Uses phone.editGroupCallParticipant with SetVideoStopped.
func (t *TelegramCore) ToggleGroupCallVideo(callID string, enabled bool) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return fmt.Errorf("no active group call %s", callID)
	}

	req := &tg.PhoneEditGroupCallParticipantRequest{
		Call:        &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Participant: &tg.InputPeerSelf{},
	}
	req.SetVideoStopped(!enabled)
	_, err = t.api.PhoneEditGroupCallParticipant(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.editGroupCallParticipant: %w", err)
	}
	call.isVideo = enabled
	fmt.Printf("[tg-group] ToggleGroupCallVideo: video=%v in group call %s\n", enabled, callID)
	return nil
}

// SetGroupCallMuted mutes or unmutes ourselves in a group call.
// Uses phone.editGroupCallParticipant with SetMuted.
func (t *TelegramCore) SetGroupCallMuted(callID string, muted bool) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return fmt.Errorf("no active group call %s", callID)
	}

	req := &tg.PhoneEditGroupCallParticipantRequest{
		Call:        &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Participant: &tg.InputPeerSelf{},
	}
	req.SetMuted(muted)
	_, err = t.api.PhoneEditGroupCallParticipant(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.editGroupCallParticipant: %w", err)
	}
	call.muted = muted
	fmt.Printf("[tg-group] SetGroupCallMuted: muted=%v in group call %s\n", muted, callID)
	return nil
}

// SendCallRating sends call quality feedback after a call ends.
// rating: 1-5 stars, comment: optional text feedback.
func (t *TelegramCore) SendCallRating(callID string, rating int, comment string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	// Clamp rating to valid range
	if rating < 1 {
		rating = 1
	}
	if rating > 5 {
		rating = 5
	}

	// We need the access hash — check if the call is still in activeCalls (might have been cleaned up)
	// The MTProto API requires InputPhoneCall with ID + AccessHash
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()

	var accessHash int64
	if call != nil {
		accessHash = call.accessHash
	}

	_, err = t.api.PhoneSetCallRating(t.ctx, &tg.PhoneSetCallRatingRequest{
		Peer:    tg.InputPhoneCall{ID: cid, AccessHash: accessHash},
		Rating:  int(rating),
		Comment: comment,
	})
	if err != nil {
		return fmt.Errorf("phone.setCallRating: %w", err)
	}
	fmt.Printf("[tg-call] Sent call rating: callID=%d rating=%d comment=%q\n", cid, rating, comment)
	return nil
}

// GetGroupCall returns information about an active group call.
func (t *TelegramCore) GetGroupCall(chatID string) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, fmt.Errorf("resolve peer: %w", err)
	}

	gcID, gcAccessHash, err := t.resolveGroupCall(peer)
	if err != nil {
		return nil, err
	}

	// Get full group call info
	gcResult, err := t.api.PhoneGetGroupCall(t.ctx, &tg.PhoneGetGroupCallRequest{
		Call:  &tg.InputGroupCall{ID: gcID, AccessHash: gcAccessHash},
		Limit: 50,
	})
	if err != nil {
		return nil, fmt.Errorf("phone.getGroupCall: %w", err)
	}

	cs := &CallSession{
		ID:    strconv.FormatInt(gcID, 10),
		State: CallStateActive,
	}

	if gc, ok := gcResult.Call.(*tg.GroupCall); ok {
		fmt.Printf("[tg-group] Group call: id=%d participants=%d title=%q\n",
			gc.ID, gc.ParticipantsCount, gc.Title)
	} else if _, ok := gcResult.Call.(*tg.GroupCallDiscarded); ok {
		cs.State = CallStateEnded
	}

	return cs, nil
}

// CreateScheduledGroupCall creates a group call scheduled for a future time.
// scheduleDate is a Unix timestamp for when the call should start.
func (t *TelegramCore) CreateScheduledGroupCall(chatID string, title string, scheduleDate int) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, fmt.Errorf("resolve peer: %w", err)
	}

	req := &tg.PhoneCreateGroupCallRequest{
		Peer:     t.peerToInputPeer(peer),
		RandomID: int(time.Now().UnixNano() & 0x7FFFFFFF),
	}
	if title != "" {
		req.SetTitle(title)
	}
	req.SetScheduleDate(scheduleDate)

	resp, err := t.api.PhoneCreateGroupCall(t.ctx, req)
	if err != nil {
		return nil, fmt.Errorf("phone.createGroupCall (scheduled): %w", err)
	}

	// Extract group call ID from response
	var gcID int64
	switch u := resp.(type) {
	case *tg.Updates:
		for _, upd := range u.Updates {
			if gc, ok := upd.(*tg.UpdateGroupCall); ok {
				if call, ok := gc.Call.(*tg.GroupCall); ok {
					gcID = call.ID
					t.mu.Lock()
					t.activeCalls[gcID] = &tgCall{
						id:          gcID,
						accessHash:  call.AccessHash,
						isGroupCall: true,
						state:       CallStateConnecting,
						done:        make(chan struct{}),
					}
					t.mu.Unlock()
					fmt.Printf("[tg-group] Scheduled group call created: id=%d scheduleDate=%d title=%q\n",
						gcID, scheduleDate, title)
				}
			}
		}
	}

	return &CallSession{
		ID:    strconv.FormatInt(gcID, 10),
		State: CallStateConnecting,
	}, nil
}

// StartScheduledGroupCall starts a previously scheduled group call.
func (t *TelegramCore) StartScheduledGroupCall(callID string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return fmt.Errorf("no active group call %s", callID)
	}

	_, err = t.api.PhoneStartScheduledGroupCall(t.ctx,
		&tg.InputGroupCall{ID: cid, AccessHash: call.accessHash})
	if err != nil {
		return fmt.Errorf("phone.startScheduledGroupCall: %w", err)
	}

	fmt.Printf("[tg-group] Started scheduled group call %d\n", cid)
	return nil
}

// GetGroupCallStreamRtmpURL returns the RTMP URL and stream key for a group call livestream.
// revoke=true generates a new stream key, false returns the existing one.
func (t *TelegramCore) GetGroupCallStreamRtmpURL(chatID string, revoke bool) (string, string, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return "", "", ErrAuth
	}
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", "", fmt.Errorf("resolve peer: %w", err)
	}

	result, err := t.api.PhoneGetGroupCallStreamRtmpURL(t.ctx, &tg.PhoneGetGroupCallStreamRtmpURLRequest{
		Peer:   t.peerToInputPeer(peer),
		Revoke: revoke,
	})
	if err != nil {
		return "", "", fmt.Errorf("phone.getGroupCallStreamRtmpUrl: %w", err)
	}

	fmt.Printf("[tg-group] RTMP URL: %s key=%s\n", result.URL, result.Key[:8]+"...")
	return result.URL, result.Key, nil
}

// GetGroupCallStreamChannels returns available stream channels for a group call.
// Returns a list of channel entries (scale, lastTimestamp).
func (t *TelegramCore) GetGroupCallStreamChannels(callID string) ([]map[string]int64, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return nil, fmt.Errorf("no active group call %s", callID)
	}

	result, err := t.api.PhoneGetGroupCallStreamChannels(t.ctx,
		&tg.InputGroupCall{ID: cid, AccessHash: call.accessHash})
	if err != nil {
		return nil, fmt.Errorf("phone.getGroupCallStreamChannels: %w", err)
	}

	var channels []map[string]int64
	for _, ch := range result.Channels {
		channels = append(channels, map[string]int64{
			"channel":        int64(ch.Channel),
			"scale":          int64(ch.Scale),
			"last_timestamp": ch.LastTimestampMs,
		})
	}
	fmt.Printf("[tg-group] Stream channels: %d entries\n", len(channels))
	return channels, nil
}

// SendAudioFrame sends a raw audio frame to an active call.
func (t *TelegramCore) SendAudioFrame(callID string, opusData []byte) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if call.audioTrack == nil {
		return fmt.Errorf("audio track not ready")
	}
	tsIncrement := call.audioTSIncrement
	if tsIncrement == 0 {
		tsIncrement = 960 // default 20ms at 48kHz
	}
	seq := uint16(atomic.AddUint32(&call.audioSeq, 1))
	ts := atomic.AddUint32(&call.audioTS, tsIncrement)
	pkt := &pionrtp.Packet{
		Header: pionrtp.Header{
			Version:        2,
			PayloadType:    111,
			SequenceNumber: seq,
			Timestamp:      ts,
			SSRC:           call.audioSSRC,
		},
		Payload: opusData,
	}
	// Group calls: add ssrc-audio-level extension (RFC 6464, ext ID 1).
	// The SFU requires this to route audio. Format: V(1 bit) + level(7 bits).
	if call.isGroupCall {
		pkt.Header.Extension = true
		pkt.Header.ExtensionProfile = 0xBEDE // RFC 5285 one-byte header
		pkt.Header.SetExtension(1, []byte{0x9E}) // V=1 (voice), level=30 (-30 dBov)
	}
	return call.audioTrack.WriteRTP(pkt)
}

// SendVideoFrame sends a VP8 frame on the video track.
// vp8Frame is the raw VP8 bitstream (no RTP payload descriptor — pion adds it).
func (t *TelegramCore) SendVideoFrame(callID string, vp8Frame []byte) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if call.videoTrack == nil {
		return fmt.Errorf("no video track (call not started as video)")
	}
	return call.videoTrack.WriteSample(pionmedia.Sample{
		Data:     vp8Frame,
		Duration: 33 * time.Millisecond, // 30fps
	})
}

// SendVideoFrameYUV encodes a YUV420P frame to VP8 and sends it.
// Requires SetVideoEncoderFactory to have been called first.
// yuv420p must be width*height*3/2 bytes.
func (t *TelegramCore) SendVideoFrameYUV(callID string, yuv420p []byte, width, height int) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if call.videoTrack == nil {
		return fmt.Errorf("no video track (call not started as video)")
	}
	// Lazy-init encoder (use built-in pure Go VP8 if no factory set)
	if call.videoEncoder == nil {
		factory := t.newVideoEncoder
		if factory == nil {
			return fmt.Errorf("no video encoder factory set; call SetVideoEncoderFactory first")
		}
		enc, err := factory(width, height, 500000) // 500kbps default
		if err != nil {
			return fmt.Errorf("create video encoder: %w", err)
		}
		call.videoEncoder = enc
	}
	vp8Frame, err := call.videoEncoder.Encode(yuv420p, width, height)
	if err != nil {
		return fmt.Errorf("VP8 encode: %w", err)
	}
	if vp8Frame == nil {
		return nil // encoder lag
	}
	return call.videoTrack.WriteSample(pionmedia.Sample{
		Data:     vp8Frame,
		Duration: 33 * time.Millisecond,
	})
}

// SetVideoEncoderFactory sets the factory for creating VP8 encoders.
// Must be called before starting video calls that use SendVideoFrameYUV.
func (t *TelegramCore) SetVideoEncoderFactory(f func(width, height, bitrate int) (VideoEncoder, error)) {
	t.newVideoEncoder = f
}

// SetVideoDecoderFactory sets the factory for creating VP8 decoders.
// When set, incoming VP8 frames are decoded and delivered via SetOnDecodedVideoFrame.
func (t *TelegramCore) SetVideoDecoderFactory(f func() (VideoDecoder, error)) {
	t.newVideoDecoder = f
}

// SetOnVideoFrame registers a callback for incoming VP8 frames (reassembled from RTP).
func (t *TelegramCore) SetOnVideoFrame(callID string, handler func(frame []byte)) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.onVideoFrame = handler
	return nil
}

// SetOnDecodedVideoFrame registers a callback for decoded YUV420P video frames.
// Requires SetVideoDecoderFactory to have been called.
func (t *TelegramCore) SetOnDecodedVideoFrame(callID string, handler func(yuv420p []byte, width, height int)) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.onDecodedVideoFrame = handler
	// Lazy-init decoder
	if call.videoDecoder == nil && t.newVideoDecoder != nil {
		dec, err := t.newVideoDecoder()
		if err != nil {
			return fmt.Errorf("create video decoder: %w", err)
		}
		call.videoDecoder = dec
	}
	return nil
}

// SetOnDecodedScreenFrame registers a callback for decoded YUV420P screen frames.
func (t *TelegramCore) SetOnDecodedScreenFrame(callID string, handler func(yuv420p []byte, width, height int)) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.onDecodedScreenFrame = handler
	return nil
}

// SetOnAudioFrame registers a callback for receiving audio frames from a call.
func (t *TelegramCore) SetOnAudioFrame(callID string, handler func(frame []byte)) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.onAudioFrame = handler
	return nil
}

// SetOnScreenFrame registers a callback for incoming screencast (screen sharing) frames.
func (t *TelegramCore) SetOnScreenFrame(callID string, handler func(frame []byte)) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.onScreenFrame = handler
	return nil
}

// SendScreenFrame sends a VP8 frame on the screencast track.
// vp8Frame is the raw VP8 bitstream (no RTP payload descriptor — pion adds it).
func (t *TelegramCore) SendScreenFrame(callID string, vp8Frame []byte) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if call.screenTrack == nil {
		return fmt.Errorf("no screen track (call StartScreenShare first)")
	}
	return call.screenTrack.WriteSample(pionmedia.Sample{
		Data:     vp8Frame,
		Duration: 33 * time.Millisecond,
	})
}

// SendScreenFrameYUV encodes a YUV420P frame to VP8 and sends it on the screencast track.
func (t *TelegramCore) SendScreenFrameYUV(callID string, yuv420p []byte, width, height int) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if call.screenTrack == nil {
		return fmt.Errorf("no screen track (call StartScreenShare first)")
	}
	if call.screenEncoder == nil {
		factory := t.newVideoEncoder
		if factory == nil {
			return fmt.Errorf("no video encoder factory set; call SetVideoEncoderFactory first")
		}
		enc, err := factory(width, height, 500000)
		if err != nil {
			return fmt.Errorf("create screen encoder: %w", err)
		}
		call.screenEncoder = enc
	}
	vp8Frame, err := call.screenEncoder.Encode(yuv420p, width, height)
	if err != nil {
		return fmt.Errorf("VP8 encode (screen): %w", err)
	}
	if vp8Frame == nil {
		return nil
	}
	return call.screenTrack.WriteSample(pionmedia.Sample{
		Data:     vp8Frame,
		Duration: 33 * time.Millisecond,
	})
}

// StartScreenShare creates a screencast track and signals screencastState=active.
func (t *TelegramCore) StartScreenShare(callID string) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if call.screenActive {
		return nil // already sharing
	}
	if call.screenTrack == nil {
		return fmt.Errorf("no screen track (Web signaling required)")
	}

	// screenSSRC should already be set from InitialSetup; fallback for non-web paths
	if call.screenSSRC == 0 {
		var buf [4]byte
		rand.Read(buf[:])
		call.screenSSRC = binary.BigEndian.Uint32(buf[:])
	}

	call.screenActive = true
	fmt.Printf("[tg-call] Screen sharing started (ssrc=%d)\n", call.screenSSRC)

	// Send updated MediaState with screencastState=active
	videoState := "inactive"
	if call.isVideo {
		videoState = "active"
	}
	t.sendCallSignaling(call, &tgMediaState{
		Type:            "MediaState",
		Muted:           call.muted,
		VideoState:      videoState,
		ScreencastState: "active",
	})
	return nil
}

// StopScreenShare stops the screencast track and signals screencastState=inactive.
func (t *TelegramCore) StopScreenShare(callID string) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	if !call.screenActive {
		return nil // not sharing
	}

	// Keep the track in the PeerConnection (avoid renegotiation), just stop sending
	call.screenActive = false
	fmt.Printf("[tg-call] Screen sharing stopped\n")

	// Send updated MediaState with screencastState=inactive
	videoState := "inactive"
	if call.isVideo {
		videoState = "active"
	}
	t.sendCallSignaling(call, &tgMediaState{
		Type:            "MediaState",
		Muted:           call.muted,
		VideoState:      videoState,
		ScreencastState: "inactive",
	})
	return nil
}

// StartCallRecording begins recording incoming audio frames to a file.
// Format: binary Opus — "OPUS" (4 bytes) header, frame count updated on stop.
// Each frame: uint16_le(len) + payload.
func (t *TelegramCore) StartCallRecording(callID string, filePath string) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}

	call.recordingMu.Lock()
	defer call.recordingMu.Unlock()
	if call.recording {
		return fmt.Errorf("already recording")
	}

	f, err := os.Create(filePath)
	if err != nil {
		return fmt.Errorf("create recording file: %w", err)
	}

	// Write header: "OPUS" + uint32_le(0) — frame count filled on stop
	header := []byte{'O', 'P', 'U', 'S', 0, 0, 0, 0}
	if _, err := f.Write(header); err != nil {
		f.Close()
		return fmt.Errorf("write header: %w", err)
	}

	call.recordingFile = f
	call.recording = true
	fmt.Printf("[tg-call] Recording started: %s\n", filePath)
	return nil
}

// StopCallRecording stops recording and finalizes the file (updates frame count in header).
// Returns the number of frames recorded.
func (t *TelegramCore) StopCallRecording(callID string) (int, error) {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return 0, fmt.Errorf("no active call %s", callID)
	}

	call.recordingMu.Lock()
	defer call.recordingMu.Unlock()
	if !call.recording {
		return 0, nil
	}

	call.recording = false
	f := call.recordingFile
	call.recordingFile = nil

	if f == nil {
		return 0, nil
	}

	// Count frames by scanning the file (from offset 8)
	pos, _ := f.Seek(0, 2) // current end
	frameBytes := pos - 8
	frameCount := 0
	if frameBytes > 0 {
		f.Seek(8, 0)
		buf := make([]byte, 2)
		for {
			if _, err := f.Read(buf); err != nil {
				break
			}
			frameLen := int(binary.LittleEndian.Uint16(buf))
			frameCount++
			f.Seek(int64(frameLen), 1)
		}
	}

	// Update frame count in header
	var countBuf [4]byte
	binary.LittleEndian.PutUint32(countBuf[:], uint32(frameCount))
	f.Seek(4, 0)
	f.Write(countBuf[:])

	f.Close()
	fmt.Printf("[tg-call] Recording stopped: %d frames\n", frameCount)
	return frameCount, nil
}

// readSenderRTCP reads RTCP feedback from a video/screen sender and triggers ForceKeyframe
// on PLI/FIR requests from the remote receiver. This replaces the old drain-only goroutine.
func (t *TelegramCore) readSenderRTCP(call *tgCall, sender *webrtc.RTPSender, isScreen bool) {
	label := "video"
	if isScreen {
		label = "screen"
	}
	var pliCount, firCount int64
	for {
		select {
		case <-call.done:
			return
		default:
		}
		pkts, _, err := sender.ReadRTCP()
		if err != nil {
			return
		}
		for _, pkt := range pkts {
			switch pkt.(type) {
			case *rtcp.PictureLossIndication:
				n := atomic.AddInt64(&pliCount, 1)
				if n == 1 || n%100 == 0 {
					fmt.Printf("[tg-call] RTCP PLI received for %s — forcing keyframe (count=%d)\n", label, n)
				}
				enc := call.videoEncoder
				if isScreen {
					enc = call.screenEncoder
				}
				if enc != nil {
					enc.ForceKeyframe()
				}
			case *rtcp.FullIntraRequest:
				n := atomic.AddInt64(&firCount, 1)
				if n == 1 || n%100 == 0 {
					fmt.Printf("[tg-call] RTCP FIR received for %s — forcing keyframe (count=%d)\n", label, n)
				}
				enc := call.videoEncoder
				if isScreen {
					enc = call.screenEncoder
				}
				if enc != nil {
					enc.ForceKeyframe()
				}
			}
		}
	}
}

// closeVideoCodecs releases VP8 encoder/decoder resources for a call.
func (call *tgCall) closeVideoCodecs() {
	if call.videoEncoder != nil {
		call.videoEncoder.Close()
		call.videoEncoder = nil
	}
	if call.screenEncoder != nil {
		call.screenEncoder.Close()
		call.screenEncoder = nil
	}
	if call.videoDecoder != nil {
		call.videoDecoder.Close()
		call.videoDecoder = nil
	}
}

// handleIncomingVideoRTP processes an incoming VP8 RTP packet: strips the VP8 payload
// descriptor, reassembles multi-packet frames, and delivers complete VP8 frames to callbacks.
// If a decoder is configured, also decodes to YUV420P.
func (t *TelegramCore) handleIncomingVideoRTP(call *tgCall, pkt *pionrtp.Packet, isScreen bool) {
	if len(pkt.Payload) == 0 {
		return
	}

	// Strip VP8 RTP payload descriptor (RFC 7741)
	vp8Data, isStart := stripVP8RTPDescriptor(pkt.Payload)
	if vp8Data == nil {
		return
	}

	// Get the appropriate frame buffer and callbacks
	var frameBuf *[]byte
	var onRawFrame func([]byte)
	var onDecodedFrame func([]byte, int, int)
	if isScreen {
		frameBuf = &call.screenFrameBuf
		onRawFrame = call.onScreenFrame
		onDecodedFrame = call.onDecodedScreenFrame
	} else {
		frameBuf = &call.videoFrameBuf
		onRawFrame = call.onVideoFrame
		onDecodedFrame = call.onDecodedVideoFrame
	}

	// Start of new VP8 partition — reset buffer
	if isStart {
		*frameBuf = (*frameBuf)[:0]
	}
	*frameBuf = append(*frameBuf, vp8Data...)

	// RTP marker bit = end of frame
	if pkt.Header.Marker {
		completeFrame := append([]byte(nil), *frameBuf...)
		*frameBuf = (*frameBuf)[:0]

		// Deliver raw VP8 frame
		if onRawFrame != nil {
			onRawFrame(completeFrame)
		}

		// Decode to YUV420P if decoder available
		if onDecodedFrame != nil && call.videoDecoder != nil {
			yuv, w, h, err := call.videoDecoder.Decode(completeFrame)
			if err == nil && yuv != nil {
				onDecodedFrame(yuv, w, h)
			}
		}
	}
}

// stripVP8RTPDescriptor removes the VP8 RTP payload descriptor per RFC 7741.
// Returns the raw VP8 frame data and whether this is the start of a VP8 partition.
func stripVP8RTPDescriptor(payload []byte) (data []byte, isStart bool) {
	if len(payload) < 1 {
		return nil, false
	}
	i := 0
	hasExtension := payload[0]&0x80 != 0
	isStart = payload[0]&0x10 != 0
	i++
	if hasExtension {
		if i >= len(payload) {
			return nil, false
		}
		hasPictureID := payload[i]&0x80 != 0
		hasTL0PICIDX := payload[i]&0x40 != 0
		hasTIDorKEYIDX := payload[i]&0x20 != 0 || payload[i]&0x10 != 0
		i++
		if hasPictureID && i < len(payload) {
			if payload[i]&0x80 != 0 {
				i++ // 15-bit PictureID MSB
			}
			i++ // PictureID LSB
		}
		if hasTL0PICIDX {
			i++
		}
		if hasTIDorKEYIDX {
			i++
		}
	}
	if i >= len(payload) {
		return nil, false
	}
	return payload[i:], isStart
}

// writeRecordingFrame writes an audio frame to the recording file if recording is active.
func (call *tgCall) writeRecordingFrame(payload []byte) {
	call.recordingMu.Lock()
	defer call.recordingMu.Unlock()
	if !call.recording || call.recordingFile == nil || len(payload) == 0 {
		return
	}
	var lenBuf [2]byte
	binary.LittleEndian.PutUint16(lenBuf[:], uint16(len(payload)))
	call.recordingFile.Write(lenBuf[:])
	call.recordingFile.Write(payload)
}

// SetEchoMode enables or disables echo mode for a call.
// When enabled, all received audio is immediately sent back to the caller.
func (t *TelegramCore) SetEchoMode(callID string, enabled bool) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.echoMode = enabled
	call.externalAudio = enabled // disable silence sender — echo handler sends audio directly
	fmt.Printf("[tg-call] Echo mode %s for call %s\n", map[bool]string{true: "ENABLED", false: "disabled"}[enabled], callID)
	return nil
}

// SetAudioFrameDuration sets the opus frame duration for outgoing audio.
// durationMs is the frame length in milliseconds (20, 60, 120).
func (t *TelegramCore) SetAudioFrameDuration(callID string, durationMs int) error {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return fmt.Errorf("no active call %s", callID)
	}
	call.audioTSIncrement = uint32(48000 * durationMs / 1000) // samples at 48kHz
	call.externalAudio = true // stop internal silence sender
	fmt.Printf("[tg-call] Audio frame duration set to %dms (%d samples) for call %s, silence sender stopped\n",
		durationMs, call.audioTSIncrement, callID)
	return nil
}

// GetProfile returns the profile information for a user, chat, or channel.
func (t *TelegramCore) GetProfile(userID string) (*User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	var inputUser tg.InputUserClass
	if userID == "" || userID == "me" || userID == "self" {
		inputUser = &tg.InputUserSelf{}
	} else {
		id, err := tgUserID(userID)
		if err != nil {
			return nil, err
		}
		hash := t.getCachedUserHash(id)
		inputUser = &tg.InputUser{UserID: id, AccessHash: hash}
	}
	users, err := t.api.UsersGetUsers(t.ctx, []tg.InputUserClass{inputUser})
	if err != nil {
		return nil, fmt.Errorf("get profile: %w", err)
	}

	if len(users) == 0 {
		return nil, ErrNotFound
	}

	user, ok := users[0].(*tg.User)
	if !ok {
		return nil, ErrNotFound
	}

	// Cache the access hash from the response
	t.cacheUserHash(user.ID, user.AccessHash)

	return t.convertUser(user), nil
}

// CreateGroup creates a new basic group chat with the specified users.
func (t *TelegramCore) CreateGroup(name string, members []string) (*Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	var users []tg.InputUserClass
	for _, m := range members {
		id, err := tgUserID(m)
		if err != nil {
			return nil, err
		}
		users = append(users, &tg.InputUser{UserID: id})
	}

	result, err := t.api.MessagesCreateChat(t.ctx, &tg.MessagesCreateChatRequest{
		Title: name,
		Users: users,
	})
	if err != nil {
		return nil, fmt.Errorf("create group: %w", err)
	}

	// Extract chat info from the result
	if result != nil && result.Updates != nil {
		return t.extractDialogFromUpdates(result.Updates), nil
	}
	return &Dialog{Title: name, Type: ChatTypeGroup, Platform: tgPlatform}, nil
}

// CreateChannel creates a new channel or supergroup.
func (t *TelegramCore) CreateChannel(name string, description string) (*Dialog, error) {
	return t.RawCreateChannel(name, description, true, false)
}

// RawCreateChannel creates a channel or megagroup (supergroup).
func (t *TelegramCore) RawCreateChannel(name, description string, broadcast, megagroup bool) (*Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	result, err := t.api.ChannelsCreateChannel(t.ctx, &tg.ChannelsCreateChannelRequest{
		Title:     name,
		About:     description,
		Broadcast: broadcast,
		Megagroup: megagroup,
	})
	if err != nil {
		return nil, fmt.Errorf("create channel: %w", err)
	}

	return t.extractDialogFromUpdates(result), nil
}

// CreateTopic creates a new forum topic in a supergroup.
func (t *TelegramCore) CreateTopic(chatID string, name string) (*Dialog, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	_, err = t.api.MessagesCreateForumTopic(t.ctx, &tg.MessagesCreateForumTopicRequest{
		Peer:     inputPeer,
		Title:    name,
		RandomID: time.Now().UnixNano(),
	})
	if err != nil {
		return nil, fmt.Errorf("create topic: %w", err)
	}

	return &Dialog{
		Title:    name,
		Type:     ChatTypeTopic,
		ParentID: chatID,
		Platform: tgPlatform,
	}, nil
}

// GetFolders returns all chat folders configured by the user.
func (t *TelegramCore) GetFolders() ([]Folder, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	result, err := t.api.MessagesGetDialogFilters(t.ctx)
	if err != nil {
		return nil, fmt.Errorf("get folders: %w", err)
	}

	var folders []Folder
	for _, f := range result.GetFilters() {
		var folder Folder

		switch filter := f.(type) {
		case *tg.DialogFilter:
			folder = Folder{
				ID:              strconv.Itoa(filter.ID),
				Name:            filter.Title.Text,
				Contacts:        filter.Contacts,
				NonContacts:     filter.NonContacts,
				Groups:          filter.Groups,
				Channels:        filter.Broadcasts,
				Bots:            filter.Bots,
				ExcludeMuted:    filter.ExcludeMuted,
				ExcludeRead:     filter.ExcludeRead,
				ExcludeArchived: filter.ExcludeArchived,
			}
			for _, p := range filter.IncludePeers {
				folder.ChatIDs = append(folder.ChatIDs, inputPeerToID(p))
			}
			for _, p := range filter.ExcludePeers {
				folder.ExcludeChatIDs = append(folder.ExcludeChatIDs, inputPeerToID(p))
			}
			for _, p := range filter.PinnedPeers {
				folder.PinnedChatIDs = append(folder.PinnedChatIDs, inputPeerToID(p))
			}

		case *tg.DialogFilterChatlist:
			// Shared/public folders — explicit include list only, no type filters.
			folder = Folder{
				ID:   strconv.Itoa(filter.ID),
				Name: filter.Title.Text,
			}
			for _, p := range filter.IncludePeers {
				folder.ChatIDs = append(folder.ChatIDs, inputPeerToID(p))
			}
			for _, p := range filter.PinnedPeers {
				folder.PinnedChatIDs = append(folder.PinnedChatIDs, inputPeerToID(p))
			}

		default:
			continue // Skip DialogFilterDefault and unknown types
		}
		log.Printf("[tg-folders] Folder %q (id=%s): contacts=%v nonContacts=%v groups=%v channels=%v bots=%v excludeMuted=%v excludeRead=%v excludeArchived=%v includes=%d excludes=%d pinned=%d includeIDs=%v",
			folder.Name, folder.ID, folder.Contacts, folder.NonContacts, folder.Groups, folder.Channels, folder.Bots,
			folder.ExcludeMuted, folder.ExcludeRead, folder.ExcludeArchived,
			len(folder.ChatIDs), len(folder.ExcludeChatIDs), len(folder.PinnedChatIDs), folder.ChatIDs)
		folders = append(folders, folder)
	}
	return folders, nil
}

// CreateFolder creates a new chat folder with the specified filters.
func (t *TelegramCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	var peers []tg.InputPeerClass
	for _, cid := range chatIDs {
		peer, err := t.resolvePeer(cid)
		if err != nil {
			continue
		}
		inputPeer, _ := t.toInputPeer(peer)
		peers = append(peers, inputPeer)
	}

	filterID := int(time.Now().Unix()%200) + 20 // avoid collision with existing filters (IDs 2-15 common)

	// Telegram folder titles are max 12 UTF-8 chars
	titleRunes := []rune(name)
	if len(titleRunes) > 12 {
		titleRunes = titleRunes[:12]
	}
	filter := &tg.DialogFilter{
		ID:           filterID,
		Title:        tg.TextWithEntities{Text: string(titleRunes), Entities: []tg.MessageEntityClass{}},
		IncludePeers: peers,
		PinnedPeers:  []tg.InputPeerClass{},
		ExcludePeers: []tg.InputPeerClass{},
	}
	// Set contacts flag to satisfy minimum filter requirements
	filter.SetFlags()

	_, err := t.api.MessagesUpdateDialogFilter(t.ctx, &tg.MessagesUpdateDialogFilterRequest{
		ID:     filterID,
		Filter: filter,
	})
	if err != nil {
		return nil, fmt.Errorf("create folder: %w", err)
	}

	return &Folder{
		ID:      strconv.Itoa(filterID),
		Name:    name,
		ChatIDs: chatIDs,
	}, nil
}

// OnUpdate registers a callback to receive real-time updates from Telegram.
func (t *TelegramCore) OnUpdate(handler func(Update)) {
	t.updateMu.Lock()
	defer t.updateMu.Unlock()
	t.updateHandlers = append(t.updateHandlers, handler)
}

// Close shuts down the Telegram client and releases all resources.
func (t *TelegramCore) Close() error {
	if t.cancel != nil {
		t.cancel()
	}
	t.wg.Wait()
	t.mu.Lock()
	t.authed = false
	t.mu.Unlock()
	return nil
}

// --- Internal helpers ---

func (t *TelegramCore) fireUpdate(u Update) {
	t.updateMu.RLock()
	n := len(t.updateHandlers)
	if n == 0 {
		t.updateMu.RUnlock()
		return
	}
	if n == 1 {
		h := t.updateHandlers[0]
		t.updateMu.RUnlock()
		h(u)
		return
	}
	handlers := make([]func(Update), n)
	copy(handlers, t.updateHandlers)
	t.updateMu.RUnlock()
	for _, h := range handlers {
		h(u)
	}
}

// peerToInputPeer converts PeerClass to InputPeerClass using cached access hashes.
func (t *TelegramCore) peerToInputPeer(peer tg.PeerClass) tg.InputPeerClass {
	switch p := peer.(type) {
	case *tg.PeerUser:
		hash := t.getCachedUserHash(p.UserID)
		return &tg.InputPeerUser{UserID: p.UserID, AccessHash: hash}
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		return &tg.InputPeerChannel{ChannelID: p.ChannelID, AccessHash: hash}
	case *tg.PeerChat:
		return &tg.InputPeerChat{ChatID: p.ChatID}
	}
	return &tg.InputPeerSelf{}
}

// resolveGroupCall finds the active group call in a chat, returns (id, accessHash, err).
func (t *TelegramCore) resolveGroupCall(peer tg.PeerClass) (int64, int64, error) {
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		fullChan, err := t.api.ChannelsGetFullChannel(t.ctx, &tg.InputChannel{
			ChannelID:  p.ChannelID,
			AccessHash: hash,
		})
		if err != nil {
			return 0, 0, fmt.Errorf("get full channel: %w", err)
		}
		if cf, ok := fullChan.FullChat.(*tg.ChannelFull); ok {
			if igc, ok := cf.GetCall(); ok {
				if gc, ok := igc.(*tg.InputGroupCall); ok {
					return gc.ID, gc.AccessHash, nil
				}
			}
		}
	case *tg.PeerChat:
		fullChat, err := t.api.MessagesGetFullChat(t.ctx, p.ChatID)
		if err != nil {
			return 0, 0, fmt.Errorf("get full chat: %w", err)
		}
		if cf, ok := fullChat.FullChat.(*tg.ChatFull); ok {
			if igc, ok := cf.GetCall(); ok {
				if gc, ok := igc.(*tg.InputGroupCall); ok {
					return gc.ID, gc.AccessHash, nil
				}
			}
		}
	default:
		return 0, 0, fmt.Errorf("group calls only work in groups/channels, got %T", peer)
	}
	return 0, 0, fmt.Errorf("no active group call")
}

// tgMsgID parses a message ID string to int, returning an error for invalid input.
func tgMsgID(s string) (int, error) {
	id, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("invalid message ID %q: %w", s, err)
	}
	return id, nil
}

// tgUserID parses a user/channel ID string to int64, returning an error for invalid input.
func tgUserID(s string) (int64, error) {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid ID %q: %w", s, err)
	}
	return id, nil
}

// withPeer acquires a read lock, checks auth, resolves the peer, and returns the input peer.
// Caller must NOT hold t.mu. The lock is held for the duration via the returned unlock func.
func (t *TelegramCore) withPeer(chatID string) (tg.InputPeerClass, func(), error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, nil, ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		t.mu.RUnlock()
		return nil, nil, err
	}
	inputPeer, _ := t.toInputPeer(peer)
	return inputPeer, t.mu.RUnlock, nil
}

// resolvePeer resolves a chat ID string to a tg.PeerClass.
func (t *TelegramCore) resolvePeer(chatID string) (tg.PeerClass, error) {
	// Handle @username
	if strings.HasPrefix(chatID, "@") {
		resolved, err := t.api.ContactsResolveUsername(t.ctx, &tg.ContactsResolveUsernameRequest{
			Username: strings.TrimPrefix(chatID, "@"),
		})
		if err != nil {
			return nil, fmt.Errorf("resolve username: %w", err)
		}
		if len(resolved.Users) > 0 {
			u := resolved.Users[0].(*tg.User)
			return &tg.PeerUser{UserID: u.ID}, nil
		}
		if len(resolved.Chats) > 0 {
			switch c := resolved.Chats[0].(type) {
			case *tg.Channel:
				return &tg.PeerChannel{ChannelID: c.ID}, nil
			case *tg.Chat:
				return &tg.PeerChat{ChatID: c.ID}, nil
			}
		}
		return nil, ErrNotFound
	}

	// Numeric ID
	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid chat ID: %s", chatID)
	}

	// Negative IDs are groups/channels in Telegram convention
	if id < 0 {
		// -100xxxx is a channel, -xxxx is a chat
		absID := -id
		if absID > 1000000000000 {
			return &tg.PeerChannel{ChannelID: absID - 1000000000000}, nil
		}
		return &tg.PeerChat{ChatID: absID}, nil
	}

	return &tg.PeerUser{UserID: id}, nil
}

func (t *TelegramCore) toInputPeer(peer tg.PeerClass) (tg.InputPeerClass, error) {
	switch p := peer.(type) {
	case *tg.PeerUser:
		hash := t.getCachedUserHash(p.UserID)
		return &tg.InputPeerUser{UserID: p.UserID, AccessHash: hash}, nil
	case *tg.PeerChat:
		return &tg.InputPeerChat{ChatID: p.ChatID}, nil
	case *tg.PeerChannel:
		hash, err := t.resolveChannelAccessHash(p.ChannelID)
		if err != nil {
			return &tg.InputPeerChannel{ChannelID: p.ChannelID}, nil
		}
		return &tg.InputPeerChannel{ChannelID: p.ChannelID, AccessHash: hash}, nil
	default:
		return nil, fmt.Errorf("unknown peer type: %T", peer)
	}
}

// --- Peer access hash cache ---

func (t *TelegramCore) cacheUserHash(userID, accessHash int64) {
	t.peerMu.Lock()
	t.userAccessHash[userID] = accessHash
	t.peerMu.Unlock()
}

func (t *TelegramCore) getCachedUserHash(userID int64) int64 {
	t.peerMu.RLock()
	hash, ok := t.userAccessHash[userID]
	t.peerMu.RUnlock()
	if ok {
		return hash
	}
	return 0
}

func (t *TelegramCore) getCachedUserName(userID int64) string {
	t.peerMu.RLock()
	name := t.userNames[userID]
	t.peerMu.RUnlock()
	return name
}

func (t *TelegramCore) getCachedUsername(userID int64) string {
	t.peerMu.RLock()
	uname := t.userUsernames[userID]
	t.peerMu.RUnlock()
	return uname
}

func (t *TelegramCore) getCachedUserColorID(userID int64) int {
	t.peerMu.RLock()
	cid, ok := t.userColorIDs[userID]
	t.peerMu.RUnlock()
	if ok {
		return cid
	}
	// -1 = unknown; Dart UI falls back to senderId % 7
	return -1
}

func (t *TelegramCore) cacheChannelHash(channelID, accessHash int64) {
	t.peerMu.Lock()
	t.channelAccessHash[channelID] = accessHash
	t.peerMu.Unlock()
}

func (t *TelegramCore) getCachedChannelName(channelID int64) string {
	t.peerMu.RLock()
	name := t.channelNames[channelID]
	t.peerMu.RUnlock()
	return name
}

func (t *TelegramCore) getCachedChannelHash(channelID int64) (int64, bool) {
	t.peerMu.RLock()
	hash, ok := t.channelAccessHash[channelID]
	t.peerMu.RUnlock()
	return hash, ok
}

// encodeFileExtra packs access hash and file reference for later download.
func encodeFileExtra(accessHash int64, fileRef []byte) string {
	return strconv.FormatInt(accessHash, 10) + ":" + base64.StdEncoding.EncodeToString(fileRef)
}

// decodeFileExtra unpacks access hash and file reference from Extra field.
func decodeFileExtra(extra string) (int64, []byte) {
	parts := strings.SplitN(extra, ":", 2)
	if len(parts) != 2 {
		return 0, nil
	}
	hash, _ := strconv.ParseInt(parts[0], 10, 64)
	ref, _ := base64.StdEncoding.DecodeString(parts[1])
	return hash, ref
}

func (t *TelegramCore) cacheFileInfo(fileID, accessHash int64, fileRef []byte) {
	t.peerMu.Lock()
	t.fileAccessHash[fileID] = accessHash
	if len(fileRef) > 0 {
		t.fileReference[fileID] = fileRef
	}
	t.peerMu.Unlock()
}

func (t *TelegramCore) getCachedFileHash(fileID int64) int64 {
	t.peerMu.RLock()
	defer t.peerMu.RUnlock()
	return t.fileAccessHash[fileID]
}

func (t *TelegramCore) getCachedFileRef(fileID int64) []byte {
	t.peerMu.RLock()
	defer t.peerMu.RUnlock()
	return t.fileReference[fileID]
}

// cacheEntities extracts access hashes from user/chat lists and caches them.
func (t *TelegramCore) cacheEntities(users []tg.UserClass, chats []tg.ChatClass) {
	if len(users) == 0 && len(chats) == 0 {
		return
	}
	t.peerMu.Lock()
	for _, u := range users {
		if user, ok := u.(*tg.User); ok {
			t.userAccessHash[user.ID] = user.AccessHash
			name := strings.TrimSpace(user.FirstName + " " + user.LastName)
			if name == "" {
				name = user.Username
			}
			if name != "" {
				t.userNames[user.ID] = name
			}
			if user.Username != "" {
				t.userUsernames[user.ID] = user.Username
			}
			if pc, ok := user.GetColor(); ok {
				if c, ok := pc.(*tg.PeerColor); ok {
					t.userColorIDs[user.ID] = c.Color
				}
			}
			if photo, ok := user.Photo.(*tg.UserProfilePhoto); ok {
				t.peerPhotoID[user.ID] = photo.PhotoID
			}
		}
	}
	for _, c := range chats {
		switch ch := c.(type) {
		case *tg.Channel:
			t.channelAccessHash[ch.ID] = ch.AccessHash
			t.channelNames[ch.ID] = ch.Title
			if photo, ok := ch.Photo.(*tg.ChatPhoto); ok {
				t.peerPhotoID[ch.ID] = photo.PhotoID
			}
		case *tg.Chat:
			t.channelNames[ch.ID] = ch.Title
			if photo, ok := ch.Photo.(*tg.ChatPhoto); ok {
				t.peerPhotoID[ch.ID] = photo.PhotoID
			}
		}
	}
	t.peerMu.Unlock()
}

// resolveChannelAccessHash fetches the access hash for a channel/supergroup.
func (t *TelegramCore) resolveChannelAccessHash(channelID int64) (int64, error) {
	// Check cache first
	if hash, ok := t.getCachedChannelHash(channelID); ok {
		return hash, nil
	}

	if t.api == nil {
		return 0, fmt.Errorf("api not initialized")
	}
	result, err := t.api.ChannelsGetChannels(t.ctx, []tg.InputChannelClass{
		&tg.InputChannel{ChannelID: channelID},
	})
	if err != nil {
		return 0, err
	}
	chats := result.GetChats()
	for _, chat := range chats {
		if ch, ok := chat.(*tg.Channel); ok && ch.ID == channelID {
			t.cacheChannelHash(ch.ID, ch.AccessHash)
			return ch.AccessHash, nil
		}
	}
	return 0, fmt.Errorf("channel %d not found", channelID)
}

func (t *TelegramCore) convertMessage(msg *tg.Message) *Message {
	m := &Message{
		ID:         strconv.Itoa(msg.ID),
		ChatID:     peerToID(msg.PeerID),
		Text:       msg.Message,
		Timestamp:  time.Unix(int64(msg.Date), 0),
		Status:     MessageStatusSent,
		IsPinned:   msg.Pinned,
		IsOutgoing: msg.Out,
		Views:      msg.Views,
		Forwards:   msg.Forwards,
		Platform:   tgPlatform,
	}

	if gid, ok := msg.GetGroupedID(); ok && gid != 0 {
		m.GroupedID = strconv.FormatInt(gid, 10)
	}

	if from := msg.FromID; from != nil {
		m.SenderID = peerToID(from)
		if peer, ok := from.(*tg.PeerUser); ok {
			m.SenderName = t.getCachedUserName(peer.UserID)
			m.SenderColorID = t.getCachedUserColorID(peer.UserID)
			// Look up admin rank from cache for group/supergroup chats.
			if chatID := peerToInt64(msg.PeerID); chatID != 0 {
				m.SenderRank = t.getAdminRank(chatID, peer.UserID)
			}
		}
	}

	// Channel post author signature (e.g. "John" when channel has "Sign messages" on).
	if author, ok := msg.GetPostAuthor(); ok && author != "" && m.SenderRank == "" {
		m.SenderRank = author
	}

	if msg.EditDate != 0 {
		et := time.Unix(int64(msg.EditDate), 0)
		m.EditedAt = &et
	}

	if reply, ok := msg.GetReplyTo(); ok {
		if rh, ok := reply.(*tg.MessageReplyHeader); ok {
			m.ReplyToID = strconv.Itoa(rh.ReplyToMsgID)
			if rh.ForumTopic {
				topicID := rh.ReplyToTopID
				if topicID == 0 {
					topicID = rh.ReplyToMsgID
				}
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				tidStr := strconv.Itoa(topicID)
				m.Extra["topic_id"] = tidStr
				// Look up cached topic name and color.
				chatID := peerToID(msg.PeerID)
				if title, color, ok := t.GetForumTopicInfo(chatID, tidStr); ok {
					m.Extra["topic_name"] = title
					m.Extra["topic_color"] = color
				}
			}
		}
	}

	if fwd, ok := msg.GetFwdFrom(); ok {
		// Resolve forward origin to a display name.
		// Priority: FromName (privacy-set) > cached user/channel name > PostAuthor > peer ID fallback.
		if name, ok := fwd.GetFromName(); ok && name != "" {
			m.ForwardFrom = name
		} else if from, ok := fwd.GetFromID(); ok {
			switch p := from.(type) {
			case *tg.PeerUser:
				if name := t.getCachedUserName(p.UserID); name != "" {
					m.ForwardFrom = name
				} else {
					m.ForwardFrom = "User " + strconv.FormatInt(p.UserID, 10)
				}
			case *tg.PeerChannel:
				if name := t.getCachedChannelName(p.ChannelID); name != "" {
					m.ForwardFrom = name
				} else if author, ok := fwd.GetPostAuthor(); ok && author != "" {
					m.ForwardFrom = author
				} else {
					m.ForwardFrom = "Channel " + strconv.FormatInt(p.ChannelID, 10)
				}
			case *tg.PeerChat:
				if name := t.getCachedChannelName(p.ChatID); name != "" {
					m.ForwardFrom = name
				} else {
					m.ForwardFrom = "Chat " + strconv.FormatInt(p.ChatID, 10)
				}
			}
		} else if author, ok := fwd.GetPostAuthor(); ok && author != "" {
			m.ForwardFrom = author
		}
	}

	// Via-bot label: resolve ViaBotID to @username for inline bot attribution.
	if viaBotID, ok := msg.GetViaBotID(); ok && viaBotID != 0 {
		if uname := t.getCachedUsername(viaBotID); uname != "" {
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["via_bot_name"] = "@" + uname
		} else if name := t.getCachedUserName(viaBotID); name != "" {
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["via_bot_name"] = name
		}
	}

	// Extract rich-text entities.
	if len(msg.Entities) > 0 {
		m.Entities = convertTgEntities(msg.Entities)
	}

	if media := msg.Media; media != nil {
		switch md := media.(type) {
		case *tg.MessageMediaDocument:
			if d, ok := md.Document.(*tg.Document); ok {
				ref := FileRef{
					ID:       strconv.FormatInt(d.ID, 10),
					Size:     d.Size,
					MimeType: d.MimeType,
					Extra:    encodeFileExtra(d.AccessHash, d.FileReference),
				}
				isAnimated := false
				for _, attr := range d.Attributes {
					switch a := attr.(type) {
					case *tg.DocumentAttributeFilename:
						ref.Name = a.FileName
					case *tg.DocumentAttributeAnimated:
						isAnimated = true
					case *tg.DocumentAttributeVideo:
						ref.Width = a.W
						ref.Height = a.H
						ref.Duration = int(a.Duration)
					case *tg.DocumentAttributeAudio:
						ref.Duration = int(a.Duration)
					case *tg.DocumentAttributeImageSize:
						ref.Width = a.W
						ref.Height = a.H
					}
				}
				if isAnimated && ref.MimeType == "video/mp4" {
					ref.MimeType = "image/gif"
				}
				// Extract stripped thumbnail from document's thumb sizes (videos, stickers, GIFs).
				ref.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
				m.Attachments = []FileRef{ref}
				t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
			}
			if md.Spoiler {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["media_spoiler"] = true
			}
		case *tg.MessageMediaPhoto:
			if p, ok := md.Photo.(*tg.Photo); ok {
				ref := FileRef{
					ID:       strconv.FormatInt(p.ID, 10),
					MimeType: "image/jpeg",
					Name:     "photo.jpg",
					Extra:    encodeFileExtra(p.AccessHash, p.FileReference),
				}
				for _, size := range p.Sizes {
					if s, ok := size.(*tg.PhotoSize); ok {
						ref.Size = int64(s.Size)
						ref.Width = s.W
						ref.Height = s.H
					}
				}
				// Extract stripped thumbnail — a ~100 byte blurred JPEG delivered inline,
				// so photos show a blurhash-like preview with no download required.
				ref.ThumbB64 = extractStrippedThumbB64(p.Sizes)
				m.Attachments = []FileRef{ref}
				t.cacheFileInfo(p.ID, p.AccessHash, p.FileReference)
			}
			if md.Spoiler {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["media_spoiler"] = true
			}
		}
	}

	if reactions, ok := msg.GetReactions(); ok {
		results := reactions.Results
		if len(results) > 0 {
			m.Reactions = make([]Reaction, 0, len(results))
			for _, r := range results {
				if re, ok := r.Reaction.(*tg.ReactionEmoji); ok && re.Emoticon != "" {
					m.Reactions = append(m.Reactions, Reaction{
						Emoji: re.Emoticon,
						Count: r.Count,
						ByMe:  r.ChosenOrder > 0,
					})
				}
			}
		}
	}

	return m
}

// convertServiceMessage converts a tg.MessageService to our Message struct.
// Service messages are system events like "X joined the group", "X pinned a message", etc.
func (t *TelegramCore) convertServiceMessage(svc *tg.MessageService) *Message {
	m := &Message{
		ID:        strconv.Itoa(svc.ID),
		ChatID:    peerToID(svc.PeerID),
		Timestamp: time.Unix(int64(svc.Date), 0),
		Status:    MessageStatusSent,
		IsOutgoing: svc.Out,
		IsService: true,
		Platform:  tgPlatform,
	}

	if from := svc.FromID; from != nil {
		m.SenderID = peerToID(from)
		if peer, ok := from.(*tg.PeerUser); ok {
			m.SenderName = t.getCachedUserName(peer.UserID)
		}
	}

	m.Text = t.serviceActionText(m.SenderName, svc.Action)
	return m
}

// serviceActionText generates human-readable text from a MessageActionClass.
func (t *TelegramCore) serviceActionText(sender string, action tg.MessageActionClass) string {
	if sender == "" {
		sender = "Someone"
	}
	switch a := action.(type) {
	case *tg.MessageActionChatCreate:
		return sender + " created the group \u201c" + a.Title + "\u201d"
	case *tg.MessageActionChatEditTitle:
		return sender + " changed the group name to \u201c" + a.Title + "\u201d"
	case *tg.MessageActionChatEditPhoto:
		return sender + " updated the group photo"
	case *tg.MessageActionChatDeletePhoto:
		return sender + " removed the group photo"
	case *tg.MessageActionChatAddUser:
		names := make([]string, 0, len(a.Users))
		for _, uid := range a.Users {
			n := t.getCachedUserName(uid)
			if n == "" {
				n = "user"
			}
			names = append(names, n)
		}
		return sender + " added " + joinNames(names)
	case *tg.MessageActionChatDeleteUser:
		removed := t.getCachedUserName(a.UserID)
		if removed == "" {
			removed = "a user"
		}
		if removed == sender {
			return sender + " left the group"
		}
		return sender + " removed " + removed
	case *tg.MessageActionChatJoinedByLink:
		return sender + " joined via invite link"
	case *tg.MessageActionChatJoinedByRequest:
		return sender + " was accepted into the group"
	case *tg.MessageActionChannelCreate:
		return "Channel \u201c" + a.Title + "\u201d was created"
	case *tg.MessageActionPinMessage:
		return sender + " pinned a message"
	case *tg.MessageActionHistoryClear:
		return "Chat history was cleared"
	case *tg.MessageActionGameScore:
		return sender + " scored " + strconv.Itoa(a.Score) + " in a game"
	case *tg.MessageActionPhoneCall:
		dur := ""
		if a.Duration > 0 {
			mins := a.Duration / 60
			secs := a.Duration % 60
			if mins > 0 {
				dur = " (" + strconv.Itoa(mins) + "m " + strconv.Itoa(secs) + "s)"
			} else {
				dur = " (" + strconv.Itoa(secs) + "s)"
			}
		}
		if a.Video {
			return "Video call" + dur
		}
		return "Voice call" + dur
	case *tg.MessageActionGroupCall:
		if a.Duration > 0 {
			mins := a.Duration / 60
			secs := a.Duration % 60
			return "Voice chat ended (" + strconv.Itoa(mins) + "m " + strconv.Itoa(secs) + "s)"
		}
		return sender + " started a voice chat"
	case *tg.MessageActionContactSignUp:
		return sender + " joined Telegram"
	case *tg.MessageActionCustomAction:
		return a.Message
	case *tg.MessageActionChatMigrateTo:
		return "Group migrated to a supergroup"
	case *tg.MessageActionChannelMigrateFrom:
		return "Group migrated from \u201c" + a.Title + "\u201d"
	case *tg.MessageActionBotAllowed:
		return sender + " allowed the bot"
	case *tg.MessageActionTopicCreate:
		return sender + " created topic \u201c" + a.Title + "\u201d"
	case *tg.MessageActionTopicEdit:
		if title, ok := a.GetTitle(); ok {
			return sender + " changed topic name to \u201c" + title + "\u201d"
		}
		if closed, ok := a.GetClosed(); ok && closed {
			return sender + " closed the topic"
		}
		if closed, ok := a.GetClosed(); ok && !closed {
			return sender + " reopened the topic"
		}
		return sender + " edited the topic"
	case *tg.MessageActionInviteToGroupCall:
		return sender + " invited members to the voice chat"
	case *tg.MessageActionSetChatWallPaper:
		return sender + " changed the chat wallpaper"
	case *tg.MessageActionGiftCode:
		return sender + " sent a gift code"
	case *tg.MessageActionSetMessagesTTL:
		if a.Period > 0 {
			return sender + " set messages to auto-delete"
		}
		return sender + " disabled auto-delete timer"
	case *tg.MessageActionEmpty:
		return ""
	default:
		return sender + " performed an action"
	}
}

// joinNames joins a list of names with commas and "and".
func joinNames(names []string) string {
	switch len(names) {
	case 0:
		return ""
	case 1:
		return names[0]
	case 2:
		return names[0] + " and " + names[1]
	default:
		result := ""
		for i, n := range names {
			if i == len(names)-1 {
				result += "and " + n
			} else {
				result += n + ", "
			}
		}
		return result
	}
}

// convertTgEntities converts gotd MessageEntityClass list to our TextEntity format.
func convertTgEntities(entities []tg.MessageEntityClass) []TextEntity {
	result := make([]TextEntity, 0, len(entities))
	for _, e := range entities {
		var te TextEntity
		switch v := e.(type) {
		case *tg.MessageEntityBold:
			te = TextEntity{Type: "bold", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityItalic:
			te = TextEntity{Type: "italic", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityUnderline:
			te = TextEntity{Type: "underline", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityStrike:
			te = TextEntity{Type: "strike", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityCode:
			te = TextEntity{Type: "code", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityPre:
			te = TextEntity{Type: "pre", Offset: v.Offset, Length: v.Length, Language: v.Language}
		case *tg.MessageEntityTextURL:
			te = TextEntity{Type: "text_url", Offset: v.Offset, Length: v.Length, URL: v.URL}
		case *tg.MessageEntityURL:
			te = TextEntity{Type: "url", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityMention:
			te = TextEntity{Type: "mention", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityMentionName:
			te = TextEntity{Type: "mention_name", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityHashtag:
			te = TextEntity{Type: "hashtag", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityBotCommand:
			te = TextEntity{Type: "bot_command", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityEmail:
			te = TextEntity{Type: "email", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityPhone:
			te = TextEntity{Type: "phone", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityCashtag:
			te = TextEntity{Type: "cashtag", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntitySpoiler:
			te = TextEntity{Type: "spoiler", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityBlockquote:
			te = TextEntity{Type: "blockquote", Offset: v.Offset, Length: v.Length}
		case *tg.MessageEntityCustomEmoji:
			te = TextEntity{Type: "custom_emoji", Offset: v.Offset, Length: v.Length}
		default:
			continue
		}
		result = append(result, te)
	}
	return result
}

func (t *TelegramCore) convertUser(user *tg.User) *User {
	u := &User{
		ID:          strconv.FormatInt(user.ID, 10),
		Username:    user.Username,
		DisplayName: strings.TrimSpace(user.FirstName + " " + user.LastName),
		Phone:       user.Phone,
		IsBot:       user.Bot,
		IsContact:   user.Contact,
		IsVerified:  user.Verified,
		IsPremium:   user.Premium,
		Platform:    tgPlatform,
	}

	// Classify presence into (isOnline, kind, lastSeen) and propagate via the
	// User struct AND seed an UpdateUserStatus event so the engine cache picks
	// up initial state (the OnUserStatus dispatcher only fires on deltas, so
	// without this the DM top bar has no subtitle until the peer toggles).
	if status := user.Status; status != nil {
		var kind string
		var lastSeen *time.Time
		emit := true
		switch s := status.(type) {
		case *tg.UserStatusOnline:
			u.IsOnline = true
			kind = "online"
		case *tg.UserStatusOffline:
			u.IsOnline = false
			kind = "exact"
			ts := time.Unix(int64(s.WasOnline), 0)
			u.LastSeen = &ts
			lastSeen = &ts
		case *tg.UserStatusRecently:
			kind = "recently"
		case *tg.UserStatusLastWeek:
			kind = "within_week"
		case *tg.UserStatusLastMonth:
			kind = "within_month"
		case *tg.UserStatusEmpty:
			kind = "long_ago"
		default:
			emit = false
		}
		if emit {
			isOnline := u.IsOnline
			t.fireUpdate(Update{
				Type:         UpdateUserStatus,
				UserID:       u.ID,
				IsOnline:     &isOnline,
				LastSeenKind: kind,
				LastSeen:     lastSeen,
				Platform:     tgPlatform,
			})
		}
	}

	// Extract stripped thumbnail from profile photo (tiny b64 thumbnail, no API call needed).
	if photo, ok := user.Photo.(*tg.UserProfilePhoto); ok {
		if thumb, ok := photo.GetStrippedThumb(); ok && len(thumb) > 0 {
			if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
				u.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
			}
		}
	}

	return u
}

// extractStrippedThumbB64 walks a []PhotoSizeClass looking for a PhotoStrippedSize
// entry (tiny ~100-byte JPEG thumbnail delivered inline with the message). When
// found, it inflates it to a valid JPEG and returns the base64 encoding. Works
// for both Photo.Sizes and Document.Thumbs.
func extractStrippedThumbB64(sizes []tg.PhotoSizeClass) string {
	for _, s := range sizes {
		if stripped, ok := s.(*tg.PhotoStrippedSize); ok && len(stripped.Bytes) > 0 {
			if jpg := tgStrippedToJPEG(stripped.Bytes); len(jpg) > 0 {
				return base64.StdEncoding.EncodeToString(jpg)
			}
		}
	}
	return ""
}

// tgStrippedToJPEG reconstructs a valid JPEG from Telegram's stripped thumbnail format.
// The format strips the JPEG header/footer to save bytes; we prepend/append them back.
// See: https://core.telegram.org/api/files#stripped-thumbnails
func tgStrippedToJPEG(data []byte) []byte {
	if len(data) < 3 || data[0] != 1 {
		return nil
	}
	// Standard JPEG header template for Telegram stripped photos.
	header := []byte{
		0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
		0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x28, 0x1C, 0x1E, 0x23, 0x1E, 0x19, 0x28,
		0x23, 0x21, 0x23, 0x2D, 0x2B, 0x28, 0x30, 0x3C, 0x64, 0x41, 0x3C, 0x37, 0x37, 0x3C, 0x7B, 0x58,
		0x5D, 0x49, 0x64, 0x91, 0x80, 0x99, 0x96, 0x8F, 0x80, 0x90, 0xA9, 0xB6, 0xE3, 0xCA, 0xA9, 0xBE,
		0xA4, 0xC4, 0xDB, 0xE9, 0xE7, 0xF1, 0xF0, 0xE9, 0xDA, 0xC5, 0xE0, 0xC0, 0x80, 0x90, 0xA3, 0xA0,
		0xA8, 0xC8, 0xD0, 0xC2, 0xC0, 0x7D, 0xAB, 0xB5, 0xCC, 0xD9, 0xC7, 0xC5, 0xC0, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
		0xDB, 0x00, 0x43, 0x01, 0x2B, 0x2D, 0x2D, 0x3C, 0x35, 0x3C, 0x76, 0x41, 0x41, 0x76, 0x9C, 0x69,
		0x90, 0x99, 0x9C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x00, 0x00, 0x00, 0x03,
		0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01,
		0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
		0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00,
		0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01,
		0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22,
		0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24,
		0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29,
		0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
		0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A,
		0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A,
		0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8,
		0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6,
		0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3,
		0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9,
		0xFA, 0xFF, 0xC4, 0x00, 0x1F, 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
		0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x11, 0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07,
		0x05, 0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31,
		0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1,
		0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1,
		0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39,
		0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
		0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
		0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
		0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5,
		0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3,
		0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
		0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00,
		0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00,
	}
	footer := []byte{0xFF, 0xD9}

	// Replace height and width in the SOF0 marker (byte 164 = height, 166 = width).
	header[164] = data[1]
	header[166] = data[2]

	// Combine: header + scan data + footer.
	result := make([]byte, 0, len(header)+len(data)-3+len(footer))
	result = append(result, header...)
	result = append(result, data[3:]...)
	result = append(result, footer...)
	return result
}

func (t *TelegramCore) convertDialogs(result tg.MessagesDialogsClass) ([]Dialog, error) {
	var dialogs []Dialog

	switch r := result.(type) {
	case *tg.MessagesDialogs:
		t.cacheEntities(r.Users, r.Chats)
		dialogs = t.extractDialogs(r.Dialogs, r.Messages, r.Chats, r.Users)
	case *tg.MessagesDialogsSlice:
		t.cacheEntities(r.Users, r.Chats)
		dialogs = t.extractDialogs(r.Dialogs, r.Messages, r.Chats, r.Users)
	}

	return dialogs, nil
}

func (t *TelegramCore) extractDialogs(dlgs []tg.DialogClass, msgs []tg.MessageClass, chats []tg.ChatClass, users []tg.UserClass) []Dialog {
	userMap := make(map[int64]*tg.User, len(users))
	for _, u := range users {
		if user, ok := u.(*tg.User); ok {
			userMap[user.ID] = user
		}
	}
	chatMap := make(map[int64]tg.ChatClass, len(chats))
	for _, c := range chats {
		switch ch := c.(type) {
		case *tg.Chat:
			chatMap[ch.ID] = ch
		case *tg.Channel:
			chatMap[ch.ID] = ch
		}
	}
	msgMap := make(map[int]tg.MessageClass, len(msgs))
	for _, m := range msgs {
		if msg, ok := m.(*tg.Message); ok {
			msgMap[msg.ID] = msg
		}
	}

	result := make([]Dialog, 0, len(dlgs))
	for _, d := range dlgs {
		dlg, ok := d.(*tg.Dialog)
		if !ok {
			continue
		}

		dialog := Dialog{
			UnreadCount:         dlg.UnreadCount,
			UnreadMark:          dlg.UnreadMark,
			UnreadMentionCount:  dlg.UnreadMentionsCount,
			UnreadReactionCount: dlg.UnreadReactionsCount,
			IsPinned:            dlg.Pinned,
			Platform:            tgPlatform,
		}

		switch p := dlg.Peer.(type) {
		case *tg.PeerUser:
			dialog.ID = strconv.FormatInt(p.UserID, 10)
			dialog.Type = ChatTypeDM
			if p.UserID == t.selfID {
				// Self-chat = Saved Messages (spec §31.1).
				dialog.Title = "Saved Messages"
			} else if user, ok := userMap[p.UserID]; ok {
				dialog.Title = strings.TrimSpace(user.FirstName + " " + user.LastName)
				dialog.IsVerified = user.Verified
				dialog.IsScam = user.Scam
				dialog.IsFake = user.Fake
				if _, ok := user.Photo.(*tg.UserProfilePhoto); ok {
					dialog.AvatarURL = "has_photo"
				}
			}
		case *tg.PeerChat:
			dialog.ID = strconv.FormatInt(-p.ChatID, 10)
			dialog.Type = ChatTypeGroup
			if chat, ok := chatMap[p.ChatID]; ok {
				if c, ok := chat.(*tg.Chat); ok {
					dialog.Title = c.Title
					dialog.MemberCount = c.ParticipantsCount
					if _, ok := c.Photo.(*tg.ChatPhoto); ok {
						dialog.AvatarURL = "has_photo"
					}
				}
			}
		case *tg.PeerChannel:
			dialog.ID = strconv.FormatInt(-1000000000000-p.ChannelID, 10)
			if ch, ok := chatMap[p.ChannelID]; ok {
				if c, ok := ch.(*tg.Channel); ok {
					dialog.Title = c.Title
					dialog.MemberCount = c.ParticipantsCount
					dialog.IsVerified = c.Verified
					dialog.IsScam = c.Scam
					dialog.IsFake = c.Fake
					if c.Broadcast {
						dialog.Type = ChatTypeChannel
					} else {
						dialog.Type = ChatTypeGroup
					}
					if _, ok := c.Photo.(*tg.ChatPhoto); ok {
						dialog.AvatarURL = "has_photo"
					}
				}
			}
		}

		// Last message
		if dlg.TopMessage != 0 {
			if msg, ok := msgMap[dlg.TopMessage]; ok {
				if m, ok := msg.(*tg.Message); ok {
					dialog.LastMessage = t.convertMessage(m)
				}
			}
		}

		result = append(result, dialog)
	}

	return result
}

func (t *TelegramCore) extractMessageFromUpdates(updates tg.UpdatesClass, chatID string) *Message {
	switch u := updates.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			switch upd := update.(type) {
			case *tg.UpdateNewMessage:
				if msg, ok := upd.Message.(*tg.Message); ok {
					return t.convertMessage(msg)
				}
			case *tg.UpdateNewChannelMessage:
				if msg, ok := upd.Message.(*tg.Message); ok {
					return t.convertMessage(msg)
				}
			}
		}
	case *tg.UpdateShortSentMessage:
		return &Message{
			ID:         strconv.Itoa(u.ID),
			ChatID:     chatID,
			SenderID:   strconv.FormatInt(t.selfID, 10),
			SenderName: t.selfName,
			Timestamp:  time.Unix(int64(u.Date), 0),
			Status:     MessageStatusSent,
			IsOutgoing: true,
			Platform:   tgPlatform,
		}
	}
	// Fallback — at minimum provide timestamp and status
	return &Message{ChatID: chatID, Platform: tgPlatform, Status: MessageStatusSent, IsOutgoing: true, Timestamp: time.Now()}
}

func (t *TelegramCore) extractDialogFromUpdates(updates tg.UpdatesClass) *Dialog {
	switch u := updates.(type) {
	case *tg.Updates:
		t.cacheEntities(u.Users, u.Chats)
		for _, chat := range u.Chats {
			switch c := chat.(type) {
			case *tg.Chat:
				return &Dialog{
					ID:          strconv.FormatInt(-c.ID, 10),
					Type:        ChatTypeGroup,
					Title:       c.Title,
					MemberCount: c.ParticipantsCount,
					Platform:    tgPlatform,
				}
			case *tg.Channel:
				return &Dialog{
					ID:       strconv.FormatInt(-1000000000000-c.ID, 10),
					Type:     ChatTypeChannel,
					Title:    c.Title,
					Platform: tgPlatform,
				}
			}
		}
	}
	return &Dialog{Platform: tgPlatform}
}

func (t *TelegramCore) convertMessages(result tg.MessagesMessagesClass) []Message {
	var rawMsgs []tg.MessageClass
	switch r := result.(type) {
	case *tg.MessagesMessages:
		t.cacheEntities(r.Users, r.Chats)
		rawMsgs = r.Messages
	case *tg.MessagesMessagesSlice:
		t.cacheEntities(r.Users, r.Chats)
		rawMsgs = r.Messages
	case *tg.MessagesChannelMessages:
		t.cacheEntities(r.Users, r.Chats)
		rawMsgs = r.Messages
	}
	if len(rawMsgs) == 0 {
		return nil
	}

	// Lazily fetch admin ranks for channel/supergroup chats on first message load.
	for _, m := range rawMsgs {
		if msg, ok := m.(*tg.Message); ok {
			if ch, ok := msg.PeerID.(*tg.PeerChannel); ok {
				t.adminRanksMu.RLock()
				fetched := t.adminRanksFetched[ch.ChannelID]
				t.adminRanksMu.RUnlock()
				if !fetched {
					t.adminRanksMu.Lock()
					t.adminRanksFetched[ch.ChannelID] = true
					t.adminRanksMu.Unlock()
					t.fetchAndCacheAdminRanks(ch.ChannelID)
				}
				break
			}
		}
	}

	messages := make([]Message, 0, len(rawMsgs))
	for _, m := range rawMsgs {
		switch msg := m.(type) {
		case *tg.Message:
			messages = append(messages, *t.convertMessage(msg))
		case *tg.MessageService:
			if _, ok := msg.Action.(*tg.MessageActionEmpty); ok {
				continue // skip empty actions
			}
			if _, ok := msg.Action.(*tg.MessageActionHistoryClear); ok {
				continue // skip history clear pseudo-messages
			}
			messages = append(messages, *t.convertServiceMessage(msg))
		}
	}
	return messages
}

func inputPeerToID(peer tg.InputPeerClass) string {
	switch p := peer.(type) {
	case *tg.InputPeerUser:
		return strconv.FormatInt(p.UserID, 10)
	case *tg.InputPeerChat:
		return strconv.FormatInt(-p.ChatID, 10)
	case *tg.InputPeerChannel:
		return strconv.FormatInt(-1000000000000-p.ChannelID, 10)
	default:
		return ""
	}
}

func peerToID(peer tg.PeerClass) string {
	switch p := peer.(type) {
	case *tg.PeerUser:
		return strconv.FormatInt(p.UserID, 10)
	case *tg.PeerChat:
		return strconv.FormatInt(-p.ChatID, 10)
	case *tg.PeerChannel:
		return strconv.FormatInt(-1000000000000-p.ChannelID, 10)
	default:
		return ""
	}
}

// peerToInt64 extracts the raw numeric ID from a PeerClass (chat/channel/user).
func peerToInt64(peer tg.PeerClass) int64 {
	switch p := peer.(type) {
	case *tg.PeerUser:
		return p.UserID
	case *tg.PeerChat:
		return p.ChatID
	case *tg.PeerChannel:
		return p.ChannelID
	default:
		return 0
	}
}

// getAdminRank returns the cached admin rank for a user in a chat, or "".
func (t *TelegramCore) getAdminRank(chatID, userID int64) string {
	t.adminRanksMu.RLock()
	defer t.adminRanksMu.RUnlock()
	if ranks, ok := t.adminRanks[chatID]; ok {
		return ranks[userID]
	}
	return ""
}

// setAdminRank stores an admin rank in the cache.
func (t *TelegramCore) setAdminRank(chatID, userID int64, rank string) {
	t.adminRanksMu.Lock()
	defer t.adminRanksMu.Unlock()
	if t.adminRanks[chatID] == nil {
		t.adminRanks[chatID] = make(map[int64]string)
	}
	t.adminRanks[chatID][userID] = rank
}

// forumTopicInfo holds cached info for a forum topic (name, icon color).
type forumTopicInfo struct {
	Title     string
	IconColor int // one of the 6 predefined colors (0x6FB9F0, 0xFFD67E, etc.)
}

// cacheForumTopic stores forum topic info for use in message topic buttons.
func (t *TelegramCore) cacheForumTopic(chatID string, topicID int, title string, iconColor int) {
	t.forumTopicsMu.Lock()
	defer t.forumTopicsMu.Unlock()
	if t.forumTopics == nil {
		t.forumTopics = make(map[string]forumTopicInfo)
	}
	key := chatID + ":" + strconv.Itoa(topicID)
	t.forumTopics[key] = forumTopicInfo{Title: title, IconColor: iconColor}
}

// GetForumTopicInfo returns cached topic name and color for a given chat+topic.
// Exported so the engine can call it when populating message topic fields.
func (t *TelegramCore) GetForumTopicInfo(chatID, topicID string) (title string, iconColor int, ok bool) {
	t.forumTopicsMu.RLock()
	defer t.forumTopicsMu.RUnlock()
	key := chatID + ":" + topicID
	if info, found := t.forumTopics[key]; found {
		return info.Title, info.IconColor, true
	}
	return "", 0, false
}

// fetchAndCacheAdminRanks fetches admin ranks for a channel/supergroup and caches them.
func (t *TelegramCore) fetchAndCacheAdminRanks(channelID int64) {
	hash, err := t.resolveChannelAccessHash(channelID)
	if err != nil {
		return
	}
	participants, err := t.api.ChannelsGetParticipants(t.ctx, &tg.ChannelsGetParticipantsRequest{
		Channel: &tg.InputChannel{ChannelID: channelID, AccessHash: hash},
		Filter:  &tg.ChannelParticipantsAdmins{},
		Offset:  0,
		Limit:   200,
	})
	if err != nil {
		return
	}
	cp, ok := participants.(*tg.ChannelsChannelParticipants)
	if !ok {
		return
	}
	for _, p := range cp.Participants {
		switch admin := p.(type) {
		case *tg.ChannelParticipantAdmin:
			rank := admin.Rank
			if rank == "" {
				rank = "admin"
			}
			t.setAdminRank(channelID, admin.UserID, rank)
		case *tg.ChannelParticipantCreator:
			rank := admin.Rank
			if rank == "" {
				rank = "owner"
			}
			t.setAdminRank(channelID, admin.UserID, rank)
		}
	}
}

// GetAdminRanks returns admin/creator ranks for all admins in a chat.
// Implements engine.AdminRankProvider.
func (t *TelegramCore) GetAdminRanks(chatID string) (map[string]string, error) {
	// Check auth without holding lock for the full duration — avoids deadlock
	// when background update handlers hold t.mu.Lock().
	t.mu.RLock()
	authed := t.authed
	api := t.api
	t.mu.RUnlock()
	if !authed || api == nil {
		return nil, ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, nil // basic chats don't have admin ranks
	}

	// Use cached ranks if available.
	t.adminRanksMu.RLock()
	if cached, ok := t.adminRanks[ch.ChannelID]; ok && len(cached) > 0 {
		t.adminRanksMu.RUnlock()
		result := make(map[string]string, len(cached))
		for uid, rank := range cached {
			result[strconv.FormatInt(uid, 10)] = rank
		}
		return result, nil
	}
	t.adminRanksMu.RUnlock()

	// Fetch admin participants from the API.
	t.fetchAndCacheAdminRanks(ch.ChannelID)

	t.adminRanksMu.RLock()
	defer t.adminRanksMu.RUnlock()
	cached := t.adminRanks[ch.ChannelID]
	if len(cached) == 0 {
		return nil, nil
	}
	result := make(map[string]string, len(cached))
	for uid, rank := range cached {
		result[strconv.FormatInt(uid, 10)] = rank
	}
	return result, nil
}

// --- Interactive auth helpers ---

// ProvideAuthCode sends the OTP code to the auth flow when it's waiting interactively.
// Call this after WaitForAuthCode signals that the code is needed.
func (t *TelegramCore) ProvideAuthCode(code string) {
	if t.authCodeCh != nil {
		t.authCodeCh <- code
	}
}

// ProvideAuthPassword sends the 2FA password to the auth flow when it's waiting interactively.
func (t *TelegramCore) ProvideAuthPassword(password string) {
	if t.authPwdCh != nil {
		t.authPwdCh <- password
	}
}

// AuthCodeRequested returns a channel that is closed when the auth flow needs an OTP code.
// Returns nil if auth isn't using interactive mode (OTP was pre-provided).
// Blocks briefly to ensure auth setup is complete (avoids race with Authenticate goroutine).
func (t *TelegramCore) AuthCodeRequested() <-chan struct{} {
	if t.authSetupDone != nil {
		<-t.authSetupDone
	}
	return t.authCodeReady
}

// AuthPasswordRequested returns a channel that is closed when the auth flow needs a 2FA password.
// Returns nil if auth isn't using interactive mode (password was pre-provided).
func (t *TelegramCore) AuthPasswordRequested() <-chan struct{} {
	if t.authSetupDone != nil {
		<-t.authSetupDone
	}
	return t.authPwdReady
}

// --- QR auth ---

// StartQRAuth initializes the Telegram client for QR code authentication
// and exports the first login token. The returned URL should be displayed
// as a QR code. Call RefreshQRToken periodically to check acceptance.
func (t *TelegramCore) StartQRAuth() (tokenURL string, expiresSecs int, err error) {
	t.mu.Lock()
	t.initClient()
	t.ctx, t.cancel = context.WithCancel(context.Background())
	close(t.authSetupDone)
	t.mu.Unlock()

	clientReady := make(chan struct{})
	errCh := make(chan error, 1)

	t.wg.Add(1)
	go func() {
		defer t.wg.Done()
		errCh <- t.client.Run(t.ctx, func(ctx context.Context) error {
			api := tg.NewClient(t.client)
			up := uploader.NewUploader(api)
			sndr := message.NewSender(api).WithUploader(up)

			t.mu.Lock()
			t.api = api
			t.sender = sndr
			t.mu.Unlock()

			close(clientReady)

			// Stay connected until context is cancelled
			<-ctx.Done()
			return ctx.Err()
		})
	}()

	select {
	case <-clientReady:
	case err := <-errCh:
		return "", 0, fmt.Errorf("client failed: %w", err)
	case <-time.After(30 * time.Second):
		return "", 0, fmt.Errorf("timeout connecting")
	}

	return t.exportQRLoginToken()
}

// RefreshQRToken re-exports the QR login token and checks if it was accepted.
// Returns accepted=true if the QR was scanned successfully.
func (t *TelegramCore) RefreshQRToken() (tokenURL string, expiresSecs int, accepted bool, err error) {
	t.mu.RLock()
	if t.api == nil {
		t.mu.RUnlock()
		return "", 0, false, fmt.Errorf("client not initialized")
	}
	t.mu.RUnlock()

	url, expires, exportErr := t.exportQRLoginToken()
	if exportErr != nil {
		return "", 0, false, exportErr
	}
	if url == "" {
		// Empty URL means auth was accepted
		return "", 0, true, nil
	}
	return url, expires, false, nil
}

func (t *TelegramCore) exportQRLoginToken() (string, int, error) {
	result, err := t.api.AuthExportLoginToken(t.ctx, &tg.AuthExportLoginTokenRequest{
		APIID:   t.apiID,
		APIHash: t.apiHash,
	})
	if err != nil {
		return "", 0, fmt.Errorf("export token: %w", err)
	}

	switch v := result.(type) {
	case *tg.AuthLoginToken:
		url := "tg://login?token=" + base64.RawURLEncoding.EncodeToString(v.Token)
		expiry := int(v.Expires) - int(time.Now().Unix())
		if expiry < 0 {
			expiry = 30
		}
		return url, expiry, nil

	case *tg.AuthLoginTokenSuccess:
		authResult, ok := v.Authorization.(*tg.AuthAuthorization)
		if !ok {
			return "", 0, fmt.Errorf("unexpected auth type: %T", v.Authorization)
		}
		u, ok := authResult.User.(*tg.User)
		if !ok {
			return "", 0, fmt.Errorf("unexpected user type: %T", authResult.User)
		}
		t.mu.Lock()
		t.authed = true
		t.selfID = u.ID
		t.selfName = strings.TrimSpace(u.FirstName + " " + u.LastName)
		if t.selfName == "" {
			t.selfName = u.Username
		}
		t.mu.Unlock()
		t.peerMu.Lock()
		t.userAccessHash[u.ID] = u.AccessHash
		if t.selfName != "" {
			t.userNames[u.ID] = t.selfName
		}
		t.peerMu.Unlock()
		return "", 0, nil // empty URL = accepted

	case *tg.AuthLoginTokenMigrateTo:
		return "", 0, fmt.Errorf("DC migration required (DC %d)", v.DCID)
	}

	return "", 0, fmt.Errorf("unexpected token type: %T", result)
}

// --- Auth flow ---

type telegramAuthFlow struct {
	phone    string
	code     string
	password string

	// Interactive channels (nil if pre-provided)
	codeCh    chan string
	codeReady chan struct{}
	pwdCh     chan string
	pwdReady  chan struct{}
}

func (f *telegramAuthFlow) Phone(_ context.Context) (string, error) {
	return f.phone, nil
}

func (f *telegramAuthFlow) Password(ctx context.Context) (string, error) {
	if f.password != "" {
		return f.password, nil
	}
	if f.pwdCh != nil {
		// Signal that 2FA password is needed
		close(f.pwdReady)
		select {
		case pw := <-f.pwdCh:
			return pw, nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	return "", fmt.Errorf("2FA password required but not provided")
}

func (f *telegramAuthFlow) Code(ctx context.Context, _ *tg.AuthSentCode) (string, error) {
	if f.code != "" {
		return f.code, nil
	}
	if f.codeCh != nil {
		// Signal that OTP code is needed
		close(f.codeReady)
		select {
		case code := <-f.codeCh:
			return code, nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	return "", fmt.Errorf("OTP code required but not provided")
}

func (f *telegramAuthFlow) AcceptTermsOfService(_ context.Context, tos tg.HelpTermsOfService) error {
	return nil
}

func (f *telegramAuthFlow) SignUp(_ context.Context) (auth.UserInfo, error) {
	return auth.UserInfo{}, fmt.Errorf("sign up not supported")
}

// --- User-mode extended methods (not in Core interface) ---

// SearchMessagesGlobal searches messages across all chats.
func (t *TelegramCore) SearchMessagesGlobal(query string, limit int) ([]Message, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	if limit <= 0 {
		limit = 20
	}

	result, err := t.api.MessagesSearchGlobal(t.ctx, &tg.MessagesSearchGlobalRequest{
		Q:          query,
		Filter:     &tg.InputMessagesFilterEmpty{},
		OffsetPeer: &tg.InputPeerEmpty{},
		Limit:      limit,
	})
	if err != nil {
		return nil, fmt.Errorf("global search: %w", err)
	}

	return t.convertMessages(result), nil
}

// GetContacts returns the user's contact list.
func (t *TelegramCore) GetContacts() ([]User, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	result, err := t.api.ContactsGetContacts(t.ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get contacts: %w", err)
	}

	contacts, ok := result.(*tg.ContactsContacts)
	if !ok {
		return nil, nil // contacts not modified
	}

	t.cacheEntities(contacts.Users, nil)

	var users []User
	for _, u := range contacts.Users {
		if user, ok := u.(*tg.User); ok {
			users = append(users, *t.convertUser(user))
		}
	}
	return users, nil
}

// BlockUser blocks a user.
func (t *TelegramCore) BlockUser(userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	id, err := tgUserID(userID)
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(id)
	_, err = t.api.ContactsBlock(t.ctx, &tg.ContactsBlockRequest{
		ID: &tg.InputPeerUser{UserID: id, AccessHash: hash},
	})
	return err
}

// UnblockUser unblocks a user.
func (t *TelegramCore) UnblockUser(userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	id, err := tgUserID(userID)
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(id)
	_, err = t.api.ContactsUnblock(t.ctx, &tg.ContactsUnblockRequest{
		ID: &tg.InputPeerUser{UserID: id, AccessHash: hash},
	})
	return err
}

// ArchiveChat moves a chat to the archive folder.
func (t *TelegramCore) ArchiveChat(chatID string, archived bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	folderID := 1 // 1 = Archive folder
	if !archived {
		folderID = 0 // 0 = Main folder (unarchive)
	}

	_, err = t.api.FoldersEditPeerFolders(t.ctx, []tg.InputFolderPeer{
		{Peer: inputPeer, FolderID: folderID},
	})
	return err
}

// SendScheduled sends a message scheduled for a future time.
func (t *TelegramCore) SendScheduled(chatID string, text string, scheduleDate int) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	result, err := t.api.MessagesSendMessage(t.ctx, &tg.MessagesSendMessageRequest{
		Peer:         inputPeer,
		Message:      text,
		RandomID:     time.Now().UnixNano(),
		ScheduleDate: scheduleDate,
	})
	if err != nil {
		return nil, fmt.Errorf("send scheduled: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

// GetScheduledMessages retrieves scheduled messages in a chat.
func (t *TelegramCore) GetScheduledMessages(chatID string) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	result, err := t.api.MessagesGetScheduledHistory(t.ctx, &tg.MessagesGetScheduledHistoryRequest{
		Peer: inputPeer,
	})
	if err != nil {
		return nil, fmt.Errorf("get scheduled: %w", err)
	}

	return t.convertMessages(result), nil
}

// DeleteScheduledMessages deletes scheduled messages by ID.
func (t *TelegramCore) DeleteScheduledMessages(chatID string, msgIDs []int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	_, err = t.api.MessagesDeleteScheduledMessages(t.ctx, &tg.MessagesDeleteScheduledMessagesRequest{
		Peer: inputPeer,
		ID:   msgIDs,
	})
	return err
}

// SaveDraft saves a message draft for a chat.
func (t *TelegramCore) SaveDraft(chatID, text string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	_, err = t.api.MessagesSaveDraft(t.ctx, &tg.MessagesSaveDraftRequest{
		Peer:    inputPeer,
		Message: text,
	})
	return err
}

// ClearDraft clears the draft for a chat.
func (t *TelegramCore) ClearDraft(chatID string) error {
	return t.SaveDraft(chatID, "")
}

// ActiveSession represents a logged-in session.
type ActiveSession struct {
	Hash        int64  `json:"hash"`
	Device      string `json:"device"`
	Platform    string `json:"platform"`
	AppName     string `json:"app_name"`
	AppVersion  string `json:"app_version"`
	IP          string `json:"ip"`
	Country     string `json:"country"`
	DateCreated int    `json:"date_created"`
	DateActive  int    `json:"date_active"`
	IsCurrent   bool   `json:"is_current"`
}

// GetActiveSessions returns all active login sessions.
func (t *TelegramCore) GetActiveSessions() ([]ActiveSession, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	result, err := t.api.AccountGetAuthorizations(t.ctx)
	if err != nil {
		return nil, fmt.Errorf("get sessions: %w", err)
	}

	var sessions []ActiveSession
	for _, a := range result.Authorizations {
		sessions = append(sessions, ActiveSession{
			Hash:        a.Hash,
			Device:      a.DeviceModel,
			Platform:    a.SystemVersion,
			AppName:     a.AppName,
			AppVersion:  a.AppVersion,
			IP:          a.IP,
			Country:     a.Country,
			DateCreated: a.DateCreated,
			DateActive:  a.DateActive,
			IsCurrent:   a.Current,
		})
	}
	return sessions, nil
}

// SetGroupPermissions sets default permissions for a group/supergroup.
func (t *TelegramCore) SetGroupPermissions(chatID string, rights tg.ChatBannedRights) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	_, err = t.api.MessagesEditChatDefaultBannedRights(t.ctx, &tg.MessagesEditChatDefaultBannedRightsRequest{
		Peer:          inputPeer,
		BannedRights:  rights,
	})
	return err
}

// PromoteAdmin promotes a user to admin in a channel/supergroup.
func (t *TelegramCore) PromoteAdmin(chatID, userID string, rights tg.ChatAdminRights) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("telegram: promote only works on channels/supergroups: %w", ErrNotSupported)
	}

	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)

	_, err = t.api.ChannelsEditAdmin(t.ctx, &tg.ChannelsEditAdminRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		UserID:  &tg.InputUser{UserID: uid, AccessHash: uhash},
		AdminRights: rights,
		Rank:    "",
	})
	return err
}

// DemoteAdmin removes admin rights from a user.
func (t *TelegramCore) DemoteAdmin(chatID, userID string) error {
	return t.PromoteAdmin(chatID, userID, tg.ChatAdminRights{})
}

// RestrictUser restricts a user in a channel/supergroup.
func (t *TelegramCore) RestrictUser(chatID, userID string, rights tg.ChatBannedRights) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("restrict only works on channels/supergroups")
	}

	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)

	_, err = t.api.ChannelsEditBanned(t.ctx, &tg.ChannelsEditBannedRequest{
		Channel:     &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		BannedRights: rights,
	})
	return err
}

// SetSlowMode sets slow mode interval for a supergroup (0 to disable).
func (t *TelegramCore) SetSlowMode(chatID string, seconds int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("slow mode only works on channels/supergroups")
	}

	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleSlowMode(t.ctx, &tg.ChannelsToggleSlowModeRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Seconds: seconds,
	})
	return err
}

// GetAdminLog gets recent admin actions in a supergroup/channel.
func (t *TelegramCore) GetAdminLog(chatID string, limit int) (int, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return 0, ErrAuth
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return 0, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return 0, fmt.Errorf("admin log only works on channels/supergroups")
	}

	if limit <= 0 {
		limit = 10
	}

	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := t.api.ChannelsGetAdminLog(t.ctx, &tg.ChannelsGetAdminLogRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Q:       "",
		Limit:   limit,
	})
	if err != nil {
		return 0, fmt.Errorf("get admin log: %w", err)
	}

	return len(result.Events), nil
}

// GetStickerSet retrieves a sticker set by short name.
func (t *TelegramCore) GetStickerSet(shortName string) (*tg.MessagesStickerSet, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}

	result, err := t.api.MessagesGetStickerSet(t.ctx, &tg.MessagesGetStickerSetRequest{
		Stickerset: &tg.InputStickerSetShortName{ShortName: shortName},
	})
	if err != nil {
		return nil, fmt.Errorf("get sticker set: %w", err)
	}

	stickerSet, ok := result.(*tg.MessagesStickerSet)
	if !ok {
		return nil, ErrNotFound
	}

	// Cache file info for all stickers
	for _, doc := range stickerSet.Documents {
		if d, ok := doc.(*tg.Document); ok {
			t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		}
	}

	return stickerSet, nil
}

// DeleteFolder deletes a dialog filter/folder by ID.
func (t *TelegramCore) DeleteFolder(filterID int) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}

	_, err := t.api.MessagesUpdateDialogFilter(t.ctx, &tg.MessagesUpdateDialogFilterRequest{
		ID: filterID,
		// nil Filter = delete
	})
	return err
}

// ResolveUsername resolves a @username to a peer and caches the result.
func (t *TelegramCore) ResolveUsername(username string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return "", ErrAuth
	}

	resolved, err := t.api.ContactsResolveUsername(t.ctx, &tg.ContactsResolveUsernameRequest{
		Username: strings.TrimPrefix(username, "@"),
	})
	if err != nil {
		return "", fmt.Errorf("resolve username: %w", err)
	}

	t.cacheEntities(resolved.Users, resolved.Chats)

	if len(resolved.Users) > 0 {
		if u, ok := resolved.Users[0].(*tg.User); ok {
			return strconv.FormatInt(u.ID, 10), nil
		}
	}
	if len(resolved.Chats) > 0 {
		switch c := resolved.Chats[0].(type) {
		case *tg.Channel:
			return strconv.FormatInt(-1000000000000-c.ID, 10), nil
		case *tg.Chat:
			return strconv.FormatInt(-c.ID, 10), nil
		}
	}
	return "", ErrNotFound
}

// --- Comprehensive API methods ---

// PinDialog pins a chat dialog to the top of the chat list.
func (t *TelegramCore) PinDialog(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesToggleDialogPin(t.ctx, &tg.MessagesToggleDialogPinRequest{
		Pinned: true, Peer: &tg.InputDialogPeer{Peer: inputPeer},
	}); return err
}

// UnpinDialog unpins a dialog from the chat list.
func (t *TelegramCore) UnpinDialog(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesToggleDialogPin(t.ctx, &tg.MessagesToggleDialogPinRequest{
		Peer: &tg.InputDialogPeer{Peer: inputPeer},
	}); return err
}

// GetPinnedDialogs returns the list of pinned chats.
func (t *TelegramCore) GetPinnedDialogs() ([]Dialog, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	result, err := t.api.MessagesGetPinnedDialogs(t.ctx, 0)
	if err != nil { return nil, err }
	t.cacheEntities(result.Users, result.Chats)
	return t.extractDialogs(result.Dialogs, result.Messages, result.Chats, result.Users), nil
}

// MarkDialogUnread marks or unmarks a chat as unread.
func (t *TelegramCore) MarkDialogUnread(chatID string, unread bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesMarkDialogUnread(t.ctx, &tg.MessagesMarkDialogUnreadRequest{
		Unread: unread, Peer: &tg.InputDialogPeer{Peer: inputPeer},
	}); return err
}

// UnpinAllMessages removes all pinned messages in a chat.
func (t *TelegramCore) UnpinAllMessages(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesUnpinAllMessages(t.ctx, &tg.MessagesUnpinAllMessagesRequest{Peer: inputPeer})
	return err
}

// SetTyping sends a specific typing action to a chat.
func (t *TelegramCore) SetTyping(chatID string, action tg.SendMessageActionClass) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesSetTyping(t.ctx, &tg.MessagesSetTypingRequest{Peer: inputPeer, Action: action})
	return err
}

// GetOnlineCount returns the number of online members in a chat.
func (t *TelegramCore) GetOnlineCount(chatID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	result, err := t.api.MessagesGetOnlines(t.ctx, inputPeer)
	if err != nil { return 0, err }
	return result.Onlines, nil
}

// GetMessageViews returns the view counts for specified messages.
func (t *TelegramCore) GetMessageViews(chatID string, msgID string) ([]int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return nil, err }
	result, err := t.api.MessagesGetMessagesViews(t.ctx, &tg.MessagesGetMessagesViewsRequest{
		Peer: inputPeer, ID: []int{id}, Increment: false,
	})
	if err != nil { return nil, err }
	var views []int
	for _, v := range result.Views {
		views = append(views, v.Views)
	}
	return views, nil
}

// GetMessageReadParticipants returns users who read a specific message.
func (t *TelegramCore) GetMessageReadParticipants(chatID string, msgID string) ([]int64, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return nil, err }
	result, err := t.api.MessagesGetMessageReadParticipants(t.ctx, &tg.MessagesGetMessageReadParticipantsRequest{
		Peer: inputPeer, MsgID: id,
	})
	if err != nil { return nil, err }
	var userIDs []int64
	for _, rp := range result {
		userIDs = append(userIDs, rp.UserID)
	}
	return userIDs, nil
}

// ReadMentions marks all mentions in a chat as read.
func (t *TelegramCore) ReadMentions(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesReadMentions(t.ctx, &tg.MessagesReadMentionsRequest{Peer: inputPeer})
	return err
}

// ReadReactions marks all unread reactions in a chat as read.
func (t *TelegramCore) ReadReactions(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesReadReactions(t.ctx, &tg.MessagesReadReactionsRequest{Peer: inputPeer})
	return err
}

// TranslateText translates message text to the specified language.
func (t *TelegramCore) TranslateText(chatID string, msgID string, toLang string) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return "", err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return "", err }
	result, err := t.api.MessagesTranslateText(t.ctx, &tg.MessagesTranslateTextRequest{
		Peer: inputPeer, ID: []int{id}, ToLang: toLang,
	})
	if err != nil { return "", err }
	if len(result.Result) > 0 { return result.Result[0].Text, nil }
	return "", nil
}

// GetWebPagePreview returns a preview of a URL for link embedding.
func (t *TelegramCore) GetWebPagePreview(url string) (string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return "", ErrAuth }
	result, err := t.api.MessagesGetWebPagePreview(t.ctx, &tg.MessagesGetWebPagePreviewRequest{Message: url})
	if err != nil { return "", err }
	if result.Media != nil {
		if mw, ok := result.Media.(*tg.MessageMediaWebPage); ok {
			if wp, ok := mw.Webpage.(*tg.WebPage); ok { return wp.Title, nil }
		}
	}
	return "", nil
}

// SetHistoryTTL sets the auto-delete timer for messages in a chat.
func (t *TelegramCore) SetHistoryTTL(chatID string, period int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesSetHistoryTTL(t.ctx, &tg.MessagesSetHistoryTTLRequest{Peer: inputPeer, Period: period})
	return err
}

// GetAllDrafts returns all message drafts across all chats.
func (t *TelegramCore) GetAllDrafts() error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.MessagesGetAllDrafts(t.ctx)
	return err
}

// SendPoll sends a poll to a chat.
func (t *TelegramCore) SendPoll(chatID string, question string, answers []string) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	var pollAnswers []tg.PollAnswerClass
	for i, a := range answers {
		pollAnswers = append(pollAnswers, &tg.PollAnswer{Text: tg.TextWithEntities{Text: a}, Option: []byte{byte(i)}})
	}
	result, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(), Message: "",
		Media: &tg.InputMediaPoll{Poll: tg.Poll{ID: time.Now().UnixNano(), Question: tg.TextWithEntities{Text: question}, Answers: pollAnswers}},
	})
	if err != nil { return nil, err }
	return t.extractMessageFromUpdates(result, chatID), nil
}

// VoteInPoll casts a vote on a poll.
func (t *TelegramCore) VoteInPoll(chatID string, msgID string, optionIdx int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return err }
	_, err = t.api.MessagesSendVote(t.ctx, &tg.MessagesSendVoteRequest{
		Peer: inputPeer, MsgID: id, Options: [][]byte{{byte(optionIdx)}},
	})
	return err
}

// ExportChatInvite creates a new invite link for a chat.
func (t *TelegramCore) ExportChatInvite(chatID string) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return "", err }
	defer unlock()
	result, err := t.api.MessagesExportChatInvite(t.ctx, &tg.MessagesExportChatInviteRequest{Peer: inputPeer})
	if err != nil { return "", err }
	if inv, ok := result.(*tg.ChatInviteExported); ok { return inv.Link, nil }
	return "", nil
}

// GetFullChannel returns full information for a channel or supergroup.
func (t *TelegramCore) GetFullChannel(chatID string) (*Dialog, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return nil, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return nil, fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := t.api.ChannelsGetFullChannel(t.ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	if err != nil { return nil, err }
	t.cacheEntities(result.Users, result.Chats)
	d := &Dialog{Platform: tgPlatform, ID: chatID}
	if fc, ok := result.FullChat.(*tg.ChannelFull); ok {
		d.MemberCount = fc.ParticipantsCount
	}
	for _, c := range result.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			d.Title = cc.Title
			if cc.Broadcast { d.Type = ChatTypeChannel } else { d.Type = ChatTypeGroup }
		}
	}
	return d, nil
}

// GetParticipants returns participants of a channel or supergroup with filtering.
func (t *TelegramCore) GetParticipants(chatID string, limit int) ([]User, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return nil, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return nil, fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	if limit <= 0 { limit = 50 }
	result, err := t.api.ChannelsGetParticipants(t.ctx, &tg.ChannelsGetParticipantsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Filter: &tg.ChannelParticipantsRecent{}, Limit: limit,
	})
	if err != nil { return nil, err }
	cp, ok := result.(*tg.ChannelsChannelParticipants); if !ok { return nil, nil }
	t.cacheEntities(cp.Users, cp.Chats)
	var users []User
	for _, u := range cp.Users { if user, ok := u.(*tg.User); ok { users = append(users, *t.convertUser(user)) } }
	return users, nil
}

// GetCommonChats returns groups and channels shared with a specific user.
func (t *TelegramCore) GetCommonChats(userID string, limit int) ([]Dialog, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	id, err := tgUserID(userID)
	if err != nil { return nil, err }
	hash := t.getCachedUserHash(id)
	if limit <= 0 { limit = 50 }
	result, err := t.api.MessagesGetCommonChats(t.ctx, &tg.MessagesGetCommonChatsRequest{
		UserID: &tg.InputUser{UserID: id, AccessHash: hash}, Limit: limit,
	})
	if err != nil { return nil, err }
	var dialogs []Dialog
	if mc, ok := result.(*tg.MessagesChats); ok {
		for _, c := range mc.Chats {
			switch ch := c.(type) {
			case *tg.Chat: dialogs = append(dialogs, Dialog{ID: strconv.FormatInt(-ch.ID, 10), Title: ch.Title, Type: ChatTypeGroup, Platform: tgPlatform})
			case *tg.Channel:
				ctype := ChatTypeGroup; if ch.Broadcast { ctype = ChatTypeChannel }
				dialogs = append(dialogs, Dialog{ID: strconv.FormatInt(-1000000000000-ch.ID, 10), Title: ch.Title, Type: ctype, Platform: tgPlatform})
			}
		}
	}
	return dialogs, nil
}

// ExportMessageLink returns a public link to a specific message.
func (t *TelegramCore) ExportMessageLink(chatID string, msgID string) (string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return "", ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return "", err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return "", fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	id, err := tgMsgID(msgID)
	if err != nil { return "", err }
	result, err := t.api.ChannelsExportMessageLink(t.ctx, &tg.ChannelsExportMessageLinkRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, ID: id,
	})
	if err != nil { return "", err }
	return result.Link, nil
}

// GetSendAs returns peers the user can send messages as in a chat.
func (t *TelegramCore) GetSendAs(chatID string) ([]string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	result, err := t.api.ChannelsGetSendAs(t.ctx, &tg.ChannelsGetSendAsRequest{Peer: inputPeer})
	if err != nil { return nil, err }
	var ids []string
	for _, p := range result.Peers { ids = append(ids, peerToID(p.Peer)) }
	return ids, nil
}

// JoinChannel joins a public channel or supergroup by its username.
func (t *TelegramCore) JoinChannel(chatID string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsJoinChannel(t.ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	return err
}

// LeaveChannel leaves a channel or supergroup.
func (t *TelegramCore) LeaveChannel(chatID string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsLeaveChannel(t.ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	return err
}

// ToggleAntiSpam enables or disables the anti-spam system for a supergroup.
func (t *TelegramCore) ToggleAntiSpam(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleAntiSpam(t.ctx, &tg.ChannelsToggleAntiSpamRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	}); return err
}

// ToggleSignatures enables or disables author signatures in a channel.
func (t *TelegramCore) ToggleSignatures(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleSignatures(t.ctx, &tg.ChannelsToggleSignaturesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, SignaturesEnabled: enabled,
	}); return err
}

// TogglePreHistoryHidden controls whether new members see pre-join messages.
func (t *TelegramCore) TogglePreHistoryHidden(chatID string, hidden bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsTogglePreHistoryHidden(t.ctx, &tg.ChannelsTogglePreHistoryHiddenRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: hidden,
	}); return err
}

// ToggleNoForwards enables or disables forwarding restrictions in a chat.
func (t *TelegramCore) ToggleNoForwards(chatID string, enabled bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesToggleNoForwards(t.ctx, &tg.MessagesToggleNoForwardsRequest{Peer: inputPeer, Enabled: enabled})
	return err
}

// SetChatReactions configures which reactions are available in a chat.
func (t *TelegramCore) SetChatReactions(chatID string, reactions []tg.ReactionClass) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	var availReactions tg.ChatReactionsClass
	if reactions == nil { availReactions = &tg.ChatReactionsAll{} } else { availReactions = &tg.ChatReactionsSome{Reactions: reactions} }
	_, err = t.api.MessagesSetChatAvailableReactions(t.ctx, &tg.MessagesSetChatAvailableReactionsRequest{
		Peer: inputPeer, AvailableReactions: availReactions,
	}); return err
}

// EditChannelTitle changes the title of a channel or supergroup.
func (t *TelegramCore) EditChannelTitle(chatID string, title string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsEditTitle(t.ctx, &tg.ChannelsEditTitleRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Title: title,
	}); return err
}

// GetForumTopics returns the list of topics in a forum supergroup.
func (t *TelegramCore) GetForumTopics(chatID string, limit int) ([]Dialog, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return nil, err }
	if _, ok := peer.(*tg.PeerChannel); !ok { return nil, fmt.Errorf("not a channel") }
	if limit <= 0 { limit = 20 }
	inputPeer, _ := t.toInputPeer(peer)
	result, err := t.api.MessagesGetForumTopics(t.ctx, &tg.MessagesGetForumTopicsRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil { return nil, err }
	var topics []Dialog
	for _, topic := range result.Topics {
		if ft, ok := topic.(*tg.ForumTopic); ok {
			// Cache topic info for message topic buttons.
			t.cacheForumTopic(chatID, ft.ID, ft.Title, ft.IconColor)
			topics = append(topics, Dialog{ID: strconv.Itoa(ft.ID), Title: ft.Title, Type: ChatTypeTopic, ParentID: chatID, Platform: tgPlatform})
		}
	}
	return topics, nil
}

// ToggleForum enables or disables forum mode for a supergroup.
func (t *TelegramCore) ToggleForum(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleForum(t.ctx, &tg.ChannelsToggleForumRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	}); return err
}

// GetFullUser returns full profile information for a user by their ID.
func (t *TelegramCore) GetFullUser(userID string) (*User, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	id, err := tgUserID(userID)
	if err != nil { return nil, err }
	hash := t.getCachedUserHash(id)
	result, err := t.api.UsersGetFullUser(t.ctx, &tg.InputUser{UserID: id, AccessHash: hash})
	if err != nil { return nil, err }
	t.cacheEntities(result.Users, nil)
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok && user.ID == id {
			cu := t.convertUser(user)
			cu.Phone = result.FullUser.About
			return cu, nil
		}
	}
	return nil, ErrNotFound
}

// UpdateProfile updates the user's first name, last name, or bio.
func (t *TelegramCore) UpdateProfile(firstName, lastName, about string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	req := &tg.AccountUpdateProfileRequest{}
	if firstName != "" { req.FirstName = firstName; req.SetFlags() }
	if lastName != "" { req.LastName = lastName; req.SetFlags() }
	if about != "" { req.About = about; req.SetFlags() }
	_, err := t.api.AccountUpdateProfile(t.ctx, req); return err
}

// UpdateStatus sets the user's online or offline status.
func (t *TelegramCore) UpdateStatus(online bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.AccountUpdateStatus(t.ctx, !online); return err
}

// GetUserPhotos returns the profile photos of a user.
func (t *TelegramCore) GetUserPhotos(userID string, limit int) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	id, err := tgUserID(userID)
	if err != nil { return 0, err }
	hash := t.getCachedUserHash(id)
	if limit <= 0 { limit = 10 }
	result, err := t.api.PhotosGetUserPhotos(t.ctx, &tg.PhotosGetUserPhotosRequest{
		UserID: &tg.InputUser{UserID: id, AccessHash: hash}, Limit: limit,
	})
	if err != nil { return 0, err }
	switch r := result.(type) {
	case *tg.PhotosPhotos: return len(r.Photos), nil
	case *tg.PhotosPhotosSlice: return r.Count, nil
	}
	return 0, nil
}

// GetAccountTTL returns the account self-destruct timer.
func (t *TelegramCore) GetAccountTTL() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.AccountGetAccountTTL(t.ctx)
	if err != nil { return 0, err }
	return result.Days, nil
}

// GetPrivacy returns the privacy rules for a specific setting.
func (t *TelegramCore) GetPrivacy(key tg.InputPrivacyKeyClass) ([]tg.PrivacyRuleClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	result, err := t.api.AccountGetPrivacy(t.ctx, key)
	if err != nil { return nil, err }
	return result.Rules, nil
}

// SetPrivacy sets privacy rules for a given key (calls, messages, etc.).
func (t *TelegramCore) SetPrivacy(key tg.InputPrivacyKeyClass, rules []tg.InputPrivacyRuleClass) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.AccountSetPrivacy(t.ctx, &tg.AccountSetPrivacyRequest{
		Key: key, Rules: rules,
	})
	return err
}

// GetAllStickerSets returns all installed sticker sets.
func (t *TelegramCore) GetAllStickerSets() ([]string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	result, err := t.api.MessagesGetAllStickers(t.ctx, 0)
	if err != nil { return nil, err }
	var names []string
	if as, ok := result.(*tg.MessagesAllStickers); ok {
		for _, s := range as.Sets { names = append(names, s.ShortName) }
	}
	return names, nil
}

// GetFavedStickers returns favorite stickers.
func (t *TelegramCore) GetFavedStickers() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesGetFavedStickers(t.ctx, 0)
	if err != nil { return 0, err }
	if fs, ok := result.(*tg.MessagesFavedStickers); ok { return len(fs.Stickers), nil }
	return 0, nil
}

// StartBot starts a conversation with a bot using a deep link parameter.
func (t *TelegramCore) StartBot(botID string, chatID string, startParam string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	bid, err := tgUserID(botID)
	if err != nil { return err }
	bhash := t.getCachedUserHash(bid)
	peer, _ := t.resolvePeer(chatID)
	inputPeer, _ := t.toInputPeer(peer)
	_, err = t.api.MessagesStartBot(t.ctx, &tg.MessagesStartBotRequest{
		Bot: &tg.InputUser{UserID: bid, AccessHash: bhash}, Peer: inputPeer,
		RandomID: time.Now().UnixNano(), StartParam: startParam,
	}); return err
}

// GetBotCallbackAnswer sends a callback query to a bot and returns its answer.
func (t *TelegramCore) GetBotCallbackAnswer(chatID string, msgID string, data []byte) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return "", err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return "", err }
	result, err := t.api.MessagesGetBotCallbackAnswer(t.ctx, &tg.MessagesGetBotCallbackAnswerRequest{
		Peer: inputPeer, MsgID: id, Data: data,
	})
	if err != nil { return "", err }
	return result.Message, nil
}

// GetInlineBotResults queries an inline bot and returns its results.
func (t *TelegramCore) GetInlineBotResults(botID string, query string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	bid, err := tgUserID(botID)
	if err != nil { return 0, err }
	bhash := t.getCachedUserHash(bid)
	result, err := t.api.MessagesGetInlineBotResults(t.ctx, &tg.MessagesGetInlineBotResultsRequest{
		Bot: &tg.InputUser{UserID: bid, AccessHash: bhash},
		Peer: &tg.InputPeerSelf{}, Query: query, Offset: "",
	})
	if err != nil { return 0, err }
	return len(result.Results), nil
}

// GetCallConfig returns the WebRTC configuration for voice and video calls.
func (t *TelegramCore) GetCallConfig() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	_, err := t.api.PhoneGetCallConfig(t.ctx)
	if err != nil { return 0, err }
	return 1, nil // just verify it works
}

// GetBroadcastStats returns statistics for a broadcast channel.
func (t *TelegramCore) GetBroadcastStats(chatID string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return 0, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return 0, fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := t.api.StatsGetBroadcastStats(t.ctx, &tg.StatsGetBroadcastStatsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	})
	if err != nil { return 0, err }
	return int(result.Followers.Current), nil
}

// GetAllStories returns all visible stories from contacts and channels.
func (t *TelegramCore) GetAllStories() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.StoriesGetAllStories(t.ctx, &tg.StoriesGetAllStoriesRequest{})
	if err != nil { return 0, err }
	if as, ok := result.(*tg.StoriesAllStories); ok { return as.Count, nil }
	return 0, nil
}

// GetNearestDC returns the nearest data center for the current connection.
func (t *TelegramCore) GetNearestDC() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.HelpGetNearestDC(t.ctx)
	if err != nil { return 0, err }
	return result.NearestDC, nil
}

// GetCountriesList returns the list of countries with phone codes.
func (t *TelegramCore) GetCountriesList() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.HelpGetCountriesList(t.ctx, &tg.HelpGetCountriesListRequest{LangCode: "en"})
	if err != nil { return 0, err }
	if cl, ok := result.(*tg.HelpCountriesList); ok { return len(cl.Countries), nil }
	return 0, nil
}

// SetChatTheme sets or clears the visual theme for a chat.
func (t *TelegramCore) SetChatTheme(chatID string, emoticon string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	var theme tg.InputChatThemeClass
	if emoticon == "" {
		theme = &tg.InputChatThemeEmpty{}
	} else {
		theme = &tg.InputChatTheme{Emoticon: emoticon}
	}
	_, err = t.api.MessagesSetChatTheme(t.ctx, &tg.MessagesSetChatThemeRequest{Peer: inputPeer, Theme: theme})
	return err
}

// --- Missing comprehensive methods ---

// GetMessageReactionsList returns the list of reactions on a specific message.
func (t *TelegramCore) GetMessageReactionsList(chatID string, msgID int, limit int) ([]Reaction, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	if limit <= 0 { limit = 50 }
	result, err := t.api.MessagesGetMessageReactionsList(t.ctx, &tg.MessagesGetMessageReactionsListRequest{
		Peer: inputPeer, ID: msgID, Limit: limit,
	})
	if err != nil { return nil, err }
	var reactions []Reaction
	for _, r := range result.Reactions {
		emoji := ""
		if re, ok := r.Reaction.(*tg.ReactionEmoji); ok { emoji = re.Emoticon }
		reactions = append(reactions, Reaction{Emoji: emoji, Count: 1})
	}
	return reactions, nil
}

// GetUnreadMentions returns unread messages that mention the user.
func (t *TelegramCore) GetUnreadMentions(chatID string, limit int) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	if limit <= 0 { limit = 20 }
	result, err := t.api.MessagesGetUnreadMentions(t.ctx, &tg.MessagesGetUnreadMentionsRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil { return nil, err }
	return t.convertMessages(result), nil
}

// GetUnreadReactions returns messages with unread reactions in a chat.
func (t *TelegramCore) GetUnreadReactions(chatID string, limit int) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	if limit <= 0 { limit = 20 }
	result, err := t.api.MessagesGetUnreadReactions(t.ctx, &tg.MessagesGetUnreadReactionsRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil { return nil, err }
	return t.convertMessages(result), nil
}

// DeleteHistory deletes message history in a chat up to a specified message.
func (t *TelegramCore) DeleteHistory(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesDeleteHistory(t.ctx, &tg.MessagesDeleteHistoryRequest{Peer: inputPeer, MaxID: 0})
	return err
}

// SendScheduledNow immediately sends a previously scheduled message.
func (t *TelegramCore) SendScheduledNow(chatID string, msgIDs []int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesSendScheduledMessages(t.ctx, &tg.MessagesSendScheduledMessagesRequest{
		Peer: inputPeer, ID: msgIDs,
	})
	return err
}

// GetPollResults returns the current results of a poll.
func (t *TelegramCore) GetPollResults(chatID string, msgID int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesGetPollResults(t.ctx, &tg.MessagesGetPollResultsRequest{
		Peer: inputPeer, MsgID: msgID,
	})
	return err
}

// CheckChatInvite returns info about a chat invite link without joining.
func (t *TelegramCore) CheckChatInvite(hash string) (string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return "", ErrAuth }
	result, err := t.api.MessagesCheckChatInvite(t.ctx, hash)
	if err != nil { return "", err }
	switch inv := result.(type) {
	case *tg.ChatInvite:
		return inv.Title, nil
	case *tg.ChatInviteAlready:
		if ch, ok := inv.Chat.(*tg.Channel); ok { return ch.Title, nil }
		if ch, ok := inv.Chat.(*tg.Chat); ok { return ch.Title, nil }
	case *tg.ChatInvitePeek:
		if ch, ok := inv.Chat.(*tg.Channel); ok { return ch.Title, nil }
		if ch, ok := inv.Chat.(*tg.Chat); ok { return ch.Title, nil }
	}
	return "", nil
}

// GetFullChat returns full information for a basic group chat.
func (t *TelegramCore) GetFullChat(chatID string) (*Dialog, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return nil, err }
	chat, ok := peer.(*tg.PeerChat); if !ok { return nil, fmt.Errorf("not a basic chat") }
	result, err := t.api.MessagesGetFullChat(t.ctx, chat.ChatID)
	if err != nil { return nil, err }
	t.cacheEntities(result.Users, result.Chats)
	d := &Dialog{Platform: tgPlatform, ID: chatID, Type: ChatTypeGroup}
	if cf, ok := result.FullChat.(*tg.ChatFull); ok {
		d.Title = cf.About
	}
	for _, c := range result.Chats {
		if ch, ok := c.(*tg.Chat); ok && ch.ID == chat.ChatID { d.Title = ch.Title }
	}
	return d, nil
}

// ToggleJoinToSend controls whether users must join before sending messages.
func (t *TelegramCore) ToggleJoinToSend(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleJoinToSend(t.ctx, &tg.ChannelsToggleJoinToSendRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	}); return err
}

// ToggleJoinRequest enables or disables admin approval for new members.
func (t *TelegramCore) ToggleJoinRequest(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleJoinRequest(t.ctx, &tg.ChannelsToggleJoinRequestRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	}); return err
}

// DeleteChannel permanently deletes a channel or supergroup.
func (t *TelegramCore) DeleteChannel(chatID string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsDeleteChannel(t.ctx, &tg.InputChannel{
		ChannelID: ch.ChannelID, AccessHash: hash,
	}); return err
}

// EditForumTopic modifies the title or icon of a forum topic.
func (t *TelegramCore) EditForumTopic(chatID string, topicID int, title string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	req := &tg.MessagesEditForumTopicRequest{Peer: inputPeer, TopicID: topicID}
	req.SetTitle(title)
	_, err = t.api.MessagesEditForumTopic(t.ctx, req)
	return err
}

// FaveSticker adds or removes a sticker from favorites.
func (t *TelegramCore) FaveSticker(fileID int64, unfave bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	accessHash := t.getCachedFileHash(fileID)
	fileRef := t.getCachedFileRef(fileID)
	_, err := t.api.MessagesFaveSticker(t.ctx, &tg.MessagesFaveStickerRequest{
		ID: &tg.InputDocument{ID: fileID, AccessHash: accessHash, FileReference: fileRef},
		Unfave: unfave,
	}); return err
}

// GetMegagroupStats returns statistics for a supergroup.
func (t *TelegramCore) GetMegagroupStats(chatID string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return 0, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return 0, fmt.Errorf("not a supergroup") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := t.api.StatsGetMegagroupStats(t.ctx, &tg.StatsGetMegagroupStatsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	})
	if err != nil { return 0, err }
	return int(result.Members.Current), nil
}

// GetPeerStories returns the stories of a specific user or channel.
func (t *TelegramCore) GetPeerStories(peerID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(peerID)
	if err != nil { return 0, err }
	defer unlock()
	result, err := t.api.StoriesGetPeerStories(t.ctx, inputPeer)
	if err != nil { return 0, err }
	return len(result.Stories.Stories), nil
}

// GetConfig returns the current Telegram server configuration.
func (t *TelegramCore) GetConfig() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.HelpGetConfig(t.ctx)
	if err != nil { return 0, err }
	return len(result.DCOptions), nil
}

// GetAppConfig returns the application configuration from Telegram servers.
func (t *TelegramCore) GetAppConfig() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	_, err := t.api.HelpGetAppConfig(t.ctx, 0)
	if err != nil { return false, err }
	return true, nil
}

// --- Remaining methods for comprehensive coverage ---

// GetPassword retrieves the current 2FA password configuration for the account.
func (t *TelegramCore) GetPassword() (*tg.AccountPassword, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetPassword(t.ctx)
}

// GetGlobalPrivacy returns the current global privacy settings.
func (t *TelegramCore) GetGlobalPrivacy() (*tg.GlobalPrivacySettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetGlobalPrivacySettings(t.ctx)
}

// GetAppConfigCheck returns app config only if changed since a given hash.
func (t *TelegramCore) GetAppConfigCheck() error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.HelpGetAppConfig(t.ctx, 0)
	return err
}

// GetConfigDCCount returns the number of available data centers.
func (t *TelegramCore) GetConfigDCCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.HelpGetConfig(t.ctx)
	if err != nil { return 0, err }
	return len(result.DCOptions), nil
}

// SearchContactsCount returns the count of contacts matching a search query.
func (t *TelegramCore) SearchContactsCount(query string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.ContactsSearch(t.ctx, &tg.ContactsSearchRequest{Q: query, Limit: 20})
	if err != nil { return 0, err }
	return len(result.Users) + len(result.MyResults), nil
}

// GetTopPeersCount returns the count of top (frequently contacted) peers.
func (t *TelegramCore) GetTopPeersCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.ContactsGetTopPeers(t.ctx, &tg.ContactsGetTopPeersRequest{
		Correspondents: true, Limit: 10,
	})
	if err != nil { return 0, err }
	if tp, ok := result.(*tg.ContactsTopPeers); ok {
		count := 0; for _, c := range tp.Categories { count += len(c.Peers) }; return count, nil
	}
	return 0, nil
}

// GetBirthdaysCount returns the count of contacts with upcoming birthdays.
func (t *TelegramCore) GetBirthdaysCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.ContactsGetBirthdays(t.ctx)
	if err != nil { return 0, err }
	return len(result.Contacts), nil
}

// GetRecentStickersCount returns the count of recently used stickers.
func (t *TelegramCore) GetRecentStickersCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesGetRecentStickers(t.ctx, &tg.MessagesGetRecentStickersRequest{})
	if err != nil { return 0, err }
	if rs, ok := result.(*tg.MessagesRecentStickers); ok { return len(rs.Stickers), nil }
	return 0, nil
}

// GetFeaturedStickersCount returns the count of featured sticker sets.
func (t *TelegramCore) GetFeaturedStickersCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesGetFeaturedStickers(t.ctx, 0)
	if err != nil { return 0, err }
	if fs, ok := result.(*tg.MessagesFeaturedStickers); ok { return len(fs.Sets), nil }
	return 0, nil
}

// SearchStickerSetsCount returns the count of matching sticker sets.
func (t *TelegramCore) SearchStickerSetsCount(query string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesSearchStickerSets(t.ctx, &tg.MessagesSearchStickerSetsRequest{Q: query})
	if err != nil { return 0, err }
	if fs, ok := result.(*tg.MessagesFoundStickerSets); ok { return len(fs.Sets), nil }
	return 0, nil
}

// GetSearchCounters returns message counts matching different filters in a chat.
func (t *TelegramCore) GetSearchCounters(chatID string) ([]int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return nil, err }
	defer unlock()
	result, err := t.api.MessagesGetSearchCounters(t.ctx, &tg.MessagesGetSearchCountersRequest{
		Peer: inputPeer, Filters: []tg.MessagesFilterClass{&tg.InputMessagesFilterEmpty{}},
	})
	if err != nil { return nil, err }
	var counts []int
	for _, c := range result { counts = append(counts, c.Count) }
	return counts, nil
}

// GetDefaultHistoryTTL returns the default auto-delete timer for new chats.
func (t *TelegramCore) GetDefaultHistoryTTL() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesGetDefaultHistoryTTL(t.ctx)
	if err != nil { return 0, err }
	return result.Period, nil
}

// SetDefaultReaction sets the default emoji reaction for new messages.
func (t *TelegramCore) SetDefaultReaction(emoji string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.MessagesSetDefaultReaction(t.ctx, &tg.ReactionEmoji{Emoticon: emoji})
	return err
}

// ToggleParticipantsHidden hides or reveals the member list in a supergroup.
func (t *TelegramCore) ToggleParticipantsHidden(chatID string, hidden bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleParticipantsHidden(t.ctx, &tg.ChannelsToggleParticipantsHiddenRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: hidden,
	}); return err
}

// GetSuggestedFoldersCount returns the count of suggested chat folders.
func (t *TelegramCore) GetSuggestedFoldersCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesGetSuggestedDialogFilters(t.ctx)
	if err != nil { return 0, err }
	return len(result), nil
}

// GetPeerSettingsCheck returns action bar settings for a peer.
func (t *TelegramCore) GetPeerSettingsCheck(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesGetPeerSettings(t.ctx, inputPeer)
	return err
}

// GetParticipantInfo returns detailed info about a specific participant in a chat.
func (t *TelegramCore) GetParticipantInfo(chatID, userID string) (*User, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return nil, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return nil, fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil { return nil, err }
	uhash := t.getCachedUserHash(uid)
	result, err := t.api.ChannelsGetParticipant(t.ctx, &tg.ChannelsGetParticipantRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
	})
	if err != nil { return nil, err }
	t.cacheEntities(result.Users, result.Chats)
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok && user.ID == uid { return t.convertUser(user), nil }
	}
	return nil, ErrNotFound
}

// UploadProfilePhoto uploads and sets a new profile photo.
func (t *TelegramCore) UploadProfilePhoto(pngData []byte) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	u := uploader.NewUploader(t.api)
	upload, err := u.Upload(t.ctx, uploader.NewUpload("profile.png", io.NopCloser(bytes.NewReader(pngData)), int64(len(pngData))))
	if err != nil { return fmt.Errorf("upload: %w", err) }
	_, err = t.api.PhotosUploadProfilePhoto(t.ctx, &tg.PhotosUploadProfilePhotoRequest{
		File: upload,
	})
	return err
}

// GetDialogUnreadMarksCount returns the number of unread-marked dialogs.
func (t *TelegramCore) GetDialogUnreadMarksCount() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.MessagesGetDialogUnreadMarks(t.ctx, &tg.MessagesGetDialogUnreadMarksRequest{})
	if err != nil { return 0, err }
	return len(result), nil
}

// --- Batch 3 methods ---

// ToggleAutotranslation enables or disables automatic message translation for a chat.
func (t *TelegramCore) ToggleAutotranslation(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleAutotranslation(t.ctx, &tg.ChannelsToggleAutotranslationRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	}); return err
}

// UpdateChannelColor sets the accent color for a channel or supergroup.
func (t *TelegramCore) UpdateChannelColor(chatID string, colorIndex int) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsUpdateColor(t.ctx, &tg.ChannelsUpdateColorRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Color: colorIndex,
	}); return err
}

// DeleteProfilePhotos removes one or more profile photos.
func (t *TelegramCore) DeleteProfilePhotos() error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	// Get current photos first
	result, err := t.api.PhotosGetUserPhotos(t.ctx, &tg.PhotosGetUserPhotosRequest{
		UserID: &tg.InputUserSelf{}, Limit: 1,
	})
	if err != nil { return err }
	var photos []tg.InputPhotoClass
	switch r := result.(type) {
	case *tg.PhotosPhotos:
		for _, p := range r.Photos { if ph, ok := p.(*tg.Photo); ok { photos = append(photos, &tg.InputPhoto{ID: ph.ID, AccessHash: ph.AccessHash, FileReference: ph.FileReference}) } }
	case *tg.PhotosPhotosSlice:
		for _, p := range r.Photos { if ph, ok := p.(*tg.Photo); ok { photos = append(photos, &tg.InputPhoto{ID: ph.ID, AccessHash: ph.AccessHash, FileReference: ph.FileReference}) } }
	}
	if len(photos) == 0 { return nil }
	_, err = t.api.PhotosDeletePhotos(t.ctx, photos[:1])
	return err
}

// GetOutboxReadDate returns when an outgoing message was read.
func (t *TelegramCore) GetOutboxReadDate(chatID, msgID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return 0, err }
	result, err := t.api.MessagesGetOutboxReadDate(t.ctx, &tg.MessagesGetOutboxReadDateRequest{Peer: inputPeer, MsgID: id})
	if err != nil { return 0, err }
	return result.Date, nil
}

// SetAccountTTL sets the account self-destruct timer.
func (t *TelegramCore) SetAccountTTL(days int) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.AccountSetAccountTTL(t.ctx, tg.AccountDaysTTL{Days: days})
	return err
}

// ResolvePhone resolves a phone number to a Telegram user.
func (t *TelegramCore) ResolvePhone(phone string) (string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return "", ErrAuth }
	result, err := t.api.ContactsResolvePhone(t.ctx, phone)
	if err != nil { return "", err }
	t.cacheEntities(result.Users, result.Chats)
	if len(result.Users) > 0 {
		if u, ok := result.Users[0].(*tg.User); ok { return strconv.FormatInt(u.ID, 10), nil }
	}
	return "", ErrNotFound
}

// EditCloseFriends sets the list of close friends for story privacy.
func (t *TelegramCore) EditCloseFriends(userIDs []int64) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.ContactsEditCloseFriends(t.ctx, userIDs)
	return err
}

// --- Final batch methods ---

// EditChatInvite modifies an existing chat invite link with a new expiration date.
func (t *TelegramCore) EditChatInvite(chatID, link string, expireDate int) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return "", err }
	defer unlock()
	result, err := t.api.MessagesEditExportedChatInvite(t.ctx, &tg.MessagesEditExportedChatInviteRequest{
		Peer: inputPeer, Link: link, ExpireDate: expireDate,
	})
	if err != nil { return "", err }
	if inv, ok := result.GetInvite().(*tg.ChatInviteExported); ok { return inv.Link, nil }
	return link, nil
}

// GetInviteImporters returns users who joined via a specific invite link.
func (t *TelegramCore) GetInviteImporters(chatID, link string, limit int) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	if limit <= 0 { limit = 20 }
	result, err := t.api.MessagesGetChatInviteImporters(t.ctx, &tg.MessagesGetChatInviteImportersRequest{
		Peer: inputPeer, Link: link, Limit: limit, OffsetUser: &tg.InputUserEmpty{},
	})
	if err != nil { return 0, err }
	return result.Count, nil
}

// DeleteChatInvite revokes and deletes an exported chat invite link.
func (t *TelegramCore) DeleteChatInvite(chatID, link string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	// Must revoke first, then delete
	_, err = t.api.MessagesEditExportedChatInvite(t.ctx, &tg.MessagesEditExportedChatInviteRequest{
		Peer: inputPeer, Link: link, Revoked: true,
	})
	if err != nil { return fmt.Errorf("revoke invite: %w", err) }
	_, err = t.api.MessagesDeleteExportedChatInvite(t.ctx, &tg.MessagesDeleteExportedChatInviteRequest{
		Peer: inputPeer, Link: link,
	})
	return err
}

// GetContactIDs returns user IDs of all contacts.
func (t *TelegramCore) GetContactIDs() (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.ContactsGetContactIDs(t.ctx, 0)
	if err != nil { return 0, err }
	return len(result), nil
}

// GetDifferenceCheck fetches accumulated updates since the last known state.
func (t *TelegramCore) GetDifferenceCheck() error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	// Get current state first
	state, err := t.api.UpdatesGetState(t.ctx)
	if err != nil { return fmt.Errorf("get state: %w", err) }
	// Get difference from current state (should return empty)
	_, err = t.api.UpdatesGetDifference(t.ctx, &tg.UpdatesGetDifferenceRequest{
		Pts: state.Pts, Date: state.Date, Qts: state.Qts,
	})
	return err
}

// ReorderPinnedDialogs changes the display order of pinned chats.
func (t *TelegramCore) ReorderPinnedDialogs(chatIDs []string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	var order []tg.InputDialogPeerClass
	for _, cid := range chatIDs {
		peer, err := t.resolvePeer(cid); if err != nil { continue }
		inputPeer, _ := t.toInputPeer(peer)
		order = append(order, &tg.InputDialogPeer{Peer: inputPeer})
	}
	_, err := t.api.MessagesReorderPinnedDialogs(t.ctx, &tg.MessagesReorderPinnedDialogsRequest{
		FolderID: 0, Order: order, Force: true,
	})
	return err
}

// SetGlobalPrivacy configures global privacy settings.
func (t *TelegramCore) SetGlobalPrivacy(settings *tg.GlobalPrivacySettings) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.AccountSetGlobalPrivacySettings(t.ctx, *settings)
	return err
}

// GetReactionsList returns the list of available message reactions.
func (t *TelegramCore) GetReactionsList(chatID, msgID string, limit int) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil { return 0, err }
	if limit <= 0 { limit = 20 }
	result, err := t.api.MessagesGetMessageReactionsList(t.ctx, &tg.MessagesGetMessageReactionsListRequest{
		Peer: inputPeer, ID: id, Limit: limit,
	})
	if err != nil { return 0, err }
	return result.Count, nil
}

// GetSearchCalendar returns message counts by date for a chat search.
func (t *TelegramCore) GetSearchCalendar(chatID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	result, err := t.api.MessagesGetSearchResultsCalendar(t.ctx, &tg.MessagesGetSearchResultsCalendarRequest{
		Peer: inputPeer, Filter: &tg.InputMessagesFilterPhotos{},
	})
	if err != nil { return 0, err }
	return len(result.Periods), nil
}

// --- Upload progress ---

type uploadProgress struct {
	callback func(sent, total int64)
	total    int64
}

func (p *uploadProgress) Chunk(_ context.Context, state uploader.ProgressState) error {
	p.callback(int64(state.Uploaded), p.total)
	return nil
}

// --- Batch 4: remaining untested methods ---

// SendMultiMedia sends a group of media items as an album to a chat.
func (t *TelegramCore) SendMultiMedia(chatID string, mediaInputs []tg.InputSingleMedia) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	_, err = t.api.MessagesSendMultiMedia(t.ctx, &tg.MessagesSendMultiMediaRequest{
		Peer: inputPeer, MultiMedia: mediaInputs,
	})
	if err != nil { return 0, err }
	return len(mediaInputs), nil
}

// GetPollVotes returns the list of users who voted on specific poll options.
func (t *TelegramCore) GetPollVotes(chatID string, msgID int, limit int) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	if limit <= 0 { limit = 20 }
	result, err := t.api.MessagesGetPollVotes(t.ctx, &tg.MessagesGetPollVotesRequest{
		Peer: inputPeer, ID: msgID, Limit: limit,
	})
	if err != nil { return 0, err }
	return result.Count, nil
}

// DeleteChatHistory deletes the entire message history in a chat.
func (t *TelegramCore) DeleteChatHistory(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesDeleteHistory(t.ctx, &tg.MessagesDeleteHistoryRequest{
		Peer: inputPeer, MaxID: 0,
	})
	return err
}

// ImportChatInvite joins a chat using an invite link.
func (t *TelegramCore) ImportChatInvite(hash string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.MessagesImportChatInvite(t.ctx, hash)
	return err
}

// GetFullChatParticipantsCount returns the total participant count in a chat.
func (t *TelegramCore) GetFullChatParticipantsCount(chatID string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return 0, err }
	chat, ok := peer.(*tg.PeerChat); if !ok { return 0, fmt.Errorf("not a basic chat") }
	result, err := t.api.MessagesGetFullChat(t.ctx, chat.ChatID)
	if err != nil { return 0, err }
	t.cacheEntities(result.Users, result.Chats)
	if cf, ok := result.FullChat.(*tg.ChatFull); ok {
		if cp, ok := cf.Participants.(*tg.ChatParticipants); ok {
			return len(cp.Participants), nil
		}
	}
	return len(result.Users), nil
}

// InviteToChannel adds users to a channel or supergroup.
func (t *TelegramCore) InviteToChannel(chatID string, userIDs []string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return 0, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return 0, fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	var users []tg.InputUserClass
	for _, uid := range userIDs {
		id, err := tgUserID(uid)
		if err != nil { return 0, err }
		uhash := t.getCachedUserHash(id)
		users = append(users, &tg.InputUser{UserID: id, AccessHash: uhash})
	}
	result, err := t.api.ChannelsInviteToChannel(t.ctx, &tg.ChannelsInviteToChannelRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Users: users,
	})
	if err != nil { return 0, err }
	return len(userIDs) - len(result.MissingInvitees), nil
}

// AddChatUser adds a user to a basic group chat.
func (t *TelegramCore) AddChatUser(chatID string, userID string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	chat, ok := peer.(*tg.PeerChat); if !ok { return fmt.Errorf("not a basic chat") }
	uid, err := tgUserID(userID)
	if err != nil { return err }
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.MessagesAddChatUser(t.ctx, &tg.MessagesAddChatUserRequest{
		ChatID: chat.ChatID,
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
		FwdLimit: 100,
	})
	return err
}

// DeleteChatUser removes a user from a basic group chat.
func (t *TelegramCore) DeleteChatUser(chatID string, userID string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	chat, ok := peer.(*tg.PeerChat); if !ok { return fmt.Errorf("not a basic chat") }
	uid, err := tgUserID(userID)
	if err != nil { return err }
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.MessagesDeleteChatUser(t.ctx, &tg.MessagesDeleteChatUserRequest{
		ChatID: chat.ChatID,
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
	})
	return err
}

// EditChannelPhoto changes the photo of a channel or supergroup.
func (t *TelegramCore) EditChannelPhoto(chatID string, photoData []byte) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	u := uploader.NewUploader(t.api)
	upload, err := u.Upload(t.ctx, uploader.NewUpload("photo.png", io.NopCloser(bytes.NewReader(photoData)), int64(len(photoData))))
	if err != nil { return fmt.Errorf("upload: %w", err) }
	_, err = t.api.ChannelsEditPhoto(t.ctx, &tg.ChannelsEditPhotoRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Photo: &tg.InputChatUploadedPhoto{File: upload},
	})
	return err
}

// CreateForumTopic creates a new topic in a forum supergroup.
func (t *TelegramCore) CreateForumTopic(chatID string, title string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil { return 0, fmt.Errorf("generate random id: %w", err) }
	randomID := int64(binary.LittleEndian.Uint64(rb))
	result, err := t.api.MessagesCreateForumTopic(t.ctx, &tg.MessagesCreateForumTopicRequest{
		Peer: inputPeer, Title: title, RandomID: randomID,
	})
	if err != nil { return 0, err }
	// Extract topic ID from the updates
	switch u := result.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			switch ft := update.(type) {
			case *tg.UpdateNewChannelMessage:
				return ft.Message.GetID(), nil
			case *tg.UpdateNewMessage:
				return ft.Message.GetID(), nil
			}
		}
	}
	return 0, nil
}

// PinForumTopic pins or unpins a forum topic in a supergroup.
func (t *TelegramCore) PinForumTopic(chatID string, topicID int, pinned bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesUpdatePinnedForumTopic(t.ctx, &tg.MessagesUpdatePinnedForumTopicRequest{
		Peer: inputPeer, TopicID: topicID, Pinned: pinned,
	})
	return err
}

// ReorderPinnedForumTopics changes the order of pinned forum topics.
func (t *TelegramCore) ReorderPinnedForumTopics(chatID string, topicIDs []int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesReorderPinnedForumTopics(t.ctx, &tg.MessagesReorderPinnedForumTopicsRequest{
		Peer: inputPeer, Order: topicIDs, Force: true,
	})
	return err
}

// ToggleViewForumAsMessages toggles between forum and message list view.
func (t *TelegramCore) ToggleViewForumAsMessages(chatID string, enabled bool) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsToggleViewForumAsMessages(t.ctx, &tg.ChannelsToggleViewForumAsMessagesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

// DeleteTopicHistory deletes all messages in a forum topic.
func (t *TelegramCore) DeleteTopicHistory(chatID string, topicID int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesDeleteTopicHistory(t.ctx, &tg.MessagesDeleteTopicHistoryRequest{
		Peer: inputPeer, TopMsgID: topicID,
	})
	return err
}

// ReorderDialogFilters changes the display order of chat folders.
func (t *TelegramCore) ReorderDialogFilters(ids []int) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.MessagesUpdateDialogFiltersOrder(t.ctx, ids)
	return err
}

// DeleteContacts removes multiple users from the contact list.
func (t *TelegramCore) DeleteContacts(userIDs []string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	var users []tg.InputUserClass
	for _, uid := range userIDs {
		id, err := tgUserID(uid)
		if err != nil { return err }
		uhash := t.getCachedUserHash(id)
		users = append(users, &tg.InputUser{UserID: id, AccessHash: uhash})
	}
	_, err := t.api.ContactsDeleteContacts(t.ctx, users)
	return err
}

// ImportContacts imports phone contacts and returns matched Telegram users.
func (t *TelegramCore) ImportContacts(contacts []tg.InputPhoneContact) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.ContactsImportContacts(t.ctx, contacts)
	if err != nil { return 0, err }
	return len(result.Imported), nil
}

// UpdateUsername changes the user's primary username.
func (t *TelegramCore) UpdateUsername(username string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.AccountUpdateUsername(t.ctx, username)
	return err
}

// UpdateChannelUsername sets or clears a public username on a channel/supergroup.
func (t *TelegramCore) UpdateChannelUsername(chatID, username string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = t.api.ChannelsUpdateUsername(t.ctx, &tg.ChannelsUpdateUsernameRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Username: username,
	})
	return err
}

// UpdateBirthday sets or clears the user's birthday on their profile.
func (t *TelegramCore) UpdateBirthday(day, month, year int) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	req := &tg.AccountUpdateBirthdayRequest{}
	bday := tg.Birthday{Day: day, Month: month}
	if year > 0 { bday.SetYear(year) }
	req.SetBirthday(bday)
	_, err := t.api.AccountUpdateBirthday(t.ctx, req)
	return err
}

// GetChannelDifference fetches new updates for a channel since a given point.
func (t *TelegramCore) GetChannelDifference(chatID string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return 0, err }
	ch, ok := peer.(*tg.PeerChannel); if !ok { return 0, fmt.Errorf("not a channel") }
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := t.api.UpdatesGetChannelDifference(t.ctx, &tg.UpdatesGetChannelDifferenceRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Filter: &tg.ChannelMessagesFilterEmpty{},
		Pts: 1, Limit: 100,
	})
	if err != nil { return 0, err }
	if diff, ok := result.(*tg.UpdatesChannelDifference); ok {
		return len(diff.NewMessages) + len(diff.OtherUpdates), nil
	}
	return 0, nil
}

// SendInlineBotResult sends a result from an inline bot query.
func (t *TelegramCore) SendInlineBotResult(chatID string, queryID int64, resultID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return 0, err }
	defer unlock()
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil { return 0, fmt.Errorf("generate random id: %w", err) }
	randomID := int64(binary.LittleEndian.Uint64(rb))
	result, err := t.api.MessagesSendInlineBotResult(t.ctx, &tg.MessagesSendInlineBotResultRequest{
		Peer: inputPeer, QueryID: queryID, ID: resultID, RandomID: randomID,
	})
	if err != nil { return 0, err }
	switch u := result.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			if nm, ok := update.(*tg.UpdateNewMessage); ok { return nm.Message.GetID(), nil }
			if nm, ok := update.(*tg.UpdateNewChannelMessage); ok { return nm.Message.GetID(), nil }
		}
	}
	return 0, nil
}

// SendStoryWithPhoto uploads a photo and posts it as a story.
func (t *TelegramCore) SendStoryWithPhoto(text string, photoData []byte) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	u := uploader.NewUploader(t.api)
	upload, err := u.Upload(t.ctx, uploader.NewUpload("story.png", io.NopCloser(bytes.NewReader(photoData)), int64(len(photoData))))
	if err != nil { return 0, fmt.Errorf("upload: %w", err) }
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil { return 0, err }
	randomID := int64(binary.LittleEndian.Uint64(rb))
	req := &tg.StoriesSendStoryRequest{
		Peer: &tg.InputPeerSelf{},
		Media: &tg.InputMediaUploadedPhoto{File: upload},
		RandomID: randomID,
		PrivacyRules: []tg.InputPrivacyRuleClass{&tg.InputPrivacyValueAllowAll{}},
	}
	if text != "" { req.SetCaption(text) }
	result, err := t.api.StoriesSendStory(t.ctx, req)
	if err != nil { return 0, err }
	switch v := result.(type) {
	case *tg.Updates:
		for _, update := range v.Updates {
			if su, ok := update.(*tg.UpdateStory); ok {
				if si, ok := su.Story.(*tg.StoryItem); ok { return si.ID, nil }
			}
		}
	}
	return 0, nil
}

// SendStory publishes a new story.
func (t *TelegramCore) SendStory(text string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil { return 0, fmt.Errorf("generate random id: %w", err) }
	randomID := int64(binary.LittleEndian.Uint64(rb))
	req := &tg.StoriesSendStoryRequest{
		Peer: &tg.InputPeerSelf{},
		Media: &tg.InputMediaEmpty{},
		RandomID: randomID,
		PrivacyRules: []tg.InputPrivacyRuleClass{&tg.InputPrivacyValueAllowAll{}},
	}
	if text != "" { req.SetCaption(text) }
	result, err := t.api.StoriesSendStory(t.ctx, req)
	if err != nil { return 0, err }
	switch u := result.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			if su, ok := update.(*tg.UpdateStory); ok {
				if si, ok := su.Story.(*tg.StoryItem); ok { return si.ID, nil }
			}
		}
	}
	return 0, nil
}

// DeleteStories removes one or more stories by their IDs.
func (t *TelegramCore) DeleteStories(ids []int) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.StoriesDeleteStories(t.ctx, &tg.StoriesDeleteStoriesRequest{
		Peer: &tg.InputPeerSelf{}, ID: ids,
	})
	return err
}

// GetStoryViews returns the view counts for specified stories.
func (t *TelegramCore) GetStoryViews(ids []int) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.StoriesGetStoriesViews(t.ctx, &tg.StoriesGetStoriesViewsRequest{
		Peer: &tg.InputPeerSelf{}, ID: ids,
	})
	if err != nil { return 0, err }
	total := 0
	for _, v := range result.Views { total += v.ViewsCount }
	return total, nil
}

// ReactToStory adds an emoji reaction to a story.
func (t *TelegramCore) ReactToStory(userID string, storyID int, emoji string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	uid, err := tgUserID(userID)
	if err != nil { return err }
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.StoriesSendReaction(t.ctx, &tg.StoriesSendReactionRequest{
		Peer: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		StoryID: storyID,
		Reaction: &tg.ReactionEmoji{Emoticon: emoji},
	})
	return err
}

// GetPinnedStories returns the pinned stories of a user or channel.
func (t *TelegramCore) GetPinnedStories(userID string) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	uid, err := tgUserID(userID)
	if err != nil { return 0, err }
	uhash := t.getCachedUserHash(uid)
	result, err := t.api.StoriesGetPinnedStories(t.ctx, &tg.StoriesGetPinnedStoriesRequest{
		Peer: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		Limit: 100,
	})
	if err != nil { return 0, err }
	return len(result.Stories), nil
}

// SetChatWallpaper sets a custom wallpaper for a chat.
func (t *TelegramCore) SetChatWallpaper(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	_, err = t.api.MessagesSetChatWallPaper(t.ctx, &tg.MessagesSetChatWallPaperRequest{
		Peer: inputPeer, Revert: true,
	})
	return err
}

// HideChatJoinRequest approves or dismisses a pending join request.
func (t *TelegramCore) HideChatJoinRequest(chatID string, userID string, approved bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil { return err }
	defer unlock()
	uid, err := tgUserID(userID)
	if err != nil { return err }
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.MessagesHideChatJoinRequest(t.ctx, &tg.MessagesHideChatJoinRequestRequest{
		Peer: inputPeer, Approved: approved,
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
	})
	return err
}

// MigrateChat converts a basic group to a supergroup.
func (t *TelegramCore) MigrateChat(chatID string) (int64, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	peer, err := t.resolvePeer(chatID); if err != nil { return 0, err }
	chat, ok := peer.(*tg.PeerChat); if !ok { return 0, fmt.Errorf("not a basic chat") }
	result, err := t.api.MessagesMigrateChat(t.ctx, chat.ChatID)
	if err != nil { return 0, err }
	switch u := result.(type) {
	case *tg.Updates:
		for _, c := range u.Chats {
			if ch, ok := c.(*tg.Channel); ok { return ch.ID, nil }
		}
	}
	return 0, fmt.Errorf("supergroup ID not found in migration result")
}

// --- Chatlist (Folder Sharing) ---

// ExportChatlistInvite creates a shareable invite link for a chat folder.
func (t *TelegramCore) ExportChatlistInvite(folderID int, title string, peerIDs []string) (string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return "", ErrAuth }
	var peers []tg.InputPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil { continue }
		ip, _ := t.toInputPeer(peer)
		peers = append(peers, ip)
	}
	result, err := t.api.ChatlistsExportChatlistInvite(t.ctx, &tg.ChatlistsExportChatlistInviteRequest{
		Chatlist: tg.InputChatlistDialogFilter{FilterID: folderID},
		Title:    title,
		Peers:    peers,
	})
	if err != nil { return "", err }
	return result.Invite.URL, nil
}

// GetChatlistInvites returns invite links for a chat folder.
func (t *TelegramCore) GetChatlistInvites(folderID int) (int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return 0, ErrAuth }
	result, err := t.api.ChatlistsGetExportedInvites(t.ctx, tg.InputChatlistDialogFilter{FilterID: folderID})
	if err != nil { return 0, err }
	return len(result.Invites), nil
}

// DeleteChatlistInvite deletes an invite link for a chat folder.
func (t *TelegramCore) DeleteChatlistInvite(folderID int, slug string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	_, err := t.api.ChatlistsDeleteExportedInvite(t.ctx, &tg.ChatlistsDeleteExportedInviteRequest{
		Chatlist: tg.InputChatlistDialogFilter{FilterID: folderID},
		Slug:     slug,
	})
	return err
}

// JoinChatlistInvite joins a shared chat folder via an invite link.
func (t *TelegramCore) JoinChatlistInvite(slug string, peerIDs []string) error {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return ErrAuth }
	var peers []tg.InputPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil { continue }
		ip, _ := t.toInputPeer(peer)
		peers = append(peers, ip)
	}
	_, err := t.api.ChatlistsJoinChatlistInvite(t.ctx, &tg.ChatlistsJoinChatlistInviteRequest{
		Slug: slug, Peers: peers,
	})
	return err
}

// =============================================================================
// Call Media Transport (WebRTC via pion)
// =============================================================================

// callMedia manages the WebRTC media transport for a Telegram call.

// =============================================================================
// Auto-generated gotd/td API wrappers (506 methods)
// Generated 2026-04-07 — thin passthrough wrappers to t.api.*
// =============================================================================

// --- Account (110 methods) ---

// AccountAcceptAuthorization accepts a Telegram Passport authorization request.
func (t *TelegramCore) AccountAcceptAuthorization(request *tg.AccountAcceptAuthorizationRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountAcceptAuthorization(t.ctx, request)
}

// AccountCancelPasswordEmail cancels the password recovery email setup.
func (t *TelegramCore) AccountCancelPasswordEmail() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountCancelPasswordEmail(t.ctx)
}

// AccountChangeAuthorizationSettings modifies settings for an active session.
func (t *TelegramCore) AccountChangeAuthorizationSettings(request *tg.AccountChangeAuthorizationSettingsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountChangeAuthorizationSettings(t.ctx, request)
}

// AccountChangePhone changes the phone number for the account.
func (t *TelegramCore) AccountChangePhone(request *tg.AccountChangePhoneRequest) (tg.UserClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountChangePhone(t.ctx, request)
}

// AccountCheckUsername checks whether a username is available.
func (t *TelegramCore) AccountCheckUsername(username string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountCheckUsername(t.ctx, username)
}

// AccountClearRecentEmojiStatuses clears recently used emoji statuses.
func (t *TelegramCore) AccountClearRecentEmojiStatuses() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountClearRecentEmojiStatuses(t.ctx)
}

// AccountConfirmPasswordEmail confirms the password recovery email.
func (t *TelegramCore) AccountConfirmPasswordEmail(code string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountConfirmPasswordEmail(t.ctx, code)
}

// AccountConfirmPhone confirms phone ownership using a verification code.
func (t *TelegramCore) AccountConfirmPhone(request *tg.AccountConfirmPhoneRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountConfirmPhone(t.ctx, request)
}

// AccountCreateBusinessChatLink creates a business chat link.
func (t *TelegramCore) AccountCreateBusinessChatLink(link tg.InputBusinessChatLink) (*tg.BusinessChatLink, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountCreateBusinessChatLink(t.ctx, link)
}

// AccountCreateTheme creates a new custom theme.
func (t *TelegramCore) AccountCreateTheme(request *tg.AccountCreateThemeRequest) (*tg.Theme, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountCreateTheme(t.ctx, request)
}

// AccountDeclinePasswordReset cancels an active password reset request.
func (t *TelegramCore) AccountDeclinePasswordReset() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDeclinePasswordReset(t.ctx)
}

// AccountDeleteAccount permanently deletes the Telegram account.
func (t *TelegramCore) AccountDeleteAccount(request *tg.AccountDeleteAccountRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDeleteAccount(t.ctx, request)
}

// AccountDeleteAutoSaveExceptions removes all auto-save exception rules.
func (t *TelegramCore) AccountDeleteAutoSaveExceptions() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDeleteAutoSaveExceptions(t.ctx)
}

// AccountDeleteBusinessChatLink removes a business chat link.
func (t *TelegramCore) AccountDeleteBusinessChatLink(slug string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDeleteBusinessChatLink(t.ctx, slug)
}

// AccountDeletePasskey removes a registered passkey.
func (t *TelegramCore) AccountDeletePasskey(id string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDeletePasskey(t.ctx, id)
}

// AccountDeleteSecureValue removes stored Telegram Passport secure values.
func (t *TelegramCore) AccountDeleteSecureValue(types []tg.SecureValueTypeClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDeleteSecureValue(t.ctx, types)
}

// AccountDisablePeerConnectedBot disables a connected bot for a peer.
func (t *TelegramCore) AccountDisablePeerConnectedBot(peer tg.InputPeerClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountDisablePeerConnectedBot(t.ctx, peer)
}

// AccountEditBusinessChatLink modifies a business chat link.
func (t *TelegramCore) AccountEditBusinessChatLink(request *tg.AccountEditBusinessChatLinkRequest) (*tg.BusinessChatLink, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountEditBusinessChatLink(t.ctx, request)
}

// AccountFinishTakeoutSession completes a data export (takeout) session.
func (t *TelegramCore) AccountFinishTakeoutSession(request *tg.AccountFinishTakeoutSessionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountFinishTakeoutSession(t.ctx, request)
}

// AccountGetAllSecureValues returns all stored Telegram Passport secure values.
func (t *TelegramCore) AccountGetAllSecureValues() ([]tg.SecureValue, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetAllSecureValues(t.ctx)
}

// AccountGetAuthorizationForm returns the Passport authorization form for a bot.
func (t *TelegramCore) AccountGetAuthorizationForm(request *tg.AccountGetAuthorizationFormRequest) (*tg.AccountAuthorizationForm, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetAuthorizationForm(t.ctx, request)
}

// AccountGetAutoDownloadSettings returns automatic media download settings.
func (t *TelegramCore) AccountGetAutoDownloadSettings() (*tg.AccountAutoDownloadSettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetAutoDownloadSettings(t.ctx)
}

// AccountGetAutoSaveSettings returns automatic media save settings.
func (t *TelegramCore) AccountGetAutoSaveSettings() (*tg.AccountAutoSaveSettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetAutoSaveSettings(t.ctx)
}

// AccountGetBotBusinessConnection returns a bot's business connection info.
func (t *TelegramCore) AccountGetBotBusinessConnection(connectionid string) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetBotBusinessConnection(t.ctx, connectionid)
}

// AccountGetBusinessChatLinks returns all business chat links.
func (t *TelegramCore) AccountGetBusinessChatLinks() (*tg.AccountBusinessChatLinks, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetBusinessChatLinks(t.ctx)
}

// AccountGetChannelDefaultEmojiStatuses returns default emoji statuses for channels.
func (t *TelegramCore) AccountGetChannelDefaultEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetChannelDefaultEmojiStatuses(t.ctx, hash)
}

// AccountGetChannelRestrictedStatusEmojis returns restricted emoji statuses for channels.
func (t *TelegramCore) AccountGetChannelRestrictedStatusEmojis(hash int64) (tg.EmojiListClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetChannelRestrictedStatusEmojis(t.ctx, hash)
}

// AccountGetChatThemes returns available chat themes.
func (t *TelegramCore) AccountGetChatThemes(hash int64) (tg.AccountThemesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetChatThemes(t.ctx, hash)
}

// AccountGetCollectibleEmojiStatuses returns collectible emoji statuses.
func (t *TelegramCore) AccountGetCollectibleEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetCollectibleEmojiStatuses(t.ctx, hash)
}

// AccountGetConnectedBots returns connected bots for the account.
func (t *TelegramCore) AccountGetConnectedBots() (*tg.AccountConnectedBots, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetConnectedBots(t.ctx)
}

// AccountGetContactSignUpNotification returns whether contact sign-up notifications are enabled.
func (t *TelegramCore) AccountGetContactSignUpNotification() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountGetContactSignUpNotification(t.ctx)
}

// AccountGetContentSettings returns content filtering settings.
func (t *TelegramCore) AccountGetContentSettings() (*tg.AccountContentSettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetContentSettings(t.ctx)
}

// AccountGetDefaultBackgroundEmojis returns default background emoji options.
func (t *TelegramCore) AccountGetDefaultBackgroundEmojis(hash int64) (tg.EmojiListClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetDefaultBackgroundEmojis(t.ctx, hash)
}

// AccountGetDefaultEmojiStatuses returns default emoji status options.
func (t *TelegramCore) AccountGetDefaultEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetDefaultEmojiStatuses(t.ctx, hash)
}

// AccountGetDefaultGroupPhotoEmojis returns default group photo emoji options.
func (t *TelegramCore) AccountGetDefaultGroupPhotoEmojis(hash int64) (tg.EmojiListClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetDefaultGroupPhotoEmojis(t.ctx, hash)
}

// AccountGetDefaultProfilePhotoEmojis returns default profile photo emoji options.
func (t *TelegramCore) AccountGetDefaultProfilePhotoEmojis(hash int64) (tg.EmojiListClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetDefaultProfilePhotoEmojis(t.ctx, hash)
}

// AccountGetMultiWallPapers returns multiple wallpapers by their references.
func (t *TelegramCore) AccountGetMultiWallPapers(wallpapers []tg.InputWallPaperClass) ([]tg.WallPaperClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetMultiWallPapers(t.ctx, wallpapers)
}

// AccountGetNotifyExceptions returns chats with custom notification settings.
func (t *TelegramCore) AccountGetNotifyExceptions(request *tg.AccountGetNotifyExceptionsRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetNotifyExceptions(t.ctx, request)
}

// AccountGetNotifySettings returns notification settings for a chat or category.
func (t *TelegramCore) AccountGetNotifySettings(peer tg.InputNotifyPeerClass) (*tg.PeerNotifySettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetNotifySettings(t.ctx, peer)
}

// AccountGetPaidMessagesRevenue returns revenue from paid messages.
func (t *TelegramCore) AccountGetPaidMessagesRevenue(request *tg.AccountGetPaidMessagesRevenueRequest) (*tg.AccountPaidMessagesRevenue, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetPaidMessagesRevenue(t.ctx, request)
}

// AccountGetPasskeys returns registered passkeys for the account.
func (t *TelegramCore) AccountGetPasskeys() (*tg.AccountPasskeys, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetPasskeys(t.ctx)
}

// AccountGetPasswordSettings returns two-factor authentication settings.
func (t *TelegramCore) AccountGetPasswordSettings(password tg.InputCheckPasswordSRPClass) (*tg.AccountPasswordSettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetPasswordSettings(t.ctx, password)
}

// AccountGetReactionsNotifySettings returns reaction notification settings.
func (t *TelegramCore) AccountGetReactionsNotifySettings() (*tg.ReactionsNotifySettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetReactionsNotifySettings(t.ctx)
}

// AccountGetRecentEmojiStatuses returns recently used emoji statuses.
func (t *TelegramCore) AccountGetRecentEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetRecentEmojiStatuses(t.ctx, hash)
}

// AccountGetSavedMusicIDs returns IDs of saved music tracks.
func (t *TelegramCore) AccountGetSavedMusicIDs(hash int64) (tg.AccountSavedMusicIDsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetSavedMusicIDs(t.ctx, hash)
}

// AccountGetSavedRingtones returns saved notification ringtones.
func (t *TelegramCore) AccountGetSavedRingtones(hash int64) (tg.AccountSavedRingtonesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetSavedRingtones(t.ctx, hash)
}

// AccountGetSecureValue returns stored Telegram Passport secure values.
func (t *TelegramCore) AccountGetSecureValue(types []tg.SecureValueTypeClass) ([]tg.SecureValue, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetSecureValue(t.ctx, types)
}

// AccountGetTheme returns a theme by its slug or ID.
func (t *TelegramCore) AccountGetTheme(request *tg.AccountGetThemeRequest) (*tg.Theme, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetTheme(t.ctx, request)
}

// AccountGetThemes returns all available themes for a format.
func (t *TelegramCore) AccountGetThemes(request *tg.AccountGetThemesRequest) (tg.AccountThemesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetThemes(t.ctx, request)
}

// AccountGetTmpPassword generates a temporary password for payments.
func (t *TelegramCore) AccountGetTmpPassword(request *tg.AccountGetTmpPasswordRequest) (*tg.AccountTmpPassword, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetTmpPassword(t.ctx, request)
}

// AccountGetUniqueGiftChatThemes returns unique gift-based chat themes.
func (t *TelegramCore) AccountGetUniqueGiftChatThemes(request *tg.AccountGetUniqueGiftChatThemesRequest) (tg.AccountChatThemesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetUniqueGiftChatThemes(t.ctx, request)
}

// AccountGetWallPaper returns a wallpaper by its slug or ID.
func (t *TelegramCore) AccountGetWallPaper(wallpaper tg.InputWallPaperClass) (tg.WallPaperClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetWallPaper(t.ctx, wallpaper)
}

// AccountGetWallPapers returns all available wallpapers.
func (t *TelegramCore) AccountGetWallPapers(hash int64) (tg.AccountWallPapersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetWallPapers(t.ctx, hash)
}

// AccountGetWebAuthorizations returns active web login sessions.
func (t *TelegramCore) AccountGetWebAuthorizations() (*tg.AccountWebAuthorizations, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountGetWebAuthorizations(t.ctx)
}

// AccountInitPasskeyRegistration starts the passkey registration flow.
func (t *TelegramCore) AccountInitPasskeyRegistration() (*tg.AccountPasskeyRegistrationOptions, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountInitPasskeyRegistration(t.ctx)
}

// AccountInitTakeoutSession starts a data export (takeout) session.
func (t *TelegramCore) AccountInitTakeoutSession(request *tg.AccountInitTakeoutSessionRequest) (*tg.AccountTakeout, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountInitTakeoutSession(t.ctx, request)
}

// AccountInstallTheme applies a theme to the client.
func (t *TelegramCore) AccountInstallTheme(request *tg.AccountInstallThemeRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountInstallTheme(t.ctx, request)
}

// AccountInstallWallPaper adds a wallpaper to the user's collection.
func (t *TelegramCore) AccountInstallWallPaper(request *tg.AccountInstallWallPaperRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountInstallWallPaper(t.ctx, request)
}

// AccountInvalidateSignInCodes invalidates previously sent sign-in codes.
func (t *TelegramCore) AccountInvalidateSignInCodes(codes []string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountInvalidateSignInCodes(t.ctx, codes)
}

// AccountRegisterDevice registers a device for push notifications.
func (t *TelegramCore) AccountRegisterDevice(request *tg.AccountRegisterDeviceRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountRegisterDevice(t.ctx, request)
}

// AccountRegisterPasskey completes passkey registration.
func (t *TelegramCore) AccountRegisterPasskey(credential tg.InputPasskeyCredentialClass) (*tg.Passkey, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountRegisterPasskey(t.ctx, credential)
}

// AccountReorderUsernames changes the display order of usernames.
func (t *TelegramCore) AccountReorderUsernames(order []string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountReorderUsernames(t.ctx, order)
}

// AccountReportPeer reports a peer for terms of service violation.
func (t *TelegramCore) AccountReportPeer(request *tg.AccountReportPeerRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountReportPeer(t.ctx, request)
}

// AccountReportProfilePhoto reports a user's profile photo.
func (t *TelegramCore) AccountReportProfilePhoto(request *tg.AccountReportProfilePhotoRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountReportProfilePhoto(t.ctx, request)
}

// AccountResendPasswordEmail resends the password recovery email.
func (t *TelegramCore) AccountResendPasswordEmail() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountResendPasswordEmail(t.ctx)
}

// AccountResetNotifySettings resets all notification settings to defaults.
func (t *TelegramCore) AccountResetNotifySettings() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountResetNotifySettings(t.ctx)
}

// AccountResetPassword initiates a password reset with a waiting period.
func (t *TelegramCore) AccountResetPassword() (tg.AccountResetPasswordResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountResetPassword(t.ctx)
}

// AccountResetWallPapers resets wallpapers to the default set.
func (t *TelegramCore) AccountResetWallPapers() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountResetWallPapers(t.ctx)
}

// AccountResetWebAuthorization terminates a specific web login session.
func (t *TelegramCore) AccountResetWebAuthorization(hash int64) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountResetWebAuthorization(t.ctx, hash)
}

// AccountResetWebAuthorizations terminates all web login sessions.
func (t *TelegramCore) AccountResetWebAuthorizations() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountResetWebAuthorizations(t.ctx)
}

// AccountResolveBusinessChatLink resolves a business chat link to its target.
func (t *TelegramCore) AccountResolveBusinessChatLink(slug string) (*tg.AccountResolvedBusinessChatLinks, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountResolveBusinessChatLink(t.ctx, slug)
}

// AccountSaveAutoDownloadSettings updates automatic media download settings.
func (t *TelegramCore) AccountSaveAutoDownloadSettings(request *tg.AccountSaveAutoDownloadSettingsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSaveAutoDownloadSettings(t.ctx, request)
}

// AccountSaveAutoSaveSettings updates automatic media save settings.
func (t *TelegramCore) AccountSaveAutoSaveSettings(request *tg.AccountSaveAutoSaveSettingsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSaveAutoSaveSettings(t.ctx, request)
}

// AccountSaveMusic saves a music track to the user's collection.
func (t *TelegramCore) AccountSaveMusic(request *tg.AccountSaveMusicRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSaveMusic(t.ctx, request)
}

// AccountSaveRingtone saves or unsaves a notification ringtone.
func (t *TelegramCore) AccountSaveRingtone(request *tg.AccountSaveRingtoneRequest) (tg.AccountSavedRingtoneClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSaveRingtone(t.ctx, request)
}

// AccountSaveSecureValue stores a Telegram Passport secure value.
func (t *TelegramCore) AccountSaveSecureValue(request *tg.AccountSaveSecureValueRequest) (*tg.SecureValue, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSaveSecureValue(t.ctx, request)
}

// AccountSaveTheme saves a theme for later use.
func (t *TelegramCore) AccountSaveTheme(request *tg.AccountSaveThemeRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSaveTheme(t.ctx, request)
}

// AccountSaveWallPaper saves or unsaves a wallpaper.
func (t *TelegramCore) AccountSaveWallPaper(request *tg.AccountSaveWallPaperRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSaveWallPaper(t.ctx, request)
}

// AccountSendChangePhoneCode sends a verification code for changing the phone number.
func (t *TelegramCore) AccountSendChangePhoneCode(request *tg.AccountSendChangePhoneCodeRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSendChangePhoneCode(t.ctx, request)
}

// AccountSendConfirmPhoneCode sends a confirmation code for phone verification.
func (t *TelegramCore) AccountSendConfirmPhoneCode(request *tg.AccountSendConfirmPhoneCodeRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSendConfirmPhoneCode(t.ctx, request)
}

// AccountSendVerifyEmailCode sends a verification code to an email address.
func (t *TelegramCore) AccountSendVerifyEmailCode(request *tg.AccountSendVerifyEmailCodeRequest) (*tg.AccountSentEmailCode, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSendVerifyEmailCode(t.ctx, request)
}

// AccountSendVerifyPhoneCode sends a phone verification code.
func (t *TelegramCore) AccountSendVerifyPhoneCode(request *tg.AccountSendVerifyPhoneCodeRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSendVerifyPhoneCode(t.ctx, request)
}

// AccountSetAuthorizationTTL sets the inactivity timeout for sessions.
func (t *TelegramCore) AccountSetAuthorizationTTL(authorizationttldays int) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSetAuthorizationTTL(t.ctx, authorizationttldays)
}

// AccountSetContactSignUpNotification toggles contact sign-up notifications.
func (t *TelegramCore) AccountSetContactSignUpNotification(silent bool) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSetContactSignUpNotification(t.ctx, silent)
}

// AccountSetContentSettings configures content filtering settings.
func (t *TelegramCore) AccountSetContentSettings(request *tg.AccountSetContentSettingsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSetContentSettings(t.ctx, request)
}

// AccountSetMainProfileTab sets the default tab on the user's profile.
func (t *TelegramCore) AccountSetMainProfileTab(tab tg.ProfileTabClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountSetMainProfileTab(t.ctx, tab)
}

// AccountSetReactionsNotifySettings configures reaction notification settings.
func (t *TelegramCore) AccountSetReactionsNotifySettings(settings tg.ReactionsNotifySettings) (*tg.ReactionsNotifySettings, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountSetReactionsNotifySettings(t.ctx, settings)
}

// AccountToggleConnectedBotPaused pauses or resumes a connected bot.
func (t *TelegramCore) AccountToggleConnectedBotPaused(request *tg.AccountToggleConnectedBotPausedRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountToggleConnectedBotPaused(t.ctx, request)
}

// AccountToggleNoPaidMessagesException toggles paid message exception for a peer.
func (t *TelegramCore) AccountToggleNoPaidMessagesException(request *tg.AccountToggleNoPaidMessagesExceptionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountToggleNoPaidMessagesException(t.ctx, request)
}

// AccountToggleSponsoredMessages enables or disables sponsored messages.
func (t *TelegramCore) AccountToggleSponsoredMessages(enabled bool) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountToggleSponsoredMessages(t.ctx, enabled)
}

// AccountToggleUsername activates or deactivates a username.
func (t *TelegramCore) AccountToggleUsername(request *tg.AccountToggleUsernameRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountToggleUsername(t.ctx, request)
}

// AccountUnregisterDevice unregisters a device from push notifications.
func (t *TelegramCore) AccountUnregisterDevice(request *tg.AccountUnregisterDeviceRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUnregisterDevice(t.ctx, request)
}

// AccountUpdateBusinessAwayMessage sets or clears the business away message.
func (t *TelegramCore) AccountUpdateBusinessAwayMessage(request *tg.AccountUpdateBusinessAwayMessageRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateBusinessAwayMessage(t.ctx, request)
}

// AccountUpdateBusinessGreetingMessage sets or clears the business greeting message.
func (t *TelegramCore) AccountUpdateBusinessGreetingMessage(request *tg.AccountUpdateBusinessGreetingMessageRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateBusinessGreetingMessage(t.ctx, request)
}

// AccountUpdateBusinessIntro sets or clears the business introduction.
func (t *TelegramCore) AccountUpdateBusinessIntro(request *tg.AccountUpdateBusinessIntroRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateBusinessIntro(t.ctx, request)
}

// AccountUpdateBusinessLocation sets or clears the business location.
func (t *TelegramCore) AccountUpdateBusinessLocation(request *tg.AccountUpdateBusinessLocationRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateBusinessLocation(t.ctx, request)
}

// AccountUpdateBusinessWorkHours sets or clears the business work hours.
func (t *TelegramCore) AccountUpdateBusinessWorkHours(request *tg.AccountUpdateBusinessWorkHoursRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateBusinessWorkHours(t.ctx, request)
}

// AccountUpdateColor sets the accent color and background emoji for the profile.
func (t *TelegramCore) AccountUpdateColor(request *tg.AccountUpdateColorRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateColor(t.ctx, request)
}

// AccountUpdateConnectedBot updates settings for a connected bot.
func (t *TelegramCore) AccountUpdateConnectedBot(request *tg.AccountUpdateConnectedBotRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountUpdateConnectedBot(t.ctx, request)
}

// AccountUpdateDeviceLocked updates the device lock period for the session.
func (t *TelegramCore) AccountUpdateDeviceLocked(period int) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateDeviceLocked(t.ctx, period)
}

// AccountUpdateEmojiStatus sets or clears the user's emoji status.
func (t *TelegramCore) AccountUpdateEmojiStatus(emojistatus tg.EmojiStatusClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateEmojiStatus(t.ctx, emojistatus)
}

// AccountUpdateNotifySettings configures notification settings for a chat or category.
func (t *TelegramCore) AccountUpdateNotifySettings(request *tg.AccountUpdateNotifySettingsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdateNotifySettings(t.ctx, request)
}

// AccountUpdatePasswordSettings updates two-factor authentication settings.
func (t *TelegramCore) AccountUpdatePasswordSettings(request *tg.AccountUpdatePasswordSettingsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdatePasswordSettings(t.ctx, request)
}

// AccountUpdatePersonalChannel sets or clears the personal channel on the profile.
func (t *TelegramCore) AccountUpdatePersonalChannel(channel tg.InputChannelClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountUpdatePersonalChannel(t.ctx, channel)
}

// AccountUpdateTheme modifies an existing custom theme.
func (t *TelegramCore) AccountUpdateTheme(request *tg.AccountUpdateThemeRequest) (*tg.Theme, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountUpdateTheme(t.ctx, request)
}

// AccountUploadRingtone uploads a custom notification ringtone.
func (t *TelegramCore) AccountUploadRingtone(request *tg.AccountUploadRingtoneRequest) (tg.DocumentClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountUploadRingtone(t.ctx, request)
}

// AccountUploadTheme uploads a theme file to Telegram.
func (t *TelegramCore) AccountUploadTheme(request *tg.AccountUploadThemeRequest) (tg.DocumentClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountUploadTheme(t.ctx, request)
}

// AccountUploadWallPaper uploads a custom wallpaper image.
func (t *TelegramCore) AccountUploadWallPaper(request *tg.AccountUploadWallPaperRequest) (tg.WallPaperClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountUploadWallPaper(t.ctx, request)
}

// AccountVerifyEmail verifies an email address using the received code.
func (t *TelegramCore) AccountVerifyEmail(request *tg.AccountVerifyEmailRequest) (tg.AccountEmailVerifiedClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AccountVerifyEmail(t.ctx, request)
}

// AccountVerifyPhone verifies a phone number using the received code.
func (t *TelegramCore) AccountVerifyPhone(request *tg.AccountVerifyPhoneRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AccountVerifyPhone(t.ctx, request)
}

// --- Auth (25 methods) ---

// AuthAcceptLoginToken accepts a QR code login token from another device.
func (t *TelegramCore) AuthAcceptLoginToken(token []byte) (*tg.Authorization, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthAcceptLoginToken(t.ctx, token)
}

// AuthBindTempAuthKey binds a temporary auth key to a permanent one.
func (t *TelegramCore) AuthBindTempAuthKey(request *tg.AuthBindTempAuthKeyRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthBindTempAuthKey(t.ctx, request)
}

// AuthCancelCode cancels the authentication code sent to a phone number.
func (t *TelegramCore) AuthCancelCode(request *tg.AuthCancelCodeRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthCancelCode(t.ctx, request)
}

// AuthCheckPaidAuth checks whether paid authentication is available.
func (t *TelegramCore) AuthCheckPaidAuth(request *tg.AuthCheckPaidAuthRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthCheckPaidAuth(t.ctx, request)
}

// AuthCheckPassword verifies the two-factor authentication password.
func (t *TelegramCore) AuthCheckPassword(password tg.InputCheckPasswordSRPClass) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthCheckPassword(t.ctx, password)
}

// AuthCheckRecoveryPassword checks if a recovery password is valid.
func (t *TelegramCore) AuthCheckRecoveryPassword(code string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthCheckRecoveryPassword(t.ctx, code)
}

// AuthDropTempAuthKeys drops temporary auth keys except the specified ones.
func (t *TelegramCore) AuthDropTempAuthKeys(exceptauthkeys []int64) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthDropTempAuthKeys(t.ctx, exceptauthkeys)
}

// AuthExportAuthorization exports an authorization token for another DC.
func (t *TelegramCore) AuthExportAuthorization(dcid int) (*tg.AuthExportedAuthorization, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthExportAuthorization(t.ctx, dcid)
}

// AuthExportLoginToken generates a QR code login token.
func (t *TelegramCore) AuthExportLoginToken(request *tg.AuthExportLoginTokenRequest) (tg.AuthLoginTokenClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthExportLoginToken(t.ctx, request)
}

// AuthFinishPasskeyLogin completes passkey-based authentication.
func (t *TelegramCore) AuthFinishPasskeyLogin(request *tg.AuthFinishPasskeyLoginRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthFinishPasskeyLogin(t.ctx, request)
}

// AuthImportAuthorization imports an authorization token from another DC.
func (t *TelegramCore) AuthImportAuthorization(request *tg.AuthImportAuthorizationRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthImportAuthorization(t.ctx, request)
}

// AuthImportBotAuthorization authenticates a bot using a bot token.
func (t *TelegramCore) AuthImportBotAuthorization(request *tg.AuthImportBotAuthorizationRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthImportBotAuthorization(t.ctx, request)
}

// AuthImportLoginToken imports a login token for QR code authentication.
func (t *TelegramCore) AuthImportLoginToken(token []byte) (tg.AuthLoginTokenClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthImportLoginToken(t.ctx, token)
}

// AuthImportWebTokenAuthorization authenticates using a web login token.
func (t *TelegramCore) AuthImportWebTokenAuthorization(request *tg.AuthImportWebTokenAuthorizationRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthImportWebTokenAuthorization(t.ctx, request)
}

// AuthInitPasskeyLogin initiates passkey-based authentication.
func (t *TelegramCore) AuthInitPasskeyLogin(request *tg.AuthInitPasskeyLoginRequest) (*tg.AuthPasskeyLoginOptions, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthInitPasskeyLogin(t.ctx, request)
}

// AuthRecoverPassword recovers the account using a recovery email code.
func (t *TelegramCore) AuthRecoverPassword(request *tg.AuthRecoverPasswordRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthRecoverPassword(t.ctx, request)
}

// AuthReportMissingCode reports that an authentication code was not received.
func (t *TelegramCore) AuthReportMissingCode(request *tg.AuthReportMissingCodeRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthReportMissingCode(t.ctx, request)
}

// AuthRequestFirebaseSMS requests an auth code via Firebase SMS.
func (t *TelegramCore) AuthRequestFirebaseSMS(request *tg.AuthRequestFirebaseSMSRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthRequestFirebaseSMS(t.ctx, request)
}

// AuthRequestPasswordRecovery sends a recovery code to the registered email.
func (t *TelegramCore) AuthRequestPasswordRecovery() (*tg.AuthPasswordRecovery, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthRequestPasswordRecovery(t.ctx)
}

// AuthResendCode requests a new authentication code via an alternative method.
func (t *TelegramCore) AuthResendCode(request *tg.AuthResendCodeRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthResendCode(t.ctx, request)
}

// AuthResetAuthorizations terminates all other sessions.
func (t *TelegramCore) AuthResetAuthorizations() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.AuthResetAuthorizations(t.ctx)
}

// AuthResetLoginEmail resets the login email for the account.
func (t *TelegramCore) AuthResetLoginEmail(request *tg.AuthResetLoginEmailRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthResetLoginEmail(t.ctx, request)
}

// AuthSendCode sends an authentication code to the specified phone number.
func (t *TelegramCore) AuthSendCode(request *tg.AuthSendCodeRequest) (tg.AuthSentCodeClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthSendCode(t.ctx, request)
}

// AuthSignIn completes sign-in using the phone code.
func (t *TelegramCore) AuthSignIn(request *tg.AuthSignInRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthSignIn(t.ctx, request)
}

// AuthSignUp registers a new account after receiving an authentication code.
func (t *TelegramCore) AuthSignUp(request *tg.AuthSignUpRequest) (tg.AuthAuthorizationClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.AuthSignUp(t.ctx, request)
}

// --- Bots (35 methods) ---

// BotsAddPreviewMedia adds a preview media item to a bot's profile.
func (t *TelegramCore) BotsAddPreviewMedia(request *tg.BotsAddPreviewMediaRequest) (*tg.BotPreviewMedia, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsAddPreviewMedia(t.ctx, request)
}

// BotsAllowSendMessage allows a bot to send messages to the user.
func (t *TelegramCore) BotsAllowSendMessage(bot tg.InputUserClass) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsAllowSendMessage(t.ctx, bot)
}

// BotsAnswerWebhookJSONQuery answers a webhook callback with JSON data.
func (t *TelegramCore) BotsAnswerWebhookJSONQuery(request *tg.BotsAnswerWebhookJSONQueryRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsAnswerWebhookJSONQuery(t.ctx, request)
}

// BotsCanSendMessage checks if a bot can send messages to the user.
func (t *TelegramCore) BotsCanSendMessage(bot tg.InputUserClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsCanSendMessage(t.ctx, bot)
}

// BotsCheckDownloadFileParams validates bot file download parameters.
func (t *TelegramCore) BotsCheckDownloadFileParams(request *tg.BotsCheckDownloadFileParamsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsCheckDownloadFileParams(t.ctx, request)
}

// BotsCheckUsername checks if a username is available for a bot.
func (t *TelegramCore) BotsCheckUsername(username string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsCheckUsername(t.ctx, username)
}

// BotsCreateBot creates a new bot.
func (t *TelegramCore) BotsCreateBot(request *tg.BotsCreateBotRequest) (tg.UserClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsCreateBot(t.ctx, request)
}

// BotsDeletePreviewMedia removes preview media from a bot's profile.
func (t *TelegramCore) BotsDeletePreviewMedia(request *tg.BotsDeletePreviewMediaRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsDeletePreviewMedia(t.ctx, request)
}

// BotsEditPreviewMedia modifies a bot's preview media.
func (t *TelegramCore) BotsEditPreviewMedia(request *tg.BotsEditPreviewMediaRequest) (*tg.BotPreviewMedia, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsEditPreviewMedia(t.ctx, request)
}

// BotsExportBotToken generates a new bot API token.
func (t *TelegramCore) BotsExportBotToken(request *tg.BotsExportBotTokenRequest) (*tg.BotsExportedBotToken, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsExportBotToken(t.ctx, request)
}

// BotsGetAdminedBots returns bots owned by the user.
func (t *TelegramCore) BotsGetAdminedBots() ([]tg.UserClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetAdminedBots(t.ctx)
}

// BotsGetBotCommands returns a bot's command list.
func (t *TelegramCore) BotsGetBotCommands(request *tg.BotsGetBotCommandsRequest) ([]tg.BotCommand, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetBotCommands(t.ctx, request)
}

// BotsGetBotInfo returns a bot's description and about text.
func (t *TelegramCore) BotsGetBotInfo(request *tg.BotsGetBotInfoRequest) (*tg.BotsBotInfo, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetBotInfo(t.ctx, request)
}

// BotsGetBotMenuButton returns a bot's menu button configuration.
func (t *TelegramCore) BotsGetBotMenuButton(userid tg.InputUserClass) (tg.BotMenuButtonClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetBotMenuButton(t.ctx, userid)
}

// BotsGetBotRecommendations returns recommended similar bots.
func (t *TelegramCore) BotsGetBotRecommendations(bot tg.InputUserClass) (tg.UsersUsersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetBotRecommendations(t.ctx, bot)
}

// BotsGetPopularAppBots returns popular bot mini apps.
func (t *TelegramCore) BotsGetPopularAppBots(request *tg.BotsGetPopularAppBotsRequest) (*tg.BotsPopularAppBots, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetPopularAppBots(t.ctx, request)
}

// BotsGetPreviewInfo returns preview information for a bot.
func (t *TelegramCore) BotsGetPreviewInfo(request *tg.BotsGetPreviewInfoRequest) (*tg.BotsPreviewInfo, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetPreviewInfo(t.ctx, request)
}

// BotsGetPreviewMedias returns a bot's preview media items.
func (t *TelegramCore) BotsGetPreviewMedias(bot tg.InputUserClass) ([]tg.BotPreviewMedia, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetPreviewMedias(t.ctx, bot)
}

// BotsGetRequestedWebViewButton returns web view button request info.
func (t *TelegramCore) BotsGetRequestedWebViewButton(request *tg.BotsGetRequestedWebViewButtonRequest) (tg.KeyboardButtonClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsGetRequestedWebViewButton(t.ctx, request)
}

// BotsInvokeWebViewCustomMethod invokes a custom method in a web view.
func (t *TelegramCore) BotsInvokeWebViewCustomMethod(request *tg.BotsInvokeWebViewCustomMethodRequest) (*tg.DataJSON, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsInvokeWebViewCustomMethod(t.ctx, request)
}

// BotsReorderPreviewMedias reorders a bot's preview media.
func (t *TelegramCore) BotsReorderPreviewMedias(request *tg.BotsReorderPreviewMediasRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsReorderPreviewMedias(t.ctx, request)
}

// BotsReorderUsernames reorders a bot's usernames.
func (t *TelegramCore) BotsReorderUsernames(request *tg.BotsReorderUsernamesRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsReorderUsernames(t.ctx, request)
}

// BotsRequestWebViewButton requests a web view button for a bot.
func (t *TelegramCore) BotsRequestWebViewButton(request *tg.BotsRequestWebViewButtonRequest) (*tg.BotsRequestedButton, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsRequestWebViewButton(t.ctx, request)
}

// BotsResetBotCommands clears a bot's command list.
func (t *TelegramCore) BotsResetBotCommands(request *tg.BotsResetBotCommandsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsResetBotCommands(t.ctx, request)
}

// BotsSendCustomRequest sends a custom request to the bot API.
func (t *TelegramCore) BotsSendCustomRequest(request *tg.BotsSendCustomRequestRequest) (*tg.DataJSON, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsSendCustomRequest(t.ctx, request)
}

// BotsSetBotBroadcastDefaultAdminRights sets default bot admin rights in channels.
func (t *TelegramCore) BotsSetBotBroadcastDefaultAdminRights(adminrights tg.ChatAdminRights) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsSetBotBroadcastDefaultAdminRights(t.ctx, adminrights)
}

// BotsSetBotCommands sets a bot's command list.
func (t *TelegramCore) BotsSetBotCommands(request *tg.BotsSetBotCommandsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsSetBotCommands(t.ctx, request)
}

// BotsSetBotGroupDefaultAdminRights sets default bot admin rights in groups.
func (t *TelegramCore) BotsSetBotGroupDefaultAdminRights(adminrights tg.ChatAdminRights) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsSetBotGroupDefaultAdminRights(t.ctx, adminrights)
}

// BotsSetBotInfo sets a bot's description and about text.
func (t *TelegramCore) BotsSetBotInfo(request *tg.BotsSetBotInfoRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsSetBotInfo(t.ctx, request)
}

// BotsSetBotMenuButton sets a bot's menu button.
func (t *TelegramCore) BotsSetBotMenuButton(request *tg.BotsSetBotMenuButtonRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsSetBotMenuButton(t.ctx, request)
}

// BotsSetCustomVerification sets a custom verification badge for a bot.
func (t *TelegramCore) BotsSetCustomVerification(request *tg.BotsSetCustomVerificationRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsSetCustomVerification(t.ctx, request)
}

// BotsToggleUserEmojiStatusPermission toggles bot emoji status permission.
func (t *TelegramCore) BotsToggleUserEmojiStatusPermission(request *tg.BotsToggleUserEmojiStatusPermissionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsToggleUserEmojiStatusPermission(t.ctx, request)
}

// BotsToggleUsername activates or deactivates a bot username.
func (t *TelegramCore) BotsToggleUsername(request *tg.BotsToggleUsernameRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsToggleUsername(t.ctx, request)
}

// BotsUpdateStarRefProgram updates a bot's star referral program.
func (t *TelegramCore) BotsUpdateStarRefProgram(request *tg.BotsUpdateStarRefProgramRequest) (*tg.StarRefProgram, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.BotsUpdateStarRefProgram(t.ctx, request)
}

// BotsUpdateUserEmojiStatus sets a user's emoji status via a bot.
func (t *TelegramCore) BotsUpdateUserEmojiStatus(request *tg.BotsUpdateUserEmojiStatusRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.BotsUpdateUserEmojiStatus(t.ctx, request)
}

// --- Channels (28 methods) ---

// ChannelsCheckSearchPostsFlood checks whether the user is rate-limited for channel post searches.
func (t *TelegramCore) ChannelsCheckSearchPostsFlood(request *tg.ChannelsCheckSearchPostsFloodRequest) (*tg.SearchPostsFlood, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsCheckSearchPostsFlood(t.ctx, request)
}

// ChannelsCheckUsername checks if a username is available for a channel.
func (t *TelegramCore) ChannelsCheckUsername(request *tg.ChannelsCheckUsernameRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsCheckUsername(t.ctx, request)
}

// ChannelsConvertToGigagroup converts a supergroup to a broadcast group.
func (t *TelegramCore) ChannelsConvertToGigagroup(channel tg.InputChannelClass) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsConvertToGigagroup(t.ctx, channel)
}

// ChannelsDeactivateAllUsernames deactivates all channel usernames.
func (t *TelegramCore) ChannelsDeactivateAllUsernames(channel tg.InputChannelClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsDeactivateAllUsernames(t.ctx, channel)
}

// ChannelsDeleteHistory deletes channel history up to a given message.
func (t *TelegramCore) ChannelsDeleteHistory(request *tg.ChannelsDeleteHistoryRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsDeleteHistory(t.ctx, request)
}

// ChannelsDeleteParticipantHistory deletes all messages from a participant.
func (t *TelegramCore) ChannelsDeleteParticipantHistory(request *tg.ChannelsDeleteParticipantHistoryRequest) (*tg.MessagesAffectedHistory, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsDeleteParticipantHistory(t.ctx, request)
}

// ChannelsEditLocation sets or clears the geographic location of a channel.
func (t *TelegramCore) ChannelsEditLocation(request *tg.ChannelsEditLocationRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsEditLocation(t.ctx, request)
}

// ChannelsGetAdminedPublicChannels returns public channels where the user is admin.
func (t *TelegramCore) ChannelsGetAdminedPublicChannels(request *tg.ChannelsGetAdminedPublicChannelsRequest) (tg.MessagesChatsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetAdminedPublicChannels(t.ctx, request)
}

// ChannelsGetChannelRecommendations returns recommended similar channels.
func (t *TelegramCore) ChannelsGetChannelRecommendations(request *tg.ChannelsGetChannelRecommendationsRequest) (tg.MessagesChatsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetChannelRecommendations(t.ctx, request)
}

// ChannelsGetGroupsForDiscussion returns groups available as discussion groups.
func (t *TelegramCore) ChannelsGetGroupsForDiscussion() (tg.MessagesChatsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetGroupsForDiscussion(t.ctx)
}

// ChannelsGetInactiveChannels returns inactive channels and supergroups.
func (t *TelegramCore) ChannelsGetInactiveChannels() (*tg.MessagesInactiveChats, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetInactiveChannels(t.ctx)
}

// ChannelsGetLeftChannels returns channels the user has left.
func (t *TelegramCore) ChannelsGetLeftChannels(offset int) (tg.MessagesChatsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetLeftChannels(t.ctx, offset)
}

// ChannelsGetMessageAuthor returns the author of an anonymous channel message.
func (t *TelegramCore) ChannelsGetMessageAuthor(request *tg.ChannelsGetMessageAuthorRequest) (tg.UserClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetMessageAuthor(t.ctx, request)
}

// ChannelsGetMessages returns channel messages by their IDs.
func (t *TelegramCore) ChannelsGetMessages(request *tg.ChannelsGetMessagesRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsGetMessages(t.ctx, request)
}

// ChannelsReadMessageContents marks channel message contents as read.
func (t *TelegramCore) ChannelsReadMessageContents(request *tg.ChannelsReadMessageContentsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsReadMessageContents(t.ctx, request)
}

// ChannelsReorderUsernames reorders a channel's usernames.
func (t *TelegramCore) ChannelsReorderUsernames(request *tg.ChannelsReorderUsernamesRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsReorderUsernames(t.ctx, request)
}

// ChannelsReportAntiSpamFalsePositive reports a false positive in anti-spam.
func (t *TelegramCore) ChannelsReportAntiSpamFalsePositive(request *tg.ChannelsReportAntiSpamFalsePositiveRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsReportAntiSpamFalsePositive(t.ctx, request)
}

// ChannelsReportSpam reports spam messages in a channel.
func (t *TelegramCore) ChannelsReportSpam(request *tg.ChannelsReportSpamRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsReportSpam(t.ctx, request)
}

// ChannelsRestrictSponsoredMessages restricts sponsored messages.
func (t *TelegramCore) ChannelsRestrictSponsoredMessages(request *tg.ChannelsRestrictSponsoredMessagesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsRestrictSponsoredMessages(t.ctx, request)
}

// ChannelsSearchPosts searches for public channel posts.
func (t *TelegramCore) ChannelsSearchPosts(request *tg.ChannelsSearchPostsRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsSearchPosts(t.ctx, request)
}

// ChannelsSetBoostsToUnblockRestrictions sets the boost level to lift restrictions.
func (t *TelegramCore) ChannelsSetBoostsToUnblockRestrictions(request *tg.ChannelsSetBoostsToUnblockRestrictionsRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsSetBoostsToUnblockRestrictions(t.ctx, request)
}

// ChannelsSetDiscussionGroup links a discussion group to a channel.
func (t *TelegramCore) ChannelsSetDiscussionGroup(request *tg.ChannelsSetDiscussionGroupRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsSetDiscussionGroup(t.ctx, request)
}

// ChannelsSetEmojiStickers sets the custom emoji sticker set.
func (t *TelegramCore) ChannelsSetEmojiStickers(request *tg.ChannelsSetEmojiStickersRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsSetEmojiStickers(t.ctx, request)
}

// ChannelsSetMainProfileTab sets the default profile tab for a channel.
func (t *TelegramCore) ChannelsSetMainProfileTab(request *tg.ChannelsSetMainProfileTabRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsSetMainProfileTab(t.ctx, request)
}

// ChannelsSetStickers sets the sticker set for a supergroup.
func (t *TelegramCore) ChannelsSetStickers(request *tg.ChannelsSetStickersRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsSetStickers(t.ctx, request)
}

// ChannelsToggleUsername activates or deactivates a channel username.
func (t *TelegramCore) ChannelsToggleUsername(request *tg.ChannelsToggleUsernameRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChannelsToggleUsername(t.ctx, request)
}

// ChannelsUpdateEmojiStatus sets or clears a channel's emoji status.
func (t *TelegramCore) ChannelsUpdateEmojiStatus(request *tg.ChannelsUpdateEmojiStatusRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsUpdateEmojiStatus(t.ctx, request)
}

// ChannelsUpdatePaidMessagesPrice sets the price for paid messages.
func (t *TelegramCore) ChannelsUpdatePaidMessagesPrice(request *tg.ChannelsUpdatePaidMessagesPriceRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChannelsUpdatePaidMessagesPrice(t.ctx, request)
}

// --- Chatlists (7 methods) ---

// ChatlistsCheckChatlistInvite validates a chat folder invite link by its slug.
func (t *TelegramCore) ChatlistsCheckChatlistInvite(slug string) (tg.ChatlistsChatlistInviteClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChatlistsCheckChatlistInvite(t.ctx, slug)
}

// ChatlistsEditExportedInvite modifies a chat folder invite link.
func (t *TelegramCore) ChatlistsEditExportedInvite(request *tg.ChatlistsEditExportedInviteRequest) (*tg.ExportedChatlistInvite, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChatlistsEditExportedInvite(t.ctx, request)
}

// ChatlistsGetChatlistUpdates returns new chats in a shared folder.
func (t *TelegramCore) ChatlistsGetChatlistUpdates(chatlist tg.InputChatlistDialogFilter) (*tg.ChatlistsChatlistUpdates, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChatlistsGetChatlistUpdates(t.ctx, chatlist)
}

// ChatlistsGetLeaveChatlistSuggestions returns chats to remove when leaving a folder.
func (t *TelegramCore) ChatlistsGetLeaveChatlistSuggestions(chatlist tg.InputChatlistDialogFilter) ([]tg.PeerClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChatlistsGetLeaveChatlistSuggestions(t.ctx, chatlist)
}

// ChatlistsHideChatlistUpdates hides shared folder update notifications.
func (t *TelegramCore) ChatlistsHideChatlistUpdates(chatlist tg.InputChatlistDialogFilter) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ChatlistsHideChatlistUpdates(t.ctx, chatlist)
}

// ChatlistsJoinChatlistUpdates adds new chats from a shared folder.
func (t *TelegramCore) ChatlistsJoinChatlistUpdates(request *tg.ChatlistsJoinChatlistUpdatesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChatlistsJoinChatlistUpdates(t.ctx, request)
}

// ChatlistsLeaveChatlist leaves a shared chat folder.
func (t *TelegramCore) ChatlistsLeaveChatlist(request *tg.ChatlistsLeaveChatlistRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ChatlistsLeaveChatlist(t.ctx, request)
}

// --- Contacts (14 methods) ---

// ContactsAcceptContact accepts a pending contact request from a user.
func (t *TelegramCore) ContactsAcceptContact(id tg.InputUserClass) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsAcceptContact(t.ctx, id)
}

// ContactsBlockFromReplies blocks a user and deletes their reply messages.
func (t *TelegramCore) ContactsBlockFromReplies(request *tg.ContactsBlockFromRepliesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsBlockFromReplies(t.ctx, request)
}

// ContactsDeleteByPhones removes contacts by phone numbers.
func (t *TelegramCore) ContactsDeleteByPhones(phones []string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ContactsDeleteByPhones(t.ctx, phones)
}

// ContactsExportContactToken generates a token for adding the user as a contact.
func (t *TelegramCore) ContactsExportContactToken() (*tg.ExportedContactToken, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsExportContactToken(t.ctx)
}

// ContactsGetLocated returns users and groups near a location.
func (t *TelegramCore) ContactsGetLocated(request *tg.ContactsGetLocatedRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsGetLocated(t.ctx, request)
}

// ContactsGetSaved returns all saved contacts.
func (t *TelegramCore) ContactsGetSaved() ([]tg.SavedPhoneContact, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsGetSaved(t.ctx)
}

// ContactsGetSponsoredPeers returns sponsored peers from contacts.
func (t *TelegramCore) ContactsGetSponsoredPeers(q string) (tg.ContactsSponsoredPeersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsGetSponsoredPeers(t.ctx, q)
}

// ContactsGetStatuses returns the online status of all contacts.
func (t *TelegramCore) ContactsGetStatuses() ([]tg.ContactStatus, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsGetStatuses(t.ctx)
}

// ContactsImportContactToken adds a user via their contact token.
func (t *TelegramCore) ContactsImportContactToken(token string) (tg.UserClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.ContactsImportContactToken(t.ctx, token)
}

// ContactsResetSaved deletes all saved contacts from the server.
func (t *TelegramCore) ContactsResetSaved() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ContactsResetSaved(t.ctx)
}

// ContactsResetTopPeerRating resets a top peer's rating.
func (t *TelegramCore) ContactsResetTopPeerRating(request *tg.ContactsResetTopPeerRatingRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ContactsResetTopPeerRating(t.ctx, request)
}

// ContactsSetBlocked replaces the entire blocked user list.
func (t *TelegramCore) ContactsSetBlocked(request *tg.ContactsSetBlockedRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ContactsSetBlocked(t.ctx, request)
}

// ContactsToggleTopPeers enables or disables top peers suggestions.
func (t *TelegramCore) ContactsToggleTopPeers(enabled bool) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ContactsToggleTopPeers(t.ctx, enabled)
}

// ContactsUpdateContactNote sets a personal note for a contact.
func (t *TelegramCore) ContactsUpdateContactNote(request *tg.ContactsUpdateContactNoteRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.ContactsUpdateContactNote(t.ctx, request)
}

// --- Help (21 methods) ---

// HelpAcceptTermsOfService confirms acceptance of the Telegram Terms of Service.
func (t *TelegramCore) HelpAcceptTermsOfService(id tg.DataJSON) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.HelpAcceptTermsOfService(t.ctx, id)
}

// HelpDismissSuggestion dismisses a suggestion notification.
func (t *TelegramCore) HelpDismissSuggestion(request *tg.HelpDismissSuggestionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.HelpDismissSuggestion(t.ctx, request)
}

// HelpEditUserInfo edits support info for a user (support agents only).
func (t *TelegramCore) HelpEditUserInfo(request *tg.HelpEditUserInfoRequest) (tg.HelpUserInfoClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpEditUserInfo(t.ctx, request)
}

// HelpGetAppUpdate checks for available app updates.
func (t *TelegramCore) HelpGetAppUpdate(source string) (tg.HelpAppUpdateClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetAppUpdate(t.ctx, source)
}

// HelpGetCDNConfig returns the CDN configuration.
func (t *TelegramCore) HelpGetCDNConfig() (*tg.CDNConfig, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetCDNConfig(t.ctx)
}

// HelpGetDeepLinkInfo returns info about a deep link.
func (t *TelegramCore) HelpGetDeepLinkInfo(path string) (tg.HelpDeepLinkInfoClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetDeepLinkInfo(t.ctx, path)
}

// HelpGetInviteText returns the localized invite text.
func (t *TelegramCore) HelpGetInviteText() (*tg.HelpInviteText, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetInviteText(t.ctx)
}

// HelpGetPassportConfig returns the Passport country configuration.
func (t *TelegramCore) HelpGetPassportConfig(hash int) (tg.HelpPassportConfigClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetPassportConfig(t.ctx, hash)
}

// HelpGetPeerColors returns available name and reply accent colors.
func (t *TelegramCore) HelpGetPeerColors(hash int) (tg.HelpPeerColorsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetPeerColors(t.ctx, hash)
}

// PeerColorEntry is a parsed peer color entry for the UI.
type PeerColorEntry struct {
	ColorID     int   `json:"color_id"`
	DayColors   []int `json:"day_colors"`
	NightColors []int `json:"night_colors"`
	Hidden      bool  `json:"hidden"`
}

// GetPeerColorPalette fetches and parses help.peerColors into a simple list.
func (t *TelegramCore) GetPeerColorPalette() ([]PeerColorEntry, error) {
	result, err := t.HelpGetPeerColors(0)
	if err != nil {
		return nil, err
	}
	colors, ok := result.(*tg.HelpPeerColors)
	if !ok {
		return nil, nil // NotModified or unexpected type
	}
	entries := make([]PeerColorEntry, 0, len(colors.Colors))
	for _, opt := range colors.Colors {
		entry := PeerColorEntry{
			ColorID: opt.ColorID,
			Hidden:  opt.Hidden,
		}
		if cs, ok := opt.GetColors(); ok {
			if set, ok := cs.(*tg.HelpPeerColorSet); ok {
				entry.DayColors = set.Colors
			}
		}
		if cs, ok := opt.GetDarkColors(); ok {
			if set, ok := cs.(*tg.HelpPeerColorSet); ok {
				entry.NightColors = set.Colors
			}
		}
		entries = append(entries, entry)
	}
	return entries, nil
}

// HelpGetPeerProfileColors returns available profile accent colors.
func (t *TelegramCore) HelpGetPeerProfileColors(hash int) (tg.HelpPeerColorsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetPeerProfileColors(t.ctx, hash)
}

// HelpGetPremiumPromo returns Premium promotional info.
func (t *TelegramCore) HelpGetPremiumPromo() (*tg.HelpPremiumPromo, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetPremiumPromo(t.ctx)
}

// HelpGetPromoData returns current promotional data.
func (t *TelegramCore) HelpGetPromoData() (tg.HelpPromoDataClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetPromoData(t.ctx)
}

// HelpGetRecentMeURLs returns recently used t.me links.
func (t *TelegramCore) HelpGetRecentMeURLs(referer string) (*tg.HelpRecentMeURLs, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetRecentMeURLs(t.ctx, referer)
}

// HelpGetSupport returns the support user.
func (t *TelegramCore) HelpGetSupport() (*tg.HelpSupport, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetSupport(t.ctx)
}

// HelpGetSupportName returns the support account name.
func (t *TelegramCore) HelpGetSupportName() (*tg.HelpSupportName, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetSupportName(t.ctx)
}

// HelpGetTermsOfServiceUpdate checks for terms of service updates.
func (t *TelegramCore) HelpGetTermsOfServiceUpdate() (tg.HelpTermsOfServiceUpdateClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetTermsOfServiceUpdate(t.ctx)
}

// HelpGetTimezonesList returns supported timezones.
func (t *TelegramCore) HelpGetTimezonesList(hash int) (tg.HelpTimezonesListClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetTimezonesList(t.ctx, hash)
}

// HelpGetUserInfo returns support info about a user.
func (t *TelegramCore) HelpGetUserInfo(userid tg.InputUserClass) (tg.HelpUserInfoClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.HelpGetUserInfo(t.ctx, userid)
}

// HelpHidePromoData hides current promotional data.
func (t *TelegramCore) HelpHidePromoData(peer tg.InputPeerClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.HelpHidePromoData(t.ctx, peer)
}

// HelpSaveAppLog saves app event logs to the server.
func (t *TelegramCore) HelpSaveAppLog(events []tg.InputAppEvent) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.HelpSaveAppLog(t.ctx, events)
}

// HelpSetBotUpdatesStatus reports bot update processing status.
func (t *TelegramCore) HelpSetBotUpdatesStatus(request *tg.HelpSetBotUpdatesStatusRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.HelpSetBotUpdatesStatus(t.ctx, request)
}

// --- Invoke (2 methods) ---

// InvokeJSON sends a raw JSON-encoded Telegram API request and returns the JSON response.
func (t *TelegramCore) InvokeJSON(jsonData string, useSnakeCase bool) (string, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return "", ErrAuth }
	return t.api.InvokeJSON(t.ctx, jsonData, useSnakeCase)
}

// SKIP: Invoker

// --- Langpack (5 methods) ---

// LangpackGetDifference fetches language pack string updates since a given version.
func (t *TelegramCore) LangpackGetDifference(request *tg.LangpackGetDifferenceRequest) (*tg.LangPackDifference, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.LangpackGetDifference(t.ctx, request)
}

// LangpackGetLangPack returns the full localization pack for a language.
func (t *TelegramCore) LangpackGetLangPack(request *tg.LangpackGetLangPackRequest) (*tg.LangPackDifference, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.LangpackGetLangPack(t.ctx, request)
}

// LangpackGetLanguage returns info about a specific language.
func (t *TelegramCore) LangpackGetLanguage(request *tg.LangpackGetLanguageRequest) (*tg.LangPackLanguage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.LangpackGetLanguage(t.ctx, request)
}

// LangpackGetLanguages returns available languages.
func (t *TelegramCore) LangpackGetLanguages(langpack string) ([]tg.LangPackLanguage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.LangpackGetLanguages(t.ctx, langpack)
}

// LangpackGetStrings returns specific localization strings by key.
func (t *TelegramCore) LangpackGetStrings(request *tg.LangpackGetStringsRequest) ([]tg.LangPackStringClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.LangpackGetStrings(t.ctx, request)
}

// --- Messages (165 methods) ---

// MessagesAcceptEncryption accepts an incoming secret chat encryption request.
func (t *TelegramCore) MessagesAcceptEncryption(request *tg.MessagesAcceptEncryptionRequest) (tg.EncryptedChatClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesAcceptEncryption(t.ctx, request)
}

// MessagesAcceptURLAuth authorizes a URL authentication request.
func (t *TelegramCore) MessagesAcceptURLAuth(request *tg.MessagesAcceptURLAuthRequest) (tg.URLAuthResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesAcceptURLAuth(t.ctx, request)
}

// MessagesAddPollAnswer adds a vote to a poll.
func (t *TelegramCore) MessagesAddPollAnswer(request *tg.MessagesAddPollAnswerRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesAddPollAnswer(t.ctx, request)
}

// MessagesAppendTodoList appends items to a to-do list message.
func (t *TelegramCore) MessagesAppendTodoList(request *tg.MessagesAppendTodoListRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesAppendTodoList(t.ctx, request)
}

// MessagesCheckHistoryImport validates a chat history export file.
func (t *TelegramCore) MessagesCheckHistoryImport(importhead string) (*tg.MessagesHistoryImportParsed, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesCheckHistoryImport(t.ctx, importhead)
}

// MessagesCheckHistoryImportPeer checks if history import is allowed for a peer.
func (t *TelegramCore) MessagesCheckHistoryImportPeer(peer tg.InputPeerClass) (*tg.MessagesCheckedHistoryImportPeer, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesCheckHistoryImportPeer(t.ctx, peer)
}

// MessagesCheckQuickReplyShortcut checks if a shortcut name is valid.
func (t *TelegramCore) MessagesCheckQuickReplyShortcut(shortcut string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesCheckQuickReplyShortcut(t.ctx, shortcut)
}

// MessagesCheckURLAuthMatchCode validates a URL authentication match code.
func (t *TelegramCore) MessagesCheckURLAuthMatchCode(request *tg.MessagesCheckURLAuthMatchCodeRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesCheckURLAuthMatchCode(t.ctx, request)
}

// MessagesClearAllDrafts deletes all message drafts.
func (t *TelegramCore) MessagesClearAllDrafts() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesClearAllDrafts(t.ctx)
}

// MessagesClearRecentReactions clears recently used reactions.
func (t *TelegramCore) MessagesClearRecentReactions() (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesClearRecentReactions(t.ctx)
}

// MessagesClearRecentStickers clears recently used stickers.
func (t *TelegramCore) MessagesClearRecentStickers(request *tg.MessagesClearRecentStickersRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesClearRecentStickers(t.ctx, request)
}

// MessagesClickSponsoredMessage reports a click on a sponsored message.
func (t *TelegramCore) MessagesClickSponsoredMessage(request *tg.MessagesClickSponsoredMessageRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesClickSponsoredMessage(t.ctx, request)
}

// MessagesComposeMessageWithAI generates a message using Telegram's AI.
func (t *TelegramCore) MessagesComposeMessageWithAI(request *tg.MessagesComposeMessageWithAIRequest) (*tg.MessagesComposedMessageWithAI, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesComposeMessageWithAI(t.ctx, request)
}

// MessagesDeclineURLAuth declines a URL authentication request.
func (t *TelegramCore) MessagesDeclineURLAuth(url string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesDeclineURLAuth(t.ctx, url)
}

// MessagesDeleteChat deletes a basic group chat.
func (t *TelegramCore) MessagesDeleteChat(chatid int64) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesDeleteChat(t.ctx, chatid)
}

// MessagesDeleteFactCheck removes a fact-check label from a message.
func (t *TelegramCore) MessagesDeleteFactCheck(request *tg.MessagesDeleteFactCheckRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesDeleteFactCheck(t.ctx, request)
}

// MessagesDeletePhoneCallHistory deletes the phone call history.
func (t *TelegramCore) MessagesDeletePhoneCallHistory(request *tg.MessagesDeletePhoneCallHistoryRequest) (*tg.MessagesAffectedFoundMessages, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesDeletePhoneCallHistory(t.ctx, request)
}

// MessagesDeletePollAnswer removes a vote from a poll.
func (t *TelegramCore) MessagesDeletePollAnswer(request *tg.MessagesDeletePollAnswerRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesDeletePollAnswer(t.ctx, request)
}

// MessagesDeleteQuickReplyMessages deletes messages from a quick reply shortcut.
func (t *TelegramCore) MessagesDeleteQuickReplyMessages(request *tg.MessagesDeleteQuickReplyMessagesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesDeleteQuickReplyMessages(t.ctx, request)
}

// MessagesDeleteQuickReplyShortcut deletes a quick reply shortcut.
func (t *TelegramCore) MessagesDeleteQuickReplyShortcut(shortcutid int) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesDeleteQuickReplyShortcut(t.ctx, shortcutid)
}

// MessagesDeleteRevokedExportedChatInvites deletes all revoked invite links by an admin.
func (t *TelegramCore) MessagesDeleteRevokedExportedChatInvites(request *tg.MessagesDeleteRevokedExportedChatInvitesRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesDeleteRevokedExportedChatInvites(t.ctx, request)
}

// MessagesDeleteSavedHistory deletes saved messages for a peer.
func (t *TelegramCore) MessagesDeleteSavedHistory(request *tg.MessagesDeleteSavedHistoryRequest) (*tg.MessagesAffectedHistory, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesDeleteSavedHistory(t.ctx, request)
}

// MessagesDiscardEncryption discards a secret chat.
func (t *TelegramCore) MessagesDiscardEncryption(request *tg.MessagesDiscardEncryptionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesDiscardEncryption(t.ctx, request)
}

// MessagesEditChatAbout changes a chat's description.
func (t *TelegramCore) MessagesEditChatAbout(request *tg.MessagesEditChatAboutRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesEditChatAbout(t.ctx, request)
}

// MessagesEditChatAdmin promotes or demotes a user in a basic group.
func (t *TelegramCore) MessagesEditChatAdmin(request *tg.MessagesEditChatAdminRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesEditChatAdmin(t.ctx, request)
}

// MessagesEditChatCreator transfers basic group ownership.
func (t *TelegramCore) MessagesEditChatCreator(request *tg.MessagesEditChatCreatorRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesEditChatCreator(t.ctx, request)
}

// MessagesEditChatParticipantRank sets a custom admin title.
func (t *TelegramCore) MessagesEditChatParticipantRank(request *tg.MessagesEditChatParticipantRankRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesEditChatParticipantRank(t.ctx, request)
}

// MessagesEditChatPhoto changes a basic group's photo.
func (t *TelegramCore) MessagesEditChatPhoto(request *tg.MessagesEditChatPhotoRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesEditChatPhoto(t.ctx, request)
}

// MessagesEditChatTitle changes a basic group's title.
func (t *TelegramCore) MessagesEditChatTitle(request *tg.MessagesEditChatTitleRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesEditChatTitle(t.ctx, request)
}

// MessagesEditFactCheck adds or modifies a fact-check label on a message.
func (t *TelegramCore) MessagesEditFactCheck(request *tg.MessagesEditFactCheckRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesEditFactCheck(t.ctx, request)
}

// MessagesEditInlineBotMessage edits an inline bot message.
func (t *TelegramCore) MessagesEditInlineBotMessage(request *tg.MessagesEditInlineBotMessageRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesEditInlineBotMessage(t.ctx, request)
}

// MessagesEditQuickReplyShortcut renames a quick reply shortcut.
func (t *TelegramCore) MessagesEditQuickReplyShortcut(request *tg.MessagesEditQuickReplyShortcutRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesEditQuickReplyShortcut(t.ctx, request)
}

// MessagesGetAdminsWithInvites returns admins who created invite links.
func (t *TelegramCore) MessagesGetAdminsWithInvites(peer tg.InputPeerClass) (*tg.MessagesChatAdminsWithInvites, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetAdminsWithInvites(t.ctx, peer)
}

// MessagesGetArchivedStickers returns archived sticker sets.
func (t *TelegramCore) MessagesGetArchivedStickers(request *tg.MessagesGetArchivedStickersRequest) (*tg.MessagesArchivedStickers, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetArchivedStickers(t.ctx, request)
}

// MessagesGetAttachedStickers returns sticker sets attached to a media item.
func (t *TelegramCore) MessagesGetAttachedStickers(media tg.InputStickeredMediaClass) ([]tg.StickerSetCoveredClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetAttachedStickers(t.ctx, media)
}

// MessagesGetAttachMenuBot returns a bot's attachment menu entry.
func (t *TelegramCore) MessagesGetAttachMenuBot(bot tg.InputUserClass) (*tg.AttachMenuBotsBot, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetAttachMenuBot(t.ctx, bot)
}

// MessagesGetAttachMenuBots returns all bots with attachment menu entries.
func (t *TelegramCore) MessagesGetAttachMenuBots(hash int64) (tg.AttachMenuBotsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetAttachMenuBots(t.ctx, hash)
}

// MessagesGetAvailableEffects returns available message effects.
func (t *TelegramCore) MessagesGetAvailableEffects(hash int) (tg.MessagesAvailableEffectsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetAvailableEffects(t.ctx, hash)
}

// MessagesGetAvailableReactions returns all available emoji reactions.
func (t *TelegramCore) MessagesGetAvailableReactions(hash int) (tg.MessagesAvailableReactionsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetAvailableReactions(t.ctx, hash)
}

// MessagesGetBotApp returns information about a bot's mini app.
func (t *TelegramCore) MessagesGetBotApp(request *tg.MessagesGetBotAppRequest) (*tg.MessagesBotApp, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetBotApp(t.ctx, request)
}

// MessagesGetChats returns chat info for the specified chat IDs.
func (t *TelegramCore) MessagesGetChats(id []int64) (tg.MessagesChatsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetChats(t.ctx, id)
}

// MessagesGetCustomEmojiDocuments returns custom emoji documents by ID.
func (t *TelegramCore) MessagesGetCustomEmojiDocuments(documentid []int64) ([]tg.DocumentClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetCustomEmojiDocuments(t.ctx, documentid)
}

// MessagesGetDefaultTagReactions returns default reactions for saved tags.
func (t *TelegramCore) MessagesGetDefaultTagReactions(hash int64) (tg.MessagesReactionsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetDefaultTagReactions(t.ctx, hash)
}

// MessagesGetDiscussionMessage returns the discussion thread for a channel post.
func (t *TelegramCore) MessagesGetDiscussionMessage(request *tg.MessagesGetDiscussionMessageRequest) (*tg.MessagesDiscussionMessage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetDiscussionMessage(t.ctx, request)
}

// MessagesGetDocumentByHash finds a document by its SHA256 hash and size.
func (t *TelegramCore) MessagesGetDocumentByHash(request *tg.MessagesGetDocumentByHashRequest) (tg.DocumentClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetDocumentByHash(t.ctx, request)
}

// MessagesGetEmojiGameInfo returns info about an emoji-based game.
func (t *TelegramCore) MessagesGetEmojiGameInfo() (tg.MessagesEmojiGameInfoClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiGameInfo(t.ctx)
}

// MessagesGetEmojiGroups returns categorized emoji groups.
func (t *TelegramCore) MessagesGetEmojiGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiGroups(t.ctx, hash)
}

// MessagesGetEmojiKeywords returns emoji search keywords for a language.
func (t *TelegramCore) MessagesGetEmojiKeywords(langcode string) (*tg.EmojiKeywordsDifference, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiKeywords(t.ctx, langcode)
}

// MessagesGetEmojiKeywordsDifference returns updated emoji keywords since a version.
func (t *TelegramCore) MessagesGetEmojiKeywordsDifference(request *tg.MessagesGetEmojiKeywordsDifferenceRequest) (*tg.EmojiKeywordsDifference, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiKeywordsDifference(t.ctx, request)
}

// MessagesGetEmojiKeywordsLanguages returns available languages for emoji keywords.
func (t *TelegramCore) MessagesGetEmojiKeywordsLanguages(langcodes []string) ([]tg.EmojiLanguage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiKeywordsLanguages(t.ctx, langcodes)
}

// MessagesGetEmojiProfilePhotoGroups returns emoji groups for profile photos.
func (t *TelegramCore) MessagesGetEmojiProfilePhotoGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiProfilePhotoGroups(t.ctx, hash)
}

// MessagesGetEmojiStatusGroups returns emoji groups for status selection.
func (t *TelegramCore) MessagesGetEmojiStatusGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiStatusGroups(t.ctx, hash)
}

// MessagesGetEmojiStickerGroups returns emoji groups for sticker browsing.
func (t *TelegramCore) MessagesGetEmojiStickerGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiStickerGroups(t.ctx, hash)
}

// MessagesGetEmojiStickers returns custom emoji sticker sets.
func (t *TelegramCore) MessagesGetEmojiStickers(hash int64) (tg.MessagesAllStickersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiStickers(t.ctx, hash)
}

// MessagesGetEmojiURL returns the URL for emoji suggestions for a language.
func (t *TelegramCore) MessagesGetEmojiURL(langcode string) (*tg.EmojiURL, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetEmojiURL(t.ctx, langcode)
}

// MessagesGetExportedChatInvite returns info about an exported invite link.
func (t *TelegramCore) MessagesGetExportedChatInvite(request *tg.MessagesGetExportedChatInviteRequest) (tg.MessagesExportedChatInviteClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetExportedChatInvite(t.ctx, request)
}

// MessagesGetExportedChatInvites returns all exported invite links for a chat.
func (t *TelegramCore) MessagesGetExportedChatInvites(request *tg.MessagesGetExportedChatInvitesRequest) (*tg.MessagesExportedChatInvites, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetExportedChatInvites(t.ctx, request)
}

// MessagesGetExtendedMedia returns extended media info for messages.
func (t *TelegramCore) MessagesGetExtendedMedia(request *tg.MessagesGetExtendedMediaRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetExtendedMedia(t.ctx, request)
}

// MessagesGetFactCheck returns fact-check labels on messages.
func (t *TelegramCore) MessagesGetFactCheck(request *tg.MessagesGetFactCheckRequest) ([]tg.FactCheck, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetFactCheck(t.ctx, request)
}

// MessagesGetFeaturedEmojiStickers returns featured custom emoji sticker sets.
func (t *TelegramCore) MessagesGetFeaturedEmojiStickers(hash int64) (tg.MessagesFeaturedStickersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetFeaturedEmojiStickers(t.ctx, hash)
}

// MessagesGetForumTopicsByID returns forum topics by their IDs.
func (t *TelegramCore) MessagesGetForumTopicsByID(request *tg.MessagesGetForumTopicsByIDRequest) (*tg.MessagesForumTopics, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetForumTopicsByID(t.ctx, request)
}

// MessagesGetFutureChatCreatorAfterLeave checks who becomes creator if current one leaves.
func (t *TelegramCore) MessagesGetFutureChatCreatorAfterLeave(peer tg.InputPeerClass) (tg.UserClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetFutureChatCreatorAfterLeave(t.ctx, peer)
}

// MessagesGetGameHighScores returns the high score table for a game.
func (t *TelegramCore) MessagesGetGameHighScores(request *tg.MessagesGetGameHighScoresRequest) (*tg.MessagesHighScores, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetGameHighScores(t.ctx, request)
}

// MessagesGetInlineGameHighScores returns game high scores for an inline message.
func (t *TelegramCore) MessagesGetInlineGameHighScores(request *tg.MessagesGetInlineGameHighScoresRequest) (*tg.MessagesHighScores, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetInlineGameHighScores(t.ctx, request)
}

// MessagesGetMaskStickers returns mask sticker sets.
func (t *TelegramCore) MessagesGetMaskStickers(hash int64) (tg.MessagesAllStickersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetMaskStickers(t.ctx, hash)
}

// MessagesGetMessageEditData checks if a message can be edited.
func (t *TelegramCore) MessagesGetMessageEditData(request *tg.MessagesGetMessageEditDataRequest) (*tg.MessagesMessageEditData, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetMessageEditData(t.ctx, request)
}

// MessagesGetMessages returns messages by their IDs.
func (t *TelegramCore) MessagesGetMessages(id []tg.InputMessageClass) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetMessages(t.ctx, id)
}

// MessagesGetMessagesReactions returns reactions on specified messages.
func (t *TelegramCore) MessagesGetMessagesReactions(request *tg.MessagesGetMessagesReactionsRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetMessagesReactions(t.ctx, request)
}

// MessagesGetMyStickers returns sticker sets owned by the user.
func (t *TelegramCore) MessagesGetMyStickers(request *tg.MessagesGetMyStickersRequest) (*tg.MessagesMyStickers, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetMyStickers(t.ctx, request)
}

// MessagesGetOldFeaturedStickers returns previously featured sticker sets.
func (t *TelegramCore) MessagesGetOldFeaturedStickers(request *tg.MessagesGetOldFeaturedStickersRequest) (tg.MessagesFeaturedStickersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetOldFeaturedStickers(t.ctx, request)
}

// MessagesGetPaidReactionPrivacy returns paid reaction privacy settings.
func (t *TelegramCore) MessagesGetPaidReactionPrivacy() (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetPaidReactionPrivacy(t.ctx)
}

// MessagesGetPeerDialogs returns dialog info for specific peers.
func (t *TelegramCore) MessagesGetPeerDialogs(peers []tg.InputDialogPeerClass) (*tg.MessagesPeerDialogs, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetPeerDialogs(t.ctx, peers)
}

// MessagesGetPinnedSavedDialogs returns pinned saved message dialogs.
func (t *TelegramCore) MessagesGetPinnedSavedDialogs() (tg.MessagesSavedDialogsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetPinnedSavedDialogs(t.ctx)
}

// MessagesGetPreparedInlineMessage returns a prepared inline message.
func (t *TelegramCore) MessagesGetPreparedInlineMessage(request *tg.MessagesGetPreparedInlineMessageRequest) (*tg.MessagesPreparedInlineMessage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetPreparedInlineMessage(t.ctx, request)
}

// MessagesGetQuickReplies returns quick reply shortcuts.
func (t *TelegramCore) MessagesGetQuickReplies(hash int64) (tg.MessagesQuickRepliesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetQuickReplies(t.ctx, hash)
}

// MessagesGetQuickReplyMessages returns messages in a quick reply shortcut.
func (t *TelegramCore) MessagesGetQuickReplyMessages(request *tg.MessagesGetQuickReplyMessagesRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetQuickReplyMessages(t.ctx, request)
}

// MessagesGetRecentLocations returns recently shared live locations.
func (t *TelegramCore) MessagesGetRecentLocations(request *tg.MessagesGetRecentLocationsRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetRecentLocations(t.ctx, request)
}

// MessagesGetRecentReactions returns recently used reactions.
func (t *TelegramCore) MessagesGetRecentReactions(request *tg.MessagesGetRecentReactionsRequest) (tg.MessagesReactionsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetRecentReactions(t.ctx, request)
}

// MessagesGetReplies returns reply thread messages for a message.
func (t *TelegramCore) MessagesGetReplies(request *tg.MessagesGetRepliesRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetReplies(t.ctx, request)
}

// MessagesGetSavedDialogs returns saved message dialogs.
func (t *TelegramCore) MessagesGetSavedDialogs(request *tg.MessagesGetSavedDialogsRequest) (tg.MessagesSavedDialogsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSavedDialogs(t.ctx, request)
}

// MessagesGetSavedDialogsByID returns saved dialogs by their peer IDs.
func (t *TelegramCore) MessagesGetSavedDialogsByID(request *tg.MessagesGetSavedDialogsByIDRequest) (tg.MessagesSavedDialogsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSavedDialogsByID(t.ctx, request)
}

// MessagesGetSavedGifs returns saved GIF animations.
func (t *TelegramCore) MessagesGetSavedGifs(hash int64) (tg.MessagesSavedGifsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSavedGifs(t.ctx, hash)
}

// MessagesGetSavedHistory returns saved messages for a specific peer.
func (t *TelegramCore) MessagesGetSavedHistory(request *tg.MessagesGetSavedHistoryRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSavedHistory(t.ctx, request)
}

// MessagesGetSavedReactionTags returns saved reaction tag labels.
func (t *TelegramCore) MessagesGetSavedReactionTags(request *tg.MessagesGetSavedReactionTagsRequest) (tg.MessagesSavedReactionTagsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSavedReactionTags(t.ctx, request)
}

// MessagesGetScheduledMessages returns scheduled messages in a chat.
func (t *TelegramCore) MessagesGetScheduledMessages(request *tg.MessagesGetScheduledMessagesRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetScheduledMessages(t.ctx, request)
}

// MessagesGetSearchResultsPositions returns positions of search results.
func (t *TelegramCore) MessagesGetSearchResultsPositions(request *tg.MessagesGetSearchResultsPositionsRequest) (*tg.MessagesSearchResultsPositions, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSearchResultsPositions(t.ctx, request)
}

// MessagesGetSplitRanges returns date ranges for message history split by DC.
func (t *TelegramCore) MessagesGetSplitRanges() ([]tg.MessageRange, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSplitRanges(t.ctx)
}

// MessagesGetSponsoredMessages returns sponsored messages for a channel.
func (t *TelegramCore) MessagesGetSponsoredMessages(request *tg.MessagesGetSponsoredMessagesRequest) (tg.MessagesSponsoredMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetSponsoredMessages(t.ctx, request)
}

// MessagesGetStickers returns stickers matching an emoji.
func (t *TelegramCore) MessagesGetStickers(request *tg.MessagesGetStickersRequest) (tg.MessagesStickersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetStickers(t.ctx, request)
}

// MessagesGetTopReactions returns the most used reactions.
func (t *TelegramCore) MessagesGetTopReactions(request *tg.MessagesGetTopReactionsRequest) (tg.MessagesReactionsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetTopReactions(t.ctx, request)
}

// MessagesGetUnreadPollVotes returns unread poll votes in a chat.
func (t *TelegramCore) MessagesGetUnreadPollVotes(request *tg.MessagesGetUnreadPollVotesRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetUnreadPollVotes(t.ctx, request)
}

// MessagesGetWebPage returns a web page preview by URL.
func (t *TelegramCore) MessagesGetWebPage(request *tg.MessagesGetWebPageRequest) (*tg.MessagesWebPage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesGetWebPage(t.ctx, request)
}

// MessagesHideAllChatJoinRequests approves or dismisses all join requests.
func (t *TelegramCore) MessagesHideAllChatJoinRequests(request *tg.MessagesHideAllChatJoinRequestsRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesHideAllChatJoinRequests(t.ctx, request)
}

// MessagesHidePeerSettingsBar hides the action bar in a chat.
func (t *TelegramCore) MessagesHidePeerSettingsBar(peer tg.InputPeerClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesHidePeerSettingsBar(t.ctx, peer)
}

// MessagesInitHistoryImport starts a chat history import.
func (t *TelegramCore) MessagesInitHistoryImport(request *tg.MessagesInitHistoryImportRequest) (*tg.MessagesHistoryImport, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesInitHistoryImport(t.ctx, request)
}

// MessagesInstallStickerSet adds a sticker set to the user's collection.
func (t *TelegramCore) MessagesInstallStickerSet(request *tg.MessagesInstallStickerSetRequest) (tg.MessagesStickerSetInstallResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesInstallStickerSet(t.ctx, request)
}

// MessagesProlongWebView extends an open web view session.
func (t *TelegramCore) MessagesProlongWebView(request *tg.MessagesProlongWebViewRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesProlongWebView(t.ctx, request)
}

// MessagesRateTranscribedAudio rates an audio transcription's quality.
func (t *TelegramCore) MessagesRateTranscribedAudio(request *tg.MessagesRateTranscribedAudioRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesRateTranscribedAudio(t.ctx, request)
}

// MessagesReadDiscussion marks discussion thread messages as read.
func (t *TelegramCore) MessagesReadDiscussion(request *tg.MessagesReadDiscussionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReadDiscussion(t.ctx, request)
}

// MessagesReadEncryptedHistory marks secret chat messages as read.
func (t *TelegramCore) MessagesReadEncryptedHistory(request *tg.MessagesReadEncryptedHistoryRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReadEncryptedHistory(t.ctx, request)
}

// MessagesReadFeaturedStickers marks featured sticker sets as seen.
func (t *TelegramCore) MessagesReadFeaturedStickers(id []int64) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReadFeaturedStickers(t.ctx, id)
}

// MessagesReadMessageContents marks message contents as read.
func (t *TelegramCore) MessagesReadMessageContents(id []int) (*tg.MessagesAffectedMessages, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesReadMessageContents(t.ctx, id)
}

// MessagesReadPollVotes marks poll votes as read.
func (t *TelegramCore) MessagesReadPollVotes(request *tg.MessagesReadPollVotesRequest) (*tg.MessagesAffectedHistory, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesReadPollVotes(t.ctx, request)
}

// MessagesReadSavedHistory marks saved messages as read.
func (t *TelegramCore) MessagesReadSavedHistory(request *tg.MessagesReadSavedHistoryRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReadSavedHistory(t.ctx, request)
}

// MessagesReceivedMessages confirms message delivery up to a given ID.
func (t *TelegramCore) MessagesReceivedMessages(maxid int) ([]tg.ReceivedNotifyMessage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesReceivedMessages(t.ctx, maxid)
}

// MessagesReceivedQueue confirms receipt of update queue messages.
func (t *TelegramCore) MessagesReceivedQueue(maxqts int) ([]int64, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesReceivedQueue(t.ctx, maxqts)
}

// MessagesReorderPinnedSavedDialogs reorders pinned saved dialogs.
func (t *TelegramCore) MessagesReorderPinnedSavedDialogs(request *tg.MessagesReorderPinnedSavedDialogsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReorderPinnedSavedDialogs(t.ctx, request)
}

// MessagesReorderQuickReplies reorders quick reply shortcuts.
func (t *TelegramCore) MessagesReorderQuickReplies(order []int) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReorderQuickReplies(t.ctx, order)
}

// MessagesReorderStickerSets reorders sticker sets.
func (t *TelegramCore) MessagesReorderStickerSets(request *tg.MessagesReorderStickerSetsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReorderStickerSets(t.ctx, request)
}

// MessagesReport reports messages for moderation.
func (t *TelegramCore) MessagesReport(request *tg.MessagesReportRequest) (tg.ReportResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesReport(t.ctx, request)
}

// MessagesReportEncryptedSpam reports a secret chat as spam.
func (t *TelegramCore) MessagesReportEncryptedSpam(peer tg.InputEncryptedChat) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReportEncryptedSpam(t.ctx, peer)
}

// MessagesReportMessagesDelivery reports message delivery status.
func (t *TelegramCore) MessagesReportMessagesDelivery(request *tg.MessagesReportMessagesDeliveryRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReportMessagesDelivery(t.ctx, request)
}

// MessagesReportMusicListen reports a music listening event.
func (t *TelegramCore) MessagesReportMusicListen(request *tg.MessagesReportMusicListenRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReportMusicListen(t.ctx, request)
}

// MessagesReportReaction reports an inappropriate reaction.
func (t *TelegramCore) MessagesReportReaction(request *tg.MessagesReportReactionRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReportReaction(t.ctx, request)
}

// MessagesReportReadMetrics reports message read metrics.
func (t *TelegramCore) MessagesReportReadMetrics(request *tg.MessagesReportReadMetricsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReportReadMetrics(t.ctx, request)
}

// MessagesReportSpam reports a peer as spam.
func (t *TelegramCore) MessagesReportSpam(peer tg.InputPeerClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesReportSpam(t.ctx, peer)
}

// MessagesReportSponsoredMessage reports a sponsored message.
func (t *TelegramCore) MessagesReportSponsoredMessage(request *tg.MessagesReportSponsoredMessageRequest) (tg.ChannelsSponsoredMessageReportResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesReportSponsoredMessage(t.ctx, request)
}

// MessagesRequestAppWebView opens a bot's mini app view.
func (t *TelegramCore) MessagesRequestAppWebView(request *tg.MessagesRequestAppWebViewRequest) (*tg.WebViewResultURL, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesRequestAppWebView(t.ctx, request)
}

// MessagesRequestEncryption initiates a secret chat with a user.
func (t *TelegramCore) MessagesRequestEncryption(request *tg.MessagesRequestEncryptionRequest) (tg.EncryptedChatClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesRequestEncryption(t.ctx, request)
}

// MessagesRequestMainWebView opens the main web view for a bot.
func (t *TelegramCore) MessagesRequestMainWebView(request *tg.MessagesRequestMainWebViewRequest) (*tg.WebViewResultURL, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesRequestMainWebView(t.ctx, request)
}

// MessagesRequestSimpleWebView opens a simple web view for a bot.
func (t *TelegramCore) MessagesRequestSimpleWebView(request *tg.MessagesRequestSimpleWebViewRequest) (*tg.WebViewResultURL, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesRequestSimpleWebView(t.ctx, request)
}

// MessagesRequestURLAuth requests URL authentication info from a bot.
func (t *TelegramCore) MessagesRequestURLAuth(request *tg.MessagesRequestURLAuthRequest) (tg.URLAuthResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesRequestURLAuth(t.ctx, request)
}

// MessagesRequestWebView opens a web view for a bot keyboard button.
func (t *TelegramCore) MessagesRequestWebView(request *tg.MessagesRequestWebViewRequest) (*tg.WebViewResultURL, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesRequestWebView(t.ctx, request)
}

// MessagesSaveDefaultSendAs sets the default send-as peer for a chat.
func (t *TelegramCore) MessagesSaveDefaultSendAs(request *tg.MessagesSaveDefaultSendAsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSaveDefaultSendAs(t.ctx, request)
}

// MessagesSaveGif saves or unsaves a GIF animation.
func (t *TelegramCore) MessagesSaveGif(request *tg.MessagesSaveGifRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSaveGif(t.ctx, request)
}

// MessagesSavePreparedInlineMessage saves a prepared inline message.
func (t *TelegramCore) MessagesSavePreparedInlineMessage(request *tg.MessagesSavePreparedInlineMessageRequest) (*tg.MessagesBotPreparedInlineMessage, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSavePreparedInlineMessage(t.ctx, request)
}

// MessagesSaveRecentSticker saves or unsaves a recent sticker.
func (t *TelegramCore) MessagesSaveRecentSticker(request *tg.MessagesSaveRecentStickerRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSaveRecentSticker(t.ctx, request)
}

// MessagesSearchCustomEmoji searches for custom emoji.
func (t *TelegramCore) MessagesSearchCustomEmoji(request *tg.MessagesSearchCustomEmojiRequest) (tg.EmojiListClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSearchCustomEmoji(t.ctx, request)
}

// MessagesSearchEmojiStickerSets searches for emoji sticker sets.
func (t *TelegramCore) MessagesSearchEmojiStickerSets(request *tg.MessagesSearchEmojiStickerSetsRequest) (tg.MessagesFoundStickerSetsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSearchEmojiStickerSets(t.ctx, request)
}

// MessagesSearchSentMedia searches for sent media across all chats.
func (t *TelegramCore) MessagesSearchSentMedia(request *tg.MessagesSearchSentMediaRequest) (tg.MessagesMessagesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSearchSentMedia(t.ctx, request)
}

// MessagesSearchStickers searches for stickers by emoji or keyword.
func (t *TelegramCore) MessagesSearchStickers(request *tg.MessagesSearchStickersRequest) (tg.MessagesFoundStickersClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSearchStickers(t.ctx, request)
}

// MessagesSendBotRequestedPeer sends a selected peer to a bot.
func (t *TelegramCore) MessagesSendBotRequestedPeer(request *tg.MessagesSendBotRequestedPeerRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendBotRequestedPeer(t.ctx, request)
}

// MessagesSendEncrypted sends an encrypted message in a secret chat.
func (t *TelegramCore) MessagesSendEncrypted(request *tg.MessagesSendEncryptedRequest) (tg.MessagesSentEncryptedMessageClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendEncrypted(t.ctx, request)
}

// MessagesSendEncryptedFile sends an encrypted file in a secret chat.
func (t *TelegramCore) MessagesSendEncryptedFile(request *tg.MessagesSendEncryptedFileRequest) (tg.MessagesSentEncryptedMessageClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendEncryptedFile(t.ctx, request)
}

// MessagesSendEncryptedService sends a service message in a secret chat.
func (t *TelegramCore) MessagesSendEncryptedService(request *tg.MessagesSendEncryptedServiceRequest) (tg.MessagesSentEncryptedMessageClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendEncryptedService(t.ctx, request)
}

// MessagesSendPaidReaction sends a paid reaction on a message.
func (t *TelegramCore) MessagesSendPaidReaction(request *tg.MessagesSendPaidReactionRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendPaidReaction(t.ctx, request)
}

// MessagesSendQuickReplyMessages sends quick reply messages to a chat.
func (t *TelegramCore) MessagesSendQuickReplyMessages(request *tg.MessagesSendQuickReplyMessagesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendQuickReplyMessages(t.ctx, request)
}

// MessagesSendScreenshotNotification notifies about a screenshot in a secret chat.
func (t *TelegramCore) MessagesSendScreenshotNotification(request *tg.MessagesSendScreenshotNotificationRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendScreenshotNotification(t.ctx, request)
}

// MessagesSendWebViewData sends web view data to a bot.
func (t *TelegramCore) MessagesSendWebViewData(request *tg.MessagesSendWebViewDataRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendWebViewData(t.ctx, request)
}

// MessagesSendWebViewResultMessage sends a web view interaction result.
func (t *TelegramCore) MessagesSendWebViewResultMessage(request *tg.MessagesSendWebViewResultMessageRequest) (*tg.WebViewMessageSent, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSendWebViewResultMessage(t.ctx, request)
}

// MessagesSetBotCallbackAnswer answers a callback query.
func (t *TelegramCore) MessagesSetBotCallbackAnswer(request *tg.MessagesSetBotCallbackAnswerRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetBotCallbackAnswer(t.ctx, request)
}

// MessagesSetBotPrecheckoutResults responds to a pre-checkout query.
func (t *TelegramCore) MessagesSetBotPrecheckoutResults(request *tg.MessagesSetBotPrecheckoutResultsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetBotPrecheckoutResults(t.ctx, request)
}

// MessagesSetBotShippingResults responds to a shipping query.
func (t *TelegramCore) MessagesSetBotShippingResults(request *tg.MessagesSetBotShippingResultsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetBotShippingResults(t.ctx, request)
}

// MessagesSetDefaultHistoryTTL sets the default auto-delete timer.
func (t *TelegramCore) MessagesSetDefaultHistoryTTL(period int) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetDefaultHistoryTTL(t.ctx, period)
}

// MessagesSetEncryptedTyping sends typing in a secret chat.
func (t *TelegramCore) MessagesSetEncryptedTyping(request *tg.MessagesSetEncryptedTypingRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetEncryptedTyping(t.ctx, request)
}

// MessagesSetGameScore sets a game score for a user.
func (t *TelegramCore) MessagesSetGameScore(request *tg.MessagesSetGameScoreRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSetGameScore(t.ctx, request)
}

// MessagesSetInlineBotResults sets results for an inline query.
func (t *TelegramCore) MessagesSetInlineBotResults(request *tg.MessagesSetInlineBotResultsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetInlineBotResults(t.ctx, request)
}

// MessagesSetInlineGameScore sets a game score in an inline message.
func (t *TelegramCore) MessagesSetInlineGameScore(request *tg.MessagesSetInlineGameScoreRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesSetInlineGameScore(t.ctx, request)
}

// MessagesStartHistoryImport begins processing a history import.
func (t *TelegramCore) MessagesStartHistoryImport(request *tg.MessagesStartHistoryImportRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesStartHistoryImport(t.ctx, request)
}

// MessagesSummarizeText generates an AI summary of text.
func (t *TelegramCore) MessagesSummarizeText(request *tg.MessagesSummarizeTextRequest) (*tg.TextWithEntities, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesSummarizeText(t.ctx, request)
}

// MessagesToggleBotInAttachMenu adds or removes a bot from the attach menu.
func (t *TelegramCore) MessagesToggleBotInAttachMenu(request *tg.MessagesToggleBotInAttachMenuRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesToggleBotInAttachMenu(t.ctx, request)
}

// MessagesToggleDialogFilterTags toggles filter tags in dialog folders.
func (t *TelegramCore) MessagesToggleDialogFilterTags(enabled bool) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesToggleDialogFilterTags(t.ctx, enabled)
}

// MessagesTogglePaidReactionPrivacy toggles paid reaction privacy.
func (t *TelegramCore) MessagesTogglePaidReactionPrivacy(request *tg.MessagesTogglePaidReactionPrivacyRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesTogglePaidReactionPrivacy(t.ctx, request)
}

// MessagesTogglePeerTranslations toggles auto-translation for a peer.
func (t *TelegramCore) MessagesTogglePeerTranslations(request *tg.MessagesTogglePeerTranslationsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesTogglePeerTranslations(t.ctx, request)
}

// MessagesToggleSavedDialogPin pins or unpins a saved dialog.
func (t *TelegramCore) MessagesToggleSavedDialogPin(request *tg.MessagesToggleSavedDialogPinRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesToggleSavedDialogPin(t.ctx, request)
}

// MessagesToggleStickerSets archives or unarchives sticker sets.
func (t *TelegramCore) MessagesToggleStickerSets(request *tg.MessagesToggleStickerSetsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesToggleStickerSets(t.ctx, request)
}

// MessagesToggleSuggestedPostApproval toggles suggested post approval.
func (t *TelegramCore) MessagesToggleSuggestedPostApproval(request *tg.MessagesToggleSuggestedPostApprovalRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesToggleSuggestedPostApproval(t.ctx, request)
}

// MessagesToggleTodoCompleted marks to-do items as completed or not.
func (t *TelegramCore) MessagesToggleTodoCompleted(request *tg.MessagesToggleTodoCompletedRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesToggleTodoCompleted(t.ctx, request)
}

// MessagesTranscribeAudio transcribes a voice message to text.
func (t *TelegramCore) MessagesTranscribeAudio(request *tg.MessagesTranscribeAudioRequest) (*tg.MessagesTranscribedAudio, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesTranscribeAudio(t.ctx, request)
}

// MessagesUninstallStickerSet removes a sticker set from the collection.
func (t *TelegramCore) MessagesUninstallStickerSet(stickerset tg.InputStickerSetClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesUninstallStickerSet(t.ctx, stickerset)
}

// MessagesUpdateSavedReactionTag updates a saved reaction tag label.
func (t *TelegramCore) MessagesUpdateSavedReactionTag(request *tg.MessagesUpdateSavedReactionTagRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesUpdateSavedReactionTag(t.ctx, request)
}

// MessagesUploadEncryptedFile uploads an encrypted file for a secret chat.
func (t *TelegramCore) MessagesUploadEncryptedFile(request *tg.MessagesUploadEncryptedFileRequest) (tg.EncryptedFileClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesUploadEncryptedFile(t.ctx, request)
}

// MessagesUploadImportedMedia uploads media for a history import.
func (t *TelegramCore) MessagesUploadImportedMedia(request *tg.MessagesUploadImportedMediaRequest) (tg.MessageMediaClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesUploadImportedMedia(t.ctx, request)
}

// MessagesUploadMedia uploads media for later use in messages.
func (t *TelegramCore) MessagesUploadMedia(request *tg.MessagesUploadMediaRequest) (tg.MessageMediaClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.MessagesUploadMedia(t.ctx, request)
}

// MessagesViewSponsoredMessage reports a sponsored message view.
func (t *TelegramCore) MessagesViewSponsoredMessage(randomid []byte) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.MessagesViewSponsoredMessage(t.ctx, randomid)
}

// --- Phone (37 methods) ---

// PhoneCheckGroupCall checks the availability or status of a group call.
func (t *TelegramCore) PhoneCheckGroupCall(request *tg.PhoneCheckGroupCallRequest) ([]int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneCheckGroupCall(t.ctx, request)
}

// PhoneCreateConferenceCall creates a new conference call.
func (t *TelegramCore) PhoneCreateConferenceCall(request *tg.PhoneCreateConferenceCallRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneCreateConferenceCall(t.ctx, request)
}

// PhoneCreateGroupCall creates a new group call in a chat.
func (t *TelegramCore) PhoneCreateGroupCall(request *tg.PhoneCreateGroupCallRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneCreateGroupCall(t.ctx, request)
}

// PhoneDeclineConferenceCallInvite declines a conference call invitation.
func (t *TelegramCore) PhoneDeclineConferenceCallInvite(msgid int) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneDeclineConferenceCallInvite(t.ctx, msgid)
}

// PhoneDeleteConferenceCallParticipants removes conference call participants.
func (t *TelegramCore) PhoneDeleteConferenceCallParticipants(request *tg.PhoneDeleteConferenceCallParticipantsRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneDeleteConferenceCallParticipants(t.ctx, request)
}

// PhoneDeleteGroupCallMessages deletes group call messages.
func (t *TelegramCore) PhoneDeleteGroupCallMessages(request *tg.PhoneDeleteGroupCallMessagesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneDeleteGroupCallMessages(t.ctx, request)
}

// PhoneDeleteGroupCallParticipantMessages deletes a participant's group call messages.
func (t *TelegramCore) PhoneDeleteGroupCallParticipantMessages(request *tg.PhoneDeleteGroupCallParticipantMessagesRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneDeleteGroupCallParticipantMessages(t.ctx, request)
}

// PhoneDiscardGroupCall ends a group call.
func (t *TelegramCore) PhoneDiscardGroupCall(call tg.InputGroupCallClass) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneDiscardGroupCall(t.ctx, call)
}

// PhoneEditGroupCallParticipant modifies a participant's group call settings.
func (t *TelegramCore) PhoneEditGroupCallParticipant(request *tg.PhoneEditGroupCallParticipantRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneEditGroupCallParticipant(t.ctx, request)
}

// PhoneEditGroupCallTitle changes a group call's title.
func (t *TelegramCore) PhoneEditGroupCallTitle(request *tg.PhoneEditGroupCallTitleRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneEditGroupCallTitle(t.ctx, request)
}

// PhoneExportGroupCallInvite generates an invite link for a group call.
func (t *TelegramCore) PhoneExportGroupCallInvite(request *tg.PhoneExportGroupCallInviteRequest) (*tg.PhoneExportedGroupCallInvite, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneExportGroupCallInvite(t.ctx, request)
}

// PhoneGetGroupCall returns group call information.
func (t *TelegramCore) PhoneGetGroupCall(request *tg.PhoneGetGroupCallRequest) (*tg.PhoneGroupCall, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupCall(t.ctx, request)
}

// PhoneGetGroupCallChainBlocks returns chain block data for a group call.
func (t *TelegramCore) PhoneGetGroupCallChainBlocks(request *tg.PhoneGetGroupCallChainBlocksRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupCallChainBlocks(t.ctx, request)
}

// PhoneGetGroupCallJoinAs returns identities available for joining a group call.
func (t *TelegramCore) PhoneGetGroupCallJoinAs(peer tg.InputPeerClass) (*tg.PhoneJoinAsPeers, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupCallJoinAs(t.ctx, peer)
}

// PhoneGetGroupCallStars returns star info for a group call.
func (t *TelegramCore) PhoneGetGroupCallStars(call tg.InputGroupCallClass) (*tg.PhoneGroupCallStars, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupCallStars(t.ctx, call)
}

// PhoneGetGroupCallStreamChannels returns stream channels for a group call.
func (t *TelegramCore) PhoneGetGroupCallStreamChannels(call tg.InputGroupCallClass) (*tg.PhoneGroupCallStreamChannels, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupCallStreamChannels(t.ctx, call)
}

// PhoneGetGroupCallStreamRtmpURL returns the RTMP URL for a group call.
func (t *TelegramCore) PhoneGetGroupCallStreamRtmpURL(request *tg.PhoneGetGroupCallStreamRtmpURLRequest) (*tg.PhoneGroupCallStreamRtmpURL, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupCallStreamRtmpURL(t.ctx, request)
}

// PhoneGetGroupParticipants returns group call participants.
func (t *TelegramCore) PhoneGetGroupParticipants(request *tg.PhoneGetGroupParticipantsRequest) (*tg.PhoneGroupParticipants, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneGetGroupParticipants(t.ctx, request)
}

// PhoneInviteConferenceCallParticipant invites a user to a conference call.
func (t *TelegramCore) PhoneInviteConferenceCallParticipant(request *tg.PhoneInviteConferenceCallParticipantRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneInviteConferenceCallParticipant(t.ctx, request)
}

// PhoneInviteToGroupCall invites users to a group call.
func (t *TelegramCore) PhoneInviteToGroupCall(request *tg.PhoneInviteToGroupCallRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneInviteToGroupCall(t.ctx, request)
}

// PhoneJoinGroupCall joins a group call.
func (t *TelegramCore) PhoneJoinGroupCall(request *tg.PhoneJoinGroupCallRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneJoinGroupCall(t.ctx, request)
}

// PhoneJoinGroupCallPresentation starts screen sharing in a group call.
func (t *TelegramCore) PhoneJoinGroupCallPresentation(request *tg.PhoneJoinGroupCallPresentationRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneJoinGroupCallPresentation(t.ctx, request)
}

// PhoneLeaveGroupCall leaves a group call.
func (t *TelegramCore) PhoneLeaveGroupCall(request *tg.PhoneLeaveGroupCallRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneLeaveGroupCall(t.ctx, request)
}

// PhoneLeaveGroupCallPresentation stops screen sharing in a group call.
func (t *TelegramCore) PhoneLeaveGroupCallPresentation(call tg.InputGroupCallClass) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneLeaveGroupCallPresentation(t.ctx, call)
}

// PhoneReceivedCall confirms receipt of an incoming call.
func (t *TelegramCore) PhoneReceivedCall(peer tg.InputPhoneCall) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.PhoneReceivedCall(t.ctx, peer)
}

// PhoneSaveCallDebug saves call debug information.
func (t *TelegramCore) PhoneSaveCallDebug(request *tg.PhoneSaveCallDebugRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.PhoneSaveCallDebug(t.ctx, request)
}

// PhoneSaveCallLog uploads a call log file.
func (t *TelegramCore) PhoneSaveCallLog(request *tg.PhoneSaveCallLogRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.PhoneSaveCallLog(t.ctx, request)
}

// PhoneSaveDefaultGroupCallJoinAs sets the default group call identity.
func (t *TelegramCore) PhoneSaveDefaultGroupCallJoinAs(request *tg.PhoneSaveDefaultGroupCallJoinAsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.PhoneSaveDefaultGroupCallJoinAs(t.ctx, request)
}

// PhoneSaveDefaultSendAs sets the default send-as identity for calls.
func (t *TelegramCore) PhoneSaveDefaultSendAs(request *tg.PhoneSaveDefaultSendAsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.PhoneSaveDefaultSendAs(t.ctx, request)
}

// PhoneSendConferenceCallBroadcast sends a broadcast in a conference call.
func (t *TelegramCore) PhoneSendConferenceCallBroadcast(request *tg.PhoneSendConferenceCallBroadcastRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneSendConferenceCallBroadcast(t.ctx, request)
}

// PhoneSendGroupCallEncryptedMessage sends an encrypted group call message.
func (t *TelegramCore) PhoneSendGroupCallEncryptedMessage(request *tg.PhoneSendGroupCallEncryptedMessageRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.PhoneSendGroupCallEncryptedMessage(t.ctx, request)
}

// PhoneSendGroupCallMessage sends a message in a group call.
func (t *TelegramCore) PhoneSendGroupCallMessage(request *tg.PhoneSendGroupCallMessageRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneSendGroupCallMessage(t.ctx, request)
}

// PhoneSetCallRating submits a quality rating for a call.
func (t *TelegramCore) PhoneSetCallRating(request *tg.PhoneSetCallRatingRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneSetCallRating(t.ctx, request)
}

// PhoneStartScheduledGroupCall starts a scheduled group call.
func (t *TelegramCore) PhoneStartScheduledGroupCall(call tg.InputGroupCallClass) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneStartScheduledGroupCall(t.ctx, call)
}

// PhoneToggleGroupCallRecord starts or stops group call recording.
func (t *TelegramCore) PhoneToggleGroupCallRecord(request *tg.PhoneToggleGroupCallRecordRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneToggleGroupCallRecord(t.ctx, request)
}

// PhoneToggleGroupCallSettings modifies group call settings.
func (t *TelegramCore) PhoneToggleGroupCallSettings(request *tg.PhoneToggleGroupCallSettingsRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneToggleGroupCallSettings(t.ctx, request)
}

// PhoneToggleGroupCallStartSubscription toggles group call start notifications.
func (t *TelegramCore) PhoneToggleGroupCallStartSubscription(request *tg.PhoneToggleGroupCallStartSubscriptionRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhoneToggleGroupCallStartSubscription(t.ctx, request)
}

// --- Photos (2 methods) ---

// PhotosUpdateProfilePhoto updates the user's profile photo.
func (t *TelegramCore) PhotosUpdateProfilePhoto(request *tg.PhotosUpdateProfilePhotoRequest) (*tg.PhotosPhoto, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhotosUpdateProfilePhoto(t.ctx, request)
}

// PhotosUploadContactProfilePhoto suggests a profile photo for a contact.
func (t *TelegramCore) PhotosUploadContactProfilePhoto(request *tg.PhotosUploadContactProfilePhotoRequest) (*tg.PhotosPhoto, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.PhotosUploadContactProfilePhoto(t.ctx, request)
}

// --- Stats (5 methods) ---

// StatsGetMessagePublicForwards retrieves public forwards of a channel message for statistics.
func (t *TelegramCore) StatsGetMessagePublicForwards(request *tg.StatsGetMessagePublicForwardsRequest) (*tg.StatsPublicForwards, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StatsGetMessagePublicForwards(t.ctx, request)
}

// StatsGetMessageStats returns view statistics for a channel message.
func (t *TelegramCore) StatsGetMessageStats(request *tg.StatsGetMessageStatsRequest) (*tg.StatsMessageStats, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StatsGetMessageStats(t.ctx, request)
}

// StatsGetStoryPublicForwards returns public forwards of a story.
func (t *TelegramCore) StatsGetStoryPublicForwards(request *tg.StatsGetStoryPublicForwardsRequest) (*tg.StatsPublicForwards, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StatsGetStoryPublicForwards(t.ctx, request)
}

// StatsGetStoryStats returns view statistics for a story.
func (t *TelegramCore) StatsGetStoryStats(request *tg.StatsGetStoryStatsRequest) (*tg.StatsStoryStats, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StatsGetStoryStats(t.ctx, request)
}

// StatsLoadAsyncGraph loads async statistical graph data by token.
func (t *TelegramCore) StatsLoadAsyncGraph(request *tg.StatsLoadAsyncGraphRequest) (tg.StatsGraphClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StatsLoadAsyncGraph(t.ctx, request)
}

// --- Stickers (11 methods) ---

// StickersAddStickerToSet adds a new sticker to an existing sticker set.
func (t *TelegramCore) StickersAddStickerToSet(request *tg.StickersAddStickerToSetRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersAddStickerToSet(t.ctx, request)
}

// StickersChangeSticker modifies properties of a sticker.
func (t *TelegramCore) StickersChangeSticker(request *tg.StickersChangeStickerRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersChangeSticker(t.ctx, request)
}

// StickersChangeStickerPosition changes a sticker's position in its set.
func (t *TelegramCore) StickersChangeStickerPosition(request *tg.StickersChangeStickerPositionRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersChangeStickerPosition(t.ctx, request)
}

// StickersCheckShortName checks if a sticker set short name is available.
func (t *TelegramCore) StickersCheckShortName(shortname string) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StickersCheckShortName(t.ctx, shortname)
}

// StickersCreateStickerSet creates a new sticker set.
func (t *TelegramCore) StickersCreateStickerSet(request *tg.StickersCreateStickerSetRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersCreateStickerSet(t.ctx, request)
}

// StickersDeleteStickerSet permanently deletes a sticker set.
func (t *TelegramCore) StickersDeleteStickerSet(stickerset tg.InputStickerSetClass) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StickersDeleteStickerSet(t.ctx, stickerset)
}

// StickersRemoveStickerFromSet removes a sticker from its set.
func (t *TelegramCore) StickersRemoveStickerFromSet(sticker tg.InputDocumentClass) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersRemoveStickerFromSet(t.ctx, sticker)
}

// StickersRenameStickerSet changes a sticker set's title.
func (t *TelegramCore) StickersRenameStickerSet(request *tg.StickersRenameStickerSetRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersRenameStickerSet(t.ctx, request)
}

// StickersReplaceSticker replaces a sticker with a new one.
func (t *TelegramCore) StickersReplaceSticker(request *tg.StickersReplaceStickerRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersReplaceSticker(t.ctx, request)
}

// StickersSetStickerSetThumb sets the thumbnail for a sticker set.
func (t *TelegramCore) StickersSetStickerSetThumb(request *tg.StickersSetStickerSetThumbRequest) (tg.MessagesStickerSetClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersSetStickerSetThumb(t.ctx, request)
}

// StickersSuggestShortName suggests a short name for a sticker set.
func (t *TelegramCore) StickersSuggestShortName(title string) (*tg.StickersSuggestedShortName, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StickersSuggestShortName(t.ctx, title)
}

// --- Stories (26 methods) ---

// StoriesActivateStealthMode activates stealth mode to hide story view activity.
func (t *TelegramCore) StoriesActivateStealthMode(request *tg.StoriesActivateStealthModeRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesActivateStealthMode(t.ctx, request)
}

// StoriesCanSendStory checks if the user can post a story to a peer.
func (t *TelegramCore) StoriesCanSendStory(peer tg.InputPeerClass) (*tg.StoriesCanSendStoryCount, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesCanSendStory(t.ctx, peer)
}

// StoriesCreateAlbum creates a new story album.
func (t *TelegramCore) StoriesCreateAlbum(request *tg.StoriesCreateAlbumRequest) (*tg.StoryAlbum, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesCreateAlbum(t.ctx, request)
}

// StoriesDeleteAlbum deletes a story album.
func (t *TelegramCore) StoriesDeleteAlbum(request *tg.StoriesDeleteAlbumRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StoriesDeleteAlbum(t.ctx, request)
}

// StoriesEditStory modifies a published story.
func (t *TelegramCore) StoriesEditStory(request *tg.StoriesEditStoryRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesEditStory(t.ctx, request)
}

// StoriesExportStoryLink generates a public link to a story.
func (t *TelegramCore) StoriesExportStoryLink(request *tg.StoriesExportStoryLinkRequest) (*tg.ExportedStoryLink, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesExportStoryLink(t.ctx, request)
}

// StoriesGetAlbums returns the user's story albums.
func (t *TelegramCore) StoriesGetAlbums(request *tg.StoriesGetAlbumsRequest) (tg.StoriesAlbumsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetAlbums(t.ctx, request)
}

// StoriesGetAlbumStories returns stories in a specific album.
func (t *TelegramCore) StoriesGetAlbumStories(request *tg.StoriesGetAlbumStoriesRequest) (*tg.StoriesStories, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetAlbumStories(t.ctx, request)
}

// StoriesGetAllReadPeerStories returns the read state of all peer stories.
func (t *TelegramCore) StoriesGetAllReadPeerStories() (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetAllReadPeerStories(t.ctx)
}

// StoriesGetChatsToSend returns chats where stories can be posted.
func (t *TelegramCore) StoriesGetChatsToSend() (tg.MessagesChatsClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetChatsToSend(t.ctx)
}

// StoriesGetPeerMaxIDs returns the latest story IDs for peers.
func (t *TelegramCore) StoriesGetPeerMaxIDs(id []tg.InputPeerClass) ([]tg.RecentStory, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetPeerMaxIDs(t.ctx, id)
}

// StoriesGetStoriesArchive returns archived stories for a peer.
func (t *TelegramCore) StoriesGetStoriesArchive(request *tg.StoriesGetStoriesArchiveRequest) (*tg.StoriesStories, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetStoriesArchive(t.ctx, request)
}

// StoriesGetStoriesByID returns stories by their IDs.
func (t *TelegramCore) StoriesGetStoriesByID(request *tg.StoriesGetStoriesByIDRequest) (*tg.StoriesStories, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetStoriesByID(t.ctx, request)
}

// StoriesGetStoryReactionsList returns reactions on a story.
func (t *TelegramCore) StoriesGetStoryReactionsList(request *tg.StoriesGetStoryReactionsListRequest) (*tg.StoriesStoryReactionsList, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetStoryReactionsList(t.ctx, request)
}

// StoriesGetStoryViewsList returns users who viewed a story.
func (t *TelegramCore) StoriesGetStoryViewsList(request *tg.StoriesGetStoryViewsListRequest) (*tg.StoriesStoryViewsList, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesGetStoryViewsList(t.ctx, request)
}

// StoriesIncrementStoryViews increments the view counter for stories.
func (t *TelegramCore) StoriesIncrementStoryViews(request *tg.StoriesIncrementStoryViewsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StoriesIncrementStoryViews(t.ctx, request)
}

// StoriesReadStories marks stories as read up to a given ID.
func (t *TelegramCore) StoriesReadStories(request *tg.StoriesReadStoriesRequest) ([]int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesReadStories(t.ctx, request)
}

// StoriesReorderAlbums reorders story albums.
func (t *TelegramCore) StoriesReorderAlbums(request *tg.StoriesReorderAlbumsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StoriesReorderAlbums(t.ctx, request)
}

// StoriesReport reports a story for terms of service violation.
func (t *TelegramCore) StoriesReport(request *tg.StoriesReportRequest) (tg.ReportResultClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesReport(t.ctx, request)
}

// StoriesSearchPosts searches for public story posts.
func (t *TelegramCore) StoriesSearchPosts(request *tg.StoriesSearchPostsRequest) (*tg.StoriesFoundStories, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesSearchPosts(t.ctx, request)
}

// StoriesStartLive starts a live story broadcast.
func (t *TelegramCore) StoriesStartLive(request *tg.StoriesStartLiveRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesStartLive(t.ctx, request)
}

// StoriesToggleAllStoriesHidden hides or shows the stories bar.
func (t *TelegramCore) StoriesToggleAllStoriesHidden(hidden bool) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StoriesToggleAllStoriesHidden(t.ctx, hidden)
}

// StoriesTogglePeerStoriesHidden hides or shows stories from a peer.
func (t *TelegramCore) StoriesTogglePeerStoriesHidden(request *tg.StoriesTogglePeerStoriesHiddenRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StoriesTogglePeerStoriesHidden(t.ctx, request)
}

// StoriesTogglePinned pins or unpins stories on the profile.
func (t *TelegramCore) StoriesTogglePinned(request *tg.StoriesTogglePinnedRequest) ([]int, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesTogglePinned(t.ctx, request)
}

// StoriesTogglePinnedToTop pins stories to the top of the profile.
func (t *TelegramCore) StoriesTogglePinnedToTop(request *tg.StoriesTogglePinnedToTopRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.StoriesTogglePinnedToTop(t.ctx, request)
}

// StoriesUpdateAlbum modifies a story album.
func (t *TelegramCore) StoriesUpdateAlbum(request *tg.StoriesUpdateAlbumRequest) (*tg.StoryAlbum, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.StoriesUpdateAlbum(t.ctx, request)
}

// --- Upload (8 methods) ---

// UploadGetCDNFile downloads a file chunk from a Telegram CDN node.
func (t *TelegramCore) UploadGetCDNFile(request *tg.UploadGetCDNFileRequest) (tg.UploadCDNFileClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UploadGetCDNFile(t.ctx, request)
}

// UploadGetCDNFileHashes returns file hashes for CDN download verification.
func (t *TelegramCore) UploadGetCDNFileHashes(request *tg.UploadGetCDNFileHashesRequest) ([]tg.FileHash, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UploadGetCDNFileHashes(t.ctx, request)
}

// UploadGetFile downloads a file chunk from Telegram servers.
func (t *TelegramCore) UploadGetFile(request *tg.UploadGetFileRequest) (tg.UploadFileClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UploadGetFile(t.ctx, request)
}

// UploadGetFileHashes returns file hashes for download verification.
func (t *TelegramCore) UploadGetFileHashes(request *tg.UploadGetFileHashesRequest) ([]tg.FileHash, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UploadGetFileHashes(t.ctx, request)
}

// UploadGetWebFile downloads a web file from Telegram.
func (t *TelegramCore) UploadGetWebFile(request *tg.UploadGetWebFileRequest) (*tg.UploadWebFile, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UploadGetWebFile(t.ctx, request)
}

// UploadReuploadCDNFile re-uploads a file to the CDN.
func (t *TelegramCore) UploadReuploadCDNFile(request *tg.UploadReuploadCDNFileRequest) ([]tg.FileHash, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UploadReuploadCDNFile(t.ctx, request)
}

// UploadSaveBigFilePart uploads a part of a large file.
func (t *TelegramCore) UploadSaveBigFilePart(request *tg.UploadSaveBigFilePartRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.UploadSaveBigFilePart(t.ctx, request)
}

// UploadSaveFilePart uploads a part of a file.
func (t *TelegramCore) UploadSaveFilePart(request *tg.UploadSaveFilePartRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.UploadSaveFilePart(t.ctx, request)
}

// --- Users (5 methods) ---

// UsersGetRequirementsToContact retrieves the requirements needed to contact the specified users.
func (t *TelegramCore) UsersGetRequirementsToContact(id []tg.InputUserClass) ([]tg.RequirementToContactClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UsersGetRequirementsToContact(t.ctx, id)
}

// UsersGetSavedMusic returns saved music tracks.
func (t *TelegramCore) UsersGetSavedMusic(request *tg.UsersGetSavedMusicRequest) (tg.UsersSavedMusicClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UsersGetSavedMusic(t.ctx, request)
}

// UsersGetSavedMusicByID returns saved music tracks by ID.
func (t *TelegramCore) UsersGetSavedMusicByID(request *tg.UsersGetSavedMusicByIDRequest) (tg.UsersSavedMusicClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UsersGetSavedMusicByID(t.ctx, request)
}

// UsersSetSecureValueErrors notifies about Passport data errors.
func (t *TelegramCore) UsersSetSecureValueErrors(request *tg.UsersSetSecureValueErrorsRequest) (bool, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return false, ErrAuth }
	return t.api.UsersSetSecureValueErrors(t.ctx, request)
}

// UsersSuggestBirthday suggests a birthday for a user.
func (t *TelegramCore) UsersSuggestBirthday(request *tg.UsersSuggestBirthdayRequest) (tg.UpdatesClass, error) {
	t.mu.RLock(); defer t.mu.RUnlock()
	if !t.authed || t.api == nil { return nil, ErrAuth }
	return t.api.UsersSuggestBirthday(t.ctx, request)
}


// --- Test helper methods (for ntgcalls harness and other test automation) ---

// CallInfo holds raw call state for test harnesses.
type CallInfo struct {
	ID          int64
	AccessHash  int64
	PeerID      int64
	IsOutgoing  bool
	P2PAllowed  bool
	AuthKey     [256]byte
	Connections []tg.PhoneConnectionClass
	Protocol    *tg.PhoneCallProtocol
}

// TestSetSignalingInInterceptor intercepts incoming encrypted signaling (from handleSignalingData).
func (t *TelegramCore) TestSetSignalingInInterceptor(callID int64, handler func([]byte)) {
	t.rawSigInterceptorsMu.Lock()
	defer t.rawSigInterceptorsMu.Unlock()
	if handler == nil {
		delete(t.rawSigInInterceptors, callID)
	} else {
		t.rawSigInInterceptors[callID] = handler
	}
}

// TestSetSignalingOutInterceptor intercepts outgoing encrypted signaling (from sendCallSignaling).
func (t *TelegramCore) TestSetSignalingOutInterceptor(callID int64, handler func([]byte)) {
	t.rawSigInterceptorsMu.Lock()
	defer t.rawSigInterceptorsMu.Unlock()
	if handler == nil {
		delete(t.rawSigOutInterceptors, callID)
	} else {
		t.rawSigOutInterceptors[callID] = handler
	}
}

// TestSendRawSignaling sends raw encrypted signaling bytes via MTProto.
func (t *TelegramCore) TestSendRawSignaling(callID, accessHash int64, data []byte) error {
	t.mu.RLock()
	api := t.api
	ctx := t.ctx
	t.mu.RUnlock()
	if api == nil {
		return ErrAuth
	}
	_, err := api.PhoneSendSignalingData(ctx, &tg.PhoneSendSignalingDataRequest{
		Peer: tg.InputPhoneCall{ID: callID, AccessHash: accessHash},
		Data: data,
	})
	return err
}

// TestAcceptCallRaw accepts an incoming call with skipWebRTC=true.
// DH completes normally, but no PeerConnection is created.
// After this returns, call TestGetCallInfo to get auth key and connections.
func (t *TelegramCore) TestAcceptCallRaw(callIDStr string) error {
	cid, err := strconv.ParseInt(callIDStr, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID: %w", err)
	}

	t.mu.Lock()
	call := t.activeCalls[cid]
	if call == nil {
		t.mu.Unlock()
		return fmt.Errorf("no incoming call %s", callIDStr)
	}
	call.skipWebRTC = true
	call.dhDone = make(chan struct{})
	t.mu.Unlock()

	// Do normal AcceptCall DH (AcceptCall handles the rest)
	_, err = t.AcceptCall(callIDStr)
	if err != nil {
		return err
	}

	// Wait for DH to complete
	select {
	case <-call.dhDone:
		return nil
	case <-time.After(20 * time.Second):
		return fmt.Errorf("DH exchange timed out")
	}
}

// TestStartCallRaw initiates a call with skipWebRTC=true.
// DH + confirmCall complete normally, but no PeerConnection is created.
// After this returns, call TestGetCallInfo to get auth key and connections.
func (t *TelegramCore) TestStartCallRaw(chatID string, video bool) (*CallSession, error) {
	cs, err := t.StartCall(chatID, video)
	if err != nil {
		return nil, err
	}
	cid, err2 := tgUserID(cs.ID)
	if err2 != nil {
		return nil, err2
	}
	t.mu.Lock()
	call := t.activeCalls[cid]
	if call != nil {
		call.skipWebRTC = true
		call.dhDone = make(chan struct{})
	}
	t.mu.Unlock()

	if call == nil {
		return nil, fmt.Errorf("call not found after StartCall")
	}

	// Wait for DH to complete (triggered by handleCallAccepted when callee answers)
	select {
	case <-call.dhDone:
		return cs, nil
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("DH exchange timed out — callee may not have answered")
	}
}

// TestHandleSignalingData injects raw signaling data as if received from MTProto.
func (t *TelegramCore) TestHandleSignalingData(callID int64, data []byte) {
	t.handleSignalingData(callID, data)
}

// TestGetCallInfo returns raw call state including auth key and connections.
func (t *TelegramCore) TestGetCallInfo(callIDStr string) *CallInfo {
	cid, err := strconv.ParseInt(callIDStr, 10, 64)
	if err != nil {
		return nil
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[cid]
	if call == nil {
		return nil
	}
	return &CallInfo{
		ID:          call.id,
		AccessHash:  call.accessHash,
		PeerID:      call.peerID,
		IsOutgoing:  call.isOutgoing,
		P2PAllowed:  call.p2pAllowed,
		AuthKey:     call.authKey,
		Connections: call.connections,
		Protocol:    call.protocol,
	}
}

// TestGetGroupCallAccessHash returns the access hash for a group call stored in activeCalls.
func (t *TelegramCore) TestGetGroupCallAccessHash(gcID int64) int64 {
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[gcID]
	if call == nil {
		return 0
	}
	return call.accessHash
}

// TestGetSenderSSRCs returns the SSRCs from pion's RTP senders.
func (t *TelegramCore) TestGetSenderSSRCs(callID string) string {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return "invalid-id"
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[cid]
	if call == nil || call.pc == nil {
		return "no-call"
	}
	var out strings.Builder
	for _, s := range call.pc.GetSenders() {
		params := s.GetParameters()
		for _, enc := range params.Encodings {
			out.WriteString(fmt.Sprintf("ssrc=%d ", enc.SSRC))
		}
	}
	return out.String()
}

// TestGetCallStats returns PC stats (outbound RTP packets sent, bytes sent, etc.)
func (t *TelegramCore) TestGetCallStats(callID string) string {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return "invalid-id"
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[cid]
	if call == nil || call.pc == nil {
		return "no-call"
	}
	var out strings.Builder
	for _, s := range call.pc.GetStats() {
		switch v := s.(type) {
		case webrtc.OutboundRTPStreamStats:
			out.WriteString(fmt.Sprintf("outbound: ssrc=%d packets=%d bytes=%d kind=%s ",
				v.SSRC, v.PacketsSent, v.BytesSent, v.Kind))
		case webrtc.InboundRTPStreamStats:
			out.WriteString(fmt.Sprintf("inbound: ssrc=%d packets=%d bytes=%d kind=%s ",
				v.SSRC, v.PacketsReceived, v.BytesReceived, v.Kind))
		case webrtc.ICECandidatePairStats:
			out.WriteString(fmt.Sprintf("ice-pair: state=%s local=%s remote=%s bytesSent=%d bytesRecv=%d ",
				v.State, v.LocalCandidateID, v.RemoteCandidateID, v.BytesSent, v.BytesReceived))
		}
	}
	return out.String()
}

// TestGetCallAudioSSRC returns the audio SSRC for a call.
func (t *TelegramCore) TestGetCallAudioSSRC(callID string) uint32 {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return 0
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[cid]
	if call == nil {
		return 0
	}
	return call.audioSSRC
}

// TestGetCallPCState returns the PeerConnection state as a string.
func (t *TelegramCore) TestGetCallPCState(callID string) string {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return "invalid-id"
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[cid]
	if call == nil {
		return "no-call"
	}
	if call.pc == nil {
		return "no-pc"
	}
	return fmt.Sprintf("pc=%s ice=%s", call.pc.ConnectionState(), call.pc.ICEConnectionState())
}

// --- Unified Core interface adapters ---
// These methods satisfy the expanded Core interface by delegating to existing platform-specific methods.

// GetChatInfo returns detailed information about a chat by its ID.
func (t *TelegramCore) GetChatInfo(chatID string) (*Dialog, error) {
	// Try channel first (supergroup/channel), fall back to basic chat
	d, err := t.GetFullChannel(chatID)
	if err == nil {
		return d, nil
	}
	return t.GetFullChat(chatID)
}

// EditChatTitle changes the title of a group or channel.
func (t *TelegramCore) EditChatTitle(chatID string, title string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = t.api.ChannelsEditTitle(t.ctx, &tg.ChannelsEditTitleRequest{
			Channel: &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash}, Title: title,
		})
		return err
	case *tg.PeerChat:
		_, err = t.api.MessagesEditChatTitle(t.ctx, &tg.MessagesEditChatTitleRequest{
			ChatID: p.ChatID, Title: title,
		})
		return err
	}
	return fmt.Errorf("telegram: cannot edit title for this chat type: %w", ErrNotSupported)
}

// EditChatDescription changes the description of a group or channel.
func (t *TelegramCore) EditChatDescription(chatID string, description string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesEditChatAbout(t.ctx, &tg.MessagesEditChatAboutRequest{
		Peer: inputPeer, About: description,
	})
	return err
}

// LeaveChat leaves a basic group chat.
func (t *TelegramCore) LeaveChat(chatID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = t.api.ChannelsLeaveChannel(t.ctx, &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash})
		return err
	case *tg.PeerChat:
		// Leave basic group by removing self
		me, _ := t.api.UsersGetUsers(t.ctx, []tg.InputUserClass{&tg.InputUserSelf{}})
		if len(me) > 0 {
			if u, ok := me[0].(*tg.User); ok {
				_, err = t.api.MessagesDeleteChatUser(t.ctx, &tg.MessagesDeleteChatUserRequest{
					ChatID: p.ChatID, UserID: &tg.InputUser{UserID: u.ID},
				})
				return err
			}
		}
		return fmt.Errorf("could not determine self user")
	}
	return fmt.Errorf("telegram: cannot leave this chat type: %w", ErrNotSupported)
}

// GetInviteLink returns the primary invite link for a chat.
func (t *TelegramCore) GetInviteLink(chatID string) (string, error) {
	return t.ExportChatInvite(chatID)
}

// AddMembers adds one or more users to a group or channel.
func (t *TelegramCore) AddMembers(chatID string, userIDs []string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		var users []tg.InputUserClass
		for _, uid := range userIDs {
			id, err := tgUserID(uid)
			if err != nil { return err }
			uhash := t.getCachedUserHash(id)
			users = append(users, &tg.InputUser{UserID: id, AccessHash: uhash})
		}
		_, err = t.api.ChannelsInviteToChannel(t.ctx, &tg.ChannelsInviteToChannelRequest{
			Channel: &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash}, Users: users,
		})
		return err
	case *tg.PeerChat:
		for _, uid := range userIDs {
			id, err := tgUserID(uid)
			if err != nil { return err }
			uhash := t.getCachedUserHash(id)
			_, err = t.api.MessagesAddChatUser(t.ctx, &tg.MessagesAddChatUserRequest{
				ChatID: p.ChatID, UserID: &tg.InputUser{UserID: id, AccessHash: uhash}, FwdLimit: 100,
			})
			if err != nil {
				return err
			}
		}
		return nil
	}
	return fmt.Errorf("telegram: cannot add members to this chat type: %w", ErrNotSupported)
}

// RemoveMember removes a user from a group or channel.
func (t *TelegramCore) RemoveMember(chatID string, userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = t.api.ChannelsEditBanned(t.ctx, &tg.ChannelsEditBannedRequest{
			Channel:      &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash},
			Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
			BannedRights: tg.ChatBannedRights{ViewMessages: true, UntilDate: 0},
		})
		return err
	case *tg.PeerChat:
		_, err = t.api.MessagesDeleteChatUser(t.ctx, &tg.MessagesDeleteChatUserRequest{
			ChatID: p.ChatID, UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
		})
		return err
	}
	return fmt.Errorf("telegram: cannot remove member from this chat type: %w", ErrNotSupported)
}

// BanMember bans a user from a channel or supergroup.
func (t *TelegramCore) BanMember(chatID string, userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("telegram: ban only works on channels/supergroups: %w", ErrNotSupported)
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil { return err }
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.ChannelsEditBanned(t.ctx, &tg.ChannelsEditBannedRequest{
		Channel:      &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		BannedRights: tg.ChatBannedRights{ViewMessages: true, UntilDate: 0},
	})
	return err
}

// UnbanMember lifts a ban on a user in a channel or supergroup.
func (t *TelegramCore) UnbanMember(chatID string, userID string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("telegram: unban only works on channels/supergroups: %w", ErrNotSupported)
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil { return err }
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.ChannelsEditBanned(t.ctx, &tg.ChannelsEditBannedRequest{
		Channel:      &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		BannedRights: tg.ChatBannedRights{}, // empty = unban
	})
	return err
}

// GetMembers returns the list of members in a group, supergroup, or channel.
// Handles both basic groups (via MessagesGetFullChat) and supergroups/channels (via ChannelsGetParticipants).
func (t *TelegramCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	// Try channel participants first (supergroups/channels).
	users, err := t.GetParticipants(chatID, limit)
	if err == nil {
		return users, nil
	}
	// Fallback: basic group — use MessagesGetFullChat which includes participants.
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}
	peer, peerErr := t.resolvePeer(chatID)
	if peerErr != nil {
		return nil, peerErr
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return nil, err // return original error if not a basic chat either
	}
	result, fullErr := t.api.MessagesGetFullChat(t.ctx, chat.ChatID)
	if fullErr != nil {
		return nil, fullErr
	}
	t.cacheEntities(result.Users, result.Chats)
	var members []User
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok {
			members = append(members, *t.convertUser(user))
		}
	}
	return members, nil
}

// SetAdmin grants or modifies admin rights for a user in a chat.
func (t *TelegramCore) SetAdmin(chatID string, userID string, admin bool) error {
	if admin {
		return t.PromoteAdmin(chatID, userID, tg.ChatAdminRights{
			ChangeInfo:     true,
			DeleteMessages: true,
			BanUsers:       true,
			InviteUsers:    true,
			PinMessages:    true,
		})
	}
	return t.DemoteAdmin(chatID, userID)
}

// GetContacts is already defined with the correct unified signature.
// BlockUser is already defined with the correct unified signature.
// UnblockUser is already defined with the correct unified signature.

// AddContact adds a new contact by phone number with the given first and last name.
func (t *TelegramCore) AddContact(phone string, firstName string, lastName string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	_, err := t.api.ContactsImportContacts(t.ctx, []tg.InputPhoneContact{
		{Phone: phone, FirstName: firstName, LastName: lastName},
	})
	return err
}

// DeleteContact removes a user from the contact list.
func (t *TelegramCore) DeleteContact(userID string) error {
	return t.DeleteContacts([]string{userID})
}

// GetBlockedUsers returns the list of blocked users.
func (t *TelegramCore) GetBlockedUsers() ([]User, error) {
	// Delegate to existing method with default limit
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}
	result, err := t.api.ContactsGetBlocked(t.ctx, &tg.ContactsGetBlockedRequest{Limit: 100})
	if err != nil {
		return nil, fmt.Errorf("get blocked: %w", err)
	}
	var users []User
	switch r := result.(type) {
	case *tg.ContactsBlocked:
		t.cacheEntities(r.Users, nil)
		for _, u := range r.Users {
			if user, ok := u.(*tg.User); ok {
				users = append(users, *t.convertUser(user))
			}
		}
	case *tg.ContactsBlockedSlice:
		t.cacheEntities(r.Users, nil)
		for _, u := range r.Users {
			if user, ok := u.(*tg.User); ok {
				users = append(users, *t.convertUser(user))
			}
		}
	}
	return users, nil
}

// SearchMessages searches for messages in a chat matching a query.
func (t *TelegramCore) SearchMessages(chatID string, query string, opts PaginationOpts) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	limit := opts.Limit
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesSearch(t.ctx, &tg.MessagesSearchRequest{
		Peer: inputPeer, Q: query, Filter: &tg.InputMessagesFilterEmpty{}, Limit: limit,
	})
	if err != nil {
		return nil, fmt.Errorf("search: %w", err)
	}
	return t.convertMessages(result), nil
}

// SearchGlobal searches for messages across all chats matching a query.
func (t *TelegramCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.ContactsSearch(t.ctx, &tg.ContactsSearchRequest{Q: query, Limit: limit})
	if err != nil {
		return nil, fmt.Errorf("global search: %w", err)
	}
	t.cacheEntities(result.Users, result.Chats)
	dialogs := make([]Dialog, 0, len(result.Users)+len(result.Chats))
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok {
			dialogs = append(dialogs, Dialog{
				ID: strconv.FormatInt(user.ID, 10), Title: strings.TrimSpace(user.FirstName + " " + user.LastName),
				Type: ChatTypeDM, Platform: tgPlatform,
			})
		}
	}
	for _, c := range result.Chats {
		switch ch := c.(type) {
		case *tg.Chat:
			dialogs = append(dialogs, Dialog{
				ID: strconv.FormatInt(-ch.ID, 10), Title: ch.Title,
				Type: ChatTypeGroup, Platform: tgPlatform,
			})
		case *tg.Channel:
			ctype := ChatTypeGroup
			if ch.Broadcast {
				ctype = ChatTypeChannel
			}
			dialogs = append(dialogs, Dialog{
				ID: strconv.FormatInt(-1000000000000-ch.ID, 10), Title: ch.Title,
				Type: ctype, Platform: tgPlatform,
			})
		}
	}
	return dialogs, nil
}

// SendTyping sends a typing indicator to a chat.
func (t *TelegramCore) SendTyping(chatID string) error {
	return t.SetTyping(chatID, &tg.SendMessageTypingAction{})
}

// CreatePoll creates and sends a poll with the given options to a chat.
func (t *TelegramCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	return t.SendPoll(chatID, question, options)
}

// VotePoll submits a vote for specific options on a poll.
func (t *TelegramCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	return t.VoteInPoll(chatID, msgID, optionIndex)
}

// SendSticker sends a sticker to a chat.
func (t *TelegramCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgUserID(stickerID)
	if err != nil {
		return nil, err
	}
	result, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(),
		Media: &tg.InputMediaDocument{ID: &tg.InputDocument{ID: id}},
	})
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

// GetSessions returns active sessions for the authenticated account.
func (t *TelegramCore) GetSessions() ([]Session, error) {
	sessions, err := t.GetActiveSessions()
	if err != nil {
		return nil, err
	}
	var result []Session
	for _, s := range sessions {
		result = append(result, Session{
			ID:         strconv.FormatInt(s.Hash, 10),
			Device:     s.Device,
			Platform:   s.Platform,
			AppName:    s.AppName,
			AppVersion: s.AppVersion,
			IP:         s.IP,
			Location:   s.Country,
			LastActive: time.Unix(int64(s.DateActive), 0),
			IsCurrent:  s.IsCurrent,
		})
	}
	return result, nil
}

// MuteChat enables or disables notifications for a chat.
func (t *TelegramCore) MuteChat(chatID string, muted bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	settings := tg.InputPeerNotifySettings{}
	if muted {
		settings.SetMuteUntil(2147483647) // max int32 — mute forever
	} else {
		settings.SetMuteUntil(0) // unmute
	}

	_, err = t.api.AccountUpdateNotifySettings(t.ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: settings,
	})
	return err
}

// MarkUnread marks a dialog as unread.
func (t *TelegramCore) MarkUnread(chatID string, unread bool) error {
	return t.MarkDialogUnread(chatID, unread)
}

// SendLocation sends a geographic location to a chat.
func (t *TelegramCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	result, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer: inputPeer,
		Media: &tg.InputMediaGeoPoint{
			GeoPoint: &tg.InputGeoPoint{
				Lat:  lat,
				Long: lon,
			},
		},
		RandomID: time.Now().UnixNano(),
		Message:  "",
	})
	if err != nil {
		return nil, fmt.Errorf("send location: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

// TerminateSession terminates a specific active session by its hash.
func (t *TelegramCore) TerminateSession(sessionID string) error {
	hash, err := strconv.ParseInt(sessionID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid session ID: %w", err)
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	_, err = t.api.AccountResetAuthorization(t.ctx, hash)
	return err
}
