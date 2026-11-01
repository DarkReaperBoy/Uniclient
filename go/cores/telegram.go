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
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"net"
	"net/http"
	"net/url"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/telegram/dcs"
	"github.com/gotd/td/telegram/downloader"
	"github.com/gotd/td/telegram/message"
	"github.com/gotd/td/telegram/message/styling"
	"github.com/gotd/td/telegram/uploader"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
	"github.com/pion/ice/v4"
	"github.com/pion/interceptor"
	pionlogging "github.com/pion/logging"
	"github.com/pion/rtcp"
	pionrtp "github.com/pion/rtp"
	"github.com/pion/sctp"
	"github.com/pion/stun/v4"
	"github.com/pion/webrtc/v4"

	pionmedia "github.com/pion/webrtc/v4/pkg/media"
	"uniclient/utils"
	"uniclient/wrtc"
)

const tgPlatform = "telegram"

type TelegramCore struct {
	mu sync.RWMutex
	wg sync.WaitGroup

	client *telegram.Client
	api    *tg.Client
	sender *message.Sender
	ctx    context.Context
	cancel context.CancelFunc

	preAuthAPI       *tg.Client
	authPhoneHash    string
	preAuthConnectMu sync.Mutex

	apiID             int
	apiHash           string
	useTestDC         bool
	forceRelayICE     bool
	forceV2Sig        bool
	forceV2Impl       bool
	forceV2Ref        bool
	forceV1Framing    bool
	forceInstanceImpl bool
	noOwnOffer        bool
	maxCallVersion    string
	minCallVersion    string
	botToken          string
	phone             string
	isBot             bool
	authed            bool
	customDeviceModel string

	sessionStorage telegram.SessionStorage

	dialFunc dcs.DialFunc

	proxyMu  sync.RWMutex
	proxyCfg ProxyConfig

	dispatcher     *tg.UpdateDispatcher
	updateHandlers []func(Update)
	updateMu       sync.RWMutex

	userAccessHash    map[int64]int64
	channelAccessHash map[int64]int64
	fileAccessHash    map[int64]int64
	fileReference     map[int64][]byte
	fileMimeType      map[int64]string
	userNames         map[int64]string
	userUsernames     map[int64]string
	userColorIDs      map[int64]int
	channelNames      map[int64]string
	peerPhotoID       map[int64]int64
	peerMu            sync.RWMutex

	selfID   int64
	selfName string

	authCodeCh      chan string
	authPwdCh       chan string
	authSignUpCh    chan [2]string
	authCodeReady   chan struct{}
	authPwdReady    chan struct{}
	authSignUpReady chan struct{}
	authSetupDone   chan struct{}
	authDoneCh      chan struct{}
	authErrCh       chan error

	authCodeByTelegram   bool
	authCodeFragmentURL  string
	authCodeEmailPattern string
	authCodeTimeout      int
	authCodeLength       int

	authEmailReady chan struct{}
	emailSetupMode bool
	emailNewHash   string

	qrRefreshCb func()

	activeCalls  map[int64]*tgCall
	pendingDH    map[int64]*pendingDHState
	confCallHash map[int64]int64
	confInvites  map[int64]map[int64]*confInviteEntry

	adminRanks        map[int64]map[int64]string
	adminRanksFetched map[int64]bool
	adminRanksMu      sync.RWMutex

	rawSigInInterceptors  map[int64]func([]byte)
	rawSigOutInterceptors map[int64]func([]byte)
	rawSigInterceptorsMu  sync.RWMutex

	forumTopics   map[string]forumTopicInfo
	forumTopicsMu sync.RWMutex

	timezoneOffsets   map[string]int
	timezoneOffsetsMu sync.RWMutex

	cfgMu     sync.RWMutex
	cachedCfg *tg.Config

	newVideoEncoder func(width, height, bitrate int) (VideoEncoder, error)
	newVideoDecoder func() (VideoDecoder, error)
}

var _ Core = (*TelegramCore)(nil)

type VideoEncoder interface {
	Encode(yuv420p []byte, width, height int) (vp8Frame []byte, err error)
	ForceKeyframe()
	Close()
}

type VideoDecoder interface {
	Decode(vp8Frame []byte) (yuv420p []byte, width, height int, err error)
	Close()
}

type TelegramConfig struct {
	APIID             int
	APIHash           string
	UseTestDC         bool
	SessionStorage    telegram.SessionStorage
	DialFunc          dcs.DialFunc
	ForceRelayICE     bool
	ForceV2Sig        bool
	ForceV2Impl       bool
	ForceV2Ref        bool
	ForceV1Framing    bool
	ForceInstanceImpl bool
	NoOwnOffer        bool
	MaxCallVersion    string
	MinCallVersion    string
}

func NewTelegramCore(cfg TelegramConfig) *TelegramCore {
	if cfg.SessionStorage == nil {
		cfg.SessionStorage = &session.StorageMemory{}
	}
	return &TelegramCore{
		apiID:                 cfg.APIID,
		apiHash:               cfg.APIHash,
		useTestDC:             cfg.UseTestDC,
		forceRelayICE:         cfg.ForceRelayICE,
		forceV2Sig:            cfg.ForceV2Sig,
		forceV2Impl:           cfg.ForceV2Impl,
		forceV2Ref:            cfg.ForceV2Ref,
		forceV1Framing:        cfg.ForceV1Framing,
		forceInstanceImpl:     cfg.ForceInstanceImpl,
		noOwnOffer:            cfg.NoOwnOffer,
		maxCallVersion:        cfg.MaxCallVersion,
		minCallVersion:        cfg.MinCallVersion,
		sessionStorage:        cfg.SessionStorage,
		dialFunc:              cfg.DialFunc,
		authSetupDone:         make(chan struct{}),
		userAccessHash:        make(map[int64]int64),
		channelAccessHash:     make(map[int64]int64),
		fileAccessHash:        make(map[int64]int64),
		fileReference:         make(map[int64][]byte),
		fileMimeType:          make(map[int64]string),
		userNames:             make(map[int64]string),
		userUsernames:         make(map[int64]string),
		userColorIDs:          make(map[int64]int),
		channelNames:          make(map[int64]string),
		peerPhotoID:           make(map[int64]int64),
		adminRanks:            make(map[int64]map[int64]string),
		adminRanksFetched:     make(map[int64]bool),
		activeCalls:           make(map[int64]*tgCall),
		pendingDH:             make(map[int64]*pendingDHState),
		confCallHash:          make(map[int64]int64),
		confInvites:           make(map[int64]map[int64]*confInviteEntry),
		rawSigInInterceptors:  make(map[int64]func([]byte)),
		rawSigOutInterceptors: make(map[int64]func([]byte)),
	}
}

func (t *TelegramCore) Name() string { return tgPlatform }

func (t *TelegramCore) Capabilities() []string {
	return []string{
		CapText, CapChannels, CapTopics, CapCalls, CapGroupCalls,
		CapReactions, CapReadReceipts, CapTyping, CapPolls, CapStickers,
		CapFolders, CapAdmin, CapSessions, CapBase64Image, CapScheduled,
		CapSearch, CapBlocking, CapFileTransfer, CapCloudPassword,
	}
}

func (t *TelegramCore) SetProxyConfig(cfg ProxyConfig) {
	t.proxyMu.Lock()
	t.proxyCfg = cfg
	t.proxyMu.Unlock()
}

func (t *TelegramCore) initClient() {
	dispatcher := tg.NewUpdateDispatcher()
	t.dispatcher = &dispatcher

	opts := telegram.Options{
		SessionStorage: t.sessionStorage,
		UpdateHandler:  dispatcher,
	}

	if t.customDeviceModel != "" {
		opts.Device.DeviceModel = t.customDeviceModel
	}

	t.proxyMu.RLock()
	pcfg := t.proxyCfg
	t.proxyMu.RUnlock()
	if pcfg.active() {
		if res, err := pcfg.resolver(); err != nil {
			log.Printf("[telegram] proxy resolver build failed (%s %s:%d): %v — dialing direct",
				pcfg.Type, pcfg.Host, pcfg.Port, err)
		} else if res != nil {
			opts.Resolver = res
			log.Printf("[telegram] dialing through %s proxy %s:%d", pcfg.Type, pcfg.Host, pcfg.Port)
		}
	} else if t.dialFunc != nil {
		opts.Resolver = dcs.Plain(dcs.PlainOptions{
			Dial: t.dialFunc,
		})
	}

	if t.useTestDC {
		opts.DCList = dcs.Test()
		opts.DC = 2
	}

	t.client = telegram.NewClient(t.apiID, t.apiHash, opts)

	dispatcher.OnNewMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewMessage) error {
		var converted *Message
		switch msg := u.Message.(type) {
		case *tg.Message:
			converted = t.ConvertMessage(msg)
			t.attachSublistInfo(converted, msg, e)
			if code := extractLoginCode(msg); code != "" {
				t.fireUpdate(Update{
					Type:      UpdateLoginCode,
					LoginCode: code,
					Platform:  tgPlatform,
				})
			}
		case *tg.MessageService:
			if _, ok := msg.Action.(*tg.MessageActionEmpty); ok {
				return nil
			}
			if _, ok := msg.Action.(*tg.MessageActionHistoryClear); ok {
				return nil
			}
			converted = t.ConvertServiceMessage(msg)
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
		converted := t.ConvertMessage(msg)
		t.fireUpdate(Update{
			Type:     UpdateEditMessage,
			ChatID:   converted.ChatID,
			Message:  converted,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnLoginToken(func(ctx context.Context, e tg.Entities, u *tg.UpdateLoginToken) error {
		t.mu.RLock()
		cb := t.qrRefreshCb
		t.mu.RUnlock()
		if cb != nil {
			cb()
		}
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

	dispatcher.OnNewChannelMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateNewChannelMessage) error {
		var converted *Message
		switch msg := u.Message.(type) {
		case *tg.Message:
			converted = t.ConvertMessage(msg)
			t.attachSublistInfo(converted, msg, e)
		case *tg.MessageService:
			if _, ok := msg.Action.(*tg.MessageActionEmpty); ok {
				return nil
			}
			if _, ok := msg.Action.(*tg.MessageActionHistoryClear); ok {
				return nil
			}
			converted = t.ConvertServiceMessage(msg)
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
		converted := t.ConvertMessage(msg)
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
			go func() {
				if err := t.handleIncomingCallConfirmed(c); err != nil {
					fmt.Printf("[tg-call] handleIncomingCallConfirmed ERROR: %v\n", err)
				}
			}()
		case *tg.PhoneCallDiscarded:
			fmt.Printf("[tg-call] Discarded! id=%d reason=%T needRating=%v needDebug=%v\n", c.ID, c.Reason, c.NeedRating, c.NeedDebug)
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
					ChatID:  strconv.FormatInt(c.AdminID, 10),
					IsVideo: c.Video,
					State:   CallStateRinging,
					Meta:    map[string]string{"incoming": "true"},
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

	dispatcher.OnGroupCallConnection(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCallConnection) error {
		fmt.Printf("[tg-group] UpdateGroupCallConnection: presentation=%v params=%d bytes\n",
			u.Presentation, len(u.Params.Data))
		go t.handleGroupCallConnection(u.Params.Data, u.Presentation)
		return nil
	})

	dispatcher.OnGroupCall(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCall) error {
		switch gc := u.Call.(type) {
		case *tg.GroupCall:
			fmt.Printf("[tg-group] UpdateGroupCall: id=%d participants=%d title=%q\n",
				gc.ID, gc.ParticipantsCount, gc.Title)
			t.mu.RLock()
			call := t.activeCalls[gc.ID]
			t.mu.RUnlock()
			if call != nil {
				call.gcSettingsMu.Lock()
				call.gcJoinMuted = gc.JoinMuted
				call.gcMessagesEnabled = gc.MessagesEnabled
				call.gcSettingsLoaded = true
				call.gcSettingsMu.Unlock()
				t.fireUpdate(Update{
					Type:     UpdateCallState,
					Platform: tgPlatform,
					Call: &CallSession{
						ID:      strconv.FormatInt(gc.ID, 10),
						State:   CallStateActive,
						IsGroup: true,
						Meta: map[string]string{
							"title":              gc.Title,
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
				call.sfuRemoteVideoMu.Lock()
				for eid, uid := range call.sfuRemoteVideoEndpts {
					if uid == userID {
						delete(call.sfuRemoteVideoEndpts, eid)
						videoEndpointsChanged = true
					}
				}
				call.sfuRemoteVideoMu.Unlock()
				if src := uint32(p.Source); src != 0 {
					call.audioLevelMu.Lock()
					delete(call.audioLevels, src)
					delete(call.audioLevelTs, src)
					delete(call.ssrcToUser, src)
					call.audioLevelMu.Unlock()
				}
			} else {
				fmt.Printf("[tg-group]   participant: userID=%s ssrc=%d muted=%v canSelfUnmute=%v videoJoined=%v\n",
					userID, p.Source, p.Muted, p.CanSelfUnmute, p.VideoJoined)
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
			vol := 0
			if v, ok := p.GetVolume(); ok {
				vol = v
			}
			rhr := int64(0)
			if r, ok := p.GetRaiseHandRating(); ok {
				rhr = r
			}
			participants = append(participants, CallParticipant{
				UserID:           userID,
				DisplayName:      displayName,
				IsMuted:          p.Muted,
				HasVideo:         p.VideoJoined,
				CanSelfUnmute:    p.CanSelfUnmute,
				RaisedHandRating: rhr,
				Volume:           vol,
				SSRC:             int32(p.Source),
			})
			if src := uint32(p.Source); src != 0 && userID != "" && call.ssrcToUser != nil {
				call.audioLevelMu.Lock()
				call.ssrcToUser[src] = userID
				call.audioLevelMu.Unlock()
			}
		}
		if videoEndpointsChanged {
			go t.sendSFUVideoConstraints(call)
		}

		call.lastParticipantsMu.Lock()
		call.lastParticipants = participants
		call.lastParticipantsMu.Unlock()

		t.fireUpdate(Update{
			Type:     UpdateCallState,
			Platform: tgPlatform,
			Call: &CallSession{
				ID:           strconv.FormatInt(gcID, 10),
				State:        call.state,
				IsGroup:      true,
				Participants: t.mergeConfInvites(gcID, participants),
			},
		})
		return nil
	})

	dispatcher.OnGroupCallMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCallMessage) error {
		gcID := inputGroupCallID(u.Call)
		fromID := peerToID(u.Message.FromID)
		senderName := t.resolveCallMemberName(e, gcID, fromID)
		t.fireUpdate(Update{
			Type:     UpdateGroupCallMessage,
			Platform: tgPlatform,
			GroupCallMessage: &GroupCallMessageUpdate{
				CallID:     strconv.FormatInt(gcID, 10),
				MessageID:  strconv.Itoa(u.Message.ID),
				SenderID:   fromID,
				SenderName: senderName,
				Text:       u.Message.Message.Text,
				Date:       int64(u.Message.Date),
				Outgoing:   fromID == strconv.FormatInt(t.selfID, 10),
				FromAdmin:  u.Message.FromAdmin,
			},
		})
		return nil
	})
	dispatcher.OnGroupCallEncryptedMessage(func(ctx context.Context, e tg.Entities, u *tg.UpdateGroupCallEncryptedMessage) error {
		fmt.Printf("[tg-group] updateGroupCallEncryptedMessage: %d bytes (no E2E chain — skipped)\n", len(u.EncryptedMessage))
		return nil
	})
	dispatcher.OnNotifySettings(func(ctx context.Context, e tg.Entities, u *tg.UpdateNotifySettings) error {
		var peerType string
		var peerID int64
		switch p := u.Peer.(type) {
		case *tg.NotifyPeer:
			switch peer := p.Peer.(type) {
			case *tg.PeerUser:
				peerType = "user"
				peerID = peer.UserID
			case *tg.PeerChat:
				peerType = "group"
				peerID = peer.ChatID
			case *tg.PeerChannel:
				peerType = "channel"
				peerID = peer.ChannelID
			}
		case *tg.NotifyUsers:
			peerType = "default_private"
		case *tg.NotifyChats:
			peerType = "default_group"
		case *tg.NotifyBroadcasts:
			peerType = "default_channel"
		}
		if peerType == "" {
			return nil
		}
		muted := u.NotifySettings.MuteUntil > 0
		muteUntil := int32(0)
		if muted && u.NotifySettings.MuteUntil < 2000000000 {
			muteUntil = int32(u.NotifySettings.MuteUntil)
		}
		t.fireUpdate(Update{
			Type:     UpdateNotifySettings,
			Platform: tgPlatform,
			NotifySettings: &NotifySettingsUpdate{
				PeerType:  peerType,
				PeerID:    peerID,
				Muted:     muted,
				MuteUntil: muteUntil,
			},
		})
		return nil
	})

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
	dispatcher.OnUserTyping(func(ctx context.Context, e tg.Entities, u *tg.UpdateUserTyping) error {
		action := tgActionString(u.Action)
		if action == "cancel" {
			return nil
		}
		t.fireUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   strconv.FormatInt(u.UserID, 10),
			UserID:   strconv.FormatInt(u.UserID, 10),
			Action:   action,
			Platform: tgPlatform,
		})
		return nil
	})
	dispatcher.OnChatUserTyping(func(ctx context.Context, e tg.Entities, u *tg.UpdateChatUserTyping) error {
		action := tgActionString(u.Action)
		if action == "cancel" {
			return nil
		}
		var userID string
		switch p := u.FromID.(type) {
		case *tg.PeerUser:
			userID = strconv.FormatInt(p.UserID, 10)
		default:
			return nil
		}
		t.fireUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   strconv.FormatInt(u.ChatID, 10),
			UserID:   userID,
			Action:   action,
			Platform: tgPlatform,
		})
		return nil
	})
	dispatcher.OnChannelUserTyping(func(ctx context.Context, e tg.Entities, u *tg.UpdateChannelUserTyping) error {
		action := tgActionString(u.Action)
		if action == "cancel" {
			return nil
		}
		var userID string
		switch p := u.FromID.(type) {
		case *tg.PeerUser:
			userID = strconv.FormatInt(p.UserID, 10)
		default:
			return nil
		}
		t.fireUpdate(Update{
			Type:     UpdateTyping,
			ChatID:   "-100" + strconv.FormatInt(u.ChannelID, 10),
			UserID:   userID,
			Action:   action,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnTranscribedAudio(func(ctx context.Context, e tg.Entities, u *tg.UpdateTranscribedAudio) error {
		chatID := peerToID(u.Peer)
		if chatID == "" || u.MsgID == 0 {
			return nil
		}
		t.fireUpdate(Update{
			Type:    UpdateTranscription,
			ChatID:  chatID,
			Message: nil,
			Transcription: &TranscriptionUpdate{
				MessageID:       strconv.Itoa(u.MsgID),
				TranscriptionID: u.TranscriptionID,
				Pending:         u.Pending,
				Text:            u.Text,
			},
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnBotMessageReaction(func(ctx context.Context, e tg.Entities, u *tg.UpdateBotMessageReaction) error {
		if len(u.NewReactions) == 0 {
			return nil
		}
		chatID := peerToID(u.Peer)
		var actorName string
		var actorID string
		if p, ok := u.Actor.(*tg.PeerUser); ok {
			actorID = strconv.FormatInt(p.UserID, 10)
			actorName = t.getCachedUserName(p.UserID)
		} else {
			actorID = peerToID(u.Actor)
		}
		emoji := tgReactionEmoji(u.NewReactions[0])
		m := &Message{
			ID:         fmt.Sprintf("react_%d_%d", u.MsgID, u.Date),
			ChatID:     chatID,
			SenderID:   actorID,
			SenderName: actorName,
			Text:       emoji,
			Timestamp:  time.Unix(int64(u.Date), 0),
			Status:     MessageStatusSent,
			Platform:   tgPlatform,
			Extra: map[string]interface{}{
				"is_reaction":     true,
				"reaction_emoji":  emoji,
				"reactor_name":    actorName,
				"reacted_to_type": 0,
			},
		}
		t.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   chatID,
			Message:  m,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnMessageReactions(func(ctx context.Context, e tg.Entities, u *tg.UpdateMessageReactions) error {
		chatID := peerToID(u.Peer)
		msgID := strconv.Itoa(u.MsgID)

		results := u.Reactions.GetResults()
		counts := make([]Reaction, 0, len(results))
		for _, r := range results {
			switch re := r.Reaction.(type) {
			case *tg.ReactionEmoji:
				if re.Emoticon != "" {
					counts = append(counts, Reaction{
						Emoji: re.Emoticon,
						Count: r.Count,
						ByMe:  r.ChosenOrder > 0,
					})
				}
			case *tg.ReactionCustomEmoji:
				counts = append(counts, Reaction{
					DocumentID: re.DocumentID,
					Count:      r.Count,
					ByMe:       r.ChosenOrder > 0,
				})
			}
		}
		t.fireUpdate(Update{
			Type:      UpdateReactions,
			ChatID:    chatID,
			MessageID: msgID,
			Message:   &Message{ID: msgID, ChatID: chatID, Platform: tgPlatform, Reactions: counts},
			Platform:  tgPlatform,
		})

		recent, ok := u.Reactions.GetRecentReactions()
		if !ok {
			return nil
		}
		for _, r := range recent {
			if !r.Unread {
				continue
			}
			var actorName string
			var actorID string
			if p, ok := r.PeerID.(*tg.PeerUser); ok {
				actorID = strconv.FormatInt(p.UserID, 10)
				actorName = t.getCachedUserName(p.UserID)
			} else {
				actorID = peerToID(r.PeerID)
			}
			emoji := tgReactionEmoji(r.Reaction)
			m := &Message{
				ID:         fmt.Sprintf("react_%d_%d", u.MsgID, r.Date),
				ChatID:     chatID,
				SenderID:   actorID,
				SenderName: actorName,
				Text:       emoji,
				Timestamp:  time.Unix(int64(r.Date), 0),
				Status:     MessageStatusSent,
				Platform:   tgPlatform,
				Extra: map[string]interface{}{
					"is_reaction":     true,
					"reaction_emoji":  emoji,
					"reactor_name":    actorName,
					"reacted_to_type": 0,
				},
			}
			t.fireUpdate(Update{
				Type:     UpdateNewMessage,
				ChatID:   chatID,
				Message:  m,
				Platform: tgPlatform,
			})
		}
		return nil
	})

	dispatcher.OnMessagePollVote(func(ctx context.Context, e tg.Entities, u *tg.UpdateMessagePollVote) error {
		var voterID string
		var voterName string
		if p, ok := u.Peer.(*tg.PeerUser); ok {
			voterID = strconv.FormatInt(p.UserID, 10)
			voterName = t.getCachedUserName(p.UserID)
		} else {
			voterID = peerToID(u.Peer)
		}
		var optionText string
		if len(u.Options) > 0 {
			optionText = string(u.Options[0])
		}
		pollIDStr := strconv.FormatInt(u.PollID, 10)
		m := &Message{
			ID:         fmt.Sprintf("pollvote_%s_%s", pollIDStr, voterID),
			ChatID:     voterID,
			SenderID:   voterID,
			SenderName: voterName,
			Text:       optionText,
			Timestamp:  time.Now(),
			Status:     MessageStatusSent,
			Platform:   tgPlatform,
			Extra: map[string]interface{}{
				"is_poll_vote":     true,
				"poll_vote_option": optionText,
				"reactor_name":     voterName,
			},
		}
		t.fireUpdate(Update{
			Type:     UpdateNewMessage,
			ChatID:   m.ChatID,
			Message:  m,
			Platform: tgPlatform,
		})
		return nil
	})

	dispatcher.OnMessagePoll(func(ctx context.Context, e tg.Entities, u *tg.UpdateMessagePoll) error {
		msgID := int64(0)
		chatID := ""
		if peer, ok := u.GetPeer(); ok && peer != nil {
			if id := peerToID(peer); id != "" {
				chatID = id
			}
		}
		if mid, ok := u.GetMsgID(); ok && mid != 0 {
			msgID = int64(mid)
		} else if msgID == 0 {
			msgID = u.PollID
		}

		extra := map[string]interface{}{}
		if res := u.GetResults(); res.Results != nil || res.TotalVoters > 0 {
			if rs := res.Results; len(rs) > 0 {
				opts := make([]map[string]interface{}, 0, len(rs))
				for _, v := range rs {
					opt := map[string]interface{}{
						"option": base64.StdEncoding.EncodeToString(v.Option),
					}
					opt["voters"] = v.Voters
					opt["chosen"] = v.Chosen
					opt["correct"] = v.Correct
					opts = append(opts, opt)
				}
				extra["poll_results_merge"] = opts
			}
			if tv, ok := res.GetTotalVoters(); ok {
				extra["poll_total_voters"] = tv
			}
			if sol, ok := res.GetSolution(); ok && sol != "" {
				extra["poll_solution"] = sol
			}
		}
		if poll, ok := u.GetPoll(); ok {
			if poll.Closed {
				extra["poll_closed"] = true
			}
		}

		m := &Message{
			ID:     strconv.FormatInt(msgID, 10),
			ChatID: chatID,
			Extra:  extra,
		}
		t.fireUpdate(Update{
			Type:     UpdatePollResults,
			ChatID:   chatID,
			Message:  m,
			Platform: tgPlatform,
		})
		return nil
	})

}

func tgActionString(a tg.SendMessageActionClass) string {
	switch a.(type) {
	case *tg.SendMessageTypingAction:
		return "typing"
	case *tg.SendMessageRecordVideoAction:
		return "record_video"
	case *tg.SendMessageUploadVideoAction:
		return "upload_video"
	case *tg.SendMessageRecordAudioAction:
		return "record_audio"
	case *tg.SendMessageUploadAudioAction:
		return "upload_audio"
	case *tg.SendMessageUploadPhotoAction:
		return "upload_photo"
	case *tg.SendMessageUploadDocumentAction:
		return "upload_document"
	case *tg.SendMessageGeoLocationAction:
		return "geo_location"
	case *tg.SendMessageChooseContactAction:
		return "choose_contact"
	case *tg.SendMessageGamePlayAction:
		return "game_play"
	case *tg.SendMessageRecordRoundAction:
		return "record_round"
	case *tg.SendMessageUploadRoundAction:
		return "upload_round"
	case *tg.SendMessageChooseStickerAction:
		return "choose_sticker"
	case *tg.SendMessageCancelAction:
		return "cancel"
	default:
		return "typing"
	}
}

func tgReactionEmoji(r tg.ReactionClass) string {
	switch v := r.(type) {
	case *tg.ReactionEmoji:
		return v.Emoticon
	case *tg.ReactionCustomEmoji:
		return fmt.Sprintf("custom_%d", v.DocumentID)
	case *tg.ReactionPaid:
		return "⭐"
	default:
		return "👍"
	}
}

func (t *TelegramCore) Authenticate(cfg AuthConfig) error {
	t.teardownPriorAuthAttempt()

	t.mu.Lock()

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
	if v, ok := cfg.Extra["device_model"]; ok && v != "" {
		t.customDeviceModel = v
	}
	t.initClient()
	t.ctx, t.cancel = context.WithCancel(context.Background())

	if cfg.Mode == AuthModeUser {
		if cfg.OTP == "" {
			t.authCodeCh = make(chan string, 1)
			t.authCodeReady = make(chan struct{})
		}
		if cfg.Password2F == "" {
			t.authPwdCh = make(chan string, 1)
			t.authPwdReady = make(chan struct{})
		}
		t.authSignUpCh = make(chan [2]string, 1)
		t.authSignUpReady = make(chan struct{})
		t.authEmailReady = make(chan struct{})
		t.emailSetupMode = false
		t.emailNewHash = ""
	}
	close(t.authSetupDone)

	t.mu.Unlock()

	authDone := make(chan struct{})
	errCh := make(chan error, 1)

	t.wg.Add(1)
	go func() {
		defer t.wg.Done()
		errCh <- t.client.Run(t.ctx, func(ctx context.Context) error {
			api := t.guardedClient()
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

				if cfg.OTP == "" {
					authFlow.codeCh = t.authCodeCh
					authFlow.codeReady = t.authCodeReady
				}
				if cfg.Password2F == "" {
					authFlow.pwdCh = t.authPwdCh
					authFlow.pwdReady = t.authPwdReady
				}
				authFlow.signUpCh = t.authSignUpCh
				authFlow.signUpReady = t.authSignUpReady
				authFlow.core = t

				t.mu.Lock()
				t.preAuthAPI = api
				t.mu.Unlock()

				flow := auth.NewFlow(authFlow, auth.SendCodeOptions{})
				authErr := t.client.Auth().IfNecessary(ctx, flow)
				if authErr != nil && strings.Contains(authErr.Error(), "SRP_ID_INVALID") && authFlow.lastPassword != "" {
					if pwd, getErr := api.AccountGetPassword(ctx); getErr == nil {
						if hash, hashErr := auth.PasswordHash(
							[]byte(authFlow.lastPassword),
							pwd.SRPID, pwd.SRPB, pwd.SecureRandom, pwd.CurrentAlgo,
						); hashErr == nil {
							if _, checkErr := api.AuthCheckPassword(ctx, hash); checkErr == nil {
								authErr = nil
							}
						}
					}
				}
				if authErr != nil {
					return fmt.Errorf("user auth: %w", authErr)
				}

			default:
				return fmt.Errorf("unknown auth mode: %s", cfg.Mode)
			}

			t.mu.Lock()
			t.api = api
			t.sender = sndr
			t.authed = true
			t.preAuthAPI = nil
			t.authPhoneHash = ""
			t.mu.Unlock()

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

			<-ctx.Done()
			return ctx.Err()
		})
	}()

	if cfg.Mode == AuthModeUser && cfg.OTP == "" {
		t.mu.Lock()
		t.authDoneCh = authDone
		t.authErrCh = errCh
		t.mu.Unlock()

		select {
		case <-authDone:
			return nil
		case <-t.authEmailReady:
			return fmt.Errorf("email_setup_required")
		case <-t.authCodeReady:
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
	case <-t.authSignUpReady:
		return fmt.Errorf("signup_required")
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

func (t *TelegramCore) SubmitSignUp(firstName, lastName string) error {
	if t.authSignUpCh == nil {
		return fmt.Errorf("no signup flow in progress")
	}
	t.authSignUpCh <- [2]string{firstName, lastName}

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
		return fmt.Errorf("%w: signup failed", ErrAuth)
	case <-time.After(30 * time.Second):
		return fmt.Errorf("%w: signup timed out", ErrAuth)
	}
}

func (t *TelegramCore) ResendOTPCode() error {
	t.mu.RLock()
	api := t.preAuthAPI
	hash := t.authPhoneHash
	phone := t.phone
	t.mu.RUnlock()
	if api == nil || hash == "" {
		return fmt.Errorf("no auth flow in progress")
	}
	_, err := api.AuthResendCode(t.ctx, &tg.AuthResendCodeRequest{
		PhoneNumber:   phone,
		PhoneCodeHash: hash,
	})
	return err
}

func (t *TelegramCore) AuthCodeInfo() (codeByTelegram bool, fragmentURL, emailPatternLogin string, timeout, length int) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.authCodeByTelegram, t.authCodeFragmentURL, t.authCodeEmailPattern, t.authCodeTimeout, t.authCodeLength
}

func (t *TelegramCore) EmailSetupRequired() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.emailSetupMode
}

func (t *TelegramCore) SetQRRefreshCallback(cb func()) {
	t.mu.Lock()
	t.qrRefreshCb = cb
	t.mu.Unlock()
}

func (t *TelegramCore) NoTelegramCode() (codeLength, timeout int, err error) {
	t.mu.RLock()
	api := t.preAuthAPI
	hash := t.authPhoneHash
	phone := t.phone
	t.mu.RUnlock()
	if api == nil || hash == "" {
		return 0, 0, fmt.Errorf("no auth flow in progress")
	}
	res, err := api.AuthResendCode(t.ctx, &tg.AuthResendCodeRequest{
		PhoneNumber:   phone,
		PhoneCodeHash: hash,
	})
	if err != nil {
		return 0, 0, err
	}
	sc, ok := res.(*tg.AuthSentCode)
	if !ok {
		return 0, 0, fmt.Errorf("unexpected resend result: %T", res)
	}
	length := 5
	if l, ok := sc.Type.(interface{ GetLength() int }); ok {
		length = l.GetLength()
	}
	timeout = sc.Timeout
	if timeout <= 0 {
		timeout = 60
	}
	t.mu.Lock()
	t.authPhoneHash = sc.PhoneCodeHash
	t.authCodeByTelegram = false
	t.authCodeFragmentURL = ""
	t.authCodeTimeout = timeout
	t.authCodeLength = length
	t.mu.Unlock()
	return length, timeout, nil
}

func (t *TelegramCore) SendVerifyEmailCodeDuringAuth(email string) (pattern string, length int, err error) {
	t.mu.RLock()
	api := t.preAuthAPI
	hash := t.authPhoneHash
	phone := t.phone
	t.mu.RUnlock()
	if api == nil {
		return "", 0, fmt.Errorf("no auth flow in progress")
	}
	res, err := api.AccountSendVerifyEmailCode(t.ctx, &tg.AccountSendVerifyEmailCodeRequest{
		Purpose: &tg.EmailVerifyPurposeLoginSetup{
			PhoneNumber:   phone,
			PhoneCodeHash: hash,
		},
		Email: email,
	})
	if err != nil {
		return "", 0, err
	}
	return res.EmailPattern, res.Length, nil
}

func (t *TelegramCore) VerifyEmailDuringAuth(code string) (phoneLength int, byTelegram bool, timeout int, err error) {
	t.mu.RLock()
	api := t.preAuthAPI
	phone := t.phone
	hash := t.authPhoneHash
	t.mu.RUnlock()
	if api == nil {
		return 0, false, 0, fmt.Errorf("no auth flow in progress")
	}
	res, err := api.AccountVerifyEmail(t.ctx, &tg.AccountVerifyEmailRequest{
		Purpose: &tg.EmailVerifyPurposeLoginSetup{
			PhoneNumber:   phone,
			PhoneCodeHash: hash,
		},
		Verification: &tg.EmailVerificationCode{Code: code},
	})
	if err != nil {
		return 0, false, 0, err
	}
	verified, ok := res.(*tg.AccountEmailVerifiedLogin)
	if !ok {
		return 0, false, 0, fmt.Errorf("unexpected email verify response: %T", res)
	}
	sc, ok := verified.SentCode.(*tg.AuthSentCode)
	if !ok {
		return 0, false, 0, fmt.Errorf("unexpected sent code after email verify: %T", verified.SentCode)
	}
	length := 5
	if l, ok := sc.Type.(interface{ GetLength() int }); ok {
		length = l.GetLength()
	}
	if _, isApp := sc.Type.(*tg.AuthSentCodeTypeApp); isApp {
		byTelegram = true
	}
	timeout = sc.Timeout
	t.mu.Lock()
	t.emailNewHash = sc.PhoneCodeHash
	t.authPhoneHash = sc.PhoneCodeHash
	t.authCodeByTelegram = byTelegram
	t.authCodeLength = length
	t.authCodeTimeout = timeout
	t.mu.Unlock()
	return length, byTelegram, timeout, nil
}

func (t *TelegramCore) SubmitPhoneCodeAfterEmail(code string) error {
	t.mu.RLock()
	api := t.preAuthAPI
	phone := t.phone
	hash := t.emailNewHash
	t.mu.RUnlock()
	if api == nil || hash == "" {
		return fmt.Errorf("no email auth flow in progress")
	}
	res, err := api.AuthSignIn(t.ctx, &tg.AuthSignInRequest{
		PhoneNumber:   phone,
		PhoneCodeHash: hash,
		PhoneCode:     code,
	})
	if err != nil {
		if strings.Contains(err.Error(), "SESSION_PASSWORD_NEEDED") {
			return fmt.Errorf("2fa_required")
		}
		return fmt.Errorf("%w: %s", ErrAuth, err)
	}
	switch a := res.(type) {
	case *tg.AuthAuthorization:
		t.finishEmailAuth(a)
		return nil
	case *tg.AuthAuthorizationSignUpRequired:
		return fmt.Errorf("signup_required")
	default:
		return fmt.Errorf("%w: unexpected sign-in response %T", ErrAuth, res)
	}
}

func (t *TelegramCore) finishEmailAuth(a *tg.AuthAuthorization) {
	t.mu.Lock()
	t.api = t.preAuthAPI
	t.authed = true
	t.emailSetupMode = false
	done := t.authDoneCh
	t.mu.Unlock()
	if u, ok := a.User.(*tg.User); ok {
		name := strings.TrimSpace(u.FirstName + " " + u.LastName)
		if name == "" {
			name = u.Username
		}
		t.mu.Lock()
		t.selfID = u.ID
		t.selfName = name
		t.mu.Unlock()
		t.peerMu.Lock()
		t.userAccessHash[u.ID] = u.AccessHash
		if name != "" {
			t.userNames[u.ID] = name
		}
		t.peerMu.Unlock()
	}
	if done != nil {
		select {
		case <-done:
		default:
			close(done)
		}
	}
}

func (t *TelegramCore) Submit2FAAfterEmail(password string) error {
	t.mu.RLock()
	api := t.preAuthAPI
	t.mu.RUnlock()
	if api == nil {
		return fmt.Errorf("no email auth flow in progress")
	}
	pwd, err := api.AccountGetPassword(t.ctx)
	if err != nil {
		return fmt.Errorf("%w: %s", ErrAuth, err)
	}
	hash, err := auth.PasswordHash(
		[]byte(password),
		pwd.SRPID, pwd.SRPB, pwd.SecureRandom, pwd.CurrentAlgo,
	)
	if err != nil {
		return fmt.Errorf("%w: %s", ErrAuth, err)
	}
	res, err := api.AuthCheckPassword(t.ctx, hash)
	if err != nil {
		return fmt.Errorf("%w: %s", ErrAuth, err)
	}
	a, ok := res.(*tg.AuthAuthorization)
	if !ok {
		return fmt.Errorf("%w: unexpected check-password response %T", ErrAuth, res)
	}
	t.finishEmailAuth(a)
	return nil
}

func (t *TelegramCore) Get2FAStateDuringAuth() (bool, string, error) {
	t.mu.RLock()
	api := t.api
	if api == nil {
		api = t.preAuthAPI
	}
	t.mu.RUnlock()
	if api == nil {
		return false, "", fmt.Errorf("no auth flow in progress")
	}
	pw, err := api.AccountGetPassword(t.ctx)
	if err != nil {
		return false, "", err
	}
	return pw.HasRecovery, pw.Hint, nil
}

func (t *TelegramCore) RequestRecoveryDuringAuth() (string, error) {
	t.mu.RLock()
	api := t.preAuthAPI
	t.mu.RUnlock()
	if api == nil {
		return "", fmt.Errorf("no auth flow in progress")
	}
	result, err := api.AuthRequestPasswordRecovery(t.ctx)
	if err != nil {
		return "", err
	}
	return result.EmailPattern, nil
}

func (t *TelegramCore) ResetPasswordDuringAuth() (map[string]interface{}, error) {
	t.mu.RLock()
	api := t.preAuthAPI
	t.mu.RUnlock()
	if api == nil {
		return nil, fmt.Errorf("no auth flow in progress")
	}
	result, err := api.AccountResetPassword(t.ctx)
	if err != nil {
		return nil, err
	}
	resp := map[string]interface{}{}
	switch v := result.(type) {
	case *tg.AccountResetPasswordOk:
		resp["status"] = "ok"
	case *tg.AccountResetPasswordRequestedWait:
		resp["status"] = "wait"
		resp["until_date"] = v.UntilDate
	case *tg.AccountResetPasswordFailedWait:
		resp["status"] = "failed"
		resp["until_date"] = v.RetryDate
	}
	return resp, nil
}

func isContextErr(err error) bool {
	return err == context.Canceled || err == context.DeadlineExceeded
}

func (t *TelegramCore) Logout() error {
	t.mu.Lock()
	api, ctx := t.api, t.ctx
	t.authed = false
	t.api = nil
	t.sender = nil
	cancel := t.cancel
	t.mu.Unlock()

	if api != nil {
		_, _ = api.AuthLogOut(ctx)
	}
	if cancel != nil {
		cancel()
	}
	return nil
}

func (t *TelegramCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
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

		result, err := api.MessagesGetDialogs(ctx, &tg.MessagesGetDialogsRequest{
			Limit:      batchLimit,
			OffsetDate: offsetDate,
			OffsetID:   offsetID,
			OffsetPeer: offsetPeer,
		})
		if err != nil {
			if len(allDialogs) > 0 {
				return allDialogs, nil
			}
			return nil, fmt.Errorf("get dialogs: %w", err)
		}

		batch, err := t.convertDialogs(result)
		if err != nil {
			return allDialogs, err
		}
		if len(batch) == 0 {
			break
		}

		allDialogs = append(allDialogs, batch...)

		if slice, ok := result.(*tg.MessagesDialogsSlice); ok {
			if len(allDialogs) >= slice.Count {
				break
			}
		} else {
			break
		}

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

func (t *TelegramCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	var scheduleDate int
	if sd, ok := msg.Extra["schedule_date"]; ok {
		switch v := sd.(type) {
		case float64:
			scheduleDate = int(v)
		case int64:
			scheduleDate = int(v)
		case int:
			scheduleDate = v
		}
	}

	var tgEntities []tg.MessageEntityClass
	for _, e := range msg.Entities {
		var ent tg.MessageEntityClass
		switch e.Type {
		case "bold":
			ent = &tg.MessageEntityBold{Offset: e.Offset, Length: e.Length}
		case "italic":
			ent = &tg.MessageEntityItalic{Offset: e.Offset, Length: e.Length}
		case "underline":
			ent = &tg.MessageEntityUnderline{Offset: e.Offset, Length: e.Length}
		case "strike":
			ent = &tg.MessageEntityStrike{Offset: e.Offset, Length: e.Length}
		case "code":
			if e.Language != "" {
				ent = &tg.MessageEntityPre{Offset: e.Offset, Length: e.Length, Language: e.Language}
			} else {
				ent = &tg.MessageEntityCode{Offset: e.Offset, Length: e.Length}
			}
		case "pre":
			ent = &tg.MessageEntityPre{Offset: e.Offset, Length: e.Length, Language: e.Language}
		case "spoiler":
			ent = &tg.MessageEntitySpoiler{Offset: e.Offset, Length: e.Length}
		case "text_url":
			ent = &tg.MessageEntityTextURL{Offset: e.Offset, Length: e.Length, URL: e.URL}
		case "blockquote":
			ent = &tg.MessageEntityBlockquote{Offset: e.Offset, Length: e.Length}
		case "custom_emoji":
			ent = &tg.MessageEntityCustomEmoji{Offset: e.Offset, Length: e.Length, DocumentID: e.DocumentID}
		case "formatted_date":
			ent = &tg.MessageEntityFormattedDate{
				Offset:    e.Offset,
				Length:    e.Length,
				Date:      e.Date,
				Relative:  e.DateRelative,
				ShortTime: e.DateShortTime,
				LongTime:  e.DateLongTime,
				ShortDate: e.DateShortDate,
				LongDate:  e.DateLongDate,
				DayOfWeek: e.DateDayOfWeek,
			}
		default:
			continue
		}
		tgEntities = append(tgEntities, ent)
	}

	var topicRootID int
	if trid, ok := msg.Extra["topic_root_id"]; ok {
		switch v := trid.(type) {
		case string:
			topicRootID, _ = strconv.Atoi(v)
		case float64:
			topicRootID = int(v)
		case int:
			topicRootID = v
		}
	}

	wpUrl, _ := msg.Extra["web_page_url"].(string)
	_, forceLarge := msg.Extra["force_large_media"]
	_, forceSmall := msg.Extra["force_small_media"]
	_, invertMedia := msg.Extra["invert_media"]
	_, wpOptional := msg.Extra["web_page_optional"]

	if wpUrl != "" && (forceLarge || forceSmall || invertMedia) {
		mediaReq := &tg.MessagesSendMediaRequest{
			Peer:     inputPeer,
			Message:  msg.Text,
			RandomID: time.Now().UnixNano(),
			Media: &tg.InputMediaWebPage{
				URL:             wpUrl,
				ForceLargeMedia: forceLarge,
				ForceSmallMedia: forceSmall,
				Optional:        wpOptional,
			},
		}
		if invertMedia {
			mediaReq.SetInvertMedia(true)
		}
		if len(tgEntities) > 0 {
			mediaReq.SetEntities(tgEntities)
		}
		if _, ok := msg.Extra["silent"]; ok {
			mediaReq.SetSilent(true)
		}
		if scheduleDate > 0 {
			mediaReq.SetScheduleDate(scheduleDate)
		}
		if msg.ReplyToID != "" {
			replyID, err := tgMsgID(msg.ReplyToID)
			if err != nil {
				return nil, err
			}
			reply := &tg.InputReplyToMessage{ReplyToMsgID: replyID}
			if topicRootID > 0 {
				reply.TopMsgID = topicRootID
			}
			mediaReq.SetReplyTo(reply)
		} else if topicRootID > 0 {
			mediaReq.SetReplyTo(&tg.InputReplyToMessage{TopMsgID: topicRootID})
		}
		result, err := api.MessagesSendMedia(ctx, mediaReq)
		if err != nil {
			return nil, fmt.Errorf("send message with web page: %w", err)
		}
		return t.extractMessageFromUpdates(result, chatID), nil
	}

	req := &tg.MessagesSendMessageRequest{
		Peer:     inputPeer,
		Message:  msg.Text,
		RandomID: time.Now().UnixNano(),
	}
	if len(tgEntities) > 0 {
		req.SetEntities(tgEntities)
	}
	if _, ok := msg.Extra["silent"]; ok {
		req.SetSilent(true)
	}
	if _, ok := msg.Extra["no_webpage"]; ok {
		req.SetNoWebpage(true)
	}
	if scheduleDate > 0 {
		req.SetScheduleDate(scheduleDate)
	}
	if strings.HasPrefix(msg.ReplyToID, "story:") {
		storyID, _ := strconv.Atoi(strings.TrimPrefix(msg.ReplyToID, "story:"))
		if storyID > 0 {
			req.SetReplyTo(&tg.InputReplyToStory{
				Peer:    inputPeer,
				StoryID: storyID,
			})
		}
	} else if msg.ReplyToID != "" {
		replyID, err := tgMsgID(msg.ReplyToID)
		if err != nil {
			return nil, err
		}
		reply := &tg.InputReplyToMessage{ReplyToMsgID: replyID}
		if topicRootID > 0 {
			reply.TopMsgID = topicRootID
		}
		req.SetReplyTo(reply)
	} else if topicRootID > 0 {
		req.SetReplyTo(&tg.InputReplyToMessage{TopMsgID: topicRootID})
	}

	result, err := api.MessagesSendMessage(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("send message: %w", err)
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) GetMessageByID(chatID string, msgID string) (*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	ids := []tg.InputMessageClass{&tg.InputMessageID{ID: id}}

	var result tg.MessagesMessagesClass
	if strings.HasPrefix(chatID, "-100") {
		peer, err := t.resolvePeer(chatID)
		if err != nil {
			return nil, err
		}
		ch, ok := peer.(*tg.PeerChannel)
		if !ok {
			return nil, fmt.Errorf("chat %s is not a channel", chatID)
		}
		hash, err := t.resolveChannelAccessHash(ch.ChannelID)
		if err != nil {
			return nil, fmt.Errorf("resolve channel %d access hash: %w", ch.ChannelID, err)
		}
		result, err = api.ChannelsGetMessages(ctx, &tg.ChannelsGetMessagesRequest{
			Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
			ID:      ids,
		})
		if err != nil {
			return nil, fmt.Errorf("get channel message: %w", err)
		}
	} else {
		var err error
		result, err = api.MessagesGetMessages(ctx, ids)
		if err != nil {
			return nil, fmt.Errorf("get message: %w", err)
		}
	}

	msgs := t.convertMessages(result)
	if len(msgs) == 0 {
		return nil, fmt.Errorf("message %s not found", msgID)
	}
	m := msgs[0]
	return &m, nil
}

func (t *TelegramCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
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

	result, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{
		Peer:     inputPeer,
		Limit:    limit,
		OffsetID: offsetID,
	})
	if err != nil {
		result, err = api.MessagesSearch(ctx, &tg.MessagesSearchRequest{
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

func (t *TelegramCore) GetPinnedMessages(chatID string) ([]Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesSearch(ctx, &tg.MessagesSearchRequest{
		Peer:   inputPeer,
		Q:      "",
		Filter: &tg.InputMessagesFilterPinned{},
		Limit:  50,
	})
	if err != nil {
		return nil, fmt.Errorf("get pinned messages: %w", err)
	}

	msgs := t.convertMessages(result)
	for i := range msgs {
		msgs[i].IsPinned = true
	}
	return msgs, nil
}

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

func (t *TelegramCore) EditMessageWithEntities(chatID string, msgID string, text string, entitiesJSON string) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}

	req := &tg.MessagesEditMessageRequest{
		Peer:    inputPeer,
		ID:      id,
		Message: text,
	}

	if entitiesJSON != "" {
		var entities []TextEntity
		if err := json.Unmarshal([]byte(entitiesJSON), &entities); err == nil && len(entities) > 0 {
			var tgEnts []tg.MessageEntityClass
			for _, e := range entities {
				var ent tg.MessageEntityClass
				switch e.Type {
				case "bold":
					ent = &tg.MessageEntityBold{Offset: e.Offset, Length: e.Length}
				case "italic":
					ent = &tg.MessageEntityItalic{Offset: e.Offset, Length: e.Length}
				case "underline":
					ent = &tg.MessageEntityUnderline{Offset: e.Offset, Length: e.Length}
				case "strike":
					ent = &tg.MessageEntityStrike{Offset: e.Offset, Length: e.Length}
				case "code":
					if e.Language != "" {
						ent = &tg.MessageEntityPre{Offset: e.Offset, Length: e.Length, Language: e.Language}
					} else {
						ent = &tg.MessageEntityCode{Offset: e.Offset, Length: e.Length}
					}
				case "pre":
					ent = &tg.MessageEntityPre{Offset: e.Offset, Length: e.Length, Language: e.Language}
				case "spoiler":
					ent = &tg.MessageEntitySpoiler{Offset: e.Offset, Length: e.Length}
				case "text_url":
					ent = &tg.MessageEntityTextURL{Offset: e.Offset, Length: e.Length, URL: e.URL}
				case "blockquote":
					ent = &tg.MessageEntityBlockquote{Offset: e.Offset, Length: e.Length}
				case "custom_emoji":
					ent = &tg.MessageEntityCustomEmoji{Offset: e.Offset, Length: e.Length, DocumentID: e.DocumentID}
				case "formatted_date":
					ent = &tg.MessageEntityFormattedDate{
						Offset:    e.Offset,
						Length:    e.Length,
						Date:      e.Date,
						Relative:  e.DateRelative,
						ShortTime: e.DateShortTime,
						LongTime:  e.DateLongTime,
						ShortDate: e.DateShortDate,
						LongDate:  e.DateLongDate,
						DayOfWeek: e.DateDayOfWeek,
					}
				default:
					continue
				}
				tgEnts = append(tgEnts, ent)
			}
			if len(tgEnts) > 0 {
				req.Entities = tgEnts
				req.SetFlags()
			}
		}
	}

	result, err := t.api.MessagesEditMessage(t.ctx, req)
	if err != nil {
		return nil, fmt.Errorf("edit message: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) DeleteMessage(chatID string, msgID string) error {
	return t.DeleteMessageRevoke(chatID, msgID, true)
}

func (t *TelegramCore) DeleteMessageRevoke(chatID string, msgID string, revoke bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}

	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}

	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = api.ChannelsDeleteMessages(ctx, &tg.ChannelsDeleteMessagesRequest{
			Channel: &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash},
			ID:      []int{id},
		})
	default:
		_, err = api.MessagesDeleteMessages(ctx, &tg.MessagesDeleteMessagesRequest{
			ID:     []int{id},
			Revoke: revoke,
		})
	}
	return err
}

func (t *TelegramCore) ReplyToMessage(chatID string, replyToMsgID string, msg OutgoingMessage) (*Message, error) {
	msg.ReplyToID = replyToMsgID
	return t.SendMessage(chatID, msg)
}

func (t *TelegramCore) ForwardMessage(fromChatID string, msgID string, toChatID string) (*Message, error) {
	return t.ForwardMessageWithOptions(fromChatID, msgID, toChatID, ForwardOptions{})
}

func (t *TelegramCore) ForwardMessageWithOptions(fromChatID, msgID, toChatID string, opts ForwardOptions) (*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
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

	req := &tg.MessagesForwardMessagesRequest{
		FromPeer: fromInput,
		ToPeer:   toInput,
		ID:       []int{id},
		RandomID: []int64{time.Now().UnixNano()},
	}
	req.SetDropAuthor(opts.DropAuthor)
	req.SetDropMediaCaptions(opts.DropCaptions)
	req.SetSilent(opts.Silent)
	if opts.ScheduleDate > 0 {
		req.SetScheduleDate(int(opts.ScheduleDate))
	}

	result, err := api.MessagesForwardMessages(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("forward message: %w", err)
	}

	return t.extractMessageFromUpdates(result, toChatID), nil
}

func (t *TelegramCore) ForwardMessagesWithOptions(fromChatID string, msgIDs []string, toChatID string, opts ForwardOptions) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	fromPeer, err := t.resolvePeer(fromChatID)
	if err != nil {
		return err
	}
	toPeer, err := t.resolvePeer(toChatID)
	if err != nil {
		return err
	}

	fromInput, _ := t.toInputPeer(fromPeer)
	toInput, _ := t.toInputPeer(toPeer)

	ids := make([]int, 0, len(msgIDs))
	randomIDs := make([]int64, 0, len(msgIDs))
	for _, mid := range msgIDs {
		id, err := tgMsgID(mid)
		if err != nil {
			return err
		}
		ids = append(ids, id)
		randomIDs = append(randomIDs, time.Now().UnixNano()+int64(len(randomIDs)))
	}

	req := &tg.MessagesForwardMessagesRequest{
		FromPeer: fromInput,
		ToPeer:   toInput,
		ID:       ids,
		RandomID: randomIDs,
	}
	req.SetDropAuthor(opts.DropAuthor)
	req.SetDropMediaCaptions(opts.DropCaptions)
	req.SetSilent(opts.Silent)
	if opts.ScheduleDate > 0 {
		req.SetScheduleDate(int(opts.ScheduleDate))
	}

	_, err = api.MessagesForwardMessages(ctx, req)
	if err != nil {
		return fmt.Errorf("forward messages batch: %w", err)
	}
	return nil
}

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

	var reaction tg.ReactionClass
	if strings.HasPrefix(emoji, "custom_") {
		docID, parseErr := strconv.ParseInt(emoji[7:], 10, 64)
		if parseErr == nil {
			reaction = &tg.ReactionCustomEmoji{DocumentID: docID}
		} else {
			reaction = &tg.ReactionEmoji{Emoticon: emoji}
		}
	} else {
		reaction = &tg.ReactionEmoji{Emoticon: emoji}
	}
	_, err = t.api.MessagesSendReaction(t.ctx, &tg.MessagesSendReactionRequest{
		Peer:     inputPeer,
		MsgID:    id,
		Reaction: []tg.ReactionClass{reaction},
	})
	return err
}

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
		Peer: inputPeer,
		ID:   id,
	})
	return err
}

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
		Peer:  inputPeer,
		ID:    id,
		Unpin: true,
	})
	return err
}

func (t *TelegramCore) MarkAsRead(chatID string, upToMsgID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	id, err := tgMsgID(upToMsgID)
	if err != nil {
		return err
	}

	if ch, ok := peer.(*tg.PeerChannel); ok {
		hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
		_, err = api.ChannelsReadHistory(ctx, &tg.ChannelsReadHistoryRequest{
			Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
			MaxID:   id,
		})
		return err
	}

	inputPeer, _ := t.toInputPeer(peer)
	_, err = api.MessagesReadHistory(ctx, &tg.MessagesReadHistoryRequest{
		Peer:  inputPeer,
		MaxID: id,
	})
	return err
}

func (t *TelegramCore) GetReadState(chatID string) (*ReadState, error) {
	return &ReadState{
		PeerLastRead: make(map[string]string),
	}, nil
}

func (t *TelegramCore) UploadFile(chatID string, file FileUpload, progress func(sent, total int64)) (*Message, error) {
	api, ctx, sender, err := t.withSenderAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(api)
	if progress != nil {
		u = u.WithProgress(&uploadProgress{callback: progress, total: file.Size})
	}

	upload, err := u.Upload(ctx, uploader.NewUpload(file.Name, io.NopCloser(file.Reader), file.Size))
	if err != nil {
		return nil, fmt.Errorf("upload: %w", err)
	}

	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	target := sender.To(inputPeer)

	var result tg.UpdatesClass

	switch {
	case strings.HasPrefix(file.MimeType, "image/"):
		photo := message.UploadedPhoto(upload)
		result, err = target.Media(ctx, photo)

	case strings.HasPrefix(file.MimeType, "video/"):
		doc := message.UploadedDocument(upload).
			MIME(file.MimeType).
			Filename(file.Name).
			Video()
		result, err = target.Media(ctx, doc)

	case file.MimeType == "audio/ogg" || file.MimeType == "audio/opus" || strings.HasSuffix(file.Name, ".ogg"):
		doc := message.UploadedDocument(upload).
			MIME("audio/ogg").
			Filename(file.Name).
			Voice()
		result, err = target.Media(ctx, doc)

	case strings.HasPrefix(file.MimeType, "audio/"):
		doc := message.UploadedDocument(upload).
			MIME(file.MimeType).
			Filename(file.Name).
			Audio()
		result, err = target.Media(ctx, doc)

	default:
		doc := message.UploadedDocument(upload).
			MIME(file.MimeType).
			Filename(file.Name)
		result, err = target.Media(ctx, doc)
	}

	if err != nil {
		return nil, fmt.Errorf("send file: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) UploadFileWithOptions(chatID string, file FileUpload, opts UploadOptions, progress func(sent, total int64)) (*Message, error) {
	api, ctx, sender, err := t.withSenderAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(api)
	if progress != nil {
		u = u.WithProgress(&uploadProgress{callback: progress, total: file.Size})
	}

	upload, err := u.Upload(ctx, uploader.NewUpload(file.Name, io.NopCloser(file.Reader), file.Size))
	if err != nil {
		return nil, fmt.Errorf("upload: %w", err)
	}

	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	caption := t.buildStyledCaption(opts.Caption, opts.CaptionEntities)

	var thumbUpload tg.InputFileClass
	if opts.VideoCoverPath != "" {
		coverFile, err := os.Open(opts.VideoCoverPath)
		if err == nil {
			info, _ := coverFile.Stat()
			coverName := info.Name()
			coverSize := info.Size()
			thumbUpload, err = u.Upload(ctx, uploader.NewUpload(coverName, coverFile, coverSize))
			if err != nil {
				coverFile.Close()
				thumbUpload = nil
			} else {
				coverFile.Close()
			}
		}
	}

	var media message.MediaOption
	switch {
	case opts.IsVoice:
		media = message.UploadedDocument(upload, caption...).MIME("audio/ogg").Filename(file.Name).Voice()
	case opts.IsVideoNote:
		attrs := []tg.DocumentAttributeClass{
			&tg.DocumentAttributeVideo{
				RoundMessage: true,
				W:            opts.Width,
				H:            opts.Height,
				Duration:     float64(opts.Duration),
			},
		}
		media = message.UploadedDocument(upload, caption...).MIME("video/mp4").Filename(file.Name).Attributes(attrs...)
	case strings.HasPrefix(file.MimeType, "image/"):
		media = message.UploadedPhoto(upload, caption...)
	case strings.HasPrefix(file.MimeType, "video/"):
		doc := message.UploadedDocument(upload, caption...).MIME(file.MimeType).Filename(file.Name)
		if thumbUpload != nil {
			doc = doc.Thumb(thumbUpload)
		}
		media = doc.Video()
	case file.MimeType == "audio/ogg" || file.MimeType == "audio/opus":
		media = message.UploadedDocument(upload, caption...).MIME("audio/ogg").Filename(file.Name).Voice()
	case strings.HasPrefix(file.MimeType, "audio/"):
		media = message.UploadedDocument(upload, caption...).MIME(file.MimeType).Filename(file.Name).Audio()
	default:
		media = message.UploadedDocument(upload, caption...).MIME(file.MimeType).Filename(file.Name)
	}

	builder := sender.To(inputPeer).CloneBuilder()
	if opts.Silent {
		builder = builder.Silent()
	}
	if opts.ScheduleDate > 0 {
		builder = builder.ScheduleTS(int(opts.ScheduleDate))
	}

	result, err := builder.Media(ctx, media)
	if err != nil {
		return nil, fmt.Errorf("send file: %w", err)
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) buildStyledCaption(text, entitiesJSON string) []styling.StyledTextOption {
	if text == "" {
		return nil
	}
	if entitiesJSON == "" {
		return []styling.StyledTextOption{styling.Plain(text)}
	}
	var entities []TextEntity
	if err := json.Unmarshal([]byte(entitiesJSON), &entities); err != nil {
		return []styling.StyledTextOption{styling.Plain(text)}
	}
	if len(entities) == 0 {
		return []styling.StyledTextOption{styling.Plain(text)}
	}
	sort.Slice(entities, func(i, j int) bool { return entities[i].Offset < entities[j].Offset })
	runes := []rune(text)
	var opts []styling.StyledTextOption
	pos := 0
	for _, e := range entities {
		end := e.Offset + e.Length
		if end > len(runes) {
			end = len(runes)
		}
		if e.Offset < pos || e.Offset >= len(runes) {
			continue
		}
		if e.Offset > pos {
			opts = append(opts, styling.Plain(string(runes[pos:e.Offset])))
		}
		substr := string(runes[e.Offset:end])
		switch e.Type {
		case "bold":
			opts = append(opts, styling.Bold(substr))
		case "italic":
			opts = append(opts, styling.Italic(substr))
		case "underline":
			opts = append(opts, styling.Underline(substr))
		case "strike":
			opts = append(opts, styling.Strike(substr))
		case "code":
			opts = append(opts, styling.Code(substr))
		case "pre":
			opts = append(opts, styling.Pre(substr, e.Language))
		case "spoiler":
			opts = append(opts, styling.Spoiler(substr))
		case "text_url":
			opts = append(opts, styling.TextURL(substr, e.URL))
		case "blockquote":
			opts = append(opts, styling.Blockquote(substr, false))
		case "custom_emoji":
			opts = append(opts, styling.CustomEmoji(substr, e.DocumentID))
		case "formatted_date":
			opts = append(opts, styling.FormattedDate(substr, e.DateRelative, e.DateShortTime, e.DateLongTime, e.DateShortDate, e.DateLongDate, e.DateDayOfWeek, e.Date))
		default:
			opts = append(opts, styling.Plain(substr))
		}
		pos = end
	}
	if pos < len(runes) {
		opts = append(opts, styling.Plain(string(runes[pos:])))
	}
	return opts
}

func (t *TelegramCore) SendMediaAlbum(chatID string, items []AlbumItem, silent bool, scheduleDate int64) ([]*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(api)
	var multiMedia []tg.InputSingleMedia

	for _, item := range items {
		upload, err := u.Upload(ctx, uploader.NewUpload(item.Upload.Name, io.NopCloser(item.Upload.Reader), item.Upload.Size))
		if err != nil {
			return nil, fmt.Errorf("upload album item %s: %w", item.Upload.Name, err)
		}

		var inputMedia tg.InputMediaClass
		if item.IsPhoto {
			inputMedia = &tg.InputMediaUploadedPhoto{
				File: upload,
			}
		} else {
			attrs := []tg.DocumentAttributeClass{
				&tg.DocumentAttributeFilename{FileName: item.Upload.Name},
			}
			if strings.HasPrefix(item.Upload.MimeType, "video/") {
				attrs = append(attrs, &tg.DocumentAttributeVideo{})
			}
			inputMedia = &tg.InputMediaUploadedDocument{
				File:       upload,
				MimeType:   item.Upload.MimeType,
				Attributes: attrs,
			}
		}

		entry := tg.InputSingleMedia{
			RandomID: time.Now().UnixNano() + int64(len(multiMedia)),
			Media:    inputMedia,
		}
		if item.Caption != "" {
			entry.Message = item.Caption
		}
		multiMedia = append(multiMedia, entry)
	}

	req := &tg.MessagesSendMultiMediaRequest{
		Peer:       inputPeer,
		MultiMedia: multiMedia,
		Silent:     silent,
	}
	if scheduleDate > 0 {
		req.ScheduleDate = int(scheduleDate)
		req.SetFlags()
	}

	result, err := api.MessagesSendMultiMedia(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("send album: %w", err)
	}

	var msgs []*Message
	if m := t.extractMessageFromUpdates(result, chatID); m != nil {
		msgs = append(msgs, m)
	}
	return msgs, nil
}

func (t *TelegramCore) DownloadFile(fileRef FileRef, dest string, progress func(recv, total int64)) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	location, err := t.FileLocationOf(fileRef)
	if err != nil {
		return err
	}

	f, err := os.Create(dest)
	if err != nil {
		return fmt.Errorf("create file: %w", err)
	}
	defer f.Close()

	d := downloader.NewDownloader()
	_, err = d.Download(api, location).Stream(ctx, f)
	if err != nil {
		os.Remove(dest)
		return fmt.Errorf("download: %w", err)
	}

	return nil
}

func (t *TelegramCore) DownloadChatAvatar(chatID, destPath string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return fmt.Errorf("resolve peer: %w", err)
	}

	var rawID int64
	switch p := inputPeer.(type) {
	case *tg.InputPeerUser:
		rawID = p.UserID
	case *tg.InputPeerChat:
		rawID = p.ChatID
	case *tg.InputPeerChannel:
		rawID = p.ChannelID
	}
	unlock()

	t.peerMu.RLock()
	photoID, ok := t.peerPhotoID[rawID]
	t.peerMu.RUnlock()
	if !ok || photoID == 0 {
		return fmt.Errorf("no photo for peer %s", chatID)
	}

	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
	_, err = d.Download(api, location).Stream(ctx, f)
	if err != nil {
		os.Remove(destPath)
		return fmt.Errorf("download avatar: %w", err)
	}

	return nil
}

func (t *TelegramCore) getUserAvatarB64(userID int64) string {
	t.peerMu.RLock()
	photoID, ok := t.peerPhotoID[userID]
	t.peerMu.RUnlock()
	if !ok || photoID == 0 {
		return ""
	}

	userIDStr := strconv.FormatInt(userID, 10)
	inputPeer := &tg.InputPeerUser{UserID: userID}
	t.peerMu.RLock()
	hash, hasHash := t.userAccessHash[userID]
	t.peerMu.RUnlock()
	if hasHash {
		inputPeer.AccessHash = hash
	}

	location := &tg.InputPeerPhotoFileLocation{
		Peer:    inputPeer,
		PhotoID: photoID,
	}

	tmpFile, err := os.CreateTemp("", "avatar_"+userIDStr+"_*.jpg")
	if err != nil {
		return ""
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	d := downloader.NewDownloader()
	_, err = d.Download(t.api, location).Stream(t.ctx, tmpFile)
	tmpFile.Close()
	if err != nil {
		return ""
	}

	data, err := os.ReadFile(tmpPath)
	if err != nil || len(data) == 0 {
		return ""
	}
	return base64.StdEncoding.EncodeToString(data)
}

func (t *TelegramCore) GetUserAvatarThumb(userID string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	id, err := tgUserID(userID)
	if err != nil {
		return "", err
	}
	inputUser := &tg.InputUser{UserID: id, AccessHash: t.getCachedUserHash(id)}
	users, err := api.UsersGetUsers(ctx, []tg.InputUserClass{inputUser})
	if err != nil {
		return "", err
	}
	for _, u := range users {
		if user, ok := u.(*tg.User); ok && user.ID == id {
			cu := t.convertUser(user)
			if cu.AvatarB64 != "" {
				return cu.AvatarB64, nil
			}
			break
		}
	}
	return t.getUserAvatarB64(id), nil
}

func (t *TelegramCore) SendImageBase64(chatID string, b64 string, caption string) (*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	imgData, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, fmt.Errorf("decode base64: %w", err)
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, _ := t.toInputPeer(peer)

	u := uploader.NewUploader(api)
	upload, err := u.FromBytes(ctx, "image.png", imgData)
	if err != nil {
		return nil, fmt.Errorf("upload image: %w", err)
	}

	updates, err := api.MessagesSendMedia(ctx, &tg.MessagesSendMediaRequest{
		Peer:     inputPeer,
		Media:    &tg.InputMediaUploadedPhoto{File: upload},
		Message:  caption,
		RandomID: time.Now().UnixNano(),
	})
	if err != nil {
		return nil, err
	}

	msg := t.extractMessageFromUpdates(updates, chatID)
	if msg != nil {
		return msg, nil
	}
	return &Message{ChatID: chatID, Text: caption, IsOutgoing: true, Platform: tgPlatform}, nil
}

func (t *TelegramCore) SendContact(chatID string, phone string, firstName string, lastName string, userID string) (*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}

	media := &tg.InputMediaContact{
		PhoneNumber: phone,
		FirstName:   firstName,
		LastName:    lastName,
	}
	if userID != "" {
		media.Vcard = "BEGIN:VCARD\nVERSION:3.0\nFN:" + firstName + " " + lastName + "\nTEL:" + phone + "\nEND:VCARD"
	}

	result, err := api.MessagesSendMedia(ctx, &tg.MessagesSendMediaRequest{
		Peer:     inputPeer,
		Media:    media,
		Message:  "",
		RandomID: time.Now().UnixNano(),
	})
	if err != nil {
		return nil, fmt.Errorf("send contact: %w", err)
	}

	msg := t.extractMessageFromUpdates(result, chatID)
	if msg != nil {
		return msg, nil
	}
	return &Message{ChatID: chatID, IsOutgoing: true, Platform: tgPlatform}, nil
}

type tgCall struct {
	id          int64
	accessHash  int64
	peerID      int64
	isOutgoing  bool
	isVideo     bool
	isGroupCall bool
	authKey     [256]byte

	pc                  *wrtc.PeerConnection
	audioTrack          *wrtc.TrackLocalStaticRTP
	videoTrack          *wrtc.TrackLocalStaticSample
	state               CallState
	muted               bool
	cancel              context.CancelFunc
	done                chan struct{}
	p2pAllowed          bool
	conferenceSupported bool

	fpValues      [4]uint64
	fpReady       bool
	connectedAtMs int64
	signalBars    int

	lastParticipants   []CallParticipant
	lastParticipantsMu sync.Mutex

	gcChatID          string
	gcJoinMuted       bool
	gcMessagesEnabled bool
	gcSettingsLoaded  bool
	gcSettingsMu      sync.Mutex
	noiseSuppression  bool

	audioLevels  map[uint32]float64
	audioLevelTs map[uint32]int64
	ssrcToUser   map[uint32]string
	audioLevelMu sync.Mutex

	onAudioFrame func(frame []byte)

	onVideoFrame        func(frame []byte)
	onDecodedVideoFrame func(yuv420p []byte, width, height int)

	echoMode      bool
	externalAudio bool

	audioSeq         uint32
	audioTS          uint32
	audioSSRC        uint32
	audioTSIncrement uint32

	videoSSRC    uint32
	videoEncoder VideoEncoder

	screenTrack          *wrtc.TrackLocalStaticSample
	onScreenFrame        func(frame []byte)
	onDecodedScreenFrame func(yuv420p []byte, width, height int)
	screenSSRC           uint32
	screenActive         bool
	screenEncoder        VideoEncoder

	videoFrameBuf  []byte
	screenFrameBuf []byte

	videoDecoder VideoDecoder

	remoteVideoSSRC  uint32
	remoteScreenSSRC uint32

	recording     bool
	recordingFile *os.File
	recordingMu   sync.Mutex

	incomingFrameMu     sync.Mutex
	incomingCameraFrame []byte
	incomingCameraW     int
	incomingCameraH     int
	incomingScreenFrame []byte
	incomingScreenW     int
	incomingScreenH     int

	outgoingFrameMu     sync.Mutex
	outgoingCameraFrame []byte
	outgoingCameraW     int
	outgoingCameraH     int
	outgoingScreenFrame []byte
	outgoingScreenW     int
	outgoingScreenH     int

	sigCounter uint32

	mu                sync.Mutex
	localSetupSent    bool
	remoteSDPSet      bool
	remoteOfferCount  int
	dtlsRole          string
	localSDP          string
	pendingCandidates []webrtc.ICECandidateInit
	localSDPReady     chan struct{}
	pcReady           chan struct{}
	pcReadyOnce       sync.Once

	useV2Sig     bool
	sctpConn     *sctpSignalingConn
	sctpAssoc    *sctp.Association
	sctpStream   *sctp.Stream
	sctpReady    chan struct{}
	v2SigCounter uint32

	useWebSignaling bool

	useV2Impl              bool
	useV1Framing           bool
	remoteInitialSetup     *TgInitialSetup
	remoteNegChannels      *tgNegotiateChannels
	remoteNegChannelsOffer *tgNegotiateChannels
	v2ImplExchangeSeq      uint32
	v2ImplHandshakeDone    bool
	answeredExchangeIDs    map[string]bool

	useInstanceImpl   bool
	iceAgent          *ice.Agent
	iceConn           *ice.Conn
	transportCounter  uint32
	sigEncCounter     uint32
	pendingAcks       []uint32
	instanceImplReady chan struct{}
	remoteUfrag       string
	remotePwd         string
	remoteCredsReady  chan struct{}

	remoteMuted           bool
	remoteVideoState      string
	remoteScreencastState string
	remoteVideoRotation   int
	remoteLowBattery      bool

	sfuTransportReady chan struct{}
	sfuTransportJSON  string

	sfuDataChannel       *webrtc.DataChannel
	sfuDataChannelOpen   chan struct{}
	sfuRemoteVideoEndpts map[string]string
	sfuRemoteVideoMu     sync.Mutex

	skipWebRTC  bool
	connections []tg.PhoneConnectionClass
	protocol    *tg.PhoneCallProtocol
	dhDone      chan struct{}
}

type TgInitialSetup struct {
	Type         string              `json:"@type"`
	Ufrag        string              `json:"ufrag"`
	Pwd          string              `json:"pwd"`
	Renomination bool                `json:"renomination"`
	Fingerprints []TgDTLSFingerprint `json:"fingerprints"`
	Audio        *tgMediaDesc        `json:"audio,omitempty"`
	Video        *tgMediaDesc        `json:"video,omitempty"`
	Screencast   *tgMediaDesc        `json:"screencast,omitempty"`
}

type tgMediaDesc struct {
	SSRC          string           `json:"ssrc"`
	SSRCGroups    []tgWebSSRCGroup `json:"ssrcGroups"`
	PayloadTypes  []tgPayloadType  `json:"payloadTypes"`
	RTPExtensions []tgRTPExtension `json:"rtpExtensions"`
}

type tgWebSSRCGroup struct {
	Semantics string `json:"semantics,omitempty"`
	SSRCs     []int  `json:"ssrcs"`
}

type TgDTLSFingerprint struct {
	Hash        string `json:"hash"`
	Setup       string `json:"setup"`
	Fingerprint string `json:"fingerprint"`
}

type tgNegotiateChannels struct {
	Type       string           `json:"@type"`
	ExchangeID string           `json:"exchangeId"`
	Contents   []TgMediaContent `json:"contents"`
}

type TgMediaContent struct {
	Type          string           `json:"type"`
	SSRC          string           `json:"ssrc"`
	SSRCGroups    []tgSSRCGroup    `json:"ssrcGroups,omitempty"`
	PayloadTypes  []tgPayloadType  `json:"payloadTypes"`
	RTPExtensions []tgRTPExtension `json:"rtpExtensions"`
}

type tgSSRCGroup struct {
	Semantics string   `json:"semantics"`
	SSRCs     []string `json:"ssrcs"`
}

type tgPayloadType struct {
	ID            int               `json:"id"`
	Name          string            `json:"name"`
	Clockrate     int               `json:"clockrate"`
	Channels      int               `json:"channels,omitempty"`
	FeedbackTypes []tgFeedbackType  `json:"feedbackTypes,omitempty"`
	Parameters    map[string]string `json:"parameters,omitempty"`
}

type tgFeedbackType struct {
	Type    string `json:"type"`
	Subtype string `json:"subtype"`
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
	Type            string `json:"@type"`
	Muted           bool   `json:"muted"`
	VideoState      string `json:"videoState"`
	VideoRotation   int    `json:"videoRotation"`
	ScreencastState string `json:"screencastState"`
	LowBattery      bool   `json:"lowBattery"`
}

func UnmarshalCallSignal(data []byte, v any) error {
	if err := json.Unmarshal(data, v); err != nil {
		return fmt.Errorf("call signal parse: %w", err)
	}
	return nil
}

func FingerprintLabel(setup TgInitialSetup) string {
	if len(setup.Fingerprints) == 0 {
		return "none"
	}
	return setup.Fingerprints[0].Setup
}

func FirstSSRC(contents []TgMediaContent) string {
	if len(contents) == 0 {
		return ""
	}
	return contents[0].SSRC
}

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

	meta := map[string]string{
		"remote_muted":            strconv.FormatBool(ms.Muted),
		"remote_video_state":      ms.VideoState,
		"remote_screencast_state": ms.ScreencastState,
		"remote_video_rotation":   strconv.Itoa(ms.VideoRotation),
		"remote_low_battery":      strconv.FormatBool(ms.LowBattery),
		"conference_supported":    strconv.FormatBool(call.conferenceSupported),
	}
	for k, v := range call.callStatusMeta() {
		meta[k] = v
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

func (c *tgCall) callStatusMeta() map[string]string {
	c.mu.Lock()
	defer c.mu.Unlock()
	m := make(map[string]string, 6)
	if c.fpReady {
		m["fingerprint"] = fmt.Sprintf("%d,%d,%d,%d",
			c.fpValues[0], c.fpValues[1], c.fpValues[2], c.fpValues[3])
	}
	if c.connectedAtMs > 0 {
		m["connect_time_ms"] = strconv.FormatInt(c.connectedAtMs, 10)
	}
	if c.signalBars > 0 {
		m["signal_bars"] = strconv.Itoa(c.signalBars)
	}
	m["is_muted"] = strconv.FormatBool(c.muted)
	m["is_camera_on"] = strconv.FormatBool(c.isVideo)
	m["is_screen_sharing"] = strconv.FormatBool(c.screenActive)
	return m
}

func (t *TelegramCore) fireCallStateUpdate(call *tgCall) {
	if call == nil {
		return
	}
	call.mu.Lock()
	meta := map[string]string{
		"remote_muted":            strconv.FormatBool(call.remoteMuted),
		"remote_video_state":      call.remoteVideoState,
		"remote_screencast_state": call.remoteScreencastState,
		"remote_video_rotation":   strconv.Itoa(call.remoteVideoRotation),
		"remote_low_battery":      strconv.FormatBool(call.remoteLowBattery),
		"conference_supported":    strconv.FormatBool(call.conferenceSupported),
		"is_muted":                strconv.FormatBool(call.muted),
		"is_camera_on":            strconv.FormatBool(call.isVideo),
		"is_screen_sharing":       strconv.FormatBool(call.screenActive),
	}
	if call.fpReady {
		meta["fingerprint"] = fmt.Sprintf("%d,%d,%d,%d",
			call.fpValues[0], call.fpValues[1], call.fpValues[2], call.fpValues[3])
	}
	if call.connectedAtMs > 0 {
		meta["connect_time_ms"] = strconv.FormatInt(call.connectedAtMs, 10)
	}
	if call.signalBars > 0 {
		meta["signal_bars"] = strconv.Itoa(call.signalBars)
	}
	state := call.state
	id := call.id
	call.mu.Unlock()
	t.fireUpdate(Update{
		Type:     UpdateCallState,
		Platform: tgPlatform,
		Call: &CallSession{
			ID:    strconv.FormatInt(id, 10),
			State: state,
			Meta:  meta,
		},
	})
}

func (c *tgCall) markCallConnected() {
	if c.connectedAtMs == 0 {
		c.connectedAtMs = time.Now().UnixMilli()
	}
	c.signalBars = tgCallSignalBarCount
}

const tgCallSignalBarCount = 4

func computeEmojiFingerprintValues(authKey, gA []byte) [4]uint64 {
	ga := gA
	if len(ga) < 256 {
		padded := make([]byte, 256)
		copy(padded[256-len(ga):], ga)
		ga = padded
	}
	h := sha256.New()
	h.Write(authKey)
	h.Write(ga)
	sum := h.Sum(nil)
	var vals [4]uint64
	for i := 0; i < 4; i++ {
		b := sum[i*8 : i*8+8]
		vals[i] = (uint64(b[0]&0x7f) << 56) |
			(uint64(b[1]) << 48) |
			(uint64(b[2]) << 40) |
			(uint64(b[3]) << 32) |
			(uint64(b[4]) << 24) |
			(uint64(b[5]) << 16) |
			(uint64(b[6]) << 8) |
			uint64(b[7])
	}
	return vals
}

func isV2ImplVersion(v string) bool {
	return v == "8.0.0" || v == "13.0.0"
}

func isV3Transport(v string) bool {
	return v == "13.0.0"
}

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
		return versions
	}
	return filtered
}

func isWebVersion(v string) bool {
	switch v {
	case "4.0.0", "4.0.1":
		return true
	}
	return false
}

const (
	instanceMsgCandidatesList    = 1
	instanceMsgVideoFormats      = 2
	instanceMsgRequestVideo      = 3
	instanceMsgRemoteMediaState  = 4
	instanceMsgAudioData         = 5
	instanceMsgVideoData         = 6
	instanceMsgUnstructuredData  = 7
	instanceMsgVideoParameters   = 8
	instanceMsgBatteryLevelIsLow = 9
	instanceMsgNetworkStatus     = 10
	instanceMsgAck               = 0xFF
	instanceMsgEmpty             = 0xFE
)

const (
	seqSingleMessageBit = uint32(1) << 31
	seqRequiresAckBit   = uint32(1) << 30
)

const (
	instanceSSRCAudioIncoming = 1
	instanceSSRCAudioOutgoing = 2
	instanceSSRCVideoIncoming = 3
	instanceSSRCVideoOutgoing = 4
)

func serializeInstanceImplString(buf *bytes.Buffer, s string) {
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(s)))
	buf.Write(lenBuf[:])
	buf.WriteString(s)
}

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

func serializeCandidatesListMsg(candidates []string, ufrag, pwd string) []byte {
	var buf bytes.Buffer
	buf.WriteByte(byte(len(candidates)))
	for _, c := range candidates {
		if !strings.HasPrefix(c, "candidate:") {
			c = "candidate:" + c
		}
		serializeInstanceImplString(&buf, c)
	}
	serializeInstanceImplString(&buf, ufrag)
	serializeInstanceImplString(&buf, pwd)
	return buf.Bytes()
}

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
	pwd, _, err = deserializeInstanceImplString(data, pos)
	if err != nil {
		return nil, "", "", fmt.Errorf("CandidatesList: pwd: %w", err)
	}
	return candidates, ufrag, pwd, nil
}

func serializeVideoFormatsMsg() []byte {
	return []byte{0, 0}
}

func serializeRemoteMediaStateMsg(audioActive bool, videoState int) []byte {
	state := byte(0)
	if audioActive {
		state |= 1
	}
	state |= byte(videoState&0x03) << 1
	return []byte{state}
}

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

func instanceImplSerializeMsg(typeID byte, data []byte, counter *uint32, requiresAck bool) []byte {
	seq := atomic.AddUint32(counter, 1)

	singleMessage := !requiresAck
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

func instanceImplAppendAcks(buf []byte, ackSeqs []uint32) []byte {
	for _, ackSeq := range ackSeqs {
		var ackBuf [5]byte
		binary.BigEndian.PutUint32(ackBuf[:4], ackSeq)
		ackBuf[4] = instanceMsgAck
		buf = append(buf, ackBuf[:]...)
	}
	return buf
}

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

func tgDecryptInstanceImplSignaling(key []byte, packet []byte, isOutgoing bool) ([]instanceImplMsg, error) {
	if len(packet) < 21 {
		return nil, fmt.Errorf("InstanceImpl signaling too short: %d", len(packet))
	}

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

	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	check := h.Sum(nil)
	if !bytes.Equal(check[8:24], msgKey) {
		return nil, fmt.Errorf("InstanceImpl signaling: msgKey mismatch")
	}

	return parseInstanceImplMessages(plaintext)
}

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

func tgDecryptTransport(key []byte, packet []byte, isOutgoing bool) ([]instanceImplMsg, error) {
	if len(packet) < 21 {
		return nil, fmt.Errorf("InstanceImpl transport too short: %d", len(packet))
	}

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
	Seq    uint32
}

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
		case instanceMsgAck:
			messages = append(messages, instanceImplMsg{TypeID: typeID, Seq: seq})
		case instanceMsgAudioData, instanceMsgVideoData:
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
		case instanceMsgUnstructuredData:
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
			remaining := plaintext[pos:]
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: remaining, Seq: seq})
			pos = len(plaintext)
		case instanceMsgVideoFormats:
			remaining := plaintext[pos:]
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: remaining, Seq: seq})
			pos = len(plaintext)
		case instanceMsgRemoteMediaState:
			if pos < len(plaintext) {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+1], Seq: seq})
				pos++
			}
		case instanceMsgVideoParameters:
			if pos+4 <= len(plaintext) {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+4], Seq: seq})
				pos += 4
			}
		case instanceMsgBatteryLevelIsLow:
			if pos < len(plaintext) {
				messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos : pos+1], Seq: seq})
				pos++
			}
		case instanceMsgNetworkStatus:
			end := pos + 2
			if end > len(plaintext) {
				end = len(plaintext)
			}
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: plaintext[pos:end], Seq: seq})
			pos = end
		case instanceMsgRequestVideo:
			messages = append(messages, instanceImplMsg{TypeID: typeID, Data: nil, Seq: seq})
		default:
			pos = len(plaintext)
		}
	}

	return messages, nil
}

func (t *TelegramCore) sendInstanceImplSignaling(call *tgCall, typeID byte, data []byte, requiresAck bool) {
	plaintext := instanceImplSerializeMsg(typeID, data, &call.sigEncCounter, requiresAck)

	call.mu.Lock()
	acks := call.pendingAcks
	call.pendingAcks = nil
	call.mu.Unlock()
	if len(acks) > 0 {
		if !requiresAck {
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

func (t *TelegramCore) sendInstanceImplTransport(call *tgCall, typeID byte, data []byte) error {
	if call.iceConn == nil {
		return fmt.Errorf("ICE not connected")
	}

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

	call.mu.Lock()
	acks := call.pendingAcks
	call.pendingAcks = nil
	call.mu.Unlock()
	if len(acks) > 0 {
		t.sendInstanceImplAcks(call, acks)
	}
}

func (t *TelegramCore) sendInstanceImplAcks(call *tgCall, acks []uint32) {
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

func (t *TelegramCore) startInstanceImplCall(call *tgCall, connections []tg.PhoneConnectionClass, negotiatedVersion string) error {
	t0 := time.Now()
	iceURLs := parseCallConnectionsForICE(connections)
	fmt.Printf("[tg-call] InstanceImpl: starting (version=%s, outgoing=%v, %d ICE URLs)\n",
		negotiatedVersion, call.isOutgoing, len(iceURLs))

	iceRole := ice.AgentConfig{
		Urls:         iceURLs,
		NetworkTypes: []ice.NetworkType{ice.NetworkTypeUDP4},
	}

	if !call.p2pAllowed || t.forceRelayICE {
		iceRole.CandidateTypes = []ice.CandidateType{ice.CandidateTypeRelay}
	}

	agent, err := ice.NewAgent(&iceRole)
	if err != nil {
		return fmt.Errorf("InstanceImpl ICE agent: %w", err)
	}
	call.iceAgent = agent
	call.instanceImplReady = make(chan struct{})

	var localCandidates []string
	var gatherDone = make(chan struct{})

	agent.OnCandidate(func(c ice.Candidate) {
		if c == nil {
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

	select {
	case <-gatherDone:
	case <-time.After(10 * time.Second):
		fmt.Printf("[tg-call] InstanceImpl: candidate gathering timeout\n")
	}
	fmt.Printf("[tg-call] InstanceImpl: gathered %d candidates (+%dms)\n",
		len(localCandidates), time.Since(t0).Milliseconds())

	localUfrag, localPwd, err := agent.GetLocalUserCredentials()
	if err != nil {
		return fmt.Errorf("InstanceImpl local creds: %w", err)
	}

	candidatesMsg := serializeCandidatesListMsg(localCandidates, localUfrag, localPwd)
	t.sendInstanceImplSignaling(call, instanceMsgCandidatesList, candidatesMsg, true)

	call.remoteCredsReady = make(chan struct{})
	go func() {
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

		call.mu.Lock()
		call.state = CallStateActive
		call.markCallConnected()
		call.mu.Unlock()
		t.fireUpdate(Update{
			Type:     UpdateCallState,
			Platform: tgPlatform,
			Call:     &CallSession{ID: strconv.FormatInt(call.id, 10), State: CallStateActive, Meta: call.callStatusMeta()},
		})

		t.sendInstanceImplSignaling(call, instanceMsgRemoteMediaState,
			serializeRemoteMediaStateMsg(true, 0), true)
		t.sendInstanceImplSignaling(call, instanceMsgVideoFormats,
			serializeVideoFormatsMsg(), true)
		if negotiatedVersion == "5.0.0" {
			t.sendInstanceImplSignaling(call, instanceMsgNetworkStatus,
				serializeNetworkStatusMsg(true, false), true)
		}

		var outSSRC, inSSRC uint32
		if call.isOutgoing {
			outSSRC = instanceSSRCAudioOutgoing
			inSSRC = instanceSSRCAudioIncoming
		} else {
			outSSRC = instanceSSRCAudioIncoming
			inSSRC = instanceSSRCAudioOutgoing
		}
		_ = inSSRC

		go func() {
			silence := []byte{0xF8, 0xFF, 0xFE}
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

				rtp := &pionrtp.Packet{
					Header: pionrtp.Header{
						Version:        2,
						PayloadType:    111,
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
					continue
				}

				for _, msg := range messages {
					switch msg.TypeID {
					case instanceMsgAudioData:
						if call.onAudioFrame != nil && len(msg.Data) > 0 {
							call.onAudioFrame(msg.Data)
						}
					case instanceMsgVideoData:
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

func extractWebInitialSetupFromSDP(sdp string, isOutgoing bool) *TgInitialSetup {
	v2Setup, v2NC := extractV2ImplFromSDP(sdp, isOutgoing)

	for _, content := range v2NC.Contents {
		pts := content.PayloadTypes
		if pts == nil {
			pts = []tgPayloadType{}
		}
		exts := content.RTPExtensions
		if exts == nil {
			exts = []tgRTPExtension{}
		}

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
				v2Setup.Video = desc
			} else {
				v2Setup.Screencast = desc
			}
		}
	}

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

func buildSyntheticSDPFromWebSetup(setup *TgInitialSetup, sdpType string) string {
	nc := &tgNegotiateChannels{
		Type: "NegotiateChannels",
	}
	if setup.Audio != nil {
		nc.Contents = append(nc.Contents, TgMediaContent{
			Type:          "audio",
			SSRC:          setup.Audio.SSRC,
			PayloadTypes:  setup.Audio.PayloadTypes,
			RTPExtensions: setup.Audio.RTPExtensions,
		})
	}
	if setup.Video != nil {
		var groups []tgSSRCGroup
		for _, wg := range setup.Video.SSRCGroups {
			var ssrcs []string
			for _, s := range wg.SSRCs {
				ssrcs = append(ssrcs, strconv.Itoa(s))
			}
			groups = append(groups, tgSSRCGroup{Semantics: wg.Semantics, SSRCs: ssrcs})
		}
		nc.Contents = append(nc.Contents, TgMediaContent{
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
		nc.Contents = append(nc.Contents, TgMediaContent{
			Type:          "video",
			SSRC:          setup.Screencast.SSRC,
			SSRCGroups:    groups,
			PayloadTypes:  setup.Screencast.PayloadTypes,
			RTPExtensions: setup.Screencast.RTPExtensions,
		})
	}
	sdp := buildSyntheticSDPFromV2Impl(setup, nc, sdpType)

	dcMID := strconv.Itoa(len(nc.Contents))
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

func extractV2ImplFromSDP(sdp string, isOutgoing bool) (*TgInitialSetup, *tgNegotiateChannels) {
	setup := &TgInitialSetup{
		Type: "InitialSetup",
	}

	for _, line := range strings.Split(sdp, "\r\n") {
		if strings.HasPrefix(line, "a=ice-ufrag:") {
			setup.Ufrag = strings.TrimPrefix(line, "a=ice-ufrag:")
		} else if strings.HasPrefix(line, "a=ice-pwd:") {
			setup.Pwd = strings.TrimPrefix(line, "a=ice-pwd:")
		} else if strings.HasPrefix(line, "a=fingerprint:") {
			parts := strings.SplitN(strings.TrimPrefix(line, "a=fingerprint:"), " ", 2)
			if len(parts) == 2 {
				dtlsSetup := "actpass"
				if !isOutgoing {
					dtlsSetup = "active"
				}
				for _, l2 := range strings.Split(sdp, "\r\n") {
					if strings.HasPrefix(l2, "a=setup:") {
						dtlsSetup = strings.TrimPrefix(l2, "a=setup:")
						break
					}
				}
				setup.Fingerprints = append(setup.Fingerprints, TgDTLSFingerprint{
					Hash:        parts[0],
					Setup:       dtlsSetup,
					Fingerprint: parts[1],
				})
			}
		}
	}

	nc := &tgNegotiateChannels{
		Type:       "NegotiateChannels",
		ExchangeID: "1",
	}

	type mSection struct {
		mediaType string
		content   TgMediaContent
		ssrcGroup []tgSSRCGroup
	}
	var sections []mSection
	currentIdx := -1

	for _, line := range strings.Split(sdp, "\r\n") {
		if strings.HasPrefix(line, "m=audio ") {
			sections = append(sections, mSection{mediaType: "audio", content: TgMediaContent{Type: "audio"}})
			currentIdx = len(sections) - 1
			continue
		} else if strings.HasPrefix(line, "m=video ") {
			sections = append(sections, mSection{mediaType: "video", content: TgMediaContent{Type: "video"}})
			currentIdx = len(sections) - 1
			continue
		} else if strings.HasPrefix(line, "m=") {
			currentIdx = -1
			continue
		}

		if currentIdx < 0 {
			continue
		}
		sec := &sections[currentIdx]

		if strings.HasPrefix(line, "a=ssrc-group:") {
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
			parts := strings.SplitN(strings.TrimPrefix(line, "a=ssrc:"), " ", 2)
			if len(parts) >= 1 && sec.content.SSRC == "" {
				sec.content.SSRC = parts[0]
			}
		} else if strings.HasPrefix(line, "a=rtpmap:") {
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

	for _, sec := range sections {
		content := sec.content
		content.SSRCGroups = sec.ssrcGroup
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
					continue
				}
			}
			filtered = append(filtered, pt)
		}
		content.PayloadTypes = filtered
		nc.Contents = append(nc.Contents, content)
	}
	return setup, nc
}

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
					inVideo = false
				}
			}
		}
	}
	if call.remoteScreenSSRC != 0 {
		fmt.Printf("[tg-call] V2Ref: remote SSRCs: video=%d screencast=%d\n", call.remoteVideoSSRC, call.remoteScreenSSRC)
	}
}

func buildSyntheticSDPFromV2Impl(setup *TgInitialSetup, nc *tgNegotiateChannels, sdpType string, localAudioSSRC ...uint32) string {
	var sb strings.Builder

	sb.WriteString("v=0\r\n")
	sb.WriteString("o=- 0 0 IN IP4 0.0.0.0\r\n")
	sb.WriteString("s=-\r\n")
	sb.WriteString("t=0 0\r\n")

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

	sb.WriteString("a=ice-ufrag:" + setup.Ufrag + "\r\n")
	sb.WriteString("a=ice-pwd:" + setup.Pwd + "\r\n")

	if len(setup.Fingerprints) > 0 {
		fp := setup.Fingerprints[0]
		sb.WriteString("a=fingerprint:" + fp.Hash + " " + fp.Fingerprint + "\r\n")
		sb.WriteString("a=setup:" + fp.Setup + "\r\n")
	}

	midIdx := 0
	for _, content := range nc.Contents {
		if content.Type != "audio" && content.Type != "video" {
			continue
		}

		var ptIDs []string
		for _, pt := range content.PayloadTypes {
			ptIDs = append(ptIDs, strconv.Itoa(pt.ID))
		}
		if len(ptIDs) == 0 {
			if content.Type == "audio" {
				ptIDs = []string{"111"}
			} else {
				ptIDs = []string{"96"}
			}
		}

		sb.WriteString("m=" + content.Type + " 9 UDP/TLS/RTP/SAVPF " + strings.Join(ptIDs, " ") + "\r\n")
		sb.WriteString("c=IN IP4 0.0.0.0\r\n")
		sb.WriteString("a=rtcp:9 IN IP4 0.0.0.0\r\n")

		sb.WriteString("a=ice-ufrag:" + setup.Ufrag + "\r\n")
		sb.WriteString("a=ice-pwd:" + setup.Pwd + "\r\n")

		if len(setup.Fingerprints) > 0 {
			fp := setup.Fingerprints[0]
			sb.WriteString("a=fingerprint:" + fp.Hash + " " + fp.Fingerprint + "\r\n")
			sb.WriteString("a=setup:" + fp.Setup + "\r\n")
		}

		sb.WriteString("a=mid:" + strconv.Itoa(midIdx) + "\r\n")
		midIdx++
		sb.WriteString("a=rtcp-mux\r\n")
		sb.WriteString("a=sendrecv\r\n")

		for _, ext := range content.RTPExtensions {
			sb.WriteString("a=extmap:" + strconv.Itoa(ext.ID) + " " + ext.URI + "\r\n")
		}

		for _, pt := range content.PayloadTypes {
			channels := ""
			if pt.Channels > 0 {
				channels = "/" + strconv.Itoa(pt.Channels)
			}
			sb.WriteString("a=rtpmap:" + strconv.Itoa(pt.ID) + " " + pt.Name + "/" + strconv.Itoa(pt.Clockrate) + channels + "\r\n")

			if len(pt.Parameters) > 0 {
				var params []string
				for k, v := range pt.Parameters {
					params = append(params, k+"="+v)
				}
				sb.WriteString("a=fmtp:" + strconv.Itoa(pt.ID) + " " + strings.Join(params, ";") + "\r\n")
			}

			for _, fb := range pt.FeedbackTypes {
				fbStr := "a=rtcp-fb:" + strconv.Itoa(pt.ID) + " " + fb.Type
				if fb.Subtype != "" {
					fbStr += " " + fb.Subtype
				}
				sb.WriteString(fbStr + "\r\n")
			}
		}

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
			for _, group := range content.SSRCGroups {
				if len(group.SSRCs) > 0 {
					sb.WriteString("a=ssrc-group:" + group.Semantics + " " + strings.Join(group.SSRCs, " ") + "\r\n")
				}
			}
		}
	}

	return sb.String()
}

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

func tgEncryptSignaling(key []byte, data []byte, isOutgoing bool, counter *uint32, webMode bool) ([]byte, error) {
	x := 128
	if !isOutgoing {
		x = 136
	}

	seq := atomic.AddUint32(counter, 1)

	var plaintext []byte
	if webMode {
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
		seqWithFlags := seq | 0x40000000
		plaintext = make([]byte, 4+1+4+len(data))
		binary.BigEndian.PutUint32(plaintext[:4], seqWithFlags)
		plaintext[4] = 0x7F
		binary.BigEndian.PutUint32(plaintext[5:9], uint32(len(data)))
		copy(plaintext[9:], data)
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

func tgDecryptSignaling(key []byte, packet []byte, isOutgoing bool, v1Framing ...bool) ([][]byte, []uint32, error) {
	if len(packet) < 21 {
		return nil, nil, fmt.Errorf("signaling packet too short: %d bytes", len(packet))
	}

	x := 136
	if !isOutgoing {
		x = 128
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

	if len(v1Framing) > 0 && v1Framing[0] {
		return [][]byte{plaintext[4:]}, nil, nil
	}

	var messages [][]byte
	var ackSeqs []uint32

	firstSeq := binary.BigEndian.Uint32(plaintext[:4])
	if firstSeq&seqRequiresAckBit != 0 {
		ackSeqs = append(ackSeqs, firstSeq)
	}
	pos := 4

	for pos < len(plaintext) {
		if pos+1 > len(plaintext) {
			break
		}
		typeID := plaintext[pos]
		pos++

		switch typeID {
		case 0xFE:
		case 0xFF:
		case 0x7F:
			if pos+4 > len(plaintext) {
				break
			}
			dataLen := int(binary.BigEndian.Uint32(plaintext[pos : pos+4]))
			pos += 4
			if pos+dataLen > len(plaintext) {
				if pos < len(plaintext) {
					messages = append(messages, plaintext[pos:])
				}
				pos = len(plaintext)
				break
			}
			messages = append(messages, plaintext[pos:pos+dataLen])
			pos += dataLen
		default:
			pos = len(plaintext)
		}

		if pos+5 <= len(plaintext) {
			nextSeq := binary.BigEndian.Uint32(plaintext[pos : pos+4])
			if nextSeq&seqRequiresAckBit != 0 {
				ackSeqs = append(ackSeqs, nextSeq)
			}
			pos += 4
		} else {
			break
		}
	}

	if len(messages) == 0 {
		return nil, ackSeqs, nil
	}
	return messages, ackSeqs, nil
}

func tgEncryptV2Packet(key []byte, data []byte, isOutgoing bool, counter *uint32) ([]byte, error) {
	x := 128
	if !isOutgoing {
		x = 136
	}

	seq := atomic.AddUint32(counter, 1)

	plaintext := make([]byte, 4+len(data))
	binary.BigEndian.PutUint32(plaintext[:4], seq)
	copy(plaintext[4:], data)

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
	if len(packet) < 21 {
		return nil, fmt.Errorf("V2 packet too short: %d bytes", len(packet))
	}

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

	h := sha256.New()
	h.Write(key[88+x : 88+x+32])
	h.Write(plaintext)
	check := h.Sum(nil)
	if !bytes.Equal(check[8:24], msgKey) {
		return nil, fmt.Errorf("V2 decryption: msgKey mismatch")
	}

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

type sctpSignalingConn struct {
	packets chan []byte
	sendFn  func([]byte)
	closed  int32
}

func newSctpSignalingConn(sendFn func([]byte)) *sctpSignalingConn {
	return &sctpSignalingConn{
		packets: make(chan []byte, 256),
		sendFn:  sendFn,
	}
}

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

func (c *sctpSignalingConn) LocalAddr() net.Addr                { return sctpAddr{} }
func (c *sctpSignalingConn) RemoteAddr() net.Addr               { return sctpAddr{} }
func (c *sctpSignalingConn) SetDeadline(t time.Time) error      { return nil }
func (c *sctpSignalingConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *sctpSignalingConn) SetWriteDeadline(t time.Time) error { return nil }

type sctpAddr struct{}

func (sctpAddr) Network() string { return "sctp-signaling" }
func (sctpAddr) String() string  { return "sctp-signaling" }

func (t *TelegramCore) setupSctpSignaling(call *tgCall) {
	call.sctpReady = make(chan struct{})

	sendFn := func(data []byte) {
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
			MaxReceiveBufferSize: 262144,
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

		buf := make([]byte, 64*1024)
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

			decrypted, err := tgDecryptV2Packet(call.authKey[:], payload, call.isOutgoing)
			if err != nil {
				fmt.Printf("[tg-call] SCTP V2 decrypt error: %v\n", err)
				continue
			}

			if len(decrypted) >= 2 && decrypted[0] == 0x1f && decrypted[1] == 0x8b {
				if decompressed, err := GzipDecompress(decrypted); err == nil {
					decrypted = decompressed
				}
			}

			fmt.Printf("[tg-call] SCTP signaling: %s\n", string(decrypted[:min(len(decrypted), 300)]))

			var msg map[string]interface{}
			if err := UnmarshalCallSignal(decrypted, &msg); err != nil {
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
					var setup TgInitialSetup
					if err := UnmarshalCallSignal(decrypted, &setup); err != nil {
						fmt.Printf("[tg-call] SCTP skip InitialSetup: %v\n", err)
						break
					}
					fmt.Printf("[tg-call] SCTP V2Impl: got InitialSetup (ufrag=%s)\n", setup.Ufrag)
					t.handleRemoteInitialSetupV2Impl(call, &setup)
				}
			case "NegotiateChannels":
				if call.useV2Impl {
					var nc tgNegotiateChannels
					if err := UnmarshalCallSignal(decrypted, &nc); err != nil {
						fmt.Printf("[tg-call] SCTP skip NegotiateChannels: %v\n", err)
						break
					}
					fmt.Printf("[tg-call] SCTP V2Impl: got NegotiateChannels (exchangeId=%s)\n", nc.ExchangeID)
					t.handleRemoteNegotiateChannelsV2Impl(call, &nc)
				}
			case "Candidates":
				var candidates tgCandidates
				if err := UnmarshalCallSignal(decrypted, &candidates); err != nil {
					fmt.Printf("[tg-call] SCTP skip Candidates: %v\n", err)
					break
				}
				for _, c := range candidates.Candidates {
					if !strings.Contains(c.SDPString, ".reflector") {
						t.handleRemoteCandidate(call, c.SDPString, "0", 0)
					}
				}
			case "MediaState":
				var ms tgMediaState
				if err := UnmarshalCallSignal(decrypted, &ms); err != nil {
					fmt.Printf("[tg-call] SCTP skip MediaState: %v\n", err)
					break
				}
				fmt.Printf("[tg-call] SCTP MediaState: muted=%v video=%s screencast=%s rotation=%d\n",
					ms.Muted, ms.VideoState, ms.ScreencastState, ms.VideoRotation)
				t.applyRemoteMediaState(call, ms)
			default:
				fmt.Printf("[tg-call] SCTP unknown message type: %v\n", msg["@type"])
			}
		}
	}()
}

func (t *TelegramCore) sendCallSignalingV2(call *tgCall, v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		fmt.Printf("[tg-call] V2 marshal error: %v\n", err)
		return
	}
	fmt.Printf("[tg-call] V2 signaling tx: %s\n", string(data[:min(len(data), 300)]))

	compressed, err := gzipCompress(data)
	if err != nil {
		fmt.Printf("[tg-call] V2 gzip error: %v\n", err)
		return
	}

	encrypted, err := tgEncryptV2Packet(call.authKey[:], compressed, call.isOutgoing, &call.v2SigCounter)
	if err != nil {
		fmt.Printf("[tg-call] V2 encrypt error: %v\n", err)
		return
	}

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

	_, err = call.sctpStream.WriteSCTP(encrypted, sctp.PayloadTypeWebRTCBinary)
	if err != nil {
		fmt.Printf("[tg-call] V2 SCTP write error: %v\n", err)
	}
}

func (t *TelegramCore) sendV2SignalingAcks(call *tgCall, ackSeqs []uint32) {
	if len(ackSeqs) == 0 {
		return
	}
	seq := atomic.AddUint32(&call.sigCounter, 1)
	plaintext := make([]byte, 5, 5+5*len(ackSeqs))
	binary.BigEndian.PutUint32(plaintext[:4], seq)
	plaintext[4] = 0xFE
	for _, ackSeq := range ackSeqs {
		var ackBuf [5]byte
		binary.BigEndian.PutUint32(ackBuf[:4], ackSeq)
		ackBuf[4] = 0xFF
		plaintext = append(plaintext, ackBuf[:]...)
	}

	x := 128
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

func createCallWebRTCAPI(iceUfrag, icePwd string) *wrtc.API {
	me := &wrtc.MediaEngine{}
	me.RegisterDefaultCodecs()

	me.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:    "audio/red",
			ClockRate:   48000,
			Channels:    2,
			SDPFmtpLine: "111/111",
		},
		PayloadType: 63,
	}, webrtc.RTPCodecTypeAudio)

	me.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:  "audio/telephone-event",
			ClockRate: 48000,
		},
		PayloadType: 110,
	}, webrtc.RTPCodecTypeAudio)

	for _, ext := range []struct {
		uri string
		typ webrtc.RTPCodecType
	}{
		{"urn:ietf:params:rtp-hdrext:sdes:mid", webrtc.RTPCodecTypeAudio},
		{"urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id", webrtc.RTPCodecTypeAudio},
		{"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time", webrtc.RTPCodecTypeAudio},
		{"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01", webrtc.RTPCodecTypeAudio},
	} {
		if err := me.RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability{URI: ext.uri}, ext.typ); err != nil {
			fmt.Printf("[tg-call] Warning: failed to register header extension %s: %v\n", ext.uri, err)
		}
	}

	ir := &interceptor.Registry{}
	wrtc.RegisterDefaultInterceptors(me, ir)
	se := wrtc.SettingEngine{}
	se.SetSRTPReplayProtectionWindow(1024)
	se.SetICECredentials(iceUfrag, icePwd)
	se.SetFireOnTrackBeforeFirstRTP(true)
	logFactory := pionlogging.NewDefaultLoggerFactory()
	logFactory.DefaultLogLevel = pionlogging.LogLevelWarn
	se.LoggerFactory = logFactory
	return wrtc.NewAPI(
		wrtc.WithMediaEngine(me),
		wrtc.WithInterceptorRegistry(ir),
		wrtc.WithSettingEngine(se),
	)
}

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

	p, g, err := t.getDHConfig()
	if err != nil {
		return nil, fmt.Errorf("DH config: %w", err)
	}

	a := make([]byte, 256)
	if _, err := io.ReadFull(rand.Reader, a); err != nil {
		return nil, fmt.Errorf("random: %w", err)
	}

	gBig := new(big.Int).SetInt64(int64(g))
	aBig := new(big.Int).SetBytes(a)
	pBig := new(big.Int).SetBytes(p)
	gA := new(big.Int).Exp(gBig, aBig, pBig)
	gABytes := make([]byte, 256)
	gABuf := gA.Bytes()
	copy(gABytes[256-len(gABuf):], gABuf)

	gaHash := sha256.Sum256(gABytes)

	versions := filterVersions(
		[]string{"13.0.0", "8.0.0", "4.0.0"},
		t.maxCallVersion, t.minCallVersion,
	)

	result, err := t.api.PhoneRequestCall(t.ctx, &tg.PhoneRequestCallRequest{
		UserID:   &tg.InputUser{UserID: uid, AccessHash: accessHash},
		RandomID: int(binary.BigEndian.Uint32(gaHash[:4])),
		GAHash:   gaHash[:],
		Protocol: tg.PhoneCallProtocol{
			Flags:           0b11,
			MinLayer:        65,
			MaxLayer:        92,
			LibraryVersions: versions,
		},
		Video: video,
	})
	if err != nil {
		return nil, fmt.Errorf("phone.requestCall: %w", err)
	}

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

type pendingDHState struct {
	a  []byte
	gA []byte
	p  []byte
	g  int
}

func parseCallConnections(connections []tg.PhoneConnectionClass) []webrtc.ICEServer {
	var servers []webrtc.ICEServer
	for _, conn := range connections {
		switch c := conn.(type) {
		case *tg.PhoneConnectionWebrtc:
			if c.Turn {
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

func (t *TelegramCore) handleCallAccepted(callID int64, gB []byte, protocol tg.PhoneCallProtocol) error {
	t0 := time.Now()
	t.mu.Lock()
	dh := t.pendingDH[callID]
	call := t.activeCalls[callID]
	t.mu.Unlock()

	if dh == nil || call == nil {
		return fmt.Errorf("no pending DH for call %d", callID)
	}

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

	call.mu.Lock()
	call.fpValues = computeEmojiFingerprintValues(call.authKey[:], dh.gA)
	call.fpReady = true
	call.mu.Unlock()

	t.mu.Lock()
	delete(t.pendingDH, callID)
	call.state = CallStateConnecting
	t.mu.Unlock()

	versions := filterVersions(
		[]string{"13.0.0", "8.0.0", "4.0.0"},
		t.maxCallVersion, t.minCallVersion,
	)
	confirmResult, err := t.api.PhoneConfirmCall(t.ctx, &tg.PhoneConfirmCallRequest{
		Peer:           tg.InputPhoneCall{ID: callID, AccessHash: call.accessHash},
		GA:             dh.gA,
		KeyFingerprint: fingerprint,
		Protocol: tg.PhoneCallProtocol{
			Flags:           0b11,
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
	fmt.Printf("[tg-call] PhoneCall: id=%d admin=%d participant=%d p2p=%v video=%v conferenceSupported=%v\n",
		pcResult.ID, pcResult.AdminID, pcResult.ParticipantID, pcResult.P2PAllowed, pcResult.Video, pcResult.ConferenceSupported)
	fmt.Printf("[tg-call] Protocol: minLayer=%d maxLayer=%d versions=%v\n",
		pcResult.Protocol.MinLayer, pcResult.Protocol.MaxLayer, pcResult.Protocol.LibraryVersions)
	negotiatedVersion := ""
	if len(pcResult.Protocol.LibraryVersions) > 0 {
		negotiatedVersion = pcResult.Protocol.LibraryVersions[0]
	}
	fmt.Printf("[tg-call] Negotiated version: %s\n", negotiatedVersion)

	if isV3Transport(negotiatedVersion) || t.forceV2Sig {
		call.useV2Sig = true
		fmt.Printf("[tg-call] Using SCTP signaling (version %s, forced=%v)\n", negotiatedVersion, t.forceV2Sig)
		t.setupSctpSignaling(call)
	}
	if t.forceV2Impl || (isV2ImplVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref) {
		call.useV2Impl = true
		if t.forceV1Framing {
			call.useV1Framing = true
		}
		fmt.Printf("[tg-call] Using V2Impl signaling (version %s, forced=%v, v1framing=%v)\n", negotiatedVersion, t.forceV2Impl, call.useV1Framing)
	}
	if isWebVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref && !t.forceV2Impl {
		call.useWebSignaling = true
		call.useV1Framing = true
		fmt.Printf("[tg-call] Using Web signaling (version %s)\n", negotiatedVersion)
	}

	if cp, ok := pcResult.GetCustomParameters(); ok {
		fmt.Printf("[tg-call] CustomParameters: %s\n", cp.Data)
	}

	t.mu.Lock()
	call.connections = pcResult.Connections
	call.p2pAllowed = pcResult.P2PAllowed
	call.conferenceSupported = pcResult.ConferenceSupported
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

	if call.skipWebRTC {
		fmt.Printf("[tg-call] skipWebRTC mode (outgoing) — DH done, %d connections available for test harness\n", len(pcResult.Connections))
		if call.dhDone != nil {
			close(call.dhDone)
		}
		return nil
	}

	if t.forceInstanceImpl {
		call.useInstanceImpl = true
		fmt.Printf("[tg-call] Using InstanceImpl (forced, version %s)\n", negotiatedVersion)
		return t.startInstanceImplCall(call, pcResult.Connections, negotiatedVersion)
	}

	iceServers := parseCallConnections(pcResult.Connections)
	fmt.Printf("[tg-call] %d connections → %d ICE servers, p2p=%v (+%dms)\n",
		len(pcResult.Connections), len(iceServers), call.p2pAllowed, time.Since(t0).Milliseconds())

	icePolicy := webrtc.ICETransportPolicyRelay
	if call.p2pAllowed && !t.forceRelayICE {
		icePolicy = webrtc.ICETransportPolicyAll
	}

	iceUfrag := generateICECredential(16)
	icePwd := generateICECredential(32)

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
	monitorCallDTLS(pc, t0)

	go t.finishCallSetup(call, t0)
	return nil
}

func (t *TelegramCore) finishCallSetup(call *tgCall, t0 time.Time) {
	pc := call.pc
	if pc == nil {
		return
	}

	audioTrack, err := wrtc.NewTrackLocalStaticRTP(
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

	if call.isVideo {
		videoTrack, err := wrtc.NewTrackLocalStaticSample(
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

	if call.useWebSignaling || call.isVideo {
		screenTrack, err := wrtc.NewTrackLocalStaticSample(
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

	pc.OnDataChannel(func(dc *webrtc.DataChannel) {
		fmt.Printf("[tg-call] DATA CHANNEL opened: label=%s id=%d\n", dc.Label(), *dc.ID())
		dc.OnMessage(func(msg webrtc.DataChannelMessage) {
			fmt.Printf("[tg-call] DATA CHANNEL msg: %d bytes: %s\n", len(msg.Data), string(msg.Data[:min(len(msg.Data), 200)]))
		})
	})

	pc.OnTrack(func(track *wrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		trackSSRC := uint32(track.SSRC())
		fmt.Printf("[tg-call] Incoming track: kind=%s codec=%s ssrc=%d mid=%s rid=%s streamID=%s\n",
			track.Kind(), track.Codec().MimeType, trackSSRC, track.Msid(), track.RID(), track.StreamID())
		logCallTransceivers(call)
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

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		fmt.Printf("[tg-call] ICE state: %s (+%dms)\n", state, time.Since(t0).Milliseconds())
		call.mu.Lock()
		switch state {
		case webrtc.ICEConnectionStateConnected:
			call.state = CallStateActive
			call.markCallConnected()
		case webrtc.ICEConnectionStateFailed, webrtc.ICEConnectionStateClosed:
			call.state = CallStateEnded
		}
		newCallState := call.state
		call.mu.Unlock()
		if state == webrtc.ICEConnectionStateConnected || state == webrtc.ICEConnectionStateFailed {
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call:     &CallSession{ID: strconv.FormatInt(call.id, 10), State: newCallState, Meta: call.callStatusMeta()},
			})
		}
	})

	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		cJSON := c.ToJSON()
		if call.useV2Impl || call.useWebSignaling {
			t.sendCallSignaling(call, &tgCandidates{
				Type:       "Candidates",
				Candidates: []tgCandidate{{SDPString: cJSON.Candidate}},
			})
		} else {
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

	if call.isOutgoing {
		dc, err := pc.CreateDataChannel("data", nil)
		if err == nil {
			dc.OnMessage(func(msg webrtc.DataChannelMessage) {
				fmt.Printf("[tg-call] DATA CHANNEL msg: %d bytes: %s\n", len(msg.Data), string(msg.Data[:min(len(msg.Data), 200)]))
			})
		}
	}

	if t.noOwnOffer {
		close(call.localSDPReady)
		call.localSetupSent = true
		fmt.Printf("[tg-call] NoOwnOffer mode — waiting for remote SDP offer (+%dms)\n", time.Since(t0).Milliseconds())
	} else {
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
			webSetup := extractWebInitialSetupFromSDP(offer.SDP, true)
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
			v2Setup, v2NC := extractV2ImplFromSDP(offer.SDP, true)
			v2NC.ExchangeID = strconv.FormatUint(uint64(atomic.AddUint32(&call.v2ImplExchangeSeq, 1)), 10)

			t.sendCallSignaling(call, v2Setup)
			fmt.Printf("[tg-call] V2Impl: sent InitialSetup (ufrag=%s, setup=%s) (+%dms)\n",
				v2Setup.Ufrag, FingerprintLabel(*v2Setup), time.Since(t0).Milliseconds())

			t.sendCallSignaling(call, v2NC)
			fmt.Printf("[tg-call] V2Impl: sent NegotiateChannels (exchangeId=%s, ssrc=%s) (+%dms)\n",
				v2NC.ExchangeID, FirstSSRC(v2NC.Contents), time.Since(t0).Milliseconds())
		} else {
			t.sendCallSignaling(call, map[string]interface{}{
				"@type": "offer",
				"sdp":   offer.SDP,
			})
			fmt.Printf("[tg-call] SDP offer sent (+%dms)\n", time.Since(t0).Milliseconds())
		}
		call.localSetupSent = true
	}

	videoState := "inactive"
	if call.isVideo {
		videoState = "active"
	}
	t.sendCallSignaling(call, map[string]interface{}{
		"@type":           "MediaState",
		"muted":           false,
		"videoState":      videoState,
		"videoRotation":   0,
		"screencastState": "inactive",
		"lowBattery":      false,
	})

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

func (t *TelegramCore) handleIncomingCallConfirmed(pc *tg.PhoneCall) error {
	t.mu.Lock()
	dh := t.pendingDH[pc.ID]
	call := t.activeCalls[pc.ID]
	t.mu.Unlock()

	if dh == nil || call == nil {
		return nil
	}
	if call.isOutgoing {
		return nil
	}

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

	call.mu.Lock()
	call.fpValues = computeEmojiFingerprintValues(call.authKey[:], gA)
	call.fpReady = true
	call.mu.Unlock()

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
	call.conferenceSupported = pc.ConferenceSupported
	proto := pc.Protocol
	call.protocol = &proto
	t.mu.Unlock()
	fmt.Printf("[tg-call] Incoming DH done, fp=%d\n", fingerprint)

	if call.dhDone != nil {
		close(call.dhDone)
	}

	if call.skipWebRTC {
		fmt.Printf("[tg-call] skipWebRTC mode — DH done, %d connections available for test harness\n", len(pc.Connections))
		return nil
	}

	negotiatedVersion := ""
	if len(pc.Protocol.LibraryVersions) > 0 {
		negotiatedVersion = pc.Protocol.LibraryVersions[0]
	}
	fmt.Printf("[tg-call] Incoming negotiated version: %s\n", negotiatedVersion)

	if isV3Transport(negotiatedVersion) || t.forceV2Sig {
		call.useV2Sig = true
		fmt.Printf("[tg-call] Incoming: using SCTP signaling\n")
		t.setupSctpSignaling(call)
	}
	if t.forceV2Impl || (isV2ImplVersion(negotiatedVersion) && !t.forceV2Sig && !t.forceV2Ref) {
		call.useV2Impl = true
		if t.forceV1Framing {
			call.useV1Framing = true
		}
		fmt.Printf("[tg-call] Incoming: using V2Impl signaling (version %s, forced=%v, v1framing=%v)\n", negotiatedVersion, t.forceV2Impl, call.useV1Framing)
	}
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

	if t.forceInstanceImpl {
		call.useInstanceImpl = true
		fmt.Printf("[tg-call] Incoming: using InstanceImpl (forced, version %s)\n", negotiatedVersion)
		return t.startInstanceImplCall(call, pc.Connections, negotiatedVersion)
	}

	iceServers := parseCallConnections(pc.Connections)
	fmt.Printf("[tg-call] Incoming: %d ICE servers, p2p=%v\n", len(iceServers), call.p2pAllowed)
	return t.startCallWebRTC(call, iceServers, time.Now())
}

func (t *TelegramCore) startCallWebRTC(call *tgCall, iceServers []webrtc.ICEServer, t0 time.Time) error {
	icePolicy := webrtc.ICETransportPolicyRelay
	if call.p2pAllowed && !t.forceRelayICE {
		icePolicy = webrtc.ICETransportPolicyAll
	}

	iceUfrag := generateICECredential(16)
	icePwd := generateICECredential(32)

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

	audioTrack, err := wrtc.NewTrackLocalStaticRTP(
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

	if call.isVideo {
		videoTrack, err := wrtc.NewTrackLocalStaticSample(
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

	if call.useWebSignaling || call.isVideo {
		screenTrack, err := wrtc.NewTrackLocalStaticSample(
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

	pc.OnTrack(func(track *wrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		trackSSRC := uint32(track.SSRC())
		fmt.Printf("[tg-call] Incoming track: kind=%s codec=%s ssrc=%d mid=%s rid=%s streamID=%s\n",
			track.Kind(), track.Codec().MimeType, trackSSRC, track.Msid(), track.RID(), track.StreamID())
		logCallTransceivers(call)
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
			call.markCallConnected()
		case webrtc.ICEConnectionStateFailed, webrtc.ICEConnectionStateClosed:
			call.state = CallStateEnded
		}
		newCallState := call.state
		call.mu.Unlock()
		if state == webrtc.ICEConnectionStateConnected || state == webrtc.ICEConnectionStateFailed {
			t.fireUpdate(Update{
				Type:     UpdateCallState,
				Platform: tgPlatform,
				Call:     &CallSession{ID: strconv.FormatInt(call.id, 10), State: newCallState, Meta: call.callStatusMeta()},
			})
		}
	})

	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		cJSON := c.ToJSON()
		if call.useV2Impl || call.useWebSignaling {
			t.sendCallSignaling(call, &tgCandidates{
				Type:       "Candidates",
				Candidates: []tgCandidate{{SDPString: cJSON.Candidate}},
			})
		} else {
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

	close(call.localSDPReady)
	waitingFor := "SDP offer"
	if call.useV2Impl {
		waitingFor = "InitialSetup+NegotiateChannels"
	} else if call.useWebSignaling {
		waitingFor = "Web InitialSetup"
	}
	fmt.Printf("[tg-call] Incoming PC ready, waiting for remote %s (+%dms)\n",
		waitingFor, time.Since(t0).Milliseconds())

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

func (t *TelegramCore) handleSignalingData(callID int64, data []byte) {
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

	if call.useInstanceImpl {
		t.handleInstanceImplSignaling(call, data)
		return
	}

	if call.useV2Sig && call.sctpConn != nil {
		fmt.Printf("[tg-call] SCTP feed: %d bytes (first4hex=%x)\n", len(data), data[:min(4, len(data))])
		call.sctpConn.feed(data)
		return
	}

	messages, ackSeqs, err := tgDecryptSignaling(call.authKey[:], data, call.isOutgoing, call.useV1Framing)
	if err != nil {
		fmt.Printf("[tg-call] signaling decrypt error: %v (%d bytes)\n", err, len(data))
		return
	}

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

		if len(plaintext) >= 2 && plaintext[0] == 0x1f && plaintext[1] == 0x8b {
			if decompressed, err := GzipDecompress(plaintext); err == nil {
				plaintext = decompressed
				fmt.Printf("[tg-call] decompressed gzip → %d bytes\n", len(plaintext))
			}
		}

		var msg map[string]interface{}
		if err := UnmarshalCallSignal(plaintext, &msg); err != nil {
			fmt.Printf("[tg-call] signaling: invalid JSON: %v\n", err)
			continue
		}

		switch msg["@type"] {
		case "offer", "answer":
			sdpType := msg["@type"].(string)
			sdpStr, _ := msg["sdp"].(string)
			for _, line := range strings.Split(sdpStr, "\r\n") {
				if strings.HasPrefix(line, "m=") || line == "a=sendrecv" || line == "a=recvonly" || line == "a=sendonly" || line == "a=inactive" || strings.HasPrefix(line, "a=msid") || strings.HasPrefix(line, "a=mid:") {
					fmt.Printf("[tg-call] SDP %s: %s\n", sdpType, line)
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
			fmt.Printf("[tg-call] Got candidate: mid=%s mline=%d sdp=%s\n", mid, mline, sdp[:min(len(sdp), 80)])
			t.handleRemoteCandidate(call, sdp, mid, mline)

		case "MediaState":
			var ms tgMediaState
			if err := UnmarshalCallSignal(plaintext, &ms); err != nil {
				fmt.Printf("[tg-call] skip MediaState: %v\n", err)
				break
			}
			fmt.Printf("[tg-call] Got MediaState: muted=%v video=%s screencast=%s rotation=%d\n",
				ms.Muted, ms.VideoState, ms.ScreencastState, ms.VideoRotation)
			t.applyRemoteMediaState(call, ms)

		case "InitialSetup":
			if call.useWebSignaling {
				var setup TgInitialSetup
				if err := UnmarshalCallSignal(plaintext, &setup); err != nil {
					fmt.Printf("[tg-call] skip Web InitialSetup: %v\n", err)
					break
				}
				fmt.Printf("[tg-call] Web: got InitialSetup (ufrag=%s, setup=%s, audio=%v, video=%v, screencast=%v)\n",
					setup.Ufrag, FingerprintLabel(setup), setup.Audio != nil, setup.Video != nil, setup.Screencast != nil)
				t.handleRemoteInitialSetupWeb(call, &setup)
			} else if call.useV2Impl {
				var setup TgInitialSetup
				if err := UnmarshalCallSignal(plaintext, &setup); err != nil {
					fmt.Printf("[tg-call] skip V2Impl InitialSetup: %v\n", err)
					break
				}
				fmt.Printf("[tg-call] V2Impl: got InitialSetup (ufrag=%s, setup=%s)\n",
					setup.Ufrag, FingerprintLabel(setup))
				t.handleRemoteInitialSetupV2Impl(call, &setup)
			} else {
				fmt.Printf("[tg-call] Got InitialSetup (unexpected with V2Reference)\n")
			}
		case "NegotiateChannels":
			if call.useV2Impl {
				var nc tgNegotiateChannels
				if err := UnmarshalCallSignal(plaintext, &nc); err != nil {
					fmt.Printf("[tg-call] skip NegotiateChannels: %v\n", err)
					break
				}
				ssrc := FirstSSRC(nc.Contents)
				fmt.Printf("[tg-call] V2Impl: got NegotiateChannels (exchangeId=%s, contents=%d, ssrc=%s)\n",
					nc.ExchangeID, len(nc.Contents), ssrc)
				t.handleRemoteNegotiateChannelsV2Impl(call, &nc)
			} else {
				fmt.Printf("[tg-call] Got NegotiateChannels (unexpected with V2Reference)\n")
			}
		case "Candidates":
			var candidates tgCandidates
			if err := UnmarshalCallSignal(plaintext, &candidates); err != nil {
				fmt.Printf("[tg-call] skip Candidates: %v\n", err)
				break
			}
			for _, c := range candidates.Candidates {
				if !strings.Contains(c.SDPString, ".reflector") {
					t.handleRemoteCandidate(call, c.SDPString, "0", 0)
				}
			}
		}
	}
}

func (t *TelegramCore) handleRemoteSDP(call *tgCall, sdpType string, sdp string) {
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
			if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
				Type: webrtc.SDPTypeOffer,
				SDP:  sdp,
			}); err != nil {
				fmt.Printf("[tg-call] SetRemoteDescription(offer) error: %v\n", err)
				return
			}
			call.remoteSDPSet = true
			fmt.Printf("[tg-call] Remote offer set (first), receivers=%d\n", len(call.pc.GetReceivers()))

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
			call.localSDP = answer.SDP
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
				"@type":           "MediaState",
				"muted":           false,
				"videoState":      ansVideoState,
				"videoRotation":   0,
				"screencastState": "inactive",
				"lowBattery":      false,
			})
		} else {
			call.remoteOfferCount++
			fmt.Printf("[tg-call] Re-offer #%d received\n", call.remoteOfferCount)

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
			if err := call.pc.SetLocalDescription(answer); err != nil {
				fmt.Printf("[tg-call] SetLocalDescription(re-offer) error: %v\n", err)
				return
			}
			answerSDP := answer.SDP
			if call.dtlsRole == "passive" {
				answerSDP = strings.ReplaceAll(answerSDP, "a=setup:active\r\n", "a=setup:passive\r\n")
			} else if call.dtlsRole == "active" {
				answerSDP = strings.ReplaceAll(answerSDP, "a=setup:passive\r\n", "a=setup:active\r\n")
			}
			fmt.Printf("[tg-call] Re-offer answer created (%d bytes, dtlsRole=%s)\n", len(answerSDP), call.dtlsRole)
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
				"@type":           "MediaState",
				"muted":           false,
				"videoState":      roVideoState,
				"videoRotation":   0,
				"screencastState": "inactive",
				"lowBattery":      false,
			})
		}
	} else if sdpType == "answer" {
		if call.remoteSDPSet {
			fmt.Printf("[tg-call] Ignoring duplicate SDP answer (already handled)\n")
			return
		}

		if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeAnswer,
			SDP:  sdp,
		}); err != nil {
			fmt.Printf("[tg-call] SetRemoteDescription(answer) error: %v\n", err)
			return
		}
		call.remoteSDPSet = true
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

		extractRemoteVideoSSRCs(call, sdp)
	}

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

func (t *TelegramCore) handleRemoteCandidate(call *tgCall, sdp string, mid string, mline int) {
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

	if call.pc != nil && call.pc.RemoteDescription() != nil {
		if err := call.pc.AddICECandidate(init); err != nil {
			fmt.Printf("[tg-call] AddICECandidate error: %v\n", err)
		}
	} else {
		call.pendingCandidates = append(call.pendingCandidates, init)
	}
}

func (t *TelegramCore) handleRemoteInitialSetupWeb(call *tgCall, setup *TgInitialSetup) {
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
		return
	}
	if call.pc == nil {
		fmt.Printf("[tg-call] Web: no PeerConnection\n")
		return
	}

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

	for _, c := range pending {
		if err := call.pc.AddICECandidate(c); err != nil {
			fmt.Printf("[tg-call] Web: AddICECandidate error: %v\n", err)
		}
	}

	if !call.isOutgoing {
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

		ourSetup := extractWebInitialSetupFromSDP(answer.SDP, false)
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

func (t *TelegramCore) handleRemoteInitialSetupV2Impl(call *tgCall, setup *TgInitialSetup) {
	call.mu.Lock()
	call.remoteInitialSetup = setup
	call.v2ImplHandshakeDone = true
	hasNC := call.remoteNegChannels != nil
	call.mu.Unlock()

	if hasNC {
		t.trySetRemoteV2Impl(call)
	}
}

func (t *TelegramCore) handleRemoteNegotiateChannelsV2Impl(call *tgCall, nc *tgNegotiateChannels) {
	call.mu.Lock()
	ourExchangeID := strconv.FormatUint(uint64(call.v2ImplExchangeSeq), 10)
	alreadySet := call.remoteSDPSet
	call.mu.Unlock()

	if nc.ExchangeID == ourExchangeID {
		call.mu.Lock()
		call.remoteNegChannels = nc
		hasSetup := call.remoteInitialSetup != nil
		call.mu.Unlock()

		if hasSetup {
			t.trySetRemoteV2Impl(call)
		}
	} else if alreadySet && call.isOutgoing {
		t.processRemoteV2ImplOffer(call, nc)
	} else if call.isOutgoing && nc.ExchangeID != ourExchangeID {
		call.mu.Lock()
		call.remoteNegChannelsOffer = nc
		call.mu.Unlock()
		fmt.Printf("[tg-call] V2Impl: stored remote's NegotiateChannels offer (exchangeId=%s) for later\n", nc.ExchangeID)
	} else {
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

func (t *TelegramCore) trySetRemoteV2Impl(call *tgCall) {
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

		for _, c := range pending {
			if err := call.pc.AddICECandidate(c); err != nil {
				fmt.Printf("[tg-call] V2Impl: AddICECandidate error: %v\n", err)
			}
		}
		if len(pending) > 0 {
			fmt.Printf("[tg-call] V2Impl: flushed %d pending candidates\n", len(pending))
		}

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

		call.mu.Lock()
		pendingOffer := call.remoteNegChannelsOffer
		call.remoteNegChannelsOffer = nil
		call.mu.Unlock()
		if pendingOffer != nil {
			t.processRemoteV2ImplOffer(call, pendingOffer)
		}
	} else {
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

		ourSetup, ourNC := extractV2ImplFromSDP(answer.SDP, false)
		t.sendCallSignaling(call, ourSetup)
		fmt.Printf("[tg-call] V2Impl: sent InitialSetup (ufrag=%s, setup=%s)\n",
			ourSetup.Ufrag, FingerprintLabel(*ourSetup))

		answerNC := &tgNegotiateChannels{
			Type:       "NegotiateChannels",
			ExchangeID: nc.ExchangeID,
			Contents:   nc.Contents,
		}
		t.sendCallSignaling(call, answerNC)
		fmt.Printf("[tg-call] V2Impl: sent NegotiateChannels answer (exchangeId=%s, ssrc=%s [echoed remote])\n",
			answerNC.ExchangeID, FirstSSRC(answerNC.Contents))

		var eidBuf [4]byte
		rand.Read(eidBuf[:])
		ownExchangeID := strconv.FormatUint(uint64(binary.BigEndian.Uint32(eidBuf[:])), 10)
		ourNC.ExchangeID = ownExchangeID
		t.sendCallSignaling(call, ourNC)
		fmt.Printf("[tg-call] V2Impl: sent NegotiateChannels own offer (exchangeId=%s, ssrc=%s)\n",
			ourNC.ExchangeID, FirstSSRC(ourNC.Contents))

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

func (t *TelegramCore) processRemoteV2ImplOffer(call *tgCall, nc *tgNegotiateChannels) {
	remoteSSRC := FirstSSRC(nc.Contents)

	call.mu.Lock()
	if call.answeredExchangeIDs == nil {
		call.answeredExchangeIDs = make(map[string]bool)
	}
	if call.answeredExchangeIDs[nc.ExchangeID] {
		call.mu.Unlock()
		return
	}
	call.answeredExchangeIDs[nc.ExchangeID] = true
	call.mu.Unlock()

	fmt.Printf("[tg-call] V2Impl: processing remote's NegotiateChannels offer (exchangeId=%s, ssrc=%s, contents=%d)\n",
		nc.ExchangeID, remoteSSRC, len(nc.Contents))

	answerNC := &tgNegotiateChannels{
		Type:       "NegotiateChannels",
		ExchangeID: nc.ExchangeID,
		Contents:   nc.Contents,
	}
	t.sendCallSignaling(call, answerNC)
	fmt.Printf("[tg-call] V2Impl: sent NC answer (echo, %d contents)\n", len(answerNC.Contents))

	call.mu.Lock()
	setup := call.remoteInitialSetup
	call.mu.Unlock()

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

func (t *TelegramCore) handleV2ImplReoffer(call *tgCall, setup *TgInitialSetup, nc *tgNegotiateChannels) {
	if call.localSDPReady != nil {
		select {
		case <-call.localSDPReady:
		case <-time.After(10 * time.Second):
			fmt.Printf("[tg-call] V2Impl reoffer: timeout waiting for local SDP ready\n")
			return
		}
	}

	syntheticOffer := buildSyntheticSDPFromV2Impl(setup, nc, "offer")
	fmt.Printf("[tg-call] V2Impl reoffer: built synthetic offer with remote SSRC (%d bytes)\n", len(syntheticOffer))

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

func generateICECredential(length int) string {
	const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, length)
	rand.Read(b)
	for i := range b {
		b[i] = chars[int(b[i])%len(chars)]
	}
	return string(b)
}

var TgGzipMaxDecompressed int64 = 128 * 1024 * 1024

func GzipDecompress(data []byte) ([]byte, error) {
	r, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer r.Close()
	out, err := io.ReadAll(io.LimitReader(r, TgGzipMaxDecompressed+1))
	if err != nil {
		return nil, err
	}
	if int64(len(out)) > TgGzipMaxDecompressed {
		return nil, fmt.Errorf("gzip: decompressed size exceeds %d bytes", TgGzipMaxDecompressed)
	}
	return out, nil
}

func (t *TelegramCore) JoinGroupCall(chatID string) (*CallSession, error) {
	return t.joinGroupCallInternal(chatID, false, nil)
}

func (t *TelegramCore) JoinGroupCallWithVideo(chatID string, video bool) (*CallSession, error) {
	return t.joinGroupCallInternal(chatID, video, nil)
}

func (t *TelegramCore) joinGroupCallInternal(chatID string, video bool, joinAs tg.InputPeerClass) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	callDone := make(chan struct{})

	var gcID int64
	var gcAccessHash int64
	peer, err := t.resolvePeer(chatID)
	if err == nil {
		gcID, gcAccessHash, err = t.resolveGroupCall(peer)
		if err != nil {
			return nil, err
		}
	} else {
		cid, parseErr := strconv.ParseInt(chatID, 10, 64)
		if parseErr != nil {
			return nil, fmt.Errorf("resolve peer: %w", err)
		}
		t.peerMu.RLock()
		hash, ok := t.confCallHash[cid]
		t.peerMu.RUnlock()
		if !ok {
			return nil, fmt.Errorf("resolve peer: %w (and no conference call found for ID %s)", err, chatID)
		}
		gcID = cid
		gcAccessHash = hash
	}

	fmt.Printf("[tg-group] Found group call: id=%d video=%v\n", gcID, video)

	t.mu.Lock()
	existing := t.activeCalls[gcID]
	if existing != nil && existing.pc != nil {
		t.mu.Unlock()
		return &CallSession{
			ID:    strconv.FormatInt(gcID, 10),
			State: existing.state,
		}, nil
	}
	if existing != nil {
		delete(t.activeCalls, gcID)
	}
	t.mu.Unlock()

	me := &wrtc.MediaEngine{}
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
		me.RegisterCodec(webrtc.RTPCodecParameters{
			RTPCodecCapability: webrtc.RTPCodecCapability{
				MimeType: "video/rtx", ClockRate: 90000,
				SDPFmtpLine: "apt=100",
			},
			PayloadType: 101,
		}, webrtc.RTPCodecTypeVideo)
		for _, ext := range []string{
			"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
			"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01",
			"urn:3gpp:video-orientation",
		} {
			me.RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability{URI: ext}, webrtc.RTPCodecTypeVideo)
		}
	}

	ir := &interceptor.Registry{}
	wrtc.ConfigureNack(me, ir)
	wrtc.ConfigureRTCPReports(ir)
	wrtc.ConfigureStatsInterceptor(ir)
	wrtc.ConfigureTWCCSender(me, ir)
	se := wrtc.SettingEngine{}
	se.SetIPFilter(func(ip net.IP) bool { return ip.To4() != nil })
	se.SetHandleUndeclaredSSRCWithoutAnswer(true)
	groupAPI := wrtc.NewAPI(
		wrtc.WithMediaEngine(me),
		wrtc.WithInterceptorRegistry(ir),
		wrtc.WithSettingEngine(se),
	)
	pc, err := groupAPI.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("create PeerConnection: %w", err)
	}

	audioRTPTrack, err := wrtc.NewTrackLocalStaticRTP(
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

	var videoTrackLocal *wrtc.TrackLocalStaticSample
	if video {
		videoTrackLocal, err = wrtc.NewTrackLocalStaticSample(
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

	offer, err := pc.CreateOffer(nil)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create offer: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set local desc: %w", err)
	}

	gatherDone := wrtc.GatheringCompletePromise(pc)
	<-gatherDone

	localDesc := pc.LocalDescription()
	if localDesc == nil {
		pc.Close()
		return nil, fmt.Errorf("no local description after gather")
	}
	var ufrag, pwd, fpHash, fpValue string
	var audioSSRC, videoSSRC uint32
	var videoRTXSSRC uint32
	currentMedia := ""
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
			parts := strings.Fields(strings.TrimPrefix(line, "a=ssrc-group:FID "))
			if len(parts) >= 2 {
				fmt.Sscanf(parts[0], "%d", &videoSSRC)
				fmt.Sscanf(parts[1], "%d", &videoRTXSSRC)
			}
		}
	}

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

	joinParams := map[string]interface{}{
		"ufrag": ufrag,
		"pwd":   pwd,
		"fingerprints": []map[string]string{{
			"hash":        fpHash,
			"fingerprint": fpValue,
			"setup":       "active",
		}},
		"ssrc":        int32(audioSSRC),
		"ssrc-groups": ssrcGroups,
	}
	paramsJSON, _ := json.Marshal(joinParams)
	fmt.Printf("[tg-group] Join params: %s\n", string(paramsJSON))

	inputGroupCall := &tg.InputGroupCall{ID: gcID, AccessHash: gcAccessHash}
	joinAsPeer := joinAs
	if joinAsPeer == nil {
		joinAsPeer = &tg.InputPeerSelf{}
	}
	var joinResp tg.UpdatesClass
	for attempt := 0; attempt < 3; attempt++ {
		joinResp, err = t.api.PhoneJoinGroupCall(t.ctx, &tg.PhoneJoinGroupCallRequest{
			Muted:        true,
			VideoStopped: !video,
			Call:         inputGroupCall,
			JoinAs:       joinAsPeer,
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

	var sfuTransportFromResponse string
	initialVideoEndpoints := make(map[string]string)
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
			if gcc, ok := upd.(*tg.UpdateGroupCallConnection); ok {
				sfuTransportFromResponse = gcc.Params.Data
				fmt.Printf("[tg-group] SFU transport in response: %d bytes (presentation=%v)\n",
					len(gcc.Params.Data), gcc.Presentation)
			}
		}
	}

	call := &tgCall{
		id:                   gcID,
		accessHash:           gcAccessHash,
		isGroupCall:          true,
		isVideo:              video,
		state:                CallStateConnecting,
		pc:                   pc,
		audioTrack:           audioRTPTrack,
		audioSSRC:            audioSSRC,
		done:                 callDone,
		sfuTransportReady:    make(chan struct{}),
		sfuDataChannel:       sfuDC,
		sfuDataChannelOpen:   make(chan struct{}),
		sfuRemoteVideoEndpts: initialVideoEndpoints,
		gcChatID:             chatID,
		audioLevels:          make(map[uint32]float64),
		audioLevelTs:         make(map[uint32]int64),
		ssrcToUser:           make(map[uint32]string),
	}

	pc.OnTrack(func(track *wrtc.TrackRemote, recv *webrtc.RTPReceiver) {
		trackSSRC := uint32(track.SSRC())
		codec := track.Codec().MimeType
		fmt.Printf("[tg-group] SFU track: kind=%s codec=%s ssrc=%d\n",
			track.Kind(), codec, trackSSRC)

		if track.Kind() == webrtc.RTPCodecTypeVideo {
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
					t.handleIncomingVideoRTP(call, pkt, false)
				}
			}()
		} else {
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
					if pkt.Header.Extension {
						if ext := pkt.Header.GetExtension(1); len(ext) >= 1 {
							if b := ext[0]; b&0x80 != 0 {
								dbov := int(b & 0x7F)
								lvl := float64(90-dbov) / 90.0
								if lvl < 0 {
									lvl = 0
								} else if lvl > 1 {
									lvl = 1
								}
								call.recordAudioLevel(trackSSRC, lvl)
							} else {
								call.recordAudioLevel(trackSSRC, 0)
							}
						}
					}
					if call.onAudioFrame != nil && len(pkt.Payload) > 0 {
						call.onAudioFrame(pkt.Payload)
					}
					call.writeRecordingFrame(pkt.Payload)
				}
			}()
		}
	})

	if sfuDC != nil {
		sfuDC.OnOpen(func() {
			fmt.Printf("[tg-group] Data channel open — ready for video subscription\n")
			close(call.sfuDataChannelOpen)
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

	if err := t.applySFUTransport(call); err != nil {
		pc.Close()
		t.mu.Lock()
		delete(t.activeCalls, gcID)
		t.mu.Unlock()
		return nil, fmt.Errorf("SFU transport: %w", err)
	}

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

func (t *TelegramCore) handleGroupCallConnection(paramsJSON string, isPresentation bool) {
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
		return
	}

	groupCall.sfuTransportJSON = paramsJSON
	select {
	case <-groupCall.sfuTransportReady:
	default:
		close(groupCall.sfuTransportReady)
	}
}

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
	Parameters json.RawMessage `json:"parameters,omitempty"`
	RTCPFbs    []struct {
		Type    string `json:"type"`
		Subtype string `json:"subtype,omitempty"`
	} `json:"rtcp-fbs,omitempty"`
}

type sfuHdrExt struct {
	ID  int    `json:"id"`
	URI string `json:"uri"`
}

func (t *TelegramCore) applySFUTransport(call *tgCall) error {
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

	if len(tr.Fingerprints) == 0 {
		return fmt.Errorf("sfu transport has no DTLS fingerprint")
	}
	fp := tr.Fingerprints[0]
	setup := fp.Setup
	if setup == "" {
		setup = "passive"
	}

	bundleMids := "0"
	if call.isVideo {
		bundleMids = "0 1 2"
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

	if err := call.pc.SetRemoteDescription(webrtc.SessionDescription{
		Type: webrtc.SDPTypeAnswer,
		SDP:  answerSDP,
	}); err != nil {
		return fmt.Errorf("SetRemoteDescription: %w", err)
	}
	fmt.Printf("[tg-group] Remote SDP answer set OK\n")

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

func (t *TelegramCore) sendSFUVideoConstraints(call *tgCall) {
	if call.sfuDataChannel == nil {
		return
	}

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
			call.sctpAssoc.Abort("call ended")
		}
		if call.sctpConn != nil {
			call.sctpConn.Close()
		}
		if call.pc != nil {
			call.pc.Close()
		}
		call.closeVideoCodecs()
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
		Duration:     0,
		Reason:       &tg.PhoneCallDiscardReasonHangup{},
		ConnectionID: 0,
	})
	return err
}

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
	t.fireCallStateUpdate(call)
	fmt.Printf("[tg-call] SetCallVideo: video=%v → MediaState videoState=%s\n", enabled, videoState)
	return nil
}

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
	t.fireCallStateUpdate(call)
	return nil
}

func (t *TelegramCore) ToggleCamera(callID string, enabled bool) error {
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
	screencastState := "inactive"
	if call.screenActive {
		screencastState = "active"
	}
	t.sendCallSignaling(call, tgMediaState{
		Type:            "MediaState",
		Muted:           call.muted,
		VideoState:      videoState,
		ScreencastState: screencastState,
	})
	t.fireCallStateUpdate(call)
	return nil
}

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

	p, g, err := t.getDHConfig()
	if err != nil {
		return nil, fmt.Errorf("DH config: %w", err)
	}

	b := make([]byte, 256)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return nil, fmt.Errorf("random: %w", err)
	}

	gBig := new(big.Int).SetInt64(int64(g))
	bBig := new(big.Int).SetBytes(b)
	pBig := new(big.Int).SetBytes(p)
	gB := new(big.Int).Exp(gBig, bBig, pBig)
	gBBytes := make([]byte, 256)
	gBBuf := gB.Bytes()
	copy(gBBytes[256-len(gBBuf):], gBBuf)

	t.mu.Lock()
	if t.pendingDH == nil {
		t.pendingDH = make(map[int64]*pendingDHState)
	}
	t.pendingDH[cid] = &pendingDHState{a: b, gA: gBBytes, p: p, g: g}
	t.mu.Unlock()

	versions := filterVersions(
		[]string{"13.0.0", "8.0.0", "4.0.0"},
		t.maxCallVersion, t.minCallVersion,
	)
	_, err = t.api.PhoneAcceptCall(t.ctx, &tg.PhoneAcceptCallRequest{
		Peer: tg.InputPhoneCall{ID: cid, AccessHash: call.accessHash},
		GB:   gBBytes,
		Protocol: tg.PhoneCallProtocol{
			Flags:           0b11,
			MinLayer:        65,
			MaxLayer:        92,
			LibraryVersions: versions,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("phone.acceptCall: %w", err)
	}
	fmt.Printf("[tg-call] acceptCall OK — waiting for PhoneCall update with g_a\n")

	return &CallSession{
		ID:      callID,
		ChatID:  strconv.FormatInt(call.peerID, 10),
		IsVideo: call.isVideo,
		State:   CallStateConnecting,
	}, nil
}

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

func (t *TelegramCore) EndGroupCall(callID string) error {
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

	_, err = t.api.PhoneDiscardGroupCall(t.ctx, &tg.InputGroupCall{
		ID:         cid,
		AccessHash: call.accessHash,
	})
	if err != nil {
		return fmt.Errorf("phone.discardGroupCall: %w", err)
	}

	fmt.Printf("[tg-group] Ended (discarded) group call: id=%d\n", cid)
	return nil
}

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

	screenTrack, err := wrtc.NewTrackLocalStaticSample(
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

	screenSSRC := uint32(time.Now().UnixNano() & 0x7FFFFFFF)
	rtxSSRC := screenSSRC + 1

	call.screenTrack = screenTrack
	call.screenSSRC = screenSSRC
	call.screenActive = true

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
	t.fireCallStateUpdate(call)
	return nil
}

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
	t.fireCallStateUpdate(call)
	return nil
}

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

func (t *TelegramCore) MuteGroupCallParticipant(callID string, userID string, mute bool) error {
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

	req := &tg.PhoneEditGroupCallParticipantRequest{
		Call:        &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)},
	}
	req.SetMuted(mute)
	_, err = t.api.PhoneEditGroupCallParticipant(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.editGroupCallParticipant: %w", err)
	}
	fmt.Printf("[tg-group] MuteGroupCallParticipant %s mute=%v in group call %s\n", userID, mute, callID)
	return nil
}

func (t *TelegramCore) resolveActiveGroupCall(callID string) (int64, *tgCall, error) {
	t.mu.RLock()
	authed := t.authed && t.api != nil
	t.mu.RUnlock()
	if !authed {
		return 0, nil, ErrAuth
	}
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return 0, nil, fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil || !call.isGroupCall {
		return 0, nil, fmt.Errorf("no active group call %s", callID)
	}
	return cid, call, nil
}

func (c *tgCall) recordAudioLevel(ssrc uint32, level float64) {
	if c.audioLevels == nil {
		return
	}
	c.audioLevelMu.Lock()
	prev := c.audioLevels[ssrc]
	if level > prev {
		c.audioLevels[ssrc] = level
	} else {
		c.audioLevels[ssrc] = prev*0.65 + level*0.35
	}
	c.audioLevelTs[ssrc] = time.Now().UnixMilli()
	c.audioLevelMu.Unlock()
}

func (t *TelegramCore) GetGroupCallAudioLevels(chatID string) (map[string]float64, error) {
	t.mu.RLock()
	var call *tgCall
	for _, c := range t.activeCalls {
		if c.isGroupCall && c.gcChatID == chatID {
			call = c
			break
		}
	}
	t.mu.RUnlock()
	out := make(map[string]float64)
	if call == nil {
		return out, nil
	}
	nowMs := time.Now().UnixMilli()
	call.audioLevelMu.Lock()
	for ssrc, lvl := range call.audioLevels {
		uid := call.ssrcToUser[ssrc]
		if uid == "" {
			continue
		}
		if nowMs-call.audioLevelTs[ssrc] > 250 || lvl < 0.02 {
			continue
		}
		if lvl > out[uid] {
			out[uid] = lvl
		}
	}
	call.audioLevelMu.Unlock()
	return out, nil
}

func (t *TelegramCore) GetGroupCallSettings(callID string) (bool, bool, error) {
	cid, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		return false, false, err
	}
	call.gcSettingsMu.Lock()
	loaded := call.gcSettingsLoaded
	jm, me := call.gcJoinMuted, call.gcMessagesEnabled
	ah := call.accessHash
	call.gcSettingsMu.Unlock()
	if loaded {
		return jm, me, nil
	}
	res, ferr := t.api.PhoneGetGroupCall(t.ctx, &tg.PhoneGetGroupCallRequest{
		Call:  &tg.InputGroupCall{ID: cid, AccessHash: ah},
		Limit: 1,
	})
	if ferr != nil {
		return jm, me, nil
	}
	if gc, ok := res.Call.(*tg.GroupCall); ok {
		jm, me = gc.JoinMuted, gc.MessagesEnabled
		call.gcSettingsMu.Lock()
		call.gcJoinMuted, call.gcMessagesEnabled, call.gcSettingsLoaded = jm, me, true
		call.gcSettingsMu.Unlock()
	}
	return jm, me, nil
}

func (t *TelegramCore) InviteToGroupCall(callID string, userIDs []string) error {
	cid, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		return err
	}
	users := make([]tg.InputUserClass, 0, len(userIDs))
	for _, uid := range userIDs {
		id, perr := strconv.ParseInt(uid, 10, 64)
		if perr != nil {
			continue
		}
		users = append(users, &tg.InputUser{UserID: id, AccessHash: t.getCachedUserHash(id)})
	}
	if len(users) == 0 {
		return fmt.Errorf("no valid users to invite")
	}
	_, err = t.api.PhoneInviteToGroupCall(t.ctx, &tg.PhoneInviteToGroupCallRequest{
		Call:  &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Users: users,
	})
	return err
}

func (t *TelegramCore) SetNoiseSuppression(callID string, enabled bool) error {
	_, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		cid, perr := strconv.ParseInt(callID, 10, 64)
		if perr != nil {
			return err
		}
		t.mu.RLock()
		call = t.activeCalls[cid]
		t.mu.RUnlock()
		if call == nil {
			return err
		}
	}
	call.gcSettingsMu.Lock()
	call.noiseSuppression = enabled
	call.gcSettingsMu.Unlock()
	return nil
}

func (t *TelegramCore) EditGroupCallTitle(callID, title string) error {
	cid, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		return err
	}
	_, err = t.api.PhoneEditGroupCallTitle(t.ctx, &tg.PhoneEditGroupCallTitleRequest{
		Call:  &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Title: title,
	})
	if err != nil {
		return fmt.Errorf("phone.editGroupCallTitle: %w", err)
	}
	fmt.Printf("[tg-group] EditGroupCallTitle %s -> %q\n", callID, title)
	return nil
}

func (t *TelegramCore) ToggleGroupCallRecord(callID string, start bool, title string, video bool, videoPortrait bool) error {
	cid, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		return err
	}
	req := &tg.PhoneToggleGroupCallRecordRequest{
		Call: &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
	}
	if start {
		req.SetStart(true)
	}
	if video {
		req.SetVideo(true)
		req.SetVideoPortrait(videoPortrait)
	}
	if title != "" {
		req.SetTitle(title)
	}
	_, err = t.api.PhoneToggleGroupCallRecord(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.toggleGroupCallRecord: %w", err)
	}
	fmt.Printf("[tg-group] ToggleGroupCallRecord %s start=%v video=%v portrait=%v title=%q\n",
		callID, start, video, videoPortrait, title)
	return nil
}

func (t *TelegramCore) SetGroupCallMuteNewParticipants(callID string, muted bool) error {
	cid, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		return err
	}
	req := &tg.PhoneToggleGroupCallSettingsRequest{
		Call: &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
	}
	req.SetJoinMuted(muted)
	_, err = t.api.PhoneToggleGroupCallSettings(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.toggleGroupCallSettings(join_muted): %w", err)
	}
	fmt.Printf("[tg-group] SetGroupCallMuteNewParticipants %s muted=%v\n", callID, muted)
	return nil
}

func (t *TelegramCore) SetGroupCallMessagesEnabled(callID string, enabled bool) error {
	cid, call, err := t.resolveActiveGroupCall(callID)
	if err != nil {
		return err
	}
	req := &tg.PhoneToggleGroupCallSettingsRequest{
		Call: &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
	}
	req.SetMessagesEnabled(enabled)
	_, err = t.api.PhoneToggleGroupCallSettings(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.toggleGroupCallSettings(messages_enabled): %w", err)
	}
	fmt.Printf("[tg-group] SetGroupCallMessagesEnabled %s enabled=%v\n", callID, enabled)
	return nil
}

func (c *tgCall) storeOutgoingFrame(kind string, yuv420p []byte, width, height int) {
	if len(yuv420p) == 0 || width <= 0 || height <= 0 {
		return
	}
	cp := make([]byte, len(yuv420p))
	copy(cp, yuv420p)
	c.outgoingFrameMu.Lock()
	if kind == "screen" {
		c.outgoingScreenFrame, c.outgoingScreenW, c.outgoingScreenH = cp, width, height
	} else {
		c.outgoingCameraFrame, c.outgoingCameraW, c.outgoingCameraH = cp, width, height
	}
	c.outgoingFrameMu.Unlock()
}

func (t *TelegramCore) GetGroupCallVideoFrame(callID, endpoint string) ([]byte, int, int, error) {
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return nil, 0, 0, fmt.Errorf("invalid call ID: %w", err)
	}
	t.mu.RLock()
	call := t.activeCalls[cid]
	t.mu.RUnlock()
	if call == nil {
		return nil, 0, 0, fmt.Errorf("no active call %s", callID)
	}
	var yuv []byte
	var w, h int
	switch endpoint {
	case "outgoing_camera":
		call.outgoingFrameMu.Lock()
		yuv, w, h = call.outgoingCameraFrame, call.outgoingCameraW, call.outgoingCameraH
		call.outgoingFrameMu.Unlock()
	case "outgoing_screen":
		call.outgoingFrameMu.Lock()
		yuv, w, h = call.outgoingScreenFrame, call.outgoingScreenW, call.outgoingScreenH
		call.outgoingFrameMu.Unlock()
	case "screen":
		call.incomingFrameMu.Lock()
		yuv, w, h = call.incomingScreenFrame, call.incomingScreenW, call.incomingScreenH
		call.incomingFrameMu.Unlock()
	default:
		call.incomingFrameMu.Lock()
		yuv, w, h = call.incomingCameraFrame, call.incomingCameraW, call.incomingCameraH
		call.incomingFrameMu.Unlock()
	}
	if len(yuv) == 0 || w <= 0 || h <= 0 {
		return nil, 0, 0, nil
	}
	rgba := yuv420pToRGBA(yuv, w, h)
	if rgba == nil {
		return nil, 0, 0, nil
	}
	return rgba, w, h, nil
}

func yuv420pToRGBA(yuv []byte, w, h int) []byte {
	cw := (w + 1) / 2
	ySize := w * h
	cSize := cw * ((h + 1) / 2)
	if len(yuv) < ySize+2*cSize {
		return nil
	}
	uPlane := yuv[ySize:]
	vPlane := yuv[ySize+cSize:]
	rgba := make([]byte, w*h*4)
	clamp := func(v int) byte {
		if v < 0 {
			return 0
		}
		if v > 255 {
			return 255
		}
		return byte(v)
	}
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			yi := y*w + x
			ci := (y/2)*cw + (x / 2)
			c := int(yuv[yi]) - 16
			d := int(uPlane[ci]) - 128
			e := int(vPlane[ci]) - 128
			o := yi * 4
			rgba[o] = clamp((298*c + 409*e + 128) >> 8)
			rgba[o+1] = clamp((298*c - 100*d - 208*e + 128) >> 8)
			rgba[o+2] = clamp((298*c + 516*d + 128) >> 8)
			rgba[o+3] = 255
		}
	}
	return rgba
}

func (t *TelegramCore) KickGroupCallParticipant(callID string, userID string) error {
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

	req := &tg.PhoneEditGroupCallParticipantRequest{
		Call:        &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)},
	}
	req.SetMuted(true)
	req.SetVolume(0)
	_, err = t.api.PhoneEditGroupCallParticipant(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.editGroupCallParticipant: %w", err)
	}
	fmt.Printf("[tg-group] KickGroupCallParticipant %s from group call %s\n", userID, callID)
	return nil
}

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

func (t *TelegramCore) RaiseHand(callID string, raised bool) error {
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
	req.SetRaiseHand(raised)
	_, err = t.api.PhoneEditGroupCallParticipant(t.ctx, req)
	if err != nil {
		return fmt.Errorf("phone.editGroupCallParticipant: %w", err)
	}
	fmt.Printf("[tg-group] RaiseHand: raised=%v in group call %s\n", raised, callID)
	return nil
}

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

	if rating < 1 {
		rating = 1
	}
	if rating > 5 {
		rating = 5
	}

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

type JoinAsPeerInfo struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Subtitle  string `json:"subtitle"`
	IsSelf    bool   `json:"is_self"`
	IsChannel bool   `json:"is_channel"`
}

func (t *TelegramCore) GetGroupCallJoinAsPeers(chatID string) ([]JoinAsPeerInfo, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	selfID := t.selfID
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, fmt.Errorf("resolve peer: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, fmt.Errorf("input peer: %w", err)
	}

	res, err := t.api.PhoneGetGroupCallJoinAs(t.ctx, inputPeer)
	if err != nil {
		return nil, fmt.Errorf("phone.getGroupCallJoinAs: %w", err)
	}

	users := map[int64]*tg.User{}
	for _, u := range res.Users {
		if uu, ok := u.(*tg.User); ok {
			users[uu.ID] = uu
		}
	}
	chans := map[int64]*tg.Channel{}
	chats := map[int64]*tg.Chat{}
	for _, c := range res.Chats {
		switch cc := c.(type) {
		case *tg.Channel:
			chans[cc.ID] = cc
		case *tg.Chat:
			chats[cc.ID] = cc
		}
	}

	out := make([]JoinAsPeerInfo, 0, len(res.Peers))
	for _, p := range res.Peers {
		switch pp := p.(type) {
		case *tg.PeerUser:
			name := ""
			if u := users[pp.UserID]; u != nil {
				name = strings.TrimSpace(u.FirstName + " " + u.LastName)
				if name == "" {
					name = u.Username
				}
			}
			isSelf := pp.UserID == selfID
			sub := ""
			if isSelf {
				sub = "Personal account"
			}
			out = append(out, JoinAsPeerInfo{
				ID:       strconv.FormatInt(pp.UserID, 10),
				Title:    name,
				Subtitle: sub,
				IsSelf:   isSelf,
			})
		case *tg.PeerChannel:
			name, sub := "", ""
			if c := chans[pp.ChannelID]; c != nil {
				name = c.Title
				count, _ := c.GetParticipantsCount()
				if c.Broadcast {
					sub = fmt.Sprintf("%d subscribers", count)
				} else {
					sub = fmt.Sprintf("%d members", count)
				}
			}
			out = append(out, JoinAsPeerInfo{
				ID:        strconv.FormatInt(-(pp.ChannelID + 1000000000000), 10),
				Title:     name,
				Subtitle:  sub,
				IsChannel: true,
			})
		case *tg.PeerChat:
			name, sub := "", ""
			if c := chats[pp.ChatID]; c != nil {
				name = c.Title
				sub = fmt.Sprintf("%d members", c.ParticipantsCount)
			}
			out = append(out, JoinAsPeerInfo{
				ID:       strconv.FormatInt(-pp.ChatID, 10),
				Title:    name,
				Subtitle: sub,
			})
		}
	}
	return out, nil
}

func (t *TelegramCore) JoinGroupCallAs(chatID, joinAsChatID string) (*CallSession, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return nil, ErrAuth
	}
	t.mu.RUnlock()

	joinAsPeerClass, err := t.resolvePeer(joinAsChatID)
	if err != nil {
		return nil, fmt.Errorf("resolve join-as peer: %w", err)
	}
	joinAsInput, err := t.toInputPeer(joinAsPeerClass)
	if err != nil {
		return nil, fmt.Errorf("join-as input peer: %w", err)
	}

	if dialogPeer, derr := t.resolvePeer(chatID); derr == nil {
		if dialogInput, ierr := t.toInputPeer(dialogPeer); ierr == nil {
			_, _ = t.api.PhoneSaveDefaultGroupCallJoinAs(t.ctx, &tg.PhoneSaveDefaultGroupCallJoinAsRequest{
				Peer:   dialogInput,
				JoinAs: joinAsInput,
			})
		}
	}

	return t.joinGroupCallInternal(chatID, false, joinAsInput)
}

func (t *TelegramCore) SendGroupCallMessage(chatID, text string) error {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return ErrAuth
	}
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return fmt.Errorf("resolve peer: %w", err)
	}
	gcID, gcAccessHash, err := t.resolveGroupCall(peer)
	if err != nil {
		return err
	}
	_, err = t.api.PhoneSendGroupCallMessage(t.ctx, &tg.PhoneSendGroupCallMessageRequest{
		Call:     &tg.InputGroupCall{ID: gcID, AccessHash: gcAccessHash},
		RandomID: time.Now().UnixNano(),
		Message:  tg.TextWithEntities{Text: text},
	})
	if err != nil {
		return fmt.Errorf("phone.sendGroupCallMessage: %w", err)
	}
	return nil
}

func (t *TelegramCore) GetGroupCallScheduleSubscribed(chatID string) (bool, error) {
	t.mu.RLock()
	if !t.authed || t.api == nil {
		t.mu.RUnlock()
		return false, ErrAuth
	}
	t.mu.RUnlock()

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return false, fmt.Errorf("resolve peer: %w", err)
	}
	gcID, gcAccessHash, err := t.resolveGroupCall(peer)
	if err != nil {
		return false, err
	}
	res, err := t.api.PhoneGetGroupCall(t.ctx, &tg.PhoneGetGroupCallRequest{
		Call:  &tg.InputGroupCall{ID: gcID, AccessHash: gcAccessHash},
		Limit: 1,
	})
	if err != nil {
		return false, fmt.Errorf("phone.getGroupCall: %w", err)
	}
	if gc, ok := res.Call.(*tg.GroupCall); ok {
		return gc.ScheduleStartSubscribed, nil
	}
	return false, nil
}

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

func (t *TelegramCore) ToggleGroupCallStartSubscription(callID string, subscribed bool) error {
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

	_, err = t.api.PhoneToggleGroupCallStartSubscription(t.ctx,
		&tg.PhoneToggleGroupCallStartSubscriptionRequest{
			Call:       &tg.InputGroupCall{ID: cid, AccessHash: call.accessHash},
			Subscribed: subscribed,
		})
	if err != nil {
		return fmt.Errorf("phone.toggleGroupCallStartSubscription: %w", err)
	}

	fmt.Printf("[tg-group] Toggled scheduled call %d subscription=%v\n", cid, subscribed)
	return nil
}

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
		tsIncrement = 960
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
	if call.isGroupCall {
		pkt.Header.Extension = true
		pkt.Header.ExtensionProfile = 0xBEDE
		pkt.Header.SetExtension(1, []byte{0x9E})
	}
	return call.audioTrack.WriteRTP(pkt)
}

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
		Duration: 33 * time.Millisecond,
	})
}

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
	call.storeOutgoingFrame("camera", yuv420p, width, height)
	if call.videoTrack == nil {
		return fmt.Errorf("no video track (call not started as video)")
	}
	if call.videoEncoder == nil {
		factory := t.newVideoEncoder
		if factory == nil {
			return fmt.Errorf("no video encoder factory set; call SetVideoEncoderFactory first")
		}
		enc, err := factory(width, height, 500000)
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
		return nil
	}
	return call.videoTrack.WriteSample(pionmedia.Sample{
		Data:     vp8Frame,
		Duration: 33 * time.Millisecond,
	})
}

func (t *TelegramCore) SetVideoEncoderFactory(f func(width, height, bitrate int) (VideoEncoder, error)) {
	t.newVideoEncoder = f
}

func (t *TelegramCore) SetVideoDecoderFactory(f func() (VideoDecoder, error)) {
	t.newVideoDecoder = f
}

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
	if call.videoDecoder == nil && t.newVideoDecoder != nil {
		dec, err := t.newVideoDecoder()
		if err != nil {
			return fmt.Errorf("create video decoder: %w", err)
		}
		call.videoDecoder = dec
	}
	return nil
}

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
	call.storeOutgoingFrame("screen", yuv420p, width, height)
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
		return nil
	}
	if call.screenTrack == nil {
		return fmt.Errorf("no screen track (Web signaling required)")
	}

	if call.screenSSRC == 0 {
		var buf [4]byte
		rand.Read(buf[:])
		call.screenSSRC = binary.BigEndian.Uint32(buf[:])
	}

	call.screenActive = true
	fmt.Printf("[tg-call] Screen sharing started (ssrc=%d)\n", call.screenSSRC)

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
	t.fireCallStateUpdate(call)
	return nil
}

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
		return nil
	}

	call.screenActive = false
	fmt.Printf("[tg-call] Screen sharing stopped\n")

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
	t.fireCallStateUpdate(call)
	return nil
}

func (t *TelegramCore) SetScreenSharing(callID string, enabled bool) error {
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
	if call.isGroupCall {
		if enabled {
			return t.StartGroupCallScreenShare(callID)
		}
		return t.StopGroupCallScreenShare(callID)
	}
	if enabled {
		return t.StartScreenShare(callID)
	}
	return t.StopScreenShare(callID)
}

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

	pos, _ := f.Seek(0, 2)
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

	var countBuf [4]byte
	binary.LittleEndian.PutUint32(countBuf[:], uint32(frameCount))
	f.Seek(4, 0)
	f.Write(countBuf[:])

	f.Close()
	fmt.Printf("[tg-call] Recording stopped: %d frames\n", frameCount)
	return frameCount, nil
}

func (t *TelegramCore) readSenderRTCP(call *tgCall, sender *wrtc.RTPSender, isScreen bool) {
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

func (t *TelegramCore) handleIncomingVideoRTP(call *tgCall, pkt *pionrtp.Packet, isScreen bool) {
	if len(pkt.Payload) == 0 {
		return
	}

	vp8Data, isStart := stripVP8RTPDescriptor(pkt.Payload)
	if vp8Data == nil {
		return
	}

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

	if isStart {
		*frameBuf = (*frameBuf)[:0]
	}
	*frameBuf = append(*frameBuf, vp8Data...)

	if pkt.Header.Marker {
		completeFrame := append([]byte(nil), *frameBuf...)
		*frameBuf = (*frameBuf)[:0]

		if onRawFrame != nil {
			onRawFrame(completeFrame)
		}

		if call.videoDecoder != nil {
			yuv, w, h, err := call.videoDecoder.Decode(completeFrame)
			if err == nil && yuv != nil {
				if onDecodedFrame != nil {
					onDecodedFrame(yuv, w, h)
				}
				call.storeIncomingFrame(isScreen, yuv, w, h)
			}
		}
	}
}

func (c *tgCall) storeIncomingFrame(isScreen bool, yuv []byte, w, h int) {
	frame := append([]byte(nil), yuv...)
	c.incomingFrameMu.Lock()
	if isScreen {
		c.incomingScreenFrame, c.incomingScreenW, c.incomingScreenH = frame, w, h
	} else {
		c.incomingCameraFrame, c.incomingCameraW, c.incomingCameraH = frame, w, h
	}
	c.incomingFrameMu.Unlock()
}

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
				i++
			}
			i++
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
	call.externalAudio = enabled
	fmt.Printf("[tg-call] Echo mode %s for call %s\n", map[bool]string{true: "ENABLED", false: "disabled"}[enabled], callID)
	return nil
}

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
	call.audioTSIncrement = uint32(48000 * durationMs / 1000)
	call.externalAudio = true
	fmt.Printf("[tg-call] Audio frame duration set to %dms (%d samples) for call %s, silence sender stopped\n",
		durationMs, call.audioTSIncrement, callID)
	return nil
}

func (t *TelegramCore) GetProfile(userID string) (*User, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
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
	users, err := api.UsersGetUsers(ctx, []tg.InputUserClass{inputUser})
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

	t.cacheUserHash(user.ID, user.AccessHash)

	return t.convertUser(user), nil
}

func (t *TelegramCore) CreateGroup(name string, members []string) (*Dialog, error) {
	return t.CreateGroupWithTTL(name, members, 0)
}

func (t *TelegramCore) CreateGroupWithTTL(name string, members []string, ttlSeconds int) (*Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	var users []tg.InputUserClass
	for _, m := range members {
		id, err := tgUserID(m)
		if err != nil {
			return nil, err
		}
		users = append(users, &tg.InputUser{UserID: id})
	}

	req := &tg.MessagesCreateChatRequest{
		Title: name,
		Users: users,
	}
	if ttlSeconds > 0 {
		req.SetTTLPeriod(ttlSeconds)
	}

	result, err := api.MessagesCreateChat(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("create group: %w", err)
	}

	if result != nil && result.Updates != nil {
		return t.extractDialogFromUpdates(result.Updates), nil
	}
	return &Dialog{Title: name, Type: ChatTypeGroup, Platform: tgPlatform}, nil
}

func (t *TelegramCore) SetChatTTL(chatID string, ttlSeconds int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesSetHistoryTTL(t.ctx, &tg.MessagesSetHistoryTTLRequest{
		Peer:   inputPeer,
		Period: ttlSeconds,
	})
	if err != nil {
		return fmt.Errorf("set history ttl: %w", err)
	}
	return nil
}

func (t *TelegramCore) CreateChannel(name string, description string) (*Dialog, error) {
	return t.RawCreateChannel(name, description, true, false)
}

func (t *TelegramCore) RawCreateChannel(name, description string, broadcast, megagroup bool) (*Dialog, error) {
	return t.RawCreateChannelFull(name, description, broadcast, megagroup, false, 0)
}

func (t *TelegramCore) RawCreateChannelFull(name, description string, broadcast, megagroup, forum bool, ttlPeriod int) (*Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	req := &tg.ChannelsCreateChannelRequest{
		Title:     name,
		About:     description,
		Broadcast: broadcast,
		Megagroup: megagroup,
		Forum:     forum,
	}
	if ttlPeriod > 0 {
		req.SetTTLPeriod(ttlPeriod)
	}
	result, err := api.ChannelsCreateChannel(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("create channel: %w", err)
	}

	return t.extractDialogFromUpdates(result), nil
}

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

func (t *TelegramCore) GetFolders() ([]Folder, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesGetDialogFilters(ctx)
	if err != nil {
		return nil, fmt.Errorf("get folders: %w", err)
	}

	var folders []Folder
	for _, f := range result.GetFilters() {
		var folder Folder

		switch filter := f.(type) {
		case *tg.DialogFilter:
			emoticon, _ := filter.GetEmoticon()
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
				Emoticon:        emoticon,
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
			folder = Folder{
				ID:         strconv.Itoa(filter.ID),
				Name:       filter.Title.Text,
				IsChatList: true,
			}
			for _, p := range filter.IncludePeers {
				folder.ChatIDs = append(folder.ChatIDs, inputPeerToID(p))
			}
			for _, p := range filter.PinnedPeers {
				folder.PinnedChatIDs = append(folder.PinnedChatIDs, inputPeerToID(p))
			}

		default:
			continue
		}
		log.Printf("[tg-folders] Folder %q (id=%s): contacts=%v nonContacts=%v groups=%v channels=%v bots=%v excludeMuted=%v excludeRead=%v excludeArchived=%v includes=%d excludes=%d pinned=%d includeIDs=%v",
			folder.Name, folder.ID, folder.Contacts, folder.NonContacts, folder.Groups, folder.Channels, folder.Bots,
			folder.ExcludeMuted, folder.ExcludeRead, folder.ExcludeArchived,
			len(folder.ChatIDs), len(folder.ExcludeChatIDs), len(folder.PinnedChatIDs), folder.ChatIDs)
		folders = append(folders, folder)
	}
	return folders, nil
}

func (t *TelegramCore) CreateFolder(name string, chatIDs []string) (*Folder, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
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

	filterID := int(time.Now().Unix()%200) + 20

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
	filter.SetFlags()

	_, err = api.MessagesUpdateDialogFilter(ctx, &tg.MessagesUpdateDialogFilterRequest{
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

func (t *TelegramCore) CreateFolderWithFlags(name string, chatIDs []string, contacts, nonContacts, groups, channels, bots bool) (*Folder, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
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

	filterID := int(time.Now().Unix()%200) + 20

	titleRunes := []rune(name)
	if len(titleRunes) > 12 {
		titleRunes = titleRunes[:12]
	}
	filter := &tg.DialogFilter{
		ID:           filterID,
		Title:        tg.TextWithEntities{Text: string(titleRunes), Entities: []tg.MessageEntityClass{}},
		Contacts:     contacts,
		NonContacts:  nonContacts,
		Groups:       groups,
		Broadcasts:   channels,
		Bots:         bots,
		IncludePeers: peers,
		PinnedPeers:  []tg.InputPeerClass{},
		ExcludePeers: []tg.InputPeerClass{},
	}
	filter.SetFlags()

	_, err = api.MessagesUpdateDialogFilter(ctx, &tg.MessagesUpdateDialogFilterRequest{
		ID:     filterID,
		Filter: filter,
	})
	if err != nil {
		return nil, fmt.Errorf("create folder: %w", err)
	}

	return &Folder{
		ID:          strconv.Itoa(filterID),
		Name:        name,
		ChatIDs:     chatIDs,
		Contacts:    contacts,
		NonContacts: nonContacts,
		Groups:      groups,
		Channels:    channels,
		Bots:        bots,
	}, nil
}

func (t *TelegramCore) UpdateDialogFilterFull(
	filterID int,
	isChatList bool,
	name string,
	includeIDs, excludeIDs, pinnedIDs []string,
	contacts, nonContacts, groups, channels, bots bool,
	excludeMuted, excludeRead, excludeArchived bool,
	colorIndex int,
	emoticon string,
	staticTitle bool,
) (*Folder, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	resolve := func(ids []string) []tg.InputPeerClass {
		peers := make([]tg.InputPeerClass, 0, len(ids))
		for _, cid := range ids {
			peer, err := t.resolvePeer(cid)
			if err != nil {
				continue
			}
			inputPeer, err := t.toInputPeer(peer)
			if err != nil {
				continue
			}
			peers = append(peers, inputPeer)
		}
		return peers
	}
	includePeers := resolve(includeIDs)
	excludePeers := resolve(excludeIDs)
	pinnedPeers := resolve(pinnedIDs)
	if pinnedPeers == nil {
		pinnedPeers = []tg.InputPeerClass{}
	}

	if filterID <= 0 {
		filterID = int(time.Now().Unix()%200) + 20
	}

	titleRunes := []rune(name)
	if len(titleRunes) > 12 {
		titleRunes = titleRunes[:12]
	}
	title := tg.TextWithEntities{Text: string(titleRunes), Entities: []tg.MessageEntityClass{}}

	var filter tg.DialogFilterClass
	if isChatList {
		f := &tg.DialogFilterChatlist{
			ID:           filterID,
			Title:        title,
			Emoticon:     emoticon,
			IncludePeers: includePeers,
			PinnedPeers:  pinnedPeers,
		}
		if colorIndex >= 0 && colorIndex <= 6 {
			f.SetColor(colorIndex)
		}
		if staticTitle {
			f.SetTitleNoanimate(true)
		}
		f.SetFlags()
		filter = f
	} else {
		f := &tg.DialogFilter{
			ID:              filterID,
			Title:           title,
			Contacts:        contacts,
			NonContacts:     nonContacts,
			Groups:          groups,
			Broadcasts:      channels,
			Bots:            bots,
			ExcludeMuted:    excludeMuted,
			ExcludeRead:     excludeRead,
			ExcludeArchived: excludeArchived,
			Emoticon:        emoticon,
			IncludePeers:    includePeers,
			ExcludePeers:    excludePeers,
			PinnedPeers:     pinnedPeers,
		}
		if colorIndex >= 0 && colorIndex <= 6 {
			f.SetColor(colorIndex)
		}
		if staticTitle {
			f.SetTitleNoanimate(true)
		}
		f.SetFlags()
		filter = f
	}

	if _, err := api.MessagesUpdateDialogFilter(ctx, &tg.MessagesUpdateDialogFilterRequest{
		ID:     filterID,
		Filter: filter,
	}); err != nil {
		return nil, fmt.Errorf("save folder: %w", err)
	}

	return &Folder{
		ID:              strconv.Itoa(filterID),
		Name:            name,
		ChatIDs:         includeIDs,
		ExcludeChatIDs:  excludeIDs,
		PinnedChatIDs:   pinnedIDs,
		Contacts:        contacts,
		NonContacts:     nonContacts,
		Groups:          groups,
		Channels:        channels,
		Bots:            bots,
		ExcludeMuted:    excludeMuted,
		ExcludeRead:     excludeRead,
		ExcludeArchived: excludeArchived,
		IsChatList:      isChatList,
		Emoticon:        emoticon,
	}, nil
}

func (t *TelegramCore) OnUpdate(handler func(Update)) {
	t.updateMu.Lock()
	defer t.updateMu.Unlock()
	t.updateHandlers = append(t.updateHandlers, handler)
}

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

func (t *TelegramCore) teardownPriorAuthAttempt() {
	t.mu.Lock()
	cancel := t.cancel
	t.mu.Unlock()
	if cancel == nil {
		return
	}
	cancel()
	t.wg.Wait()

	t.mu.Lock()
	t.cancel = nil
	t.api = nil
	t.sender = nil
	t.preAuthAPI = nil
	t.authed = false
	select {
	case <-t.authSetupDone:
		t.authSetupDone = make(chan struct{})
	default:
	}
	t.mu.Unlock()
}

const telegramServiceUserID = 777000

func extractLoginCode(msg *tg.Message) string {
	if msg.Out {
		return ""
	}
	pu, ok := msg.PeerID.(*tg.PeerUser)
	if !ok || pu.UserID != telegramServiceUserID {
		return ""
	}
	for _, ent := range msg.Entities {
		if tu, ok := ent.(*tg.MessageEntityTextURL); ok {
			if code := loginCodeFromURL(tu.URL); code != "" {
				return code
			}
		}
	}
	return loginCodeFromURL(msg.Message)
}

func loginCodeFromURL(s string) string {
	for _, marker := range []string{"login?code=", "login/?code="} {
		i := strings.Index(s, marker)
		if i < 0 {
			continue
		}
		rest := s[i+len(marker):]
		end := 0
		for end < len(rest) && rest[end] >= '0' && rest[end] <= '9' {
			end++
		}
		if end > 0 {
			return rest[:end]
		}
	}
	return ""
}

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

func tgMsgID(s string) (int, error) {
	id, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("invalid message ID %q: %w", s, err)
	}
	return id, nil
}

func tgUserID(s string) (int64, error) {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid ID %q: %w", s, err)
	}
	return id, nil
}

func (t *TelegramCore) withPeer(chatID string) (tg.InputPeerClass, func(), error) {
	if _, _, err := t.WithAPI(); err != nil {
		return nil, nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, nil, err
	}
	return inputPeer, func() {}, nil
}

const RpcTimeout = 60 * time.Second

type RpcGuard struct {
	next    tg.Invoker
	timeout time.Duration
}

func (g RpcGuard) Invoke(ctx context.Context, input bin.Encoder, output bin.Decoder) error {
	if _, ok := ctx.Deadline(); !ok {
		timeout := g.timeout
		if timeout <= 0 {
			timeout = RpcTimeout
		}
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}
	return g.next.Invoke(ctx, input, output)
}

func (t *TelegramCore) guardedClient() *tg.Client {
	return tg.NewClient(RpcGuard{next: t.client})
}

func (t *TelegramCore) WithAPI() (*tg.Client, context.Context, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, nil, ErrAuth
	}
	return t.api, t.ctx, nil
}

func (t *TelegramCore) withSenderAPI() (*tg.Client, context.Context, *message.Sender, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, nil, nil, ErrAuth
	}
	return t.api, t.ctx, t.sender, nil
}

func (t *TelegramCore) resolvePeer(chatID string) (tg.PeerClass, error) {
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

	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid chat ID: %s", chatID)
	}

	if id < 0 {
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
			return nil, fmt.Errorf("resolve channel %d access hash: %w", p.ChannelID, err)
		}
		return &tg.InputPeerChannel{ChannelID: p.ChannelID, AccessHash: hash}, nil
	default:
		return nil, fmt.Errorf("unknown peer type: %T", peer)
	}
}

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

func (t *TelegramCore) PreloadPeerHashes(channelHashes map[int64]int64, userHashes map[int64]int64) {
	t.peerMu.Lock()
	defer t.peerMu.Unlock()
	for id, hash := range channelHashes {
		if _, exists := t.channelAccessHash[id]; !exists {
			t.channelAccessHash[id] = hash
		}
	}
	for id, hash := range userHashes {
		if _, exists := t.userAccessHash[id]; !exists {
			t.userAccessHash[id] = hash
		}
	}
}

func encodeFileExtra(accessHash int64, fileRef []byte) string {
	return strconv.FormatInt(accessHash, 10) + ":" + base64.StdEncoding.EncodeToString(fileRef)
}

func DecodeFileExtra(extra string) (int64, []byte) {
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
	if t.fileAccessHash == nil {
		t.fileAccessHash = make(map[int64]int64)
		t.fileReference = make(map[int64][]byte)
	}
	t.fileAccessHash[fileID] = accessHash
	if len(fileRef) > 0 {
		t.fileReference[fileID] = fileRef
	}
	t.peerMu.Unlock()
}

func (t *TelegramCore) GetCachedFileHash(fileID int64) int64 {
	t.peerMu.RLock()
	defer t.peerMu.RUnlock()
	return t.fileAccessHash[fileID]
}

func (t *TelegramCore) getCachedFileRef(fileID int64) []byte {
	t.peerMu.RLock()
	defer t.peerMu.RUnlock()
	return t.fileReference[fileID]
}

func (t *TelegramCore) getCachedFileMime(fileID int64) string {
	t.peerMu.RLock()
	defer t.peerMu.RUnlock()
	return t.fileMimeType[fileID]
}

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

func (t *TelegramCore) resolveChannelAccessHash(channelID int64) (int64, error) {
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

func RepliesInfoOf(msg *tg.Message) (count int, isComments bool) {
	if r, ok := msg.GetReplies(); ok {
		return r.Replies, r.Comments
	}
	return 0, false
}

func ThreadRootOf(msg *tg.Message) string {
	if reply, ok := msg.GetReplyTo(); ok {
		if rh, ok := reply.(*tg.MessageReplyHeader); ok {
			if rh.ReplyToTopID != 0 {
				return strconv.Itoa(rh.ReplyToTopID)
			}
			if rh.ReplyToMsgID != 0 {
				return strconv.Itoa(rh.ReplyToMsgID)
			}
		}
	}
	return ""
}

func (t *TelegramCore) ConvertMessage(msg *tg.Message) *Message {
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
		NoForwards: msg.Noforwards,
		Platform:   tgPlatform,
	}

	if msg.Noforwards {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["no_forwards"] = true
	}

	if msg.PaidSuggestedPostTon {
		m.PaidPostType = 2
	} else if msg.PaidSuggestedPostStars {
		m.PaidPostType = 1
	}

	if gid, ok := msg.GetGroupedID(); ok && gid != 0 {
		m.GroupedID = strconv.FormatInt(gid, 10)
	}

	if msg.Silent {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["is_silent"] = true
	}
	if msg.MediaUnread {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["media_unread"] = true
	}
	if msg.Mentioned {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["mentioned"] = true
	}
	if ttl, ok := msg.GetTTLPeriod(); ok && ttl > 0 {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["ttl_seconds"] = ttl
	}
	if rp, ok := msg.GetScheduleRepeatPeriod(); ok && rp > 0 {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["schedule_repeat_period"] = rp
	}

	if from := msg.FromID; from != nil {
		m.SenderID = peerToID(from)
		if peer, ok := from.(*tg.PeerUser); ok {
			m.SenderName = t.getCachedUserName(peer.UserID)
			m.SenderColorID = t.getCachedUserColorID(peer.UserID)
			if chatID := peerToInt64(msg.PeerID); chatID != 0 {
				m.SenderRank = t.getAdminRank(chatID, peer.UserID)
			}
		}
	}

	if author, ok := msg.GetPostAuthor(); ok && author != "" && m.SenderRank == "" {
		m.SenderRank = author
	}

	if msg.EditDate != 0 {
		et := time.Unix(int64(msg.EditDate), 0)
		m.EditedAt = &et
	}

	if c, _ := RepliesInfoOf(msg); c > 0 {
		m.CommentsCount = c
	}
	if root := ThreadRootOf(msg); root != "" {
		m.ThreadRoot = root
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
				chatID := peerToID(msg.PeerID)
				if title, color, ok := t.GetForumTopicInfo(chatID, tidStr); ok {
					m.Extra["topic_name"] = title
					m.Extra["topic_color"] = color
				}
			}
		}
	}

	if replies, ok := msg.GetReplies(); ok && replies.Replies > 0 {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		m.Extra["replies_count"] = replies.Replies
		if replies.Comments {
			m.Extra["replies_is_comments"] = true
		}
		if chID, ok := replies.GetChannelID(); ok && chID != 0 {
			m.Extra["replies_channel_id"] = strconv.FormatInt(chID, 10)
		}
	}

	if fwd, ok := msg.GetFwdFrom(); ok {
		if name, ok := fwd.GetFromName(); ok && name != "" {
			m.ForwardFrom = name
		} else if from, ok := fwd.GetFromID(); ok {
			switch p := from.(type) {
			case *tg.PeerUser:
				m.ForwardFromID = strconv.FormatInt(p.UserID, 10)
				if name := t.getCachedUserName(p.UserID); name != "" {
					m.ForwardFrom = name
				} else {
					m.ForwardFrom = "User " + strconv.FormatInt(p.UserID, 10)
				}
			case *tg.PeerChannel:
				m.ForwardFromID = strconv.FormatInt(-1000000000000-p.ChannelID, 10)
				if name := t.getCachedChannelName(p.ChannelID); name != "" {
					m.ForwardFrom = name
				} else if author, ok := fwd.GetPostAuthor(); ok && author != "" {
					m.ForwardFrom = author
				} else {
					m.ForwardFrom = "Channel " + strconv.FormatInt(p.ChannelID, 10)
				}
			case *tg.PeerChat:
				m.ForwardFromID = strconv.FormatInt(-p.ChatID, 10)
				if name := t.getCachedChannelName(p.ChatID); name != "" {
					m.ForwardFrom = name
				} else {
					m.ForwardFrom = "Chat " + strconv.FormatInt(p.ChatID, 10)
				}
			}
		} else if author, ok := fwd.GetPostAuthor(); ok && author != "" {
			m.ForwardFrom = author
		}
		if author, ok := fwd.GetPostAuthor(); ok && author != "" && m.ForwardFrom != author {
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["forward_post_author"] = author
		}
		if psaType, ok := fwd.GetPsaType(); ok && psaType != "" {
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["forward_psa_type"] = psaType
		}
	}

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
					DC:       int(d.DCID),
				}
				isAnimated := false
				isSticker := false
				for _, attr := range d.Attributes {
					switch a := attr.(type) {
					case *tg.DocumentAttributeFilename:
						ref.Name = a.FileName
					case *tg.DocumentAttributeAnimated:
						isAnimated = true
					case *tg.DocumentAttributeSticker:
						isSticker = true
						if sn, ok := a.Stickerset.(*tg.InputStickerSetShortName); ok && sn.ShortName != "" {
							if m.Extra == nil {
								m.Extra = make(map[string]interface{})
							}
							m.Extra["sticker_set_short_name"] = sn.ShortName
						} else if sid, ok := a.Stickerset.(*tg.InputStickerSetID); ok && sid.ID != 0 {
							if m.Extra == nil {
								m.Extra = make(map[string]interface{})
							}
							m.Extra["sticker_set_id"] = sid.ID
							m.Extra["sticker_set_access_hash"] = sid.AccessHash
						}
					case *tg.DocumentAttributeVideo:
						ref.Width = a.W
						ref.Height = a.H
						ref.Duration = int(a.Duration)
					case *tg.DocumentAttributeAudio:
						ref.Duration = int(a.Duration)
						if wf, ok := a.GetWaveform(); ok && len(wf) > 0 {
							if m.Extra == nil {
								m.Extra = make(map[string]interface{})
							}
							m.Extra["waveform"] = base64.StdEncoding.EncodeToString(wf)
						}
						if title, ok := a.GetTitle(); ok && title != "" {
							if m.Extra == nil {
								m.Extra = make(map[string]interface{})
							}
							m.Extra["audio_title"] = title
						}
						if performer, ok := a.GetPerformer(); ok && performer != "" {
							if m.Extra == nil {
								m.Extra = make(map[string]interface{})
							}
							m.Extra["audio_performer"] = performer
						}
					case *tg.DocumentAttributeImageSize:
						ref.Width = a.W
						ref.Height = a.H
					}
				}
				if isAnimated && ref.MimeType == "video/mp4" {
					ref.MimeType = "image/gif"
				}
				if isSticker && ref.MimeType == "video/webm" {
					ref.MimeType = "video/webm+sticker"
				}
				if isSticker {
					for _, vt := range d.VideoThumbs {
						if vs, ok := vt.(*tg.VideoSize); ok && vs.Type == "f" {
							if m.Extra == nil {
								m.Extra = make(map[string]interface{})
							}
							m.Extra["sticker_premium"] = true
							break
						}
					}
				}
				ref.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
				m.Attachments = []FileRef{ref}
				t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
			}
			if altDocs, ok := md.GetAltDocuments(); ok && len(altDocs) > 0 {
				var qualities []map[string]interface{}
				altSeq := len(m.Attachments)
				for _, altDoc := range altDocs {
					ad, ok := altDoc.(*tg.Document)
					if !ok {
						continue
					}
					var vw, vh int
					for _, attr := range ad.Attributes {
						if v, ok := attr.(*tg.DocumentAttributeVideo); ok {
							vw = v.W
							vh = v.H
							break
						}
					}
					if vh == 0 {
						continue
					}
					altRef := FileRef{
						ID:       strconv.FormatInt(ad.ID, 10),
						Size:     ad.Size,
						MimeType: ad.MimeType,
						Extra:    encodeFileExtra(ad.AccessHash, ad.FileReference),
						Width:    vw,
						Height:   vh,
					}
					m.Attachments = append(m.Attachments, altRef)
					qualities = append(qualities, map[string]interface{}{
						"height": vh,
						"width":  vw,
						"size":   ad.Size,
						"seq":    altSeq,
					})
					t.cacheFileInfo(ad.ID, ad.AccessHash, ad.FileReference)
					altSeq++
				}
				if len(qualities) > 0 {
					if m.Extra == nil {
						m.Extra = make(map[string]interface{})
					}
					m.Extra["alt_qualities"] = qualities
				}
			}
			if md.Spoiler {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["media_spoiler"] = true
			}
			if ttl, ok := md.GetTTLSeconds(); ok && ttl > 0 {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["media_ttl_seconds"] = ttl
			}
		case *tg.MessageMediaPhoto:
			if p, ok := md.Photo.(*tg.Photo); ok {
				ref := FileRef{
					ID:       strconv.FormatInt(p.ID, 10),
					MimeType: "image/jpeg",
					Name:     "photo.jpg",
					Extra:    encodeFileExtra(p.AccessHash, p.FileReference),
					DC:       int(p.DCID),
				}
				for _, size := range p.Sizes {
					if s, ok := size.(*tg.PhotoSize); ok {
						ref.Size = int64(s.Size)
						ref.Width = s.W
						ref.Height = s.H
					}
				}
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
		case *tg.MessageMediaPoll:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			poll := md.Poll
			if m.Text == "" {
				m.Text = "📊 " + poll.Question.Text
			}
			m.Extra["poll_question"] = poll.Question.Text
			m.Extra["poll_quiz"] = poll.Quiz
			m.Extra["poll_multiple"] = poll.MultipleChoice
			m.Extra["poll_closed"] = poll.Closed
			m.Extra["poll_public"] = poll.PublicVoters
			if cp, ok := poll.GetClosePeriod(); ok {
				m.Extra["poll_close_period"] = cp
			}
			if cd, ok := poll.GetCloseDate(); ok {
				m.Extra["poll_close_date"] = cd
			}

			opts := make([]map[string]interface{}, 0, len(poll.Answers))
			for _, ac := range poll.Answers {
				a, ok := ac.(*tg.PollAnswer)
				if !ok {
					continue
				}
				opt := map[string]interface{}{
					"text":   a.Text.Text,
					"option": base64.StdEncoding.EncodeToString(a.Option),
				}
				opts = append(opts, opt)
			}

			res := md.Results
			if voters, ok := res.GetResults(); ok {
				for _, v := range voters {
					optB64 := base64.StdEncoding.EncodeToString(v.Option)
					for i := range opts {
						if opts[i]["option"] == optB64 {
							opts[i]["voters"] = v.Voters
							opts[i]["chosen"] = v.Chosen
							opts[i]["correct"] = v.Correct
							break
						}
					}
				}
			}
			m.Extra["poll_options"] = opts
			if tv, ok := res.GetTotalVoters(); ok {
				m.Extra["poll_total_voters"] = tv
			}
			if sol, ok := res.GetSolution(); ok && sol != "" {
				m.Extra["poll_solution"] = sol
			}
			if rv, ok := res.GetRecentVoters(); ok && len(rv) > 0 {
				voterIDs := make([]string, 0, len(rv))
				voterNames := make([]string, 0, len(rv))
				t.peerMu.RLock()
				for _, p := range rv {
					switch v := p.(type) {
					case *tg.PeerUser:
						voterIDs = append(voterIDs, fmt.Sprintf("%d", v.UserID))
						voterNames = append(voterNames, t.userNames[v.UserID])
					}
				}
				t.peerMu.RUnlock()
				if len(voterIDs) > 0 {
					m.Extra["poll_recent_voters"] = voterIDs
					m.Extra["poll_recent_voter_names"] = voterNames
				}
			}

			m.Attachments = []FileRef{{MimeType: "application/x-poll", Name: "poll"}}
		case *tg.MessageMediaDice:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["dice_emoji"] = md.Emoticon
			m.Extra["dice_value"] = md.Value
			m.Attachments = []FileRef{{MimeType: "application/x-dice", Name: md.Emoticon}}
		case *tg.MessageMediaGeo:
			if gp, ok := md.Geo.(*tg.GeoPoint); ok {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["geo_lat"] = gp.Lat
				m.Extra["geo_long"] = gp.Long
				m.Extra["geo_access_hash"] = gp.AccessHash
				if m.Text == "" {
					m.Text = "📍 Location"
				}
				m.Attachments = []FileRef{{MimeType: "application/x-location", Name: "location"}}
			}
		case *tg.MessageMediaGeoLive:
			if gp, ok := md.Geo.(*tg.GeoPoint); ok {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["geo_lat"] = gp.Lat
				m.Extra["geo_long"] = gp.Long
				m.Extra["geo_access_hash"] = gp.AccessHash
				m.Extra["geo_live"] = true
				m.Extra["geo_period"] = md.Period
				if heading, ok := md.GetHeading(); ok {
					m.Extra["geo_heading"] = heading
				}
				if m.Text == "" {
					m.Text = "📍 Live Location"
				}
				m.Attachments = []FileRef{{MimeType: "application/x-location", Name: "location"}}
			}
		case *tg.MessageMediaVenue:
			if gp, ok := md.Geo.(*tg.GeoPoint); ok {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["geo_lat"] = gp.Lat
				m.Extra["geo_long"] = gp.Long
				m.Extra["geo_access_hash"] = gp.AccessHash
				m.Extra["venue_title"] = md.Title
				m.Extra["venue_address"] = md.Address
				if m.Text == "" {
					m.Text = "📍 " + md.Title
				}
				m.Attachments = []FileRef{{MimeType: "application/x-location", Name: "location"}}
			}
		case *tg.MessageMediaContact:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["contact_phone"] = md.PhoneNumber
			m.Extra["contact_first_name"] = md.FirstName
			m.Extra["contact_last_name"] = md.LastName
			m.Extra["contact_user_id"] = md.UserID
			if m.Text == "" {
				name := md.FirstName
				if md.LastName != "" {
					name += " " + md.LastName
				}
				m.Text = "👤 " + name
			}
			m.Attachments = []FileRef{{MimeType: "application/x-contact", Name: "contact"}}
		case *tg.MessageMediaInvoice:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["invoice_title"] = md.Title
			m.Extra["invoice_description"] = md.Description
			m.Extra["invoice_currency"] = md.Currency
			m.Extra["invoice_total_amount"] = md.TotalAmount
			m.Extra["invoice_test"] = md.Test
			if receiptMsgID, ok := md.GetReceiptMsgID(); ok {
				m.Extra["invoice_receipt_msg_id"] = receiptMsgID
			}
			if p, ok := md.GetPhoto(); ok {
				if photo, ok := p.(*tg.WebDocument); ok {
					m.Extra["invoice_photo_url"] = photo.URL
				}
				if photo, ok := p.(*tg.WebDocumentNoProxy); ok {
					m.Extra["invoice_photo_url"] = photo.URL
				}
			}
			if md.ShippingAddressRequested {
				m.Extra["invoice_shipping_requested"] = true
			}
			if m.Text == "" {
				m.Text = "💳 " + md.Title
			}
			m.Attachments = []FileRef{{MimeType: "application/x-invoice", Name: "invoice"}}
		case *tg.MessageMediaPaidMedia:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["invoice_is_paid_media"] = true
			m.Extra["invoice_first_video"] = paidMediaFirstVideo(md.ExtendedMedia)
			m.Extra["paid_stars"] = md.StarsAmount
			if em, ok := md.ExtendedMedia[0].(*tg.MessageExtendedMedia); ok && em.Media != nil {
				if _, nested := em.Media.(*tg.MessageMediaPaidMedia); !nested {
					inner := *msg
					inner.Media = em.Media
					if innerMsg := t.ConvertMessage(&inner); innerMsg != nil {
						m.Attachments = innerMsg.Attachments
						for k, v := range innerMsg.Extra {
							m.Extra[k] = v
						}
						if m.Text == "" {
							m.Text = innerMsg.Text
						}
					}
					m.Extra["paid_unlocked"] = true
					break
				}
			}
			if pv, ok := md.ExtendedMedia[0].(*tg.MessageExtendedMediaPreview); ok {
				if pv.W > 0 {
					m.Extra["paid_w"] = pv.W
				}
				if pv.H > 0 {
					m.Extra["paid_h"] = pv.H
				}
				if pv.VideoDuration > 0 {
					m.Extra["paid_video_duration"] = pv.VideoDuration
				}
				if st, ok := pv.GetThumb(); ok {
					if b64 := extractStrippedThumbB64([]tg.PhotoSizeClass{st}); b64 != "" {
						m.Extra["paid_thumb_b64"] = b64
					}
				}
			}
			m.Attachments = []FileRef{{MimeType: "application/x-invoice", Name: "paid_media"}}
		case *tg.MessageMediaGame:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			g := md.Game
			m.Extra["game_id"] = g.ID
			m.Extra["game_access_hash"] = g.AccessHash
			m.Extra["game_short_name"] = g.ShortName
			m.Extra["game_title"] = g.Title
			m.Extra["game_description"] = g.Description
			if p, ok := g.Photo.(*tg.Photo); ok {
				thumbB64 := extractStrippedThumbB64(p.Sizes)
				if thumbB64 != "" {
					m.Extra["game_thumb_b64"] = thumbB64
				}
				for _, size := range p.Sizes {
					if s, ok := size.(*tg.PhotoSize); ok {
						m.Extra["game_photo_w"] = s.W
						m.Extra["game_photo_h"] = s.H
						break
					}
				}
			}
			if m.Text == "" {
				m.Text = "��� " + g.Title
			}
		case *tg.MessageMediaWebPage:
			if wp, ok := md.Webpage.(*tg.WebPage); ok {
				if m.Extra == nil {
					m.Extra = make(map[string]interface{})
				}
				m.Extra["wp_url"] = wp.URL
				if sn, ok := wp.GetSiteName(); ok {
					m.Extra["wp_site_name"] = sn
				}
				if t, ok := wp.GetTitle(); ok {
					m.Extra["wp_title"] = t
				}
				if d, ok := wp.GetDescription(); ok {
					m.Extra["wp_description"] = d
				}
				wpType := ""
				if t, ok := wp.GetType(); ok {
					wpType = t
				}
				_, hasIV := wp.GetCachedPage()
				if !hasIV {
					hasIV = isKnownIVDomain(wp.URL)
				}
				if hasIV && !ivIgnoreType(wpType) {
					wpType = "article_with_iv"
				}
				if wpType != "" {
					m.Extra["wp_type"] = wpType
				}
				if md.ForceLargeMedia {
					m.Extra["wp_force_large_media"] = true
				}
				if md.ForceSmallMedia {
					m.Extra["wp_force_small_media"] = true
				}
				if wp.HasLargeMedia {
					m.Extra["wp_has_large_media"] = true
				}
				if p, ok := wp.GetPhoto(); ok {
					if photo, ok := p.(*tg.Photo); ok {
						thumbB64 := extractStrippedThumbB64(photo.Sizes)
						if thumbB64 != "" {
							m.Extra["wp_thumb_b64"] = thumbB64
						}
						for _, size := range photo.Sizes {
							if s, ok := size.(*tg.PhotoSize); ok {
								m.Extra["wp_photo_w"] = s.W
								m.Extra["wp_photo_h"] = s.H
								break
							}
						}
						if photo.ID != 0 {
							m.Extra["wp_photo_id"] = strconv.FormatInt(photo.ID, 10)
							m.Extra["wp_photo_extra"] = encodeFileExtra(photo.AccessHash, photo.FileReference)
							t.cacheFileInfo(photo.ID, photo.AccessHash, photo.FileReference)
						}
					}
				}
				if du, ok := wp.GetDuration(); ok && du > 0 {
					m.Extra["wp_duration"] = du
				}
				if _, ok := wp.GetCachedPage(); ok {
					m.Extra["wp_has_iv"] = true
				}
			}
		case *tg.MessageMediaUnsupported:
			if m.Extra == nil {
				m.Extra = make(map[string]interface{})
			}
			m.Extra["unsupported_ttl"] = true
		}
	}

	if reactions, ok := msg.GetReactions(); ok {
		results := reactions.Results
		if len(results) > 0 {
			m.Reactions = make([]Reaction, 0, len(results))
			for _, r := range results {
				switch re := r.Reaction.(type) {
				case *tg.ReactionEmoji:
					if re.Emoticon != "" {
						m.Reactions = append(m.Reactions, Reaction{
							Emoji: re.Emoticon,
							Count: r.Count,
							ByMe:  r.ChosenOrder > 0,
						})
					}
				case *tg.ReactionCustomEmoji:
					m.Reactions = append(m.Reactions, Reaction{
						DocumentID: re.DocumentID,
						Count:      r.Count,
						ByMe:       r.ChosenOrder > 0,
					})
				}
			}
		}
	}

	if markup, ok := msg.GetReplyMarkup(); ok {
		if m.Extra == nil {
			m.Extra = make(map[string]interface{})
		}
		switch rm := markup.(type) {
		case *tg.ReplyKeyboardMarkup:
			type styler interface {
				GetStyle() (tg.KeyboardButtonStyle, bool)
			}
			rows := make([][]map[string]interface{}, 0, len(rm.Rows))
			for _, row := range rm.Rows {
				btns := make([]map[string]interface{}, 0, len(row.Buttons))
				for _, btn := range row.Buttons {
					b := map[string]interface{}{"text": btn.GetText()}
					switch bt := btn.(type) {
					case *tg.KeyboardButtonRequestPhone:
						b["type"] = "request_phone"
					case *tg.KeyboardButtonRequestGeoLocation:
						b["type"] = "request_location"
					case *tg.KeyboardButtonRequestPoll:
						b["type"] = "request_poll"
					case *tg.KeyboardButtonRequestPeer:
						b["type"] = "request_peer"
					case *tg.KeyboardButtonWebView:
						b["type"] = "web_view"
						b["url"] = bt.URL
					case *tg.KeyboardButtonSimpleWebView:
						b["type"] = "simple_web_view"
						b["url"] = bt.URL
					default:
						b["type"] = "text"
					}
					if s, ok := btn.(styler); ok {
						if style, ok := s.GetStyle(); ok {
							if style.BgPrimary {
								b["color"] = "primary"
							} else if style.BgDanger {
								b["color"] = "danger"
							} else if style.BgSuccess {
								b["color"] = "success"
							}
						}
					}
					btns = append(btns, b)
				}
				rows = append(rows, btns)
			}
			m.Extra["reply_keyboard"] = map[string]interface{}{
				"rows":        rows,
				"resize":      rm.Resize,
				"single_use":  rm.SingleUse,
				"persistent":  rm.Persistent,
				"placeholder": rm.Placeholder,
			}
		case *tg.ReplyInlineMarkup:
			rows := make([][]map[string]interface{}, 0, len(rm.Rows))
			for _, row := range rm.Rows {
				btns := make([]map[string]interface{}, 0, len(row.Buttons))
				for _, btn := range row.Buttons {
					b := map[string]interface{}{"text": btn.GetText()}
					switch bt := btn.(type) {
					case *tg.KeyboardButtonURL:
						b["type"] = "url"
						b["url"] = bt.URL
					case *tg.KeyboardButtonCallback:
						b["type"] = "callback"
						b["data"] = string(bt.Data)
					case *tg.KeyboardButtonSwitchInline:
						b["type"] = "switch_inline"
						b["query"] = bt.Query
						if bt.SamePeer {
							b["same_peer"] = true
						}
					case *tg.KeyboardButtonGame:
						b["type"] = "game"
					case *tg.KeyboardButtonBuy:
						b["type"] = "buy"
					case *tg.KeyboardButtonURLAuth:
						b["type"] = "url_auth"
						b["url"] = bt.URL
						b["button_id"] = bt.ButtonID
						if fwd, ok := bt.GetFwdText(); ok {
							b["fwd_text"] = fwd
						}
					case *tg.KeyboardButtonWebView:
						b["type"] = "web_view"
						b["url"] = bt.URL
					case *tg.KeyboardButtonSimpleWebView:
						b["type"] = "simple_web_view"
						b["url"] = bt.URL
					case *tg.KeyboardButtonCopy:
						b["type"] = "copy"
						b["copy_text"] = bt.CopyText
					default:
						b["type"] = "callback"
					}
					btns = append(btns, b)
				}
				rows = append(rows, btns)
			}
			m.Extra["inline_keyboard"] = rows
		case *tg.ReplyKeyboardHide:
			m.Extra["keyboard_hide"] = true
		case *tg.ReplyKeyboardForceReply:
			m.Extra["force_reply"] = true
			if ph, ok := rm.GetPlaceholder(); ok {
				m.Extra["force_reply_placeholder"] = ph
			}
		}
	}

	return m
}

func (t *TelegramCore) ConvertServiceMessage(svc *tg.MessageService) *Message {
	m := &Message{
		ID:         strconv.Itoa(svc.ID),
		ChatID:     peerToID(svc.PeerID),
		Timestamp:  time.Unix(int64(svc.Date), 0),
		Status:     MessageStatusSent,
		IsOutgoing: svc.Out,
		IsService:  true,
		Platform:   tgPlatform,
		Extra:      make(map[string]interface{}),
	}

	if from := svc.FromID; from != nil {
		m.SenderID = peerToID(from)
		if peer, ok := from.(*tg.PeerUser); ok {
			m.SenderName = t.getCachedUserName(peer.UserID)
		}
	}

	m.Text = t.ServiceActionText(m.SenderName, svc.Action)
	m.Extra["service_action"] = serviceActionTag(svc.Action)
	if gc, ok := svc.Action.(*tg.MessageActionGiftCode); ok {
		if bp, ok := gc.GetBoostPeer(); ok {
			if _, isChannel := bp.(*tg.PeerChannel); isChannel {
				m.Extra["channel"] = true
			}
		}
	}
	switch act := svc.Action.(type) {
	case *tg.MessageActionStarGift:
		m.Extra["gift_kind"] = "stargift"
		m.Extra["gift_saved"] = act.Saved
		m.Extra["gift_converted"] = act.Converted
		m.Extra["gift_refunded"] = act.Refunded
		if act.Message.Text != "" {
			m.Extra["gift_text"] = act.Message.Text
		}
		if gift, ok := act.Gift.(*tg.StarGift); ok {
			m.Extra["gift_stars"] = gift.Stars
			m.Extra["gift_limited"] = gift.Limited
			if doc, ok := gift.Sticker.(*tg.Document); ok {
				m.Extra["gift_thumb_b64"] = extractStrippedThumbB64(doc.Thumbs)
				t.cacheFileInfo(doc.ID, doc.AccessHash, doc.FileReference)
			}
		}
	case *tg.MessageActionGiftStars:
		m.Extra["gift_kind"] = "stars"
		m.Extra["gift_stars"] = act.Stars
	case *tg.MessageActionGiftTon:
		m.Extra["gift_kind"] = "ton"
		m.Extra["gift_crypto_amount"] = act.CryptoAmount
		m.Extra["gift_crypto_currency"] = act.CryptoCurrency
	case *tg.MessageActionSetChatTheme:
		emoticon := ""
		if th, ok := act.Theme.(*tg.ChatTheme); ok {
			emoticon = th.Emoticon
		}
		m.Extra["chat_theme_emoticon"] = emoticon
	case *tg.MessageActionSetChatWallPaper:
		if info := t.WallpaperFromWire(act.Wallpaper); info.ID != 0 || info.DocID != 0 {
			if raw, jerr := json.Marshal(info); jerr == nil {
				m.Extra["chat_wallpaper"] = string(raw)
				if act.Same {
					m.Extra["chat_wallpaper_same"] = true
				}
				if act.ForBoth {
					m.Extra["chat_wallpaper_for_both"] = true
				}
			}
		}
	}
	return m
}

func serviceActionTag(action tg.MessageActionClass) string {
	switch action.(type) {
	case *tg.MessageActionPhoneCall:
		return "phone_call"
	case *tg.MessageActionChatEditPhoto:
		return "set_photo"
	case *tg.MessageActionChatDeletePhoto:
		return "set_photo"
	case *tg.MessageActionSuggestBirthday:
		return "suggest_photo"
	case *tg.MessageActionSetChatWallPaper:
		return "wallpaper"
	case *tg.MessageActionGiftCode:
		return "gift_premium"
	case *tg.MessageActionGiftStars, *tg.MessageActionPrizeStars, *tg.MessageActionStarGift, *tg.MessageActionStarGiftUnique, *tg.MessageActionGiftTon:
		return "gift_stars"
	case *tg.MessageActionGiveawayResults:
		return "giveaway_results"
	case *tg.MessageActionBoostApply:
		return "boost"
	case *tg.MessageActionGroupCall, *tg.MessageActionInviteToGroupCall, *tg.MessageActionGroupCallScheduled:
		return "group_call"
	case *tg.MessageActionChatCreate, *tg.MessageActionChannelCreate:
		return "chat_create"
	case *tg.MessageActionTopicCreate:
		return "topic_create"
	case *tg.MessageActionGeoProximityReached:
		return "geo_proximity_reached"
	default:
		return ""
	}
}

func (t *TelegramCore) ServiceActionText(sender string, action tg.MessageActionClass) string {
	if sender == "" {
		sender = "Someone"
	}
	switch a := action.(type) {
	case *tg.MessageActionGeoProximityReached:
		fromName := t.proximityPeerName(a.FromID)
		toName := t.proximityPeerName(a.ToID)
		fromSelf, toSelf := false, false
		if p, ok := a.FromID.(*tg.PeerUser); ok {
			fromSelf = p.UserID == t.selfID
		}
		if p, ok := a.ToID.(*tg.PeerUser); ok {
			toSelf = p.UserID == t.selfID
		}
		return ProximityReachedText(fromName, toName, fromSelf, toSelf, a.Distance)
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
	case *tg.MessageActionStarGift:
		return sender + " sent a gift"
	case *tg.MessageActionGiftStars:
		return sender + " sent you " + strconv.FormatInt(a.Stars, 10) + " Stars"
	case *tg.MessageActionGiftTon:
		return sender + " sent you a TON gift"
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
			te = TextEntity{Type: "custom_emoji", Offset: v.Offset, Length: v.Length, DocumentID: v.DocumentID}
		case *tg.MessageEntityFormattedDate:
			te = TextEntity{
				Type: "formatted_date", Offset: v.Offset, Length: v.Length, Date: v.Date,
				DateRelative:  v.Relative,
				DateShortTime: v.ShortTime,
				DateLongTime:  v.LongTime,
				DateShortDate: v.ShortDate,
				DateLongDate:  v.LongDate,
				DateDayOfWeek: v.DayOfWeek,
			}
		default:
			continue
		}
		result = append(result, te)
	}
	return result
}

func extractEmojiStatusID(es tg.EmojiStatusClass) string {
	if es == nil {
		return ""
	}
	switch s := es.(type) {
	case *tg.EmojiStatus:
		return strconv.FormatInt(s.DocumentID, 10)
	case *tg.EmojiStatusCollectible:
		return fmt.Sprintf("collectible:%d:%06X:%06X", s.DocumentID, s.CenterColor, s.EdgeColor)
	default:
		return ""
	}
}

func (t *TelegramCore) convertUser(user *tg.User) *User {
	u := &User{
		ID:              strconv.FormatInt(user.ID, 10),
		Username:        user.Username,
		DisplayName:     strings.TrimSpace(user.FirstName + " " + user.LastName),
		Phone:           user.Phone,
		IsBot:           user.Bot,
		IsContact:       user.Contact,
		IsMutualContact: user.MutualContact,
		IsVerified:      user.Verified,
		IsPremium:       user.Premium,
		IsScam:          user.Scam,
		IsFake:          user.Fake,
		EmojiStatusID:   extractEmojiStatusID(user.EmojiStatus),
		Platform:        tgPlatform,
	}

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
		u.LastSeenKind = kind
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

	if photo, ok := user.Photo.(*tg.UserProfilePhoto); ok {
		if thumb, ok := photo.GetStrippedThumb(); ok && len(thumb) > 0 {
			if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
				u.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
			}
		}
	}

	if !user.StoriesUnavailable {
		if maxStory, ok := user.GetStoriesMaxID(); ok {
			if maxID, ok := maxStory.GetMaxID(); ok && maxID > 0 {
				u.StoryCount = 1
				u.HasUnreadStory = true
			}
		}
	}

	if stars, ok := user.GetSendPaidMessagesStars(); ok {
		u.StarsPerMessage = stars
	}

	return u
}

func userAvatarStrippedB64(u *tg.User) string {
	if u == nil {
		return ""
	}
	if photo, ok := u.Photo.(*tg.UserProfilePhoto); ok {
		if thumb, ok := photo.GetStrippedThumb(); ok && len(thumb) > 0 {
			if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
				return base64.StdEncoding.EncodeToString(jpg)
			}
		}
	}
	return ""
}

func StoryReactionEmoticon(r tg.ReactionClass) string {
	if e, ok := r.(*tg.ReactionEmoji); ok {
		return e.Emoticon
	}
	return ""
}

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

func tgStrippedToJPEG(data []byte) []byte {
	if len(data) < 3 || data[0] != 1 {
		return nil
	}
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

	header[204] = data[1]
	header[206] = data[2]

	result := make([]byte, 0, len(header)+len(data)-3+len(footer))
	result = append(result, header...)
	result = append(result, data[3:]...)
	result = append(result, footer...)
	return result
}

func paidMediaFirstVideo(media []tg.MessageExtendedMediaClass) bool {
	if len(media) == 0 {
		return false
	}
	switch em := media[0].(type) {
	case *tg.MessageExtendedMediaPreview:
		_, ok := em.GetVideoDuration()
		return ok
	case *tg.MessageExtendedMedia:
		_, isPhoto := em.Media.(*tg.MessageMediaPhoto)
		return !isPhoto
	}
	return false
}

func extractMessageMediaSummary(msg *tg.Message) (mediaType int, thumbB64 string) {
	if msg.Media == nil {
		return 0, ""
	}
	switch md := msg.Media.(type) {
	case *tg.MessageMediaPhoto:
		if p, ok := md.Photo.(*tg.Photo); ok {
			return 1, extractStrippedThumbB64(p.Sizes)
		}
		return 1, ""
	case *tg.MessageMediaDocument:
		if d, ok := md.Document.(*tg.Document); ok {
			isVideo, isAnimated, isSticker, isVoice, isVideoNote, isAudio := false, false, false, false, false, false
			for _, attr := range d.Attributes {
				switch a := attr.(type) {
				case *tg.DocumentAttributeVideo:
					if a.RoundMessage {
						isVideoNote = true
					} else {
						isVideo = true
					}
				case *tg.DocumentAttributeAnimated:
					isAnimated = true
				case *tg.DocumentAttributeSticker:
					isSticker = true
				case *tg.DocumentAttributeAudio:
					if a.Voice {
						isVoice = true
					} else {
						isAudio = true
					}
				}
			}
			tb := extractStrippedThumbB64(d.Thumbs)
			switch {
			case isVideoNote:
				return 5, tb
			case isSticker:
				return 6, tb
			case isAnimated:
				return 7, tb
			case isVideo:
				return 2, tb
			case isVoice:
				return 4, tb
			case isAudio:
				return 10, tb
			default:
				return 9, tb
			}
		}
		return 9, ""
	}
	return 0, ""
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
			TtlPeriod:           dlg.TTLPeriod,
			Platform:            tgPlatform,
		}

		switch p := dlg.Peer.(type) {
		case *tg.PeerUser:
			dialog.ID = strconv.FormatInt(p.UserID, 10)
			dialog.Type = ChatTypeDM
			if p.UserID == t.selfID {
				dialog.Title = "Saved Messages"
			} else if user, ok := userMap[p.UserID]; ok {
				dialog.Title = strings.TrimSpace(user.FirstName + " " + user.LastName)
				dialog.AccessHash = user.AccessHash
				dialog.IsVerified = user.Verified
				dialog.IsScam = user.Scam
				dialog.IsFake = user.Fake
				dialog.EmojiStatusID = extractEmojiStatusID(user.EmojiStatus)
				if _, ok := user.Photo.(*tg.UserProfilePhoto); ok {
					dialog.AvatarURL = "has_photo"
				}
				if maxStory, ok := user.GetStoriesMaxID(); ok && !user.StoriesUnavailable {
					if maxID, ok := maxStory.GetMaxID(); ok && maxID > 0 {
						dialog.StoryCount = 1
						dialog.HasUnreadStory = true
					}
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
					dialog.NoForwards = c.Noforwards
					dialog.HasActiveCall = c.CallNotEmpty
					dialog.IsCreator = c.Creator
					if c.Creator {
						dialog.IsAdmin = true
					}
					if c.Deactivated {
						dialog.WriteRestrictionType = 1
						dialog.WriteRestrictionText = "Sorry, this group is not accessible."
					} else if !c.Creator {
						rType, rText := computeWriteRestriction(nil, c.DefaultBannedRights)
						if rType > 0 {
							dialog.WriteRestrictionType = rType
							dialog.WriteRestrictionText = rText
						}
					}
				} else if cf, ok := chat.(*tg.ChatForbidden); ok {
					dialog.Title = cf.Title
					dialog.WriteRestrictionType = 1
					dialog.WriteRestrictionText = "Sorry, this group is not accessible."
				}
			}
		case *tg.PeerChannel:
			dialog.ID = strconv.FormatInt(-1000000000000-p.ChannelID, 10)
			if ch, ok := chatMap[p.ChannelID]; ok {
				if c, ok := ch.(*tg.Channel); ok {
					dialog.Title = c.Title
					dialog.AccessHash = c.AccessHash
					dialog.MemberCount = c.ParticipantsCount
					dialog.IsVerified = c.Verified
					dialog.IsScam = c.Scam
					dialog.IsFake = c.Fake
					dialog.EmojiStatusID = extractEmojiStatusID(c.EmojiStatus)
					dialog.NotJoined = c.Left
					dialog.JoinRequest = c.JoinRequest
					adminRights, hasAdmin := c.GetAdminRights()
					if !c.Creator && !hasAdmin {
						var personalRights *tg.ChatBannedRights
						if br, ok := c.GetBannedRights(); ok && !br.Zero() {
							personalRights = &br
						}
						rType, rText := computeWriteRestriction(personalRights, c.DefaultBannedRights)
						if rType > 0 {
							dialog.WriteRestrictionType = rType
							dialog.WriteRestrictionText = rText
						}
					}
					if c.Creator || hasAdmin {
						dialog.IsAdmin = true
					}
					dialog.IsCreator = c.Creator
					if c.Broadcast {
						dialog.Type = ChatTypeChannel
						if c.Creator || (hasAdmin && adminRights.PostMessages) {
							dialog.CanPost = true
						}
					} else {
						dialog.Type = ChatTypeGroup
						dialog.CanPost = true
					}
					dialog.IsForum = c.Forum
					dialog.NoForwards = c.Noforwards
					dialog.HasActiveCall = c.CallNotEmpty
					dialog.Username = c.Username
					if _, ok := c.Photo.(*tg.ChatPhoto); ok {
						dialog.AvatarURL = "has_photo"
					}
				} else if cf, ok := ch.(*tg.ChannelForbidden); ok {
					dialog.Title = cf.Title
					if cf.Broadcast {
						dialog.Type = ChatTypeChannel
					} else {
						dialog.Type = ChatTypeGroup
					}
					dialog.WriteRestrictionType = 1
					dialog.WriteRestrictionText = "Sorry, this group is not accessible."
				}
			}
		}

		if dlg.TopMessage != 0 {
			if msg, ok := msgMap[dlg.TopMessage]; ok {
				if m, ok := msg.(*tg.Message); ok {
					dialog.LastMessage = t.ConvertMessage(m)
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
					return t.ConvertMessage(msg)
				}
			case *tg.UpdateNewChannelMessage:
				if msg, ok := upd.Message.(*tg.Message); ok {
					return t.ConvertMessage(msg)
				}
			}
		}
	case *tg.UpdateShortSentMessage:
		m := &Message{
			ID:         strconv.Itoa(u.ID),
			ChatID:     chatID,
			SenderID:   strconv.FormatInt(t.selfID, 10),
			SenderName: t.selfName,
			Timestamp:  time.Unix(int64(u.Date), 0),
			Status:     MessageStatusSent,
			IsOutgoing: true,
			Platform:   tgPlatform,
		}
		if ents, ok := u.GetEntities(); ok && len(ents) > 0 {
			m.Entities = convertTgEntities(ents)
		}
		return m
	}
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
			messages = append(messages, *t.ConvertMessage(msg))
		case *tg.MessageService:
			if _, ok := msg.Action.(*tg.MessageActionEmpty); ok {
				continue
			}
			if _, ok := msg.Action.(*tg.MessageActionHistoryClear); ok {
				continue
			}
			messages = append(messages, *t.ConvertServiceMessage(msg))
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

func inputGroupCallID(call tg.InputGroupCallClass) int64 {
	if igc, ok := call.(*tg.InputGroupCall); ok {
		return igc.ID
	}
	return 0
}

func (t *TelegramCore) resolveCallMemberName(e tg.Entities, gcID int64, userID string) string {
	if userID == "" {
		return ""
	}
	id, err := strconv.ParseInt(userID, 10, 64)
	if err != nil {
		return ""
	}
	if u, ok := e.Users[id]; ok {
		name := strings.TrimSpace(u.FirstName + " " + u.LastName)
		if name != "" {
			return name
		}
		if u.Username != "" {
			return u.Username
		}
	}
	if id == t.selfID && t.selfName != "" {
		return t.selfName
	}
	return ""
}

func (t *TelegramCore) resolveShortName(peer tg.PeerClass, e tg.Entities) string {
	switch p := peer.(type) {
	case *tg.PeerUser:
		if u, ok := e.Users[p.UserID]; ok {
			if fn := strings.TrimSpace(u.FirstName); fn != "" {
				return fn
			}
			if full := strings.TrimSpace(u.FirstName + " " + u.LastName); full != "" {
				return full
			}
			if u.Username != "" {
				return u.Username
			}
		}
		if p.UserID == t.selfID && t.selfName != "" {
			return t.selfName
		}
		return t.getCachedUserName(p.UserID)
	case *tg.PeerChannel:
		if c, ok := e.Channels[p.ChannelID]; ok && c.Title != "" {
			return c.Title
		}
		return t.getCachedChannelName(p.ChannelID)
	case *tg.PeerChat:
		if c, ok := e.Chats[p.ChatID]; ok && c.Title != "" {
			return c.Title
		}
		return ""
	}
	return ""
}

func (t *TelegramCore) attachSublistInfo(m *Message, msg *tg.Message, e tg.Entities) {
	saved, hasWire := msg.GetSavedPeerID()
	var id string
	if hasWire && saved != nil {
		id = peerToID(saved)
	} else if t.selfID != 0 {
		id = DeriveSavedPeerID(msg, t.selfID)
	}
	if id == "" {
		return
	}
	m.SavedPeerID = id
	if m.Extra == nil {
		m.Extra = make(map[string]interface{})
	}
	m.Extra["sublist_peer_id"] = id
	if name := t.resolveShortName(saved, e); name != "" {
		m.Extra["sublist_peer_name"] = name
	}
}

func DeriveSavedPeerID(msg *tg.Message, selfID int64) string {
	if peer, ok := msg.GetSavedPeerID(); ok && peer != nil {
		return peerToID(peer)
	}
	if u, is := msg.GetPeerID().(*tg.PeerUser); !is || u.UserID != selfID {
		return ""
	}
	if fwd, ok := msg.GetFwdFrom(); ok {
		if sp, ok := fwd.GetSavedFromPeer(); ok && sp != nil {
			if id := peerToID(sp); id != "" {
				return id
			}
		}
		if _, ok := fwd.GetFromID(); ok {
			return strconv.FormatInt(selfID, 10)
		}
		if _, ok := fwd.GetFromName(); ok {
			return "2666000"
		}
	}
	return strconv.FormatInt(selfID, 10)
}

func (t *TelegramCore) GetSavedHistory(peerID string, offsetID, limit int) ([]Message, error) {
	peer, unlock, err := t.withPeer(peerID)
	if err != nil {
		return nil, fmt.Errorf("resolve saved sublist peer: %w", err)
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 50
	}
	result, err := api.MessagesGetSavedHistory(ctx, &tg.MessagesGetSavedHistoryRequest{
		Peer:     peer,
		OffsetID: offsetID,
		Limit:    limit,
	})
	if err != nil {
		return nil, fmt.Errorf("get saved history: %w", err)
	}
	return t.convertMessages(result), nil
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

func (t *TelegramCore) getAdminRank(chatID, userID int64) string {
	t.adminRanksMu.RLock()
	defer t.adminRanksMu.RUnlock()
	if ranks, ok := t.adminRanks[chatID]; ok {
		return ranks[userID]
	}
	return ""
}

func (t *TelegramCore) setAdminRank(chatID, userID int64, rank string) {
	t.adminRanksMu.Lock()
	defer t.adminRanksMu.Unlock()
	if t.adminRanks[chatID] == nil {
		t.adminRanks[chatID] = make(map[int64]string)
	}
	t.adminRanks[chatID][userID] = rank
}

type forumTopicInfo struct {
	Title     string
	IconColor int
}

func (t *TelegramCore) cacheForumTopic(chatID string, topicID int, title string, iconColor int) {
	t.forumTopicsMu.Lock()
	defer t.forumTopicsMu.Unlock()
	if t.forumTopics == nil {
		t.forumTopics = make(map[string]forumTopicInfo)
	}
	key := chatID + ":" + strconv.Itoa(topicID)
	t.forumTopics[key] = forumTopicInfo{Title: title, IconColor: iconColor}
}

func (t *TelegramCore) GetForumTopicInfo(chatID, topicID string) (title string, iconColor int, ok bool) {
	t.forumTopicsMu.RLock()
	defer t.forumTopicsMu.RUnlock()
	key := chatID + ":" + topicID
	if info, found := t.forumTopics[key]; found {
		return info.Title, info.IconColor, true
	}
	return "", 0, false
}

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

func (t *TelegramCore) GetAdminRanks(chatID string) (map[string]string, error) {
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
		return nil, nil
	}

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

func (t *TelegramCore) ProvideAuthCode(code string) {
	if t.authCodeCh != nil {
		t.authCodeCh <- code
	}
}

func (t *TelegramCore) ProvideAuthPassword(password string) {
	if t.authPwdCh != nil {
		t.authPwdCh <- password
	}
}

func (t *TelegramCore) AuthCodeRequested() <-chan struct{} {
	if t.authSetupDone != nil {
		<-t.authSetupDone
	}
	return t.authCodeReady
}

func (t *TelegramCore) AuthPasswordRequested() <-chan struct{} {
	if t.authSetupDone != nil {
		<-t.authSetupDone
	}
	return t.authPwdReady
}

func (t *TelegramCore) StartQRAuth() (tokenURL string, expiresSecs int, err error) {
	t.mu.Lock()
	live := t.api != nil
	t.mu.Unlock()
	if live {
		return t.exportQRLoginToken()
	}
	t.teardownPriorAuthAttempt()

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
			api := t.guardedClient()
			up := uploader.NewUploader(api)
			sndr := message.NewSender(api).WithUploader(up)

			t.mu.Lock()
			t.api = api
			t.sender = sndr
			t.mu.Unlock()

			close(clientReady)

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
		if err := t.acceptQRAuthorization(v.Authorization); err != nil {
			return "", 0, err
		}
		return "", 0, nil

	case *tg.AuthLoginTokenMigrateTo:
		if err := t.client.MigrateTo(t.ctx, v.DCID); err != nil {
			return "", 0, fmt.Errorf("qr migrate to DC %d: %w", v.DCID, err)
		}
		imported, err := t.api.AuthImportLoginToken(t.ctx, v.Token)
		if err != nil {
			return "", 0, fmt.Errorf("qr import login token: %w", err)
		}
		switch res := imported.(type) {
		case *tg.AuthLoginTokenSuccess:
			if err := t.acceptQRAuthorization(res.Authorization); err != nil {
				return "", 0, err
			}
			return "", 0, nil
		case *tg.AuthLoginToken:
			url := "tg://login?token=" + base64.RawURLEncoding.EncodeToString(res.Token)
			expiry := int(res.Expires) - int(time.Now().Unix())
			if expiry < 0 {
				expiry = 30
			}
			return url, expiry, nil
		default:
			return "", 0, fmt.Errorf("unexpected import token type: %T", imported)
		}
	}

	return "", 0, fmt.Errorf("unexpected token type: %T", result)
}

func (t *TelegramCore) acceptQRAuthorization(auth tg.AuthAuthorizationClass) error {
	authResult, ok := auth.(*tg.AuthAuthorization)
	if !ok {
		return fmt.Errorf("unexpected auth type: %T", auth)
	}
	u, ok := authResult.User.(*tg.User)
	if !ok {
		return fmt.Errorf("unexpected user type: %T", authResult.User)
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
	return nil
}

type telegramAuthFlow struct {
	phone    string
	code     string
	password string

	lastPassword string
	core         *TelegramCore

	codeCh      chan string
	codeReady   chan struct{}
	pwdCh       chan string
	pwdReady    chan struct{}
	signUpCh    chan [2]string
	signUpReady chan struct{}
}

func (f *telegramAuthFlow) Phone(_ context.Context) (string, error) {
	return f.phone, nil
}

func (f *telegramAuthFlow) Password(ctx context.Context) (string, error) {
	if f.password != "" {
		f.lastPassword = f.password
		return f.password, nil
	}
	if f.pwdCh != nil {
		close(f.pwdReady)
		select {
		case pw := <-f.pwdCh:
			f.lastPassword = pw
			return pw, nil
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	return "", fmt.Errorf("2FA password required but not provided")
}

func (f *telegramAuthFlow) Code(ctx context.Context, sentCode *tg.AuthSentCode) (string, error) {
	if sentCode != nil && f.core != nil {
		f.core.mu.Lock()
		f.core.authPhoneHash = sentCode.PhoneCodeHash
		f.core.authCodeTimeout = sentCode.Timeout
		f.core.authCodeByTelegram = false
		f.core.authCodeFragmentURL = ""
		f.core.authCodeEmailPattern = ""
		switch ct := sentCode.Type.(type) {
		case *tg.AuthSentCodeTypeApp:
			f.core.authCodeByTelegram = true
			f.core.authCodeLength = ct.Length
		case *tg.AuthSentCodeTypeFragmentSMS:
			f.core.authCodeFragmentURL = ct.URL
			if ct.Length > 0 {
				f.core.authCodeLength = ct.Length
			}
		case *tg.AuthSentCodeTypeEmailCode:
			f.core.authCodeEmailPattern = ct.EmailPattern
			if ct.Length > 0 {
				f.core.authCodeLength = ct.Length
			}
		case *tg.AuthSentCodeTypeSetUpEmailRequired:
			emailReady := f.core.authEmailReady
			f.core.emailSetupMode = true
			f.core.mu.Unlock()
			if emailReady != nil {
				close(emailReady)
			}
			<-ctx.Done()
			return "", ctx.Err()
		default:
			if l, ok := sentCode.Type.(interface{ GetLength() int }); ok {
				f.core.authCodeLength = l.GetLength()
			}
		}
		f.core.mu.Unlock()
	}
	if f.code != "" {
		return f.code, nil
	}
	if f.codeCh != nil {
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

func (f *telegramAuthFlow) SignUp(ctx context.Context) (auth.UserInfo, error) {
	if f.signUpCh != nil {
		close(f.signUpReady)
		select {
		case names := <-f.signUpCh:
			return auth.UserInfo{FirstName: names[0], LastName: names[1]}, nil
		case <-ctx.Done():
			return auth.UserInfo{}, ctx.Err()
		}
	}
	return auth.UserInfo{}, fmt.Errorf("sign up not supported")
}

func (t *TelegramCore) SearchMessagesGlobal(query string, limit int) ([]Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	if limit <= 0 {
		limit = 20
	}

	result, err := api.MessagesSearchGlobal(ctx, &tg.MessagesSearchGlobalRequest{
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

func (t *TelegramCore) GetContacts() ([]User, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.ContactsGetContacts(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get contacts: %w", err)
	}

	contacts, ok := result.(*tg.ContactsContacts)
	if !ok {
		return nil, nil
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

func (t *TelegramCore) BlockUser(userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	id, err := tgUserID(userID)
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(id)
	_, err = api.ContactsBlock(ctx, &tg.ContactsBlockRequest{
		ID: &tg.InputPeerUser{UserID: id, AccessHash: hash},
	})
	return err
}

func (t *TelegramCore) UnblockUser(userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	id, err := tgUserID(userID)
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(id)
	_, err = api.ContactsUnblock(ctx, &tg.ContactsUnblockRequest{
		ID: &tg.InputPeerUser{UserID: id, AccessHash: hash},
	})
	return err
}

func (t *TelegramCore) ArchiveChat(chatID string, archived bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	folderID := 1
	if !archived {
		folderID = 0
	}

	_, err = t.api.FoldersEditPeerFolders(t.ctx, []tg.InputFolderPeer{
		{Peer: inputPeer, FolderID: folderID},
	})
	return err
}

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

func (t *TelegramCore) ClearDraft(chatID string) error {
	return t.SaveDraft(chatID, "")
}

type ActiveSession struct {
	Hash            int64  `json:"hash"`
	Device          string `json:"device"`
	Platform        string `json:"platform"`
	SystemName      string `json:"system_name"`
	AppName         string `json:"app_name"`
	AppVersion      string `json:"app_version"`
	IP              string `json:"ip"`
	Country         string `json:"country"`
	DateCreated     int    `json:"date_created"`
	DateActive      int    `json:"date_active"`
	IsCurrent       bool   `json:"is_current"`
	PasswordPending bool   `json:"password_pending"`
	ApiID           int    `json:"api_id"`
	OfficialApp     bool   `json:"official_app"`
}

func (t *TelegramCore) GetActiveSessions() ([]ActiveSession, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.AccountGetAuthorizations(ctx)
	if err != nil {
		return nil, fmt.Errorf("get sessions: %w", err)
	}

	var sessions []ActiveSession
	for _, a := range result.Authorizations {
		sessions = append(sessions, ActiveSession{
			Hash:            a.Hash,
			Device:          a.DeviceModel,
			Platform:        a.Platform,
			SystemName:      a.SystemVersion,
			AppName:         a.AppName,
			AppVersion:      a.AppVersion,
			IP:              a.IP,
			Country:         a.Country,
			DateCreated:     a.DateCreated,
			DateActive:      a.DateActive,
			IsCurrent:       a.Current,
			PasswordPending: a.PasswordPending,
			ApiID:           a.APIID,
			OfficialApp:     a.OfficialApp,
		})
	}
	return sessions, nil
}

func (t *TelegramCore) GetSessionAutoTerminateDays() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.AccountGetAuthorizations(ctx)
	if err != nil {
		return 0, err
	}
	return result.AuthorizationTTLDays, nil
}

func (t *TelegramCore) SetSessionAutoTerminateDays(days int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountSetAuthorizationTTL(ctx, days)
	return err
}

func (t *TelegramCore) SetCustomDeviceModel(model string) {
	t.mu.Lock()
	t.customDeviceModel = model
	t.mu.Unlock()
}

func (t *TelegramCore) SetGroupPermissions(chatID string, rights tg.ChatBannedRights) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()

	_, err = t.api.MessagesEditChatDefaultBannedRights(t.ctx, &tg.MessagesEditChatDefaultBannedRightsRequest{
		Peer:         inputPeer,
		BannedRights: rights,
	})
	return err
}

func (t *TelegramCore) PromoteAdmin(chatID, userID string, rights tg.ChatAdminRights) error {
	return t.promoteAdminInternal(chatID, userID, rights, "")
}

func (t *TelegramCore) promoteAdminInternal(chatID, userID string, rights tg.ChatAdminRights, rank string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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

	_, err = api.ChannelsEditAdmin(ctx, &tg.ChannelsEditAdminRequest{
		Channel:     &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		UserID:      &tg.InputUser{UserID: uid, AccessHash: uhash},
		AdminRights: rights,
		Rank:        rank,
	})
	return err
}

func (t *TelegramCore) PromoteAdminWithRights(chatID, userID string, rights map[string]bool, rank string) error {
	return t.promoteAdminInternal(chatID, userID, tg.ChatAdminRights{
		ChangeInfo:           rights["change_info"],
		DeleteMessages:       rights["delete_messages"],
		BanUsers:             rights["ban_users"],
		InviteUsers:          rights["invite_users"],
		PinMessages:          rights["pin_messages"],
		ManageTopics:         rights["manage_topics"],
		PostMessages:         rights["post_messages"],
		EditMessages:         rights["edit_messages"],
		PostStories:          rights["post_stories"],
		EditStories:          rights["edit_stories"],
		DeleteStories:        rights["delete_stories"],
		ManageCall:           rights["manage_call"],
		AddAdmins:            rights["add_admins"],
		Anonymous:            rights["anonymous"],
		ManageRanks:          rights["manage_ranks"],
		ManageDirectMessages: rights["manage_direct"],
		Other:                true,
	}, rank)
}

func (t *TelegramCore) PromoteToAdmin(chatID, userID string) error {
	return t.PromoteAdmin(chatID, userID, tg.ChatAdminRights{
		ChangeInfo:     true,
		DeleteMessages: true,
		BanUsers:       true,
		InviteUsers:    true,
		PinMessages:    true,
		ManageCall:     true,
	})
}

func (t *TelegramCore) DemoteAdmin(chatID, userID string) error {
	return t.PromoteAdmin(chatID, userID, tg.ChatAdminRights{})
}

func (t *TelegramCore) TransferChannelOwnership(chatID, userID, password string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return fmt.Errorf("get password params: %w", err)
	}
	srpCheck, err := auth.PasswordHash([]byte(password), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
	if err != nil {
		return fmt.Errorf("SRP computation failed: %w", err)
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return fmt.Errorf("resolve chat: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return fmt.Errorf("convert to input peer: %w", err)
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid user ID: %w", err)
	}
	inputUser := &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)}
	_, err = api.MessagesEditChatCreator(ctx, &tg.MessagesEditChatCreatorRequest{
		Peer:     inputPeer,
		UserID:   inputUser,
		Password: srpCheck,
	})
	return err
}

func (t *TelegramCore) TransferOwnershipPreflight(chatID, userID string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", fmt.Errorf("resolve chat: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return "", fmt.Errorf("convert to input peer: %w", err)
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil {
		return "", fmt.Errorf("invalid user ID: %w", err)
	}
	inputUser := &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)}
	_, err = api.MessagesEditChatCreator(ctx, &tg.MessagesEditChatCreatorRequest{
		Peer:     inputPeer,
		UserID:   inputUser,
		Password: &tg.InputCheckPasswordEmpty{},
	})
	if err == nil {
		return "ok", nil
	}
	msg := err.Error()
	switch {
	case strings.Contains(msg, "PASSWORD_MISSING"):
		return "no_password", nil
	case strings.Contains(msg, "PASSWORD_TOO_FRESH"):
		return "password_too_fresh", nil
	case strings.Contains(msg, "SESSION_TOO_FRESH"):
		return "session_too_fresh", nil
	case strings.Contains(msg, "PASSWORD_HASH_INVALID") || strings.Contains(msg, "SRP"):
		return "need_password", nil
	default:
		return msg, nil
	}
}

func (t *TelegramCore) RestrictMember(chatID, userID string) error {
	return t.RestrictUser(chatID, userID, tg.ChatBannedRights{
		SendMessages: true,
		SendMedia:    true,
		SendStickers: true,
		SendGifs:     true,
		SendGames:    true,
		SendInline:   true,
		SendPolls:    true,
	})
}

func (t *TelegramCore) RestrictUser(chatID, userID string, rights tg.ChatBannedRights) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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

	_, err = api.ChannelsEditBanned(ctx, &tg.ChannelsEditBannedRequest{
		Channel:      &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		BannedRights: rights,
	})
	return err
}

func (t *TelegramCore) RestrictMemberWithRights(chatID, userID string, rights *DefaultBannedRights, untilDate int) error {
	br := tg.ChatBannedRights{
		SendPlain:       rights.SendPlain,
		SendPhotos:      rights.SendPhotos,
		SendVideos:      rights.SendVideos,
		SendRoundvideos: rights.SendRoundvideos,
		SendAudios:      rights.SendAudios,
		SendVoices:      rights.SendVoices,
		SendDocs:        rights.SendDocs,
		SendStickers:    rights.SendStickers,
		SendGifs:        rights.SendStickers,
		SendGames:       rights.SendStickers,
		SendInline:      rights.SendStickers,
		EmbedLinks:      rights.EmbedLinks,
		SendPolls:       rights.SendPolls,
		InviteUsers:     rights.InviteUsers,
		ManageTopics:    rights.ManageTopics,
		PinMessages:     rights.PinMessages,
		EditRank:        rights.EditRank,
		ChangeInfo:      rights.ChangeInfo,
		UntilDate:       untilDate,
	}
	br.SetFlags()
	return t.RestrictUser(chatID, userID, br)
}

func (t *TelegramCore) SetSlowMode(chatID string, seconds int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
	_, err = api.ChannelsToggleSlowMode(ctx, &tg.ChannelsToggleSlowModeRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Seconds: seconds,
	})
	return err
}

type AdminLogEvent struct {
	ID         int64                  `json:"id"`
	Date       int                    `json:"date"`
	UserID     int64                  `json:"user_id"`
	UserName   string                 `json:"user_name"`
	Action     string                 `json:"action"`
	Detail     string                 `json:"detail"`
	OldValue   string                 `json:"old_value,omitempty"`
	NewValue   string                 `json:"new_value,omitempty"`
	MessageID  int                    `json:"message_id,omitempty"`
	MsgText    string                 `json:"msg_text,omitempty"`
	ActionData map[string]interface{} `json:"action_data,omitempty"`
}

func (t *TelegramCore) GetAdminLogEvents(chatID string, limit int, query string, maxID int64, filters map[string]bool, admins []string) ([]AdminLogEvent, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("admin log only works on channels/supergroups")
	}

	if limit <= 0 {
		limit = 20
	}

	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	req := &tg.ChannelsGetAdminLogRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Q:       query,
		Limit:   limit,
		MaxID:   maxID,
	}
	if len(filters) > 0 {
		f := tg.ChannelAdminLogEventsFilter{}
		f.SetFlags()
		if v, ok := filters["join"]; ok {
			f.Join = v
		}
		if v, ok := filters["leave"]; ok {
			f.Leave = v
		}
		if v, ok := filters["invite"]; ok {
			f.Invite = v
		}
		if v, ok := filters["ban"]; ok {
			f.Ban = v
		}
		if v, ok := filters["unban"]; ok {
			f.Unban = v
		}
		if v, ok := filters["kick"]; ok {
			f.Kick = v
		}
		if v, ok := filters["unkick"]; ok {
			f.Unkick = v
		}
		if v, ok := filters["promote"]; ok {
			f.Promote = v
		}
		if v, ok := filters["demote"]; ok {
			f.Demote = v
		}
		if v, ok := filters["info"]; ok {
			f.Info = v
		}
		if v, ok := filters["settings"]; ok {
			f.Settings = v
		}
		if v, ok := filters["pinned"]; ok {
			f.Pinned = v
		}
		if v, ok := filters["group_call"]; ok {
			f.GroupCall = v
		}
		if v, ok := filters["invites"]; ok {
			f.Invites = v
		}
		if v, ok := filters["edit"]; ok {
			f.Edit = v
		}
		if v, ok := filters["delete"]; ok {
			f.Delete = v
		}
		if v, ok := filters["forums"]; ok {
			f.Forums = v
		}
		if v, ok := filters["sub_extend"]; ok {
			f.SubExtend = v
		}
		req.SetEventsFilter(f)
	}
	if len(admins) > 0 {
		inputs := make([]tg.InputUserClass, 0, len(admins))
		for _, a := range admins {
			uid, err := tgUserID(a)
			if err != nil {
				continue
			}
			inputs = append(inputs, &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)})
		}
		if len(inputs) > 0 {
			req.SetAdmins(inputs)
		}
	}
	result, err := api.ChannelsGetAdminLog(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("get admin log: %w", err)
	}

	userMap := make(map[int64]*tg.User)
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok {
			userMap[user.ID] = user
		}
	}

	events := make([]AdminLogEvent, 0, len(result.Events))
	for _, ev := range result.Events {
		userName := ""
		if u, ok := userMap[ev.UserID]; ok {
			userName = userDisplayName(u)
		}
		action, detail, oldVal, newVal, msgID, msgText := t.describeAdminLogAction(ev.Action, userMap)
		events = append(events, AdminLogEvent{
			ID:         ev.ID,
			Date:       ev.Date,
			UserID:     ev.UserID,
			UserName:   userName,
			Action:     action,
			Detail:     detail,
			OldValue:   oldVal,
			NewValue:   newVal,
			MessageID:  msgID,
			MsgText:    msgText,
			ActionData: t.adminLogActionData(ev.Action, userMap),
		})
	}
	return events, nil
}

func (t *TelegramCore) describeAdminLogAction(action tg.ChannelAdminLogEventActionClass, users map[int64]*tg.User) (actionType, detail, oldVal, newVal string, msgID int, msgText string) {
	switch a := action.(type) {
	case *tg.ChannelAdminLogEventActionChangeTitle:
		return "change_title", "", a.PrevValue, a.NewValue, 0, ""
	case *tg.ChannelAdminLogEventActionChangeAbout:
		return "change_about", "", a.PrevValue, a.NewValue, 0, ""
	case *tg.ChannelAdminLogEventActionChangeUsername:
		return "change_username", "", a.PrevValue, a.NewValue, 0, ""
	case *tg.ChannelAdminLogEventActionChangePhoto:
		return "change_photo", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleInvites:
		if a.NewValue {
			return "toggle_invites", "enabled", "", "", 0, ""
		}
		return "toggle_invites", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleSignatures:
		if a.NewValue {
			return "toggle_signatures", "enabled", "", "", 0, ""
		}
		return "toggle_signatures", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionUpdatePinned:
		txt := extractMessageText(a.Message)
		mid := extractMessageID(a.Message)
		if txt == "" {
			return "unpin_message", "", "", "", mid, ""
		}
		return "pin_message", "", "", "", mid, txt
	case *tg.ChannelAdminLogEventActionEditMessage:
		oldTxt := extractMessageText(a.PrevMessage)
		newTxt := extractMessageText(a.NewMessage)
		mid := extractMessageID(a.NewMessage)
		return "edit_message", "", oldTxt, newTxt, mid, newTxt
	case *tg.ChannelAdminLogEventActionDeleteMessage:
		txt := extractMessageText(a.Message)
		mid := extractMessageID(a.Message)
		return "delete_message", "", "", "", mid, txt
	case *tg.ChannelAdminLogEventActionParticipantJoin:
		return "participant_join", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantLeave:
		return "participant_leave", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantInvite:
		name := participantUserName(a.Participant, users)
		return "participant_invite", name, "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantToggleBan:
		name := participantUserName(a.PrevParticipant, users)
		return "participant_ban", name, "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantToggleAdmin:
		name := participantUserName(a.PrevParticipant, users)
		return "participant_admin", name, "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeStickerSet:
		return "change_stickerset", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionTogglePreHistoryHidden:
		if a.NewValue {
			return "toggle_prehistory", "hidden", "", "", 0, ""
		}
		return "toggle_prehistory", "visible", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionDefaultBannedRights:
		return "change_default_rights", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionStopPoll:
		return "stop_poll", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeLinkedChat:
		return "change_linked_chat", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleSlowMode:
		return "toggle_slowmode", fmt.Sprintf("%ds → %ds", a.PrevValue, a.NewValue), "", "", 0, ""
	case *tg.ChannelAdminLogEventActionStartGroupCall:
		return "start_call", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionDiscardGroupCall:
		return "end_call", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantMute:
		return "participant_mute", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantUnmute:
		return "participant_unmute", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleGroupCallSetting:
		if a.JoinMuted {
			return "call_setting", "join muted", "", "", 0, ""
		}
		return "call_setting", "join unmuted", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantJoinByInvite:
		return "join_by_invite", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionExportedInviteDelete:
		return "invite_delete", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionExportedInviteRevoke:
		return "invite_revoke", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionExportedInviteEdit:
		return "invite_edit", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeHistoryTTL:
		return "change_ttl", fmt.Sprintf("%ds → %ds", a.PrevValue, a.NewValue), "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleNoForwards:
		if a.NewValue {
			return "toggle_noforwards", "enabled", "", "", 0, ""
		}
		return "toggle_noforwards", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionSendMessage:
		txt := extractMessageText(a.Message)
		mid := extractMessageID(a.Message)
		return "send_message", "", "", "", mid, txt
	case *tg.ChannelAdminLogEventActionToggleForum:
		if a.NewValue {
			return "toggle_forum", "enabled", "", "", 0, ""
		}
		return "toggle_forum", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionCreateTopic:
		return "create_topic", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionEditTopic:
		return "edit_topic", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionDeleteTopic:
		return "delete_topic", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionPinTopic:
		return "pin_topic", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleAntiSpam:
		if a.NewValue {
			return "toggle_antispam", "enabled", "", "", 0, ""
		}
		return "toggle_antispam", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeAvailableReactions:
		return "change_reactions", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeUsernames:
		return "change_usernames", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangePeerColor:
		return "change_peer_color", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeProfilePeerColor:
		return "change_profile_color", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeWallpaper:
		return "change_wallpaper", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeEmojiStatus:
		return "change_emoji_status", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionChangeEmojiStickerSet:
		return "change_emoji_stickerset", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleSignatureProfiles:
		if a.NewValue {
			return "toggle_signature_profiles", "enabled", "", "", 0, ""
		}
		return "toggle_signature_profiles", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantSubExtend:
		return "sub_extend", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantJoinByRequest:
		return "join_by_request", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantVolume:
		return "participant_volume", "", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionToggleAutotranslation:
		if a.NewValue {
			return "toggle_autotranslation", "enabled", "", "", 0, ""
		}
		return "toggle_autotranslation", "disabled", "", "", 0, ""
	case *tg.ChannelAdminLogEventActionParticipantEditRank:
		return "participant_edit_rank", "", "", "", 0, ""
	default:
		return "unknown", fmt.Sprintf("%T", action), "", "", 0, ""
	}
}

func adminLogBannedRightsMap(br *tg.ChatBannedRights) map[string]bool {
	if br == nil {
		return nil
	}
	return map[string]bool{
		"view_messages":    br.ViewMessages,
		"send_plain":       br.SendMessages,
		"send_media":       br.SendMedia,
		"send_stickers":    br.SendStickers,
		"send_gifs":        br.SendGifs,
		"send_games":       br.SendGames,
		"send_inline":      br.SendInline,
		"embed_links":      br.EmbedLinks,
		"send_polls":       br.SendPolls,
		"send_photos":      br.SendPhotos,
		"send_videos":      br.SendVideos,
		"send_roundvideos": br.SendRoundvideos,
		"send_audios":      br.SendAudios,
		"send_voices":      br.SendVoices,
		"send_docs":        br.SendDocs,
		"invite_users":     br.InviteUsers,
		"manage_topics":    br.ManageTopics,
		"pin_messages":     br.PinMessages,
		"change_info":      br.ChangeInfo,
		"edit_rank":        br.EditRank,
	}
}

func adminLogAdminRightsMap(ar *tg.ChatAdminRights) map[string]bool {
	if ar == nil {
		return nil
	}
	return map[string]bool{
		"change_info":     ar.ChangeInfo,
		"post_messages":   ar.PostMessages,
		"edit_messages":   ar.EditMessages,
		"delete_messages": ar.DeleteMessages,
		"ban_users":       ar.BanUsers,
		"invite_users":    ar.InviteUsers,
		"pin_messages":    ar.PinMessages,
		"manage_topics":   ar.ManageTopics,
		"add_admins":      ar.AddAdmins,
		"anonymous":       ar.Anonymous,
		"manage_call":     ar.ManageCall,
		"manage_direct":   ar.ManageDirectMessages,
		"manage_ranks":    ar.ManageRanks,
		"post_stories":    ar.PostStories,
		"edit_stories":    ar.EditStories,
		"delete_stories":  ar.DeleteStories,
	}
}

func adminLogParticipantRights(p tg.ChannelParticipantClass) (admin map[string]bool, banned map[string]bool, isMember bool, rank string) {
	switch pp := p.(type) {
	case *tg.ChannelParticipant, *tg.ChannelParticipantSelf:
		isMember = true
	case *tg.ChannelParticipantCreator:
		isMember = true
		admin = adminLogAdminRightsMap(&pp.AdminRights)
		rank = pp.Rank
	case *tg.ChannelParticipantAdmin:
		isMember = true
		admin = adminLogAdminRightsMap(&pp.AdminRights)
		rank = pp.Rank
	case *tg.ChannelParticipantBanned:
		isMember = !pp.Left
		banned = adminLogBannedRightsMap(&pp.BannedRights)
	}
	return
}

func adminLogInviteLink(inv tg.ExportedChatInviteClass) string {
	if e, ok := inv.(*tg.ChatInviteExported); ok {
		return e.Link
	}
	return ""
}

func adminLogInviteFields(inv tg.ExportedChatInviteClass) (string, map[string]interface{}) {
	e, ok := inv.(*tg.ChatInviteExported)
	if !ok {
		return "", map[string]interface{}{}
	}
	title, _ := e.GetTitle()
	expire, _ := e.GetExpireDate()
	usage, _ := e.GetUsageLimit()
	return e.Link, map[string]interface{}{
		"title":          title,
		"expire":         expire,
		"usage":          usage,
		"request_needed": e.RequestNeeded,
	}
}

func adminLogTopicFields(tc tg.ForumTopicClass) (title string, closed, hidden bool, id int) {
	if ft, ok := tc.(*tg.ForumTopic); ok {
		return ft.Title, ft.Closed, ft.Hidden, ft.ID
	}
	if ft, ok := tc.(*tg.ForumTopicDeleted); ok {
		return "", false, false, ft.ID
	}
	return "", false, false, 0
}

func (t *TelegramCore) adminLogActionData(action tg.ChannelAdminLogEventActionClass, users map[int64]*tg.User) map[string]interface{} {
	msgMedia := func(m tg.MessageClass) map[string]interface{} {
		msg, ok := m.(*tg.Message)
		if !ok || msg.Media == nil {
			return nil
		}
		mt, thumb := extractMessageMediaSummary(msg)
		if mt == 0 {
			return nil
		}
		d := map[string]interface{}{"media_type": mt}
		if thumb != "" {
			d["thumb_b64"] = thumb
		}
		return d
	}
	nameOf := func(id int64) string {
		if u, ok := users[id]; ok {
			return userDisplayName(u)
		}
		return ""
	}
	switch a := action.(type) {
	case *tg.ChannelAdminLogEventActionUpdatePinned:
		return msgMedia(a.Message)
	case *tg.ChannelAdminLogEventActionDeleteMessage:
		return msgMedia(a.Message)
	case *tg.ChannelAdminLogEventActionSendMessage:
		return msgMedia(a.Message)
	case *tg.ChannelAdminLogEventActionEditMessage:
		return msgMedia(a.NewMessage)
	case *tg.ChannelAdminLogEventActionParticipantEditRank:
		return map[string]interface{}{
			"rank_user": nameOf(a.UserID),
			"prev_rank": a.PrevRank,
			"new_rank":  a.NewRank,
		}
	case *tg.ChannelAdminLogEventActionParticipantToggleBan:
		_, prevB, prevMember, _ := adminLogParticipantRights(a.PrevParticipant)
		_, newB, newMember, _ := adminLogParticipantRights(a.NewParticipant)
		return map[string]interface{}{
			"target":      participantUserName(a.NewParticipant, users),
			"prev_banned": prevB,
			"new_banned":  newB,
			"prev_member": prevMember,
			"new_member":  newMember,
		}
	case *tg.ChannelAdminLogEventActionParticipantToggleAdmin:
		prevA, _, _, prevRank := adminLogParticipantRights(a.PrevParticipant)
		newA, _, _, newRank := adminLogParticipantRights(a.NewParticipant)
		return map[string]interface{}{
			"target":     participantUserName(a.NewParticipant, users),
			"prev_admin": prevA,
			"new_admin":  newA,
			"prev_rank":  prevRank,
			"new_rank":   newRank,
		}
	case *tg.ChannelAdminLogEventActionParticipantInvite:
		adminMap, bannedMap, isMember, _ := adminLogParticipantRights(a.Participant)
		d := map[string]interface{}{
			"target":     participantUserName(a.Participant, users),
			"inv_member": isMember,
		}
		switch pp := a.Participant.(type) {
		case *tg.ChannelParticipantAdmin, *tg.ChannelParticipantCreator:
			d["inv_type"] = "admin"
			d["new_admin"] = adminMap
		case *tg.ChannelParticipantBanned:
			if bannedMap != nil && bannedMap["view_messages"] {
				d["inv_type"] = "banned"
			} else {
				d["inv_type"] = "restricted"
			}
			d["new_banned"] = bannedMap
			d["inv_until"] = pp.BannedRights.UntilDate
		default:
			d["inv_type"] = "member"
		}
		return d
	case *tg.ChannelAdminLogEventActionChangeAvailableReactions:
		d := map[string]interface{}{}
		mode, list := adminLogReactions(a.NewValue)
		d["reactions_mode"] = mode
		if len(list) > 0 {
			d["reactions_list"] = list
		}
		return d
	case *tg.ChannelAdminLogEventActionDefaultBannedRights:
		return map[string]interface{}{
			"prev_banned": adminLogBannedRightsMap(&a.PrevBannedRights),
			"new_banned":  adminLogBannedRightsMap(&a.NewBannedRights),
		}
	case *tg.ChannelAdminLogEventActionParticipantJoinByInvite:
		return map[string]interface{}{
			"link":         adminLogInviteLink(a.Invite),
			"via_chatlist": a.ViaChatlist,
		}
	case *tg.ChannelAdminLogEventActionExportedInviteDelete:
		return map[string]interface{}{"link": adminLogInviteLink(a.Invite)}
	case *tg.ChannelAdminLogEventActionExportedInviteRevoke:
		return map[string]interface{}{"link": adminLogInviteLink(a.Invite)}
	case *tg.ChannelAdminLogEventActionExportedInviteEdit:
		prevLink, prevFields := adminLogInviteFields(a.PrevInvite)
		newLink, newFields := adminLogInviteFields(a.NewInvite)
		d := map[string]interface{}{
			"link":      newLink,
			"prev_link": prevLink,
		}
		for k, v := range prevFields {
			d["prev_"+k] = v
		}
		for k, v := range newFields {
			d["new_"+k] = v
		}
		return d
	case *tg.ChannelAdminLogEventActionParticipantJoinByRequest:
		return map[string]interface{}{
			"link":        adminLogInviteLink(a.Invite),
			"approved_by": nameOf(a.ApprovedBy),
		}
	case *tg.ChannelAdminLogEventActionParticipantMute:
		uid := groupCallParticipantUserID(a.Participant)
		return map[string]interface{}{"target": nameOf(uid)}
	case *tg.ChannelAdminLogEventActionParticipantUnmute:
		uid := groupCallParticipantUserID(a.Participant)
		return map[string]interface{}{"target": nameOf(uid)}
	case *tg.ChannelAdminLogEventActionParticipantVolume:
		uid := groupCallParticipantUserID(a.Participant)
		vol := 0
		if v, ok := a.Participant.GetVolume(); ok {
			vol = v
		}
		return map[string]interface{}{"target": nameOf(uid), "volume": vol}
	case *tg.ChannelAdminLogEventActionChangeHistoryTTL:
		return map[string]interface{}{"ttl_prev": a.PrevValue, "ttl_new": a.NewValue}
	case *tg.ChannelAdminLogEventActionChangeLinkedChat:
		return map[string]interface{}{
			"linked_prev": a.PrevValue,
			"linked_new":  a.NewValue,
			"linked_name": nameOfChat(a.NewValue, nil),
		}
	case *tg.ChannelAdminLogEventActionToggleSlowMode:
		return map[string]interface{}{"slow_prev": a.PrevValue, "slow_new": a.NewValue}
	case *tg.ChannelAdminLogEventActionChangePhoto:
		_, removed := a.NewPhoto.(*tg.PhotoEmpty)
		return map[string]interface{}{"photo_removed": removed}
	case *tg.ChannelAdminLogEventActionChangeStickerSet:
		_, removed := a.NewStickerset.(*tg.InputStickerSetEmpty)
		return map[string]interface{}{"stickerset_removed": removed}
	case *tg.ChannelAdminLogEventActionChangePeerColor:
		idx, emoji := adminLogPeerColor(a.NewValue)
		return map[string]interface{}{"color_index": idx, "bg_emoji": emoji}
	case *tg.ChannelAdminLogEventActionChangeProfilePeerColor:
		idx, emoji := adminLogPeerColor(a.NewValue)
		return map[string]interface{}{"color_index": idx, "bg_emoji": emoji}
	case *tg.ChannelAdminLogEventActionChangeEmojiStatus:
		doc, until, removed := adminLogEmojiStatus(a.NewValue)
		return map[string]interface{}{"emoji_doc": doc, "emoji_until": until, "emoji_removed": removed}
	case *tg.ChannelAdminLogEventActionToggleGroupCallSetting:
		return map[string]interface{}{"join_muted": a.JoinMuted}
	case *tg.ChannelAdminLogEventActionParticipantSubExtend:
		return map[string]interface{}{"target": participantUserName(a.NewParticipant, users)}
	case *tg.ChannelAdminLogEventActionEditTopic:
		pTitle, pClosed, pHidden, _ := adminLogTopicFields(a.PrevTopic)
		nTitle, nClosed, nHidden, tid := adminLogTopicFields(a.NewTopic)
		return map[string]interface{}{
			"topic_id":    tid,
			"topic_title": nTitle,
			"prev_title":  pTitle,
			"prev_closed": pClosed,
			"new_closed":  nClosed,
			"prev_hidden": pHidden,
			"new_hidden":  nHidden,
		}
	case *tg.ChannelAdminLogEventActionChangeUsernames:
		return map[string]interface{}{
			"prev_usernames": a.PrevValue,
			"new_usernames":  a.NewValue,
		}
	}
	return nil
}

func adminLogReactions(r tg.ChatReactionsClass) (string, []string) {
	switch rr := r.(type) {
	case *tg.ChatReactionsAll:
		return "all", nil
	case *tg.ChatReactionsSome:
		list := []string{}
		for _, rc := range rr.Reactions {
			switch x := rc.(type) {
			case *tg.ReactionEmoji:
				list = append(list, x.Emoticon)
			case *tg.ReactionCustomEmoji:
				list = append(list, fmt.Sprintf("%d", x.DocumentID))
			}
		}
		return "some", list
	default:
		return "none", nil
	}
}

func groupCallParticipantUserID(p tg.GroupCallParticipant) int64 {
	if peer, ok := p.Peer.(*tg.PeerUser); ok {
		return peer.UserID
	}
	return 0
}

func nameOfChat(id int64, _ map[int64]*tg.Chat) string {
	if id == 0 {
		return ""
	}
	return fmt.Sprintf("-100%d", id)
}

func adminLogPeerColor(vc tg.PeerColorClass) (int, int64) {
	v, ok := vc.(*tg.PeerColor)
	if !ok {
		return 0, 0
	}
	idx := 0
	if c, ok := v.GetColor(); ok {
		idx = c
	}
	var emoji int64
	if e, ok := v.GetBackgroundEmojiID(); ok {
		emoji = e
	}
	return idx, emoji
}

func adminLogEmojiStatus(s tg.EmojiStatusClass) (int64, int, bool) {
	switch st := s.(type) {
	case *tg.EmojiStatus:
		until := 0
		if u, ok := st.GetUntil(); ok {
			until = u
		}
		return st.DocumentID, until, false
	default:
		return 0, 0, true
	}
}

func extractMessageText(msg tg.MessageClass) string {
	if m, ok := msg.(*tg.Message); ok {
		return m.Message
	}
	return ""
}

func extractMessageID(msg tg.MessageClass) int {
	if m, ok := msg.(*tg.Message); ok {
		return m.ID
	}
	return 0
}

func participantUserName(p tg.ChannelParticipantClass, users map[int64]*tg.User) string {
	var uid int64
	switch pp := p.(type) {
	case *tg.ChannelParticipant:
		uid = pp.UserID
	case *tg.ChannelParticipantSelf:
		uid = pp.UserID
	case *tg.ChannelParticipantCreator:
		uid = pp.UserID
	case *tg.ChannelParticipantAdmin:
		uid = pp.UserID
	case *tg.ChannelParticipantBanned:
		if peer, ok := pp.Peer.(*tg.PeerUser); ok {
			uid = peer.UserID
		}
	default:
		return ""
	}
	if u, ok := users[uid]; ok {
		return userDisplayName(u)
	}
	return fmt.Sprintf("User#%d", uid)
}

func (t *TelegramCore) GetStickerSet(shortName string) (*tg.MessagesStickerSet, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
		Stickerset: &tg.InputStickerSetShortName{ShortName: shortName},
	})
	if err != nil {
		return nil, fmt.Errorf("get sticker set: %w", err)
	}

	stickerSet, ok := result.(*tg.MessagesStickerSet)
	if !ok {
		return nil, ErrNotFound
	}

	for _, doc := range stickerSet.Documents {
		if d, ok := doc.(*tg.Document); ok {
			t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		}
	}

	return stickerSet, nil
}

func (t *TelegramCore) GetStickerSetInfo(shortName string, setID int64, accessHash int64) (*StickerSetResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	var stickersetInput tg.InputStickerSetClass
	if shortName != "" {
		stickersetInput = &tg.InputStickerSetShortName{ShortName: shortName}
	} else if setID != 0 {
		stickersetInput = &tg.InputStickerSetID{ID: setID, AccessHash: accessHash}
	} else {
		return nil, fmt.Errorf("either short_name or set_id required")
	}

	result, err := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
		Stickerset: stickersetInput,
	})
	if err != nil {
		return nil, fmt.Errorf("get sticker set: %w", err)
	}
	stickerSet, ok := result.(*tg.MessagesStickerSet)
	if !ok {
		return nil, ErrNotFound
	}

	emojiByDocID := make(map[int64]string)
	for _, pack := range stickerSet.Packs {
		for _, docID := range pack.Documents {
			emojiByDocID[docID] = pack.Emoticon
		}
	}

	_, installed := stickerSet.Set.GetInstalledDate()
	setIsPremium := stickerSet.Set.Official && stickerSet.Set.Emojis
	res := &StickerSetResult{
		Title:      stickerSet.Set.Title,
		ShortName:  stickerSet.Set.ShortName,
		Count:      stickerSet.Set.Count,
		Installed:  installed,
		Archived:   stickerSet.Set.Archived,
		Masks:      stickerSet.Set.Masks,
		Emojis:     stickerSet.Set.Emojis,
		IsCreator:  stickerSet.Set.Creator,
		IsPremium:  setIsPremium,
		SetID:      stickerSet.Set.ID,
		AccessHash: stickerSet.Set.AccessHash,
	}

	favedIDs := t.getFavedStickerIDs()

	for _, doc := range stickerSet.Documents {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)

		si := StickerInfo{
			Emoji:    emojiByDocID[d.ID],
			ThumbB64: extractStrippedThumbB64(d.Thumbs),
			MimeType: d.MimeType,
			FileID:   strconv.FormatInt(d.ID, 10),
			IsFaved:  favedIDs[d.ID],
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeImageSize:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeVideo:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeCustomEmoji:
				if !a.Free {
					si.IsPremium = true
				}
			}
		}
		res.Stickers = append(res.Stickers, si)
	}
	return res, nil
}

func (t *TelegramCore) getFavedStickerIDs() map[int64]bool {
	result, err := t.api.MessagesGetFavedStickers(t.ctx, 0)
	if err != nil {
		return nil
	}
	fs, ok := result.(*tg.MessagesFavedStickers)
	if !ok {
		return nil
	}
	ids := make(map[int64]bool, len(fs.Stickers))
	for _, doc := range fs.Stickers {
		if d, ok := doc.(*tg.Document); ok {
			ids[d.ID] = true
		}
	}
	return ids
}

func (t *TelegramCore) DeleteStickerFromSet(fileID int64) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	accessHash := t.GetCachedFileHash(fileID)
	fileRef := t.getCachedFileRef(fileID)
	_, err := t.StickersRemoveStickerFromSet(&tg.InputDocument{
		ID:            fileID,
		AccessHash:    accessHash,
		FileReference: fileRef,
	})
	return err
}

func (t *TelegramCore) GetCreatedStickerSets() ([]StickerSetResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetAllStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get all stickers: %w", err)
	}
	allStickers, ok := result.(*tg.MessagesAllStickers)
	if !ok {
		return nil, nil
	}
	var created []StickerSetResult
	for _, s := range allStickers.Sets {
		if !s.Creator {
			continue
		}
		created = append(created, StickerSetResult{
			Title:      s.Title,
			ShortName:  s.ShortName,
			SetID:      s.ID,
			AccessHash: s.AccessHash,
			Count:      s.Count,
			IsCreator:  true,
		})
	}
	return created, nil
}

func (t *TelegramCore) AddStickerToExistingSet(setID, accessHash, fileID int64, emoji string) error {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return ErrAuth
	}
	docAccessHash := t.GetCachedFileHash(fileID)
	fileRef := t.getCachedFileRef(fileID)
	_, err := t.StickersAddStickerToSet(&tg.StickersAddStickerToSetRequest{
		Stickerset: &tg.InputStickerSetID{ID: setID, AccessHash: accessHash},
		Sticker: tg.InputStickerSetItem{
			Document: &tg.InputDocument{
				ID:            fileID,
				AccessHash:    docAccessHash,
				FileReference: fileRef,
			},
			Emoji: emoji,
		},
	})
	return err
}

func (t *TelegramCore) GetStickerSuggestions(emoji string) ([]StickerInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesGetStickers(ctx, &tg.MessagesGetStickersRequest{
		Emoticon: emoji,
		Hash:     0,
	})
	if err != nil {
		return nil, fmt.Errorf("get stickers: %w", err)
	}
	stickers, ok := result.(*tg.MessagesStickers)
	if !ok {
		return nil, nil
	}

	var out []StickerInfo
	for _, doc := range stickers.Stickers {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		si := StickerInfo{
			Emoji:    emoji,
			ThumbB64: extractStrippedThumbB64(d.Thumbs),
			MimeType: d.MimeType,
			FileID:   strconv.FormatInt(d.ID, 10),
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeImageSize:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeVideo:
				si.Width = a.W
				si.Height = a.H
			}
		}
		out = append(out, si)
	}
	return out, nil
}

func (t *TelegramCore) GetInstalledEmojiSets() ([]EmojiSetSummary, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesGetEmojiStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get emoji stickers: %w", err)
	}
	allStickers, ok := result.(*tg.MessagesAllStickers)
	if !ok {
		return nil, nil
	}

	var sets []EmojiSetSummary
	for _, s := range allStickers.Sets {
		_, installed := s.GetInstalledDate()
		summary := EmojiSetSummary{
			SetID:      s.ID,
			AccessHash: s.AccessHash,
			Title:      s.Title,
			ShortName:  s.ShortName,
			Count:      s.Count,
			Installed:  installed,
		}

		setResult, err := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
			Stickerset: &tg.InputStickerSetID{ID: s.ID, AccessHash: s.AccessHash},
		})
		if err != nil {
			sets = append(sets, summary)
			continue
		}
		stickerSet, ok := setResult.(*tg.MessagesStickerSet)
		if !ok {
			sets = append(sets, summary)
			continue
		}

		emojiByDocID := make(map[int64]string)
		for _, pack := range stickerSet.Packs {
			for _, docID := range pack.Documents {
				emojiByDocID[docID] = pack.Emoticon
			}
		}

		for _, doc := range stickerSet.Documents {
			d, ok := doc.(*tg.Document)
			if !ok {
				continue
			}
			t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
			si := StickerInfo{
				Emoji:    emojiByDocID[d.ID],
				ThumbB64: extractStrippedThumbB64(d.Thumbs),
				MimeType: d.MimeType,
				FileID:   strconv.FormatInt(d.ID, 10),
			}
			for _, attr := range d.Attributes {
				switch a := attr.(type) {
				case *tg.DocumentAttributeImageSize:
					si.Width = a.W
					si.Height = a.H
				case *tg.DocumentAttributeVideo:
					si.Width = a.W
					si.Height = a.H
				}
			}
			summary.Stickers = append(summary.Stickers, si)
		}
		sets = append(sets, summary)
	}
	return sets, nil
}

func (t *TelegramCore) GetCustomEmojiThumbs(documentIDs []int64) ([]CustomEmojiThumb, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	docs, err := api.MessagesGetCustomEmojiDocuments(ctx, documentIDs)
	if err != nil {
		return nil, fmt.Errorf("get custom emoji documents: %w", err)
	}
	thumbByID := make(map[int64]*CustomEmojiThumb)
	var needDownload []struct {
		doc *tg.Document
		loc tg.InputFileLocationClass
	}
	for _, doc := range docs {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		entry := &CustomEmojiThumb{DocumentID: d.ID}
		for _, s := range d.Thumbs {
			if ps, ok := s.(*tg.PhotoPathSize); ok && len(ps.Bytes) > 0 {
				entry.PathB64 = base64.StdEncoding.EncodeToString(ps.Bytes)
			}
		}
		entry.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
		if entry.ThumbB64 != "" {
			thumbByID[d.ID] = entry
			continue
		}
		thumbByID[d.ID] = entry
		var thumbType string
		for _, s := range d.Thumbs {
			switch s.(type) {
			case *tg.PhotoSize:
				thumbType = "s"
			case *tg.PhotoCachedSize:
				thumbType = "s"
			}
			if thumbType != "" {
				break
			}
		}
		if thumbType != "" {
			loc := &tg.InputDocumentFileLocation{
				ID:            d.ID,
				AccessHash:    d.AccessHash,
				FileReference: d.FileReference,
				ThumbSize:     thumbType,
			}
			needDownload = append(needDownload, struct {
				doc *tg.Document
				loc tg.InputFileLocationClass
			}{d, loc})
		}
	}
	for _, nd := range needDownload {
		buf, err := t.downloadSmallFile(api, ctx, nd.loc, 64*1024)
		if err != nil || len(buf) == 0 {
			continue
		}
		if entry, ok := thumbByID[nd.doc.ID]; ok {
			entry.ThumbB64 = base64.StdEncoding.EncodeToString(buf)
		}
	}
	result := make([]CustomEmojiThumb, 0, len(thumbByID))
	for _, entry := range thumbByID {
		result = append(result, *entry)
	}
	return result, nil
}

func (t *TelegramCore) GetCustomEmojiFiles(documentIDs []int64) ([]CustomEmojiFile, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	docs, err := api.MessagesGetCustomEmojiDocuments(ctx, documentIDs)
	if err != nil {
		return nil, fmt.Errorf("get custom emoji documents: %w", err)
	}
	var result []CustomEmojiFile
	for _, doc := range docs {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		loc := &tg.InputDocumentFileLocation{
			ID:            d.ID,
			AccessHash:    d.AccessHash,
			FileReference: d.FileReference,
		}
		buf, err := t.downloadSmallFile(api, ctx, loc, 512*1024)
		if err != nil || len(buf) == 0 {
			continue
		}
		usesTextColor := false
		for _, attr := range d.Attributes {
			if ce, ok := attr.(*tg.DocumentAttributeCustomEmoji); ok {
				usesTextColor = ce.TextColor
				break
			}
		}
		result = append(result, CustomEmojiFile{
			DocumentID:    d.ID,
			MimeType:      d.MimeType,
			FileData:      buf,
			UsesTextColor: usesTextColor,
		})
	}
	return result, nil
}

func (t *TelegramCore) GetCustomEmojiSetInfo(documentID int64) (setID int64, accessHash int64, title string, shortName string, count int32, found bool, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, 0, "", "", 0, false, err
	}
	docs, err := api.MessagesGetCustomEmojiDocuments(ctx, []int64{documentID})
	if err != nil {
		return 0, 0, "", "", 0, false, fmt.Errorf("get custom emoji doc: %w", err)
	}
	for _, doc := range docs {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		for _, attr := range d.Attributes {
			sticker, ok := attr.(*tg.DocumentAttributeSticker)
			if !ok {
				continue
			}
			switch ss := sticker.Stickerset.(type) {
			case *tg.InputStickerSetID:
				result, getErr := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
					Stickerset: ss,
				})
				if getErr != nil {
					return ss.ID, ss.AccessHash, "", "", 0, true, nil
				}
				if stickerSet, ok := result.(*tg.MessagesStickerSet); ok {
					return stickerSet.Set.ID, ss.AccessHash, stickerSet.Set.Title, stickerSet.Set.ShortName, int32(stickerSet.Set.Count), true, nil
				}
				return ss.ID, ss.AccessHash, "", "", 0, true, nil
			case *tg.InputStickerSetShortName:
				result, getErr := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
					Stickerset: ss,
				})
				if getErr != nil {
					return 0, 0, "", ss.ShortName, 0, true, nil
				}
				if stickerSet, ok := result.(*tg.MessagesStickerSet); ok {
					return stickerSet.Set.ID, int64(stickerSet.Set.Hash), stickerSet.Set.Title, stickerSet.Set.ShortName, int32(stickerSet.Set.Count), true, nil
				}
				return 0, 0, "", ss.ShortName, 0, true, nil
			}
		}
	}
	return 0, 0, "", "", 0, false, nil
}

func (t *TelegramCore) downloadSmallFile(api *tg.Client, ctx context.Context, loc tg.InputFileLocationClass, maxBytes int) ([]byte, error) {
	var buf bytes.Buffer
	d := downloader.NewDownloader()
	_, err := d.Download(api, loc).Stream(ctx, &buf)
	if err != nil {
		return nil, err
	}
	if buf.Len() > maxBytes {
		return buf.Bytes()[:maxBytes], nil
	}
	return buf.Bytes(), nil
}

func (t *TelegramCore) GetInstalledStickerPacks() ([]StickerPackSummary, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetAllStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get all stickers: %w", err)
	}
	allStickers, ok := result.(*tg.MessagesAllStickers)
	if !ok {
		return nil, nil
	}

	var packs []StickerPackSummary
	for _, s := range allStickers.Sets {
		summary := InstalledSetSummary(&s)

		setResult, err := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
			Stickerset: &tg.InputStickerSetID{ID: s.ID, AccessHash: s.AccessHash},
		})
		if err != nil {
			packs = append(packs, summary)
			continue
		}
		stickerSet, ok := setResult.(*tg.MessagesStickerSet)
		if !ok {
			packs = append(packs, summary)
			continue
		}

		emojiByDocID := make(map[int64]string)
		for _, pack := range stickerSet.Packs {
			for _, docID := range pack.Documents {
				emojiByDocID[docID] = pack.Emoticon
			}
		}

		for _, doc := range stickerSet.Documents {
			d, ok := doc.(*tg.Document)
			if !ok {
				continue
			}
			t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
			si := StickerInfo{
				Emoji:    emojiByDocID[d.ID],
				ThumbB64: extractStrippedThumbB64(d.Thumbs),
				MimeType: d.MimeType,
				FileID:   strconv.FormatInt(d.ID, 10),
			}
			for _, attr := range d.Attributes {
				switch a := attr.(type) {
				case *tg.DocumentAttributeImageSize:
					si.Width = a.W
					si.Height = a.H
				case *tg.DocumentAttributeVideo:
					si.Width = a.W
					si.Height = a.H
				}
			}
			if summary.ThumbB64 == "" && si.ThumbB64 != "" {
				summary.ThumbB64 = si.ThumbB64
			}
			summary.Stickers = append(summary.Stickers, si)
		}
		packs = append(packs, summary)
	}
	return packs, nil
}

func InstalledSetSummary(s *tg.StickerSet) StickerPackSummary {
	summary := StickerPackSummary{
		SetID:      s.ID,
		AccessHash: s.AccessHash,
		Title:      s.Title,
		ShortName:  s.ShortName,
		Count:      s.Count,
		Archived:   s.Archived,
		Masks:      s.Masks,
		Emojis:     s.Emojis,
		Official:   s.Official,
		Installed:  true,
	}
	if thumbs, ok := s.GetThumbs(); ok {
		for _, thumb := range thumbs {
			if stripped, ok := thumb.(*tg.PhotoStrippedSize); ok {
				if jpg := tgStrippedToJPEG(stripped.Bytes); len(jpg) > 0 {
					summary.ThumbB64 = base64.StdEncoding.EncodeToString(jpg)
					break
				}
			}
		}
	}
	return summary
}

func coveredDocs(sc tg.StickerSetCoveredClass) []tg.DocumentClass {
	switch covered := sc.(type) {
	case *tg.StickerSetCovered:
		return []tg.DocumentClass{covered.Cover}
	case *tg.StickerSetMultiCovered:
		return covered.Covers
	case *tg.StickerSetFullCovered:
		return covered.Documents
	}
	return nil
}

func StickerSetCoveredSummary(sc tg.StickerSetCoveredClass) (StickerPackSummary, bool) {
	var set *tg.StickerSet
	switch covered := sc.(type) {
	case *tg.StickerSetCovered:
		set = &covered.Set
	case *tg.StickerSetMultiCovered:
		set = &covered.Set
	case *tg.StickerSetFullCovered:
		set = &covered.Set
	case *tg.StickerSetNoCovered:
		set = &covered.Set
	}
	if set == nil {
		return StickerPackSummary{}, false
	}
	summary := InstalledSetSummary(set)
	summary.Installed = false
	for _, doc := range coveredDocs(sc) {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		if d.MimeType == "video/mp4" {
			summary.Video = true
		}
		si := StickerInfo{
			ThumbB64: extractStrippedThumbB64(d.Thumbs),
			MimeType: d.MimeType,
			FileID:   strconv.FormatInt(d.ID, 10),
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeImageSize:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeVideo:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeSticker:
				si.Emoji = a.Alt
			case *tg.DocumentAttributeAnimated:
				summary.Animated = true
			}
		}
		if summary.ThumbB64 == "" && si.ThumbB64 != "" {
			summary.ThumbB64 = si.ThumbB64
		}
		summary.Stickers = append(summary.Stickers, si)
	}
	return summary, true
}

func MergeArchivedStickerSets(installed, archived []StickerPackSummary) []StickerPackSummary {
	if len(archived) == 0 {
		return installed
	}
	archivedIDs := make(map[int64]bool, len(archived))
	for _, a := range archived {
		archivedIDs[a.SetID] = true
	}
	merged := make([]StickerPackSummary, 0, len(installed)+len(archived))
	for _, p := range installed {
		if archivedIDs[p.SetID] {
			continue
		}
		merged = append(merged, p)
	}
	merged = append(merged, archived...)
	return merged
}

func StickerSetInstallRequest(setID, accessHash int64, archived bool) *tg.MessagesInstallStickerSetRequest {
	return &tg.MessagesInstallStickerSetRequest{
		Stickerset: &tg.InputStickerSetID{ID: setID, AccessHash: accessHash},
		Archived:   archived,
	}
}

func (t *TelegramCore) cacheCoveredDocs(sc tg.StickerSetCoveredClass) {
	for _, doc := range coveredDocs(sc) {
		if d, ok := doc.(*tg.Document); ok {
			t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		}
	}
}

func (t *TelegramCore) GetStickerSetSummaries() ([]StickerPackSummary, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetAllStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get all stickers: %w", err)
	}
	installed := []StickerPackSummary{}
	if all, ok := result.(*tg.MessagesAllStickers); ok {
		for _, s := range all.Sets {
			installed = append(installed, InstalledSetSummary(&s))
		}
	}
	archived := []StickerPackSummary{}
	archResult, err := api.MessagesGetArchivedStickers(ctx, &tg.MessagesGetArchivedStickersRequest{
		OffsetID: 0,
		Limit:    100,
	})
	if err == nil && archResult != nil {
		for _, sc := range archResult.Sets {
			if summary, ok := StickerSetCoveredSummary(sc); ok {
				summary.Archived = true
				archived = append(archived, summary)
			}
		}
	}
	return MergeArchivedStickerSets(installed, archived), nil
}

func (t *TelegramCore) ArchiveStickerSet(setID, accessHash int64, archived bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesInstallStickerSet(ctx, StickerSetInstallRequest(setID, accessHash, archived))
	return err
}

func (t *TelegramCore) GetRecentStickers() ([]StickerInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesGetRecentStickers(ctx, &tg.MessagesGetRecentStickersRequest{})
	if err != nil {
		return nil, fmt.Errorf("get recent stickers: %w", err)
	}
	rs, ok := result.(*tg.MessagesRecentStickers)
	if !ok {
		return nil, nil
	}

	var stickers []StickerInfo
	for _, doc := range rs.Stickers {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		si := StickerInfo{
			ThumbB64: extractStrippedThumbB64(d.Thumbs),
			MimeType: d.MimeType,
			FileID:   strconv.FormatInt(d.ID, 10),
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeImageSize:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeVideo:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeSticker:
				si.Emoji = a.Alt
			}
		}
		stickers = append(stickers, si)
	}
	if len(stickers) > 20 {
		stickers = stickers[:20]
	}
	return stickers, nil
}

func (t *TelegramCore) RemoveRecentSticker(fileID int64, extra string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	accessHash, fileRef := DecodeFileExtra(extra)
	if accessHash == 0 {
		accessHash = t.GetCachedFileHash(fileID)
		fileRef = t.getCachedFileRef(fileID)
	}
	_, err = api.MessagesSaveRecentSticker(ctx, &tg.MessagesSaveRecentStickerRequest{
		ID: &tg.InputDocument{
			ID:            fileID,
			AccessHash:    accessHash,
			FileReference: fileRef,
		},
		Unsave: true,
	})
	return err
}

func (t *TelegramCore) GetStickerFiles(documentIDs []int64) ([]CustomEmojiFile, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	var result []CustomEmojiFile
	for _, docID := range documentIDs {
		accessHash := t.GetCachedFileHash(docID)
		fileRef := t.getCachedFileRef(docID)
		if accessHash == 0 {
			continue
		}
		loc := &tg.InputDocumentFileLocation{
			ID:            docID,
			AccessHash:    accessHash,
			FileReference: fileRef,
		}
		buf, err := t.downloadSmallFile(api, ctx, loc, 512*1024)
		if err != nil || len(buf) == 0 {
			continue
		}
		mimeType := t.getCachedFileMime(docID)
		if mimeType == "" {
			mimeType = detectStickerMime(buf)
		}
		result = append(result, CustomEmojiFile{
			DocumentID: docID,
			MimeType:   mimeType,
			FileData:   buf,
		})
	}
	return result, nil
}

func detectStickerMime(data []byte) string {
	if len(data) >= 2 && data[0] == 0x1f && data[1] == 0x8b {
		return "application/x-tgsticker"
	}
	if len(data) >= 4 && data[0] == 0x1a && data[1] == 0x45 && data[2] == 0xdf && data[3] == 0xa3 {
		return "video/webm"
	}
	return "image/webp"
}

func (t *TelegramCore) GetSavedGifs() ([]GifInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetSavedGifs(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get saved gifs: %w", err)
	}
	sg, ok := result.(*tg.MessagesSavedGifs)
	if !ok {
		return nil, nil
	}
	var gifs []GifInfo
	for _, doc := range sg.Gifs {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		gi := GifInfo{
			ThumbB64: extractStrippedThumbB64(d.Thumbs),
			MimeType: d.MimeType,
			FileID:   strconv.FormatInt(d.ID, 10),
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeImageSize:
				gi.Width = a.W
				gi.Height = a.H
			case *tg.DocumentAttributeVideo:
				gi.Width = a.W
				gi.Height = a.H
			}
		}
		gifs = append(gifs, gi)
	}
	return gifs, nil
}

func (t *TelegramCore) GetGifFiles(documentIDs []int64) ([]CustomEmojiFile, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	var result []CustomEmojiFile
	for _, docID := range documentIDs {
		accessHash := t.GetCachedFileHash(docID)
		fileRef := t.getCachedFileRef(docID)
		if accessHash == 0 && len(fileRef) == 0 {
			continue
		}
		loc := &tg.InputDocumentFileLocation{
			ID:            docID,
			AccessHash:    accessHash,
			FileReference: fileRef,
		}
		buf, err := t.downloadSmallFile(api, ctx, loc, 10*1024*1024)
		if err != nil || len(buf) == 0 {
			continue
		}
		result = append(result, CustomEmojiFile{
			DocumentID: docID,
			MimeType:   "video/mp4",
			FileData:   buf,
		})
	}
	return result, nil
}

func (t *TelegramCore) GetFeaturedStickerPacks() ([]StickerPackSummary, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	installedResult, err := api.MessagesGetAllStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get installed stickers: %w", err)
	}
	installedIDs := make(map[int64]bool)
	if all, ok := installedResult.(*tg.MessagesAllStickers); ok {
		for _, s := range all.Sets {
			installedIDs[s.ID] = true
		}
	}
	result, err := api.MessagesGetFeaturedStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get featured stickers: %w", err)
	}
	fs, ok := result.(*tg.MessagesFeaturedStickers)
	if !ok {
		return nil, nil
	}
	var packs []StickerPackSummary
	for _, setCovered := range fs.Sets {
		summary, ok := StickerSetCoveredSummary(setCovered)
		if !ok {
			continue
		}
		t.cacheCoveredDocs(setCovered)
		summary.Installed = installedIDs[summary.SetID]
		packs = append(packs, summary)
	}
	return packs, nil
}

func (t *TelegramCore) SearchStickerSets(query string) ([]StickerPackSummary, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	installedResult, err := api.MessagesGetAllStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get installed stickers: %w", err)
	}
	installedIDs := make(map[int64]bool)
	if all, ok := installedResult.(*tg.MessagesAllStickers); ok {
		for _, s := range all.Sets {
			installedIDs[s.ID] = true
		}
	}
	result, err := api.MessagesSearchStickerSets(ctx, &tg.MessagesSearchStickerSetsRequest{Q: query})
	if err != nil {
		return nil, fmt.Errorf("search sticker sets: %w", err)
	}
	found, ok := result.(*tg.MessagesFoundStickerSets)
	if !ok {
		return nil, nil
	}
	var packs []StickerPackSummary
	for _, setCovered := range found.Sets {
		summary, ok := StickerSetCoveredSummary(setCovered)
		if !ok {
			continue
		}
		t.cacheCoveredDocs(setCovered)
		summary.Installed = installedIDs[summary.SetID]
		packs = append(packs, summary)
	}
	return packs, nil
}

func (t *TelegramCore) InstallStickerSet(setID, accessHash int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesInstallStickerSet(ctx, StickerSetInstallRequest(setID, accessHash, false))
	return err
}

func (t *TelegramCore) UninstallStickerSet(setID, accessHash int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesUninstallStickerSet(ctx, &tg.InputStickerSetID{ID: setID, AccessHash: accessHash})
	return err
}

func (t *TelegramCore) DeleteFolder(filterID int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	_, err = api.MessagesUpdateDialogFilter(ctx, &tg.MessagesUpdateDialogFilterRequest{
		ID: filterID,
	})
	return err
}

func (t *TelegramCore) AddChatToFolder(chatID string, folderID int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	result, err := api.MessagesGetDialogFilters(ctx)
	if err != nil {
		return fmt.Errorf("get dialog filters: %w", err)
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return fmt.Errorf("resolve peer %s: %w", chatID, err)
	}
	inputPeer, _ := t.toInputPeer(peer)

	for _, f := range result.GetFilters() {
		switch filter := f.(type) {
		case *tg.DialogFilter:
			if filter.ID != folderID {
				continue
			}
			for _, p := range filter.IncludePeers {
				if inputPeerToID(p) == chatID {
					return nil
				}
			}
			filter.IncludePeers = append(filter.IncludePeers, inputPeer)
			filter.SetFlags()
			_, err = api.MessagesUpdateDialogFilter(ctx, &tg.MessagesUpdateDialogFilterRequest{
				ID: folderID, Filter: filter,
			})
			return err
		case *tg.DialogFilterChatlist:
			if filter.ID != folderID {
				continue
			}
			for _, p := range filter.IncludePeers {
				if inputPeerToID(p) == chatID {
					return nil
				}
			}
			filter.IncludePeers = append(filter.IncludePeers, inputPeer)
			filter.SetFlags()
			_, err = api.MessagesUpdateDialogFilter(ctx, &tg.MessagesUpdateDialogFilterRequest{
				ID: folderID, Filter: filter,
			})
			return err
		}
	}
	return fmt.Errorf("folder %d not found", folderID)
}

func (t *TelegramCore) GetTopPeersList(limit int) ([]string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 20
	}
	result, err := api.ContactsGetTopPeers(ctx, &tg.ContactsGetTopPeersRequest{
		Correspondents: true, Limit: limit,
	})
	if err != nil {
		return nil, err
	}
	tp, ok := result.(*tg.ContactsTopPeers)
	if !ok {
		return nil, nil
	}
	t.cacheEntities(tp.Users, tp.Chats)
	var peerIDs []string
	for _, cat := range tp.Categories {
		for _, p := range cat.Peers {
			switch peer := p.Peer.(type) {
			case *tg.PeerUser:
				peerIDs = append(peerIDs, strconv.FormatInt(peer.UserID, 10))
			case *tg.PeerChat:
				peerIDs = append(peerIDs, strconv.FormatInt(peer.ChatID, 10))
			case *tg.PeerChannel:
				peerIDs = append(peerIDs, strconv.FormatInt(peer.ChannelID, 10))
			}
		}
	}
	return peerIDs, nil
}

func (t *TelegramCore) RemoveSavedReactionTag(emoji string, customID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.MessagesUpdateSavedReactionTagRequest{}
	if customID != 0 {
		req.Reaction = &tg.ReactionCustomEmoji{DocumentID: customID}
	} else if emoji != "" {
		req.Reaction = &tg.ReactionEmoji{Emoticon: emoji}
	} else {
		return fmt.Errorf("either emoji or custom_id must be provided")
	}
	_, err = api.MessagesUpdateSavedReactionTag(ctx, req)
	return err
}

func (t *TelegramCore) ResolveUsername(username string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}

	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
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

func (t *TelegramCore) PinDialog(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesToggleDialogPin(t.ctx, &tg.MessagesToggleDialogPinRequest{
		Pinned: true, Peer: &tg.InputDialogPeer{Peer: inputPeer},
	})
	return err
}

func (t *TelegramCore) UnpinDialog(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesToggleDialogPin(t.ctx, &tg.MessagesToggleDialogPinRequest{
		Peer: &tg.InputDialogPeer{Peer: inputPeer},
	})
	return err
}

func (t *TelegramCore) GetPinnedDialogs() ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetPinnedDialogs(ctx, 0)
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, result.Chats)
	return t.extractDialogs(result.Dialogs, result.Messages, result.Chats, result.Users), nil
}

func (t *TelegramCore) MarkDialogUnread(chatID string, unread bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesMarkDialogUnread(t.ctx, &tg.MessagesMarkDialogUnreadRequest{
		Unread: unread, Peer: &tg.InputDialogPeer{Peer: inputPeer},
	})
	return err
}

func (t *TelegramCore) UnpinAllMessages(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesUnpinAllMessages(t.ctx, &tg.MessagesUnpinAllMessagesRequest{Peer: inputPeer})
	return err
}

func (t *TelegramCore) SetTyping(chatID string, action tg.SendMessageActionClass) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesSetTyping(t.ctx, &tg.MessagesSetTypingRequest{Peer: inputPeer, Action: action})
	return err
}

func (t *TelegramCore) GetOnlineCount(chatID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	result, err := t.api.MessagesGetOnlines(t.ctx, inputPeer)
	if err != nil {
		return 0, err
	}
	return result.Onlines, nil
}

func (t *TelegramCore) GetMessagesViewsBatch(chatID string, msgIDs []string) (views, forwards map[string]int, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, nil, err
	}
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, nil, err
	}
	defer unlock()

	ids := make([]int, 0, len(msgIDs))
	idStr := make([]string, 0, len(msgIDs))
	for _, s := range msgIDs {
		id, perr := tgMsgID(s)
		if perr != nil {
			continue
		}
		ids = append(ids, id)
		idStr = append(idStr, s)
	}
	if len(ids) == 0 {
		return map[string]int{}, map[string]int{}, nil
	}
	result, err := api.MessagesGetMessagesViews(ctx, &tg.MessagesGetMessagesViewsRequest{
		Peer: inputPeer, ID: ids, Increment: false,
	})
	if err != nil {
		return nil, nil, err
	}
	views = make(map[string]int, len(ids))
	forwards = make(map[string]int, len(ids))
	for i, v := range result.Views {
		if i >= len(ids) {
			break
		}
		views[idStr[i]] = v.Views
		forwards[idStr[i]] = v.Forwards
	}
	return views, forwards, nil
}

func (t *TelegramCore) GetMessageReadParticipants(chatID string, msgID string) ([]int64, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetMessageReadParticipants(ctx, &tg.MessagesGetMessageReadParticipantsRequest{
		Peer: inputPeer, MsgID: id,
	})
	if err != nil {
		return nil, err
	}
	var userIDs []int64
	for _, rp := range result {
		userIDs = append(userIDs, rp.UserID)
	}
	return userIDs, nil
}

func (t *TelegramCore) GetMessageReadParticipantsDetailedJSON(chatID string, msgID string) ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetMessageReadParticipants(ctx, &tg.MessagesGetMessageReadParticipantsRequest{
		Peer: inputPeer, MsgID: id,
	})
	if err != nil {
		if rpcErr, ok := tgerr.As(err); ok {
			switch rpcErr.Type {
			case "YOUR_PRIVACY_RESTRICTED":
				return nil, fmt.Errorf("privacy:my_hidden")
			case "USER_PRIVACY_RESTRICTED":
				return nil, fmt.Errorf("privacy:his_hidden")
			case "MESSAGE_TOO_OLD":
				return nil, fmt.Errorf("privacy:too_old")
			}
		}
		return nil, err
	}
	var participants []map[string]interface{}
	for _, rp := range result {
		t.peerMu.RLock()
		name := t.userNames[rp.UserID]
		t.peerMu.RUnlock()
		entry := map[string]interface{}{
			"user_id": rp.UserID,
			"date":    rp.Date,
			"name":    name,
		}
		avatarB64 := t.getUserAvatarB64(rp.UserID)
		if avatarB64 != "" {
			entry["avatar_b64"] = avatarB64
		}
		participants = append(participants, entry)
	}
	return participants, nil
}

func (t *TelegramCore) ReadMentions(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesReadMentions(t.ctx, &tg.MessagesReadMentionsRequest{Peer: inputPeer})
	return err
}

func (t *TelegramCore) ReadReactions(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesReadReactions(t.ctx, &tg.MessagesReadReactionsRequest{Peer: inputPeer})
	return err
}

func (t *TelegramCore) TranslateText(chatID string, msgID string, toLang string) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return "", err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return "", err
	}
	result, err := t.api.MessagesTranslateText(t.ctx, &tg.MessagesTranslateTextRequest{
		Peer: inputPeer, ID: []int{id}, ToLang: toLang,
	})
	if err != nil {
		return "", err
	}
	if len(result.Result) > 0 {
		return result.Result[0].Text, nil
	}
	return "", nil
}

func (t *TelegramCore) TranslateFreeText(text, toLang string) (string, error) {
	result, err := t.api.MessagesTranslateText(t.ctx, &tg.MessagesTranslateTextRequest{
		Text:   []tg.TextWithEntities{{Text: text}},
		ToLang: toLang,
	})
	if err != nil {
		return "", err
	}
	if len(result.Result) > 0 {
		return result.Result[0].Text, nil
	}
	return "", nil
}

func (t *TelegramCore) ReportMessage(chatID string, msgIDs []int, option []byte, message string) (*ReportResult, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	result, err := t.api.MessagesReport(t.ctx, &tg.MessagesReportRequest{
		Peer: inputPeer, ID: msgIDs, Option: option, Message: message,
	})
	if err != nil {
		if rpcErr, ok := tgerr.As(err); ok && rpcErr.Type == "MESSAGE_ID_REQUIRED" {
			return &ReportResult{Type: "message_id_required"}, nil
		}
		return nil, err
	}
	switch r := result.(type) {
	case *tg.ReportResultChooseOption:
		opts := make([]ReportOption, len(r.Options))
		for i, o := range r.Options {
			opts[i] = ReportOption{Text: o.Text, Option: o.Option}
		}
		return &ReportResult{Type: "choose_option", Title: r.Title, Options: opts}, nil
	case *tg.ReportResultAddComment:
		return &ReportResult{Type: "add_comment", CommentOptional: r.Optional, CommentOption: r.Option}, nil
	case *tg.ReportResultReported:
		return &ReportResult{Type: "reported"}, nil
	}
	return &ReportResult{Type: "reported"}, nil
}

func (t *TelegramCore) ReportPeer(chatID, reason, message string) (bool, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return false, err
	}
	defer unlock()
	var tlReason tg.ReportReasonClass
	switch reason {
	case "spam":
		tlReason = &tg.InputReportReasonSpam{}
	case "fake":
		tlReason = &tg.InputReportReasonFake{}
	case "violence":
		tlReason = &tg.InputReportReasonViolence{}
	case "child_abuse":
		tlReason = &tg.InputReportReasonChildAbuse{}
	case "pornography":
		tlReason = &tg.InputReportReasonPornography{}
	case "copyright":
		tlReason = &tg.InputReportReasonCopyright{}
	case "illegal_drugs":
		tlReason = &tg.InputReportReasonIllegalDrugs{}
	case "personal_details":
		tlReason = &tg.InputReportReasonPersonalDetails{}
	default:
		tlReason = &tg.InputReportReasonOther{}
	}
	return t.api.AccountReportPeer(t.ctx, &tg.AccountReportPeerRequest{
		Peer:    inputPeer,
		Reason:  tlReason,
		Message: message,
	})
}

func (t *TelegramCore) ReportReaction(chatID string, msgID int, participantID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	chatPeer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	chatInput, err := t.toInputPeer(chatPeer)
	if err != nil {
		return err
	}
	reactPeer, err := t.resolvePeer(participantID)
	if err != nil {
		return err
	}
	reactInput, err := t.toInputPeer(reactPeer)
	if err != nil {
		return err
	}
	_, err = api.MessagesReportReaction(ctx, &tg.MessagesReportReactionRequest{
		Peer: chatInput, ID: msgID, ReactionPeer: reactInput,
	})
	return err
}

func (t *TelegramCore) GetWebPagePreview(url string) (string, error) {
	r, err := t.GetWebPagePreviewFull(url)
	if err != nil {
		return "", err
	}
	if r != nil {
		return r.Title, nil
	}
	return "", nil
}

func (t *TelegramCore) GetWebPagePreviewFull(url string) (*WebPagePreviewResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetWebPagePreview(ctx, &tg.MessagesGetWebPagePreviewRequest{Message: url})
	if err != nil {
		return nil, err
	}
	if result.Media != nil {
		if mw, ok := result.Media.(*tg.MessageMediaWebPage); ok {
			if wp, ok := mw.Webpage.(*tg.WebPage); ok {
				r := &WebPagePreviewResult{
					URL:           wp.URL,
					SiteName:      wp.SiteName,
					Title:         wp.Title,
					Description:   wp.Description,
					HasLargeMedia: wp.HasLargeMedia,
				}
				if t, ok := wp.GetType(); ok {
					r.Type = t
				}
				if a, ok := wp.GetAuthor(); ok {
					r.Author = a
				}
				if e, ok := wp.GetEmbedURL(); ok {
					r.EmbedURL = e
				}
				if wp.Photo != nil {
					r.HasPhoto = true
					if photo, ok := wp.Photo.(*tg.Photo); ok {
						r.ThumbB64 = extractStrippedThumbB64(photo.Sizes)
					}
				}
				if _, ok := wp.GetDocument(); ok {
					r.HasDocument = true
				}
				if _, ok := wp.GetCachedPage(); ok {
					r.HasIV = true
				}
				if attrs, ok := wp.GetAttributes(); ok {
					for _, attr := range attrs {
						if _, ok := attr.(*tg.WebPageAttributeUniqueStarGift); ok {
							r.HasUniqueGift = true
							break
						}
					}
				}
				return r, nil
			}
			if pending, ok := mw.Webpage.(*tg.WebPagePending); ok {
				return &WebPagePreviewResult{
					URL:         pending.URL,
					PendingTill: int64(pending.Date),
				}, nil
			}
		}
	}
	return nil, nil
}

func (t *TelegramCore) GetInstantViewPage(url string) ([]byte, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetWebPage(ctx, &tg.MessagesGetWebPageRequest{
		URL:  url,
		Hash: 0,
	})
	if err != nil {
		return nil, err
	}
	wp, ok := result.Webpage.(*tg.WebPage)
	if !ok {
		return nil, fmt.Errorf("no web page data")
	}
	page, ok := wp.GetCachedPage()
	if !ok {
		return nil, fmt.Errorf("no instant view for this page")
	}

	photoMap := make(map[int64]ivPhotoInfo)
	for _, p := range page.Photos {
		if photo, ok := p.(*tg.Photo); ok {
			info := ivPhotoInfo{
				ThumbB64: extractStrippedThumbB64(photo.Sizes),
			}
			info.Extra = encodeFileExtra(photo.AccessHash, photo.FileReference)
			t.cacheFileInfo(photo.ID, photo.AccessHash, photo.FileReference)
			for _, sz := range photo.Sizes {
				switch s := sz.(type) {
				case *tg.PhotoSizeProgressive:
					if s.W > info.Width {
						info.Width = s.W
						info.Height = s.H
					}
				case *tg.PhotoSize:
					if s.W > info.Width {
						info.Width = s.W
						info.Height = s.H
					}
				}
			}
			photoMap[photo.ID] = info
		}
	}

	docMap := make(map[int64]*tg.Document)
	for _, d := range page.Documents {
		if doc, ok := d.(*tg.Document); ok {
			docMap[doc.ID] = doc
			t.cacheFileInfo(doc.ID, doc.AccessHash, doc.FileReference)
		}
	}

	blocks := make([]map[string]interface{}, 0, len(page.Blocks))
	for _, b := range page.Blocks {
		if m := ivBlockToMap(b, photoMap, docMap); m != nil {
			blocks = append(blocks, m)
		}
	}

	out := map[string]interface{}{
		"url":       page.URL,
		"blocks":    blocks,
		"rtl":       page.Rtl,
		"v2":        page.V2,
		"title":     wp.Title,
		"site_name": wp.SiteName,
	}
	return json.Marshal(out)
}

func isKnownIVDomain(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	host := strings.ToLower(u.Hostname())
	for _, d := range []string{
		"telegra.ph", "graph.org",
	} {
		if host == d || strings.HasSuffix(host, "."+d) {
			return true
		}
	}
	return false
}

func ivIgnoreType(t string) bool {
	switch t {
	case "telegram_message", "telegram_channel", "telegram_megagroup", "telegram_chat",
		"telegram_user", "telegram_botapp", "telegram_channel_request",
		"telegram_megagroup_request", "telegram_chat_request", "telegram_channel_boost",
		"telegram_megagroup_boost", "telegram_giftcode", "telegram_stickerset",
		"telegram_theme", "telegram_background", "telegram_voicechat",
		"telegram_livestream", "telegram_story", "telegram_newbot":
		return true
	}
	return false
}

type ivPhotoInfo struct {
	ThumbB64 string
	Extra    string
	Width    int
	Height   int
}

func ivRichTextToMap(rt tg.RichTextClass) interface{} {
	if rt == nil {
		return nil
	}
	switch v := rt.(type) {
	case *tg.TextPlain:
		return map[string]interface{}{"t": "plain", "v": v.Text}
	case *tg.TextBold:
		return map[string]interface{}{"t": "bold", "c": ivRichTextToMap(v.Text)}
	case *tg.TextItalic:
		return map[string]interface{}{"t": "italic", "c": ivRichTextToMap(v.Text)}
	case *tg.TextUnderline:
		return map[string]interface{}{"t": "underline", "c": ivRichTextToMap(v.Text)}
	case *tg.TextStrike:
		return map[string]interface{}{"t": "strike", "c": ivRichTextToMap(v.Text)}
	case *tg.TextFixed:
		return map[string]interface{}{"t": "fixed", "c": ivRichTextToMap(v.Text)}
	case *tg.TextURL:
		return map[string]interface{}{"t": "url", "c": ivRichTextToMap(v.Text), "href": v.URL}
	case *tg.TextEmail:
		return map[string]interface{}{"t": "email", "c": ivRichTextToMap(v.Text), "addr": v.Email}
	case *tg.TextConcat:
		parts := make([]interface{}, 0, len(v.Texts))
		for _, t := range v.Texts {
			if m := ivRichTextToMap(t); m != nil {
				parts = append(parts, m)
			}
		}
		return map[string]interface{}{"t": "concat", "parts": parts}
	case *tg.TextSubscript:
		return map[string]interface{}{"t": "sub", "c": ivRichTextToMap(v.Text)}
	case *tg.TextSuperscript:
		return map[string]interface{}{"t": "sup", "c": ivRichTextToMap(v.Text)}
	case *tg.TextMarked:
		return map[string]interface{}{"t": "marked", "c": ivRichTextToMap(v.Text)}
	case *tg.TextPhone:
		return map[string]interface{}{"t": "phone", "c": ivRichTextToMap(v.Text), "phone": v.Phone}
	case *tg.TextAnchor:
		return map[string]interface{}{"t": "anchor", "c": ivRichTextToMap(v.Text), "name": v.Name}
	case *tg.TextImage:
		return map[string]interface{}{"t": "image", "doc_id": v.DocumentID, "w": v.W, "h": v.H}
	case *tg.TextEmpty:
		return nil
	}
	return nil
}

func ivCaptionToMap(c tg.PageCaption) interface{} {
	text := ivRichTextToMap(c.Text)
	credit := ivRichTextToMap(c.Credit)
	if text == nil && credit == nil {
		return nil
	}
	return map[string]interface{}{"text": text, "credit": credit}
}

func ivBlockToMap(b tg.PageBlockClass, photoMap map[int64]ivPhotoInfo, docMap map[int64]*tg.Document) map[string]interface{} {
	switch v := b.(type) {
	case *tg.PageBlockTitle:
		return map[string]interface{}{"type": "title", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockSubtitle:
		return map[string]interface{}{"type": "subtitle", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockAuthorDate:
		m := map[string]interface{}{"type": "author_date", "author": ivRichTextToMap(v.Author)}
		if v.PublishedDate > 0 {
			m["date"] = v.PublishedDate
		}
		return m
	case *tg.PageBlockHeader:
		return map[string]interface{}{"type": "header", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockSubheader:
		return map[string]interface{}{"type": "subheader", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockParagraph:
		return map[string]interface{}{"type": "paragraph", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockPreformatted:
		m := map[string]interface{}{"type": "preformatted", "text": ivRichTextToMap(v.Text)}
		if v.Language != "" {
			m["lang"] = v.Language
		}
		return m
	case *tg.PageBlockFooter:
		return map[string]interface{}{"type": "footer", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockDivider:
		return map[string]interface{}{"type": "divider"}
	case *tg.PageBlockAnchor:
		return map[string]interface{}{"type": "anchor", "name": v.Name}
	case *tg.PageBlockList:
		items := make([]interface{}, 0, len(v.Items))
		for _, item := range v.Items {
			switch li := item.(type) {
			case *tg.PageListItemText:
				items = append(items, map[string]interface{}{"text": ivRichTextToMap(li.Text)})
			case *tg.PageListItemBlocks:
				blocks := make([]interface{}, 0, len(li.Blocks))
				for _, ib := range li.Blocks {
					if m := ivBlockToMap(ib, photoMap, docMap); m != nil {
						blocks = append(blocks, m)
					}
				}
				items = append(items, map[string]interface{}{"blocks": blocks})
			}
		}
		return map[string]interface{}{"type": "list", "items": items}
	case *tg.PageBlockBlockquote:
		return map[string]interface{}{"type": "blockquote", "text": ivRichTextToMap(v.Text), "caption": ivRichTextToMap(v.Caption)}
	case *tg.PageBlockPullquote:
		return map[string]interface{}{"type": "pullquote", "text": ivRichTextToMap(v.Text), "caption": ivRichTextToMap(v.Caption)}
	case *tg.PageBlockPhoto:
		m := map[string]interface{}{"type": "photo", "photo_id": v.PhotoID, "caption": ivCaptionToMap(v.Caption)}
		if info, ok := photoMap[v.PhotoID]; ok {
			m["thumb"] = info.ThumbB64
			m["extra"] = info.Extra
			m["w"] = info.Width
			m["h"] = info.Height
		}
		if u, ok := v.GetURL(); ok {
			m["url"] = u
		}
		return m
	case *tg.PageBlockVideo:
		m := map[string]interface{}{"type": "video", "video_id": v.VideoID, "autoplay": v.Autoplay, "loop": v.Loop, "caption": ivCaptionToMap(v.Caption)}
		if doc, ok := docMap[v.VideoID]; ok {
			m["extra"] = encodeFileExtra(doc.AccessHash, doc.FileReference)
			m["mime"] = doc.MimeType
			m["size"] = doc.Size
			m["thumb"] = extractStrippedThumbB64(doc.Thumbs)
			for _, attr := range doc.Attributes {
				if a, ok := attr.(*tg.DocumentAttributeVideo); ok {
					m["duration"] = a.Duration
					m["w"] = a.W
					m["h"] = a.H
				}
				if a, ok := attr.(*tg.DocumentAttributeFilename); ok {
					m["filename"] = a.FileName
				}
			}
		}
		return m
	case *tg.PageBlockCover:
		if inner := ivBlockToMap(v.Cover, photoMap, docMap); inner != nil {
			return map[string]interface{}{"type": "cover", "cover": inner}
		}
		return nil
	case *tg.PageBlockEmbed:
		m := map[string]interface{}{"type": "embed", "w": v.W, "h": v.H, "caption": ivCaptionToMap(v.Caption)}
		if u, ok := v.GetURL(); ok {
			m["url"] = u
		}
		if h, ok := v.GetHTML(); ok {
			m["html"] = h
		}
		return m
	case *tg.PageBlockEmbedPost:
		m := map[string]interface{}{"type": "embed_post", "url": v.URL, "author": v.Author, "date": v.Date, "caption": ivCaptionToMap(v.Caption)}
		blocks := make([]interface{}, 0, len(v.Blocks))
		for _, ib := range v.Blocks {
			if bm := ivBlockToMap(ib, photoMap, docMap); bm != nil {
				blocks = append(blocks, bm)
			}
		}
		m["blocks"] = blocks
		return m
	case *tg.PageBlockCollage:
		items := make([]interface{}, 0, len(v.Items))
		for _, ib := range v.Items {
			if bm := ivBlockToMap(ib, photoMap, docMap); bm != nil {
				items = append(items, bm)
			}
		}
		return map[string]interface{}{"type": "collage", "items": items, "caption": ivCaptionToMap(v.Caption)}
	case *tg.PageBlockSlideshow:
		items := make([]interface{}, 0, len(v.Items))
		for _, ib := range v.Items {
			if bm := ivBlockToMap(ib, photoMap, docMap); bm != nil {
				items = append(items, bm)
			}
		}
		return map[string]interface{}{"type": "slideshow", "items": items, "caption": ivCaptionToMap(v.Caption)}
	case *tg.PageBlockDetails:
		blocks := make([]interface{}, 0, len(v.Blocks))
		for _, ib := range v.Blocks {
			if bm := ivBlockToMap(ib, photoMap, docMap); bm != nil {
				blocks = append(blocks, bm)
			}
		}
		return map[string]interface{}{"type": "details", "title": ivRichTextToMap(v.Title), "blocks": blocks, "open": v.Open}
	case *tg.PageBlockRelatedArticles:
		articles := make([]interface{}, 0, len(v.Articles))
		for _, a := range v.Articles {
			am := map[string]interface{}{"url": a.URL}
			if t, ok := a.GetTitle(); ok {
				am["title"] = t
			}
			if d, ok := a.GetDescription(); ok {
				am["desc"] = d
			}
			if a, ok := a.GetAuthor(); ok {
				am["author"] = a
			}
			articles = append(articles, am)
		}
		return map[string]interface{}{"type": "related", "title": ivRichTextToMap(v.Title), "articles": articles}
	case *tg.PageBlockKicker:
		return map[string]interface{}{"type": "kicker", "text": ivRichTextToMap(v.Text)}
	case *tg.PageBlockTable:
		rows := make([]interface{}, 0, len(v.Rows))
		for _, row := range v.Rows {
			cells := make([]interface{}, 0, len(row.Cells))
			for _, cell := range row.Cells {
				cm := map[string]interface{}{"text": ivRichTextToMap(cell.Text), "header": cell.Header}
				if cs, ok := cell.GetColspan(); ok {
					cm["colspan"] = cs
				}
				if rs, ok := cell.GetRowspan(); ok {
					cm["rowspan"] = rs
				}
				if cell.AlignCenter {
					cm["align_center"] = true
				} else if cell.AlignRight {
					cm["align_right"] = true
				}
				if cell.ValignMiddle {
					cm["valign_middle"] = true
				} else if cell.ValignBottom {
					cm["valign_bottom"] = true
				}
				cells = append(cells, cm)
			}
			rows = append(rows, cells)
		}
		return map[string]interface{}{"type": "table", "title": ivRichTextToMap(v.Title), "rows": rows, "bordered": v.Bordered, "striped": v.Striped}
	case *tg.PageBlockOrderedList:
		items := make([]interface{}, 0, len(v.Items))
		for _, item := range v.Items {
			switch li := item.(type) {
			case *tg.PageListOrderedItemText:
				items = append(items, map[string]interface{}{"num": li.Num, "text": ivRichTextToMap(li.Text)})
			case *tg.PageListOrderedItemBlocks:
				blocks := make([]interface{}, 0, len(li.Blocks))
				for _, ib := range li.Blocks {
					if m := ivBlockToMap(ib, photoMap, docMap); m != nil {
						blocks = append(blocks, m)
					}
				}
				items = append(items, map[string]interface{}{"num": li.Num, "blocks": blocks})
			}
		}
		return map[string]interface{}{"type": "ordered_list", "items": items}
	case *tg.PageBlockChannel:
		m := map[string]interface{}{"type": "channel"}
		if ch, ok := v.Channel.(*tg.Channel); ok {
			m["title"] = ch.Title
			if u, ok := ch.GetUsername(); ok {
				m["username"] = u
			}
			m["id"] = ch.ID
		}
		return m
	case *tg.PageBlockAudio:
		m := map[string]interface{}{"type": "audio", "audio_id": v.AudioID, "caption": ivCaptionToMap(v.Caption)}
		if doc, ok := docMap[v.AudioID]; ok {
			m["extra"] = encodeFileExtra(doc.AccessHash, doc.FileReference)
			m["mime"] = doc.MimeType
			m["size"] = doc.Size
			for _, attr := range doc.Attributes {
				if a, ok := attr.(*tg.DocumentAttributeAudio); ok {
					m["duration"] = a.Duration
					if t, ok := a.GetTitle(); ok {
						m["title"] = t
					}
					if p, ok := a.GetPerformer(); ok {
						m["performer"] = p
					}
				}
				if a, ok := attr.(*tg.DocumentAttributeFilename); ok {
					m["filename"] = a.FileName
				}
			}
		}
		return m
	case *tg.PageBlockMap:
		geo := v.Geo
		m := map[string]interface{}{"type": "map", "zoom": v.Zoom, "w": v.W, "h": v.H, "caption": ivCaptionToMap(v.Caption)}
		if pt, ok := geo.(*tg.GeoPoint); ok {
			m["lat"] = pt.Lat
			m["lng"] = pt.Long
			m["access"] = pt.AccessHash
		}
		return m
	}
	return nil
}

func (t *TelegramCore) DownloadIVPhoto(photoID int64, extra string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return "", ErrAuth
	}
	dir, err := utils.PrivateCacheDir("telegram-iv")
	if err != nil {
		return "", err
	}
	dest := filepath.Join(dir, fmt.Sprintf("iv_photo_%d.jpg", photoID))
	if _, err := os.Stat(dest); err == nil {
		return dest, nil
	}
	ref := FileRef{ID: strconv.FormatInt(photoID, 10), MimeType: "image/jpeg", Extra: extra}
	if err := t.DownloadFile(ref, dest, nil); err != nil {
		return "", fmt.Errorf("download IV photo %d: %w", photoID, err)
	}
	return dest, nil
}

func (t *TelegramCore) DownloadIVDocument(docID int64, extra, mime string) (string, error) {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return "", ErrAuth
	}
	ext := ".bin"
	switch {
	case strings.HasPrefix(mime, "video/mp4"), strings.HasPrefix(mime, "video/"):
		ext = ".mp4"
	case strings.HasPrefix(mime, "audio/mpeg"):
		ext = ".mp3"
	case strings.HasPrefix(mime, "audio/ogg"):
		ext = ".ogg"
	case strings.HasPrefix(mime, "audio/"):
		ext = ".mp3"
	}
	dir, err := utils.PrivateCacheDir("telegram-iv")
	if err != nil {
		return "", err
	}
	dest := filepath.Join(dir, fmt.Sprintf("iv_doc_%d%s", docID, ext))
	if _, err := os.Stat(dest); err == nil {
		return dest, nil
	}
	ref := FileRef{ID: strconv.FormatInt(docID, 10), MimeType: mime, Extra: extra}
	if err := t.DownloadFile(ref, dest, nil); err != nil {
		return "", fmt.Errorf("download IV document %d: %w", docID, err)
	}
	return dest, nil
}

func (t *TelegramCore) SetHistoryTTL(chatID string, period int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesSetHistoryTTL(t.ctx, &tg.MessagesSetHistoryTTLRequest{Peer: inputPeer, Period: period})
	return err
}

func (t *TelegramCore) GetAllDrafts() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesGetAllDrafts(ctx)
	return err
}

func (t *TelegramCore) SendPoll(chatID string, question string, answers []string) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	var pollAnswers []tg.PollAnswerClass
	for i, a := range answers {
		pollAnswers = append(pollAnswers, &tg.PollAnswer{Text: tg.TextWithEntities{Text: a}, Option: []byte{byte(i)}})
	}
	result, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(), Message: "",
		Media: &tg.InputMediaPoll{Poll: tg.Poll{ID: time.Now().UnixNano(), Question: tg.TextWithEntities{Text: question}, Answers: pollAnswers}},
	})
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) VoteInPoll(chatID string, msgID string, optionIdx int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	_, err = t.api.MessagesSendVote(t.ctx, &tg.MessagesSendVoteRequest{
		Peer: inputPeer, MsgID: id, Options: [][]byte{{byte(optionIdx)}},
	})
	return err
}

func (t *TelegramCore) VoteInPollMulti(chatID string, msgID string, optionIndices []int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	options := make([][]byte, len(optionIndices))
	for i, idx := range optionIndices {
		options[i] = []byte{byte(idx)}
	}
	_, err = t.api.MessagesSendVote(t.ctx, &tg.MessagesSendVoteRequest{
		Peer: inputPeer, MsgID: id, Options: options,
	})
	return err
}

func (t *TelegramCore) RetractPollVote(chatID string, msgID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	_, err = t.api.MessagesSendVote(t.ctx, &tg.MessagesSendVoteRequest{
		Peer: inputPeer, MsgID: id, Options: [][]byte{},
	})
	return err
}

func (t *TelegramCore) StopPoll(chatID string, msgID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	msgs, err := t.api.MessagesGetMessages(t.ctx, []tg.InputMessageClass{&tg.InputMessageID{ID: id}})
	if err != nil {
		return err
	}
	var poll *tg.Poll
	switch m := msgs.(type) {
	case *tg.MessagesMessages:
		for _, msg := range m.Messages {
			if pmsg, ok := msg.(*tg.Message); ok {
				if mp, ok := pmsg.Media.(*tg.MessageMediaPoll); ok {
					poll = &mp.Poll
				}
			}
		}
	case *tg.MessagesMessagesSlice:
		for _, msg := range m.Messages {
			if pmsg, ok := msg.(*tg.Message); ok {
				if mp, ok := pmsg.Media.(*tg.MessageMediaPoll); ok {
					poll = &mp.Poll
				}
			}
		}
	case *tg.MessagesChannelMessages:
		for _, msg := range m.Messages {
			if pmsg, ok := msg.(*tg.Message); ok {
				if mp, ok := pmsg.Media.(*tg.MessageMediaPoll); ok {
					poll = &mp.Poll
				}
			}
		}
	}
	if poll == nil {
		return fmt.Errorf("message is not a poll")
	}
	poll.SetClosed(true)
	_, err = t.api.MessagesEditMessage(t.ctx, &tg.MessagesEditMessageRequest{
		Peer:  inputPeer,
		ID:    id,
		Media: &tg.InputMediaPoll{Poll: *poll},
	})
	return err
}

func (t *TelegramCore) ExportChatInvite(chatID string) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return "", err
	}
	defer unlock()
	result, err := t.api.MessagesExportChatInvite(t.ctx, &tg.MessagesExportChatInviteRequest{Peer: inputPeer})
	if err != nil {
		return "", err
	}
	if inv, ok := result.(*tg.ChatInviteExported); ok {
		return inv.Link, nil
	}
	return "", nil
}

func (t *TelegramCore) GetFullChannel(chatID string) (*Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.ChannelsGetFullChannel(ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, result.Chats)
	d := &Dialog{Platform: tgPlatform, ID: chatID}
	if fc, ok := result.FullChat.(*tg.ChannelFull); ok {
		d.MemberCount = fc.ParticipantsCount
		if fc.LinkedChatID != 0 {
			d.LinkedChatId = strconv.Itoa(int(fc.LinkedChatID))
		}
	}
	for _, c := range result.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			d.Title = cc.Title
			if cc.Broadcast {
				d.Type = ChatTypeChannel
			} else {
				d.Type = ChatTypeGroup
			}
		}
	}
	return d, nil
}

type ChatPermissionFlags struct {
	SlowmodeSeconds       int      `json:"slowmode_seconds"`
	JoinToSend            bool     `json:"join_to_send"`
	NoForwards            bool     `json:"no_forwards"`
	JoinRequest           bool     `json:"join_request"`
	IsForum               bool     `json:"is_forum"`
	Antispam              bool     `json:"antispam"`
	Signatures            bool     `json:"signatures"`
	SignatureProfiles     bool     `json:"signature_profiles"`
	PreHistoryHidden      bool     `json:"pre_history_hidden"`
	NoTranslations        bool     `json:"no_translations"`
	HasUsername           bool     `json:"has_username"`
	LinkedChatID          string   `json:"linked_chat_id"`
	PendingRequestsCount  int      `json:"pending_requests_count"`
	BoostLevel            int      `json:"boost_level"`
	IsMegagroup           bool     `json:"is_megagroup"`
	IsBroadcast           bool     `json:"is_broadcast"`
	IsGigagroup           bool     `json:"is_gigagroup"`
	AmCreator             bool     `json:"am_creator"`
	HasAdminRights        bool     `json:"has_admin_rights"`
	CanViewStats          bool     `json:"can_view_stats"`
	AdminCanChangeInfo    bool     `json:"admin_can_change_info"`
	CanAddAdmins          bool     `json:"can_add_admins"`
	CanBanUsers           bool     `json:"can_ban_users"`
	CanInviteUsers        bool     `json:"can_invite_users"`
	CanViewParticipants   bool     `json:"can_view_participants"`
	ParticipantsHidden    bool     `json:"participants_hidden"`
	CanSetStickers        bool     `json:"can_set_stickers"`
	AutoTranslateMinLevel int      `json:"auto_translate_min_level"`
	MigratedFromChatID    string   `json:"migrated_from_chat_id"`
	DirectMessagesEnabled bool     `json:"direct_messages_enabled"`
	DirectMessagesStars   int64    `json:"direct_messages_stars"`
	StarRefJoinAllowed    bool     `json:"starref_join_allowed"`
	AdminCanPost          bool     `json:"admin_can_post"`
	ReactionsUniqMax      int      `json:"reactions_uniq_max"`
	ReactionsMaxCount     int      `json:"reactions_max_count"`
	PaidReactionsEnabled  bool     `json:"paid_reactions_enabled"`
	ForumTabs             bool     `json:"forum_tabs"`
	HasLocation           bool     `json:"has_location"`
	ReactionsMode         string   `json:"reactions_mode"`
	ReactionsAllowed      []string `json:"reactions_allowed"`
	AntispamGroupSizeMin  int      `json:"antispam_group_size_min"`
	MemberCount           int      `json:"member_count"`
}

type DefaultBannedRights struct {
	SendPlain        bool  `json:"send_plain"`
	SendPhotos       bool  `json:"send_photos"`
	SendVideos       bool  `json:"send_videos"`
	SendRoundvideos  bool  `json:"send_roundvideos"`
	SendAudios       bool  `json:"send_audios"`
	SendVoices       bool  `json:"send_voices"`
	SendDocs         bool  `json:"send_docs"`
	SendStickers     bool  `json:"send_stickers"`
	EmbedLinks       bool  `json:"embed_links"`
	SendPolls        bool  `json:"send_polls"`
	InviteUsers      bool  `json:"invite_users"`
	ManageTopics     bool  `json:"manage_topics"`
	PinMessages      bool  `json:"pin_messages"`
	EditRank         bool  `json:"edit_rank"`
	ChangeInfo       bool  `json:"change_info"`
	SlowmodeSeconds  int   `json:"slowmode_seconds"`
	BoostsUnrestrict int   `json:"boosts_unrestrict"`
	ChargeStars      int64 `json:"charge_stars"`
}

func computeWriteRestriction(personalRights *tg.ChatBannedRights, defaultRights tg.ChatBannedRights) (int, string) {
	if personalRights != nil && personalRights.ViewMessages {
		return 1, "Sorry, this group is not accessible."
	}
	if personalRights != nil && !personalRights.Zero() {
		until := personalRights.UntilDate
		isTimed := until > 0 && until < 2145916800
		if personalRights.SendPlain {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending messages until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group have restricted your ability to send messages."
		}
		if personalRights.SendPhotos {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending photos here until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group restricted you from sending photos here."
		}
		if personalRights.SendVideos {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending videos here until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group restricted you from sending videos here."
		}
		if personalRights.SendAudios {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending music here until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group restricted you from sending music here."
		}
		if personalRights.SendDocs {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending files here until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group restricted you from sending files here."
		}
		if personalRights.SendVoices {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending voice messages here until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group restricted you from sending voice messages here."
		}
		if personalRights.SendRoundvideos {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted you from sending video messages here until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group restricted you from sending video messages here."
		}
		if personalRights.SendStickers {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted your ability to send stickers until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group have restricted your ability to send stickers."
		}
		if personalRights.SendGifs {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted your ability to send GIFs until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group have restricted your ability to send GIFs."
		}
		if personalRights.SendInline || personalRights.SendGames {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted your ability to send inline content until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group have restricted your ability to send inline content."
		}
		if personalRights.SendPolls {
			if isTimed {
				return 1, fmt.Sprintf("The admins of this group have restricted your ability to send polls until %s.", formatRestrictionDate(until))
			}
			return 1, "The admins of this group have restricted your ability to send polls."
		}
	}

	if defaultRights.SendPlain {
		return 1, "Sending messages is not allowed in this group."
	}
	if defaultRights.SendPhotos {
		return 1, "Sending photos isn't allowed in this group."
	}
	if defaultRights.SendVideos {
		return 1, "Sending videos isn't allowed in this group."
	}
	if defaultRights.SendAudios {
		return 1, "Sending music isn't allowed in this group."
	}
	if defaultRights.SendDocs {
		return 1, "Sending files isn't allowed in this group."
	}
	if defaultRights.SendVoices {
		return 1, "Sending voice messages isn't allowed in this group."
	}
	if defaultRights.SendRoundvideos {
		return 1, "Sending video messages isn't allowed in this group."
	}
	if defaultRights.SendStickers {
		return 1, "Stickers aren't allowed in this group."
	}
	if defaultRights.SendGifs {
		return 1, "Sending GIFs isn't allowed in this group."
	}
	if defaultRights.SendInline || defaultRights.SendGames {
		return 1, "Sending inline content isn't allowed in this group."
	}
	if defaultRights.SendPolls {
		return 1, "Sorry, sending polls is not allowed in this group."
	}
	return 0, ""
}

func formatRestrictionDate(unixTime int) string {
	t := time.Unix(int64(unixTime), 0)
	return t.Format("Jan 2, 2006") + ", " + t.Format("3:04 PM")
}

func (t *TelegramCore) GetDefaultBannedRights(chatID string) (*DefaultBannedRights, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	rights := &DefaultBannedRights{}

	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		result, err := api.ChannelsGetFullChannel(ctx, &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash})
		if err != nil {
			return nil, err
		}
		t.cacheEntities(result.Users, result.Chats)
		if fc, ok := result.FullChat.(*tg.ChannelFull); ok {
			rights.SlowmodeSeconds = fc.SlowmodeSeconds
			if bu, ok := fc.GetBoostsUnrestrict(); ok {
				rights.BoostsUnrestrict = bu
			}
			if stars, ok := fc.GetSendPaidMessagesStars(); ok {
				rights.ChargeStars = stars
			}
		}
		for _, c := range result.Chats {
			if cc, ok := c.(*tg.Channel); ok && cc.ID == p.ChannelID {
				if cc.DefaultBannedRights.ViewMessages {
					break
				}
				br := cc.DefaultBannedRights
				rights.SendPlain = br.SendPlain
				rights.SendPhotos = br.SendPhotos
				rights.SendVideos = br.SendVideos
				rights.SendRoundvideos = br.SendRoundvideos
				rights.SendAudios = br.SendAudios
				rights.SendVoices = br.SendVoices
				rights.SendDocs = br.SendDocs
				rights.SendStickers = br.SendStickers
				rights.EmbedLinks = br.EmbedLinks
				rights.SendPolls = br.SendPolls
				rights.InviteUsers = br.InviteUsers
				rights.ManageTopics = br.ManageTopics
				rights.PinMessages = br.PinMessages
				rights.EditRank = br.EditRank
				rights.ChangeInfo = br.ChangeInfo
				break
			}
		}
	case *tg.PeerChat:
		result, err := api.MessagesGetFullChat(ctx, p.ChatID)
		if err != nil {
			return nil, err
		}
		t.cacheEntities(result.Users, result.Chats)
		for _, c := range result.Chats {
			if cc, ok := c.(*tg.Chat); ok && cc.ID == p.ChatID {
				br := cc.DefaultBannedRights
				rights.SendPlain = br.SendPlain
				rights.SendPhotos = br.SendPhotos
				rights.SendVideos = br.SendVideos
				rights.SendRoundvideos = br.SendRoundvideos
				rights.SendAudios = br.SendAudios
				rights.SendVoices = br.SendVoices
				rights.SendDocs = br.SendDocs
				rights.SendStickers = br.SendStickers
				rights.EmbedLinks = br.EmbedLinks
				rights.SendPolls = br.SendPolls
				rights.InviteUsers = br.InviteUsers
				rights.ManageTopics = br.ManageTopics
				rights.PinMessages = br.PinMessages
				rights.EditRank = br.EditRank
				rights.ChangeInfo = br.ChangeInfo
				break
			}
		}
	default:
		return nil, fmt.Errorf("not a group or channel")
	}
	return rights, nil
}

func (t *TelegramCore) SetDefaultBannedRights(chatID string, rights *DefaultBannedRights) error {
	br := tg.ChatBannedRights{
		SendPlain:       rights.SendPlain,
		SendPhotos:      rights.SendPhotos,
		SendVideos:      rights.SendVideos,
		SendRoundvideos: rights.SendRoundvideos,
		SendAudios:      rights.SendAudios,
		SendVoices:      rights.SendVoices,
		SendDocs:        rights.SendDocs,
		SendStickers:    rights.SendStickers,
		SendGifs:        rights.SendStickers,
		SendGames:       rights.SendStickers,
		SendInline:      rights.SendStickers,
		EmbedLinks:      rights.EmbedLinks,
		SendPolls:       rights.SendPolls,
		InviteUsers:     rights.InviteUsers,
		ManageTopics:    rights.ManageTopics,
		PinMessages:     rights.PinMessages,
		EditRank:        rights.EditRank,
		ChangeInfo:      rights.ChangeInfo,
	}
	br.SetFlags()
	return t.SetGroupPermissions(chatID, br)
}

func (t *TelegramCore) GetChatPermissionFlags(chatID string) (*ChatPermissionFlags, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel/supergroup")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.ChannelsGetFullChannel(ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, result.Chats)
	flags := &ChatPermissionFlags{AutoTranslateMinLevel: 3}
	if fc, ok := result.FullChat.(*tg.ChannelFull); ok {
		flags.MemberCount = fc.ParticipantsCount
		flags.SlowmodeSeconds = fc.SlowmodeSeconds
		flags.CanViewStats = fc.CanViewStats
		flags.Antispam = fc.Antispam
		flags.PreHistoryHidden = fc.HiddenPrehistory
		flags.NoTranslations = fc.TranslationsDisabled
		flags.PendingRequestsCount = fc.RequestsPending
		flags.CanSetStickers = fc.CanSetStickers
		flags.CanViewParticipants = fc.CanViewParticipants
		flags.ParticipantsHidden = fc.ParticipantsHidden
		if stars, ok := fc.GetSendPaidMessagesStars(); ok {
			flags.DirectMessagesStars = stars
		}
		if rl, ok := fc.GetReactionsLimit(); ok {
			flags.ReactionsMaxCount = rl
		}
		flags.PaidReactionsEnabled = fc.PaidReactionsAvailable
		if loc, ok := fc.GetLocation(); ok {
			if _, isLoc := loc.(*tg.ChannelLocation); isLoc {
				flags.HasLocation = true
			}
		}
		flags.ReactionsMode = "none"
		if ar, ok := fc.GetAvailableReactions(); ok {
			switch r := ar.(type) {
			case *tg.ChatReactionsAll:
				flags.ReactionsMode = "all"
			case *tg.ChatReactionsSome:
				flags.ReactionsMode = "some"
				for _, rc := range r.Reactions {
					switch rr := rc.(type) {
					case *tg.ReactionEmoji:
						flags.ReactionsAllowed = append(flags.ReactionsAllowed, rr.Emoticon)
					case *tg.ReactionCustomEmoji:
						flags.ReactionsAllowed = append(flags.ReactionsAllowed, fmt.Sprintf("%d", rr.DocumentID))
					}
				}
			case *tg.ChatReactionsNone:
				flags.ReactionsMode = "none"
			}
		}
		if lc, ok := fc.GetLinkedChatID(); ok && lc != 0 {
			flags.LinkedChatID = fmt.Sprintf("-100%d", lc)
		}
		if mf, ok := fc.GetMigratedFromChatID(); ok && mf != 0 {
			flags.MigratedFromChatID = fmt.Sprintf("-%d", mf)
		}
	}
	flags.AutoTranslateMinLevel = t.appConfigIntNoLock("channel_autotranslation_level_min", 3)
	flags.StarRefJoinAllowed = t.appConfigBoolNoLock("starref_connect_allowed", false)
	flags.ReactionsUniqMax = t.appConfigIntNoLock("reactions_uniq_max", 11)
	flags.AntispamGroupSizeMin = t.appConfigIntNoLock("telegram_antispam_group_size_min", 100)
	for _, c := range result.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			flags.JoinToSend = cc.JoinToSend
			flags.NoForwards = cc.Noforwards
			flags.JoinRequest = cc.JoinRequest
			flags.IsForum = cc.Forum
			flags.ForumTabs = cc.ForumTabs
			flags.Signatures = cc.Signatures
			flags.SignatureProfiles = cc.SignatureProfiles
			flags.HasUsername = len(cc.Usernames) > 0 || cc.Username != ""
			flags.IsMegagroup = cc.Megagroup
			flags.IsBroadcast = cc.Broadcast
			flags.IsGigagroup = cc.Gigagroup
			flags.AmCreator = cc.Creator
			flags.DirectMessagesEnabled = cc.BroadcastMessagesAllowed
			if ar, ok := cc.GetAdminRights(); ok {
				flags.HasAdminRights = true
				flags.AdminCanChangeInfo = ar.ChangeInfo
				flags.AdminCanPost = ar.PostMessages
				flags.CanAddAdmins = ar.AddAdmins
				flags.CanBanUsers = ar.BanUsers
				flags.CanInviteUsers = ar.InviteUsers
			}
			if cc.Creator {
				flags.CanAddAdmins = true
				flags.CanBanUsers = true
				flags.CanInviteUsers = true
			}
			if lvl, ok := cc.GetLevel(); ok {
				flags.BoostLevel = lvl
			}
			break
		}
	}
	return flags, nil
}

func (t *TelegramCore) appConfigRawNoLock(key string) (tg.JSONValueClass, bool) {
	result, err := t.api.HelpGetAppConfig(t.ctx, 0)
	if err != nil {
		return nil, false
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok || cfg.Config == nil {
		return nil, false
	}
	obj, ok := cfg.Config.(*tg.JSONObject)
	if !ok {
		return nil, false
	}
	for _, kv := range obj.Value {
		if kv.Key == key {
			return kv.Value, true
		}
	}
	return nil, false
}

func (t *TelegramCore) appConfigIntNoLock(key string, def int) int {
	if v, ok := t.appConfigRawNoLock(key); ok {
		if n, ok := v.(*tg.JSONNumber); ok {
			return int(n.Value)
		}
	}
	return def
}

func (t *TelegramCore) appConfigBoolNoLock(key string, def bool) bool {
	if v, ok := t.appConfigRawNoLock(key); ok {
		if b, ok := v.(*tg.JSONBool); ok {
			return b.Value
		}
	}
	return def
}

func appConfigIntAPI(api *tg.Client, ctx context.Context, key string, def int) int {
	if v, ok := appConfigRawAPI(api, ctx, key); ok {
		if n, ok := v.(*tg.JSONNumber); ok {
			return int(n.Value)
		}
	}
	return def
}

func appConfigBoolAPI(api *tg.Client, ctx context.Context, key string, def bool) bool {
	if v, ok := appConfigRawAPI(api, ctx, key); ok {
		if b, ok := v.(*tg.JSONBool); ok {
			return b.Value
		}
	}
	return def
}

func appConfigRawAPI(api *tg.Client, ctx context.Context, key string) (tg.JSONValueClass, bool) {
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return nil, false
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok || cfg.Config == nil {
		return nil, false
	}
	obj, ok := cfg.Config.(*tg.JSONObject)
	if !ok {
		return nil, false
	}
	for _, kv := range obj.Value {
		if kv.Key == key {
			return kv.Value, true
		}
	}
	return nil, false
}

func (t *TelegramCore) ToggleChannelAutoTranslation(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleAutotranslation(ctx, &tg.ChannelsToggleAutotranslationRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) GetBotManageInfo(chatID string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	id, err := tgUserID(chatID)
	if err != nil {
		return nil, err
	}
	hash := t.getCachedUserHash(id)
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: id, AccessHash: hash})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, nil)
	out := map[string]interface{}{
		"has_verifier_settings":  false,
		"starref_allowed":        appConfigBoolAPI(api, ctx, "starref_program_allowed", false),
		"starref_commission":     0,
		"starref_commission_min": appConfigIntAPI(api, ctx, "starref_min_commission_permille", 1),
		"starref_commission_max": appConfigIntAPI(api, ctx, "starref_max_commission_permille", 900),
	}
	if bi, ok := result.FullUser.GetBotInfo(); ok {
		if vs, ok := bi.GetVerifierSettings(); ok {
			out["has_verifier_settings"] = true
			out["verifier_can_modify_description"] = vs.CanModifyCustomDescription
			if desc, ok := vs.GetCustomDescription(); ok {
				out["verifier_custom_description"] = desc
			}
		}
	}
	out["bot_verification_description_length_limit"] = appConfigIntAPI(api, ctx, "bot_verification_description_length_limit", 70)
	if srp, ok := result.FullUser.GetStarrefProgram(); ok {
		out["starref_commission"] = srp.CommissionPermille
		program := map[string]interface{}{
			"commission_permille": srp.CommissionPermille,
			"duration_months":     srp.DurationMonths,
		}
		if ed, ok := srp.GetEndDate(); ok {
			program["end_date"] = ed
		}
		out["star_ref_program"] = program
	}
	return out, nil
}

func (t *TelegramCore) GetBotVerifyState(botID, userID string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return false, err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return false, err
	}
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)})
	if err != nil {
		return false, err
	}
	if bv, ok := result.FullUser.GetBotVerification(); ok {
		return bv.BotID == bid, nil
	}
	return false, nil
}

func (t *TelegramCore) SetBotCustomVerification(botID, peerID string, enabled bool, customDescription string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return false, err
	}
	peer, err := t.resolvePeer(peerID)
	if err != nil {
		return false, err
	}
	inputPeer := t.peerToInputPeer(peer)
	req := &tg.BotsSetCustomVerificationRequest{Peer: inputPeer}
	req.SetBot(&tg.InputUser{UserID: bid, AccessHash: t.getCachedUserHash(bid)})
	if enabled {
		req.SetEnabled(true)
		if customDescription != "" {
			req.SetCustomDescription(customDescription)
		}
	}
	return api.BotsSetCustomVerification(ctx, req)
}

func connectedStarRefBotsToMaps(users map[int64]*tg.User, bots []tg.ConnectedBotStarRef) []map[string]interface{} {
	out := make([]map[string]interface{}, 0, len(bots))
	for _, b := range bots {
		name, uname, avatar := "", "", ""
		if u, ok := users[b.BotID]; ok {
			name = userDisplayName(u)
			uname = u.Username
			avatar = userAvatarStrippedB64(u)
		}
		out = append(out, map[string]interface{}{
			"bot_id":              strconv.FormatInt(b.BotID, 10),
			"bot_name":            name,
			"bot_username":        uname,
			"avatar_b64":          avatar,
			"url":                 b.URL,
			"commission_permille": b.CommissionPermille,
			"duration_months":     b.DurationMonths,
			"date":                b.Date,
			"revoked":             b.Revoked,
			"participants":        b.Participants,
			"revenue":             b.Revenue,
		})
	}
	return out
}

func (t *TelegramCore) GetSuggestedStarRefBots(chatID, offset string, limit int, orderByRevenue, orderByDate bool) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 20
	}
	req := &tg.PaymentsGetSuggestedStarRefBotsRequest{Peer: inputPeer, Offset: offset, Limit: limit}
	req.OrderByRevenue = orderByRevenue
	req.OrderByDate = orderByDate
	res, err := api.PaymentsGetSuggestedStarRefBots(ctx, req)
	if err != nil {
		return nil, err
	}
	users := map[int64]*tg.User{}
	for _, u := range res.Users {
		if uu, ok := u.(*tg.User); ok {
			users[uu.ID] = uu
		}
	}
	bots := make([]map[string]interface{}, 0, len(res.SuggestedBots))
	for _, p := range res.SuggestedBots {
		name, uname, avatar := "", "", ""
		if u, ok := users[p.BotID]; ok {
			name = userDisplayName(u)
			uname = u.Username
			avatar = userAvatarStrippedB64(u)
		}
		m := map[string]interface{}{
			"bot_id":              strconv.FormatInt(p.BotID, 10),
			"bot_name":            name,
			"bot_username":        uname,
			"avatar_b64":          avatar,
			"commission_permille": p.CommissionPermille,
			"duration_months":     p.DurationMonths,
		}
		if dr, ok := p.GetDailyRevenuePerUser(); ok && dr != nil {
			m["daily_revenue"] = dr.GetAmount()
		}
		bots = append(bots, m)
	}
	return map[string]interface{}{
		"count":       res.Count,
		"bots":        bots,
		"next_offset": res.NextOffset,
	}, nil
}

func (t *TelegramCore) GetConnectedStarRefBots(chatID string) ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	res, err := api.PaymentsGetConnectedStarRefBots(ctx, &tg.PaymentsGetConnectedStarRefBotsRequest{Peer: inputPeer})
	if err != nil {
		return nil, err
	}
	users := map[int64]*tg.User{}
	for _, u := range res.Users {
		if uu, ok := u.(*tg.User); ok {
			users[uu.ID] = uu
		}
	}
	return connectedStarRefBotsToMaps(users, res.ConnectedBots), nil
}

func (t *TelegramCore) ConnectStarRefBot(chatID, botID string, revoked bool, link string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return nil, err
	}
	if revoked {
		if link == "" {
			return nil, fmt.Errorf("revoke requires the connected link")
		}
		editRes, eerr := api.PaymentsEditConnectedStarRefBot(ctx, &tg.PaymentsEditConnectedStarRefBotRequest{
			Revoked: true,
			Peer:    inputPeer,
			Link:    link,
		})
		if eerr != nil {
			return nil, eerr
		}
		users := map[int64]*tg.User{}
		for _, u := range editRes.Users {
			if uu, ok := u.(*tg.User); ok {
				users[uu.ID] = uu
			}
		}
		list := connectedStarRefBotsToMaps(users, editRes.ConnectedBots)
		if len(list) > 0 {
			return list[0], nil
		}
		return map[string]interface{}{"revoked": true}, nil
	}
	res, err := api.PaymentsConnectStarRefBot(ctx, &tg.PaymentsConnectStarRefBotRequest{
		Peer: inputPeer,
		Bot:  &tg.InputUser{UserID: bid, AccessHash: t.getCachedUserHash(bid)},
	})
	if err != nil {
		return nil, err
	}
	users := map[int64]*tg.User{}
	for _, u := range res.Users {
		if uu, ok := u.(*tg.User); ok {
			users[uu.ID] = uu
		}
	}
	list := connectedStarRefBotsToMaps(users, res.ConnectedBots)
	for _, m := range list {
		if m["bot_id"] == botID {
			return m, nil
		}
	}
	if len(list) > 0 {
		return list[0], nil
	}
	return map[string]interface{}{}, nil
}

func (t *TelegramCore) GetParticipants(chatID string, limit int) ([]User, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	if limit <= 0 {
		limit = 50
	}
	result, err := api.ChannelsGetParticipants(ctx, &tg.ChannelsGetParticipantsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Filter:  &tg.ChannelParticipantsRecent{}, Limit: limit,
	})
	if err != nil {
		return nil, err
	}
	cp, ok := result.(*tg.ChannelsChannelParticipants)
	if !ok {
		return nil, nil
	}
	t.cacheEntities(cp.Users, cp.Chats)
	roles := make(map[int64]string, len(cp.Participants))
	for _, p := range cp.Participants {
		switch pt := p.(type) {
		case *tg.ChannelParticipantCreator:
			roles[pt.UserID] = "creator"
			t.setAdminRank(ch.ChannelID, pt.UserID, "owner")
		case *tg.ChannelParticipantAdmin:
			roles[pt.UserID] = "admin"
			t.setAdminRank(ch.ChannelID, pt.UserID, "admin")
		}
	}
	var users []User
	for _, u := range cp.Users {
		if user, ok := u.(*tg.User); ok {
			cu := t.convertUser(user)
			if r, ok := roles[user.ID]; ok {
				cu.Role = r
			}
			users = append(users, *cu)
		}
	}
	return users, nil
}

type ParticipantExtra struct {
	CustomRank   string
	PromotedBy   int64
	PromotedDate int
	IsSelf       bool
	IsCreator    bool
	CanEditAdmin bool
	CanRestrict  bool
	BannedRights *DefaultBannedRights
	BannedUntil  int
}

func bannedRightsFromTG(br tg.ChatBannedRights) *DefaultBannedRights {
	return &DefaultBannedRights{
		SendPlain:       br.SendPlain,
		SendPhotos:      br.SendPhotos,
		SendVideos:      br.SendVideos,
		SendRoundvideos: br.SendRoundvideos,
		SendAudios:      br.SendAudios,
		SendVoices:      br.SendVoices,
		SendDocs:        br.SendDocs,
		SendStickers:    br.SendStickers,
		EmbedLinks:      br.EmbedLinks,
		SendPolls:       br.SendPolls,
		InviteUsers:     br.InviteUsers,
		ManageTopics:    br.ManageTopics,
		PinMessages:     br.PinMessages,
		EditRank:        br.EditRank,
		ChangeInfo:      br.ChangeInfo,
	}
}

func (t *TelegramCore) GetParticipantsByRole(chatID, role, query string, limit, offset int) ([]User, map[int64]ParticipantExtra, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, nil, fmt.Errorf("not a channel/supergroup")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	if limit <= 0 {
		limit = 200
	}

	if role == "requests" {
		inputPeer := &tg.InputPeerChannel{ChannelID: ch.ChannelID, AccessHash: hash}
		var users []User
		extras := map[int64]ParticipantExtra{}
		offsetDate := 0
		var offsetUser tg.InputUserClass = &tg.InputUserEmpty{}
		skipped := 0
		for len(users) < limit {
			batch := offset + limit - skipped - len(users)
			if batch > 200 {
				batch = 200
			}
			if batch <= 0 {
				break
			}
			res, err := api.MessagesGetChatInviteImporters(ctx, &tg.MessagesGetChatInviteImportersRequest{
				Requested:  true,
				Peer:       inputPeer,
				Q:          query,
				OffsetDate: offsetDate,
				OffsetUser: offsetUser,
				Limit:      batch,
			})
			if err != nil {
				return nil, nil, err
			}
			t.cacheEntities(res.Users, nil)
			userByID := make(map[int64]*tg.User, len(res.Users))
			for _, u := range res.Users {
				if uu, ok := u.(*tg.User); ok {
					userByID[uu.ID] = uu
				}
			}
			if len(res.Importers) == 0 {
				break
			}
			for _, imp := range res.Importers {
				offsetDate = imp.Date
				if uu := userByID[imp.UserID]; uu != nil {
					offsetUser = &tg.InputUser{UserID: uu.ID, AccessHash: uu.AccessHash}
				} else {
					offsetUser = &tg.InputUser{UserID: imp.UserID, AccessHash: t.getCachedUserHash(imp.UserID)}
				}
				if skipped < offset {
					skipped++
					continue
				}
				if len(users) >= limit {
					break
				}
				if uu := userByID[imp.UserID]; uu != nil {
					cu := t.convertUser(uu)
					cu.Role = "member"
					users = append(users, *cu)
					extras[imp.UserID] = ParticipantExtra{PromotedDate: imp.Date}
				}
			}
			if len(res.Importers) < batch {
				break
			}
		}
		return users, extras, nil
	}

	var filter tg.ChannelParticipantsFilterClass
	switch role {
	case "admins":
		filter = &tg.ChannelParticipantsAdmins{}
	case "restricted":
		filter = &tg.ChannelParticipantsBanned{Q: query}
	case "kicked":
		filter = &tg.ChannelParticipantsKicked{Q: query}
	default:
		filter = &tg.ChannelParticipantsSearch{Q: query}
	}

	result, err := api.ChannelsGetParticipants(ctx, &tg.ChannelsGetParticipantsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Filter:  filter,
		Offset:  offset,
		Limit:   limit,
	})
	if err != nil {
		return nil, nil, err
	}
	cp, ok := result.(*tg.ChannelsChannelParticipants)
	if !ok {
		return nil, nil, nil
	}
	t.cacheEntities(cp.Users, cp.Chats)

	selfCreator, selfAddAdmins, selfBanUsers := false, false, false
	for _, c := range cp.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			selfCreator = cc.Creator
			if ar, ok := cc.GetAdminRights(); ok {
				selfAddAdmins = ar.AddAdmins
				selfBanUsers = ar.BanUsers
			}
			break
		}
	}

	extras := make(map[int64]ParticipantExtra, len(cp.Participants))
	roles := make(map[int64]string, len(cp.Participants))
	for _, p := range cp.Participants {
		switch pt := p.(type) {
		case *tg.ChannelParticipantCreator:
			roles[pt.UserID] = "creator"
			extras[pt.UserID] = ParticipantExtra{
				CustomRank: pt.Rank,
				IsSelf:     pt.UserID == t.selfID,
				IsCreator:  true,
			}
		case *tg.ChannelParticipantAdmin:
			roles[pt.UserID] = "admin"
			isSelf := pt.UserID == t.selfID
			extras[pt.UserID] = ParticipantExtra{
				CustomRank:   pt.Rank,
				PromotedBy:   pt.PromotedBy,
				PromotedDate: pt.Date,
				IsSelf:       isSelf,
				CanEditAdmin: !isSelf && pt.CanEdit,
				CanRestrict:  !isSelf && pt.CanEdit && (selfCreator || selfBanUsers),
			}
		case *tg.ChannelParticipantBanned:
			if peer, ok := pt.Peer.(*tg.PeerUser); ok {
				roles[peer.UserID] = "restricted"
				if pt.BannedRights.ViewMessages {
					roles[peer.UserID] = "banned"
				}
				extras[peer.UserID] = ParticipantExtra{
					PromotedBy:   pt.KickedBy,
					PromotedDate: pt.Date,
					IsSelf:       peer.UserID == t.selfID,
					CanRestrict:  selfCreator || selfBanUsers,
					BannedRights: bannedRightsFromTG(pt.BannedRights),
					BannedUntil:  pt.BannedRights.UntilDate,
				}
			}
		}
	}

	for _, u := range cp.Users {
		uu, ok := u.(*tg.User)
		if !ok {
			continue
		}
		if _, has := extras[uu.ID]; has {
			continue
		}
		isSelf := uu.ID == t.selfID
		extras[uu.ID] = ParticipantExtra{
			IsSelf:       isSelf,
			CanEditAdmin: !isSelf && (selfCreator || selfAddAdmins),
			CanRestrict:  !isSelf && (selfCreator || selfBanUsers),
		}
	}

	var users []User
	for _, u := range cp.Users {
		if user, ok := u.(*tg.User); ok {
			cu := t.convertUser(user)
			if r, ok := roles[user.ID]; ok {
				cu.Role = r
			}
			users = append(users, *cu)
		}
	}
	return users, extras, nil
}

func (t *TelegramCore) GetCommonChats(userID string, limit int) ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	id, err := tgUserID(userID)
	if err != nil {
		return nil, err
	}
	hash := t.getCachedUserHash(id)
	if limit <= 0 {
		limit = 50
	}
	result, err := api.MessagesGetCommonChats(ctx, &tg.MessagesGetCommonChatsRequest{
		UserID: &tg.InputUser{UserID: id, AccessHash: hash}, Limit: limit,
	})
	if err != nil {
		return nil, err
	}
	var dialogs []Dialog
	if mc, ok := result.(*tg.MessagesChats); ok {
		for _, c := range mc.Chats {
			switch ch := c.(type) {
			case *tg.Chat:
				dialogs = append(dialogs, Dialog{ID: strconv.FormatInt(-ch.ID, 10), Title: ch.Title, Type: ChatTypeGroup, Platform: tgPlatform})
			case *tg.Channel:
				ctype := ChatTypeGroup
				if ch.Broadcast {
					ctype = ChatTypeChannel
				}
				dialogs = append(dialogs, Dialog{ID: strconv.FormatInt(-1000000000000-ch.ID, 10), Title: ch.Title, Type: ctype, Platform: tgPlatform})
			}
		}
	}
	return dialogs, nil
}

func (t *TelegramCore) GetSimilarChannels(chatID string) ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.ChannelsGetChannelRecommendations(ctx, &tg.ChannelsGetChannelRecommendationsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	})
	if err != nil {
		return nil, err
	}
	var chats []tg.ChatClass
	switch mc := result.(type) {
	case *tg.MessagesChats:
		chats = mc.Chats
	case *tg.MessagesChatsSlice:
		chats = mc.Chats
	}
	var dialogs []Dialog
	for _, c := range chats {
		channel, ok := c.(*tg.Channel)
		if !ok {
			continue
		}
		d := Dialog{
			ID:       strconv.FormatInt(-1000000000000-channel.ID, 10),
			Title:    channel.Title,
			Type:     ChatTypeChannel,
			Platform: tgPlatform,
		}
		if cp, ok := channel.Photo.(*tg.ChatPhoto); ok {
			if thumb, ok := cp.GetStrippedThumb(); ok && len(thumb) > 0 {
				if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
					d.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
				}
			}
		}
		if channel.ParticipantsCount > 0 {
			d.MemberCount = channel.ParticipantsCount
		}
		t.cacheChannelHash(channel.ID, channel.AccessHash)
		dialogs = append(dialogs, d)
	}
	return dialogs, nil
}

func (t *TelegramCore) GetChatsToSend() ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.StoriesGetChatsToSend(ctx)
	if err != nil {
		return nil, err
	}
	var chats []tg.ChatClass
	switch mc := result.(type) {
	case *tg.MessagesChats:
		chats = mc.Chats
	case *tg.MessagesChatsSlice:
		chats = mc.Chats
	}
	var dialogs []Dialog
	for _, c := range chats {
		channel, ok := c.(*tg.Channel)
		if !ok {
			continue
		}
		if channel.AccessHash != 0 {
			t.cacheChannelHash(channel.ID, channel.AccessHash)
		}
		ctype := ChatTypeGroup
		if channel.Broadcast {
			ctype = ChatTypeChannel
		}
		d := Dialog{
			ID:       strconv.FormatInt(-1000000000000-channel.ID, 10),
			Title:    channel.Title,
			Type:     ctype,
			Username: channel.Username,
			Platform: tgPlatform,
		}
		if cp, ok := channel.Photo.(*tg.ChatPhoto); ok {
			if thumb, ok := cp.GetStrippedThumb(); ok && len(thumb) > 0 {
				if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
					d.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
				}
			}
		}
		if channel.ParticipantsCount > 0 {
			d.MemberCount = channel.ParticipantsCount
		}
		dialogs = append(dialogs, d)
	}
	return dialogs, nil
}

func (t *TelegramCore) ExportMessageLink(chatID string, msgID string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return "", fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	id, err := tgMsgID(msgID)
	if err != nil {
		return "", err
	}
	result, err := api.ChannelsExportMessageLink(ctx, &tg.ChannelsExportMessageLinkRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, ID: id,
	})
	if err != nil {
		return "", err
	}
	return result.Link, nil
}

func (t *TelegramCore) GetSendAs(chatID string) ([]string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	result, err := t.api.ChannelsGetSendAs(t.ctx, &tg.ChannelsGetSendAsRequest{Peer: inputPeer})
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, p := range result.Peers {
		ids = append(ids, peerToID(p.Peer))
	}
	return ids, nil
}

func (t *TelegramCore) SaveDefaultSendAs(chatID, peerID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	chatPeer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	chatInput, err := t.toInputPeer(chatPeer)
	if err != nil {
		return err
	}
	sendAsPeer, err := t.resolvePeer(peerID)
	if err != nil {
		return err
	}
	sendAsInput, err := t.toInputPeer(sendAsPeer)
	if err != nil {
		return err
	}
	_, err = api.MessagesSaveDefaultSendAs(ctx, &tg.MessagesSaveDefaultSendAsRequest{
		Peer:   chatInput,
		SendAs: sendAsInput,
	})
	return err
}

func (t *TelegramCore) JoinChannel(chatID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsJoinChannel(ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	return err
}

func (t *TelegramCore) LeaveChannel(chatID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsLeaveChannel(ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	return err
}

func (t *TelegramCore) ToggleAntiSpam(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleAntiSpam(ctx, &tg.ChannelsToggleAntiSpamRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) ToggleSignatures(chatID string, enabled bool, profilesEnabled ...bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	req := &tg.ChannelsToggleSignaturesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, SignaturesEnabled: enabled,
	}
	if len(profilesEnabled) > 0 {
		req.SetProfilesEnabled(profilesEnabled[0])
	}
	_, err = api.ChannelsToggleSignatures(ctx, req)
	return err
}

func (t *TelegramCore) TogglePreHistoryHidden(chatID string, hidden bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsTogglePreHistoryHidden(ctx, &tg.ChannelsTogglePreHistoryHiddenRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: hidden,
	})
	return err
}

func (t *TelegramCore) TogglePeerTranslations(chatID string, disabled bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesTogglePeerTranslations(t.ctx, &tg.MessagesTogglePeerTranslationsRequest{
		Peer: inputPeer, Disabled: disabled,
	})
	return err
}

func (t *TelegramCore) SetGroupStickerSet(chatID, shortName string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	var stickerSet tg.InputStickerSetClass
	if shortName == "" {
		stickerSet = &tg.InputStickerSetEmpty{}
	} else {
		stickerSet = &tg.InputStickerSetShortName{ShortName: shortName}
	}
	_, err = api.ChannelsSetStickers(ctx, &tg.ChannelsSetStickersRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Stickerset: stickerSet,
	})
	return err
}

func (t *TelegramCore) SetDiscussionGroup(broadcastID, groupID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	var broadcastInput tg.InputChannelClass
	if broadcastID != "" {
		peer, err := t.resolvePeer(broadcastID)
		if err != nil {
			return err
		}
		ch, ok := peer.(*tg.PeerChannel)
		if !ok {
			return fmt.Errorf("broadcast is not a channel")
		}
		hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
		broadcastInput = &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}
	} else {
		broadcastInput = &tg.InputChannelEmpty{}
	}

	var groupInput tg.InputChannelClass
	if groupID != "" {
		peer, err := t.resolvePeer(groupID)
		if err != nil {
			return err
		}
		ch, ok := peer.(*tg.PeerChannel)
		if !ok {
			return fmt.Errorf("group is not a channel/supergroup")
		}
		hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
		groupInput = &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}
	} else {
		groupInput = &tg.InputChannelEmpty{}
	}

	_, err = api.ChannelsSetDiscussionGroup(ctx, &tg.ChannelsSetDiscussionGroupRequest{
		Broadcast: broadcastInput, Group: groupInput,
	})
	return err
}

func (t *TelegramCore) GetDiscussionGroups() ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.ChannelsGetGroupsForDiscussion(ctx)
	if err != nil {
		return nil, err
	}
	var groups []map[string]interface{}
	var chats []tg.ChatClass
	switch v := result.(type) {
	case *tg.MessagesChats:
		chats = v.Chats
	case *tg.MessagesChatsSlice:
		chats = v.Chats
	}
	for _, chat := range chats {
		switch c := chat.(type) {
		case *tg.Channel:
			groups = append(groups, map[string]interface{}{
				"id":       fmt.Sprintf("-100%d", c.ID),
				"title":    c.Title,
				"username": c.Username,
			})
		case *tg.Chat:
			groups = append(groups, map[string]interface{}{
				"id":       fmt.Sprintf("-%d", c.ID),
				"title":    c.Title,
				"username": "",
			})
		}
	}
	return groups, nil
}

func (t *TelegramCore) ToggleNoForwards(chatID string, enabled bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesToggleNoForwards(t.ctx, &tg.MessagesToggleNoForwardsRequest{Peer: inputPeer, Enabled: enabled})
	return err
}

func (t *TelegramCore) SetChatReactions(chatID string, reactions []tg.ReactionClass) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	var availReactions tg.ChatReactionsClass
	if reactions == nil {
		availReactions = &tg.ChatReactionsAll{}
	} else {
		availReactions = &tg.ChatReactionsSome{Reactions: reactions}
	}
	_, err = t.api.MessagesSetChatAvailableReactions(t.ctx, &tg.MessagesSetChatAvailableReactionsRequest{
		Peer: inputPeer, AvailableReactions: availReactions,
	})
	return err
}

func (t *TelegramCore) SetChatReactionsMode(chatID string, mode string, emojis []string, maxCount int, paidEnabled bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	var availReactions tg.ChatReactionsClass
	switch mode {
	case "all":
		availReactions = &tg.ChatReactionsAll{}
	case "none":
		availReactions = &tg.ChatReactionsNone{}
	case "some":
		reactions := make([]tg.ReactionClass, 0, len(emojis))
		for _, e := range emojis {
			reactions = append(reactions, &tg.ReactionEmoji{Emoticon: e})
		}
		if len(reactions) == 0 {
			availReactions = &tg.ChatReactionsNone{}
		} else {
			availReactions = &tg.ChatReactionsSome{Reactions: reactions}
		}
	default:
		return fmt.Errorf("unknown reaction mode: %s", mode)
	}
	req := &tg.MessagesSetChatAvailableReactionsRequest{
		Peer:               inputPeer,
		AvailableReactions: availReactions,
	}
	if maxCount > 0 {
		req.SetReactionsLimit(maxCount)
	}
	if paidEnabled {
		req.SetPaidEnabled(true)
	}
	_, err = t.api.MessagesSetChatAvailableReactions(t.ctx, req)
	return err
}

func (t *TelegramCore) UpdatePaidMessagesPrice(chatID string, stars int64, broadcastEnabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	req := &tg.ChannelsUpdatePaidMessagesPriceRequest{
		Channel:               &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		SendPaidMessagesStars: stars,
	}
	if broadcastEnabled {
		req.SetBroadcastMessagesAllowed(true)
	}
	_, err = api.ChannelsUpdatePaidMessagesPrice(ctx, req)
	return err
}

func (t *TelegramCore) SetBoostsUnrestrict(chatID string, boosts int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsSetBoostsToUnblockRestrictions(ctx, &tg.ChannelsSetBoostsToUnblockRestrictionsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Boosts:  boosts,
	})
	return err
}

func (t *TelegramCore) GetBoostsJSON(chatID string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	status, err := api.PremiumGetBoostsStatus(ctx, inputPeer)
	if err != nil {
		return nil, err
	}
	out := map[string]interface{}{
		"level":                status.Level,
		"boosts":               status.Boosts,
		"current_level_boosts": status.CurrentLevelBoosts,
		"next_level_boosts":    status.NextLevelBoosts,
		"gift_boosts":          status.GiftBoosts,
		"my_boost":             status.MyBoost,
		"boost_url":            status.BoostURL,
	}
	if pa := status.PremiumAudience; pa.Total > 0 {
		out["premium_audience"] = map[string]interface{}{
			"part":  pa.Part,
			"total": pa.Total,
		}
	}
	if slots, ok := status.GetMyBoostSlots(); ok {
		out["my_boost_slots"] = slots
	}
	if prepaid, ok := status.GetPrepaidGiveaways(); ok && len(prepaid) > 0 {
		var giveaways []map[string]interface{}
		for _, pg := range prepaid {
			switch g := pg.(type) {
			case *tg.PrepaidGiveaway:
				giveaways = append(giveaways, map[string]interface{}{
					"id":       g.ID,
					"months":   g.Months,
					"quantity": g.Quantity,
					"date":     g.Date,
				})
			case *tg.PrepaidStarsGiveaway:
				giveaways = append(giveaways, map[string]interface{}{
					"id":       g.ID,
					"credits":  g.Stars,
					"quantity": g.Quantity,
					"boosts":   g.Boosts,
					"date":     g.Date,
				})
			}
		}
		out["prepaid_giveaways"] = giveaways
	}
	return out, nil
}

func (t *TelegramCore) ApplyBoost(chatID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return err
	}
	_, err = api.PremiumApplyBoost(ctx, &tg.PremiumApplyBoostRequest{
		Peer: inputPeer,
	})
	return err
}

func (t *TelegramCore) GetDiscussionThread(chatID, msgID string) ([]Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("comments only exist on channel posts")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	dm, err := api.MessagesGetDiscussionMessage(ctx, &tg.MessagesGetDiscussionMessageRequest{
		Peer:  &tg.InputPeerChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		MsgID: id,
	})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(dm.Users, dm.Chats)
	var out []Message
	for _, mc := range dm.Messages {
		if m, ok := mc.(*tg.Message); ok {
			out = append(out, *t.ConvertMessage(m))
		}
	}
	return out, nil
}

func (t *TelegramCore) ReadDiscussion(chatID, msgID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("comments only exist on channel posts")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	_, err = api.MessagesReadDiscussion(ctx, &tg.MessagesReadDiscussionRequest{
		Peer:  &tg.InputPeerChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		MsgID: id,
	})
	return err
}

func (t *TelegramCore) GetBoostsListJSON(chatID string, isGifts bool, offset string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	req := &tg.PremiumGetBoostsListRequest{
		Peer:   inputPeer,
		Offset: offset,
		Limit:  50,
	}
	if isGifts {
		req.SetGifts(true)
	}
	list, err := api.PremiumGetBoostsList(ctx, req)
	if err != nil {
		return nil, err
	}
	out := map[string]interface{}{
		"count": list.Count,
	}
	if nextOff, ok := list.GetNextOffset(); ok {
		out["next_offset"] = nextOff
	}
	t.cacheEntities(list.Users, nil)
	var boosters []map[string]interface{}
	userMap := map[int64]tg.UserClass{}
	for _, u := range list.Users {
		if usr, ok := u.(*tg.User); ok {
			userMap[usr.ID] = usr
		}
	}
	for _, b := range list.Boosts {
		row := map[string]interface{}{
			"id":      b.ID,
			"date":    b.Date,
			"expires": b.Expires,
		}
		if b.Gift {
			row["gift"] = true
		}
		if b.Giveaway {
			row["giveaway"] = true
		}
		if b.Unclaimed {
			row["unclaimed"] = true
		}
		if uid, ok := b.GetUserID(); ok {
			row["user_id"] = uid
			if u, exists := userMap[uid]; exists {
				if usr, ok := u.(*tg.User); ok {
					name := usr.FirstName
					if usr.LastName != "" {
						name += " " + usr.LastName
					}
					row["user_name"] = name
				}
			}
			if av := t.getUserAvatarB64(uid); av != "" {
				row["avatar_b64"] = av
			}
		}
		if mult, ok := b.GetMultiplier(); ok {
			row["multiplier"] = mult
		}
		boosters = append(boosters, row)
	}
	out["boosters"] = boosters
	return out, nil
}

func (t *TelegramCore) GetGiftCodeOptions(chatID string) ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	req := &tg.PaymentsGetPremiumGiftCodeOptionsRequest{}
	if chatID != "" {
		peer, err := t.resolvePeer(chatID)
		if err != nil {
			return nil, err
		}
		inputPeer, err := t.toInputPeer(peer)
		if err != nil {
			return nil, err
		}
		req.SetBoostPeer(inputPeer)
	}
	options, err := api.PaymentsGetPremiumGiftCodeOptions(ctx, req)
	if err != nil {
		return nil, err
	}
	var result []map[string]interface{}
	for _, opt := range options {
		row := map[string]interface{}{
			"users":    opt.Users,
			"months":   opt.Months,
			"currency": opt.Currency,
			"amount":   opt.Amount,
		}
		if sp, ok := opt.GetStoreProduct(); ok {
			row["store_product"] = sp
		}
		if sq, ok := opt.GetStoreQuantity(); ok {
			row["store_quantity"] = sq
		}
		result = append(result, row)
	}
	return result, nil
}

func (t *TelegramCore) GetGiveawayPeriodMax() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 604800, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return 604800, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return 604800, nil
	}
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				if kv.Key == "giveaway_period_max" {
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						return int(n.Value), nil
					}
				}
			}
		}
	}
	return 604800, nil
}

func (t *TelegramCore) EditChannelTitle(chatID string, title string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsEditTitle(ctx, &tg.ChannelsEditTitleRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Title: title,
	})
	return err
}

func (t *TelegramCore) GetForumTopics(chatID string, limit int) ([]ForumTopic, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	if _, ok := peer.(*tg.PeerChannel); !ok {
		return nil, fmt.Errorf("not a channel")
	}
	if limit <= 0 {
		limit = 20
	}
	inputPeer, _ := t.toInputPeer(peer)
	result, err := api.MessagesGetForumTopics(ctx, &tg.MessagesGetForumTopicsRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil {
		return nil, err
	}

	return t.parseForumTopicsResult(chatID, result), nil
}

func (t *TelegramCore) GetForumTopicsWithOffset(chatID string, limit, offsetDate, offsetID, offsetTopic int) ([]ForumTopic, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	if _, ok := peer.(*tg.PeerChannel); !ok {
		return nil, fmt.Errorf("not a channel")
	}
	if limit <= 0 {
		limit = 20
	}
	inputPeer, _ := t.toInputPeer(peer)
	result, err := api.MessagesGetForumTopics(ctx, &tg.MessagesGetForumTopicsRequest{
		Peer: inputPeer, Limit: limit,
		OffsetDate: offsetDate, OffsetID: offsetID, OffsetTopic: offsetTopic,
	})
	if err != nil {
		return nil, err
	}

	return t.parseForumTopicsResult(chatID, result), nil
}

func (t *TelegramCore) parseForumTopicsResult(chatID string, result *tg.MessagesForumTopics) []ForumTopic {
	var canManageTopics, canDeleteMessages bool
	for _, c := range result.Chats {
		if ch, ok := c.(*tg.Channel); ok {
			if rights, ok := ch.GetAdminRights(); ok {
				canManageTopics = rights.ManageTopics
				canDeleteMessages = rights.DeleteMessages
			}
			break
		}
	}

	msgMap := make(map[int]tg.MessageClass, len(result.Messages))
	for _, m := range result.Messages {
		switch msg := m.(type) {
		case *tg.Message:
			msgMap[msg.ID] = msg
		case *tg.MessageService:
			msgMap[msg.ID] = msg
		}
	}

	var topics []ForumTopic
	for _, topic := range result.Topics {
		ft, ok := topic.(*tg.ForumTopic)
		if !ok {
			continue
		}
		t.cacheForumTopic(chatID, ft.ID, ft.Title, ft.IconColor)

		creatorID := ""
		if ft.FromID != nil {
			switch p := ft.FromID.(type) {
			case *tg.PeerUser:
				creatorID = strconv.FormatInt(p.UserID, 10)
			case *tg.PeerChannel:
				creatorID = strconv.FormatInt(p.ChannelID, 10)
			case *tg.PeerChat:
				creatorID = strconv.FormatInt(p.ChatID, 10)
			}
		}

		var lastMsgText string
		var lastMsgDate int64
		if mc, ok := msgMap[ft.TopMessage]; ok {
			switch msg := mc.(type) {
			case *tg.Message:
				lastMsgText = msg.Message
				lastMsgDate = int64(msg.Date)
			case *tg.MessageService:
				lastMsgDate = int64(msg.Date)
			}
		}

		isGeneral := ft.ID == 1
		canEdit := ft.My || canManageTopics
		topics = append(topics, ForumTopic{
			ID:              strconv.Itoa(ft.ID),
			Title:           ft.Title,
			ColorID:         ft.IconColor,
			IconEmojiID:     ft.IconEmojiID,
			CreatorID:       creatorID,
			CreationDate:    int64(ft.Date),
			IsClosed:        ft.Closed,
			IsHidden:        ft.Hidden,
			IsMy:            ft.My,
			IsPinned:        ft.Pinned,
			UnreadCount:     ft.UnreadCount,
			UnreadMentions:  ft.UnreadMentionsCount,
			UnreadReactions: ft.UnreadReactionsCount,
			TopMessageID:    strconv.Itoa(ft.TopMessage),
			ReadInboxMaxID:  ft.ReadInboxMaxID,
			ReadOutboxMaxID: ft.ReadOutboxMaxID,
			ParentID:        chatID,
			CanEdit:         canEdit,
			CanDelete:       !isGeneral && (canDeleteMessages || ft.My),
			CanToggleClosed: canEdit,
			CanTogglePinned: canManageTopics,
			LastMsgText:     lastMsgText,
			LastMsgDate:     lastMsgDate,
		})
	}
	return topics
}

func (t *TelegramCore) ToggleForum(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleForum(ctx, &tg.ChannelsToggleForumRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) ToggleForumTabs(chatID string, enabled bool, tabs bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleForum(ctx, &tg.ChannelsToggleForumRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled, Tabs: tabs,
	})
	return err
}

func ApplyBotInfoFields(cu *User, bi *tg.BotInfo) {
	if cu == nil || bi == nil {
		return
	}
	if d, ok := bi.GetDescription(); ok && d != "" {
		cu.BotDescription = d
	}
	if pp, ok := bi.GetPrivacyPolicyURL(); ok && pp != "" {
		cu.BotPrivacyURL = pp
	}
	if mb, ok := bi.GetMenuButton(); ok {
		if webApp, ok := mb.(*tg.BotMenuButton); ok {
			cu.BotMenuText = webApp.Text
		}
	}
}

func (t *TelegramCore) GetFullUser(userID string) (*User, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	id, err := tgUserID(userID)
	if err != nil {
		return nil, err
	}
	hash := t.getCachedUserHash(id)
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: id, AccessHash: hash})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, nil)
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok && user.ID == id {
			cu := t.convertUser(user)
			cu.Bio = result.FullUser.About
			if bi, ok := result.FullUser.GetBotInfo(); ok {
				ApplyBotInfoFields(cu, &bi)
			}
			if bday, ok := result.FullUser.GetBirthday(); ok {
				cu.BirthdayDay = bday.Day
				cu.BirthdayMonth = bday.Month
				if y, ok := bday.GetYear(); ok {
					cu.BirthdayYear = y
				}
			}
			if pcID, ok := result.FullUser.GetPersonalChannelID(); ok && pcID != 0 {
				cu.PersonalChannelID = fmt.Sprintf("%d", pcID)
				for _, ch := range result.Chats {
					if channel, ok := ch.(*tg.Channel); ok && channel.ID == pcID {
						cu.PersonalChannelName = channel.Title
						if pc, ok := channel.GetParticipantsCount(); ok {
							cu.PersonalChannelCount = pc
						}
						break
					}
				}
			}
			cu.VoiceMessagesForbidden = result.FullUser.VoiceMessagesForbidden
			cu.ContactRequirePremium = result.FullUser.ContactRequirePremium
			cu.NeedContactsException = result.FullUser.Settings.NeedContactsException
			if pp, ok := result.FullUser.GetPersonalPhoto(); ok {
				cu.HasPersonalPhoto = true
				if photo, ok := pp.(*tg.Photo); ok {
					cu.PersonalPhotoId = fmt.Sprintf("%d", photo.ID)
					if photo.VideoSizes != nil {
						for _, vs := range photo.VideoSizes {
							if sv, ok := vs.(*tg.VideoSize); ok {
								cu.VideoStartPosition = int(sv.VideoStartTs * 1000)
								break
							}
						}
					}
				}
			}
			if fp, ok := result.FullUser.GetFallbackPhoto(); ok {
				if photo, ok := fp.(*tg.Photo); ok {
					cu.FallbackPhotoId = fmt.Sprintf("%d", photo.ID)
				}
			}
			if pp, ok := result.FullUser.GetProfilePhoto(); ok {
				if photo, ok := pp.(*tg.Photo); ok {
					cu.UserpicPhotoId = fmt.Sprintf("%d", photo.ID)
				}
			}
			if noteVal, ok := result.FullUser.GetNote(); ok {
				cu.Note = noteVal.Text
				if ents := convertTgEntities(noteVal.Entities); len(ents) > 0 {
					if b, err := json.Marshal(ents); err == nil {
						cu.NoteEntities = string(b)
					}
				}
			}
			if bwh, ok := result.FullUser.GetBusinessWorkHours(); ok {
				type interval struct {
					Start int `json:"start"`
					End   int `json:"end"`
				}
				type bh struct {
					Timezone  string     `json:"timezone"`
					UtcOffset int        `json:"utc_offset"`
					Intervals []interval `json:"intervals"`
				}
				out := bh{Timezone: bwh.TimezoneID}
				if off, ok := t.timezoneOffsetNoLock(bwh.TimezoneID); ok {
					out.UtcOffset = off
				}
				for _, wo := range bwh.WeeklyOpen {
					out.Intervals = append(out.Intervals, interval{Start: wo.StartMinute, End: wo.EndMinute})
				}
				if data, err := json.Marshal(out); err == nil {
					cu.BusinessHours = string(data)
				}
			}
			return cu, nil
		}
	}
	return nil, ErrNotFound
}

type BotCommandEntry struct {
	Command     string `json:"command"`
	Description string `json:"description"`
	BotID       string `json:"bot_id"`
	BotName     string `json:"bot_name"`
	BotUsername string `json:"bot_username"`
	AvatarB64   string `json:"avatar_b64,omitempty"`
}

func (t *TelegramCore) GetChatBotCommands(chatID string) ([]BotCommandEntry, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}

	userMap := make(map[int64]*tg.User)

	switch p := peer.(type) {
	case *tg.PeerUser:
		hash := t.getCachedUserHash(p.UserID)
		result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: p.UserID, AccessHash: hash})
		if err != nil {
			return nil, err
		}
		t.cacheEntities(result.Users, nil)
		for _, u := range result.Users {
			if user, ok := u.(*tg.User); ok {
				userMap[user.ID] = user
			}
		}
		bi, ok := result.FullUser.GetBotInfo()
		if !ok {
			return nil, nil
		}
		cmds, _ := bi.GetCommands()
		var entries []BotCommandEntry
		for _, c := range cmds {
			e := BotCommandEntry{Command: c.Command, Description: c.Description, BotID: strconv.FormatInt(p.UserID, 10)}
			if u, ok := userMap[p.UserID]; ok {
				e.BotName = userDisplayName(u)
				e.BotUsername = u.Username
				if photo, ok := u.Photo.(*tg.UserProfilePhoto); ok {
					if thumb, ok := photo.GetStrippedThumb(); ok && len(thumb) > 0 {
						if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
							e.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
						}
					}
				}
			}
			entries = append(entries, e)
		}
		return entries, nil

	case *tg.PeerChat:
		result, err := api.MessagesGetFullChat(ctx, p.ChatID)
		if err != nil {
			return nil, err
		}
		t.cacheEntities(result.Users, result.Chats)
		for _, u := range result.Users {
			if user, ok := u.(*tg.User); ok {
				userMap[user.ID] = user
			}
		}
		cf, ok := result.FullChat.(*tg.ChatFull)
		if !ok {
			return nil, nil
		}
		botInfos, _ := cf.GetBotInfo()
		return t.extractBotCommands(botInfos, userMap), nil

	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		result, err := api.ChannelsGetFullChannel(ctx, &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash})
		if err != nil {
			return nil, err
		}
		t.cacheEntities(result.Users, result.Chats)
		for _, u := range result.Users {
			if user, ok := u.(*tg.User); ok {
				userMap[user.ID] = user
			}
		}
		cf, ok := result.FullChat.(*tg.ChannelFull)
		if !ok {
			return nil, nil
		}
		botInfos := cf.GetBotInfo()
		return t.extractBotCommands(botInfos, userMap), nil
	}
	return nil, nil
}

func (t *TelegramCore) extractBotCommands(botInfos []tg.BotInfo, userMap map[int64]*tg.User) []BotCommandEntry {
	var entries []BotCommandEntry
	for _, bi := range botInfos {
		uid, _ := bi.GetUserID()
		cmds, _ := bi.GetCommands()
		for _, c := range cmds {
			e := BotCommandEntry{Command: c.Command, Description: c.Description, BotID: strconv.FormatInt(uid, 10)}
			if u, ok := userMap[uid]; ok {
				e.BotName = userDisplayName(u)
				e.BotUsername = u.Username
				if photo, ok := u.Photo.(*tg.UserProfilePhoto); ok {
					if thumb, ok := photo.GetStrippedThumb(); ok && len(thumb) > 0 {
						if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
							e.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
						}
					}
				}
			}
			entries = append(entries, e)
		}
	}
	return entries
}

func userDisplayName(u *tg.User) string {
	name := u.FirstName
	if u.LastName != "" {
		name += " " + u.LastName
	}
	return name
}

func (t *TelegramCore) UpdateProfile(firstName, lastName, about string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.AccountUpdateProfileRequest{}
	if firstName != "" {
		req.FirstName = firstName
		req.SetFlags()
	}
	if lastName != "" {
		req.LastName = lastName
		req.SetFlags()
	}
	if about != "" {
		req.About = about
		req.SetFlags()
	}
	_, err = api.AccountUpdateProfile(ctx, req)
	return err
}

func (t *TelegramCore) SelfUserID() string {
	return strconv.FormatInt(t.selfID, 10)
}

func (t *TelegramCore) GetSelfBio() (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: t.selfID, AccessHash: 0})
	if err != nil {
		return "", err
	}
	return result.FullUser.About, nil
}

func (t *TelegramCore) GetSelfBirthday() (day, month, year int, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, 0, 0, err
	}
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: t.selfID, AccessHash: 0})
	if err != nil {
		return 0, 0, 0, err
	}
	bday, ok := result.FullUser.GetBirthday()
	if !ok {
		return 0, 0, 0, nil
	}
	y, _ := bday.GetYear()
	return bday.Day, bday.Month, y, nil
}

func (t *TelegramCore) UpdateBio(bio string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.AccountUpdateProfileRequest{}
	req.SetAbout(bio)
	_, err = api.AccountUpdateProfile(ctx, req)
	return err
}

func (t *TelegramCore) GetSelfColorAndChannel() (colorID int, channelName string, bgEmojiID int64, profileColorID int, profileBgEmojiID int64, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return -1, "", 0, -1, 0, err
	}
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: t.selfID, AccessHash: 0})
	if err != nil {
		return -1, "", 0, -1, 0, err
	}

	colorID = -1
	profileColorID = -1
	for _, u := range result.Users {
		user, ok := u.(*tg.User)
		if !ok || user.ID != t.selfID {
			continue
		}
		if pc, ok := user.GetColor(); ok {
			if c, ok := pc.(*tg.PeerColor); ok {
				if v, ok := c.GetColor(); ok {
					colorID = v
				}
				if v, ok := c.GetBackgroundEmojiID(); ok {
					bgEmojiID = v
				}
			}
		}
		if pc, ok := user.GetProfileColor(); ok {
			if c, ok := pc.(*tg.PeerColor); ok {
				if v, ok := c.GetColor(); ok {
					profileColorID = v
				}
				if v, ok := c.GetBackgroundEmojiID(); ok {
					profileBgEmojiID = v
				}
			}
		}
		break
	}

	channelName = ""
	if chID, ok := result.FullUser.GetPersonalChannelID(); ok && chID != 0 {
		for _, ch := range result.Chats {
			if channel, ok := ch.(*tg.Channel); ok && channel.ID == chID {
				channelName = channel.Title
				break
			}
		}
	}
	return colorID, channelName, bgEmojiID, profileColorID, profileBgEmojiID, nil
}

func (t *TelegramCore) UpdateNameColor(colorID int, backgroundEmojiID int64, forProfile bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	pc := &tg.PeerColor{}
	pc.SetColor(colorID)
	if backgroundEmojiID != 0 {
		pc.SetBackgroundEmojiID(backgroundEmojiID)
	}
	req := &tg.AccountUpdateColorRequest{}
	req.SetColor(pc)
	if forProfile {
		req.SetForProfile(true)
	}
	_, err = api.AccountUpdateColor(ctx, req)
	if err != nil {
		return err
	}
	if !forProfile {
		t.peerMu.Lock()
		t.userColorIDs[t.selfID] = colorID
		t.peerMu.Unlock()
	}
	return nil
}

func (t *TelegramCore) GetBackgroundEmojiList() ([]int64, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.AccountGetDefaultBackgroundEmojis(ctx, 0)
	if err != nil {
		return nil, err
	}
	switch v := result.(type) {
	case *tg.EmojiList:
		return v.DocumentID, nil
	default:
		return nil, nil
	}
}

func (t *TelegramCore) GetContentSettings() (sensitiveEnabled bool, sensitiveCanChange bool, ageVerifyNeeded bool, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, false, false, err
	}
	cs, err := api.AccountGetContentSettings(ctx)
	if err != nil {
		return false, false, false, err
	}
	if !cs.SensitiveCanChange {
		result, err2 := api.HelpGetAppConfig(ctx, 0)
		if err2 == nil {
			if cfg, ok := result.(*tg.HelpAppConfig); ok && cfg.Config != nil {
				if obj, ok2 := cfg.Config.(*tg.JSONObject); ok2 {
					for _, kv := range obj.Value {
						if kv.Key == "need_age_video_verification" {
							if b, ok3 := kv.Value.(*tg.JSONBool); ok3 {
								ageVerifyNeeded = b.Value
							}
						}
					}
				}
			}
		}
	}
	return cs.SensitiveEnabled, cs.SensitiveCanChange, ageVerifyNeeded, nil
}

func (t *TelegramCore) SetContentSettings(sensitiveEnabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.AccountSetContentSettingsRequest{SensitiveEnabled: sensitiveEnabled}
	req.SetFlags()
	_, err = api.AccountSetContentSettings(ctx, req)
	return err
}

func (t *TelegramCore) UpdateStatus(online bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountUpdateStatus(ctx, !online)
	return err
}

func (t *TelegramCore) GetUserPhotos(userID string, limit int) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	id, err := tgUserID(userID)
	if err != nil {
		return 0, err
	}
	hash := t.getCachedUserHash(id)
	if limit <= 0 {
		limit = 10
	}
	result, err := api.PhotosGetUserPhotos(ctx, &tg.PhotosGetUserPhotosRequest{
		UserID: &tg.InputUser{UserID: id, AccessHash: hash}, Limit: limit,
	})
	if err != nil {
		return 0, err
	}
	switch r := result.(type) {
	case *tg.PhotosPhotos:
		return len(r.Photos), nil
	case *tg.PhotosPhotosSlice:
		return r.Count, nil
	}
	return 0, nil
}

func (t *TelegramCore) GetUserPhotoAtIndex(userID string, index int) (string, string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", "", err
	}
	id, err := tgUserID(userID)
	if err != nil {
		return "", "", err
	}
	hash := t.getCachedUserHash(id)
	result, err := api.PhotosGetUserPhotos(ctx, &tg.PhotosGetUserPhotosRequest{
		UserID: &tg.InputUser{UserID: id, AccessHash: hash},
		Offset: index,
		Limit:  1,
	})
	if err != nil {
		return "", "", err
	}
	var photos []tg.PhotoClass
	switch r := result.(type) {
	case *tg.PhotosPhotos:
		photos = r.Photos
	case *tg.PhotosPhotosSlice:
		photos = r.Photos
	}
	if len(photos) == 0 {
		return "", "", fmt.Errorf("no photo at index %d", index)
	}
	photo, ok := photos[0].(*tg.Photo)
	if !ok {
		return "", "", fmt.Errorf("photo at index %d is not available", index)
	}
	photoId := fmt.Sprintf("%d", photo.ID)
	avatarDir, err := utils.PrivateCacheDir("telegram-photos")
	if err != nil {
		return "", "", err
	}
	destPath := filepath.Join(avatarDir, fmt.Sprintf("%s_%d_%d.jpg", userID, index, photo.ID))
	if _, err := os.Stat(destPath); err == nil {
		return destPath, photoId, nil
	}
	var bestSize tg.PhotoSizeClass
	var bestW int
	for _, s := range photo.Sizes {
		switch sz := s.(type) {
		case *tg.PhotoSize:
			if sz.W > bestW {
				bestW = sz.W
				bestSize = s
			}
		case *tg.PhotoCachedSize:
			if sz.W > bestW {
				bestW = sz.W
				bestSize = s
			}
		case *tg.PhotoStrippedSize:
			if bestSize == nil {
				bestSize = s
			}
		}
	}
	if bestSize == nil {
		return "", photoId, fmt.Errorf("no downloadable size for photo")
	}
	var sizeType string
	switch sz := bestSize.(type) {
	case *tg.PhotoSize:
		sizeType = sz.Type
	case *tg.PhotoCachedSize:
		sizeType = sz.Type
	case *tg.PhotoStrippedSize:
		sizeType = sz.Type
	}
	location := &tg.InputPhotoFileLocation{
		ID:            photo.ID,
		AccessHash:    photo.AccessHash,
		FileReference: photo.FileReference,
		ThumbSize:     sizeType,
	}
	f, err := os.Create(destPath)
	if err != nil {
		return "", photoId, err
	}
	defer f.Close()
	d := downloader.NewDownloader()
	_, err = d.Download(api, location).Stream(ctx, f)
	if err != nil {
		os.Remove(destPath)
		return "", photoId, err
	}
	return destPath, photoId, nil
}

func (t *TelegramCore) GetAccountTTL() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.AccountGetAccountTTL(ctx)
	if err != nil {
		return 0, err
	}
	return result.Days, nil
}

func (t *TelegramCore) GetPrivacy(key tg.InputPrivacyKeyClass) ([]tg.PrivacyRuleClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.AccountGetPrivacy(ctx, key)
	if err != nil {
		return nil, err
	}
	return result.Rules, nil
}

func (t *TelegramCore) SetPrivacy(key tg.InputPrivacyKeyClass, rules []tg.InputPrivacyRuleClass) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountSetPrivacy(ctx, &tg.AccountSetPrivacyRequest{
		Key: key, Rules: rules,
	})
	return err
}

func PrivacyKeyFor(key string) tg.InputPrivacyKeyClass {
	switch key {
	case "last_seen":
		return &tg.InputPrivacyKeyStatusTimestamp{}
	case "phone_number":
		return &tg.InputPrivacyKeyPhoneNumber{}
	case "profile_photo":
		return &tg.InputPrivacyKeyProfilePhoto{}
	case "calls":
		return &tg.InputPrivacyKeyPhoneCall{}
	case "p2p":
		return &tg.InputPrivacyKeyPhoneP2P{}
	case "forwards":
		return &tg.InputPrivacyKeyForwards{}
	case "group_invites":
		return &tg.InputPrivacyKeyChatInvite{}
	case "voice_messages":
		return &tg.InputPrivacyKeyVoiceMessages{}
	case "about":
		return &tg.InputPrivacyKeyAbout{}
	case "birthday":
		return &tg.InputPrivacyKeyBirthday{}
	}
	return nil
}

func PrivacyScopeFromRules(rules []tg.PrivacyRuleClass) string {
	scope := "nobody"
	for _, r := range rules {
		switch r.(type) {
		case *tg.PrivacyValueAllowAll:
			return "everybody"
		case *tg.PrivacyValueAllowContacts:
			scope = "contacts"
		case *tg.PrivacyValueAllowCloseFriends:
			if scope == "nobody" {
				scope = "close_friends"
			}
		}
	}
	return scope
}

func PrivacyRulesForScope(scope string) []tg.InputPrivacyRuleClass {
	switch scope {
	case "everybody":
		return []tg.InputPrivacyRuleClass{&tg.InputPrivacyValueAllowAll{}}
	case "contacts":
		return []tg.InputPrivacyRuleClass{
			&tg.InputPrivacyValueAllowContacts{},
			&tg.InputPrivacyValueDisallowAll{},
		}
	case "close_friends":
		return []tg.InputPrivacyRuleClass{
			&tg.InputPrivacyValueAllowCloseFriends{},
			&tg.InputPrivacyValueDisallowAll{},
		}
	default:
		return []tg.InputPrivacyRuleClass{&tg.InputPrivacyValueDisallowAll{}}
	}
}

func (t *TelegramCore) GetPrivacyScope(key string) (string, error) {
	k := PrivacyKeyFor(key)
	if k == nil {
		return "", fmt.Errorf("unknown privacy key: %s", key)
	}
	rules, err := t.GetPrivacy(k)
	if err != nil {
		return "", err
	}
	return PrivacyScopeFromRules(rules), nil
}

func (t *TelegramCore) SetPrivacyScope(key, scope string) error {
	k := PrivacyKeyFor(key)
	if k == nil {
		return fmt.Errorf("unknown privacy key: %s", key)
	}
	return t.SetPrivacy(k, PrivacyRulesForScope(scope))
}

func (t *TelegramCore) GetAllStickerSets() ([]string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetAllStickers(ctx, 0)
	if err != nil {
		return nil, err
	}
	var names []string
	if as, ok := result.(*tg.MessagesAllStickers); ok {
		for _, s := range as.Sets {
			names = append(names, s.ShortName)
		}
	}
	return names, nil
}

func (t *TelegramCore) GetFavedStickers() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesGetFavedStickers(ctx, 0)
	if err != nil {
		return 0, err
	}
	if fs, ok := result.(*tg.MessagesFavedStickers); ok {
		return len(fs.Stickers), nil
	}
	return 0, nil
}

func (t *TelegramCore) GetFavedStickersList() ([]StickerInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetFavedStickers(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get faved stickers: %w", err)
	}
	fs, ok := result.(*tg.MessagesFavedStickers)
	if !ok {
		return nil, nil
	}
	var stickers []StickerInfo
	for _, doc := range fs.Stickers {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
		si := StickerInfo{
			ThumbB64: extractStrippedThumbB64(d.Thumbs),
			MimeType: d.MimeType,
			FileID:   strconv.FormatInt(d.ID, 10),
			IsFaved:  true,
		}
		for _, attr := range d.Attributes {
			switch a := attr.(type) {
			case *tg.DocumentAttributeImageSize:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeVideo:
				si.Width = a.W
				si.Height = a.H
			case *tg.DocumentAttributeSticker:
				si.Emoji = a.Alt
			}
		}
		stickers = append(stickers, si)
	}
	return stickers, nil
}

func (t *TelegramCore) GetGifSearchEmojies() ([]string, error) {
	fallback := []string{
		"\U0001F44D",
		"\U0001F618",
		"\U0001F60D",
		"\U0001F621",
		"\U0001F973",
		"\U0001F602",
		"\U0001F62E",
		"\U0001F644",
		"\U0001F60E",
		"\U0001F44E",
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return fallback, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return fallback, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return fallback, nil
	}
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				if kv.Key != "gif_search_emojies" {
					continue
				}
				if arr, ok3 := kv.Value.(*tg.JSONArray); ok3 {
					var out []string
					for _, item := range arr.Value {
						if s, ok4 := item.(*tg.JSONString); ok4 && s.Value != "" {
							out = append(out, s.Value)
						}
					}
					if len(out) > 0 {
						return out, nil
					}
				}
			}
		}
	}
	return fallback, nil
}

func (t *TelegramCore) StartBot(botID string, chatID string, startParam string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return err
	}
	bhash := t.getCachedUserHash(bid)
	peer, _ := t.resolvePeer(chatID)
	inputPeer, _ := t.toInputPeer(peer)
	_, err = api.MessagesStartBot(ctx, &tg.MessagesStartBotRequest{
		Bot: &tg.InputUser{UserID: bid, AccessHash: bhash}, Peer: inputPeer,
		RandomID: time.Now().UnixNano(), StartParam: startParam,
	})
	return err
}

func (t *TelegramCore) GetBotCallbackAnswer(chatID string, msgID string, data []byte, isGame bool) (BotCallbackResult, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return BotCallbackResult{}, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return BotCallbackResult{}, err
	}
	req := &tg.MessagesGetBotCallbackAnswerRequest{
		Peer:  inputPeer,
		MsgID: id,
	}
	if isGame {
		req.SetGame(true)
	} else {
		req.Data = data
	}
	result, err := t.api.MessagesGetBotCallbackAnswer(t.ctx, req)
	if err != nil {
		return BotCallbackResult{}, err
	}
	msg, _ := result.GetMessage()
	url, _ := result.GetURL()
	return BotCallbackResult{
		Message:   msg,
		URL:       url,
		ShowAlert: result.Alert,
	}, nil
}

func (t *TelegramCore) RequestURLAuth(chatID string, msgID string, buttonID int) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	req := &tg.MessagesRequestURLAuthRequest{}
	req.SetPeer(inputPeer)
	req.SetMsgID(id)
	req.SetButtonID(buttonID)
	result, err := t.api.MessagesRequestURLAuth(t.ctx, req)
	if err != nil {
		return nil, err
	}
	out := map[string]interface{}{}
	switch r := result.(type) {
	case *tg.URLAuthResultRequest:
		out["type"] = "request"
		out["domain"] = r.Domain
		out["request_write_access"] = r.RequestWriteAccess
		out["request_phone_number"] = r.RequestPhoneNumber
		if bot, ok := r.Bot.(*tg.User); ok {
			out["bot_id"] = fmt.Sprintf("%d", bot.ID)
			out["bot_name"] = userDisplayName(bot)
			if bot.Verified {
				out["bot_verified"] = true
			}
			if photo, ok := bot.Photo.(*tg.UserProfilePhoto); ok {
				out["bot_photo_id"] = fmt.Sprintf("%d", photo.PhotoID)
			}
		}
		if v, ok := r.GetBrowser(); ok {
			out["browser"] = v
		}
		if v, ok := r.GetPlatform(); ok {
			out["platform"] = v
		}
		if v, ok := r.GetIP(); ok {
			out["ip"] = v
		}
		if v, ok := r.GetRegion(); ok {
			out["region"] = v
		}
		if v, ok := r.GetVerifiedAppName(); ok {
			out["verified_app_name"] = v
		}
		if r.MatchCodesFirst {
			out["match_codes_first"] = true
			if codes, ok := r.GetMatchCodes(); ok {
				out["match_codes"] = codes
			}
		}
	case *tg.URLAuthResultAccepted:
		out["type"] = "accepted"
		if u, ok := r.GetURL(); ok {
			out["url"] = u
		}
	default:
		out["type"] = "default"
	}
	return out, nil
}

func (t *TelegramCore) AcceptURLAuth(chatID string, msgID string, buttonID int, writeAllowed bool, sharePhone bool) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return "", err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return "", err
	}
	req := &tg.MessagesAcceptURLAuthRequest{}
	req.SetPeer(inputPeer)
	req.SetMsgID(id)
	req.SetButtonID(buttonID)
	req.WriteAllowed = writeAllowed
	req.SharePhoneNumber = sharePhone
	req.SetFlags()
	result, err := t.api.MessagesAcceptURLAuth(t.ctx, req)
	if err != nil {
		return "", err
	}
	switch r := result.(type) {
	case *tg.URLAuthResultAccepted:
		if u, ok := r.GetURL(); ok {
			return u, nil
		}
		return "", nil
	default:
		return "", nil
	}
}

func (t *TelegramCore) RequestBotWebView(chatID string, botID string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return "", err
	}
	bhash := t.getCachedUserHash(bid)
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return "", err
	}
	result, err := api.MessagesRequestMainWebView(ctx, &tg.MessagesRequestMainWebViewRequest{
		Peer:     inputPeer,
		Bot:      &tg.InputUser{UserID: bid, AccessHash: bhash},
		Platform: "tdesktop",
	})
	if err != nil {
		return "", err
	}
	return result.URL, nil
}

type InlineBotResult struct {
	ID            string `json:"id"`
	Type          string `json:"type"`
	Title         string `json:"title"`
	Description   string `json:"description"`
	ThumbURL      string `json:"thumb_url,omitempty"`
	ContentURL    string `json:"content_url,omitempty"`
	ThumbW        int    `json:"thumb_w,omitempty"`
	ThumbH        int    `json:"thumb_h,omitempty"`
	ThumbB64      string `json:"thumb_b64,omitempty"`
	DocumentID    int64  `json:"document_id,omitempty"`
	DocumentExtra string `json:"document_extra,omitempty"`
}

type InlineBotResults struct {
	QueryID       int64             `json:"query_id"`
	NextOffset    string            `json:"next_offset"`
	Gallery       bool              `json:"gallery"`
	Results       []InlineBotResult `json:"results"`
	SwitchPM      string            `json:"switch_pm,omitempty"`
	SwitchPMParam string            `json:"switch_pm_param,omitempty"`
}

func (t *TelegramCore) GetInlineBotResults(botID string, query string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return 0, err
	}
	bhash := t.getCachedUserHash(bid)
	result, err := api.MessagesGetInlineBotResults(ctx, &tg.MessagesGetInlineBotResultsRequest{
		Bot:  &tg.InputUser{UserID: bid, AccessHash: bhash},
		Peer: &tg.InputPeerSelf{}, Query: query, Offset: "",
	})
	if err != nil {
		return 0, err
	}
	return len(result.Results), nil
}

func (t *TelegramCore) GetInlineBotResultsFull(botID string, query string, offset string, chatID string) (*InlineBotResults, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	bid, err := tgUserID(botID)
	if err != nil {
		return nil, err
	}
	bhash := t.getCachedUserHash(bid)
	peer := tg.InputPeerClass(&tg.InputPeerSelf{})
	if chatID != "" {
		if inputPeer, unlock, perr := t.withPeer(chatID); perr == nil {
			peer = inputPeer
			unlock()
		}
	}
	result, err := api.MessagesGetInlineBotResults(ctx, &tg.MessagesGetInlineBotResultsRequest{
		Bot:    &tg.InputUser{UserID: bid, AccessHash: bhash},
		Peer:   peer,
		Query:  query,
		Offset: offset,
	})
	if err != nil {
		return nil, err
	}
	out := &InlineBotResults{
		QueryID:    result.QueryID,
		NextOffset: result.NextOffset,
		Gallery:    result.Gallery,
	}
	if pm, ok := result.GetSwitchPm(); ok {
		out.SwitchPM = pm.Text
		out.SwitchPMParam = pm.StartParam
	}
	for _, r := range result.Results {
		item := InlineBotResult{}
		switch v := r.(type) {
		case *tg.BotInlineResult:
			item.ID = v.ID
			item.Type = v.Type
			item.Title, _ = v.GetTitle()
			item.Description, _ = v.GetDescription()
			if thumb, ok := v.GetThumb(); ok {
				item.ThumbURL = thumb.GetURL()
				if sized, ok := thumb.(*tg.WebDocument); ok {
					for _, attr := range sized.Attributes {
						if ds, ok := attr.(*tg.DocumentAttributeImageSize); ok {
							item.ThumbW = ds.W
							item.ThumbH = ds.H
						}
					}
				}
			}
			if content, ok := v.GetContent(); ok {
				item.ContentURL = content.GetURL()
			}
		case *tg.BotInlineMediaResult:
			item.ID = v.ID
			item.Type = v.Type
			item.Title, _ = v.GetTitle()
			item.Description, _ = v.GetDescription()
			if photo, ok := v.GetPhoto(); ok {
				if p, ok := photo.(*tg.Photo); ok {
					for _, sz := range p.Sizes {
						if ps, ok := sz.(*tg.PhotoSize); ok {
							item.ThumbW = ps.W
							item.ThumbH = ps.H
							break
						}
					}
					item.ThumbB64 = extractStrippedThumbB64(p.Sizes)
				}
			}
			if doc, ok := v.GetDocument(); ok {
				if d, ok := doc.(*tg.Document); ok {
					item.DocumentID = d.ID
					item.DocumentExtra = encodeFileExtra(d.AccessHash, d.FileReference)
					t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
					if item.ThumbB64 == "" {
						item.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
					}
					if item.ThumbW == 0 {
						for _, sz := range d.Thumbs {
							if ps, ok := sz.(*tg.PhotoSize); ok {
								item.ThumbW = ps.W
								item.ThumbH = ps.H
								break
							}
						}
					}
				}
			}
		}
		out.Results = append(out.Results, item)
	}
	return out, nil
}

func (t *TelegramCore) GetCallConfig() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	_, err = api.PhoneGetCallConfig(ctx)
	if err != nil {
		return 0, err
	}
	return 1, nil
}

func (t *TelegramCore) GetBroadcastStats(chatID string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.StatsGetBroadcastStats(ctx, &tg.StatsGetBroadcastStatsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	})
	if err != nil {
		return nil, err
	}
	notifPct := 0.0
	if result.EnabledNotifications.Total > 0 {
		notifPct = result.EnabledNotifications.Part / result.EnabledNotifications.Total * 100
	}
	charts := []map[string]interface{}{}
	type chartEntry struct {
		title string
		graph tg.StatsGraphClass
		ctype string
	}
	entries := []chartEntry{
		{"Followers", result.GrowthGraph, "Linear"},
		{"New Followers", result.FollowersGraph, "Linear"},
		{"Notifications", result.MuteGraph, "Linear"},
		{"Views By Hours", result.TopHoursGraph, "Linear"},
		{"Views By Source", result.ViewsBySourceGraph, "StackBar"},
		{"New Followers By Source", result.NewFollowersBySourceGraph, "StackBar"},
		{"Languages", result.LanguagesGraph, "StackLinear"},
		{"Interactions", result.InteractionsGraph, "DoubleLinear"},
		{"IV Interactions", result.IvInteractionsGraph, "DoubleLinear"},
		{"Reactions By Emotion", result.ReactionsByEmotionGraph, "Bar"},
		{"Story Interactions", result.StoryInteractionsGraph, "DoubleLinear"},
		{"Story Reactions By Emotion", result.StoryReactionsByEmotionGraph, "Bar"},
	}
	for _, e := range entries {
		c := statsGraphToMap(e.title, e.graph, e.ctype)
		if c != nil {
			charts = append(charts, c)
		}
	}
	recentPosts := []map[string]interface{}{}
	if len(result.RecentPostsInteractions) > 0 {
		var msgIDs []tg.InputMessageClass
		type postIA struct {
			MsgID, Views, Forwards, Reactions int
		}
		var interactions []postIA
		for _, pi := range result.RecentPostsInteractions {
			if v, ok := pi.(*tg.PostInteractionCountersMessage); ok {
				msgIDs = append(msgIDs, &tg.InputMessageID{ID: v.MsgID})
				interactions = append(interactions, postIA{v.MsgID, v.Views, v.Forwards, v.Reactions})
			}
		}
		if len(msgIDs) > 0 {
			msgMap := map[int]*tg.Message{}
			msgs, merr := api.ChannelsGetMessages(ctx, &tg.ChannelsGetMessagesRequest{
				Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
				ID:      msgIDs,
			})
			if merr == nil {
				if cm, ok := msgs.(*tg.MessagesChannelMessages); ok {
					for _, m := range cm.Messages {
						if msg, ok := m.(*tg.Message); ok {
							msgMap[msg.ID] = msg
						}
					}
				}
			}
			for _, ia := range interactions {
				post := map[string]interface{}{
					"msg_id":    ia.MsgID,
					"views":     ia.Views,
					"forwards":  ia.Forwards,
					"reactions": ia.Reactions,
				}
				if msg, ok := msgMap[ia.MsgID]; ok {
					post["text"] = msg.Message
					post["date"] = msg.Date
					mt, tb := extractMessageMediaSummary(msg)
					post["media_type"] = mt
					if tb != "" {
						post["thumb_b64"] = tb
					}
				}
				recentPosts = append(recentPosts, post)
			}
		}
	}

	return map[string]interface{}{
		"period_min":            result.Period.MinDate,
		"period_max":            result.Period.MaxDate,
		"followers":             statsAbsVal(result.Followers),
		"enabled_notifications": notifPct,
		"views_per_post":        statsAbsVal(result.ViewsPerPost),
		"views_per_story":       statsAbsVal(result.ViewsPerStory),
		"shares_per_post":       statsAbsVal(result.SharesPerPost),
		"shares_per_story":      statsAbsVal(result.SharesPerStory),
		"reactions_per_post":    statsAbsVal(result.ReactionsPerPost),
		"reactions_per_story":   statsAbsVal(result.ReactionsPerStory),
		"charts":                charts,
		"recent_posts":          recentPosts,
	}, nil
}

func statsGraphToMap(title string, g tg.StatsGraphClass, chartType string) map[string]interface{} {
	if g == nil {
		return nil
	}
	switch v := g.(type) {
	case *tg.StatsGraph:
		m := map[string]interface{}{
			"title": title,
			"type":  chartType,
			"data":  v.JSON.Data,
		}
		if tok, ok := v.GetZoomToken(); ok && tok != "" {
			m["zoom_token"] = tok
		}
		return m
	case *tg.StatsGraphAsync:
		return map[string]interface{}{
			"title":       title,
			"type":        chartType,
			"async_token": v.Token,
		}
	default:
		return nil
	}
}

func statsAbsVal(v tg.StatsAbsValueAndPrev) map[string]interface{} {
	growth := 0.0
	if v.Previous > 0 {
		growth = (v.Current - v.Previous) / v.Previous * 100
	}
	return map[string]interface{}{
		"current":  v.Current,
		"previous": v.Previous,
		"growth":   growth,
	}
}

func (t *TelegramCore) GetAllStories() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.StoriesGetAllStories(ctx, &tg.StoriesGetAllStoriesRequest{})
	if err != nil {
		return 0, err
	}
	if as, ok := result.(*tg.StoriesAllStories); ok {
		return as.Count, nil
	}
	return 0, nil
}

func (t *TelegramCore) GetNearestDC() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.HelpGetNearestDC(ctx)
	if err != nil {
		return 0, err
	}
	return result.NearestDC, nil
}

func (t *TelegramCore) SetChatTheme(chatID string, emoticon string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
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

func (t *TelegramCore) GetMessageReactionsList(chatID string, msgID int, limit int, offset string, reactionFilter string) ([]Reaction, string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, "", err
	}
	defer unlock()
	if limit <= 0 {
		limit = 50
	}
	req := &tg.MessagesGetMessageReactionsListRequest{
		Peer: inputPeer, ID: msgID, Limit: limit,
	}
	if offset != "" {
		req.SetOffset(offset)
	}
	if reactionFilter != "" {
		if strings.HasPrefix(reactionFilter, "custom:") {
			docID, _ := strconv.ParseInt(reactionFilter[7:], 10, 64)
			if docID != 0 {
				req.SetReaction(&tg.ReactionCustomEmoji{DocumentID: docID})
			}
		} else {
			req.SetReaction(&tg.ReactionEmoji{Emoticon: reactionFilter})
		}
	}
	result, err := t.api.MessagesGetMessageReactionsList(t.ctx, req)
	if err != nil {
		return nil, "", err
	}
	users := make(map[int64]*tg.User)
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok {
			users[user.ID] = user
		}
	}
	var reactions []Reaction
	for _, r := range result.Reactions {
		var rx Reaction
		switch re := r.Reaction.(type) {
		case *tg.ReactionEmoji:
			rx = Reaction{Emoji: re.Emoticon, Count: 1, Date: r.Date}
		case *tg.ReactionCustomEmoji:
			rx = Reaction{DocumentID: re.DocumentID, Count: 1, Date: r.Date}
		default:
			rx = Reaction{Count: 1, Date: r.Date}
		}
		if peer, ok := r.PeerID.(*tg.PeerUser); ok {
			rx.PeerID = strconv.FormatInt(peer.UserID, 10)
			if u, found := users[peer.UserID]; found {
				name := u.FirstName
				if u.LastName != "" {
					name += " " + u.LastName
				}
				rx.PeerName = name
			}
		}
		reactions = append(reactions, rx)
	}
	nextOffset, _ := result.GetNextOffset()
	return reactions, nextOffset, nil
}

func (t *TelegramCore) GetAvailableReactionEmojis() ([]string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool)
	var emojis []string
	topResult, err := api.MessagesGetTopReactions(ctx, &tg.MessagesGetTopReactionsRequest{
		Limit: 50,
		Hash:  0,
	})
	if err == nil {
		switch r := topResult.(type) {
		case *tg.MessagesReactions:
			for _, rx := range r.Reactions {
				if re, ok := rx.(*tg.ReactionEmoji); ok && !seen[re.Emoticon] {
					emojis = append(emojis, re.Emoticon)
					seen[re.Emoticon] = true
				}
			}
		}
	}
	availResult, err := api.MessagesGetAvailableReactions(ctx, 0)
	if err == nil {
		if avail, ok := availResult.(*tg.MessagesAvailableReactions); ok {
			for _, r := range avail.Reactions {
				if !seen[r.Reaction] {
					emojis = append(emojis, r.Reaction)
					seen[r.Reaction] = true
				}
			}
		}
	}
	if len(emojis) == 0 {
		emojis = []string{"👍", "❤️", "🔥", "🥰", "👏", "😱", "😢", "🎉"}
	}
	return emojis, nil
}

func (t *TelegramCore) SendBotRequestedPeer(chatID string, msgID int, buttonID int, peerIDs []string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	var requestedPeers []tg.InputPeerClass
	for _, pid := range peerIDs {
		id, parseErr := strconv.ParseInt(pid, 10, 64)
		if parseErr != nil {
			continue
		}
		rp, rpUnlock, rpErr := t.withPeer(strconv.FormatInt(id, 10))
		if rpErr != nil {
			requestedPeers = append(requestedPeers, &tg.InputPeerUser{UserID: id})
			continue
		}
		rpUnlock()
		requestedPeers = append(requestedPeers, rp)
	}
	if len(requestedPeers) == 0 {
		return fmt.Errorf("no valid peers to send")
	}
	_, err = t.api.MessagesSendBotRequestedPeer(t.ctx, &tg.MessagesSendBotRequestedPeerRequest{
		Peer:           inputPeer,
		MsgID:          msgID,
		ButtonID:       buttonID,
		RequestedPeers: requestedPeers,
	})
	return err
}

func (t *TelegramCore) GetUnreadMentions(chatID string, limit int) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesGetUnreadMentions(t.ctx, &tg.MessagesGetUnreadMentionsRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil {
		return nil, err
	}
	return t.convertMessages(result), nil
}

func (t *TelegramCore) GetUnreadPollVotes(chatID string, limit int) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesGetUnreadPollVotes(t.ctx, &tg.MessagesGetUnreadPollVotesRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil {
		return nil, err
	}
	return t.convertMessages(result), nil
}

func (t *TelegramCore) GetUnreadReactions(chatID string, limit int) ([]Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesGetUnreadReactions(t.ctx, &tg.MessagesGetUnreadReactionsRequest{
		Peer: inputPeer, Limit: limit,
	})
	if err != nil {
		return nil, err
	}
	return t.convertMessages(result), nil
}

func (t *TelegramCore) DeleteHistory(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesDeleteHistory(t.ctx, &tg.MessagesDeleteHistoryRequest{Peer: inputPeer, MaxID: 0})
	return err
}

func (t *TelegramCore) SendScheduledNow(chatID string, msgIDs []int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesSendScheduledMessages(t.ctx, &tg.MessagesSendScheduledMessagesRequest{
		Peer: inputPeer, ID: msgIDs,
	})
	return err
}

func (t *TelegramCore) RescheduleMessage(chatID string, msgID int, scheduleDate int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	req := &tg.MessagesEditMessageRequest{
		Peer:         inputPeer,
		ID:           msgID,
		ScheduleDate: scheduleDate,
	}
	req.SetScheduleDate(scheduleDate)
	_, err = t.api.MessagesEditMessage(t.ctx, req)
	return err
}

func (t *TelegramCore) GetPollResults(chatID string, msgID int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesGetPollResults(t.ctx, &tg.MessagesGetPollResultsRequest{
		Peer: inputPeer, MsgID: msgID,
	})
	return err
}

func (t *TelegramCore) CheckChatInvite(hash string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	result, err := api.MessagesCheckChatInvite(ctx, hash)
	if err != nil {
		return "", err
	}
	switch inv := result.(type) {
	case *tg.ChatInvite:
		return inv.Title, nil
	case *tg.ChatInviteAlready:
		if ch, ok := inv.Chat.(*tg.Channel); ok {
			return ch.Title, nil
		}
		if ch, ok := inv.Chat.(*tg.Chat); ok {
			return ch.Title, nil
		}
	case *tg.ChatInvitePeek:
		if ch, ok := inv.Chat.(*tg.Channel); ok {
			return ch.Title, nil
		}
		if ch, ok := inv.Chat.(*tg.Chat); ok {
			return ch.Title, nil
		}
	}
	return "", nil
}

func (t *TelegramCore) GetFullChat(chatID string) (*Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return nil, fmt.Errorf("not a basic chat")
	}
	result, err := api.MessagesGetFullChat(ctx, chat.ChatID)
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, result.Chats)
	d := &Dialog{Platform: tgPlatform, ID: chatID, Type: ChatTypeGroup}
	if cf, ok := result.FullChat.(*tg.ChatFull); ok {
		d.Title = cf.About
	}
	for _, c := range result.Chats {
		if ch, ok := c.(*tg.Chat); ok && ch.ID == chat.ChatID {
			d.Title = ch.Title
		}
	}
	return d, nil
}

func (t *TelegramCore) ToggleJoinToSend(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleJoinToSend(ctx, &tg.ChannelsToggleJoinToSendRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) ToggleJoinRequest(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleJoinRequest(ctx, &tg.ChannelsToggleJoinRequestRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) DeleteChannel(chatID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsDeleteChannel(ctx, &tg.InputChannel{
		ChannelID: ch.ChannelID, AccessHash: hash,
	})
	return err
}

func (t *TelegramCore) EditForumTopic(chatID string, topicID int, title string, iconEmojiId int64) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	req := &tg.MessagesEditForumTopicRequest{Peer: inputPeer, TopicID: topicID}
	req.SetTitle(title)
	if iconEmojiId >= 0 {
		req.SetIconEmojiID(iconEmojiId)
	}
	_, err = t.api.MessagesEditForumTopic(t.ctx, req)
	return err
}

func (t *TelegramCore) FaveSticker(fileID int64, extra string, unfave bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	accessHash := t.GetCachedFileHash(fileID)
	fileRef := t.getCachedFileRef(fileID)
	if accessHash == 0 && extra != "" {
		accessHash, fileRef = DecodeFileExtra(extra)
		t.cacheFileInfo(fileID, accessHash, fileRef)
	}
	_, err = api.MessagesFaveSticker(ctx, &tg.MessagesFaveStickerRequest{
		ID:     &tg.InputDocument{ID: fileID, AccessHash: accessHash, FileReference: fileRef},
		Unfave: unfave,
	})
	return err
}

func (t *TelegramCore) SaveGif(fileID int64, extra string, unsave bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	accessHash := t.GetCachedFileHash(fileID)
	fileRef := t.getCachedFileRef(fileID)
	if accessHash == 0 && extra != "" {
		accessHash, fileRef = DecodeFileExtra(extra)
		t.cacheFileInfo(fileID, accessHash, fileRef)
	}
	_, err = api.MessagesSaveGif(ctx, &tg.MessagesSaveGifRequest{
		ID:     &tg.InputDocument{ID: fileID, AccessHash: accessHash, FileReference: fileRef},
		Unsave: unsave,
	})
	return err
}

func (t *TelegramCore) GetMegagroupStats(chatID string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a supergroup")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.StatsGetMegagroupStats(ctx, &tg.StatsGetMegagroupStatsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	})
	if err != nil {
		return nil, err
	}
	charts := []map[string]interface{}{}
	type chartEntry struct {
		title string
		graph tg.StatsGraphClass
		ctype string
	}
	entries := []chartEntry{
		{"Members", result.GrowthGraph, "Linear"},
		{"New Members", result.MembersGraph, "Linear"},
		{"New Members By Source", result.NewMembersBySourceGraph, "StackBar"},
		{"Members' Primary Language", result.LanguagesGraph, "StackLinear"},
		{"Messages", result.MessagesGraph, "StackBar"},
		{"Actions", result.ActionsGraph, "DoubleLinear"},
		{"Top Hours", result.TopHoursGraph, "Linear"},
		{"Days Of Week", result.WeekdaysGraph, "StackLinear"},
	}
	for _, e := range entries {
		c := statsGraphToMap(e.title, e.graph, e.ctype)
		if c != nil {
			charts = append(charts, c)
		}
	}
	userMap := map[int64]map[string]interface{}{}
	for _, u := range result.Users {
		usr, ok := u.(*tg.User)
		if !ok {
			continue
		}
		firstName := usr.FirstName
		lastName := usr.LastName
		name := firstName
		if lastName != "" {
			name += " " + lastName
		}
		userMap[usr.ID] = map[string]interface{}{
			"id":         fmt.Sprintf("%d", usr.ID),
			"name":       name,
			"first_name": firstName,
			"last_name":  lastName,
		}
	}

	topPosters := []map[string]interface{}{}
	for _, p := range result.TopPosters {
		entry := map[string]interface{}{
			"user_id":   fmt.Sprintf("%d", p.UserID),
			"messages":  p.Messages,
			"avg_chars": p.AvgChars,
		}
		if u, ok := userMap[p.UserID]; ok {
			entry["name"] = u["name"]
		}
		topPosters = append(topPosters, entry)
	}

	topAdmins := []map[string]interface{}{}
	for _, a := range result.TopAdmins {
		entry := map[string]interface{}{
			"user_id": fmt.Sprintf("%d", a.UserID),
			"deleted": a.Deleted,
			"kicked":  a.Kicked,
			"banned":  a.Banned,
		}
		if u, ok := userMap[a.UserID]; ok {
			entry["name"] = u["name"]
		}
		topAdmins = append(topAdmins, entry)
	}

	topInviters := []map[string]interface{}{}
	for _, i := range result.TopInviters {
		entry := map[string]interface{}{
			"user_id":     fmt.Sprintf("%d", i.UserID),
			"invitations": i.Invitations,
		}
		if u, ok := userMap[i.UserID]; ok {
			entry["name"] = u["name"]
		}
		topInviters = append(topInviters, entry)
	}

	return map[string]interface{}{
		"period_min":   result.Period.MinDate,
		"period_max":   result.Period.MaxDate,
		"members":      statsAbsVal(result.Members),
		"messages":     statsAbsVal(result.Messages),
		"viewers":      statsAbsVal(result.Viewers),
		"posters":      statsAbsVal(result.Posters),
		"charts":       charts,
		"top_posters":  topPosters,
		"top_admins":   topAdmins,
		"top_inviters": topInviters,
	}, nil
}

func (t *TelegramCore) GetPeerStories(peerID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(peerID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	result, err := t.api.StoriesGetPeerStories(t.ctx, inputPeer)
	if err != nil {
		return 0, err
	}
	return len(result.Stories.Stories), nil
}

func (t *TelegramCore) FetchPeerStoriesData(peerID string) (string, error) {
	inputPeer, unlock, err := t.withPeer(peerID)
	if err != nil {
		return "", err
	}
	defer unlock()
	result, err := t.api.StoriesGetPeerStories(t.ctx, inputPeer)
	if err != nil {
		return "", err
	}

	type storyMediaAreaCoords struct {
		X        float64 `json:"x"`
		Y        float64 `json:"y"`
		W        float64 `json:"w"`
		H        float64 `json:"h"`
		Rotation float64 `json:"rotation"`
		Radius   float64 `json:"radius,omitempty"`
	}
	type storyMediaArea struct {
		Type      string               `json:"type"`
		Coords    storyMediaAreaCoords `json:"coords"`
		Lat       float64              `json:"lat,omitempty"`
		Lng       float64              `json:"lng,omitempty"`
		Title     string               `json:"title,omitempty"`
		Address   string               `json:"address,omitempty"`
		Emoji     string               `json:"emoji,omitempty"`
		Reaction  string               `json:"reaction,omitempty"`
		Flipped   bool                 `json:"flipped,omitempty"`
		Dark      bool                 `json:"dark,omitempty"`
		ChannelID int64                `json:"channel_id,omitempty"`
		MsgID     int                  `json:"msg_id,omitempty"`
		URL       string               `json:"url,omitempty"`
		TempC     float64              `json:"temp_c,omitempty"`
		Color     int                  `json:"color,omitempty"`
	}

	type storyItem struct {
		ID            int              `json:"id"`
		Date          int              `json:"date"`
		Caption       string           `json:"caption"`
		MediaType     string           `json:"media_type"`
		FileRef       FileRef          `json:"file_ref"`
		Views         int              `json:"views"`
		Forwards      int              `json:"forwards,omitempty"`
		Reactions     int              `json:"reactions,omitempty"`
		SentReaction  string           `json:"sent_reaction,omitempty"`
		Pinned        bool             `json:"pinned"`
		Edited        bool             `json:"edited"`
		NoForwards    bool             `json:"no_forwards,omitempty"`
		Expires       int              `json:"expires,omitempty"`
		Privacy       string           `json:"privacy"`
		FwdFromName   string           `json:"fwd_from_name,omitempty"`
		FwdFromPeerID string           `json:"fwd_from_peer_id,omitempty"`
		FwdStoryID    int              `json:"fwd_story_id,omitempty"`
		FwdModified   bool             `json:"fwd_modified,omitempty"`
		MediaAreas    []storyMediaArea `json:"media_areas,omitempty"`
	}

	var items []storyItem
	for _, sc := range result.Stories.Stories {
		si, ok := sc.(*tg.StoryItem)
		if !ok {
			continue
		}

		privacy := "public"
		if si.CloseFriends {
			privacy = "close_friends"
		} else if si.SelectedContacts {
			privacy = "selected_contacts"
		} else if si.Contacts {
			privacy = "contacts"
		}
		item := storyItem{
			ID:         si.ID,
			Date:       si.Date,
			Pinned:     si.Pinned,
			Edited:     si.Edited,
			NoForwards: si.Noforwards,
			Expires:    si.ExpireDate,
			Privacy:    privacy,
		}
		if caption, ok := si.GetCaption(); ok {
			item.Caption = caption
		}
		if views, ok := si.GetViews(); ok {
			item.Views = views.ViewsCount
			if fc, ok := views.GetForwardsCount(); ok {
				item.Forwards = fc
			}
			if rc, ok := views.GetReactionsCount(); ok {
				item.Reactions = rc
			}
		}
		if sent, ok := si.GetSentReaction(); ok && sent != nil {
			item.SentReaction = StoryReactionEmoticon(sent)
		}

		switch md := si.Media.(type) {
		case *tg.MessageMediaPhoto:
			item.MediaType = "photo"
			if p, ok := md.Photo.(*tg.Photo); ok {
				ref := FileRef{
					ID:       strconv.FormatInt(p.ID, 10),
					MimeType: "image/jpeg",
					Name:     fmt.Sprintf("story_%d.jpg", si.ID),
					Extra:    encodeFileExtra(p.AccessHash, p.FileReference),
				}
				for _, size := range p.Sizes {
					if s, ok := size.(*tg.PhotoSize); ok {
						ref.Size = int64(s.Size)
						ref.Width = s.W
						ref.Height = s.H
					}
				}
				ref.ThumbB64 = extractStrippedThumbB64(p.Sizes)
				t.cacheFileInfo(p.ID, p.AccessHash, p.FileReference)
				item.FileRef = ref
			}
		case *tg.MessageMediaDocument:
			if d, ok := md.Document.(*tg.Document); ok {
				ref := FileRef{
					ID:       strconv.FormatInt(d.ID, 10),
					MimeType: d.MimeType,
					Name:     fmt.Sprintf("story_%d.mp4", si.ID),
					Size:     d.Size,
					Extra:    encodeFileExtra(d.AccessHash, d.FileReference),
				}
				ref.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
				for _, attr := range d.Attributes {
					if v, ok := attr.(*tg.DocumentAttributeVideo); ok {
						ref.Width = v.W
						ref.Height = v.H
						ref.Duration = int(v.Duration)
						break
					}
				}
				t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
				item.FileRef = ref
				item.MediaType = "video"
			}
		}

		if fwd, ok := si.GetFwdFrom(); ok {
			item.FwdModified = fwd.Modified
			if name, ok := fwd.GetFromName(); ok && name != "" {
				item.FwdFromName = name
			} else if from, ok := fwd.GetFrom(); ok {
				item.FwdFromPeerID = peerToID(from)
			}
			if sid, ok := fwd.GetStoryID(); ok {
				item.FwdStoryID = sid
			}
		}

		if areas, ok := si.GetMediaAreas(); ok {
			for _, ma := range areas {
				coords := ma.GetCoordinates()
				radius, _ := coords.GetRadius()
				base := storyMediaArea{
					Coords: storyMediaAreaCoords{
						X: coords.X, Y: coords.Y,
						W: coords.W, H: coords.H,
						Rotation: coords.Rotation,
						Radius:   radius,
					},
				}
				switch a := ma.(type) {
				case *tg.MediaAreaVenue:
					base.Type = "venue"
					base.Title = a.Title
					base.Address = a.Address
					if gp, ok := a.Geo.(*tg.GeoPoint); ok {
						base.Lat = gp.Lat
						base.Lng = gp.Long
					}
				case *tg.MediaAreaGeoPoint:
					base.Type = "location"
					if gp, ok := a.Geo.(*tg.GeoPoint); ok {
						base.Lat = gp.Lat
						base.Lng = gp.Long
					}
					if addr, ok := a.GetAddress(); ok {
						base.Address = addr.Street
						if addr.City != "" {
							if base.Address != "" {
								base.Address += ", "
							}
							base.Address += addr.City
						}
					}
				case *tg.MediaAreaSuggestedReaction:
					base.Type = "reaction"
					base.Flipped = a.Flipped
					base.Dark = a.Dark
					switch r := a.Reaction.(type) {
					case *tg.ReactionEmoji:
						base.Reaction = r.Emoticon
					case *tg.ReactionCustomEmoji:
						base.Reaction = fmt.Sprintf("custom:%d", r.DocumentID)
					}
				case *tg.MediaAreaChannelPost:
					base.Type = "channel_post"
					base.ChannelID = a.ChannelID
					base.MsgID = a.MsgID
				case *tg.MediaAreaURL:
					base.Type = "url"
					base.URL = a.URL
				case *tg.MediaAreaWeather:
					base.Type = "weather"
					base.Emoji = a.Emoji
					base.TempC = a.TemperatureC
					base.Color = a.Color
				default:
					continue
				}
				item.MediaAreas = append(item.MediaAreas, base)
			}
		}

		items = append(items, item)
	}

	data, err := json.Marshal(items)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

type StoryAlbumInfo struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	Count int    `json:"count"`
}

func (t *TelegramCore) GetStoryAlbums(peerID string) ([]StoryAlbumInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	var inputPeer tg.InputPeerClass
	if peerID == "" {
		inputPeer = &tg.InputPeerSelf{}
	} else {
		ip, unlock, err := t.withPeer(peerID)
		if err != nil {
			return nil, err
		}
		defer unlock()
		inputPeer = ip
	}
	result, err := api.StoriesGetAlbums(ctx, &tg.StoriesGetAlbumsRequest{
		Peer: inputPeer,
		Hash: 0,
	})
	if err != nil {
		return nil, err
	}
	modified, ok := result.AsModified()
	if !ok {
		return nil, nil
	}
	var albums []StoryAlbumInfo
	for _, a := range modified.Albums {
		albums = append(albums, StoryAlbumInfo{
			ID:    int64(a.AlbumID),
			Title: a.Title,
		})
	}
	return albums, nil
}

func (t *TelegramCore) GetAlbumStories(peerID string, albumID int, offset, limit int) (string, int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", 0, err
	}
	var inputPeer tg.InputPeerClass
	if peerID == "" {
		inputPeer = &tg.InputPeerSelf{}
	} else {
		ip, unlock, err := t.withPeer(peerID)
		if err != nil {
			return "", 0, err
		}
		defer unlock()
		inputPeer = ip
	}
	if limit <= 0 {
		limit = 50
	}
	result, err := api.StoriesGetAlbumStories(ctx, &tg.StoriesGetAlbumStoriesRequest{
		Peer:    inputPeer,
		AlbumID: albumID,
		Offset:  offset,
		Limit:   limit,
	})
	if err != nil {
		return "", 0, err
	}

	type storyEntry struct {
		ID        int    `json:"id"`
		Date      int    `json:"date"`
		Caption   string `json:"caption,omitempty"`
		MediaType string `json:"media_type"`
		ThumbB64  string `json:"thumb_b64,omitempty"`
		LocalPath string `json:"local_path,omitempty"`
	}
	var entries []storyEntry
	for _, sc := range result.Stories {
		si, ok := sc.(*tg.StoryItem)
		if !ok {
			continue
		}
		entry := storyEntry{ID: si.ID, Date: si.Date}
		if caption, ok := si.GetCaption(); ok {
			entry.Caption = caption
		}
		switch md := si.Media.(type) {
		case *tg.MessageMediaPhoto:
			entry.MediaType = "photo"
			if p, ok := md.Photo.(*tg.Photo); ok {
				entry.ThumbB64 = extractStrippedThumbB64(p.Sizes)
			}
		case *tg.MessageMediaDocument:
			entry.MediaType = "video"
			if d, ok := md.Document.(*tg.Document); ok {
				entry.ThumbB64 = extractStrippedThumbB64(d.Thumbs)
			}
		}
		entries = append(entries, entry)
	}
	data, err := json.Marshal(entries)
	if err != nil {
		return "", 0, err
	}
	return string(data), result.Count, nil
}

func (t *TelegramCore) CreateStoryAlbum(title string) (int64, string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, "", err
	}
	album, err := api.StoriesCreateAlbum(ctx, &tg.StoriesCreateAlbumRequest{
		Peer:  &tg.InputPeerSelf{},
		Title: title,
	})
	if err != nil {
		return 0, "", err
	}
	return int64(album.AlbumID), album.Title, nil
}

func (t *TelegramCore) ReorderStoryAlbums(albumIDs []int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.StoriesReorderAlbums(ctx, &tg.StoriesReorderAlbumsRequest{
		Peer:  &tg.InputPeerSelf{},
		Order: albumIDs,
	})
	return err
}

func (t *TelegramCore) GetConfig() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.HelpGetConfig(ctx)
	if err != nil {
		return 0, err
	}
	return len(result.DCOptions), nil
}

func (t *TelegramCore) GetNotifyDelayConfig() (cloudDelayMs, defaultDelayMs, onlineCloudTimeoutMs int, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, 0, 0, err
	}
	result, err := api.HelpGetConfig(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	return result.NotifyCloudDelayMs, result.NotifyDefaultDelayMs, result.OnlineCloudTimeoutMs, nil
}

func (t *TelegramCore) GetAppConfig() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	_, err = api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return false, err
	}
	return true, nil
}

func (t *TelegramCore) GetMegagroupSizeMax() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.HelpGetConfig(ctx)
	if err != nil {
		return 0, err
	}
	return result.MegagroupSizeMax, nil
}

func (t *TelegramCore) GetPassword() (*tg.AccountPassword, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetPassword(ctx)
}

type PasskeyInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Date int    `json:"date"`
}

func (t *TelegramCore) GetPasskeyList() ([]PasskeyInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.AccountGetPasskeys(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]PasskeyInfo, len(result.Passkeys))
	for i, pk := range result.Passkeys {
		out[i] = PasskeyInfo{ID: pk.ID, Name: pk.Name, Date: pk.Date}
	}
	return out, nil
}

type CloudPasswordState struct {
	HasPassword             bool   `json:"hasPassword"`
	HasRecovery             bool   `json:"hasRecovery"`
	Hint                    string `json:"hint"`
	EmailUnconfirmedPattern string `json:"emailUnconfirmedPattern"`
	PendingResetDate        int    `json:"pendingResetDate"`
	LoginEmailPattern       string `json:"loginEmailPattern"`
}

type PasswordResetResult struct {
	Done      bool `json:"done"`
	UntilDate int  `json:"untilDate"`
	RetryDate int  `json:"retryDate"`
}

func (t *TelegramCore) GetCloudPasswordState() (CloudPasswordState, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return CloudPasswordState{}, err
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return CloudPasswordState{}, err
	}
	state := CloudPasswordState{
		HasPassword: pw.HasPassword,
		HasRecovery: pw.HasRecovery,
		Hint:        pw.Hint,
	}
	if pattern, ok := pw.GetEmailUnconfirmedPattern(); ok {
		state.EmailUnconfirmedPattern = pattern
	}
	if date, ok := pw.GetPendingResetDate(); ok {
		state.PendingResetDate = date
	}
	if pattern, ok := pw.GetLoginEmailPattern(); ok {
		state.LoginEmailPattern = pattern
	}
	return state, nil
}

func (t *TelegramCore) CheckCloudPassword(password string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return err
	}
	srpCheck, err := auth.PasswordHash([]byte(password), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
	if err != nil {
		return fmt.Errorf("SRP computation failed: %w", err)
	}
	_, err = api.AccountGetPasswordSettings(ctx, srpCheck)
	return err
}

func (t *TelegramCore) SetCloudPassword(currentPassword, newPassword, hint, email string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return err
	}
	var oldCheck tg.InputCheckPasswordSRPClass
	if pw.HasPassword && currentPassword != "" {
		check, err2 := auth.PasswordHash([]byte(currentPassword), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
		if err2 != nil {
			return fmt.Errorf("SRP computation failed: %w", err2)
		}
		oldCheck = check
	} else {
		oldCheck = &tg.InputCheckPasswordEmpty{}
	}
	newSettings := &tg.AccountPasswordInputSettings{}
	if newPassword != "" {
		algoModPow, ok := pw.NewAlgo.(*tg.PasswordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow)
		if !ok {
			return fmt.Errorf("unsupported new password KDF algorithm")
		}
		secureRandom := make([]byte, 32)
		if _, err := rand.Read(secureRandom); err != nil {
			return err
		}
		algoModPow.Salt1 = append(algoModPow.Salt1, secureRandom...)
		newHash, err := auth.NewPasswordHash([]byte(newPassword), algoModPow)
		if err != nil {
			return fmt.Errorf("new password hash failed: %w", err)
		}
		newSettings.SetNewAlgo(algoModPow)
		newSettings.SetNewPasswordHash(newHash)
		newSettings.SetHint(hint)
	} else {
		newSettings.SetNewAlgo(&tg.PasswordKdfAlgoUnknown{})
		newSettings.SetNewPasswordHash([]byte{})
		newSettings.SetHint("")
	}
	if email != "" {
		newSettings.SetEmail(email)
	}
	_, err = api.AccountUpdatePasswordSettings(ctx, &tg.AccountUpdatePasswordSettingsRequest{
		Password:    oldCheck,
		NewSettings: *newSettings,
	})
	return err
}

func (t *TelegramCore) RemoveCloudPassword(currentPassword string) error {
	return t.SetCloudPassword(currentPassword, "", "", "")
}

func (t *TelegramCore) SetCloudPasswordEmail(currentPassword, email string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return err
	}
	var oldCheck tg.InputCheckPasswordSRPClass
	if pw.HasPassword && currentPassword != "" {
		check, err2 := auth.PasswordHash([]byte(currentPassword), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
		if err2 != nil {
			return fmt.Errorf("SRP computation failed: %w", err2)
		}
		oldCheck = check
	} else {
		oldCheck = &tg.InputCheckPasswordEmpty{}
	}
	newSettings := tg.AccountPasswordInputSettings{}
	newSettings.SetEmail(email)
	_, err = api.AccountUpdatePasswordSettings(ctx, &tg.AccountUpdatePasswordSettingsRequest{
		Password:    oldCheck,
		NewSettings: newSettings,
	})
	return err
}

func (t *TelegramCore) CheckRecoveryPassword(code string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AuthCheckRecoveryPassword(ctx, code)
	return err
}

func (t *TelegramCore) RecoverPasswordWithCode(code, newPassword, hint string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.AuthRecoverPasswordRequest{Code: code}
	if newPassword != "" {
		pw, err := api.AccountGetPassword(ctx)
		if err != nil {
			return err
		}
		algoModPow, ok := pw.NewAlgo.(*tg.PasswordKdfAlgoSHA256SHA256PBKDF2HMACSHA512iter100000SHA256ModPow)
		if !ok {
			return fmt.Errorf("unsupported new password KDF algorithm")
		}
		secureRandom := make([]byte, 32)
		if _, err := rand.Read(secureRandom); err != nil {
			return err
		}
		algoModPow.Salt1 = append(algoModPow.Salt1, secureRandom...)
		newHash, err := auth.NewPasswordHash([]byte(newPassword), algoModPow)
		if err != nil {
			return fmt.Errorf("new password hash failed: %w", err)
		}
		settings := tg.AccountPasswordInputSettings{}
		settings.SetNewAlgo(algoModPow)
		settings.SetNewPasswordHash(newHash)
		settings.SetHint(hint)
		req.SetNewSettings(settings)
	}
	_, err = api.AuthRecoverPassword(ctx, req)
	return err
}

func (t *TelegramCore) RequestPasswordRecovery() (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	result, err := api.AuthRequestPasswordRecovery(ctx)
	if err != nil {
		return "", err
	}
	return result.EmailPattern, nil
}

func (t *TelegramCore) ResetPassword() (PasswordResetResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return PasswordResetResult{}, err
	}
	result, err := api.AccountResetPassword(ctx)
	if err != nil {
		return PasswordResetResult{}, err
	}
	switch v := result.(type) {
	case *tg.AccountResetPasswordOk:
		return PasswordResetResult{Done: true}, nil
	case *tg.AccountResetPasswordRequestedWait:
		return PasswordResetResult{UntilDate: v.UntilDate}, nil
	case *tg.AccountResetPasswordFailedWait:
		return PasswordResetResult{RetryDate: v.RetryDate}, nil
	}
	return PasswordResetResult{}, fmt.Errorf("unexpected reset password result type")
}

func (t *TelegramCore) CancelResetPassword() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountDeclinePasswordReset(ctx)
	return err
}

func (t *TelegramCore) GetGlobalPrivacy() (*tg.GlobalPrivacySettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetGlobalPrivacySettings(ctx)
}

func (t *TelegramCore) GetGiftSettings() (showIcon bool, disallowLimited, disallowUnlimited, disallowUnique, disallowChannels, disallowPremium bool, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, false, false, false, false, false, err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return false, false, false, false, false, false, err
	}
	dg, _ := s.GetDisallowedGifts()
	return s.DisplayGiftsButton, dg.DisallowLimitedStargifts, dg.DisallowUnlimitedStargifts, dg.DisallowUniqueStargifts, dg.DisallowStargiftsFromChannels, dg.DisallowPremiumGifts, nil
}

func (t *TelegramCore) SetGiftSettings(showIcon, acceptLimited, acceptUnlimited, acceptUnique, acceptChannels, acceptPremium bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return err
	}
	s.SetDisplayGiftsButton(showIcon)
	s.SetDisallowedGifts(tg.DisallowedGiftsSettings{
		DisallowLimitedStargifts:      !acceptLimited,
		DisallowUnlimitedStargifts:    !acceptUnlimited,
		DisallowUniqueStargifts:       !acceptUnique,
		DisallowStargiftsFromChannels: !acceptChannels,
		DisallowPremiumGifts:          !acceptPremium,
	})
	_, err = api.AccountSetGlobalPrivacySettings(ctx, *s)
	return err
}

func (t *TelegramCore) GetArchiveSettings() (archiveAndMute bool, keepArchivedUnmuted bool, keepArchivedFolders bool, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, false, false, err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return false, false, false, err
	}
	return s.ArchiveAndMuteNewNoncontactPeers, s.KeepArchivedUnmuted, s.KeepArchivedFolders, nil
}

func (t *TelegramCore) SetArchiveSettings(archiveAndMute, keepArchivedUnmuted, keepArchivedFolders bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	s := tg.GlobalPrivacySettings{}
	s.SetArchiveAndMuteNewNoncontactPeers(archiveAndMute)
	s.SetKeepArchivedUnmuted(keepArchivedUnmuted)
	s.SetKeepArchivedFolders(keepArchivedFolders)
	_, err = api.AccountSetGlobalPrivacySettings(ctx, s)
	return err
}

func (t *TelegramCore) GetAppConfigCheck() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.HelpGetAppConfig(ctx, 0)
	return err
}

func (t *TelegramCore) GetConfigDCCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.HelpGetConfig(ctx)
	if err != nil {
		return 0, err
	}
	return len(result.DCOptions), nil
}

func (t *TelegramCore) SearchContactsCount(query string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.ContactsSearch(ctx, &tg.ContactsSearchRequest{Q: query, Limit: 20})
	if err != nil {
		return 0, err
	}
	return len(result.Users) + len(result.MyResults), nil
}

func (t *TelegramCore) GetTopPeersCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.ContactsGetTopPeers(ctx, &tg.ContactsGetTopPeersRequest{
		Correspondents: true, Limit: 10,
	})
	if err != nil {
		return 0, err
	}
	if tp, ok := result.(*tg.ContactsTopPeers); ok {
		count := 0
		for _, c := range tp.Categories {
			count += len(c.Peers)
		}
		return count, nil
	}
	return 0, nil
}

func (t *TelegramCore) GetBirthdaysCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.ContactsGetBirthdays(ctx)
	if err != nil {
		return 0, err
	}
	return len(result.Contacts), nil
}

func (t *TelegramCore) GetRecentStickersCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesGetRecentStickers(ctx, &tg.MessagesGetRecentStickersRequest{})
	if err != nil {
		return 0, err
	}
	if rs, ok := result.(*tg.MessagesRecentStickers); ok {
		return len(rs.Stickers), nil
	}
	return 0, nil
}

func (t *TelegramCore) GetFeaturedStickersCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesGetFeaturedStickers(ctx, 0)
	if err != nil {
		return 0, err
	}
	if fs, ok := result.(*tg.MessagesFeaturedStickers); ok {
		return len(fs.Sets), nil
	}
	return 0, nil
}

func (t *TelegramCore) SearchStickerSetsCount(query string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesSearchStickerSets(ctx, &tg.MessagesSearchStickerSetsRequest{Q: query})
	if err != nil {
		return 0, err
	}
	if fs, ok := result.(*tg.MessagesFoundStickerSets); ok {
		return len(fs.Sets), nil
	}
	return 0, nil
}

func (t *TelegramCore) GetSearchCounters(chatID string) ([]int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	result, err := t.api.MessagesGetSearchCounters(t.ctx, &tg.MessagesGetSearchCountersRequest{
		Peer: inputPeer, Filters: []tg.MessagesFilterClass{&tg.InputMessagesFilterEmpty{}},
	})
	if err != nil {
		return nil, err
	}
	var counts []int
	for _, c := range result {
		counts = append(counts, c.Count)
	}
	return counts, nil
}

func (t *TelegramCore) GetDefaultHistoryTTL() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesGetDefaultHistoryTTL(ctx)
	if err != nil {
		return 0, err
	}
	return result.Period, nil
}

func ReactionClassForKey(key string) tg.ReactionClass {
	if strings.HasPrefix(key, "custom_") {
		if docID, err := strconv.ParseInt(key[7:], 10, 64); err == nil {
			return &tg.ReactionCustomEmoji{DocumentID: docID}
		}
	}
	return &tg.ReactionEmoji{Emoticon: key}
}

func DecodeDefaultReactionKey(r tg.ReactionClass) string {
	switch v := r.(type) {
	case *tg.ReactionEmoji:
		return v.Emoticon
	case *tg.ReactionCustomEmoji:
		return "custom_" + strconv.FormatInt(v.DocumentID, 10)
	}
	return ""
}

func (t *TelegramCore) SetDefaultReaction(emoji string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	reaction := ReactionClassForKey(emoji)
	_, err = api.MessagesSetDefaultReaction(ctx, reaction)
	if err == nil {
		t.cfgMu.Lock()
		if t.cachedCfg != nil {
			t.cachedCfg.ReactionsDefault = reaction
		}
		t.cfgMu.Unlock()
	}
	return err
}

func (t *TelegramCore) GetDefaultReaction() (string, error) {
	t.cfgMu.RLock()
	cfg := t.cachedCfg
	t.cfgMu.RUnlock()
	if cfg == nil {
		api, ctx, err := t.WithAPI()
		if err != nil {
			return "", err
		}
		result, err := api.HelpGetConfig(ctx)
		if err != nil {
			return "", fmt.Errorf("get config: %w", err)
		}
		t.cfgMu.Lock()
		t.cachedCfg = result
		t.cfgMu.Unlock()
		cfg = result
	}
	if reaction, ok := cfg.GetReactionsDefault(); ok {
		return DecodeDefaultReactionKey(reaction), nil
	}
	return "", nil
}

func (t *TelegramCore) ReactToMessageList(chatID string, msgID string, emojis []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	var peer tg.InputPeerClass
	if inputPeer, unlock, perr := t.withPeer(chatID); perr == nil {
		peer = inputPeer
		unlock()
	} else {
		return perr
	}
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	reactions := make([]tg.ReactionClass, 0, len(emojis))
	for _, emoji := range emojis {
		if strings.HasPrefix(emoji, "custom_") {
			if docID, perr := strconv.ParseInt(emoji[7:], 10, 64); perr == nil {
				reactions = append(reactions, &tg.ReactionCustomEmoji{DocumentID: docID})
				continue
			}
		}
		reactions = append(reactions, &tg.ReactionEmoji{Emoticon: emoji})
	}
	_, err = api.MessagesSendReaction(ctx, &tg.MessagesSendReactionRequest{
		Peer:     peer,
		MsgID:    id,
		Reaction: reactions,
	})
	return err
}

func (t *TelegramCore) ToggleParticipantsHidden(chatID string, hidden bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleParticipantsHidden(ctx, &tg.ChannelsToggleParticipantsHiddenRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: hidden,
	})
	return err
}

func (t *TelegramCore) GetSuggestedFoldersCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesGetSuggestedDialogFilters(ctx)
	if err != nil {
		return 0, err
	}
	return len(result), nil
}

func (t *TelegramCore) GetSuggestedFolders() ([]SuggestedFolder, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetSuggestedDialogFilters(ctx)
	if err != nil {
		return nil, err
	}

	var suggestions []SuggestedFolder
	for _, s := range result {
		var folder Folder
		switch filter := s.Filter.(type) {
		case *tg.DialogFilter:
			folder = Folder{
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
		case *tg.DialogFilterChatlist:
			folder = Folder{
				Name: filter.Title.Text,
			}
			for _, p := range filter.IncludePeers {
				folder.ChatIDs = append(folder.ChatIDs, inputPeerToID(p))
			}
		default:
			continue
		}
		suggestions = append(suggestions, SuggestedFolder{
			Filter:      folder,
			Description: s.Description,
		})
	}
	return suggestions, nil
}

func (t *TelegramCore) GetPeerSettingsCheck(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesGetPeerSettings(t.ctx, inputPeer)
	return err
}

func (t *TelegramCore) GetPeerBarSettings(chatID string) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return "", err
	}
	defer unlock()
	result, err := t.api.MessagesGetPeerSettings(t.ctx, inputPeer)
	if err != nil {
		return "", err
	}
	t.cacheEntities(result.Users, result.Chats)
	s := result.Settings
	m := map[string]interface{}{
		"report_spam":    s.ReportSpam,
		"add_contact":    s.AddContact,
		"block_contact":  s.BlockContact,
		"share_contact":  s.ShareContact,
		"autoarchived":   s.Autoarchived,
		"invite_members": s.InviteMembers,
	}
	if title, ok := s.GetRequestChatTitle(); ok {
		m["request_chat"] = true
		m["request_chat_title"] = title
	}
	if date, ok := s.GetRequestChatDate(); ok {
		m["request_chat_date"] = date
	}
	if s.RequestChatBroadcast {
		m["request_chat_broadcast"] = true
	}
	if dist, ok := s.GetGeoDistance(); ok {
		m["geo_distance"] = dist
	}
	if url, ok := s.GetBusinessBotManageURL(); ok && url != "" {
		m["business_bot_manage_url"] = url
	}
	if p, ok := inputPeer.(*tg.InputPeerUser); ok {
		for _, u := range result.Users {
			if user, ok := u.(*tg.User); ok && user.ID == p.UserID && user.BotCanEdit {
				if _, hasPhoto := user.Photo.(*tg.UserProfilePhoto); !hasPhoto {
					m["set_bot_photo"] = true
				}
				break
			}
		}
	}
	data, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func (t *TelegramCore) GetParticipantInfo(chatID, userID string) (*User, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil {
		return nil, err
	}
	uhash := t.getCachedUserHash(uid)
	result, err := api.ChannelsGetParticipant(ctx, &tg.ChannelsGetParticipantRequest{
		Channel:     &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
	})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, result.Chats)
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok && user.ID == uid {
			cu := t.convertUser(user)
			switch pp := result.Participant.(type) {
			case *tg.ChannelParticipantCreator:
				cu.Role = "creator"
				cu.AdminRights = adminLogAdminRightsMap(&pp.AdminRights)
				cu.Rank = pp.Rank
			case *tg.ChannelParticipantAdmin:
				cu.Role = "admin"
				cu.AdminRights = adminLogAdminRightsMap(&pp.AdminRights)
				cu.Rank = pp.Rank
			case *tg.ChannelParticipantBanned:
				if pp.BannedRights.ViewMessages {
					cu.Role = "kicked"
				} else {
					cu.Role = "restricted"
				}
			case *tg.ChannelParticipant, *tg.ChannelParticipantSelf:
				cu.Role = "member"
			}
			if bp, ok := result.Participant.(*tg.ChannelParticipantBanned); ok {
				br := bp.BannedRights
				cu.BannedUntil = br.UntilDate
				cu.BannedBy = strconv.FormatInt(bp.KickedBy, 10)
				cu.BannedDate = bp.Date
				for _, ru := range result.Users {
					if u2, ok := ru.(*tg.User); ok && u2.ID == bp.KickedBy {
						cu.BannedByName = userDisplayName(u2)
					}
				}
				cu.BannedRights = map[string]bool{
					"send_plain":       br.SendPlain,
					"send_photos":      br.SendPhotos,
					"send_videos":      br.SendVideos,
					"send_roundvideos": br.SendRoundvideos,
					"send_audios":      br.SendAudios,
					"send_voices":      br.SendVoices,
					"send_docs":        br.SendDocs,
					"send_stickers":    br.SendStickers,
					"embed_links":      br.EmbedLinks,
					"send_polls":       br.SendPolls,
					"invite_users":     br.InviteUsers,
					"manage_topics":    br.ManageTopics,
					"pin_messages":     br.PinMessages,
					"change_info":      br.ChangeInfo,
				}
			}
			return cu, nil
		}
	}
	return nil, ErrNotFound
}

func (t *TelegramCore) UploadProfilePhoto(pngData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("profile.png", io.NopCloser(bytes.NewReader(pngData)), int64(len(pngData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	_, err = api.PhotosUploadProfilePhoto(ctx, &tg.PhotosUploadProfilePhotoRequest{
		File: upload,
	})
	return err
}

func (t *TelegramCore) SetBotPhoto(chatID string, pngData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	id, err := strconv.ParseInt(chatID, 10, 64)
	if err != nil {
		return fmt.Errorf("parse bot user ID: %w", err)
	}
	hash := t.getCachedUserHash(id)
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("bot_photo.png", io.NopCloser(bytes.NewReader(pngData)), int64(len(pngData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	req := &tg.PhotosUploadProfilePhotoRequest{File: upload}
	req.SetBot(&tg.InputUser{UserID: id, AccessHash: hash})
	_, err = api.PhotosUploadProfilePhoto(ctx, req)
	return err
}

func (t *TelegramCore) SetEmojiProfilePhoto(documentID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.PhotosUploadProfilePhotoRequest{}
	req.SetVideoEmojiMarkup(&tg.VideoSizeEmojiMarkup{
		EmojiID:          documentID,
		BackgroundColors: []int{0x6B93FF, 0x976FFF, 0xE46ACE, 0xFFB743},
	})
	_, err = api.PhotosUploadProfilePhoto(ctx, req)
	return err
}

func (t *TelegramCore) UploadFallbackPhoto(pngData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("fallback.png", io.NopCloser(bytes.NewReader(pngData)), int64(len(pngData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	req := &tg.PhotosUploadProfilePhotoRequest{File: upload}
	req.SetFallback(true)
	_, err = api.PhotosUploadProfilePhoto(ctx, req)
	return err
}

func (t *TelegramCore) DeleteFallbackPhoto() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: t.selfID, AccessHash: 0})
	if err != nil {
		return err
	}
	fp, ok := result.FullUser.GetFallbackPhoto()
	if !ok {
		return nil
	}
	ph, ok := fp.(*tg.Photo)
	if !ok {
		return nil
	}
	_, err = api.PhotosDeletePhotos(ctx, []tg.InputPhotoClass{
		&tg.InputPhoto{ID: ph.ID, AccessHash: ph.AccessHash, FileReference: ph.FileReference},
	})
	return err
}

func (t *TelegramCore) HasFallbackPhoto() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	result, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: t.selfID, AccessHash: 0})
	if err != nil {
		return false, err
	}
	_, ok := result.FullUser.GetFallbackPhoto()
	return ok, nil
}

func (t *TelegramCore) GetDialogUnreadMarksCount() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.MessagesGetDialogUnreadMarks(ctx, &tg.MessagesGetDialogUnreadMarksRequest{})
	if err != nil {
		return 0, err
	}
	return len(result), nil
}

func (t *TelegramCore) ToggleAutotranslation(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleAutotranslation(ctx, &tg.ChannelsToggleAutotranslationRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) UpdateChannelColor(chatID string, colorIndex int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsUpdateColor(ctx, &tg.ChannelsUpdateColorRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Color: colorIndex,
	})
	return err
}

func (t *TelegramCore) UpdateChannelColorEx(chatID string, colorIndex int, backgroundEmojiID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	req := &tg.ChannelsUpdateColorRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	}
	if colorIndex >= 0 {
		req.SetColor(colorIndex)
	}
	req.SetBackgroundEmojiID(backgroundEmojiID)
	_, err = api.ChannelsUpdateColor(ctx, req)
	return err
}

func (t *TelegramCore) UpdateChannelEmojiStatus(chatID string, documentID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	var status tg.EmojiStatusClass
	if documentID == 0 {
		status = &tg.EmojiStatusEmpty{}
	} else {
		status = &tg.EmojiStatus{DocumentID: documentID}
	}
	_, err = api.ChannelsUpdateEmojiStatus(ctx, &tg.ChannelsUpdateEmojiStatusRequest{
		Channel:     &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		EmojiStatus: status,
	})
	return err
}

func (t *TelegramCore) DeleteProfilePhotos() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	result, err := api.PhotosGetUserPhotos(ctx, &tg.PhotosGetUserPhotosRequest{
		UserID: &tg.InputUserSelf{}, Limit: 1,
	})
	if err != nil {
		return err
	}
	var photos []tg.InputPhotoClass
	switch r := result.(type) {
	case *tg.PhotosPhotos:
		for _, p := range r.Photos {
			if ph, ok := p.(*tg.Photo); ok {
				photos = append(photos, &tg.InputPhoto{ID: ph.ID, AccessHash: ph.AccessHash, FileReference: ph.FileReference})
			}
		}
	case *tg.PhotosPhotosSlice:
		for _, p := range r.Photos {
			if ph, ok := p.(*tg.Photo); ok {
				photos = append(photos, &tg.InputPhoto{ID: ph.ID, AccessHash: ph.AccessHash, FileReference: ph.FileReference})
			}
		}
	}
	if len(photos) == 0 {
		return nil
	}
	_, err = api.PhotosDeletePhotos(ctx, photos[:1])
	return err
}

func (t *TelegramCore) GetOutboxReadDate(chatID, msgID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return 0, err
	}
	result, err := t.api.MessagesGetOutboxReadDate(t.ctx, &tg.MessagesGetOutboxReadDateRequest{Peer: inputPeer, MsgID: id})
	if err != nil {
		return 0, err
	}
	return result.Date, nil
}

func (t *TelegramCore) SetAccountTTL(days int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountSetAccountTTL(ctx, tg.AccountDaysTTL{Days: days})
	return err
}

func (t *TelegramCore) ResolvePhone(phone string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	result, err := api.ContactsResolvePhone(ctx, phone)
	if err != nil {
		return "", err
	}
	t.cacheEntities(result.Users, result.Chats)
	if len(result.Users) > 0 {
		if u, ok := result.Users[0].(*tg.User); ok {
			return strconv.FormatInt(u.ID, 10), nil
		}
	}
	return "", ErrNotFound
}

func (t *TelegramCore) EditCloseFriends(userIDs []int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.ContactsEditCloseFriends(ctx, userIDs)
	return err
}

func (t *TelegramCore) EditChatInvite(chatID, link string, expireDate int) (string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return "", err
	}
	defer unlock()
	result, err := t.api.MessagesEditExportedChatInvite(t.ctx, &tg.MessagesEditExportedChatInviteRequest{
		Peer: inputPeer, Link: link, ExpireDate: expireDate,
	})
	if err != nil {
		return "", err
	}
	if inv, ok := result.GetInvite().(*tg.ChatInviteExported); ok {
		return inv.Link, nil
	}
	return link, nil
}

func (t *TelegramCore) GetInviteImporters(chatID, link string, limit int) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesGetChatInviteImporters(t.ctx, &tg.MessagesGetChatInviteImportersRequest{
		Peer: inputPeer, Link: link, Limit: limit, OffsetUser: &tg.InputUserEmpty{},
	})
	if err != nil {
		return 0, err
	}
	return result.Count, nil
}

func (t *TelegramCore) GetInviteImportersList(chatID, link string, requested bool, limit int, offsetUserID int64, offsetDate int) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	if limit <= 0 {
		limit = 50
	}
	var offsetUser tg.InputUserClass = &tg.InputUserEmpty{}
	if offsetUserID != 0 {
		offsetUser = &tg.InputUser{UserID: offsetUserID, AccessHash: t.getCachedUserHash(offsetUserID)}
	}
	req := &tg.MessagesGetChatInviteImportersRequest{
		Peer:       inputPeer,
		Link:       link,
		Limit:      limit,
		OffsetUser: offsetUser,
		OffsetDate: offsetDate,
	}
	if requested {
		req.Requested = true
	}
	res, err := t.api.MessagesGetChatInviteImporters(t.ctx, req)
	if err != nil {
		return nil, err
	}
	t.cacheEntities(res.Users, nil)
	byID := map[int64]*tg.User{}
	for _, u := range res.Users {
		if uu, ok := u.(*tg.User); ok {
			byID[uu.ID] = uu
		}
	}
	importers := make([]map[string]interface{}, 0, len(res.Importers))
	for _, imp := range res.Importers {
		m := map[string]interface{}{
			"user_id": strconv.FormatInt(imp.UserID, 10),
			"date":    imp.Date,
		}
		if uu := byID[imp.UserID]; uu != nil {
			cu := t.convertUser(uu)
			m["display_name"] = cu.DisplayName
			m["username"] = cu.Username
			m["avatar_b64"] = cu.AvatarB64
		}
		if requested && imp.About != "" {
			m["about"] = imp.About
		}
		importers = append(importers, m)
	}
	return map[string]interface{}{
		"count":     res.Count,
		"importers": importers,
	}, nil
}

func (t *TelegramCore) DeleteChatInvite(chatID, link string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesEditExportedChatInvite(t.ctx, &tg.MessagesEditExportedChatInviteRequest{
		Peer: inputPeer, Link: link, Revoked: true,
	})
	if err != nil {
		return fmt.Errorf("revoke invite: %w", err)
	}
	_, err = t.api.MessagesDeleteExportedChatInvite(t.ctx, &tg.MessagesDeleteExportedChatInviteRequest{
		Peer: inputPeer, Link: link,
	})
	return err
}

func (t *TelegramCore) GetContactIDs() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.ContactsGetContactIDs(ctx, 0)
	if err != nil {
		return 0, err
	}
	return len(result), nil
}

func (t *TelegramCore) GetDifferenceCheck() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	state, err := api.UpdatesGetState(ctx)
	if err != nil {
		return fmt.Errorf("get state: %w", err)
	}
	_, err = api.UpdatesGetDifference(ctx, &tg.UpdatesGetDifferenceRequest{
		Pts: state.Pts, Date: state.Date, Qts: state.Qts,
	})
	return err
}

func (t *TelegramCore) ReorderPinnedSavedDialogs(peerIDs []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	var order []tg.InputDialogPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil {
			continue
		}
		inputPeer, _ := t.toInputPeer(peer)
		order = append(order, &tg.InputDialogPeer{Peer: inputPeer})
	}
	_, err = api.MessagesReorderPinnedSavedDialogs(ctx, &tg.MessagesReorderPinnedSavedDialogsRequest{
		Order: order, Force: true,
	})
	return err
}

func (t *TelegramCore) ReorderPinnedDialogs(chatIDs []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	var order []tg.InputDialogPeerClass
	for _, cid := range chatIDs {
		peer, err := t.resolvePeer(cid)
		if err != nil {
			continue
		}
		inputPeer, _ := t.toInputPeer(peer)
		order = append(order, &tg.InputDialogPeer{Peer: inputPeer})
	}
	_, err = api.MessagesReorderPinnedDialogs(ctx, &tg.MessagesReorderPinnedDialogsRequest{
		FolderID: 0, Order: order, Force: true,
	})
	return err
}

func (t *TelegramCore) SetGlobalPrivacy(settings *tg.GlobalPrivacySettings) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountSetGlobalPrivacySettings(ctx, *settings)
	return err
}

func (t *TelegramCore) GetHideReadMarks() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return false, err
	}
	return s.HideReadMarks, nil
}

func (t *TelegramCore) SetHideReadMarks(hide bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return err
	}
	s.SetHideReadMarks(hide)
	_, err = api.AccountSetGlobalPrivacySettings(ctx, *s)
	return err
}

func (t *TelegramCore) GetMessagesPrivacy() (option string, chargeStars int64, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", 0, err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return "", 0, err
	}
	stars, _ := s.GetNoncontactPeersPaidStars()
	if stars > 0 {
		return "charge_stars", stars, nil
	}
	if s.NewNoncontactPeersRequirePremium {
		return "contacts_premium", 0, nil
	}
	return "everyone", 0, nil
}

func (t *TelegramCore) SetMessagesPrivacy(option string, chargeStars int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	s, err := api.AccountGetGlobalPrivacySettings(ctx)
	if err != nil {
		return err
	}
	switch option {
	case "everyone":
		s.SetNewNoncontactPeersRequirePremium(false)
		s.SetNoncontactPeersPaidStars(0)
	case "contacts_premium":
		s.SetNewNoncontactPeersRequirePremium(true)
		s.SetNoncontactPeersPaidStars(0)
	case "charge_stars":
		s.SetNewNoncontactPeersRequirePremium(true)
		if chargeStars < 1 {
			chargeStars = 1
		}
		s.SetNoncontactPeersPaidStars(chargeStars)
	}
	_, err = api.AccountSetGlobalPrivacySettings(ctx, *s)
	return err
}

func (t *TelegramCore) GetConfcallSizeLimit() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 200, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return 200, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return 200, nil
	}
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				if kv.Key == "groupcall_video_participants_max" {
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						return int(n.Value), nil
					}
				}
			}
		}
	}
	return 200, nil
}

func (t *TelegramCore) GetStarsPaidPostAmountMax() (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 10000, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return 10000, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return 10000, nil
	}
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				if kv.Key == "stars_paid_post_amount_max" {
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						return int(n.Value), nil
					}
				}
			}
		}
	}
	return 10000, nil
}

func (t *TelegramCore) UnlockPaidMedia(chatID, msgID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return err
	}
	id, err := strconv.Atoi(strings.TrimSpace(msgID))
	if err != nil || id <= 0 {
		return fmt.Errorf("%w: bad message id %q", ErrInvalidInput, msgID)
	}
	invoice := &tg.InputInvoiceMessage{Peer: inputPeer, MsgID: id}
	rawForm, err := api.PaymentsGetPaymentForm(ctx, &tg.PaymentsGetPaymentFormRequest{
		Invoice: invoice,
	})
	if err != nil {
		return fmt.Errorf("get payment form: %w", err)
	}
	form, ok := rawForm.(*tg.PaymentsPaymentForm)
	if !ok {
		return fmt.Errorf("unexpected payment form type: %T", rawForm)
	}
	rawRes, err := api.PaymentsSendStarsForm(ctx, &tg.PaymentsSendStarsFormRequest{
		FormID:  form.FormID,
		Invoice: invoice,
	})
	if err != nil {
		return fmt.Errorf("pay: %w", err)
	}
	switch res := rawRes.(type) {
	case *tg.PaymentsPaymentResult:
		return nil
	case *tg.PaymentsPaymentVerificationNeeded:
		if res.URL != "" {
			return fmt.Errorf("verification needed: %s", res.URL)
		}
		return fmt.Errorf("verification needed")
	default:
		return fmt.Errorf("unexpected payment result type: %T", rawRes)
	}
}

func (t *TelegramCore) GetStarsBalance() (int64, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.PaymentsGetStarsStatus(ctx, &tg.PaymentsGetStarsStatusRequest{
		Peer: &tg.InputPeerSelf{},
	})
	if err != nil {
		return 0, err
	}
	return result.Balance.GetAmount(), nil
}

type StarsRevenueResult struct {
	CurrentBalance    int64                    `json:"current_balance"`
	AvailableBalance  int64                    `json:"available_balance"`
	OverallRevenue    int64                    `json:"overall_revenue"`
	WithdrawalEnabled bool                     `json:"withdrawal_enabled"`
	UsdRate           float64                  `json:"usd_rate"`
	Charts            []map[string]interface{} `json:"charts,omitempty"`
	WithdrawalMin     int64                    `json:"withdrawal_min,omitempty"`
	WithdrawalMax     int64                    `json:"withdrawal_max,omitempty"`
}

func (t *TelegramCore) GetStarsRevenueStats(chatID string) (StarsRevenueResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return StarsRevenueResult{}, err
	}
	peer, _ := t.resolvePeer(chatID)
	inputPeer, _ := t.toInputPeer(peer)
	result, err := api.PaymentsGetStarsRevenueStats(ctx, &tg.PaymentsGetStarsRevenueStatsRequest{
		Peer: inputPeer,
	})
	if err != nil {
		return StarsRevenueResult{}, err
	}
	charts := []map[string]interface{}{}
	if c := statsGraphToMap("Revenue", result.RevenueGraph, "StackBar"); c != nil {
		charts = append(charts, c)
	}
	if c := statsGraphToMap("Top Hours", result.TopHoursGraph, "Linear"); c != nil {
		charts = append(charts, c)
	}
	avail := result.Status.AvailableBalance.GetAmount()
	withdrawMin := int64(t.appConfigIntNoLock("stars_revenue_withdrawal_min", 1000))
	withdrawMax := int64(t.appConfigIntNoLock("stars_revenue_withdrawal_max", 1000000000))
	if withdrawMax <= 0 || withdrawMax > avail {
		withdrawMax = avail
	}
	return StarsRevenueResult{
		CurrentBalance:    result.Status.CurrentBalance.GetAmount(),
		AvailableBalance:  avail,
		OverallRevenue:    result.Status.OverallRevenue.GetAmount(),
		WithdrawalEnabled: result.Status.WithdrawalEnabled,
		UsdRate:           result.UsdRate,
		Charts:            charts,
		WithdrawalMin:     withdrawMin,
		WithdrawalMax:     withdrawMax,
	}, nil
}

func StarsStatusFromWire(res *tg.PaymentsStarsStatus) StarsStatus {
	if res == nil {
		return StarsStatus{}
	}
	names := map[int64]string{}
	for _, u := range res.Users {
		if user, ok := u.(*tg.User); ok {
			names[user.ID] = userDisplayName(user)
		}
	}
	for _, c := range res.Chats {
		switch ch := c.(type) {
		case *tg.Channel:
			names[ch.ID] = ch.Title
		case *tg.Chat:
			names[ch.ID] = ch.Title
		}
	}
	out := StarsStatus{NextOffset: res.NextOffset}
	if res.Balance != nil {
		out.BalanceNano = res.Balance.GetAmount()
	}
	for _, tx := range res.History {
		t := StarsTxn{
			ID:        tx.ID,
			NanoStars: tx.Amount.GetAmount(),
			Date:      int64(tx.Date),
			Refund:    tx.Refund,
			Pending:   tx.Pending,
			Failed:    tx.Failed,
			Gift:      tx.Gift,
		}
		if title, ok := tx.GetTitle(); ok {
			t.Title = title
		}
		if desc, ok := tx.GetDescription(); ok {
			t.Description = desc
		}
		if sp, ok := tx.Peer.(*tg.StarsTransactionPeer); ok {
			switch p := sp.Peer.(type) {
			case *tg.PeerUser:
				t.PeerTitle = names[p.UserID]
			case *tg.PeerChannel:
				t.PeerTitle = names[p.ChannelID]
			case *tg.PeerChat:
				t.PeerTitle = names[p.ChatID]
			}
		}
		out.Txns = append(out.Txns, t)
	}
	return out
}

func (t *TelegramCore) GetMyStars(offset, filter string) (StarsStatus, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return StarsStatus{}, err
	}
	req := &tg.PaymentsGetStarsTransactionsRequest{
		Peer:   &tg.InputPeerSelf{},
		Offset: offset,
		Limit:  30,
	}
	switch filter {
	case "in":
		req.Inbound = true
	case "out":
		req.Outbound = true
	}
	res, err := api.PaymentsGetStarsTransactions(ctx, req)
	if err != nil {
		return StarsStatus{}, fmt.Errorf("get stars transactions: %w", err)
	}
	return StarsStatusFromWire(res), nil
}

func (t *TelegramCore) GetStarsTransactions(chatID, offset string, limit int, filter string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 30
	}
	req := &tg.PaymentsGetStarsTransactionsRequest{
		Peer:   inputPeer,
		Offset: offset,
		Limit:  limit,
	}
	switch filter {
	case "in":
		req.Inbound = true
	case "out":
		req.Outbound = true
	}
	res, err := api.PaymentsGetStarsTransactions(ctx, req)
	if err != nil {
		return nil, err
	}
	txns := make([]map[string]interface{}, 0, len(res.History))
	for _, tx := range res.History {
		m := map[string]interface{}{
			"id":          tx.ID,
			"amount":      tx.Amount.GetAmount(),
			"date":        tx.Date,
			"refund":      tx.Refund,
			"title":       tx.Title,
			"description": tx.Description,
			"pending":     tx.Pending,
			"failed":      tx.Failed,
			"gift":        tx.Gift,
		}
		if sp, ok := tx.GetSubscriptionPeriod(); ok && sp != 0 {
			m["subscription_period"] = sp
		}
		txns = append(txns, m)
	}
	return map[string]interface{}{
		"transactions": txns,
		"next_offset":  res.NextOffset,
		"balance":      res.Balance.GetAmount(),
	}, nil
}

func (t *TelegramCore) GetStarsRevenueWithdrawalUrl(chatID, password string, amount int64) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return "", err
	}
	stats, err := api.PaymentsGetStarsRevenueStats(ctx, &tg.PaymentsGetStarsRevenueStatsRequest{Peer: inputPeer})
	if err != nil {
		return "", fmt.Errorf("get revenue stats: %w", err)
	}
	avail := stats.Status.AvailableBalance.GetAmount()
	if avail <= 0 {
		return "", fmt.Errorf("no balance available to withdraw")
	}
	if amount <= 0 || amount > avail {
		amount = avail
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return "", fmt.Errorf("get password params: %w", err)
	}
	srpCheck, err := auth.PasswordHash([]byte(password), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
	if err != nil {
		return "", fmt.Errorf("SRP computation failed: %w", err)
	}
	res, err := api.PaymentsGetStarsRevenueWithdrawalURL(ctx, &tg.PaymentsGetStarsRevenueWithdrawalURLRequest{
		Peer:     inputPeer,
		Amount:   amount,
		Password: srpCheck,
	})
	if err != nil {
		return "", err
	}
	return res.URL, nil
}

func (t *TelegramCore) GetSponsoredInfo(chatID string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return map[string]interface{}{"is_broadcast": false}, nil
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	inputCh := &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}
	requiredLevel := appConfigIntAPI(api, ctx, "channel_restrict_sponsored_level_min", 50)
	isBroadcast := false
	restricted := false
	full, err := api.ChannelsGetFullChannel(ctx, inputCh)
	if err != nil {
		return nil, err
	}
	if cf, ok := full.FullChat.(*tg.ChannelFull); ok {
		restricted = cf.RestrictedSponsored
	}
	for _, c := range full.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			isBroadcast = cc.Broadcast && !cc.Megagroup
		}
	}
	currentLevel := 0
	if isBroadcast {
		if bs, err := api.PremiumGetBoostsStatus(ctx, &tg.InputPeerChannel{ChannelID: ch.ChannelID, AccessHash: hash}); err == nil {
			currentLevel = bs.Level
		}
	}
	return map[string]interface{}{
		"is_broadcast":   isBroadcast,
		"restricted":     restricted,
		"required_level": requiredLevel,
		"current_level":  currentLevel,
	}, nil
}

func (t *TelegramCore) SetRestrictSponsored(chatID string, restricted bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsRestrictSponsoredMessages(ctx, &tg.ChannelsRestrictSponsoredMessagesRequest{
		Channel:    &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Restricted: restricted,
	})
	return err
}

func (t *TelegramCore) GetBroadcastRevenueStats(chatID string) (StarsRevenueResult, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return StarsRevenueResult{}, err
	}
	peer, _ := t.resolvePeer(chatID)
	inputPeer, _ := t.toInputPeer(peer)
	result, err := api.PaymentsGetStarsRevenueStats(ctx, &tg.PaymentsGetStarsRevenueStatsRequest{
		Ton:  true,
		Peer: inputPeer,
	})
	if err != nil {
		return StarsRevenueResult{}, err
	}
	charts := []map[string]interface{}{}
	if c := statsGraphToMap("Top Hours", result.TopHoursGraph, "Bar"); c != nil {
		charts = append(charts, c)
	}
	if c := statsGraphToMap("Revenue", result.RevenueGraph, "StackBar"); c != nil {
		charts = append(charts, c)
	}
	return StarsRevenueResult{
		CurrentBalance:    result.Status.CurrentBalance.GetAmount(),
		AvailableBalance:  result.Status.AvailableBalance.GetAmount(),
		OverallRevenue:    result.Status.OverallRevenue.GetAmount(),
		WithdrawalEnabled: result.Status.WithdrawalEnabled,
		UsdRate:           result.UsdRate,
		Charts:            charts,
	}, nil
}

func (t *TelegramCore) GetBroadcastRevenueTransactions(chatID, offset string, limit int) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 30
	}
	res, err := api.PaymentsGetStarsTransactions(ctx, &tg.PaymentsGetStarsTransactionsRequest{
		Ton:    true,
		Peer:   inputPeer,
		Offset: offset,
		Limit:  limit,
	})
	if err != nil {
		return nil, err
	}
	txns := make([]map[string]interface{}, 0, len(res.History))
	for _, tx := range res.History {
		m := map[string]interface{}{
			"id":          tx.ID,
			"amount":      tx.Amount.GetAmount(),
			"date":        tx.Date,
			"refund":      tx.Refund,
			"pending":     tx.Pending,
			"failed":      tx.Failed,
			"title":       tx.Title,
			"description": tx.Description,
		}
		if url, ok := tx.GetTransactionURL(); ok && url != "" {
			m["transaction_url"] = url
		}
		if td, ok := tx.GetTransactionDate(); ok && td != 0 {
			m["transaction_date"] = td
		}
		switch tx.Peer.(type) {
		case *tg.StarsTransactionPeerFragment:
			m["provider"] = "Fragment"
		case *tg.StarsTransactionPeerAds:
			m["provider"] = "Telegram Ads"
		case *tg.StarsTransactionPeerAppStore:
			m["provider"] = "App Store"
		case *tg.StarsTransactionPeerPlayMarket:
			m["provider"] = "Google Play"
		case *tg.StarsTransactionPeerPremiumBot:
			m["provider"] = "Telegram"
		case *tg.StarsTransactionPeerAPI:
			m["provider"] = "Telegram API"
		}
		txns = append(txns, m)
	}
	return map[string]interface{}{
		"transactions": txns,
		"next_offset":  res.NextOffset,
	}, nil
}

func (t *TelegramCore) GetBroadcastRevenueWithdrawalUrl(chatID, password string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", err
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return "", err
	}
	stats, err := api.PaymentsGetStarsRevenueStats(ctx, &tg.PaymentsGetStarsRevenueStatsRequest{Ton: true, Peer: inputPeer})
	if err != nil {
		return "", fmt.Errorf("get revenue stats: %w", err)
	}
	if stats.Status.AvailableBalance.GetAmount() <= 0 {
		return "", fmt.Errorf("no balance available to withdraw")
	}
	pw, err := api.AccountGetPassword(ctx)
	if err != nil {
		return "", fmt.Errorf("get password params: %w", err)
	}
	srpCheck, err := auth.PasswordHash([]byte(password), pw.SRPID, pw.SRPB, pw.SecureRandom, pw.CurrentAlgo)
	if err != nil {
		return "", fmt.Errorf("SRP computation failed: %w", err)
	}
	res, err := api.PaymentsGetStarsRevenueWithdrawalURL(ctx, &tg.PaymentsGetStarsRevenueWithdrawalURLRequest{
		Ton:      true,
		Peer:     inputPeer,
		Amount:   0,
		Password: srpCheck,
	})
	if err != nil {
		return "", err
	}
	return res.URL, nil
}

func (t *TelegramCore) GetPremiumStatus() (premiumPossible bool, premiumCanBuy bool, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, false, err
	}
	blocked := false
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err == nil {
		if cfg, ok := result.(*tg.HelpAppConfig); ok {
			if jv := cfg.Config; jv != nil {
				if obj, ok2 := jv.(*tg.JSONObject); ok2 {
					for _, kv := range obj.Value {
						if kv.Key == "premium_purchase_blocked" {
							if b, ok3 := kv.Value.(*tg.JSONBool); ok3 {
								blocked = b.Value
							}
						}
					}
				}
			}
		}
	}
	premiumPossible = !blocked
	selfPremium := false
	users, err2 := api.UsersGetUsers(ctx, []tg.InputUserClass{&tg.InputUserSelf{}})
	if err2 == nil && len(users) > 0 {
		if u, ok := users[0].(*tg.User); ok {
			selfPremium = u.Premium
		}
	}
	premiumCanBuy = premiumPossible && !selfPremium
	return premiumPossible, premiumCanBuy, nil
}

func (t *TelegramCore) GetDialogFiltersEnabled() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return false, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return false, nil
	}
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				if kv.Key == "dialog_filters_enabled" {
					if b, ok3 := kv.Value.(*tg.JSONBool); ok3 {
						return b.Value, nil
					}
				}
			}
		}
	}
	return false, nil
}

func (t *TelegramCore) GetFolderLimits() (freeLimit, premiumLimit int, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 10, 20, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return 10, 20, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return 10, 20, nil
	}
	freeLimit, premiumLimit = 10, 20
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				switch kv.Key {
				case "dialog_filters_limit_default":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						freeLimit = int(n.Value)
					}
				case "dialog_filters_limit_premium":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						premiumLimit = int(n.Value)
					}
				}
			}
		}
	}
	return freeLimit, premiumLimit, nil
}

func (t *TelegramCore) GetAllFolderLimits() (map[string]int, error) {
	limits := map[string]int{
		"free_limit": 10, "premium_limit": 20,
		"chats_per_folder_free": 100, "chats_per_folder_premium": 200,
		"shared_folders_free": 2, "shared_folders_premium": 20,
		"links_per_folder_free": 3, "links_per_folder_premium": 20,
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return limits, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return limits, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return limits, nil
	}
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
					switch kv.Key {
					case "dialog_filters_limit_default":
						limits["free_limit"] = int(n.Value)
					case "dialog_filters_limit_premium":
						limits["premium_limit"] = int(n.Value)
					case "dialog_filters_chats_limit_default":
						limits["chats_per_folder_free"] = int(n.Value)
					case "dialog_filters_chats_limit_premium":
						limits["chats_per_folder_premium"] = int(n.Value)
					case "chatlist_invites_limit_default":
						limits["links_per_folder_free"] = int(n.Value)
					case "chatlist_invites_limit_premium":
						limits["links_per_folder_premium"] = int(n.Value)
					case "chatlists_joined_limit_default":
						limits["shared_folders_free"] = int(n.Value)
					case "chatlists_joined_limit_premium":
						limits["shared_folders_premium"] = int(n.Value)
					}
				}
			}
		}
	}
	return limits, nil
}

func (t *TelegramCore) GetPublicLinksLimits() (freeLimit, premiumLimit int, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 10, 20, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return 10, 20, nil
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return 10, 20, nil
	}
	freeLimit, premiumLimit = 10, 20
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				switch kv.Key {
				case "channels_public_limit_default":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						freeLimit = int(n.Value)
					}
				case "channels_public_limit_premium":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						premiumLimit = int(n.Value)
					}
				}
			}
		}
	}
	return freeLimit, premiumLimit, nil
}

type ForumTopicIconInfo struct {
	DocumentID int64  `json:"document_id"`
	Emoji      string `json:"emoji"`
}

func (t *TelegramCore) GetForumTopicDefaultIcons() ([]ForumTopicIconInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetStickerSet(ctx, &tg.MessagesGetStickerSetRequest{
		Stickerset: &tg.InputStickerSetEmojiDefaultTopicIcons{},
	})
	if err != nil {
		return nil, fmt.Errorf("get topic icons: %w", err)
	}
	stickerSet, ok := result.(*tg.MessagesStickerSet)
	if !ok {
		return nil, ErrNotFound
	}
	emojiByDocID := make(map[int64]string)
	for _, pack := range stickerSet.Packs {
		for _, docID := range pack.Documents {
			emojiByDocID[docID] = pack.Emoticon
		}
	}
	var icons []ForumTopicIconInfo
	for _, doc := range stickerSet.Documents {
		if d, ok := doc.(*tg.Document); ok {
			t.cacheFileInfo(d.ID, d.AccessHash, d.FileReference)
			icons = append(icons, ForumTopicIconInfo{
				DocumentID: d.ID,
				Emoji:      emojiByDocID[d.ID],
			})
		}
	}
	return icons, nil
}

type ChannelUsernameInfo struct {
	Username string `json:"username"`
	Active   bool   `json:"active"`
	Editable bool   `json:"editable"`
}

func (t *TelegramCore) GetChannelUsernames(chatID string) ([]ChannelUsernameInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.ChannelsGetFullChannel(ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	if err != nil {
		return nil, err
	}
	t.cacheEntities(result.Users, result.Chats)
	var out []ChannelUsernameInfo
	for _, c := range result.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			if unames, ok2 := cc.GetUsernames(); ok2 {
				for _, u := range unames {
					out = append(out, ChannelUsernameInfo{
						Username: u.Username,
						Active:   u.Active,
						Editable: u.Editable,
					})
				}
			} else if u, ok2 := cc.GetUsername(); ok2 && u != "" {
				out = append(out, ChannelUsernameInfo{Username: u, Active: true, Editable: true})
			}
			break
		}
	}
	return out, nil
}

func (t *TelegramCore) ToggleChannelUsername(chatID, username string, active bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return false, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return false, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	return api.ChannelsToggleUsername(ctx, &tg.ChannelsToggleUsernameRequest{
		Channel:  &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Username: username,
		Active:   active,
	})
}

func (t *TelegramCore) ReorderChannelUsernames(chatID string, order []string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return false, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return false, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	return api.ChannelsReorderUsernames(ctx, &tg.ChannelsReorderUsernamesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Order:   order,
	})
}

func (t *TelegramCore) GetPaidMessagesConfig() (maxStars int64, commissionPermille int32, withdrawRate float64, err error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, 0, 0, err
	}
	result, err := api.HelpGetAppConfig(ctx, 0)
	if err != nil {
		return 0, 0, 0, err
	}
	cfg, ok := result.(*tg.HelpAppConfig)
	if !ok {
		return 10000, 150, 0.013, nil
	}
	maxStars = 10000
	commissionPermille = 150
	withdrawRate = 0.013
	if jv := cfg.Config; jv != nil {
		if obj, ok2 := jv.(*tg.JSONObject); ok2 {
			for _, kv := range obj.Value {
				switch kv.Key {
				case "paid_message_stars_max":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						maxStars = int64(n.Value)
					}
				case "paid_message_commission_permille":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						commissionPermille = int32(n.Value)
					}
				case "stars_usd_withdraw_rate_x1000":
					if n, ok3 := kv.Value.(*tg.JSONNumber); ok3 {
						withdrawRate = n.Value / 1000.0
					}
				}
			}
		}
	}
	return maxStars, commissionPermille, withdrawRate, nil
}

func (t *TelegramCore) GetReactionsList(chatID, msgID string, limit int) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return 0, err
	}
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesGetMessageReactionsList(t.ctx, &tg.MessagesGetMessageReactionsListRequest{
		Peer: inputPeer, ID: id, Limit: limit,
	})
	if err != nil {
		return 0, err
	}
	return result.Count, nil
}

func (t *TelegramCore) GetSearchCalendar(chatID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	result, err := t.api.MessagesGetSearchResultsCalendar(t.ctx, &tg.MessagesGetSearchResultsCalendarRequest{
		Peer: inputPeer, Filter: &tg.InputMessagesFilterPhotos{},
	})
	if err != nil {
		return 0, err
	}
	return len(result.Periods), nil
}

type uploadProgress struct {
	callback func(sent, total int64)
	total    int64
}

func (p *uploadProgress) Chunk(_ context.Context, state uploader.ProgressState) error {
	p.callback(int64(state.Uploaded), p.total)
	return nil
}

func (t *TelegramCore) SendMultiMedia(chatID string, mediaInputs []tg.InputSingleMedia) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	_, err = t.api.MessagesSendMultiMedia(t.ctx, &tg.MessagesSendMultiMediaRequest{
		Peer: inputPeer, MultiMedia: mediaInputs,
	})
	if err != nil {
		return 0, err
	}
	return len(mediaInputs), nil
}

func (t *TelegramCore) GetPollVotes(chatID string, msgID int, limit int) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	if limit <= 0 {
		limit = 20
	}
	result, err := t.api.MessagesGetPollVotes(t.ctx, &tg.MessagesGetPollVotesRequest{
		Peer: inputPeer, ID: msgID, Limit: limit,
	})
	if err != nil {
		return 0, err
	}
	return result.Count, nil
}

func (t *TelegramCore) DeleteChatHistory(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesDeleteHistory(t.ctx, &tg.MessagesDeleteHistoryRequest{
		Peer: inputPeer, MaxID: 0,
	})
	return err
}

func (t *TelegramCore) DeleteChatHistoryWithRevoke(chatID string, revoke bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesDeleteHistory(t.ctx, &tg.MessagesDeleteHistoryRequest{
		Peer: inputPeer, MaxID: 0, Revoke: revoke,
	})
	return err
}

func (t *TelegramCore) ImportChatInvite(hash string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesImportChatInvite(ctx, hash)
	return err
}

func (t *TelegramCore) GetFullChatParticipantsCount(chatID string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return 0, err
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return 0, fmt.Errorf("not a basic chat")
	}
	result, err := api.MessagesGetFullChat(ctx, chat.ChatID)
	if err != nil {
		return 0, err
	}
	t.cacheEntities(result.Users, result.Chats)
	if cf, ok := result.FullChat.(*tg.ChatFull); ok {
		if cp, ok := cf.Participants.(*tg.ChatParticipants); ok {
			return len(cp.Participants), nil
		}
	}
	return len(result.Users), nil
}

func (t *TelegramCore) InviteToChannel(chatID string, userIDs []string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return 0, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return 0, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	var users []tg.InputUserClass
	for _, uid := range userIDs {
		id, err := tgUserID(uid)
		if err != nil {
			return 0, err
		}
		uhash := t.getCachedUserHash(id)
		users = append(users, &tg.InputUser{UserID: id, AccessHash: uhash})
	}
	result, err := api.ChannelsInviteToChannel(ctx, &tg.ChannelsInviteToChannelRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Users:   users,
	})
	if err != nil {
		return 0, err
	}
	return len(userIDs) - len(result.MissingInvitees), nil
}

func (t *TelegramCore) AddChatUser(chatID string, userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return fmt.Errorf("not a basic chat")
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.MessagesAddChatUser(ctx, &tg.MessagesAddChatUserRequest{
		ChatID:   chat.ChatID,
		UserID:   &tg.InputUser{UserID: uid, AccessHash: uhash},
		FwdLimit: 100,
	})
	return err
}

func (t *TelegramCore) DeleteChatUser(chatID string, userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return fmt.Errorf("not a basic chat")
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.MessagesDeleteChatUser(ctx, &tg.MessagesDeleteChatUserRequest{
		ChatID: chat.ChatID,
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
	})
	return err
}

func (t *TelegramCore) EditChannelPhoto(chatID string, photoData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("photo.png", io.NopCloser(bytes.NewReader(photoData)), int64(len(photoData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	_, err = api.ChannelsEditPhoto(ctx, &tg.ChannelsEditPhotoRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Photo:   &tg.InputChatUploadedPhoto{File: upload},
	})
	return err
}

func (t *TelegramCore) EditChannelVideoPhoto(chatID string, videoData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("video.mp4", io.NopCloser(bytes.NewReader(videoData)), int64(len(videoData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	photo := &tg.InputChatUploadedPhoto{}
	photo.SetVideo(upload)
	photo.SetVideoStartTs(0.0)
	_, err = api.ChannelsEditPhoto(ctx, &tg.ChannelsEditPhotoRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Photo:   photo,
	})
	return err
}

func (t *TelegramCore) CreateForumTopic(chatID string, title string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil {
		return 0, fmt.Errorf("generate random id: %w", err)
	}
	randomID := int64(binary.LittleEndian.Uint64(rb))
	result, err := t.api.MessagesCreateForumTopic(t.ctx, &tg.MessagesCreateForumTopicRequest{
		Peer: inputPeer, Title: title, RandomID: randomID,
	})
	if err != nil {
		return 0, err
	}
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

func (t *TelegramCore) PinForumTopic(chatID string, topicID int, pinned bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesUpdatePinnedForumTopic(t.ctx, &tg.MessagesUpdatePinnedForumTopicRequest{
		Peer: inputPeer, TopicID: topicID, Pinned: pinned,
	})
	return err
}

func (t *TelegramCore) ReorderPinnedForumTopics(chatID string, topicIDs []int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = api.MessagesReorderPinnedForumTopics(ctx, &tg.MessagesReorderPinnedForumTopicsRequest{
		Peer: inputPeer, Order: topicIDs, Force: true,
	})
	return err
}

func (t *TelegramCore) ToggleViewForumAsMessages(chatID string, enabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsToggleViewForumAsMessages(ctx, &tg.ChannelsToggleViewForumAsMessagesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}, Enabled: enabled,
	})
	return err
}

func (t *TelegramCore) ToggleForumTopicClosed(chatID string, topicID int, closed bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	req := &tg.MessagesEditForumTopicRequest{Peer: inputPeer, TopicID: topicID}
	req.SetClosed(closed)
	_, err = t.api.MessagesEditForumTopic(t.ctx, req)
	return err
}

func (t *TelegramCore) ToggleGeneralTopicHidden(chatID string, hidden bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	req := &tg.MessagesEditForumTopicRequest{Peer: inputPeer, TopicID: 1}
	req.SetHidden(hidden)
	_, err = t.api.MessagesEditForumTopic(t.ctx, req)
	return err
}

func (t *TelegramCore) DeleteTopicHistory(chatID string, topicID int) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesDeleteTopicHistory(t.ctx, &tg.MessagesDeleteTopicHistoryRequest{
		Peer: inputPeer, TopMsgID: topicID,
	})
	return err
}

func (t *TelegramCore) ReorderDialogFilters(ids []int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesUpdateDialogFiltersOrder(ctx, ids)
	return err
}

func (t *TelegramCore) DeleteContacts(userIDs []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	var users []tg.InputUserClass
	for _, uid := range userIDs {
		id, err := tgUserID(uid)
		if err != nil {
			return err
		}
		uhash := t.getCachedUserHash(id)
		users = append(users, &tg.InputUser{UserID: id, AccessHash: uhash})
	}
	_, err = api.ContactsDeleteContacts(ctx, users)
	return err
}

func (t *TelegramCore) ImportContacts(contacts []tg.InputPhoneContact) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.ContactsImportContacts(ctx, contacts)
	if err != nil {
		return 0, err
	}
	return len(result.Imported), nil
}

func (t *TelegramCore) UpdateUsername(username string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountUpdateUsername(ctx, username)
	return err
}

func (t *TelegramCore) GetChatUsername(chatID string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return "", err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return "", nil
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.ChannelsGetFullChannel(ctx, &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash})
	if err != nil {
		return "", err
	}
	for _, c := range result.Chats {
		if cc, ok := c.(*tg.Channel); ok && cc.ID == ch.ChannelID {
			return cc.Username, nil
		}
	}
	return "", nil
}

func (t *TelegramCore) UpdateChannelUsername(chatID, username string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	_, err = api.ChannelsUpdateUsername(ctx, &tg.ChannelsUpdateUsernameRequest{
		Channel:  &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Username: username,
	})
	return err
}

func (t *TelegramCore) CheckChannelUsername(chatID, username string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return false, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return false, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	return api.ChannelsCheckUsername(ctx, &tg.ChannelsCheckUsernameRequest{
		Channel:  &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Username: username,
	})
}

func (t *TelegramCore) UpdateBirthday(day, month, year int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.AccountUpdateBirthdayRequest{}
	bday := tg.Birthday{Day: day, Month: month}
	if year > 0 {
		bday.SetYear(year)
	}
	req.SetBirthday(bday)
	_, err = api.AccountUpdateBirthday(ctx, req)
	return err
}

func (t *TelegramCore) GetChannelDifference(chatID string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return 0, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return 0, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	result, err := api.UpdatesGetChannelDifference(ctx, &tg.UpdatesGetChannelDifferenceRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Filter:  &tg.ChannelMessagesFilterEmpty{},
		Pts:     1, Limit: 100,
	})
	if err != nil {
		return 0, err
	}
	if diff, ok := result.(*tg.UpdatesChannelDifference); ok {
		return len(diff.NewMessages) + len(diff.OtherUpdates), nil
	}
	return 0, nil
}

func (t *TelegramCore) SendInlineBotResult(chatID string, queryID int64, resultID string) (int, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil {
		return 0, fmt.Errorf("generate random id: %w", err)
	}
	randomID := int64(binary.LittleEndian.Uint64(rb))
	result, err := t.api.MessagesSendInlineBotResult(t.ctx, &tg.MessagesSendInlineBotResultRequest{
		Peer: inputPeer, QueryID: queryID, ID: resultID, RandomID: randomID,
	})
	if err != nil {
		return 0, err
	}
	switch u := result.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			if nm, ok := update.(*tg.UpdateNewMessage); ok {
				return nm.Message.GetID(), nil
			}
			if nm, ok := update.(*tg.UpdateNewChannelMessage); ok {
				return nm.Message.GetID(), nil
			}
		}
	}
	return 0, nil
}

func (t *TelegramCore) storyPrivacyRules(opts StoryPostOptions) []tg.InputPrivacyRuleClass {
	var rules []tg.InputPrivacyRuleClass
	switch opts.Privacy {
	case "contacts":
		rules = append(rules, &tg.InputPrivacyValueAllowContacts{})
		if len(opts.ExcludedContactIDs) > 0 {
			users := make([]tg.InputUserClass, 0, len(opts.ExcludedContactIDs))
			for _, uid := range opts.ExcludedContactIDs {
				id, parseErr := strconv.ParseInt(uid, 10, 64)
				if parseErr != nil {
					continue
				}
				users = append(users, &tg.InputUser{UserID: id})
			}
			rules = append(rules, &tg.InputPrivacyValueDisallowUsers{Users: users})
		}
	case "closeFriends":
		rules = append(rules, &tg.InputPrivacyValueAllowCloseFriends{})
	case "selectedContacts":
		if len(opts.SelectedContactIDs) > 0 {
			users := make([]tg.InputUserClass, 0, len(opts.SelectedContactIDs))
			for _, uid := range opts.SelectedContactIDs {
				id, parseErr := strconv.ParseInt(uid, 10, 64)
				if parseErr != nil {
					continue
				}
				users = append(users, &tg.InputUser{UserID: id})
			}
			rules = append(rules, &tg.InputPrivacyValueAllowUsers{Users: users})
		} else {
			rules = append(rules, &tg.InputPrivacyValueAllowContacts{})
		}
	default:
		rules = append(rules, &tg.InputPrivacyValueAllowAll{})
	}
	return rules
}

func (t *TelegramCore) sendStoryCommon(api *tg.Client, ctx context.Context, req *tg.StoriesSendStoryRequest) (int, error) {
	result, err := api.StoriesSendStory(ctx, req)
	if err != nil {
		return 0, err
	}
	switch v := result.(type) {
	case *tg.Updates:
		for _, update := range v.Updates {
			if su, ok := update.(*tg.UpdateStory); ok {
				if si, ok := su.Story.(*tg.StoryItem); ok {
					return si.ID, nil
				}
			}
		}
	}
	return 0, nil
}

func (t *TelegramCore) SendStoryWithPhoto(text string, photoData []byte, opts StoryPostOptions) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("story.png", io.NopCloser(bytes.NewReader(photoData)), int64(len(photoData))))
	if err != nil {
		return 0, fmt.Errorf("upload: %w", err)
	}
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil {
		return 0, err
	}
	randomID := int64(binary.LittleEndian.Uint64(rb))

	req := &tg.StoriesSendStoryRequest{
		Peer:         &tg.InputPeerSelf{},
		Media:        &tg.InputMediaUploadedPhoto{File: upload},
		RandomID:     randomID,
		PrivacyRules: t.storyPrivacyRules(opts),
	}
	if text != "" {
		req.SetCaption(text)
	}
	if opts.DurationHours > 0 {
		req.SetPeriod(opts.DurationHours * 3600)
	}
	if opts.SaveToProfile {
		req.SetPinned(true)
	}
	if !opts.AllowSharing {
		req.SetNoforwards(true)
	}
	return t.sendStoryCommon(api, ctx, req)
}

func trimVideoWithFFmpeg(videoPath string, trimStart, trimEnd float64) (string, error) {
	probeCmd := exec.Command("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", videoPath)
	probeOut, err := probeCmd.Output()
	if err != nil {
		return "", fmt.Errorf("ffprobe: %w", err)
	}
	durStr := strings.TrimSpace(string(probeOut))
	duration, err := strconv.ParseFloat(durStr, 64)
	if err != nil || duration <= 0 {
		return "", fmt.Errorf("parse duration %q: %w", durStr, err)
	}
	startSec := duration * trimStart
	endSec := duration * trimEnd
	storyDir, err := utils.PrivateCacheDir("telegram-story")
	if err != nil {
		return "", err
	}
	outPath := filepath.Join(storyDir, fmt.Sprintf("story_trimmed_%d.mp4", time.Now().UnixNano()))
	cmd := exec.Command("ffmpeg", "-y",
		"-ss", fmt.Sprintf("%.3f", startSec),
		"-to", fmt.Sprintf("%.3f", endSec),
		"-i", videoPath,
		"-c", "copy",
		"-avoid_negative_ts", "make_zero",
		outPath)
	if err := cmd.Run(); err != nil {
		os.Remove(outPath)
		return "", fmt.Errorf("ffmpeg trim: %w", err)
	}
	return outPath, nil
}

func overlayVideoWithFFmpeg(videoPath string, overlayPNG []byte) (string, error) {
	storyDir, err := utils.PrivateCacheDir("telegram-story")
	if err != nil {
		return "", err
	}
	overlayPath := filepath.Join(storyDir, fmt.Sprintf("story_overlay_%d.png", time.Now().UnixNano()))
	if err := os.WriteFile(overlayPath, overlayPNG, 0644); err != nil {
		return "", err
	}
	defer os.Remove(overlayPath)

	outPath := filepath.Join(storyDir, fmt.Sprintf("story_composited_%d.mp4", time.Now().UnixNano()))
	cmd := exec.Command("ffmpeg", "-y",
		"-i", videoPath,
		"-i", overlayPath,
		"-filter_complex", "[1:v]scale=main_w:main_h[ovr];[0:v][ovr]overlay=0:0",
		"-c:a", "copy",
		"-shortest",
		outPath)
	if err := cmd.Run(); err != nil {
		os.Remove(outPath)
		return "", fmt.Errorf("ffmpeg overlay: %w", err)
	}
	return outPath, nil
}

func (t *TelegramCore) SendStoryWithVideoFile(text string, videoPath string, opts StoryPostOptions) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}

	actualVideoPath := videoPath
	if opts.TrimStart > 0.0 || opts.TrimEnd < 1.0 {
		trimmed, trimErr := trimVideoWithFFmpeg(videoPath, opts.TrimStart, opts.TrimEnd)
		if trimErr == nil {
			defer os.Remove(trimmed)
			actualVideoPath = trimmed
		}
	}
	overlayApplied := false
	if len(opts.OverlayData) > 0 {
		composited, compErr := overlayVideoWithFFmpeg(actualVideoPath, opts.OverlayData)
		if compErr == nil {
			defer os.Remove(composited)
			actualVideoPath = composited
			overlayApplied = true
		}
	}

	videoData, err := os.ReadFile(actualVideoPath)
	if err != nil {
		return 0, fmt.Errorf("read video: %w", err)
	}

	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload(filepath.Base(videoPath), io.NopCloser(bytes.NewReader(videoData)), int64(len(videoData))))
	if err != nil {
		return 0, fmt.Errorf("upload video: %w", err)
	}

	media := &tg.InputMediaUploadedDocument{
		File:     upload,
		MimeType: "video/mp4",
		Attributes: []tg.DocumentAttributeClass{
			&tg.DocumentAttributeVideo{
				SupportsStreaming: true,
			},
		},
	}

	if len(opts.OverlayData) > 0 && !overlayApplied {
		thumbUpload, thumbErr := u.Upload(ctx, uploader.NewUpload("thumb.png", io.NopCloser(bytes.NewReader(opts.OverlayData)), int64(len(opts.OverlayData))))
		if thumbErr == nil {
			media.SetThumb(thumbUpload)
		}
	}

	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil {
		return 0, err
	}
	randomID := int64(binary.LittleEndian.Uint64(rb))

	req := &tg.StoriesSendStoryRequest{
		Peer:         &tg.InputPeerSelf{},
		Media:        media,
		RandomID:     randomID,
		PrivacyRules: t.storyPrivacyRules(opts),
	}
	if text != "" {
		req.SetCaption(text)
	}
	if opts.DurationHours > 0 {
		req.SetPeriod(opts.DurationHours * 3600)
	}
	if opts.SaveToProfile {
		req.SetPinned(true)
	}
	if !opts.AllowSharing {
		req.SetNoforwards(true)
	}
	return t.sendStoryCommon(api, ctx, req)
}

func (t *TelegramCore) SendStory(text string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	rb := make([]byte, 8)
	if _, err := rand.Read(rb); err != nil {
		return 0, fmt.Errorf("generate random id: %w", err)
	}
	randomID := int64(binary.LittleEndian.Uint64(rb))
	req := &tg.StoriesSendStoryRequest{
		Peer:         &tg.InputPeerSelf{},
		Media:        &tg.InputMediaEmpty{},
		RandomID:     randomID,
		PrivacyRules: []tg.InputPrivacyRuleClass{&tg.InputPrivacyValueAllowAll{}},
	}
	if text != "" {
		req.SetCaption(text)
	}
	result, err := api.StoriesSendStory(ctx, req)
	if err != nil {
		return 0, err
	}
	switch u := result.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			if su, ok := update.(*tg.UpdateStory); ok {
				if si, ok := su.Story.(*tg.StoryItem); ok {
					return si.ID, nil
				}
			}
		}
	}
	return 0, nil
}

func (t *TelegramCore) DeleteStories(ids []int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.StoriesDeleteStories(ctx, &tg.StoriesDeleteStoriesRequest{
		Peer: &tg.InputPeerSelf{}, ID: ids,
	})
	return err
}

func (t *TelegramCore) GetStoryViews(ids []int) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.StoriesGetStoriesViews(ctx, &tg.StoriesGetStoriesViewsRequest{
		Peer: &tg.InputPeerSelf{}, ID: ids,
	})
	if err != nil {
		return 0, err
	}
	total := 0
	for _, v := range result.Views {
		total += v.ViewsCount
	}
	return total, nil
}

func (t *TelegramCore) ReactToStory(userID string, storyID int, emoji string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(userID)
	if err != nil {
		return fmt.Errorf("resolve peer: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return fmt.Errorf("input peer: %w", err)
	}
	var reaction tg.ReactionClass
	if emoji == "" {
		reaction = &tg.ReactionEmpty{}
	} else {
		reaction = &tg.ReactionEmoji{Emoticon: emoji}
	}
	_, err = api.StoriesSendReaction(ctx, &tg.StoriesSendReactionRequest{
		Peer:     inputPeer,
		StoryID:  storyID,
		Reaction: reaction,
	})
	return err
}

func (t *TelegramCore) ExportStoryLink(peerID string, storyID int) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	peer, err := t.resolvePeer(peerID)
	if err != nil {
		return "", fmt.Errorf("resolve peer: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return "", fmt.Errorf("input peer: %w", err)
	}
	res, err := api.StoriesExportStoryLink(ctx, &tg.StoriesExportStoryLinkRequest{
		Peer: inputPeer,
		ID:   storyID,
	})
	if err != nil {
		return "", fmt.Errorf("export story link: %w", err)
	}
	return res.Link, nil
}

func (t *TelegramCore) GetPinnedStories(userID string) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return 0, err
	}
	uhash := t.getCachedUserHash(uid)
	result, err := api.StoriesGetPinnedStories(ctx, &tg.StoriesGetPinnedStoriesRequest{
		Peer:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		Limit: 100,
	})
	if err != nil {
		return 0, err
	}
	return len(result.Stories), nil
}

func (t *TelegramCore) SetChatWallpaper(chatID string, wallpaper WallpaperInfo, forBoth bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	if wallpaper.ID == 0 && wallpaper.DocID == 0 {
		return fmt.Errorf("wallpaper has no reference")
	}
	input := tg.InputWallPaperClass(&tg.InputWallPaper{
		ID:         wallpaper.ID,
		AccessHash: wallpaper.AccessHash,
	})
	_, err = t.api.MessagesSetChatWallPaper(t.ctx, &tg.MessagesSetChatWallPaperRequest{
		Peer:      inputPeer,
		Wallpaper: input,
		Settings:  WallpaperSettingsFromInfo(wallpaper),
		ForBoth:   forBoth,
	})
	return err
}

func (t *TelegramCore) RevertChatWallpaper(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesSetChatWallPaper(t.ctx, &tg.MessagesSetChatWallPaperRequest{
		Peer:   inputPeer,
		Revert: true,
	})
	return err
}

func (t *TelegramCore) UploadChatWallpaper(data []byte, mime string, blurred bool) (WallpaperInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return WallpaperInfo{}, err
	}
	if len(data) == 0 {
		return WallpaperInfo{}, fmt.Errorf("empty wallpaper data")
	}
	if mime == "" {
		mime = http.DetectContentType(data)
	}
	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload("wallpaper.jpg", bytes.NewReader(data), int64(len(data))))
	if err != nil {
		return WallpaperInfo{}, fmt.Errorf("upload: %w", err)
	}
	settings := tg.WallPaperSettings{Blur: blurred}
	resp, err := api.AccountUploadWallPaper(ctx, &tg.AccountUploadWallPaperRequest{
		ForChat:  true,
		File:     upload,
		MimeType: mime,
		Settings: settings,
	})
	if err != nil {
		return WallpaperInfo{}, err
	}
	if _, ok := resp.(*tg.WallPaper); !ok {
		return WallpaperInfo{}, fmt.Errorf("unexpected upload response")
	}
	return t.WallpaperFromWire(resp), nil
}

func (t *TelegramCore) HideChatJoinRequest(chatID string, userID string, approved bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = t.api.MessagesHideChatJoinRequest(t.ctx, &tg.MessagesHideChatJoinRequestRequest{
		Peer: inputPeer, Approved: approved,
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
	})
	return err
}

func (t *TelegramCore) MigrateChat(chatID string) (int64, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return 0, err
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return 0, fmt.Errorf("not a basic chat")
	}
	result, err := api.MessagesMigrateChat(ctx, chat.ChatID)
	if err != nil {
		return 0, err
	}
	switch u := result.(type) {
	case *tg.Updates:
		for _, c := range u.Chats {
			if ch, ok := c.(*tg.Channel); ok {
				return ch.ID, nil
			}
		}
	}
	return 0, fmt.Errorf("supergroup ID not found in migration result")
}

func (t *TelegramCore) ExportChatlistInvite(folderID int, title string, peerIDs []string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	var peers []tg.InputPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil {
			continue
		}
		ip, _ := t.toInputPeer(peer)
		peers = append(peers, ip)
	}
	result, err := api.ChatlistsExportChatlistInvite(ctx, &tg.ChatlistsExportChatlistInviteRequest{
		Chatlist: tg.InputChatlistDialogFilter{FilterID: folderID},
		Title:    title,
		Peers:    peers,
	})
	if err != nil {
		return "", err
	}
	return result.Invite.URL, nil
}

func (t *TelegramCore) GetChatlistInvites(folderID int) (int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	result, err := api.ChatlistsGetExportedInvites(ctx, tg.InputChatlistDialogFilter{FilterID: folderID})
	if err != nil {
		return 0, err
	}
	return len(result.Invites), nil
}

func (t *TelegramCore) GetFolderInviteLinks(folderID int) ([]ChatlistInviteLink, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.ChatlistsGetExportedInvites(ctx, tg.InputChatlistDialogFilter{FilterID: folderID})
	if err != nil {
		return nil, err
	}
	var links []ChatlistInviteLink
	for _, inv := range result.Invites {
		slug := inv.URL
		for i := len(slug) - 1; i >= 0; i-- {
			if slug[i] == '/' || slug[i] == '+' {
				slug = slug[i+1:]
				break
			}
		}
		peerIDs := make([]string, 0, len(inv.Peers))
		for _, p := range inv.Peers {
			if id := peerToID(p); id != "" {
				peerIDs = append(peerIDs, id)
			}
		}
		links = append(links, ChatlistInviteLink{
			URL:       inv.URL,
			Title:     inv.Title,
			PeerCount: len(inv.Peers),
			Slug:      slug,
			PeerIDs:   peerIDs,
		})
	}
	return links, nil
}

func (t *TelegramCore) EditChatlistInvite(folderID int, slug string, peerIDs []string, title string) (ChatlistInviteLink, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return ChatlistInviteLink{}, err
	}
	var peers []tg.InputPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil {
			continue
		}
		ip, _ := t.toInputPeer(peer)
		peers = append(peers, ip)
	}
	req := &tg.ChatlistsEditExportedInviteRequest{
		Chatlist: tg.InputChatlistDialogFilter{FilterID: folderID},
		Slug:     slug,
		Peers:    peers,
	}
	if title != "" {
		req.SetTitle(title)
	}
	result, err := api.ChatlistsEditExportedInvite(ctx, req)
	if err != nil {
		return ChatlistInviteLink{}, err
	}
	outPeerIDs := make([]string, 0, len(result.Peers))
	for _, p := range result.Peers {
		if id := peerToID(p); id != "" {
			outPeerIDs = append(outPeerIDs, id)
		}
	}
	return ChatlistInviteLink{
		URL:       result.URL,
		Title:     result.Title,
		PeerCount: len(result.Peers),
		Slug:      slug,
		PeerIDs:   outPeerIDs,
	}, nil
}

func (t *TelegramCore) DeleteChatlistInvite(folderID int, slug string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.ChatlistsDeleteExportedInvite(ctx, &tg.ChatlistsDeleteExportedInviteRequest{
		Chatlist: tg.InputChatlistDialogFilter{FilterID: folderID},
		Slug:     slug,
	})
	return err
}

func (t *TelegramCore) GetLeaveChatlistSuggestions(folderID int) ([]string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peers, err := api.ChatlistsGetLeaveChatlistSuggestions(ctx, tg.InputChatlistDialogFilter{FilterID: folderID})
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(peers))
	for _, p := range peers {
		if id := peerToID(p); id != "" {
			ids = append(ids, id)
		}
	}
	return ids, nil
}

func (t *TelegramCore) LeaveChatlistFolder(folderID int, peerIDs []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	var peers []tg.InputPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil {
			continue
		}
		ip, _ := t.toInputPeer(peer)
		peers = append(peers, ip)
	}
	_, err = api.ChatlistsLeaveChatlist(ctx, &tg.ChatlistsLeaveChatlistRequest{
		Chatlist: tg.InputChatlistDialogFilter{FilterID: folderID},
		Peers:    peers,
	})
	return err
}

func (t *TelegramCore) JoinChatlistInvite(slug string, peerIDs []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	var peers []tg.InputPeerClass
	for _, pid := range peerIDs {
		peer, err := t.resolvePeer(pid)
		if err != nil {
			continue
		}
		ip, _ := t.toInputPeer(peer)
		peers = append(peers, ip)
	}
	_, err = api.ChatlistsJoinChatlistInvite(ctx, &tg.ChatlistsJoinChatlistInviteRequest{
		Slug: slug, Peers: peers,
	})
	return err
}

func (t *TelegramCore) AccountAcceptAuthorization(request *tg.AccountAcceptAuthorizationRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountAcceptAuthorization(ctx, request)
}

func (t *TelegramCore) AccountCancelPasswordEmail() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountCancelPasswordEmail(ctx)
}

func (t *TelegramCore) AccountChangeAuthorizationSettings(request *tg.AccountChangeAuthorizationSettingsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountChangeAuthorizationSettings(ctx, request)
}

func (t *TelegramCore) AccountChangePhone(request *tg.AccountChangePhoneRequest) (tg.UserClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountChangePhone(ctx, request)
}

func (t *TelegramCore) AccountCheckUsername(username string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountCheckUsername(ctx, username)
}

func (t *TelegramCore) GetAccountUsernames() ([]ChannelUsernameInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	full, err := api.UsersGetFullUser(ctx, &tg.InputUserSelf{})
	if err != nil {
		return nil, err
	}
	var out []ChannelUsernameInfo
	for _, u := range full.Users {
		if user, ok := u.(*tg.User); ok && user.Self {
			if unames, ok2 := user.GetUsernames(); ok2 {
				for _, un := range unames {
					out = append(out, ChannelUsernameInfo{
						Username: un.Username,
						Active:   un.Active,
						Editable: un.Editable,
					})
				}
			} else if uname, ok2 := user.GetUsername(); ok2 && uname != "" {
				out = append(out, ChannelUsernameInfo{Username: uname, Active: true, Editable: true})
			}
			break
		}
	}
	return out, nil
}

func (t *TelegramCore) ToggleAccountUsername(username string, active bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountToggleUsername(ctx, &tg.AccountToggleUsernameRequest{
		Username: username,
		Active:   active,
	})
}

func (t *TelegramCore) ReorderAccountUsernames(order []string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountReorderUsernames(ctx, order)
}

func (t *TelegramCore) AccountClearRecentEmojiStatuses() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountClearRecentEmojiStatuses(ctx)
}

func (t *TelegramCore) AccountConfirmPasswordEmail(code string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountConfirmPasswordEmail(ctx, code)
}

func (t *TelegramCore) AccountConfirmPhone(request *tg.AccountConfirmPhoneRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountConfirmPhone(ctx, request)
}

func (t *TelegramCore) AccountCreateBusinessChatLink(link tg.InputBusinessChatLink) (*tg.BusinessChatLink, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountCreateBusinessChatLink(ctx, link)
}

func (t *TelegramCore) AccountCreateTheme(request *tg.AccountCreateThemeRequest) (*tg.Theme, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountCreateTheme(ctx, request)
}

func (t *TelegramCore) AccountDeclinePasswordReset() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDeclinePasswordReset(ctx)
}

func (t *TelegramCore) AccountDeleteAccount(request *tg.AccountDeleteAccountRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDeleteAccount(ctx, request)
}

func (t *TelegramCore) AccountDeleteAutoSaveExceptions() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDeleteAutoSaveExceptions(ctx)
}

func (t *TelegramCore) AccountDeleteBusinessChatLink(slug string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDeleteBusinessChatLink(ctx, slug)
}

func (t *TelegramCore) AccountDeletePasskey(id string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDeletePasskey(ctx, id)
}

func (t *TelegramCore) AccountDeleteSecureValue(types []tg.SecureValueTypeClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDeleteSecureValue(ctx, types)
}

func (t *TelegramCore) AccountDisablePeerConnectedBot(peer tg.InputPeerClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountDisablePeerConnectedBot(ctx, peer)
}

func (t *TelegramCore) AccountEditBusinessChatLink(request *tg.AccountEditBusinessChatLinkRequest) (*tg.BusinessChatLink, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountEditBusinessChatLink(ctx, request)
}

func (t *TelegramCore) AccountFinishTakeoutSession(request *tg.AccountFinishTakeoutSessionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountFinishTakeoutSession(ctx, request)
}

func (t *TelegramCore) InitTakeout(contacts, msgUsers, msgChats, msgMegagroups, msgChannels, files bool, fileMaxSizeBytes int64) (int64, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return 0, err
	}
	req := &tg.AccountInitTakeoutSessionRequest{}
	if contacts {
		req.SetContacts(true)
	}
	if msgUsers {
		req.SetMessageUsers(true)
	}
	if msgChats {
		req.SetMessageChats(true)
	}
	if msgMegagroups {
		req.SetMessageMegagroups(true)
	}
	if msgChannels {
		req.SetMessageChannels(true)
	}
	if files {
		req.SetFiles(true)
		req.SetFileMaxSize(fileMaxSizeBytes)
	}
	result, err := api.AccountInitTakeoutSession(ctx, req)
	if err != nil {
		return 0, err
	}
	return result.ID, nil
}

func (t *TelegramCore) FinishTakeout() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountFinishTakeoutSession(ctx, &tg.AccountFinishTakeoutSessionRequest{})
	return err
}

func (t *TelegramCore) AccountGetAllSecureValues() ([]tg.SecureValue, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetAllSecureValues(ctx)
}

func (t *TelegramCore) AccountGetAuthorizationForm(request *tg.AccountGetAuthorizationFormRequest) (*tg.AccountAuthorizationForm, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetAuthorizationForm(ctx, request)
}

func (t *TelegramCore) AccountGetAutoDownloadSettings() (*tg.AccountAutoDownloadSettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetAutoDownloadSettings(ctx)
}

func (t *TelegramCore) AccountGetAutoSaveSettings() (*tg.AccountAutoSaveSettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetAutoSaveSettings(ctx)
}

func (t *TelegramCore) AccountGetBotBusinessConnection(connectionid string) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetBotBusinessConnection(ctx, connectionid)
}

func (t *TelegramCore) AccountGetBusinessChatLinks() (*tg.AccountBusinessChatLinks, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetBusinessChatLinks(ctx)
}

func (t *TelegramCore) AccountGetChannelDefaultEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetChannelDefaultEmojiStatuses(ctx, hash)
}

func (t *TelegramCore) AccountGetChannelRestrictedStatusEmojis(hash int64) (tg.EmojiListClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetChannelRestrictedStatusEmojis(ctx, hash)
}

func (t *TelegramCore) AccountGetChatThemes(hash int64) (tg.AccountThemesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetChatThemes(ctx, hash)
}

func (t *TelegramCore) AccountGetCollectibleEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetCollectibleEmojiStatuses(ctx, hash)
}

func (t *TelegramCore) AccountGetConnectedBots() (*tg.AccountConnectedBots, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetConnectedBots(ctx)
}

func (t *TelegramCore) AccountGetContactSignUpNotification() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountGetContactSignUpNotification(ctx)
}

func (t *TelegramCore) AccountGetContentSettings() (*tg.AccountContentSettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetContentSettings(ctx)
}

func (t *TelegramCore) AccountGetDefaultBackgroundEmojis(hash int64) (tg.EmojiListClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetDefaultBackgroundEmojis(ctx, hash)
}

func (t *TelegramCore) AccountGetDefaultEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetDefaultEmojiStatuses(ctx, hash)
}

func (t *TelegramCore) AccountGetDefaultGroupPhotoEmojis(hash int64) (tg.EmojiListClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetDefaultGroupPhotoEmojis(ctx, hash)
}

func (t *TelegramCore) AccountGetDefaultProfilePhotoEmojis(hash int64) (tg.EmojiListClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetDefaultProfilePhotoEmojis(ctx, hash)
}

func (t *TelegramCore) AccountGetMultiWallPapers(wallpapers []tg.InputWallPaperClass) ([]tg.WallPaperClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetMultiWallPapers(ctx, wallpapers)
}

func (t *TelegramCore) AccountGetNotifyExceptions(request *tg.AccountGetNotifyExceptionsRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetNotifyExceptions(ctx, request)
}

func (t *TelegramCore) AccountGetNotifySettings(peer tg.InputNotifyPeerClass) (*tg.PeerNotifySettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetNotifySettings(ctx, peer)
}

func (t *TelegramCore) AccountGetPaidMessagesRevenue(request *tg.AccountGetPaidMessagesRevenueRequest) (*tg.AccountPaidMessagesRevenue, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetPaidMessagesRevenue(ctx, request)
}

func (t *TelegramCore) AccountGetPasskeys() (*tg.AccountPasskeys, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetPasskeys(ctx)
}

func (t *TelegramCore) AccountGetPasswordSettings(password tg.InputCheckPasswordSRPClass) (*tg.AccountPasswordSettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetPasswordSettings(ctx, password)
}

func (t *TelegramCore) AccountGetReactionsNotifySettings() (*tg.ReactionsNotifySettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetReactionsNotifySettings(ctx)
}

func (t *TelegramCore) AccountGetRecentEmojiStatuses(hash int64) (tg.AccountEmojiStatusesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetRecentEmojiStatuses(ctx, hash)
}

func (t *TelegramCore) AccountGetSavedMusicIDs(hash int64) (tg.AccountSavedMusicIDsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetSavedMusicIDs(ctx, hash)
}

func (t *TelegramCore) AccountGetSavedRingtones(hash int64) (tg.AccountSavedRingtonesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetSavedRingtones(ctx, hash)
}

func (t *TelegramCore) AccountGetSecureValue(types []tg.SecureValueTypeClass) ([]tg.SecureValue, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetSecureValue(ctx, types)
}

func (t *TelegramCore) AccountGetTheme(request *tg.AccountGetThemeRequest) (*tg.Theme, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetTheme(ctx, request)
}

func (t *TelegramCore) AccountGetThemes(request *tg.AccountGetThemesRequest) (tg.AccountThemesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetThemes(ctx, request)
}

func (t *TelegramCore) GetCloudThemes() ([]CloudThemeInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	resp, err := api.AccountGetThemes(ctx, &tg.AccountGetThemesRequest{
		Format: "tdesktop",
		Hash:   0,
	})
	if err != nil {
		return nil, err
	}
	themes, ok := resp.(*tg.AccountThemes)
	if !ok {
		return nil, nil
	}
	var result []CloudThemeInfo
	for _, th := range themes.Themes {
		info := CloudThemeInfo{
			ID:        th.ID,
			Title:     th.Title,
			Slug:      th.Slug,
			IsCreator: th.Creator,
		}
		if doc, ok := th.GetDocument(); ok {
			info.DocumentId = doc.GetID()
		}
		if len(th.Settings) > 0 {
			s := th.Settings[0]
			info.AccentColor = s.AccentColor
			switch s.BaseTheme.(type) {
			case *tg.BaseThemeNight, *tg.BaseThemeTinted:
				info.IsDark = true
			}
			if len(s.MessageColors) > 0 {
				info.SentColor = s.MessageColors[0]
			}
			info.RecvColor = info.AccentColor
		}
		result = append(result, info)
	}
	return result, nil
}

func (t *TelegramCore) DeleteCloudTheme(themeID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	theme := &tg.InputTheme{ID: themeID}
	_, err = api.AccountSaveTheme(ctx, &tg.AccountSaveThemeRequest{
		Theme:  theme,
		Unsave: true,
	})
	return err
}

func (t *TelegramCore) CreateCloudThemeWithData(title, slug string, themeData []byte) (*CloudThemeInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload(slug+".tdesktop-theme", io.NopCloser(bytes.NewReader(themeData)), int64(len(themeData))))
	if err != nil {
		return nil, fmt.Errorf("upload theme file: %w", err)
	}

	doc, err := api.AccountUploadTheme(ctx, &tg.AccountUploadThemeRequest{
		File:     upload,
		FileName: slug + ".tdesktop-theme",
		MimeType: "application/x-tgtheme-tdesktop",
	})
	if err != nil {
		return nil, fmt.Errorf("account upload theme: %w", err)
	}

	d, ok := doc.(*tg.Document)
	if !ok {
		return nil, fmt.Errorf("unexpected document type: %T", doc)
	}

	req := &tg.AccountCreateThemeRequest{
		Slug:  slug,
		Title: title,
	}
	req.SetDocument(&tg.InputDocument{
		ID:            d.ID,
		AccessHash:    d.AccessHash,
		FileReference: d.FileReference,
	})

	theme, err := api.AccountCreateTheme(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("account create theme: %w", err)
	}

	info := &CloudThemeInfo{
		ID:         theme.ID,
		AccessHash: theme.AccessHash,
		Title:      theme.Title,
		Slug:       theme.Slug,
		IsCreator:  theme.Creator,
	}
	if doc, ok := theme.GetDocument(); ok {
		info.DocumentId = doc.GetID()
	}
	if len(theme.Settings) > 0 {
		s := theme.Settings[0]
		info.AccentColor = s.AccentColor
		switch s.BaseTheme.(type) {
		case *tg.BaseThemeNight, *tg.BaseThemeTinted:
			info.IsDark = true
		}
		if len(s.MessageColors) > 0 {
			info.SentColor = s.MessageColors[0]
		}
		info.RecvColor = info.AccentColor
	}
	return info, nil
}

func (t *TelegramCore) UpdateCloudThemeWithData(themeID, accessHash int64, title, slug string, themeData []byte) (*CloudThemeInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(api)
	upload, err := u.Upload(ctx, uploader.NewUpload(slug+".tdesktop-theme", io.NopCloser(bytes.NewReader(themeData)), int64(len(themeData))))
	if err != nil {
		return nil, fmt.Errorf("upload theme file: %w", err)
	}

	doc, err := api.AccountUploadTheme(ctx, &tg.AccountUploadThemeRequest{
		File:     upload,
		FileName: slug + ".tdesktop-theme",
		MimeType: "application/x-tgtheme-tdesktop",
	})
	if err != nil {
		return nil, fmt.Errorf("account upload theme: %w", err)
	}

	d, ok := doc.(*tg.Document)
	if !ok {
		return nil, fmt.Errorf("unexpected document type: %T", doc)
	}

	req := &tg.AccountUpdateThemeRequest{
		Format: "tdesktop",
		Theme:  &tg.InputTheme{ID: themeID, AccessHash: accessHash},
		Slug:   slug,
		Title:  title,
	}
	req.SetSlug(slug)
	req.SetTitle(title)
	req.SetDocument(&tg.InputDocument{
		ID:            d.ID,
		AccessHash:    d.AccessHash,
		FileReference: d.FileReference,
	})

	theme, err := api.AccountUpdateTheme(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("account update theme: %w", err)
	}

	info := &CloudThemeInfo{
		ID:         theme.ID,
		AccessHash: theme.AccessHash,
		Title:      theme.Title,
		Slug:       theme.Slug,
		IsCreator:  theme.Creator,
	}
	if doc, ok := theme.GetDocument(); ok {
		info.DocumentId = doc.GetID()
	}
	if len(theme.Settings) > 0 {
		s := theme.Settings[0]
		info.AccentColor = s.AccentColor
		switch s.BaseTheme.(type) {
		case *tg.BaseThemeNight, *tg.BaseThemeTinted:
			info.IsDark = true
		}
		if len(s.MessageColors) > 0 {
			info.SentColor = s.MessageColors[0]
		}
		info.RecvColor = info.AccentColor
	}
	return info, nil
}

func (t *TelegramCore) AccountGetTmpPassword(request *tg.AccountGetTmpPasswordRequest) (*tg.AccountTmpPassword, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetTmpPassword(ctx, request)
}

func (t *TelegramCore) AccountGetUniqueGiftChatThemes(request *tg.AccountGetUniqueGiftChatThemesRequest) (tg.AccountChatThemesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetUniqueGiftChatThemes(ctx, request)
}

func (t *TelegramCore) AccountGetWallPaper(wallpaper tg.InputWallPaperClass) (tg.WallPaperClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetWallPaper(ctx, wallpaper)
}

func (t *TelegramCore) AccountGetWallPapers(hash int64) (tg.AccountWallPapersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetWallPapers(ctx, hash)
}

func (t *TelegramCore) AccountGetWebAuthorizations() (*tg.AccountWebAuthorizations, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountGetWebAuthorizations(ctx)
}

func (t *TelegramCore) AccountInitPasskeyRegistration() (*tg.AccountPasskeyRegistrationOptions, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountInitPasskeyRegistration(ctx)
}

func (t *TelegramCore) AccountInitTakeoutSession(request *tg.AccountInitTakeoutSessionRequest) (*tg.AccountTakeout, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountInitTakeoutSession(ctx, request)
}

func (t *TelegramCore) InstallCloudTheme(themeID int64, isDark bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	theme := &tg.InputTheme{ID: themeID}
	_, err = api.AccountInstallTheme(ctx, &tg.AccountInstallThemeRequest{
		Dark:  isDark,
		Theme: theme,
	})
	return err
}

func (t *TelegramCore) AccountInstallTheme(request *tg.AccountInstallThemeRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountInstallTheme(ctx, request)
}

func (t *TelegramCore) AccountInstallWallPaper(request *tg.AccountInstallWallPaperRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountInstallWallPaper(ctx, request)
}

func (t *TelegramCore) AccountInvalidateSignInCodes(codes []string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountInvalidateSignInCodes(ctx, codes)
}

func (t *TelegramCore) AccountRegisterDevice(request *tg.AccountRegisterDeviceRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountRegisterDevice(ctx, request)
}

func (t *TelegramCore) AccountRegisterPasskey(credential tg.InputPasskeyCredentialClass) (*tg.Passkey, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountRegisterPasskey(ctx, credential)
}

func (t *TelegramCore) AccountReorderUsernames(order []string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountReorderUsernames(ctx, order)
}

func (t *TelegramCore) AccountReportPeer(request *tg.AccountReportPeerRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountReportPeer(ctx, request)
}

func (t *TelegramCore) AccountReportProfilePhoto(request *tg.AccountReportProfilePhotoRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountReportProfilePhoto(ctx, request)
}

func (t *TelegramCore) AccountResendPasswordEmail() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountResendPasswordEmail(ctx)
}

func (t *TelegramCore) AccountResetNotifySettings() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountResetNotifySettings(ctx)
}

func (t *TelegramCore) AccountResetPassword() (tg.AccountResetPasswordResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountResetPassword(ctx)
}

func (t *TelegramCore) AccountResetWallPapers() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountResetWallPapers(ctx)
}

func (t *TelegramCore) AccountResetWebAuthorization(hash int64) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountResetWebAuthorization(ctx, hash)
}

func (t *TelegramCore) AccountResetWebAuthorizations() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountResetWebAuthorizations(ctx)
}

func (t *TelegramCore) AccountResolveBusinessChatLink(slug string) (*tg.AccountResolvedBusinessChatLinks, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountResolveBusinessChatLink(ctx, slug)
}

func (t *TelegramCore) AccountSaveAutoDownloadSettings(request *tg.AccountSaveAutoDownloadSettingsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSaveAutoDownloadSettings(ctx, request)
}

func (t *TelegramCore) AccountSaveAutoSaveSettings(request *tg.AccountSaveAutoSaveSettingsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSaveAutoSaveSettings(ctx, request)
}

func (t *TelegramCore) AccountSaveMusic(request *tg.AccountSaveMusicRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSaveMusic(ctx, request)
}

func (t *TelegramCore) AccountSaveRingtone(request *tg.AccountSaveRingtoneRequest) (tg.AccountSavedRingtoneClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSaveRingtone(ctx, request)
}

func (t *TelegramCore) AccountSaveSecureValue(request *tg.AccountSaveSecureValueRequest) (*tg.SecureValue, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSaveSecureValue(ctx, request)
}

func (t *TelegramCore) AccountSaveTheme(request *tg.AccountSaveThemeRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSaveTheme(ctx, request)
}

func (t *TelegramCore) AccountSaveWallPaper(request *tg.AccountSaveWallPaperRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSaveWallPaper(ctx, request)
}

func (t *TelegramCore) AccountSendChangePhoneCode(request *tg.AccountSendChangePhoneCodeRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSendChangePhoneCode(ctx, request)
}

func (t *TelegramCore) AccountSendConfirmPhoneCode(request *tg.AccountSendConfirmPhoneCodeRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSendConfirmPhoneCode(ctx, request)
}

func (t *TelegramCore) AccountSendVerifyEmailCode(request *tg.AccountSendVerifyEmailCodeRequest) (*tg.AccountSentEmailCode, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSendVerifyEmailCode(ctx, request)
}

func (t *TelegramCore) AccountSendVerifyPhoneCode(request *tg.AccountSendVerifyPhoneCodeRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSendVerifyPhoneCode(ctx, request)
}

func (t *TelegramCore) AccountSetAuthorizationTTL(authorizationttldays int) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSetAuthorizationTTL(ctx, authorizationttldays)
}

func (t *TelegramCore) AccountSetContactSignUpNotification(silent bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSetContactSignUpNotification(ctx, silent)
}

func (t *TelegramCore) AccountSetContentSettings(request *tg.AccountSetContentSettingsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSetContentSettings(ctx, request)
}

func (t *TelegramCore) AccountSetMainProfileTab(tab tg.ProfileTabClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountSetMainProfileTab(ctx, tab)
}

func (t *TelegramCore) AccountSetReactionsNotifySettings(settings tg.ReactionsNotifySettings) (*tg.ReactionsNotifySettings, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountSetReactionsNotifySettings(ctx, settings)
}

func (t *TelegramCore) AccountToggleConnectedBotPaused(request *tg.AccountToggleConnectedBotPausedRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountToggleConnectedBotPaused(ctx, request)
}

func (t *TelegramCore) AccountToggleNoPaidMessagesException(request *tg.AccountToggleNoPaidMessagesExceptionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountToggleNoPaidMessagesException(ctx, request)
}

func (t *TelegramCore) AccountToggleSponsoredMessages(enabled bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountToggleSponsoredMessages(ctx, enabled)
}

func (t *TelegramCore) AccountToggleUsername(request *tg.AccountToggleUsernameRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountToggleUsername(ctx, request)
}

func (t *TelegramCore) AccountUnregisterDevice(request *tg.AccountUnregisterDeviceRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUnregisterDevice(ctx, request)
}

func (t *TelegramCore) AccountUpdateBusinessAwayMessage(request *tg.AccountUpdateBusinessAwayMessageRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateBusinessAwayMessage(ctx, request)
}

func (t *TelegramCore) AccountUpdateBusinessGreetingMessage(request *tg.AccountUpdateBusinessGreetingMessageRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateBusinessGreetingMessage(ctx, request)
}

func (t *TelegramCore) AccountUpdateBusinessIntro(request *tg.AccountUpdateBusinessIntroRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateBusinessIntro(ctx, request)
}

func (t *TelegramCore) AccountUpdateBusinessLocation(request *tg.AccountUpdateBusinessLocationRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateBusinessLocation(ctx, request)
}

func (t *TelegramCore) AccountUpdateBusinessWorkHours(request *tg.AccountUpdateBusinessWorkHoursRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateBusinessWorkHours(ctx, request)
}

func (t *TelegramCore) AccountUpdateColor(request *tg.AccountUpdateColorRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateColor(ctx, request)
}

func (t *TelegramCore) AccountUpdateConnectedBot(request *tg.AccountUpdateConnectedBotRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountUpdateConnectedBot(ctx, request)
}

func (t *TelegramCore) AccountUpdateDeviceLocked(period int) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateDeviceLocked(ctx, period)
}

func (t *TelegramCore) AccountUpdateEmojiStatus(emojistatus tg.EmojiStatusClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateEmojiStatus(ctx, emojistatus)
}

func (t *TelegramCore) SetEmojiStatus(documentID int64, expiresIn int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	status := &tg.EmojiStatus{DocumentID: documentID}
	if expiresIn > 0 {
		status.SetUntil(int(time.Now().Unix()) + expiresIn)
	}
	_, err = api.AccountUpdateEmojiStatus(ctx, status)
	return err
}

func (t *TelegramCore) ClearEmojiStatus() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountUpdateEmojiStatus(ctx, &tg.EmojiStatusEmpty{})
	return err
}

func (t *TelegramCore) DeleteQuickReply(shortcutID int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesDeleteQuickReplyShortcut(ctx, shortcutID)
	return err
}

func (t *TelegramCore) DeleteBusinessLink(slug string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountDeleteBusinessChatLink(ctx, slug)
	return err
}

func (t *TelegramCore) AccountUpdateNotifySettings(request *tg.AccountUpdateNotifySettingsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdateNotifySettings(ctx, request)
}

func (t *TelegramCore) AccountUpdatePasswordSettings(request *tg.AccountUpdatePasswordSettingsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdatePasswordSettings(ctx, request)
}

func (t *TelegramCore) AccountUpdatePersonalChannel(channel tg.InputChannelClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountUpdatePersonalChannel(ctx, channel)
}

func (t *TelegramCore) SetPersonalChannel(channelUsername string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
		Username: strings.TrimPrefix(channelUsername, "@"),
	})
	if err != nil {
		return fmt.Errorf("resolve channel: %w", err)
	}
	t.cacheEntities(resolved.Users, resolved.Chats)
	for _, c := range resolved.Chats {
		if ch, ok := c.(*tg.Channel); ok {
			_, err := api.AccountUpdatePersonalChannel(ctx, &tg.InputChannel{
				ChannelID:  ch.ID,
				AccessHash: ch.AccessHash,
			})
			return err
		}
	}
	return fmt.Errorf("no channel found for username %q", channelUsername)
}

func (t *TelegramCore) ClearPersonalChannel() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountUpdatePersonalChannel(ctx, &tg.InputChannelEmpty{})
	return err
}

func (t *TelegramCore) AccountUpdateTheme(request *tg.AccountUpdateThemeRequest) (*tg.Theme, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountUpdateTheme(ctx, request)
}

func (t *TelegramCore) AccountUploadRingtone(request *tg.AccountUploadRingtoneRequest) (tg.DocumentClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountUploadRingtone(ctx, request)
}

func (t *TelegramCore) AccountUploadTheme(request *tg.AccountUploadThemeRequest) (tg.DocumentClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountUploadTheme(ctx, request)
}

func (t *TelegramCore) AccountUploadWallPaper(request *tg.AccountUploadWallPaperRequest) (tg.WallPaperClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountUploadWallPaper(ctx, request)
}

func (t *TelegramCore) AccountVerifyEmail(request *tg.AccountVerifyEmailRequest) (tg.AccountEmailVerifiedClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AccountVerifyEmail(ctx, request)
}

func (t *TelegramCore) AccountVerifyPhone(request *tg.AccountVerifyPhoneRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AccountVerifyPhone(ctx, request)
}

func (t *TelegramCore) AuthAcceptLoginToken(token []byte) (*tg.Authorization, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthAcceptLoginToken(ctx, token)
}

func (t *TelegramCore) AuthBindTempAuthKey(request *tg.AuthBindTempAuthKeyRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthBindTempAuthKey(ctx, request)
}

func (t *TelegramCore) AuthCancelCode(request *tg.AuthCancelCodeRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthCancelCode(ctx, request)
}

func (t *TelegramCore) AuthCheckPaidAuth(request *tg.AuthCheckPaidAuthRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthCheckPaidAuth(ctx, request)
}

func (t *TelegramCore) AuthCheckPassword(password tg.InputCheckPasswordSRPClass) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthCheckPassword(ctx, password)
}

func (t *TelegramCore) AuthCheckRecoveryPassword(code string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthCheckRecoveryPassword(ctx, code)
}

func (t *TelegramCore) AuthDropTempAuthKeys(exceptauthkeys []int64) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthDropTempAuthKeys(ctx, exceptauthkeys)
}

func (t *TelegramCore) AuthExportAuthorization(dcid int) (*tg.AuthExportedAuthorization, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthExportAuthorization(ctx, dcid)
}

func (t *TelegramCore) AuthExportLoginToken(request *tg.AuthExportLoginTokenRequest) (tg.AuthLoginTokenClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthExportLoginToken(ctx, request)
}

func (t *TelegramCore) AuthFinishPasskeyLogin(request *tg.AuthFinishPasskeyLoginRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthFinishPasskeyLogin(ctx, request)
}

func (t *TelegramCore) AuthImportAuthorization(request *tg.AuthImportAuthorizationRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthImportAuthorization(ctx, request)
}

func (t *TelegramCore) AuthImportBotAuthorization(request *tg.AuthImportBotAuthorizationRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthImportBotAuthorization(ctx, request)
}

func (t *TelegramCore) AuthImportLoginToken(token []byte) (tg.AuthLoginTokenClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthImportLoginToken(ctx, token)
}

func (t *TelegramCore) AuthImportWebTokenAuthorization(request *tg.AuthImportWebTokenAuthorizationRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthImportWebTokenAuthorization(ctx, request)
}

func (t *TelegramCore) AuthInitPasskeyLogin(request *tg.AuthInitPasskeyLoginRequest) (*tg.AuthPasskeyLoginOptions, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthInitPasskeyLogin(ctx, request)
}

func (t *TelegramCore) AuthRecoverPassword(request *tg.AuthRecoverPasswordRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthRecoverPassword(ctx, request)
}

func (t *TelegramCore) AuthReportMissingCode(request *tg.AuthReportMissingCodeRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthReportMissingCode(ctx, request)
}

func (t *TelegramCore) AuthRequestFirebaseSMS(request *tg.AuthRequestFirebaseSMSRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthRequestFirebaseSMS(ctx, request)
}

func (t *TelegramCore) AuthRequestPasswordRecovery() (*tg.AuthPasswordRecovery, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthRequestPasswordRecovery(ctx)
}

func (t *TelegramCore) AuthResendCode(request *tg.AuthResendCodeRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthResendCode(ctx, request)
}

func (t *TelegramCore) AuthResetAuthorizations() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.AuthResetAuthorizations(ctx)
}

func (t *TelegramCore) AuthResetLoginEmail(request *tg.AuthResetLoginEmailRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthResetLoginEmail(ctx, request)
}

func (t *TelegramCore) AuthSendCode(request *tg.AuthSendCodeRequest) (tg.AuthSentCodeClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthSendCode(ctx, request)
}

func (t *TelegramCore) AuthSignIn(request *tg.AuthSignInRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthSignIn(ctx, request)
}

func (t *TelegramCore) AuthSignUp(request *tg.AuthSignUpRequest) (tg.AuthAuthorizationClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.AuthSignUp(ctx, request)
}

func (t *TelegramCore) BotsAddPreviewMedia(request *tg.BotsAddPreviewMediaRequest) (*tg.BotPreviewMedia, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsAddPreviewMedia(ctx, request)
}

func (t *TelegramCore) BotsAllowSendMessage(bot tg.InputUserClass) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsAllowSendMessage(ctx, bot)
}

func (t *TelegramCore) BotsAnswerWebhookJSONQuery(request *tg.BotsAnswerWebhookJSONQueryRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsAnswerWebhookJSONQuery(ctx, request)
}

func (t *TelegramCore) BotsCanSendMessage(bot tg.InputUserClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsCanSendMessage(ctx, bot)
}

func (t *TelegramCore) BotsCheckDownloadFileParams(request *tg.BotsCheckDownloadFileParamsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsCheckDownloadFileParams(ctx, request)
}

func (t *TelegramCore) BotsCheckUsername(username string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsCheckUsername(ctx, username)
}

func (t *TelegramCore) BotsCreateBot(request *tg.BotsCreateBotRequest) (tg.UserClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsCreateBot(ctx, request)
}

func (t *TelegramCore) BotsDeletePreviewMedia(request *tg.BotsDeletePreviewMediaRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsDeletePreviewMedia(ctx, request)
}

func (t *TelegramCore) BotsEditPreviewMedia(request *tg.BotsEditPreviewMediaRequest) (*tg.BotPreviewMedia, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsEditPreviewMedia(ctx, request)
}

func (t *TelegramCore) BotsExportBotToken(request *tg.BotsExportBotTokenRequest) (*tg.BotsExportedBotToken, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsExportBotToken(ctx, request)
}

func (t *TelegramCore) BotsGetAdminedBots() ([]tg.UserClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetAdminedBots(ctx)
}

func (t *TelegramCore) BotsGetBotCommands(request *tg.BotsGetBotCommandsRequest) ([]tg.BotCommand, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetBotCommands(ctx, request)
}

func (t *TelegramCore) BotsGetBotInfo(request *tg.BotsGetBotInfoRequest) (*tg.BotsBotInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetBotInfo(ctx, request)
}

func (t *TelegramCore) BotsGetBotMenuButton(userid tg.InputUserClass) (tg.BotMenuButtonClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetBotMenuButton(ctx, userid)
}

func (t *TelegramCore) BotsGetBotRecommendations(bot tg.InputUserClass) (tg.UsersUsersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetBotRecommendations(ctx, bot)
}

func (t *TelegramCore) BotsGetPopularAppBots(request *tg.BotsGetPopularAppBotsRequest) (*tg.BotsPopularAppBots, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetPopularAppBots(ctx, request)
}

func (t *TelegramCore) BotsGetPreviewInfo(request *tg.BotsGetPreviewInfoRequest) (*tg.BotsPreviewInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetPreviewInfo(ctx, request)
}

func (t *TelegramCore) BotsGetPreviewMedias(bot tg.InputUserClass) ([]tg.BotPreviewMedia, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetPreviewMedias(ctx, bot)
}

func (t *TelegramCore) BotsGetRequestedWebViewButton(request *tg.BotsGetRequestedWebViewButtonRequest) (tg.KeyboardButtonClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsGetRequestedWebViewButton(ctx, request)
}

func (t *TelegramCore) BotsInvokeWebViewCustomMethod(request *tg.BotsInvokeWebViewCustomMethodRequest) (*tg.DataJSON, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsInvokeWebViewCustomMethod(ctx, request)
}

func (t *TelegramCore) BotsReorderPreviewMedias(request *tg.BotsReorderPreviewMediasRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsReorderPreviewMedias(ctx, request)
}

func (t *TelegramCore) BotsReorderUsernames(request *tg.BotsReorderUsernamesRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsReorderUsernames(ctx, request)
}

func (t *TelegramCore) BotsRequestWebViewButton(request *tg.BotsRequestWebViewButtonRequest) (*tg.BotsRequestedButton, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsRequestWebViewButton(ctx, request)
}

func (t *TelegramCore) BotsResetBotCommands(request *tg.BotsResetBotCommandsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsResetBotCommands(ctx, request)
}

func (t *TelegramCore) BotsSendCustomRequest(request *tg.BotsSendCustomRequestRequest) (*tg.DataJSON, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsSendCustomRequest(ctx, request)
}

func (t *TelegramCore) BotsSetBotBroadcastDefaultAdminRights(adminrights tg.ChatAdminRights) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsSetBotBroadcastDefaultAdminRights(ctx, adminrights)
}

func (t *TelegramCore) BotsSetBotCommands(request *tg.BotsSetBotCommandsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsSetBotCommands(ctx, request)
}

func (t *TelegramCore) BotsSetBotGroupDefaultAdminRights(adminrights tg.ChatAdminRights) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsSetBotGroupDefaultAdminRights(ctx, adminrights)
}

func (t *TelegramCore) BotsSetBotInfo(request *tg.BotsSetBotInfoRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsSetBotInfo(ctx, request)
}

func (t *TelegramCore) BotsSetBotMenuButton(request *tg.BotsSetBotMenuButtonRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsSetBotMenuButton(ctx, request)
}

func (t *TelegramCore) BotsSetCustomVerification(request *tg.BotsSetCustomVerificationRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsSetCustomVerification(ctx, request)
}

func (t *TelegramCore) BotsToggleUserEmojiStatusPermission(request *tg.BotsToggleUserEmojiStatusPermissionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsToggleUserEmojiStatusPermission(ctx, request)
}

func (t *TelegramCore) BotsToggleUsername(request *tg.BotsToggleUsernameRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsToggleUsername(ctx, request)
}

func (t *TelegramCore) BotsUpdateStarRefProgram(request *tg.BotsUpdateStarRefProgramRequest) (*tg.StarRefProgram, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.BotsUpdateStarRefProgram(ctx, request)
}

func (t *TelegramCore) SetStarRefProgram(chatID string, commissionPermille, durationMonths int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := tgUserID(chatID)
	if err != nil {
		return err
	}
	req := &tg.BotsUpdateStarRefProgramRequest{
		Bot:                &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)},
		CommissionPermille: commissionPermille,
	}
	if durationMonths > 0 {
		req.DurationMonths = durationMonths
	}
	req.SetFlags()
	_, err = api.BotsUpdateStarRefProgram(ctx, req)
	return err
}

func (t *TelegramCore) BotsUpdateUserEmojiStatus(request *tg.BotsUpdateUserEmojiStatusRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.BotsUpdateUserEmojiStatus(ctx, request)
}

func (t *TelegramCore) ChannelsCheckSearchPostsFlood(request *tg.ChannelsCheckSearchPostsFloodRequest) (*tg.SearchPostsFlood, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsCheckSearchPostsFlood(ctx, request)
}

func (t *TelegramCore) ChannelsCheckUsername(request *tg.ChannelsCheckUsernameRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsCheckUsername(ctx, request)
}

func (t *TelegramCore) ChannelsConvertToGigagroup(channel tg.InputChannelClass) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsConvertToGigagroup(ctx, channel)
}

func (t *TelegramCore) ChannelsDeactivateAllUsernames(channel tg.InputChannelClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsDeactivateAllUsernames(ctx, channel)
}

func (t *TelegramCore) ChannelsDeleteHistory(request *tg.ChannelsDeleteHistoryRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsDeleteHistory(ctx, request)
}

func (t *TelegramCore) ChannelsDeleteParticipantHistory(request *tg.ChannelsDeleteParticipantHistoryRequest) (*tg.MessagesAffectedHistory, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsDeleteParticipantHistory(ctx, request)
}

func (t *TelegramCore) ChannelsEditLocation(request *tg.ChannelsEditLocationRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsEditLocation(ctx, request)
}

func (t *TelegramCore) ChannelsGetAdminedPublicChannels(request *tg.ChannelsGetAdminedPublicChannelsRequest) (tg.MessagesChatsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetAdminedPublicChannels(ctx, request)
}

func (t *TelegramCore) GetAdminedPublicChannels() ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.ChannelsGetAdminedPublicChannels(ctx, &tg.ChannelsGetAdminedPublicChannelsRequest{})
	if err != nil {
		return nil, err
	}
	var chats []tg.ChatClass
	switch mc := result.(type) {
	case *tg.MessagesChats:
		chats = mc.Chats
	case *tg.MessagesChatsSlice:
		chats = mc.Chats
	}
	var dialogs []Dialog
	for _, c := range chats {
		channel, ok := c.(*tg.Channel)
		if !ok {
			continue
		}
		username := ""
		if u, ok := channel.GetUsername(); ok {
			username = u
		}
		if username == "" && len(channel.Usernames) > 0 {
			for _, un := range channel.Usernames {
				if un.Active {
					username = un.Username
					break
				}
			}
		}
		if username == "" {
			continue
		}
		d := Dialog{
			ID:       strconv.FormatInt(-1000000000000-channel.ID, 10),
			Title:    channel.Title,
			Type:     ChatTypeChannel,
			Platform: tgPlatform,
		}
		if cp, ok := channel.Photo.(*tg.ChatPhoto); ok {
			if thumb, ok := cp.GetStrippedThumb(); ok && len(thumb) > 0 {
				if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
					d.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
				}
			}
		}
		if channel.ParticipantsCount > 0 {
			d.MemberCount = channel.ParticipantsCount
		}
		d.LinkedChatId = username
		dialogs = append(dialogs, d)
	}
	return dialogs, nil
}

func (t *TelegramCore) GetAdminedPublicChannelsForPersonal() ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.ChannelsGetAdminedPublicChannels(ctx, &tg.ChannelsGetAdminedPublicChannelsRequest{
		ForPersonal: true,
	})
	if err != nil {
		return nil, err
	}
	var chats []tg.ChatClass
	switch mc := result.(type) {
	case *tg.MessagesChats:
		chats = mc.Chats
	case *tg.MessagesChatsSlice:
		chats = mc.Chats
	}
	var dialogs []Dialog
	for _, c := range chats {
		channel, ok := c.(*tg.Channel)
		if !ok {
			continue
		}
		username := ""
		if u, ok := channel.GetUsername(); ok {
			username = u
		}
		if username == "" && len(channel.Usernames) > 0 {
			for _, un := range channel.Usernames {
				if un.Active {
					username = un.Username
					break
				}
			}
		}
		if username == "" {
			continue
		}
		d := Dialog{
			ID:       strconv.FormatInt(-1000000000000-channel.ID, 10),
			Title:    channel.Title,
			Type:     ChatTypeChannel,
			Platform: tgPlatform,
		}
		if cp, ok := channel.Photo.(*tg.ChatPhoto); ok {
			if thumb, ok := cp.GetStrippedThumb(); ok && len(thumb) > 0 {
				if jpg := tgStrippedToJPEG(thumb); len(jpg) > 0 {
					d.AvatarB64 = base64.StdEncoding.EncodeToString(jpg)
				}
			}
		}
		if channel.ParticipantsCount > 0 {
			d.MemberCount = channel.ParticipantsCount
		}
		d.LinkedChatId = username
		dialogs = append(dialogs, d)
	}
	return dialogs, nil
}

func (t *TelegramCore) ChannelsGetChannelRecommendations(request *tg.ChannelsGetChannelRecommendationsRequest) (tg.MessagesChatsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetChannelRecommendations(ctx, request)
}

func (t *TelegramCore) ChannelsGetGroupsForDiscussion() (tg.MessagesChatsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetGroupsForDiscussion(ctx)
}

func (t *TelegramCore) ChannelsGetInactiveChannels() (*tg.MessagesInactiveChats, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetInactiveChannels(ctx)
}

func (t *TelegramCore) ChannelsGetLeftChannels(offset int) (tg.MessagesChatsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetLeftChannels(ctx, offset)
}

func (t *TelegramCore) ChannelsGetMessageAuthor(request *tg.ChannelsGetMessageAuthorRequest) (tg.UserClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetMessageAuthor(ctx, request)
}

func (t *TelegramCore) ChannelsGetMessages(request *tg.ChannelsGetMessagesRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsGetMessages(ctx, request)
}

func (t *TelegramCore) ChannelsReadMessageContents(request *tg.ChannelsReadMessageContentsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsReadMessageContents(ctx, request)
}

func (t *TelegramCore) ChannelsReorderUsernames(request *tg.ChannelsReorderUsernamesRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsReorderUsernames(ctx, request)
}

func (t *TelegramCore) ChannelsReportAntiSpamFalsePositive(request *tg.ChannelsReportAntiSpamFalsePositiveRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsReportAntiSpamFalsePositive(ctx, request)
}

func (t *TelegramCore) ChannelsReportSpam(request *tg.ChannelsReportSpamRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsReportSpam(ctx, request)
}

func (t *TelegramCore) ChannelsRestrictSponsoredMessages(request *tg.ChannelsRestrictSponsoredMessagesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsRestrictSponsoredMessages(ctx, request)
}

func (t *TelegramCore) ChannelsSearchPosts(request *tg.ChannelsSearchPostsRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsSearchPosts(ctx, request)
}

func (t *TelegramCore) ChannelsSetBoostsToUnblockRestrictions(request *tg.ChannelsSetBoostsToUnblockRestrictionsRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsSetBoostsToUnblockRestrictions(ctx, request)
}

func (t *TelegramCore) ChannelsSetDiscussionGroup(request *tg.ChannelsSetDiscussionGroupRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsSetDiscussionGroup(ctx, request)
}

func (t *TelegramCore) ChannelsSetEmojiStickers(request *tg.ChannelsSetEmojiStickersRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsSetEmojiStickers(ctx, request)
}

func (t *TelegramCore) ChannelsSetMainProfileTab(request *tg.ChannelsSetMainProfileTabRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsSetMainProfileTab(ctx, request)
}

func (t *TelegramCore) ChannelsSetStickers(request *tg.ChannelsSetStickersRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsSetStickers(ctx, request)
}

func (t *TelegramCore) ChannelsToggleUsername(request *tg.ChannelsToggleUsernameRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChannelsToggleUsername(ctx, request)
}

func (t *TelegramCore) ChannelsUpdateEmojiStatus(request *tg.ChannelsUpdateEmojiStatusRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsUpdateEmojiStatus(ctx, request)
}

func (t *TelegramCore) ChannelsUpdatePaidMessagesPrice(request *tg.ChannelsUpdatePaidMessagesPriceRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChannelsUpdatePaidMessagesPrice(ctx, request)
}

func (t *TelegramCore) ChatlistsCheckChatlistInvite(slug string) (tg.ChatlistsChatlistInviteClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChatlistsCheckChatlistInvite(ctx, slug)
}

func (t *TelegramCore) ChatlistsEditExportedInvite(request *tg.ChatlistsEditExportedInviteRequest) (*tg.ExportedChatlistInvite, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChatlistsEditExportedInvite(ctx, request)
}

func (t *TelegramCore) ChatlistsGetChatlistUpdates(chatlist tg.InputChatlistDialogFilter) (*tg.ChatlistsChatlistUpdates, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChatlistsGetChatlistUpdates(ctx, chatlist)
}

func (t *TelegramCore) ChatlistsGetLeaveChatlistSuggestions(chatlist tg.InputChatlistDialogFilter) ([]tg.PeerClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChatlistsGetLeaveChatlistSuggestions(ctx, chatlist)
}

func (t *TelegramCore) ChatlistsHideChatlistUpdates(chatlist tg.InputChatlistDialogFilter) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ChatlistsHideChatlistUpdates(ctx, chatlist)
}

func (t *TelegramCore) ChatlistsJoinChatlistUpdates(request *tg.ChatlistsJoinChatlistUpdatesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChatlistsJoinChatlistUpdates(ctx, request)
}

func (t *TelegramCore) ChatlistsLeaveChatlist(request *tg.ChatlistsLeaveChatlistRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ChatlistsLeaveChatlist(ctx, request)
}

func (t *TelegramCore) ContactsAcceptContact(id tg.InputUserClass) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsAcceptContact(ctx, id)
}

func (t *TelegramCore) HidePeerSettingsBar(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesHidePeerSettingsBar(t.ctx, inputPeer)
	return err
}

func (t *TelegramCore) SharePhoneWithPeer(chatID string) error {
	uid, err := tgUserID(chatID)
	if err != nil {
		return err
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(uid)
	_, err = api.ContactsAcceptContact(ctx, &tg.InputUser{UserID: uid, AccessHash: hash})
	return err
}

func (t *TelegramCore) ContactsBlockFromReplies(request *tg.ContactsBlockFromRepliesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsBlockFromReplies(ctx, request)
}

func (t *TelegramCore) ContactsDeleteByPhones(phones []string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ContactsDeleteByPhones(ctx, phones)
}

func (t *TelegramCore) ContactsExportContactToken() (*tg.ExportedContactToken, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsExportContactToken(ctx)
}

func (t *TelegramCore) ContactsGetLocated(request *tg.ContactsGetLocatedRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsGetLocated(ctx, request)
}

func (t *TelegramCore) ContactsGetSaved() ([]tg.SavedPhoneContact, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsGetSaved(ctx)
}

func (t *TelegramCore) ContactsGetSponsoredPeers(q string) (tg.ContactsSponsoredPeersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsGetSponsoredPeers(ctx, q)
}

func (t *TelegramCore) ContactsGetStatuses() ([]tg.ContactStatus, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsGetStatuses(ctx)
}

func (t *TelegramCore) ContactsImportContactToken(token string) (tg.UserClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.ContactsImportContactToken(ctx, token)
}

func (t *TelegramCore) ContactsResetSaved() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ContactsResetSaved(ctx)
}

func (t *TelegramCore) ContactsResetTopPeerRating(request *tg.ContactsResetTopPeerRatingRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ContactsResetTopPeerRating(ctx, request)
}

func (t *TelegramCore) ContactsSetBlocked(request *tg.ContactsSetBlockedRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ContactsSetBlocked(ctx, request)
}

func (t *TelegramCore) ContactsToggleTopPeers(enabled bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ContactsToggleTopPeers(ctx, enabled)
}

func (t *TelegramCore) RemoveFromTopPeers(peerID string) error {
	inputPeer, unlock, err := t.withPeer(peerID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.ContactsResetTopPeerRating(t.ctx, &tg.ContactsResetTopPeerRatingRequest{
		Category: &tg.TopPeerCategoryCorrespondents{},
		Peer:     inputPeer,
	})
	return err
}

func (t *TelegramCore) ContactsUpdateContactNote(request *tg.ContactsUpdateContactNoteRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.ContactsUpdateContactNote(ctx, request)
}

func (t *TelegramCore) UpdateContactNote(userID, note string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(uid)
	_, err = api.ContactsUpdateContactNote(ctx, &tg.ContactsUpdateContactNoteRequest{
		ID:   &tg.InputUser{UserID: uid, AccessHash: hash},
		Note: tg.TextWithEntities{Text: note},
	})
	return err
}

func (t *TelegramCore) HelpAcceptTermsOfService(id tg.DataJSON) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.HelpAcceptTermsOfService(ctx, id)
}

func (t *TelegramCore) HelpDismissSuggestion(request *tg.HelpDismissSuggestionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.HelpDismissSuggestion(ctx, request)
}

func (t *TelegramCore) HelpEditUserInfo(request *tg.HelpEditUserInfoRequest) (tg.HelpUserInfoClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpEditUserInfo(ctx, request)
}

func (t *TelegramCore) HelpGetAppUpdate(source string) (tg.HelpAppUpdateClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetAppUpdate(ctx, source)
}

func (t *TelegramCore) HelpGetCDNConfig() (*tg.CDNConfig, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetCDNConfig(ctx)
}

func (t *TelegramCore) HelpGetDeepLinkInfo(path string) (tg.HelpDeepLinkInfoClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetDeepLinkInfo(ctx, path)
}

func (t *TelegramCore) HelpGetInviteText() (*tg.HelpInviteText, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetInviteText(ctx)
}

func (t *TelegramCore) HelpGetPassportConfig(hash int) (tg.HelpPassportConfigClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetPassportConfig(ctx, hash)
}

func (t *TelegramCore) HelpGetPeerColors(hash int) (tg.HelpPeerColorsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetPeerColors(ctx, hash)
}

type PeerColorEntry struct {
	ColorID         int   `json:"color_id"`
	DayColors       []int `json:"day_colors"`
	NightColors     []int `json:"night_colors"`
	Hidden          bool  `json:"hidden"`
	ChannelMinLevel int   `json:"channel_min_level"`
	GroupMinLevel   int   `json:"group_min_level"`
}

type CloudThemeInfo struct {
	ID          int64  `json:"id"`
	AccessHash  int64  `json:"access_hash"`
	Title       string `json:"title"`
	Slug        string `json:"slug"`
	IsCreator   bool   `json:"is_creator"`
	DocumentId  int64  `json:"document_id"`
	AccentColor int    `json:"accent_color"`
	BgColor     int    `json:"bg_color"`
	SentColor   int    `json:"sent_color"`
	RecvColor   int    `json:"recv_color"`
	IsDark      bool   `json:"is_dark"`
}

func inflateStrippedThumb(stripped []byte) []byte {
	if len(stripped) < 3 {
		return stripped
	}
	header := []byte{
		0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
		0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
		0x00, 0x28, 0x1C, 0x1E, 0x23, 0x1E, 0x19, 0x28, 0x23, 0x21, 0x23, 0x2D,
		0x2B, 0x28, 0x30, 0x3C, 0x64, 0x41, 0x3C, 0x37, 0x37, 0x3C, 0x7B, 0x58,
		0x5D, 0x49, 0x64, 0x91, 0x80, 0x99, 0x96, 0x8F, 0x80, 0x8C, 0x8A, 0xA0,
		0xB4, 0xE6, 0xC3, 0xA0, 0xAA, 0xDA, 0xAD, 0x8A, 0x8C, 0xC8, 0xFF, 0xCB,
		0xDA, 0xEE, 0xF5, 0xF8, 0xF8, 0xF8, 0x95, 0xBA, 0xFF, 0xFF, 0xFF, 0xFF,
		0xF8, 0xED, 0xF8, 0xC8, 0xF8, 0xF8, 0xF8, 0xFF, 0xDB, 0x00, 0x43, 0x01,
		0x2B, 0x2D, 0x2D, 0x3C, 0x35, 0x3C, 0x76, 0x41, 0x41, 0x76, 0xF8, 0xA5,
		0x8C, 0xA5, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
		0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
		0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
		0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8,
		0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xF8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00,
		0x00, 0x00, 0x00, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11,
		0x01, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01,
		0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
		0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4,
		0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05,
		0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04,
		0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22,
		0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15,
		0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17,
		0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x34, 0x35, 0x36,
		0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
		0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66,
		0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
		0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95,
		0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8,
		0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2,
		0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5,
		0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
		0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9,
		0xFA, 0xFF, 0xC4, 0x00, 0x1F, 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01,
		0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
		0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4,
		0x00, 0xB5, 0x11, 0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07,
		0x05, 0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11,
		0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13,
		0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23,
		0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1,
		0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35,
		0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
		0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65,
		0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
		0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93,
		0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6,
		0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9,
		0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3,
		0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6,
		0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9,
		0xFA, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11,
		0x00, 0x3F, 0x00,
	}
	footer := []byte{0xFF, 0xD9}
	header[164] = stripped[1]
	header[166] = stripped[2]
	result := make([]byte, 0, len(header)+len(stripped)-3+len(footer))
	result = append(result, header...)
	result = append(result, stripped[3:]...)
	result = append(result, footer...)
	return result
}

type WallpaperInfo struct {
	ID         int64  `json:"id"`
	Slug       string `json:"slug"`
	Pattern    bool   `json:"pattern"`
	Dark       bool   `json:"dark"`
	Default    bool   `json:"default"`
	Creator    bool   `json:"creator,omitempty"`
	Colors     []int  `json:"colors,omitempty"`
	Rotation   int    `json:"rotation"`
	Blurred    bool   `json:"blurred"`
	Motion     bool   `json:"motion,omitempty"`
	Intensity  int    `json:"intensity,omitempty"`
	AccessHash int64  `json:"access_hash,omitempty"`
	ThumbB64   string `json:"thumb_b64,omitempty"`
	IsPhoto    bool   `json:"is_photo,omitempty"`
	DocID      int64  `json:"doc_id,omitempty"`
	DocHash    int64  `json:"doc_hash,omitempty"`
	DocRef     string `json:"doc_ref,omitempty"`
}

func (t *TelegramCore) WallpaperFromWire(wp tg.WallPaperClass) WallpaperInfo {
	var info WallpaperInfo
	w, ok := wp.(*tg.WallPaper)
	if !ok {
		return info
	}
	info.ID = w.ID
	info.AccessHash = w.AccessHash
	info.Slug = w.Slug
	info.Pattern = w.Pattern
	info.Dark = w.Dark
	info.Default = w.Default
	info.Creator = w.Creator
	if doc, ok := w.Document.(*tg.Document); ok {
		info.DocID = doc.ID
		info.DocHash = doc.AccessHash
		info.DocRef = string(doc.FileReference)
		info.IsPhoto = true
		info.ThumbB64 = extractStrippedThumbB64(doc.Thumbs)
		t.cacheFileInfo(doc.ID, doc.AccessHash, doc.FileReference)
	}
	if w.Flags.Has(2) {
		s := w.Settings
		info.Blurred = s.Blur
		info.Motion = s.Motion
		info.Rotation = s.Rotation
		if s.Flags.Has(3) {
			info.Intensity = s.Intensity
		}
		if s.Flags.Has(0) {
			info.Colors = append(info.Colors, s.BackgroundColor)
		}
		if s.Flags.Has(4) {
			info.Colors = append(info.Colors, s.SecondBackgroundColor)
		}
		if s.Flags.Has(5) {
			info.Colors = append(info.Colors, s.ThirdBackgroundColor)
		}
		if s.Flags.Has(6) {
			info.Colors = append(info.Colors, s.FourthBackgroundColor)
		}
	}
	return info
}

func WallpaperSettingsFromInfo(info WallpaperInfo) tg.WallPaperSettings {
	s := tg.WallPaperSettings{Blur: info.Blurred, Motion: info.Motion, Rotation: info.Rotation}
	if len(info.Colors) > 0 {
		s.SetBackgroundColor(info.Colors[0])
	}
	if len(info.Colors) > 1 {
		s.SetSecondBackgroundColor(info.Colors[1])
	}
	if len(info.Colors) > 2 {
		s.SetThirdBackgroundColor(info.Colors[2])
	}
	if len(info.Colors) > 3 {
		s.SetFourthBackgroundColor(info.Colors[3])
	}
	if info.Intensity != 0 {
		s.SetIntensity(info.Intensity)
	}
	return s
}

func (t *TelegramCore) GetWallpapers() ([]WallpaperInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	resp, err := api.AccountGetWallPapers(ctx, 0)
	if err != nil {
		return nil, err
	}
	wps, ok := resp.(*tg.AccountWallPapers)
	if !ok {
		return nil, nil
	}
	var result []WallpaperInfo
	for _, wpClass := range wps.Wallpapers {
		wp, ok := wpClass.(*tg.WallPaper)
		if !ok {
			continue
		}
		info := WallpaperInfo{
			ID:      wp.ID,
			Slug:    wp.Slug,
			Pattern: wp.Pattern,
			Dark:    wp.Dark,
			Default: wp.Default,
		}
		if wp.Flags.Has(2) {
			s := wp.Settings
			var colors []int
			if s.Flags.Has(0) {
				colors = append(colors, s.BackgroundColor)
			}
			if s.Flags.Has(4) {
				colors = append(colors, s.SecondBackgroundColor)
			}
			if s.Flags.Has(5) {
				colors = append(colors, s.ThirdBackgroundColor)
			}
			if s.Flags.Has(6) {
				colors = append(colors, s.FourthBackgroundColor)
			}
			info.Colors = colors
			info.Rotation = s.Rotation
			info.Blurred = s.Blur
		}
		if doc, ok := wp.Document.(*tg.Document); ok {
			info.DocID = doc.ID
			info.DocHash = doc.AccessHash
			info.DocRef = base64.StdEncoding.EncodeToString(doc.FileReference)
			isPhoto := false
			for _, attr := range doc.Attributes {
				if _, ok := attr.(*tg.DocumentAttributeImageSize); ok {
					isPhoto = true
					break
				}
			}
			if isPhoto || (!wp.Pattern && len(info.Colors) == 0) {
				info.IsPhoto = true
			}
			var bestPhotoSize *tg.PhotoSize
			for _, thumb := range doc.Thumbs {
				switch th := thumb.(type) {
				case *tg.PhotoCachedSize:
					if len(th.Bytes) > 0 {
						info.ThumbB64 = base64.StdEncoding.EncodeToString(th.Bytes)
					}
				case *tg.PhotoStrippedSize:
					if len(th.Bytes) > 0 {
						info.ThumbB64 = base64.StdEncoding.EncodeToString(inflateStrippedThumb(th.Bytes))
					}
				case *tg.PhotoSize:
					if bestPhotoSize == nil || th.Type == "s" || (th.Type == "m" && bestPhotoSize.Type != "s") {
						bestPhotoSize = th
					}
				}
				if info.ThumbB64 != "" {
					break
				}
			}
			if info.ThumbB64 == "" && bestPhotoSize != nil {
				loc := &tg.InputDocumentFileLocation{
					ID:            doc.ID,
					AccessHash:    doc.AccessHash,
					FileReference: doc.FileReference,
					ThumbSize:     bestPhotoSize.Type,
				}
				result, err := api.UploadGetFile(ctx, &tg.UploadGetFileRequest{
					Location: loc,
					Limit:    262144,
				})
				if err == nil {
					if file, ok := result.(*tg.UploadFile); ok && len(file.Bytes) > 0 {
						info.ThumbB64 = base64.StdEncoding.EncodeToString(file.Bytes)
					}
				}
			}
		}
		result = append(result, info)
	}
	return result, nil
}

func (t *TelegramCore) DownloadWallpaperDocument(docID int64, accessHash int64, fileRef []byte) ([]byte, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	loc := &tg.InputDocumentFileLocation{
		ID:            docID,
		AccessHash:    accessHash,
		FileReference: fileRef,
	}
	var buf bytes.Buffer
	d := downloader.NewDownloader()
	_, err = d.Download(api, loc).Stream(ctx, &buf)
	if err != nil {
		return nil, fmt.Errorf("download wallpaper doc: %w", err)
	}
	return buf.Bytes(), nil
}

type ChatThemeInfo struct {
	Emoticon         string `json:"emoticon"`
	ID               int64  `json:"id"`
	IsDark           bool   `json:"is_dark"`
	AccentColor      int    `json:"accent_color"`
	MessageColors    []int  `json:"message_colors,omitempty"`
	BgColors         []int  `json:"bg_colors,omitempty"`
	PatternIntensity int    `json:"pattern_intensity,omitempty"`
}

func (t *TelegramCore) GetChatThemesList() ([]ChatThemeInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	resp, err := api.AccountGetChatThemes(ctx, 0)
	if err != nil {
		return nil, err
	}
	themes, ok := resp.(*tg.AccountThemes)
	if !ok {
		return nil, nil
	}
	var result []ChatThemeInfo
	for _, th := range themes.Themes {
		if !th.ForChat {
			continue
		}
		emoticon, _ := th.GetEmoticon()
		for _, s := range th.Settings {
			isDark := false
			switch s.BaseTheme.(type) {
			case *tg.BaseThemeNight, *tg.BaseThemeTinted:
				isDark = true
			}
			info := ChatThemeInfo{
				Emoticon:    emoticon,
				ID:          th.ID,
				IsDark:      isDark,
				AccentColor: s.AccentColor,
			}
			if mc, ok := s.GetMessageColors(); ok {
				info.MessageColors = mc
			}
			if wp, ok := s.GetWallpaper(); ok {
				if wpFull, ok := wp.(*tg.WallPaper); ok {
					if wpSettings, ok := wpFull.GetSettings(); ok {
						var bgc []int
						if c, ok := wpSettings.GetBackgroundColor(); ok {
							bgc = append(bgc, c)
						}
						if c, ok := wpSettings.GetSecondBackgroundColor(); ok {
							bgc = append(bgc, c)
						}
						if c, ok := wpSettings.GetThirdBackgroundColor(); ok {
							bgc = append(bgc, c)
						}
						if c, ok := wpSettings.GetFourthBackgroundColor(); ok {
							bgc = append(bgc, c)
						}
						info.BgColors = bgc
						if in, ok := wpSettings.GetIntensity(); ok {
							info.PatternIntensity = in
						}
					}
				}
			}
			result = append(result, info)
		}
	}
	return result, nil
}

func (t *TelegramCore) GetPeerColorPalette() ([]PeerColorEntry, error) {
	result, err := t.HelpGetPeerColors(0)
	if err != nil {
		return nil, err
	}
	colors, ok := result.(*tg.HelpPeerColors)
	if !ok {
		return nil, nil
	}
	entries := make([]PeerColorEntry, 0, len(colors.Colors))
	for _, opt := range colors.Colors {
		entry := PeerColorEntry{
			ColorID:         opt.ColorID,
			Hidden:          opt.Hidden,
			ChannelMinLevel: opt.ChannelMinLevel,
			GroupMinLevel:   opt.GroupMinLevel,
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

func (t *TelegramCore) GetColorLevelRequirements() (map[string]interface{}, error) {
	palette, err := t.GetPeerColorPalette()
	if err != nil {
		return nil, err
	}
	t.mu.RLock()
	defer t.mu.RUnlock()
	if !t.authed || t.api == nil {
		return nil, ErrAuth
	}
	channelLevels := map[string]int{}
	groupLevels := map[string]int{}
	for _, c := range palette {
		channelLevels[strconv.Itoa(c.ColorID)] = c.ChannelMinLevel
		groupLevels[strconv.Itoa(c.ColorID)] = c.GroupMinLevel
	}
	return map[string]interface{}{
		"bg_icon_level_min":      t.appConfigIntNoLock("channel_bg_icon_level_min", 5),
		"emoji_status_level_min": t.appConfigIntNoLock("channel_emoji_status_level_min", 8),
		"channel_levels":         channelLevels,
		"group_levels":           groupLevels,
	}, nil
}

func (t *TelegramCore) HelpGetPeerProfileColors(hash int) (tg.HelpPeerColorsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetPeerProfileColors(ctx, hash)
}

func PremiumPlansFromPromo(promo *tg.HelpPremiumPromo) PremiumPromo {
	if promo == nil {
		return PremiumPromo{}
	}
	out := PremiumPromo{StatusText: promo.StatusText}
	for _, o := range promo.PeriodOptions {
		out.Options = append(out.Options, PremiumPlanOption{
			Months:             o.Months,
			Currency:           o.Currency,
			Amount:             o.Amount,
			BotURL:             o.BotURL,
			StoreProduct:       o.StoreProduct,
			Current:            o.Current,
			CanPurchaseUpgrade: o.CanPurchaseUpgrade,
		})
	}
	return out
}

func (t *TelegramCore) GetPremiumPromo() (PremiumPromo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return PremiumPromo{}, err
	}
	promo, err := api.HelpGetPremiumPromo(ctx)
	if err != nil {
		return PremiumPromo{}, fmt.Errorf("get premium promo: %w", err)
	}
	return PremiumPlansFromPromo(promo), nil
}

func (t *TelegramCore) HelpGetPremiumPromo() (*tg.HelpPremiumPromo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetPremiumPromo(ctx)
}

func (t *TelegramCore) HelpGetPromoData() (tg.HelpPromoDataClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetPromoData(ctx)
}

func (t *TelegramCore) HelpGetRecentMeURLs(referer string) (*tg.HelpRecentMeURLs, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetRecentMeURLs(ctx, referer)
}

func (t *TelegramCore) HelpGetSupport() (*tg.HelpSupport, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetSupport(ctx)
}

func (t *TelegramCore) HelpGetSupportName() (*tg.HelpSupportName, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetSupportName(ctx)
}

func (t *TelegramCore) HelpGetTermsOfServiceUpdate() (tg.HelpTermsOfServiceUpdateClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetTermsOfServiceUpdate(ctx)
}

func (t *TelegramCore) HelpGetTimezonesList(hash int) (tg.HelpTimezonesListClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetTimezonesList(ctx, hash)
}

func (t *TelegramCore) timezoneOffsetNoLock(id string) (int, bool) {
	if id == "" || t.api == nil {
		return 0, false
	}
	t.timezoneOffsetsMu.RLock()
	cache := t.timezoneOffsets
	t.timezoneOffsetsMu.RUnlock()
	if cache == nil {
		result, err := t.api.HelpGetTimezonesList(t.ctx, 0)
		if err != nil {
			return 0, false
		}
		list, ok := result.(*tg.HelpTimezonesList)
		if !ok {
			return 0, false
		}
		cache = make(map[string]int, len(list.Timezones))
		for _, tz := range list.Timezones {
			cache[tz.ID] = tz.UtcOffset
		}
		t.timezoneOffsetsMu.Lock()
		t.timezoneOffsets = cache
		t.timezoneOffsetsMu.Unlock()
	}
	off, ok := cache[id]
	return off, ok
}

func (t *TelegramCore) HelpGetUserInfo(userid tg.InputUserClass) (tg.HelpUserInfoClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.HelpGetUserInfo(ctx, userid)
}

func (t *TelegramCore) HelpHidePromoData(peer tg.InputPeerClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.HelpHidePromoData(ctx, peer)
}

func (t *TelegramCore) HelpSaveAppLog(events []tg.InputAppEvent) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.HelpSaveAppLog(ctx, events)
}

func (t *TelegramCore) HelpSetBotUpdatesStatus(request *tg.HelpSetBotUpdatesStatusRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.HelpSetBotUpdatesStatus(ctx, request)
}

func (t *TelegramCore) InvokeJSON(jsonData string, useSnakeCase bool) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	return api.InvokeJSON(ctx, jsonData, useSnakeCase)
}

func (t *TelegramCore) LangpackGetDifference(request *tg.LangpackGetDifferenceRequest) (*tg.LangPackDifference, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.LangpackGetDifference(ctx, request)
}

func (t *TelegramCore) LangpackGetLangPack(request *tg.LangpackGetLangPackRequest) (*tg.LangPackDifference, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.LangpackGetLangPack(ctx, request)
}

func (t *TelegramCore) LangpackGetLanguage(request *tg.LangpackGetLanguageRequest) (*tg.LangPackLanguage, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.LangpackGetLanguage(ctx, request)
}

func (t *TelegramCore) ensurePreAuthAPI() (*tg.Client, context.Context, error) {
	t.mu.RLock()
	if t.api != nil {
		api, ctx := t.api, t.ctx
		t.mu.RUnlock()
		return api, ctx, nil
	}
	if t.preAuthAPI != nil {
		api, ctx := t.preAuthAPI, t.ctx
		t.mu.RUnlock()
		return api, ctx, nil
	}
	t.mu.RUnlock()

	t.preAuthConnectMu.Lock()
	defer t.preAuthConnectMu.Unlock()

	t.mu.RLock()
	if t.api != nil {
		api, ctx := t.api, t.ctx
		t.mu.RUnlock()
		return api, ctx, nil
	}
	if t.preAuthAPI != nil {
		api, ctx := t.preAuthAPI, t.ctx
		t.mu.RUnlock()
		return api, ctx, nil
	}
	t.mu.RUnlock()

	t.mu.Lock()
	t.initClient()
	t.ctx, t.cancel = context.WithCancel(context.Background())
	ctx := t.ctx
	t.mu.Unlock()

	clientReady := make(chan struct{})
	errCh := make(chan error, 1)
	t.wg.Add(1)
	go func() {
		defer t.wg.Done()
		errCh <- t.client.Run(ctx, func(rctx context.Context) error {
			api := t.guardedClient()
			t.mu.Lock()
			t.preAuthAPI = api
			t.mu.Unlock()
			close(clientReady)
			<-rctx.Done()
			return rctx.Err()
		})
	}()

	select {
	case <-clientReady:
	case err := <-errCh:
		return nil, nil, fmt.Errorf("pre-auth connect: %w", err)
	case <-time.After(30 * time.Second):
		return nil, nil, fmt.Errorf("pre-auth connect timeout")
	}

	t.mu.RLock()
	api := t.preAuthAPI
	t.mu.RUnlock()
	if api == nil {
		return nil, nil, ErrAuth
	}
	return api, ctx, nil
}

func (t *TelegramCore) LangpackGetLanguages(langpack string) ([]tg.LangPackLanguage, error) {
	api, ctx, err := t.ensurePreAuthAPI()
	if err != nil {
		return nil, err
	}
	return api.LangpackGetLanguages(ctx, langpack)
}

func (t *TelegramCore) LangpackGetStrings(request *tg.LangpackGetStringsRequest) ([]tg.LangPackStringClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.LangpackGetStrings(ctx, request)
}

func (t *TelegramCore) LangpackGetStringsMap(langCode string, keys []string) (map[string]string, error) {
	api, ctx, err := t.ensurePreAuthAPI()
	if err != nil {
		return nil, err
	}
	strs, err := api.LangpackGetStrings(ctx, &tg.LangpackGetStringsRequest{
		LangPack: "tdesktop",
		LangCode: langCode,
		Keys:     keys,
	})
	if err != nil {
		return nil, err
	}
	out := make(map[string]string, len(strs))
	for _, s := range strs {
		switch v := s.(type) {
		case *tg.LangPackString:
			out[v.Key] = v.Value
		case *tg.LangPackStringPluralized:
			if v.ZeroValue != "" {
				out[v.Key+"#zero"] = v.ZeroValue
			}
			if v.OneValue != "" {
				out[v.Key+"#one"] = v.OneValue
			}
			if v.TwoValue != "" {
				out[v.Key+"#two"] = v.TwoValue
			}
			if v.FewValue != "" {
				out[v.Key+"#few"] = v.FewValue
			}
			if v.ManyValue != "" {
				out[v.Key+"#many"] = v.ManyValue
			}
			if v.OtherValue != "" {
				out[v.Key+"#other"] = v.OtherValue
			}
		}
	}
	return out, nil
}

func (t *TelegramCore) SetInterfaceLanguage(langCode string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.LangpackGetLangPack(ctx, &tg.LangpackGetLangPackRequest{
		LangPack: "tdesktop",
		LangCode: langCode,
	})
	return err
}

func (t *TelegramCore) MessagesAcceptEncryption(request *tg.MessagesAcceptEncryptionRequest) (tg.EncryptedChatClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesAcceptEncryption(ctx, request)
}

func (t *TelegramCore) MessagesAcceptURLAuth(request *tg.MessagesAcceptURLAuthRequest) (tg.URLAuthResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesAcceptURLAuth(ctx, request)
}

func (t *TelegramCore) MessagesAddPollAnswer(request *tg.MessagesAddPollAnswerRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesAddPollAnswer(ctx, request)
}

func (t *TelegramCore) MessagesAppendTodoList(request *tg.MessagesAppendTodoListRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesAppendTodoList(ctx, request)
}

func (t *TelegramCore) MessagesCheckHistoryImport(importhead string) (*tg.MessagesHistoryImportParsed, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesCheckHistoryImport(ctx, importhead)
}

func (t *TelegramCore) MessagesCheckHistoryImportPeer(peer tg.InputPeerClass) (*tg.MessagesCheckedHistoryImportPeer, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesCheckHistoryImportPeer(ctx, peer)
}

func (t *TelegramCore) MessagesCheckQuickReplyShortcut(shortcut string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesCheckQuickReplyShortcut(ctx, shortcut)
}

func (t *TelegramCore) MessagesCheckURLAuthMatchCode(request *tg.MessagesCheckURLAuthMatchCodeRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesCheckURLAuthMatchCode(ctx, request)
}

func (t *TelegramCore) MessagesClearAllDrafts() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesClearAllDrafts(ctx)
}

func (t *TelegramCore) MessagesClearRecentReactions() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesClearRecentReactions(ctx)
}

func (t *TelegramCore) MessagesClearRecentStickers(request *tg.MessagesClearRecentStickersRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesClearRecentStickers(ctx, request)
}

func (t *TelegramCore) MessagesClickSponsoredMessage(request *tg.MessagesClickSponsoredMessageRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesClickSponsoredMessage(ctx, request)
}

func (t *TelegramCore) MessagesComposeMessageWithAI(request *tg.MessagesComposeMessageWithAIRequest) (*tg.MessagesComposedMessageWithAI, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesComposeMessageWithAI(ctx, request)
}

func (t *TelegramCore) MessagesDeclineURLAuth(url string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesDeclineURLAuth(ctx, url)
}

func (t *TelegramCore) MessagesDeleteChat(chatid int64) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesDeleteChat(ctx, chatid)
}

func (t *TelegramCore) MessagesDeleteFactCheck(request *tg.MessagesDeleteFactCheckRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesDeleteFactCheck(ctx, request)
}

func (t *TelegramCore) MessagesDeletePhoneCallHistory(request *tg.MessagesDeletePhoneCallHistoryRequest) (*tg.MessagesAffectedFoundMessages, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesDeletePhoneCallHistory(ctx, request)
}

func (t *TelegramCore) ClearCallHistory(revoke bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.MessagesDeletePhoneCallHistoryRequest{}
	if revoke {
		req.SetRevoke(true)
	}
	for {
		result, err := api.MessagesDeletePhoneCallHistory(ctx, req)
		if err != nil {
			return fmt.Errorf("clear call history: %w", err)
		}
		if result.Offset == 0 {
			break
		}
	}
	return nil
}

type CallHistoryEntry struct {
	MsgID      string `json:"msg_id"`
	PeerID     string `json:"peer_id"`
	PeerName   string `json:"peer_name"`
	AvatarPath string `json:"avatar_path,omitempty"`
	Timestamp  int64  `json:"timestamp"`
	Duration   int    `json:"duration"`
	IsOutgoing bool   `json:"is_outgoing"`
	IsMissed   bool   `json:"is_missed"`
	IsVideo    bool   `json:"is_video"`
}

func (t *TelegramCore) GetCallHistory(offsetID int, limit int) ([]CallHistoryEntry, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesSearch(ctx, &tg.MessagesSearchRequest{
		Peer:     &tg.InputPeerEmpty{},
		Q:        "",
		Filter:   &tg.InputMessagesFilterPhoneCalls{},
		Limit:    limit,
		OffsetID: offsetID,
	})
	if err != nil {
		return nil, fmt.Errorf("get call history: %w", err)
	}

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

	entries := make([]CallHistoryEntry, 0, len(rawMsgs))
	for _, m := range rawMsgs {
		svc, ok := m.(*tg.MessageService)
		if !ok {
			continue
		}
		action, ok := svc.Action.(*tg.MessageActionPhoneCall)
		if !ok {
			continue
		}

		entry := CallHistoryEntry{
			MsgID:      strconv.Itoa(svc.ID),
			Timestamp:  int64(svc.Date),
			IsOutgoing: svc.Out,
			IsVideo:    action.Video,
			Duration:   action.Duration,
		}

		if action.Reason != nil {
			switch action.Reason.(type) {
			case *tg.PhoneCallDiscardReasonBusy, *tg.PhoneCallDiscardReasonMissed:
				if !svc.Out {
					entry.IsMissed = true
				}
			}
		}
		if action.Duration == 0 && !svc.Out {
			entry.IsMissed = true
		}

		var peerUserID int64
		if svc.Out {
			if p, ok := svc.PeerID.(*tg.PeerUser); ok {
				peerUserID = p.UserID
			}
		} else {
			if from := svc.FromID; from != nil {
				if p, ok := from.(*tg.PeerUser); ok {
					peerUserID = p.UserID
				}
			} else if p, ok := svc.PeerID.(*tg.PeerUser); ok {
				peerUserID = p.UserID
			}
		}

		if peerUserID != 0 {
			entry.PeerID = strconv.FormatInt(peerUserID, 10)
			entry.PeerName = t.getCachedUserName(peerUserID)
		}

		entries = append(entries, entry)
	}
	return entries, nil
}

func (t *TelegramCore) MessagesDeletePollAnswer(request *tg.MessagesDeletePollAnswerRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesDeletePollAnswer(ctx, request)
}

func (t *TelegramCore) MessagesDeleteQuickReplyMessages(request *tg.MessagesDeleteQuickReplyMessagesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesDeleteQuickReplyMessages(ctx, request)
}

func (t *TelegramCore) MessagesDeleteQuickReplyShortcut(shortcutid int) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesDeleteQuickReplyShortcut(ctx, shortcutid)
}

func (t *TelegramCore) MessagesDeleteRevokedExportedChatInvites(request *tg.MessagesDeleteRevokedExportedChatInvitesRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesDeleteRevokedExportedChatInvites(ctx, request)
}

func (t *TelegramCore) MessagesDeleteSavedHistory(request *tg.MessagesDeleteSavedHistoryRequest) (*tg.MessagesAffectedHistory, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesDeleteSavedHistory(ctx, request)
}

func (t *TelegramCore) MessagesDiscardEncryption(request *tg.MessagesDiscardEncryptionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesDiscardEncryption(ctx, request)
}

func (t *TelegramCore) MessagesEditChatAbout(request *tg.MessagesEditChatAboutRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesEditChatAbout(ctx, request)
}

func (t *TelegramCore) MessagesEditChatAdmin(request *tg.MessagesEditChatAdminRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesEditChatAdmin(ctx, request)
}

func (t *TelegramCore) MessagesEditChatCreator(request *tg.MessagesEditChatCreatorRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesEditChatCreator(ctx, request)
}

func (t *TelegramCore) MessagesEditChatParticipantRank(request *tg.MessagesEditChatParticipantRankRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesEditChatParticipantRank(ctx, request)
}

func (t *TelegramCore) MessagesEditChatPhoto(request *tg.MessagesEditChatPhotoRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesEditChatPhoto(ctx, request)
}

func (t *TelegramCore) MessagesEditChatTitle(request *tg.MessagesEditChatTitleRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesEditChatTitle(ctx, request)
}

func (t *TelegramCore) MessagesEditFactCheck(request *tg.MessagesEditFactCheckRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesEditFactCheck(ctx, request)
}

func (t *TelegramCore) MessagesEditInlineBotMessage(request *tg.MessagesEditInlineBotMessageRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesEditInlineBotMessage(ctx, request)
}

func (t *TelegramCore) MessagesEditQuickReplyShortcut(request *tg.MessagesEditQuickReplyShortcutRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesEditQuickReplyShortcut(ctx, request)
}

func (t *TelegramCore) MessagesGetAdminsWithInvites(peer tg.InputPeerClass) (*tg.MessagesChatAdminsWithInvites, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetAdminsWithInvites(ctx, peer)
}

func (t *TelegramCore) MessagesGetArchivedStickers(request *tg.MessagesGetArchivedStickersRequest) (*tg.MessagesArchivedStickers, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetArchivedStickers(ctx, request)
}

func (t *TelegramCore) MessagesGetAttachedStickers(media tg.InputStickeredMediaClass) ([]tg.StickerSetCoveredClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetAttachedStickers(ctx, media)
}

func (t *TelegramCore) MessagesGetAttachMenuBot(bot tg.InputUserClass) (*tg.AttachMenuBotsBot, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetAttachMenuBot(ctx, bot)
}

func (t *TelegramCore) MessagesGetAttachMenuBots(hash int64) (tg.AttachMenuBotsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetAttachMenuBots(ctx, hash)
}

func (t *TelegramCore) GetAttachMenuBots() ([]AttachMenuBotInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetAttachMenuBots(ctx, 0)
	if err != nil {
		return nil, err
	}
	bots, ok := result.(*tg.AttachMenuBots)
	if !ok {
		return nil, nil
	}
	var out []AttachMenuBotInfo
	for _, b := range bots.Bots {
		if !b.ShowInAttachMenu {
			continue
		}
		out = append(out, AttachMenuBotInfo{
			BotID:     b.BotID,
			ShortName: b.ShortName,
			Inactive:  b.Inactive,
		})
	}
	return out, nil
}

func (t *TelegramCore) GetMainMenuBots() ([]AttachMenuBotInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.MessagesGetAttachMenuBots(ctx, 0)
	if err != nil {
		return nil, err
	}
	bots, ok := result.(*tg.AttachMenuBots)
	if !ok {
		return nil, nil
	}
	usernames := make(map[int64]string, len(bots.Users))
	for _, u := range bots.Users {
		user, ok := u.(*tg.User)
		if !ok {
			continue
		}
		if uname, ok := user.GetUsername(); ok && uname != "" {
			usernames[user.ID] = uname
			continue
		}
		if list, ok := user.GetUsernames(); ok {
			for _, un := range list {
				if un.Active && un.Username != "" {
					usernames[user.ID] = un.Username
					break
				}
			}
		}
	}
	var out []AttachMenuBotInfo
	for _, b := range bots.Bots {
		if !b.ShowInSideMenu {
			continue
		}
		hasMedia := false
		for _, icon := range b.Icons {
			if icon.Name == "default_static" {
				hasMedia = true
				break
			}
		}
		if !hasMedia {
			continue
		}
		out = append(out, AttachMenuBotInfo{
			BotID:     b.BotID,
			ShortName: b.ShortName,
			Inactive:  b.Inactive,
			Username:  usernames[b.BotID],
		})
	}
	return out, nil
}

func (t *TelegramCore) MessagesGetAvailableEffects(hash int) (tg.MessagesAvailableEffectsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetAvailableEffects(ctx, hash)
}

func (t *TelegramCore) MessagesGetAvailableReactions(hash int) (tg.MessagesAvailableReactionsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetAvailableReactions(ctx, hash)
}

func (t *TelegramCore) MessagesGetBotApp(request *tg.MessagesGetBotAppRequest) (*tg.MessagesBotApp, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetBotApp(ctx, request)
}

func (t *TelegramCore) MessagesGetChats(id []int64) (tg.MessagesChatsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetChats(ctx, id)
}

func (t *TelegramCore) MessagesGetCustomEmojiDocuments(documentid []int64) ([]tg.DocumentClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetCustomEmojiDocuments(ctx, documentid)
}

func (t *TelegramCore) MessagesGetDefaultTagReactions(hash int64) (tg.MessagesReactionsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetDefaultTagReactions(ctx, hash)
}

func (t *TelegramCore) MessagesGetDiscussionMessage(request *tg.MessagesGetDiscussionMessageRequest) (*tg.MessagesDiscussionMessage, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetDiscussionMessage(ctx, request)
}

func (t *TelegramCore) MessagesGetDocumentByHash(request *tg.MessagesGetDocumentByHashRequest) (tg.DocumentClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetDocumentByHash(ctx, request)
}

func (t *TelegramCore) MessagesGetEmojiGameInfo() (tg.MessagesEmojiGameInfoClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiGameInfo(ctx)
}

func (t *TelegramCore) MessagesGetEmojiGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiGroups(ctx, hash)
}

func (t *TelegramCore) MessagesGetEmojiKeywords(langcode string) (interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiKeywords(ctx, langcode)
}

type emojiKeywordDiffEntry struct {
	Keyword   string
	Emoticons []string
	Deleted   bool
}

type emojiKeywordDiffResult struct {
	LangCode string
	Version  int
	Keywords []emojiKeywordDiffEntry
}

func (t *TelegramCore) MessagesGetEmojiKeywordsDifference(langCode string, fromVersion int) (interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	raw, err := api.MessagesGetEmojiKeywordsDifference(ctx, &tg.MessagesGetEmojiKeywordsDifferenceRequest{
		LangCode:    langCode,
		FromVersion: fromVersion,
	})
	if err != nil {
		return nil, err
	}
	out := &emojiKeywordDiffResult{LangCode: raw.LangCode, Version: raw.Version}
	for _, kw := range raw.Keywords {
		switch v := kw.(type) {
		case *tg.EmojiKeywordDeleted:
			out.Keywords = append(out.Keywords, emojiKeywordDiffEntry{
				Keyword:   v.Keyword,
				Emoticons: v.Emoticons,
				Deleted:   true,
			})
		case *tg.EmojiKeyword:
			out.Keywords = append(out.Keywords, emojiKeywordDiffEntry{
				Keyword:   v.Keyword,
				Emoticons: v.Emoticons,
			})
		}
	}
	return out, nil
}

func (t *TelegramCore) MessagesGetEmojiKeywordsLanguages(langcodes []string) (interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiKeywordsLanguages(ctx, langcodes)
}

func (t *TelegramCore) MessagesGetEmojiProfilePhotoGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiProfilePhotoGroups(ctx, hash)
}

func (t *TelegramCore) MessagesGetEmojiStatusGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiStatusGroups(ctx, hash)
}

func (t *TelegramCore) MessagesGetEmojiStickerGroups(hash int) (tg.MessagesEmojiGroupsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiStickerGroups(ctx, hash)
}

func (t *TelegramCore) MessagesGetEmojiStickers(hash int64) (tg.MessagesAllStickersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiStickers(ctx, hash)
}

func (t *TelegramCore) MessagesGetEmojiURL(langcode string) (*tg.EmojiURL, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetEmojiURL(ctx, langcode)
}

func (t *TelegramCore) MessagesGetExportedChatInvite(request *tg.MessagesGetExportedChatInviteRequest) (tg.MessagesExportedChatInviteClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetExportedChatInvite(ctx, request)
}

func (t *TelegramCore) MessagesGetExportedChatInvites(request *tg.MessagesGetExportedChatInvitesRequest) (*tg.MessagesExportedChatInvites, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetExportedChatInvites(ctx, request)
}

func (t *TelegramCore) MessagesGetExtendedMedia(request *tg.MessagesGetExtendedMediaRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetExtendedMedia(ctx, request)
}

func (t *TelegramCore) MessagesGetFactCheck(request *tg.MessagesGetFactCheckRequest) ([]tg.FactCheck, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetFactCheck(ctx, request)
}

func (t *TelegramCore) MessagesGetFeaturedEmojiStickers(hash int64) (tg.MessagesFeaturedStickersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetFeaturedEmojiStickers(ctx, hash)
}

func (t *TelegramCore) MessagesGetForumTopicsByID(request *tg.MessagesGetForumTopicsByIDRequest) (*tg.MessagesForumTopics, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetForumTopicsByID(ctx, request)
}

func (t *TelegramCore) MessagesGetFutureChatCreatorAfterLeave(peer tg.InputPeerClass) (tg.UserClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetFutureChatCreatorAfterLeave(ctx, peer)
}

func (t *TelegramCore) MessagesGetGameHighScores(request *tg.MessagesGetGameHighScoresRequest) (*tg.MessagesHighScores, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetGameHighScores(ctx, request)
}

func (t *TelegramCore) MessagesGetInlineGameHighScores(request *tg.MessagesGetInlineGameHighScoresRequest) (*tg.MessagesHighScores, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetInlineGameHighScores(ctx, request)
}

func (t *TelegramCore) MessagesGetMaskStickers(hash int64) (tg.MessagesAllStickersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetMaskStickers(ctx, hash)
}

func (t *TelegramCore) MessagesGetMessageEditData(request *tg.MessagesGetMessageEditDataRequest) (*tg.MessagesMessageEditData, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetMessageEditData(ctx, request)
}

func (t *TelegramCore) MessagesGetMessages(id []tg.InputMessageClass) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetMessages(ctx, id)
}

func (t *TelegramCore) MessagesGetMessagesReactions(request *tg.MessagesGetMessagesReactionsRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetMessagesReactions(ctx, request)
}

func (t *TelegramCore) MessagesGetMyStickers(request *tg.MessagesGetMyStickersRequest) (*tg.MessagesMyStickers, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetMyStickers(ctx, request)
}

func (t *TelegramCore) MessagesGetOldFeaturedStickers(request *tg.MessagesGetOldFeaturedStickersRequest) (tg.MessagesFeaturedStickersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetOldFeaturedStickers(ctx, request)
}

func (t *TelegramCore) MessagesGetPaidReactionPrivacy() (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetPaidReactionPrivacy(ctx)
}

func (t *TelegramCore) MessagesGetPeerDialogs(peers []tg.InputDialogPeerClass) (*tg.MessagesPeerDialogs, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetPeerDialogs(ctx, peers)
}

func (t *TelegramCore) MessagesGetPinnedSavedDialogs() (tg.MessagesSavedDialogsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetPinnedSavedDialogs(ctx)
}

func (t *TelegramCore) MessagesGetPreparedInlineMessage(request *tg.MessagesGetPreparedInlineMessageRequest) (*tg.MessagesPreparedInlineMessage, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetPreparedInlineMessage(ctx, request)
}

func (t *TelegramCore) MessagesGetQuickReplies(hash int64) (tg.MessagesQuickRepliesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetQuickReplies(ctx, hash)
}

func (t *TelegramCore) MessagesGetQuickReplyMessages(request *tg.MessagesGetQuickReplyMessagesRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetQuickReplyMessages(ctx, request)
}

func (t *TelegramCore) MessagesGetRecentLocations(request *tg.MessagesGetRecentLocationsRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetRecentLocations(ctx, request)
}

func (t *TelegramCore) MessagesGetRecentReactions(request *tg.MessagesGetRecentReactionsRequest) (tg.MessagesReactionsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetRecentReactions(ctx, request)
}

func (t *TelegramCore) MessagesGetReplies(request *tg.MessagesGetRepliesRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetReplies(ctx, request)
}

func (t *TelegramCore) MessagesGetSavedDialogs(request *tg.MessagesGetSavedDialogsRequest) (tg.MessagesSavedDialogsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSavedDialogs(ctx, request)
}

func (t *TelegramCore) MessagesGetSavedDialogsByID(request *tg.MessagesGetSavedDialogsByIDRequest) (tg.MessagesSavedDialogsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSavedDialogsByID(ctx, request)
}

func (t *TelegramCore) MessagesGetSavedGifs(hash int64) (tg.MessagesSavedGifsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSavedGifs(ctx, hash)
}

func (t *TelegramCore) MessagesGetSavedHistory(request *tg.MessagesGetSavedHistoryRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSavedHistory(ctx, request)
}

func (t *TelegramCore) MessagesGetSavedReactionTags(request *tg.MessagesGetSavedReactionTagsRequest) (tg.MessagesSavedReactionTagsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSavedReactionTags(ctx, request)
}

func (t *TelegramCore) MessagesGetScheduledMessages(request *tg.MessagesGetScheduledMessagesRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetScheduledMessages(ctx, request)
}

func (t *TelegramCore) MessagesGetSearchResultsPositions(request *tg.MessagesGetSearchResultsPositionsRequest) (*tg.MessagesSearchResultsPositions, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSearchResultsPositions(ctx, request)
}

func (t *TelegramCore) MessagesGetSplitRanges() ([]tg.MessageRange, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSplitRanges(ctx)
}

func (t *TelegramCore) MessagesGetSponsoredMessages(request *tg.MessagesGetSponsoredMessagesRequest) (tg.MessagesSponsoredMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetSponsoredMessages(ctx, request)
}

func (t *TelegramCore) MessagesGetStickers(request *tg.MessagesGetStickersRequest) (tg.MessagesStickersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetStickers(ctx, request)
}

func (t *TelegramCore) MessagesGetTopReactions(request *tg.MessagesGetTopReactionsRequest) (tg.MessagesReactionsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetTopReactions(ctx, request)
}

func (t *TelegramCore) MessagesGetUnreadPollVotes(request *tg.MessagesGetUnreadPollVotesRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetUnreadPollVotes(ctx, request)
}

func (t *TelegramCore) MessagesGetWebPage(request *tg.MessagesGetWebPageRequest) (*tg.MessagesWebPage, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesGetWebPage(ctx, request)
}

func (t *TelegramCore) MessagesHideAllChatJoinRequests(request *tg.MessagesHideAllChatJoinRequestsRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesHideAllChatJoinRequests(ctx, request)
}

func (t *TelegramCore) MessagesHidePeerSettingsBar(peer tg.InputPeerClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesHidePeerSettingsBar(ctx, peer)
}

func (t *TelegramCore) MessagesInitHistoryImport(request *tg.MessagesInitHistoryImportRequest) (*tg.MessagesHistoryImport, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesInitHistoryImport(ctx, request)
}

func (t *TelegramCore) MessagesInstallStickerSet(request *tg.MessagesInstallStickerSetRequest) (tg.MessagesStickerSetInstallResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesInstallStickerSet(ctx, request)
}

func (t *TelegramCore) MessagesProlongWebView(request *tg.MessagesProlongWebViewRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesProlongWebView(ctx, request)
}

func (t *TelegramCore) MessagesRateTranscribedAudio(request *tg.MessagesRateTranscribedAudioRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesRateTranscribedAudio(ctx, request)
}

func (t *TelegramCore) MessagesReadDiscussion(request *tg.MessagesReadDiscussionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReadDiscussion(ctx, request)
}

func (t *TelegramCore) MessagesReadEncryptedHistory(request *tg.MessagesReadEncryptedHistoryRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReadEncryptedHistory(ctx, request)
}

func (t *TelegramCore) MessagesReadFeaturedStickers(id []int64) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReadFeaturedStickers(ctx, id)
}

func (t *TelegramCore) MessagesReadMessageContents(id []int) (*tg.MessagesAffectedMessages, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesReadMessageContents(ctx, id)
}

func (t *TelegramCore) MessagesReadPollVotes(request *tg.MessagesReadPollVotesRequest) (*tg.MessagesAffectedHistory, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesReadPollVotes(ctx, request)
}

func (t *TelegramCore) MessagesReadSavedHistory(request *tg.MessagesReadSavedHistoryRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReadSavedHistory(ctx, request)
}

func (t *TelegramCore) MessagesReceivedMessages(maxid int) ([]tg.ReceivedNotifyMessage, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesReceivedMessages(ctx, maxid)
}

func (t *TelegramCore) MessagesReceivedQueue(maxqts int) ([]int64, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesReceivedQueue(ctx, maxqts)
}

func (t *TelegramCore) MessagesReorderPinnedSavedDialogs(request *tg.MessagesReorderPinnedSavedDialogsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReorderPinnedSavedDialogs(ctx, request)
}

func (t *TelegramCore) MessagesReorderQuickReplies(order []int) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReorderQuickReplies(ctx, order)
}

func (t *TelegramCore) MessagesReorderStickerSets(request *tg.MessagesReorderStickerSetsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReorderStickerSets(ctx, request)
}

func (t *TelegramCore) ReorderStickerSets(order []int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesReorderStickerSets(ctx, &tg.MessagesReorderStickerSetsRequest{
		Order: order,
	})
	return err
}

func (t *TelegramCore) MessagesReport(request *tg.MessagesReportRequest) (tg.ReportResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesReport(ctx, request)
}

func (t *TelegramCore) MessagesReportEncryptedSpam(peer tg.InputEncryptedChat) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReportEncryptedSpam(ctx, peer)
}

func (t *TelegramCore) MessagesReportMessagesDelivery(request *tg.MessagesReportMessagesDeliveryRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReportMessagesDelivery(ctx, request)
}

func (t *TelegramCore) MessagesReportMusicListen(request *tg.MessagesReportMusicListenRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReportMusicListen(ctx, request)
}

func (t *TelegramCore) ReportMusicListen(docID int64, accessHash int64, fileRef []byte, durationSec int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesReportMusicListen(ctx, &tg.MessagesReportMusicListenRequest{
		ID: &tg.InputDocument{
			ID:            docID,
			AccessHash:    accessHash,
			FileReference: fileRef,
		},
		ListenedDuration: durationSec,
	})
	return err
}

func (t *TelegramCore) RefreshDocumentFileRef(docID int64, chatID string, msgID string) ([]byte, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()

	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}

	var msgs tg.MessagesMessagesClass
	if ch, ok := inputPeer.(*tg.InputPeerChannel); ok {
		msgs, err = t.api.ChannelsGetMessages(t.ctx, &tg.ChannelsGetMessagesRequest{
			Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: ch.AccessHash},
			ID:      []tg.InputMessageClass{&tg.InputMessageID{ID: id}},
		})
	} else {
		msgs, err = t.api.MessagesGetMessages(t.ctx, []tg.InputMessageClass{&tg.InputMessageID{ID: id}})
	}
	if err != nil {
		return nil, err
	}

	var messageList []tg.MessageClass
	switch m := msgs.(type) {
	case *tg.MessagesMessages:
		messageList = m.Messages
	case *tg.MessagesMessagesSlice:
		messageList = m.Messages
	case *tg.MessagesChannelMessages:
		messageList = m.Messages
	}
	for _, msg := range messageList {
		m, ok := msg.(*tg.Message)
		if !ok || m.Media == nil {
			continue
		}
		if md, ok := m.Media.(*tg.MessageMediaDocument); ok {
			if d, ok := md.Document.(*tg.Document); ok && d.ID == docID {
				return d.FileReference, nil
			}
		}
	}
	return nil, fmt.Errorf("document %d not found in message", docID)
}

func (t *TelegramCore) MessagesReportReaction(request *tg.MessagesReportReactionRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReportReaction(ctx, request)
}

func (t *TelegramCore) MessagesReportReadMetrics(request *tg.MessagesReportReadMetricsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReportReadMetrics(ctx, request)
}

func (t *TelegramCore) MessagesReportSpam(peer tg.InputPeerClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesReportSpam(ctx, peer)
}

func (t *TelegramCore) MessagesReportSponsoredMessage(request *tg.MessagesReportSponsoredMessageRequest) (tg.ChannelsSponsoredMessageReportResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesReportSponsoredMessage(ctx, request)
}

func (t *TelegramCore) MessagesRequestAppWebView(request *tg.MessagesRequestAppWebViewRequest) (*tg.WebViewResultURL, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesRequestAppWebView(ctx, request)
}

func (t *TelegramCore) MessagesRequestEncryption(request *tg.MessagesRequestEncryptionRequest) (tg.EncryptedChatClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesRequestEncryption(ctx, request)
}

func (t *TelegramCore) MessagesRequestMainWebView(request *tg.MessagesRequestMainWebViewRequest) (*tg.WebViewResultURL, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesRequestMainWebView(ctx, request)
}

func (t *TelegramCore) MessagesRequestSimpleWebView(request *tg.MessagesRequestSimpleWebViewRequest) (*tg.WebViewResultURL, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesRequestSimpleWebView(ctx, request)
}

func (t *TelegramCore) MessagesRequestURLAuth(request *tg.MessagesRequestURLAuthRequest) (tg.URLAuthResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesRequestURLAuth(ctx, request)
}

func (t *TelegramCore) MessagesRequestWebView(request *tg.MessagesRequestWebViewRequest) (*tg.WebViewResultURL, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesRequestWebView(ctx, request)
}

func (t *TelegramCore) MessagesSaveDefaultSendAs(request *tg.MessagesSaveDefaultSendAsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSaveDefaultSendAs(ctx, request)
}

func (t *TelegramCore) MessagesSaveGif(request *tg.MessagesSaveGifRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSaveGif(ctx, request)
}

func (t *TelegramCore) MessagesSavePreparedInlineMessage(request *tg.MessagesSavePreparedInlineMessageRequest) (*tg.MessagesBotPreparedInlineMessage, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSavePreparedInlineMessage(ctx, request)
}

func (t *TelegramCore) MessagesSaveRecentSticker(request *tg.MessagesSaveRecentStickerRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSaveRecentSticker(ctx, request)
}

func (t *TelegramCore) MessagesSearchCustomEmoji(request *tg.MessagesSearchCustomEmojiRequest) (tg.EmojiListClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSearchCustomEmoji(ctx, request)
}

func (t *TelegramCore) MessagesSearchEmojiStickerSets(request *tg.MessagesSearchEmojiStickerSetsRequest) (tg.MessagesFoundStickerSetsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSearchEmojiStickerSets(ctx, request)
}

func (t *TelegramCore) MessagesSearchSentMedia(request *tg.MessagesSearchSentMediaRequest) (tg.MessagesMessagesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSearchSentMedia(ctx, request)
}

func (t *TelegramCore) MessagesSearchStickers(request *tg.MessagesSearchStickersRequest) (tg.MessagesFoundStickersClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSearchStickers(ctx, request)
}

func (t *TelegramCore) MessagesSendBotRequestedPeer(request *tg.MessagesSendBotRequestedPeerRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendBotRequestedPeer(ctx, request)
}

func (t *TelegramCore) MessagesSendEncrypted(request *tg.MessagesSendEncryptedRequest) (tg.MessagesSentEncryptedMessageClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendEncrypted(ctx, request)
}

func (t *TelegramCore) MessagesSendEncryptedFile(request *tg.MessagesSendEncryptedFileRequest) (tg.MessagesSentEncryptedMessageClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendEncryptedFile(ctx, request)
}

func (t *TelegramCore) MessagesSendEncryptedService(request *tg.MessagesSendEncryptedServiceRequest) (tg.MessagesSentEncryptedMessageClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendEncryptedService(ctx, request)
}

func (t *TelegramCore) MessagesSendPaidReaction(request *tg.MessagesSendPaidReactionRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendPaidReaction(ctx, request)
}

func (t *TelegramCore) MessagesSendQuickReplyMessages(request *tg.MessagesSendQuickReplyMessagesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendQuickReplyMessages(ctx, request)
}

func (t *TelegramCore) MessagesSendScreenshotNotification(request *tg.MessagesSendScreenshotNotificationRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendScreenshotNotification(ctx, request)
}

func (t *TelegramCore) MessagesSendWebViewData(request *tg.MessagesSendWebViewDataRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendWebViewData(ctx, request)
}

func (t *TelegramCore) MessagesSendWebViewResultMessage(request *tg.MessagesSendWebViewResultMessageRequest) (*tg.WebViewMessageSent, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSendWebViewResultMessage(ctx, request)
}

func (t *TelegramCore) MessagesSetBotCallbackAnswer(request *tg.MessagesSetBotCallbackAnswerRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetBotCallbackAnswer(ctx, request)
}

func (t *TelegramCore) MessagesSetBotPrecheckoutResults(request *tg.MessagesSetBotPrecheckoutResultsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetBotPrecheckoutResults(ctx, request)
}

func (t *TelegramCore) MessagesSetBotShippingResults(request *tg.MessagesSetBotShippingResultsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetBotShippingResults(ctx, request)
}

func (t *TelegramCore) MessagesSetDefaultHistoryTTL(period int) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetDefaultHistoryTTL(ctx, period)
}

func (t *TelegramCore) MessagesSetEncryptedTyping(request *tg.MessagesSetEncryptedTypingRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetEncryptedTyping(ctx, request)
}

func (t *TelegramCore) MessagesSetGameScore(request *tg.MessagesSetGameScoreRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSetGameScore(ctx, request)
}

func (t *TelegramCore) MessagesSetInlineBotResults(request *tg.MessagesSetInlineBotResultsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetInlineBotResults(ctx, request)
}

func (t *TelegramCore) MessagesSetInlineGameScore(request *tg.MessagesSetInlineGameScoreRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesSetInlineGameScore(ctx, request)
}

func (t *TelegramCore) MessagesStartHistoryImport(request *tg.MessagesStartHistoryImportRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesStartHistoryImport(ctx, request)
}

func (t *TelegramCore) MessagesSummarizeText(request *tg.MessagesSummarizeTextRequest) (*tg.TextWithEntities, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesSummarizeText(ctx, request)
}

func (t *TelegramCore) MessagesToggleBotInAttachMenu(request *tg.MessagesToggleBotInAttachMenuRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesToggleBotInAttachMenu(ctx, request)
}

func (t *TelegramCore) MarkAllStoriesRead() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	result, err := api.StoriesGetAllStories(ctx, &tg.StoriesGetAllStoriesRequest{})
	if err != nil {
		return err
	}
	allStories, ok := result.(*tg.StoriesAllStories)
	if !ok || len(allStories.PeerStories) == 0 {
		return nil
	}

	for _, u := range allStories.Users {
		if user, ok := u.(*tg.User); ok && user.AccessHash != 0 {
			t.cacheUserHash(user.ID, user.AccessHash)
		}
	}
	for _, c := range allStories.Chats {
		if ch, ok := c.(*tg.Channel); ok && ch.AccessHash != 0 {
			t.cacheChannelHash(ch.ID, ch.AccessHash)
		}
	}

	for _, ps := range allStories.PeerStories {
		maxStoryID := 0
		for _, s := range ps.Stories {
			if id := s.GetID(); id > maxStoryID {
				maxStoryID = id
			}
		}
		if maxStoryID == 0 {
			continue
		}
		maxRead, hasRead := ps.GetMaxReadID()
		if hasRead && maxRead >= maxStoryID {
			continue
		}
		inputPeer := t.peerToInputPeer(ps.Peer)
		api.StoriesReadStories(ctx, &tg.StoriesReadStoriesRequest{
			Peer:  inputPeer,
			MaxID: maxStoryID,
		})
	}
	return nil
}

func (t *TelegramCore) RemoveBotFromMenu(botID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.MessagesToggleBotInAttachMenu(ctx, &tg.MessagesToggleBotInAttachMenuRequest{
		Bot:     &tg.InputUser{UserID: botID, AccessHash: t.getCachedUserHash(botID)},
		Enabled: false,
	})
	return err
}

func (t *TelegramCore) MessagesToggleDialogFilterTags(enabled bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesToggleDialogFilterTags(ctx, enabled)
}

func (t *TelegramCore) MessagesTogglePaidReactionPrivacy(request *tg.MessagesTogglePaidReactionPrivacyRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesTogglePaidReactionPrivacy(ctx, request)
}

func (t *TelegramCore) MessagesTogglePeerTranslations(request *tg.MessagesTogglePeerTranslationsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesTogglePeerTranslations(ctx, request)
}

func (t *TelegramCore) MessagesToggleSavedDialogPin(request *tg.MessagesToggleSavedDialogPinRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesToggleSavedDialogPin(ctx, request)
}

func (t *TelegramCore) ToggleSavedDialogPin(peerID string, pinned bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(peerID)
	if err != nil {
		return err
	}
	inputPeer, _ := t.toInputPeer(peer)
	_, err = api.MessagesToggleSavedDialogPin(ctx, &tg.MessagesToggleSavedDialogPinRequest{
		Peer:   &tg.InputDialogPeer{Peer: inputPeer},
		Pinned: pinned,
	})
	return err
}

func (t *TelegramCore) DeleteSavedHistory(peerID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(peerID)
	if err != nil {
		return err
	}
	inputPeer, _ := t.toInputPeer(peer)
	_, err = api.MessagesDeleteSavedHistory(ctx, &tg.MessagesDeleteSavedHistoryRequest{
		Peer: inputPeer,
	})
	return err
}

func (t *TelegramCore) MessagesToggleStickerSets(request *tg.MessagesToggleStickerSetsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesToggleStickerSets(ctx, request)
}

func (t *TelegramCore) MessagesToggleSuggestedPostApproval(request *tg.MessagesToggleSuggestedPostApprovalRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesToggleSuggestedPostApproval(ctx, request)
}

func (t *TelegramCore) MessagesToggleTodoCompleted(request *tg.MessagesToggleTodoCompletedRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesToggleTodoCompleted(ctx, request)
}

func (t *TelegramCore) MessagesTranscribeAudio(request *tg.MessagesTranscribeAudioRequest) (*tg.MessagesTranscribedAudio, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesTranscribeAudio(ctx, request)
}

func (t *TelegramCore) TranscribeAudio(chatID, msgID string) (bool, int64, string, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return false, 0, "", err
	}
	defer unlock()

	mid, err := tgMsgID(msgID)
	if err != nil {
		return false, 0, "", err
	}

	res, err := t.api.MessagesTranscribeAudio(t.ctx, &tg.MessagesTranscribeAudioRequest{
		Peer:  inputPeer,
		MsgID: mid,
	})
	if err != nil {
		return false, 0, "", err
	}
	return res.Pending, res.TranscriptionID, res.Text, nil
}

func (t *TelegramCore) MessagesUninstallStickerSet(stickerset tg.InputStickerSetClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesUninstallStickerSet(ctx, stickerset)
}

func (t *TelegramCore) MessagesUpdateSavedReactionTag(request *tg.MessagesUpdateSavedReactionTagRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesUpdateSavedReactionTag(ctx, request)
}

func (t *TelegramCore) MessagesUploadEncryptedFile(request *tg.MessagesUploadEncryptedFileRequest) (tg.EncryptedFileClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesUploadEncryptedFile(ctx, request)
}

func (t *TelegramCore) MessagesUploadImportedMedia(request *tg.MessagesUploadImportedMediaRequest) (tg.MessageMediaClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesUploadImportedMedia(ctx, request)
}

func (t *TelegramCore) MessagesUploadMedia(request *tg.MessagesUploadMediaRequest) (tg.MessageMediaClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.MessagesUploadMedia(ctx, request)
}

func (t *TelegramCore) MessagesViewSponsoredMessage(randomid []byte) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.MessagesViewSponsoredMessage(ctx, randomid)
}

func (t *TelegramCore) PhoneCheckGroupCall(request *tg.PhoneCheckGroupCallRequest) ([]int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneCheckGroupCall(ctx, request)
}

func (t *TelegramCore) PhoneCreateConferenceCall(request *tg.PhoneCreateConferenceCallRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneCreateConferenceCall(ctx, request)
}

func (t *TelegramCore) CreateConferenceCall() (string, string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", "", err
	}
	var ridBuf [4]byte
	if _, err := rand.Read(ridBuf[:]); err != nil {
		return "", "", fmt.Errorf("rand: %w", err)
	}
	rid := int(binary.LittleEndian.Uint32(ridBuf[:]))
	req := &tg.PhoneCreateConferenceCallRequest{
		RandomID: rid,
	}
	updates, err := api.PhoneCreateConferenceCall(ctx, req)
	if err != nil {
		return "", "", err
	}
	upd, ok := updates.(*tg.Updates)
	if !ok {
		return "", "", fmt.Errorf("unexpected updates type: %T", updates)
	}
	for _, u := range upd.Updates {
		if gc, ok := u.(*tg.UpdateGroupCall); ok {
			if call, ok := gc.Call.(*tg.GroupCall); ok {
				t.peerMu.Lock()
				t.confCallHash[call.ID] = call.AccessHash
				t.peerMu.Unlock()
				callID := strconv.FormatInt(call.ID, 10)
				link, _ := call.GetInviteLink()
				return callID, link, nil
			}
		}
	}
	return "", "", fmt.Errorf("conference call created but no GroupCall found in updates")
}

type confInviteEntry struct {
	calling bool
	msgIDs  []int
}

func collectConfInviteMessageIDs(updates tg.UpdatesClass) []int {
	var list []tg.UpdateClass
	switch u := updates.(type) {
	case *tg.Updates:
		list = u.Updates
	case *tg.UpdatesCombined:
		list = u.Updates
	case *tg.UpdateShort:
		list = []tg.UpdateClass{u.Update}
	}
	var ids []int
	add := func(msg tg.MessageClass) {
		switch m := msg.(type) {
		case *tg.Message:
			if m.ID != 0 {
				ids = append(ids, m.ID)
			}
		case *tg.MessageService:
			if m.ID != 0 {
				ids = append(ids, m.ID)
			}
		}
	}
	for _, update := range list {
		switch upd := update.(type) {
		case *tg.UpdateNewMessage:
			add(upd.Message)
		case *tg.UpdateNewChannelMessage:
			add(upd.Message)
		case *tg.UpdateMessageID:
			if upd.ID != 0 {
				ids = append(ids, upd.ID)
			}
		}
	}
	return ids
}

func (t *TelegramCore) registerConfInvite(callID, userID int64, calling bool, msgIDs []int) {
	t.peerMu.Lock()
	defer t.peerMu.Unlock()
	m := t.confInvites[callID]
	if m == nil {
		m = make(map[int64]*confInviteEntry)
		t.confInvites[callID] = m
	}
	e := m[userID]
	if e == nil {
		e = &confInviteEntry{}
		m[userID] = e
	}
	e.calling = calling
	e.msgIDs = append(e.msgIDs, msgIDs...)
}

func (t *TelegramCore) takeConfInvite(callID, userID int64) (*confInviteEntry, bool) {
	t.peerMu.Lock()
	defer t.peerMu.Unlock()
	m := t.confInvites[callID]
	if m == nil {
		return nil, false
	}
	e, ok := m[userID]
	if !ok {
		return nil, false
	}
	delete(m, userID)
	if len(m) == 0 {
		delete(t.confInvites, callID)
	}
	return e, true
}

func (t *TelegramCore) mergeConfInvites(callID int64, participants []CallParticipant) []CallParticipant {
	t.peerMu.RLock()
	m := t.confInvites[callID]
	type inv struct {
		uid     int64
		calling bool
	}
	var list []inv
	for uid, e := range m {
		list = append(list, inv{uid, e.calling})
	}
	t.peerMu.RUnlock()
	if len(list) == 0 {
		return participants
	}
	joined := make(map[string]bool, len(participants))
	for _, p := range participants {
		joined[p.UserID] = true
	}
	for _, iv := range list {
		uidStr := strconv.FormatInt(iv.uid, 10)
		if joined[uidStr] {
			continue
		}
		state := "invited"
		if iv.calling {
			state = "calling"
		}
		participants = append(participants, CallParticipant{
			UserID:      uidStr,
			DisplayName: t.getCachedUserName(iv.uid),
			State:       state,
		})
	}
	return participants
}

func (t *TelegramCore) fireConfCallParticipants(callID int64) {
	t.mu.RLock()
	call := t.activeCalls[callID]
	t.mu.RUnlock()
	if call == nil {
		return
	}
	call.lastParticipantsMu.Lock()
	base := make([]CallParticipant, len(call.lastParticipants))
	copy(base, call.lastParticipants)
	call.lastParticipantsMu.Unlock()
	t.fireUpdate(Update{
		Type:     UpdateCallState,
		Platform: tgPlatform,
		Call: &CallSession{
			ID:           strconv.FormatInt(callID, 10),
			State:        call.state,
			IsGroup:      true,
			Participants: t.mergeConfInvites(callID, base),
		},
	})
}

func (t *TelegramCore) InviteToConferenceCall(callID string, userIDs, videoUserIDs []string) error {
	t.mu.RLock()
	authed := t.authed && t.api != nil
	t.mu.RUnlock()
	if !authed {
		return ErrAuth
	}
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID %q: %w", callID, err)
	}
	t.peerMu.RLock()
	hash, ok := t.confCallHash[cid]
	t.peerMu.RUnlock()
	if !ok {
		return fmt.Errorf("no access hash for conference call %s", callID)
	}

	withVideo := make(map[string]bool, len(videoUserIDs))
	for _, v := range videoUserIDs {
		withVideo[v] = true
	}

	var firstErr error
	invited := 0
	for _, uid := range userIDs {
		id, perr := strconv.ParseInt(uid, 10, 64)
		if perr != nil {
			continue
		}
		t.peerMu.RLock()
		uHash := t.userAccessHash[id]
		t.peerMu.RUnlock()
		updates, ierr := t.api.PhoneInviteConferenceCallParticipant(t.ctx, &tg.PhoneInviteConferenceCallParticipantRequest{
			Call:   &tg.InputGroupCall{ID: cid, AccessHash: hash},
			UserID: &tg.InputUser{UserID: id, AccessHash: uHash},
			Video:  withVideo[uid],
		})
		if ierr != nil {
			if firstErr == nil {
				firstErr = ierr
			}
			continue
		}
		t.registerConfInvite(cid, id, true, collectConfInviteMessageIDs(updates))
		invited++
	}
	if invited == 0 && firstErr != nil {
		return firstErr
	}
	t.fireConfCallParticipants(cid)
	return nil
}

func (t *TelegramCore) DeclineOutgoingConferenceInvite(callID, userID string, discard bool) error {
	t.mu.RLock()
	authed := t.authed && t.api != nil
	t.mu.RUnlock()
	if !authed {
		return ErrAuth
	}
	cid, err := strconv.ParseInt(callID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid call ID %q: %w", callID, err)
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid user ID %q: %w", userID, err)
	}

	entry, ok := t.takeConfInvite(cid, uid)
	var msgIDs []int
	if ok {
		msgIDs = entry.msgIDs
	}

	var firstErr error
	if discard {
		if len(msgIDs) > 0 {
			if _, derr := t.api.MessagesDeleteMessages(t.ctx, &tg.MessagesDeleteMessagesRequest{
				ID:     msgIDs,
				Revoke: true,
			}); derr != nil {
				firstErr = derr
			}
		}
	} else {
		for _, mid := range msgIDs {
			if _, derr := t.api.PhoneDeclineConferenceCallInvite(t.ctx, mid); derr != nil && firstErr == nil {
				firstErr = derr
			}
		}
		if ok {
			t.registerConfInvite(cid, uid, false, msgIDs)
		}
	}

	t.fireConfCallParticipants(cid)
	return firstErr
}

func (t *TelegramCore) PhoneCreateGroupCall(request *tg.PhoneCreateGroupCallRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneCreateGroupCall(ctx, request)
}

func (t *TelegramCore) PhoneDeclineConferenceCallInvite(msgid int) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneDeclineConferenceCallInvite(ctx, msgid)
}

func (t *TelegramCore) PhoneDeleteConferenceCallParticipants(request *tg.PhoneDeleteConferenceCallParticipantsRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneDeleteConferenceCallParticipants(ctx, request)
}

func (t *TelegramCore) PhoneDeleteGroupCallMessages(request *tg.PhoneDeleteGroupCallMessagesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneDeleteGroupCallMessages(ctx, request)
}

func (t *TelegramCore) PhoneDeleteGroupCallParticipantMessages(request *tg.PhoneDeleteGroupCallParticipantMessagesRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneDeleteGroupCallParticipantMessages(ctx, request)
}

func (t *TelegramCore) PhoneDiscardGroupCall(call tg.InputGroupCallClass) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneDiscardGroupCall(ctx, call)
}

func (t *TelegramCore) PhoneEditGroupCallParticipant(request *tg.PhoneEditGroupCallParticipantRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneEditGroupCallParticipant(ctx, request)
}

func (t *TelegramCore) PhoneEditGroupCallTitle(request *tg.PhoneEditGroupCallTitleRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneEditGroupCallTitle(ctx, request)
}

func (t *TelegramCore) PhoneExportGroupCallInvite(request *tg.PhoneExportGroupCallInviteRequest) (*tg.PhoneExportedGroupCallInvite, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneExportGroupCallInvite(ctx, request)
}

func (t *TelegramCore) PhoneGetGroupCall(request *tg.PhoneGetGroupCallRequest) (*tg.PhoneGroupCall, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupCall(ctx, request)
}

func (t *TelegramCore) PhoneGetGroupCallChainBlocks(request *tg.PhoneGetGroupCallChainBlocksRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupCallChainBlocks(ctx, request)
}

func (t *TelegramCore) PhoneGetGroupCallJoinAs(peer tg.InputPeerClass) (*tg.PhoneJoinAsPeers, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupCallJoinAs(ctx, peer)
}

func (t *TelegramCore) PhoneGetGroupCallStars(call tg.InputGroupCallClass) (*tg.PhoneGroupCallStars, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupCallStars(ctx, call)
}

func (t *TelegramCore) PhoneGetGroupCallStreamChannels(call tg.InputGroupCallClass) (*tg.PhoneGroupCallStreamChannels, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupCallStreamChannels(ctx, call)
}

func (t *TelegramCore) PhoneGetGroupCallStreamRtmpURL(request *tg.PhoneGetGroupCallStreamRtmpURLRequest) (*tg.PhoneGroupCallStreamRtmpURL, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupCallStreamRtmpURL(ctx, request)
}

func (t *TelegramCore) PhoneGetGroupParticipants(request *tg.PhoneGetGroupParticipantsRequest) (*tg.PhoneGroupParticipants, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneGetGroupParticipants(ctx, request)
}

func (t *TelegramCore) PhoneInviteConferenceCallParticipant(request *tg.PhoneInviteConferenceCallParticipantRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneInviteConferenceCallParticipant(ctx, request)
}

func (t *TelegramCore) PhoneInviteToGroupCall(request *tg.PhoneInviteToGroupCallRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneInviteToGroupCall(ctx, request)
}

func (t *TelegramCore) PhoneJoinGroupCall(request *tg.PhoneJoinGroupCallRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneJoinGroupCall(ctx, request)
}

func (t *TelegramCore) PhoneJoinGroupCallPresentation(request *tg.PhoneJoinGroupCallPresentationRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneJoinGroupCallPresentation(ctx, request)
}

func (t *TelegramCore) PhoneLeaveGroupCall(request *tg.PhoneLeaveGroupCallRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneLeaveGroupCall(ctx, request)
}

func (t *TelegramCore) PhoneLeaveGroupCallPresentation(call tg.InputGroupCallClass) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneLeaveGroupCallPresentation(ctx, call)
}

func (t *TelegramCore) PhoneReceivedCall(peer tg.InputPhoneCall) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.PhoneReceivedCall(ctx, peer)
}

func (t *TelegramCore) PhoneSaveCallDebug(request *tg.PhoneSaveCallDebugRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.PhoneSaveCallDebug(ctx, request)
}

func (t *TelegramCore) PhoneSaveCallLog(request *tg.PhoneSaveCallLogRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.PhoneSaveCallLog(ctx, request)
}

func (t *TelegramCore) PhoneSaveDefaultGroupCallJoinAs(request *tg.PhoneSaveDefaultGroupCallJoinAsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.PhoneSaveDefaultGroupCallJoinAs(ctx, request)
}

func (t *TelegramCore) PhoneSaveDefaultSendAs(request *tg.PhoneSaveDefaultSendAsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.PhoneSaveDefaultSendAs(ctx, request)
}

func (t *TelegramCore) PhoneSendConferenceCallBroadcast(request *tg.PhoneSendConferenceCallBroadcastRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneSendConferenceCallBroadcast(ctx, request)
}

func (t *TelegramCore) PhoneSendGroupCallEncryptedMessage(request *tg.PhoneSendGroupCallEncryptedMessageRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.PhoneSendGroupCallEncryptedMessage(ctx, request)
}

func (t *TelegramCore) PhoneSendGroupCallMessage(request *tg.PhoneSendGroupCallMessageRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneSendGroupCallMessage(ctx, request)
}

func (t *TelegramCore) PhoneSetCallRating(request *tg.PhoneSetCallRatingRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneSetCallRating(ctx, request)
}

func (t *TelegramCore) PhoneStartScheduledGroupCall(call tg.InputGroupCallClass) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneStartScheduledGroupCall(ctx, call)
}

func (t *TelegramCore) PhoneToggleGroupCallRecord(request *tg.PhoneToggleGroupCallRecordRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneToggleGroupCallRecord(ctx, request)
}

func (t *TelegramCore) PhoneToggleGroupCallSettings(request *tg.PhoneToggleGroupCallSettingsRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneToggleGroupCallSettings(ctx, request)
}

func (t *TelegramCore) PhoneToggleGroupCallStartSubscription(request *tg.PhoneToggleGroupCallStartSubscriptionRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhoneToggleGroupCallStartSubscription(ctx, request)
}

func (t *TelegramCore) PhotosUpdateProfilePhoto(request *tg.PhotosUpdateProfilePhotoRequest) (*tg.PhotosPhoto, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhotosUpdateProfilePhoto(ctx, request)
}

func (t *TelegramCore) PhotosUploadContactProfilePhoto(request *tg.PhotosUploadContactProfilePhotoRequest) (*tg.PhotosPhoto, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.PhotosUploadContactProfilePhoto(ctx, request)
}

func (t *TelegramCore) StatsGetMessagePublicForwards(request *tg.StatsGetMessagePublicForwardsRequest) (*tg.StatsPublicForwards, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StatsGetMessagePublicForwards(ctx, request)
}

func (t *TelegramCore) StatsGetMessageStats(request *tg.StatsGetMessageStatsRequest) (*tg.StatsMessageStats, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StatsGetMessageStats(ctx, request)
}

func (t *TelegramCore) GetMessageStatsJSON(chatID string, msgID int) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	inputCh := &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}
	result, err := api.StatsGetMessageStats(ctx, &tg.StatsGetMessageStatsRequest{
		Channel: inputCh,
		MsgID:   msgID,
	})
	if err != nil {
		return nil, err
	}
	charts := []map[string]interface{}{}
	if c := statsGraphToMap("Interactions", result.ViewsGraph, "DoubleLinear"); c != nil {
		charts = append(charts, c)
	}
	if c := statsGraphToMap("Reactions By Emotion", result.ReactionsByEmotionGraph, "Bar"); c != nil {
		charts = append(charts, c)
	}
	out := map[string]interface{}{"charts": charts}

	fwds, ferr := api.StatsGetMessagePublicForwards(ctx, &tg.StatsGetMessagePublicForwardsRequest{
		Channel: inputCh,
		MsgID:   msgID,
		Limit:   100,
	})
	if ferr == nil && fwds != nil {
		out["public_forwards_count"] = fwds.Count
		chatMap := map[int64]tg.ChatClass{}
		for _, c := range fwds.Chats {
			switch v := c.(type) {
			case *tg.Chat:
				chatMap[v.ID] = v
			case *tg.Channel:
				chatMap[v.ID] = v
			}
		}
		userMap := map[int64]tg.UserClass{}
		for _, u := range fwds.Users {
			if usr, ok := u.(*tg.User); ok {
				userMap[usr.ID] = usr
			}
		}
		var forwards []map[string]interface{}
		for _, f := range fwds.Forwards {
			switch pf := f.(type) {
			case *tg.PublicForwardMessage:
				msg, ok := pf.Message.(*tg.Message)
				if !ok {
					continue
				}
				row := map[string]interface{}{"type": "message"}
				var peerID int64
				switch p := msg.PeerID.(type) {
				case *tg.PeerChannel:
					peerID = p.ChannelID
				case *tg.PeerChat:
					peerID = p.ChatID
				case *tg.PeerUser:
					peerID = p.UserID
				}
				if ch, ok := chatMap[peerID]; ok {
					switch v := ch.(type) {
					case *tg.Channel:
						row["name"] = v.Title
						row["peer_id"] = fmt.Sprintf("channel_%d", v.ID)
						if pc, ok := v.GetParticipantsCount(); ok {
							row["members"] = pc
						}
						row["is_megagroup"] = v.Megagroup
					case *tg.Chat:
						row["name"] = v.Title
						row["peer_id"] = fmt.Sprintf("chat_%d", v.ID)
						row["members"] = v.ParticipantsCount
						row["is_megagroup"] = true
					}
				} else if u, ok := userMap[peerID]; ok {
					if usr, ok := u.(*tg.User); ok {
						name := usr.FirstName
						if usr.LastName != "" {
							name += " " + usr.LastName
						}
						row["name"] = name
						row["peer_id"] = fmt.Sprintf("user_%d", usr.ID)
					}
				}
				row["msg_id"] = msg.ID
				row["views"] = msg.Views
				row["date"] = msg.Date
				forwards = append(forwards, row)
			case *tg.PublicForwardStory:
				row := map[string]interface{}{"type": "story"}
				switch p := pf.Peer.(type) {
				case *tg.PeerChannel:
					if ch, ok := chatMap[p.ChannelID]; ok {
						if v, ok := ch.(*tg.Channel); ok {
							row["name"] = v.Title
							row["peer_id"] = fmt.Sprintf("channel_%d", v.ID)
						}
					}
				}
				forwards = append(forwards, row)
			}
		}
		out["public_forwards"] = forwards
		if fwds.NextOffset != "" {
			out["next_offset"] = fwds.NextOffset
		}
	}

	if msgs, mErr := api.ChannelsGetMessages(ctx, &tg.ChannelsGetMessagesRequest{
		Channel: inputCh,
		ID:      []tg.InputMessageClass{&tg.InputMessageID{ID: msgID}},
	}); mErr == nil {
		var list []tg.MessageClass
		switch m := msgs.(type) {
		case *tg.MessagesChannelMessages:
			list = m.Messages
		case *tg.MessagesMessages:
			list = m.Messages
		}
		for _, mc := range list {
			msg, ok := mc.(*tg.Message)
			if !ok || msg.ID != msgID {
				continue
			}
			if v, ok := msg.GetViews(); ok {
				out["views"] = v
			}
			if f, ok := msg.GetForwards(); ok {
				out["forwards"] = f
			}
			if r, ok := msg.GetReactions(); ok {
				total := 0
				for _, rc := range r.Results {
					total += rc.Count
				}
				out["reactions"] = total
			}
			break
		}
	}

	return out, nil
}

func (t *TelegramCore) GetMessagePublicForwardsJSON(chatID string, msgID int, offset string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("not a channel")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	inputCh := &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash}
	fwds, err := api.StatsGetMessagePublicForwards(ctx, &tg.StatsGetMessagePublicForwardsRequest{
		Channel: inputCh,
		MsgID:   msgID,
		Offset:  offset,
		Limit:   100,
	})
	if err != nil {
		return nil, err
	}
	out := map[string]interface{}{}
	chatMap := map[int64]tg.ChatClass{}
	for _, c := range fwds.Chats {
		switch v := c.(type) {
		case *tg.Chat:
			chatMap[v.ID] = v
		case *tg.Channel:
			chatMap[v.ID] = v
		}
	}
	var forwards []map[string]interface{}
	for _, f := range fwds.Forwards {
		switch pf := f.(type) {
		case *tg.PublicForwardMessage:
			msg, ok := pf.Message.(*tg.Message)
			if !ok {
				continue
			}
			row := map[string]interface{}{"type": "message"}
			var peerID int64
			switch p := msg.PeerID.(type) {
			case *tg.PeerChannel:
				peerID = p.ChannelID
			case *tg.PeerChat:
				peerID = p.ChatID
			case *tg.PeerUser:
				peerID = p.UserID
			}
			if ch, ok := chatMap[peerID]; ok {
				switch v := ch.(type) {
				case *tg.Channel:
					row["name"] = v.Title
					row["peer_id"] = fmt.Sprintf("channel_%d", v.ID)
					if pc, ok := v.GetParticipantsCount(); ok {
						row["members"] = pc
					}
					row["is_megagroup"] = v.Megagroup
				case *tg.Chat:
					row["name"] = v.Title
					row["peer_id"] = fmt.Sprintf("chat_%d", v.ID)
					row["members"] = v.ParticipantsCount
					row["is_megagroup"] = true
				}
			}
			row["msg_id"] = msg.ID
			row["views"] = msg.Views
			row["date"] = msg.Date
			forwards = append(forwards, row)
		case *tg.PublicForwardStory:
			row := map[string]interface{}{"type": "story"}
			switch p := pf.Peer.(type) {
			case *tg.PeerChannel:
				if ch, ok := chatMap[p.ChannelID]; ok {
					if v, ok := ch.(*tg.Channel); ok {
						row["name"] = v.Title
						row["peer_id"] = fmt.Sprintf("channel_%d", v.ID)
					}
				}
			}
			forwards = append(forwards, row)
		}
	}
	out["forwards"] = forwards
	if fwds.NextOffset != "" {
		out["next_offset"] = fwds.NextOffset
	}
	return out, nil
}

func (t *TelegramCore) StatsGetStoryPublicForwards(request *tg.StatsGetStoryPublicForwardsRequest) (*tg.StatsPublicForwards, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StatsGetStoryPublicForwards(ctx, request)
}

func (t *TelegramCore) StatsGetStoryStats(request *tg.StatsGetStoryStatsRequest) (*tg.StatsStoryStats, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StatsGetStoryStats(ctx, request)
}

func (t *TelegramCore) StatsLoadAsyncGraph(request *tg.StatsLoadAsyncGraphRequest) (tg.StatsGraphClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StatsLoadAsyncGraph(ctx, request)
}

func (t *TelegramCore) LoadStatsGraph(token string, x int64) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	req := &tg.StatsLoadAsyncGraphRequest{Token: token}
	if x != 0 {
		req.SetX(x)
	}
	result, err := api.StatsLoadAsyncGraph(ctx, req)
	if err != nil {
		return nil, err
	}
	m := statsGraphToMap("", result, "")
	if m == nil {
		return nil, fmt.Errorf("graph returned empty or error")
	}
	return m, nil
}

func (t *TelegramCore) StickersAddStickerToSet(request *tg.StickersAddStickerToSetRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersAddStickerToSet(ctx, request)
}

func (t *TelegramCore) StickersChangeSticker(request *tg.StickersChangeStickerRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersChangeSticker(ctx, request)
}

func (t *TelegramCore) StickersChangeStickerPosition(request *tg.StickersChangeStickerPositionRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersChangeStickerPosition(ctx, request)
}

func (t *TelegramCore) StickersCheckShortName(shortname string) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StickersCheckShortName(ctx, shortname)
}

func (t *TelegramCore) StickersCreateStickerSet(request *tg.StickersCreateStickerSetRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersCreateStickerSet(ctx, request)
}

func (t *TelegramCore) StickersDeleteStickerSet(stickerset tg.InputStickerSetClass) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StickersDeleteStickerSet(ctx, stickerset)
}

func (t *TelegramCore) StickersRemoveStickerFromSet(sticker tg.InputDocumentClass) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersRemoveStickerFromSet(ctx, sticker)
}

func (t *TelegramCore) StickersRenameStickerSet(request *tg.StickersRenameStickerSetRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersRenameStickerSet(ctx, request)
}

func (t *TelegramCore) StickersReplaceSticker(request *tg.StickersReplaceStickerRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersReplaceSticker(ctx, request)
}

func (t *TelegramCore) StickersSetStickerSetThumb(request *tg.StickersSetStickerSetThumbRequest) (tg.MessagesStickerSetClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersSetStickerSetThumb(ctx, request)
}

func (t *TelegramCore) StickersSuggestShortName(title string) (*tg.StickersSuggestedShortName, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StickersSuggestShortName(ctx, title)
}

func (t *TelegramCore) StoriesActivateStealthMode(request *tg.StoriesActivateStealthModeRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesActivateStealthMode(ctx, request)
}

func (t *TelegramCore) ActivateStealthMode() error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.StoriesActivateStealthMode(ctx, &tg.StoriesActivateStealthModeRequest{
		Past:   true,
		Future: true,
	})
	return err
}

func (t *TelegramCore) StoriesCanSendStory(peer tg.InputPeerClass) (*tg.StoriesCanSendStoryCount, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesCanSendStory(ctx, peer)
}

func (t *TelegramCore) StoriesCreateAlbum(request *tg.StoriesCreateAlbumRequest) (*tg.StoryAlbum, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesCreateAlbum(ctx, request)
}

func (t *TelegramCore) StoriesDeleteAlbum(request *tg.StoriesDeleteAlbumRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StoriesDeleteAlbum(ctx, request)
}

func (t *TelegramCore) StoriesEditStory(request *tg.StoriesEditStoryRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesEditStory(ctx, request)
}

func (t *TelegramCore) StoriesExportStoryLink(request *tg.StoriesExportStoryLinkRequest) (*tg.ExportedStoryLink, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesExportStoryLink(ctx, request)
}

func (t *TelegramCore) StoriesGetAlbums(request *tg.StoriesGetAlbumsRequest) (tg.StoriesAlbumsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetAlbums(ctx, request)
}

func (t *TelegramCore) StoriesGetAlbumStories(request *tg.StoriesGetAlbumStoriesRequest) (*tg.StoriesStories, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetAlbumStories(ctx, request)
}

func (t *TelegramCore) StoriesGetAllReadPeerStories() (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetAllReadPeerStories(ctx)
}

func (t *TelegramCore) StoriesGetChatsToSend() (tg.MessagesChatsClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetChatsToSend(ctx)
}

func (t *TelegramCore) StoriesGetPeerMaxIDs(id []tg.InputPeerClass) ([]tg.RecentStory, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetPeerMaxIDs(ctx, id)
}

func (t *TelegramCore) StoriesGetStoriesArchive(request *tg.StoriesGetStoriesArchiveRequest) (*tg.StoriesStories, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetStoriesArchive(ctx, request)
}

func (t *TelegramCore) StoriesGetStoriesByID(request *tg.StoriesGetStoriesByIDRequest) (*tg.StoriesStories, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetStoriesByID(ctx, request)
}

func (t *TelegramCore) StoriesGetStoryReactionsList(request *tg.StoriesGetStoryReactionsListRequest) (*tg.StoriesStoryReactionsList, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetStoryReactionsList(ctx, request)
}

func (t *TelegramCore) StoriesGetStoryViewsList(request *tg.StoriesGetStoryViewsListRequest) (*tg.StoriesStoryViewsList, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesGetStoryViewsList(ctx, request)
}

func (t *TelegramCore) StoriesIncrementStoryViews(request *tg.StoriesIncrementStoryViewsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StoriesIncrementStoryViews(ctx, request)
}

func (t *TelegramCore) StoriesReadStories(request *tg.StoriesReadStoriesRequest) ([]int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesReadStories(ctx, request)
}

func (t *TelegramCore) StoriesReorderAlbums(request *tg.StoriesReorderAlbumsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StoriesReorderAlbums(ctx, request)
}

func (t *TelegramCore) StoriesReport(request *tg.StoriesReportRequest) (tg.ReportResultClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesReport(ctx, request)
}

func (t *TelegramCore) StoriesSearchPosts(request *tg.StoriesSearchPostsRequest) (*tg.StoriesFoundStories, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesSearchPosts(ctx, request)
}

func (t *TelegramCore) StoriesStartLive(request *tg.StoriesStartLiveRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesStartLive(ctx, request)
}

func (t *TelegramCore) StoriesToggleAllStoriesHidden(hidden bool) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StoriesToggleAllStoriesHidden(ctx, hidden)
}

func (t *TelegramCore) StoriesTogglePeerStoriesHidden(request *tg.StoriesTogglePeerStoriesHiddenRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StoriesTogglePeerStoriesHidden(ctx, request)
}

func (t *TelegramCore) StoriesTogglePinned(request *tg.StoriesTogglePinnedRequest) ([]int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesTogglePinned(ctx, request)
}

func (t *TelegramCore) StoriesTogglePinnedToTop(request *tg.StoriesTogglePinnedToTopRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.StoriesTogglePinnedToTop(ctx, request)
}

func (t *TelegramCore) StoriesUpdateAlbum(request *tg.StoriesUpdateAlbumRequest) (*tg.StoryAlbum, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.StoriesUpdateAlbum(ctx, request)
}

func (t *TelegramCore) UploadGetCDNFile(request *tg.UploadGetCDNFileRequest) (tg.UploadCDNFileClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UploadGetCDNFile(ctx, request)
}

func (t *TelegramCore) UploadGetCDNFileHashes(request *tg.UploadGetCDNFileHashesRequest) ([]tg.FileHash, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UploadGetCDNFileHashes(ctx, request)
}

func (t *TelegramCore) UploadGetFile(request *tg.UploadGetFileRequest) (tg.UploadFileClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UploadGetFile(ctx, request)
}

func (t *TelegramCore) UploadGetFileHashes(request *tg.UploadGetFileHashesRequest) ([]tg.FileHash, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UploadGetFileHashes(ctx, request)
}

func (t *TelegramCore) UploadGetWebFile(request *tg.UploadGetWebFileRequest) (*tg.UploadWebFile, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UploadGetWebFile(ctx, request)
}

func (t *TelegramCore) UploadReuploadCDNFile(request *tg.UploadReuploadCDNFileRequest) ([]tg.FileHash, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UploadReuploadCDNFile(ctx, request)
}

func (t *TelegramCore) UploadSaveBigFilePart(request *tg.UploadSaveBigFilePartRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.UploadSaveBigFilePart(ctx, request)
}

func (t *TelegramCore) UploadSaveFilePart(request *tg.UploadSaveFilePartRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.UploadSaveFilePart(ctx, request)
}

func (t *TelegramCore) UsersGetRequirementsToContact(id []tg.InputUserClass) ([]tg.RequirementToContactClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UsersGetRequirementsToContact(ctx, id)
}

func (t *TelegramCore) UsersGetSavedMusic(request *tg.UsersGetSavedMusicRequest) (tg.UsersSavedMusicClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UsersGetSavedMusic(ctx, request)
}

func (t *TelegramCore) UsersGetSavedMusicByID(request *tg.UsersGetSavedMusicByIDRequest) (tg.UsersSavedMusicClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UsersGetSavedMusicByID(ctx, request)
}

func (t *TelegramCore) UsersSetSecureValueErrors(request *tg.UsersSetSecureValueErrorsRequest) (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	return api.UsersSetSecureValueErrors(ctx, request)
}

func (t *TelegramCore) UsersSuggestBirthday(request *tg.UsersSuggestBirthdayRequest) (tg.UpdatesClass, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	return api.UsersSuggestBirthday(ctx, request)
}

func (t *TelegramCore) SuggestBirthday(userID string, day, month, year int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := strconv.ParseInt(userID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid user ID: %w", err)
	}
	inputUser := &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)}
	bday := tg.Birthday{Day: day, Month: month}
	if year > 0 {
		bday.SetYear(year)
	}
	_, err = api.UsersSuggestBirthday(ctx, &tg.UsersSuggestBirthdayRequest{
		ID:       inputUser,
		Birthday: bday,
	})
	return err
}

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

func (t *TelegramCore) TestSetSignalingInInterceptor(callID int64, handler func([]byte)) {
	t.rawSigInterceptorsMu.Lock()
	defer t.rawSigInterceptorsMu.Unlock()
	if handler == nil {
		delete(t.rawSigInInterceptors, callID)
	} else {
		t.rawSigInInterceptors[callID] = handler
	}
}

func (t *TelegramCore) TestSetSignalingOutInterceptor(callID int64, handler func([]byte)) {
	t.rawSigInterceptorsMu.Lock()
	defer t.rawSigInterceptorsMu.Unlock()
	if handler == nil {
		delete(t.rawSigOutInterceptors, callID)
	} else {
		t.rawSigOutInterceptors[callID] = handler
	}
}

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

	_, err = t.AcceptCall(callIDStr)
	if err != nil {
		return err
	}

	select {
	case <-call.dhDone:
		return nil
	case <-time.After(20 * time.Second):
		return fmt.Errorf("DH exchange timed out")
	}
}

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

	select {
	case <-call.dhDone:
		return cs, nil
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("DH exchange timed out — callee may not have answered")
	}
}

func (t *TelegramCore) TestHandleSignalingData(callID int64, data []byte) {
	t.handleSignalingData(callID, data)
}

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

func (t *TelegramCore) TestGetGroupCallAccessHash(gcID int64) int64 {
	t.mu.RLock()
	defer t.mu.RUnlock()
	call := t.activeCalls[gcID]
	if call == nil {
		return 0
	}
	return call.accessHash
}

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

func (t *TelegramCore) GetChatInfo(chatID string) (*Dialog, error) {
	d, err := t.GetFullChannel(chatID)
	if err == nil {
		return d, nil
	}
	return t.GetFullChat(chatID)
}

func (t *TelegramCore) EditChatTitle(chatID string, title string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = api.ChannelsEditTitle(ctx, &tg.ChannelsEditTitleRequest{
			Channel: &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash}, Title: title,
		})
		return err
	case *tg.PeerChat:
		_, err = api.MessagesEditChatTitle(ctx, &tg.MessagesEditChatTitleRequest{
			ChatID: p.ChatID, Title: title,
		})
		return err
	}
	return fmt.Errorf("telegram: cannot edit title for this chat type: %w", ErrNotSupported)
}

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

func (t *TelegramCore) LeaveChat(chatID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	switch p := peer.(type) {
	case *tg.PeerChannel:
		hash, _ := t.resolveChannelAccessHash(p.ChannelID)
		_, err = api.ChannelsLeaveChannel(ctx, &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash})
		return err
	case *tg.PeerChat:
		me, _ := api.UsersGetUsers(ctx, []tg.InputUserClass{&tg.InputUserSelf{}})
		if len(me) > 0 {
			if u, ok := me[0].(*tg.User); ok {
				_, err = api.MessagesDeleteChatUser(ctx, &tg.MessagesDeleteChatUserRequest{
					ChatID: p.ChatID, UserID: &tg.InputUser{UserID: u.ID},
				})
				return err
			}
		}
		return fmt.Errorf("could not determine self user")
	}
	return fmt.Errorf("telegram: cannot leave this chat type: %w", ErrNotSupported)
}

func (t *TelegramCore) GetInviteLink(chatID string) (string, error) {
	return t.ExportChatInvite(chatID)
}

func inviteLinkFromExported(inv *tg.ChatInviteExported) map[string]interface{} {
	m := map[string]interface{}{
		"link":          inv.Link,
		"label":         inv.Title,
		"admin_id":      strconv.FormatInt(inv.AdminID, 10),
		"date":          inv.Date,
		"start_date":    inv.StartDate,
		"expire_date":   inv.ExpireDate,
		"usage_limit":   inv.UsageLimit,
		"usage":         inv.Usage,
		"requested":     inv.Requested,
		"permanent":     inv.Permanent,
		"revoked":       inv.Revoked,
		"need_approval": inv.RequestNeeded,
	}
	if sp, ok := inv.GetSubscriptionPricing(); ok {
		m["subscription_credits"] = sp.Amount
	}
	return m
}

func (t *TelegramCore) GetExportedChatInvites(chatID string, revoked bool, adminID string, offsetDate int, offsetLink string) ([]map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	var adminUser tg.InputUserClass
	if adminID != "" {
		uid, _ := strconv.ParseInt(adminID, 10, 64)
		adminUser = &tg.InputUser{UserID: uid, AccessHash: t.getCachedUserHash(uid)}
	} else {
		adminUser = &tg.InputUserSelf{}
	}
	req := &tg.MessagesGetExportedChatInvitesRequest{
		Peer:    inputPeer,
		AdminID: adminUser,
		Revoked: revoked,
		Limit:   100,
	}
	if offsetDate > 0 {
		req.SetOffsetDate(offsetDate)
	}
	if offsetLink != "" {
		req.SetOffsetLink(offsetLink)
	}
	result, err := t.api.MessagesGetExportedChatInvites(t.ctx, req)
	if err != nil {
		return nil, err
	}
	botByID := map[int64]bool{}
	for _, u := range result.Users {
		if uu, ok := u.(*tg.User); ok {
			botByID[uu.ID] = uu.Bot
		}
	}
	var links []map[string]interface{}
	for _, inv := range result.Invites {
		if exported, ok := inv.(*tg.ChatInviteExported); ok {
			m := inviteLinkFromExported(exported)
			m["admin_is_bot"] = botByID[exported.AdminID]
			links = append(links, m)
		}
	}
	return links, nil
}

func (t *TelegramCore) CreateChatInviteLink(chatID, label string, expireDate, usageLimit int, requestApproval bool) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	req := &tg.MessagesExportChatInviteRequest{
		Peer:          inputPeer,
		RequestNeeded: requestApproval,
	}
	if label != "" {
		req.SetTitle(label)
	}
	if expireDate > 0 {
		req.SetExpireDate(expireDate)
	}
	if usageLimit > 0 && !requestApproval {
		req.SetUsageLimit(usageLimit)
	}
	result, err := t.api.MessagesExportChatInvite(t.ctx, req)
	if err != nil {
		return nil, err
	}
	if inv, ok := result.(*tg.ChatInviteExported); ok {
		return inviteLinkFromExported(inv), nil
	}
	return nil, fmt.Errorf("unexpected response type")
}

func (t *TelegramCore) CreateChatInviteLinkWithSubscription(chatID, label string, expireDate, usageLimit int, requestApproval bool, subscriptionCredits int) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	req := &tg.MessagesExportChatInviteRequest{
		Peer:          inputPeer,
		RequestNeeded: requestApproval,
	}
	if label != "" {
		req.SetTitle(label)
	}
	if expireDate > 0 {
		req.SetExpireDate(expireDate)
	}
	if usageLimit > 0 && !requestApproval {
		req.SetUsageLimit(usageLimit)
	}
	if subscriptionCredits > 0 {
		req.SetSubscriptionPricing(tg.StarsSubscriptionPricing{
			Period: 30 * 24 * 60 * 60,
			Amount: int64(subscriptionCredits),
		})
	}
	result, err := t.api.MessagesExportChatInvite(t.ctx, req)
	if err != nil {
		return nil, err
	}
	if inv, ok := result.(*tg.ChatInviteExported); ok {
		return inviteLinkFromExported(inv), nil
	}
	return nil, fmt.Errorf("unexpected response type")
}

func (t *TelegramCore) EditChatInviteLink(chatID, link, label string, expireDate, usageLimit int, requestApproval bool) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	req := &tg.MessagesEditExportedChatInviteRequest{
		Peer:          inputPeer,
		Link:          link,
		RequestNeeded: requestApproval,
	}
	req.SetTitle(label)
	req.SetExpireDate(expireDate)
	if !requestApproval {
		req.SetUsageLimit(usageLimit)
	}
	result, err := t.api.MessagesEditExportedChatInvite(t.ctx, req)
	if err != nil {
		return nil, err
	}
	if inv, ok := result.GetInvite().(*tg.ChatInviteExported); ok {
		return inviteLinkFromExported(inv), nil
	}
	return nil, fmt.Errorf("unexpected response type")
}

func (t *TelegramCore) EditChatInviteLinkWithSubscription(chatID, link, label string, expireDate, usageLimit int, requestApproval bool, subscriptionCredits int) (map[string]interface{}, error) {
	return t.EditChatInviteLink(chatID, link, label, expireDate, usageLimit, requestApproval)
}

func (t *TelegramCore) RevokeChatInviteLink(chatID, link string) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	result, err := t.api.MessagesEditExportedChatInvite(t.ctx, &tg.MessagesEditExportedChatInviteRequest{
		Peer: inputPeer, Link: link, Revoked: true,
	})
	if err != nil {
		return nil, err
	}
	if inv, ok := result.GetInvite().(*tg.ChatInviteExported); ok {
		return inviteLinkFromExported(inv), nil
	}
	return nil, fmt.Errorf("unexpected response type")
}

func (t *TelegramCore) DeleteRevokedChatInviteLink(chatID, link string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesDeleteExportedChatInvite(t.ctx, &tg.MessagesDeleteExportedChatInviteRequest{
		Peer: inputPeer, Link: link,
	})
	return err
}

func (t *TelegramCore) DeleteAllRevokedChatInvites(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	_, err = t.api.MessagesDeleteRevokedExportedChatInvites(t.ctx, &tg.MessagesDeleteRevokedExportedChatInvitesRequest{
		Peer:    inputPeer,
		AdminID: &tg.InputUserSelf{},
	})
	return err
}

func (t *TelegramCore) GetAdminsWithInvites(chatID string) ([]map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	result, err := t.api.MessagesGetAdminsWithInvites(t.ctx, inputPeer)
	if err != nil {
		return nil, err
	}
	var admins []map[string]interface{}
	for _, a := range result.Admins {
		name := ""
		for _, u := range result.Users {
			if user, ok := u.(*tg.User); ok && user.ID == a.AdminID {
				name = user.FirstName
				if user.LastName != "" {
					name += " " + user.LastName
				}
				break
			}
		}
		admins = append(admins, map[string]interface{}{
			"admin_id":              strconv.FormatInt(a.AdminID, 10),
			"admin_name":            name,
			"invites_count":         a.InvitesCount,
			"revoked_invites_count": a.RevokedInvitesCount,
		})
	}
	return admins, nil
}

func (t *TelegramCore) AddMembers(chatID string, userIDs []string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
			if err != nil {
				return err
			}
			uhash := t.getCachedUserHash(id)
			users = append(users, &tg.InputUser{UserID: id, AccessHash: uhash})
		}
		_, err = api.ChannelsInviteToChannel(ctx, &tg.ChannelsInviteToChannelRequest{
			Channel: &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash}, Users: users,
		})
		return err
	case *tg.PeerChat:
		for _, uid := range userIDs {
			id, err := tgUserID(uid)
			if err != nil {
				return err
			}
			uhash := t.getCachedUserHash(id)
			_, err = api.MessagesAddChatUser(ctx, &tg.MessagesAddChatUserRequest{
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

func (t *TelegramCore) RemoveMember(chatID string, userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
		_, err = api.ChannelsEditBanned(ctx, &tg.ChannelsEditBannedRequest{
			Channel:      &tg.InputChannel{ChannelID: p.ChannelID, AccessHash: hash},
			Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
			BannedRights: tg.ChatBannedRights{ViewMessages: true, UntilDate: 0},
		})
		return err
	case *tg.PeerChat:
		_, err = api.MessagesDeleteChatUser(ctx, &tg.MessagesDeleteChatUserRequest{
			ChatID: p.ChatID, UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
		})
		return err
	}
	return fmt.Errorf("telegram: cannot remove member from this chat type: %w", ErrNotSupported)
}

func (t *TelegramCore) BanMember(chatID string, userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.ChannelsEditBanned(ctx, &tg.ChannelsEditBannedRequest{
		Channel:      &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		BannedRights: tg.ChatBannedRights{ViewMessages: true, UntilDate: 0},
	})
	return err
}

func (t *TelegramCore) BanMemberUntil(chatID, userID string, untilDate int) error {
	return t.RestrictUser(chatID, userID, tg.ChatBannedRights{
		ViewMessages: true,
		UntilDate:    untilDate,
	})
}

func (t *TelegramCore) DeleteParticipantHistory(chatID string, userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("telegram: delete participant history only works on channels/supergroups: %w", ErrNotSupported)
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.ChannelsDeleteParticipantHistory(ctx, &tg.ChannelsDeleteParticipantHistoryRequest{
		Channel:     &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
	})
	return err
}

func (t *TelegramCore) ReportChannelSpam(chatID string, userID string, msgIDs []int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return fmt.Errorf("telegram: report channel spam only works on channels/supergroups: %w", ErrNotSupported)
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.ChannelsReportSpam(ctx, &tg.ChannelsReportSpamRequest{
		Channel:     &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant: &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		ID:          msgIDs,
	})
	return err
}

func (t *TelegramCore) UnbanMember(chatID string, userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
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
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.ChannelsEditBanned(ctx, &tg.ChannelsEditBannedRequest{
		Channel:      &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
		Participant:  &tg.InputPeerUser{UserID: uid, AccessHash: uhash},
		BannedRights: tg.ChatBannedRights{},
	})
	return err
}

func (t *TelegramCore) GetMembers(chatID string, opts PaginationOpts) ([]User, error) {
	limit := opts.Limit
	if limit <= 0 {
		limit = 50
	}
	users, err := t.GetParticipants(chatID, limit)
	if err == nil {
		return users, nil
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	peer, peerErr := t.resolvePeer(chatID)
	if peerErr != nil {
		return nil, peerErr
	}
	chat, ok := peer.(*tg.PeerChat)
	if !ok {
		return nil, err
	}
	result, fullErr := api.MessagesGetFullChat(ctx, chat.ChatID)
	if fullErr != nil {
		return nil, fullErr
	}
	t.cacheEntities(result.Users, result.Chats)
	roles := make(map[int64]string)
	if fc, ok := result.FullChat.(*tg.ChatFull); ok {
		if cp, ok := fc.Participants.(*tg.ChatParticipants); ok {
			for _, p := range cp.Participants {
				switch pt := p.(type) {
				case *tg.ChatParticipantCreator:
					roles[pt.UserID] = "creator"
				case *tg.ChatParticipantAdmin:
					roles[pt.UserID] = "admin"
				}
			}
		}
	}
	var members []User
	for _, u := range result.Users {
		if user, ok := u.(*tg.User); ok {
			cu := t.convertUser(user)
			if r, ok := roles[user.ID]; ok {
				cu.Role = r
			}
			members = append(members, *cu)
		}
	}
	return members, nil
}

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

func (t *TelegramCore) AddContact(phone string, firstName string, lastName string) error {
	_, err := t.AddContactReturnUserID(phone, firstName, lastName)
	return err
}

func (t *TelegramCore) AddContactReturnUserID(phone string, firstName string, lastName string) (string, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return "", err
	}
	var buf [8]byte
	rand.Read(buf[:])
	clientID := int64(binary.LittleEndian.Uint64(buf[:]))
	result, err := api.ContactsImportContacts(ctx, []tg.InputPhoneContact{
		{ClientID: clientID, Phone: phone, FirstName: firstName, LastName: lastName},
	})
	if err != nil {
		return "", err
	}
	for _, imp := range result.Imported {
		if imp.ClientID == clientID {
			return strconv.FormatInt(imp.UserID, 10), nil
		}
	}
	return "", nil
}

func (t *TelegramCore) AddContactWithNote(phone, firstName, lastName, note string, sharePhone bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.ContactsAddContactRequest{
		ID:                       &tg.InputUser{},
		FirstName:                firstName,
		LastName:                 lastName,
		Phone:                    phone,
		AddPhonePrivacyException: sharePhone,
	}
	req.SetNote(tg.TextWithEntities{Text: note})
	_, err = api.ContactsAddContact(ctx, req)
	return err
}

func parseNoteEntities(entitiesJSON string) []tg.MessageEntityClass {
	if entitiesJSON == "" {
		return nil
	}
	var ents []TextEntity
	if err := json.Unmarshal([]byte(entitiesJSON), &ents); err != nil {
		return nil
	}
	var out []tg.MessageEntityClass
	for _, e := range ents {
		var ent tg.MessageEntityClass
		switch e.Type {
		case "bold":
			ent = &tg.MessageEntityBold{Offset: e.Offset, Length: e.Length}
		case "italic":
			ent = &tg.MessageEntityItalic{Offset: e.Offset, Length: e.Length}
		case "underline":
			ent = &tg.MessageEntityUnderline{Offset: e.Offset, Length: e.Length}
		case "strike":
			ent = &tg.MessageEntityStrike{Offset: e.Offset, Length: e.Length}
		case "code":
			if e.Language != "" {
				ent = &tg.MessageEntityPre{Offset: e.Offset, Length: e.Length, Language: e.Language}
			} else {
				ent = &tg.MessageEntityCode{Offset: e.Offset, Length: e.Length}
			}
		case "pre":
			ent = &tg.MessageEntityPre{Offset: e.Offset, Length: e.Length, Language: e.Language}
		case "spoiler":
			ent = &tg.MessageEntitySpoiler{Offset: e.Offset, Length: e.Length}
		case "text_url":
			ent = &tg.MessageEntityTextURL{Offset: e.Offset, Length: e.Length, URL: e.URL}
		case "blockquote":
			ent = &tg.MessageEntityBlockquote{Offset: e.Offset, Length: e.Length}
		case "custom_emoji":
			ent = &tg.MessageEntityCustomEmoji{Offset: e.Offset, Length: e.Length, DocumentID: e.DocumentID}
		case "formatted_date":
			ent = &tg.MessageEntityFormattedDate{
				Offset:    e.Offset,
				Length:    e.Length,
				Date:      e.Date,
				Relative:  e.DateRelative,
				ShortTime: e.DateShortTime,
				LongTime:  e.DateLongTime,
				ShortDate: e.DateShortDate,
				LongDate:  e.DateLongDate,
				DayOfWeek: e.DateDayOfWeek,
			}
		default:
			continue
		}
		out = append(out, ent)
	}
	return out
}

func (t *TelegramCore) AddContactByUserID(userID, firstName, lastName, note, noteEntitiesJSON string, sharePhone bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	hash := t.getCachedUserHash(uid)
	req := &tg.ContactsAddContactRequest{
		ID:                       &tg.InputUser{UserID: uid, AccessHash: hash},
		FirstName:                firstName,
		LastName:                 lastName,
		AddPhonePrivacyException: sharePhone,
	}
	if note != "" {
		twe := tg.TextWithEntities{Text: note}
		if ents := parseNoteEntities(noteEntitiesJSON); len(ents) > 0 {
			twe.Entities = ents
		}
		req.SetNote(twe)
	}
	_, err = api.ContactsAddContact(ctx, req)
	return err
}

func (t *TelegramCore) SuggestContactPhoto(userID string, photoData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	u := uploader.NewUploader(t.api)
	upload, err := u.Upload(ctx, uploader.NewUpload("photo.png", io.NopCloser(bytes.NewReader(photoData)), int64(len(photoData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	_, err = api.PhotosUploadContactProfilePhoto(ctx, &tg.PhotosUploadContactProfilePhotoRequest{
		Suggest: true,
		UserID:  &tg.InputUser{UserID: uid, AccessHash: uhash},
		File:    upload,
	})
	return err
}

func (t *TelegramCore) SetPersonalContactPhoto(userID string, photoData []byte) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	u := uploader.NewUploader(t.api)
	upload, err := u.Upload(ctx, uploader.NewUpload("photo.png", io.NopCloser(bytes.NewReader(photoData)), int64(len(photoData))))
	if err != nil {
		return fmt.Errorf("upload: %w", err)
	}
	_, err = api.PhotosUploadContactProfilePhoto(ctx, &tg.PhotosUploadContactProfilePhotoRequest{
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
		File:   upload,
	})
	return err
}

func (t *TelegramCore) ClearPersonalContactPhoto(userID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	uid, err := tgUserID(userID)
	if err != nil {
		return err
	}
	uhash := t.getCachedUserHash(uid)
	_, err = api.PhotosUploadContactProfilePhoto(ctx, &tg.PhotosUploadContactProfilePhotoRequest{
		Save:   true,
		UserID: &tg.InputUser{UserID: uid, AccessHash: uhash},
	})
	return err
}

func (t *TelegramCore) DeleteContact(userID string) error {
	return t.DeleteContacts([]string{userID})
}

func (t *TelegramCore) GetBlockedUsers() ([]User, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.ContactsGetBlocked(ctx, &tg.ContactsGetBlockedRequest{Limit: 100})
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

func (t *TelegramCore) GetBlockedUsersPaged(offset, limit int) ([]User, int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, 0, err
	}
	if limit <= 0 {
		limit = 50
	}
	result, err := api.ContactsGetBlocked(ctx, &tg.ContactsGetBlockedRequest{
		Offset: offset,
		Limit:  limit,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("get blocked paged: %w", err)
	}
	var users []User
	var total int
	switch r := result.(type) {
	case *tg.ContactsBlocked:
		t.cacheEntities(r.Users, nil)
		for _, u := range r.Users {
			if user, ok := u.(*tg.User); ok {
				users = append(users, *t.convertUser(user))
			}
		}
		total = len(users) + offset
	case *tg.ContactsBlockedSlice:
		t.cacheEntities(r.Users, nil)
		for _, u := range r.Users {
			if user, ok := u.(*tg.User); ok {
				users = append(users, *t.convertUser(user))
			}
		}
		total = r.Count
	}
	return users, total, nil
}

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

func parseSavedReaction(s string) tg.ReactionClass {
	if strings.HasPrefix(s, "custom_") {
		if docID, err := strconv.ParseInt(s[len("custom_"):], 10, 64); err == nil {
			return &tg.ReactionCustomEmoji{DocumentID: docID}
		}
	}
	return &tg.ReactionEmoji{Emoticon: s}
}

func (t *TelegramCore) SearchSavedMessagesByReaction(savedPeerID string, reactions []string, offsetID, limit int) ([]Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 30
	}

	req := &tg.MessagesSearchRequest{
		Peer:     &tg.InputPeerSelf{},
		Q:        "",
		Filter:   &tg.InputMessagesFilterEmpty{},
		Limit:    limit,
		OffsetID: offsetID,
	}

	var savedReactions []tg.ReactionClass
	for _, r := range reactions {
		if r == "" {
			continue
		}
		savedReactions = append(savedReactions, parseSavedReaction(r))
	}
	if len(savedReactions) > 0 {
		req.SetSavedReaction(savedReactions)
	}

	if savedPeerID != "" {
		if peer, err := t.resolvePeer(savedPeerID); err == nil {
			if inputPeer, err := t.toInputPeer(peer); err == nil {
				req.SetSavedPeerID(inputPeer)
			}
		}
	}

	result, err := api.MessagesSearch(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("search saved by reaction: %w", err)
	}
	return t.convertMessages(result), nil
}

func (t *TelegramCore) SearchMessagesFromCount(chatID string, senderID string) (int, error) {
	chatPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return 0, err
	}
	defer unlock()

	senderPeer, err := t.resolvePeer(senderID)
	if err != nil {
		return 0, fmt.Errorf("resolve sender: %w", err)
	}
	senderInput, err := t.toInputPeer(senderPeer)
	if err != nil {
		return 0, fmt.Errorf("sender input peer: %w", err)
	}

	req := &tg.MessagesSearchRequest{
		Peer:   chatPeer,
		Q:      "",
		Filter: &tg.InputMessagesFilterEmpty{},
		Limit:  1,
	}
	req.SetFromID(senderInput)

	result, err := t.api.MessagesSearch(t.ctx, req)
	if err != nil {
		return 0, fmt.Errorf("search from count: %w", err)
	}

	switch r := result.(type) {
	case *tg.MessagesMessages:
		return len(r.Messages), nil
	case *tg.MessagesMessagesSlice:
		return r.Count, nil
	case *tg.MessagesChannelMessages:
		return r.Count, nil
	default:
		return 0, nil
	}
}

func (t *TelegramCore) SearchGlobal(query string, opts PaginationOpts) ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 20
	}
	result, err := api.ContactsSearch(ctx, &tg.ContactsSearchRequest{Q: query, Limit: limit})
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

func (t *TelegramCore) SearchGlobalUsers(query string, limit int) ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 20
	}
	result, err := api.ContactsSearch(ctx, &tg.ContactsSearchRequest{Q: query, Limit: limit})
	if err != nil {
		return nil, fmt.Errorf("global user search: %w", err)
	}
	t.cacheEntities(result.Users, result.Chats)
	seen := make(map[int64]bool)
	out := make([]map[string]interface{}, 0, len(result.Users))
	for _, u := range result.Users {
		user, ok := u.(*tg.User)
		if !ok || user.Self || user.Deleted || seen[user.ID] {
			continue
		}
		seen[user.ID] = true
		out = append(out, map[string]interface{}{
			"id":       strconv.FormatInt(user.ID, 10),
			"name":     userDisplayName(user),
			"username": user.Username,
		})
	}
	return out, nil
}

func (t *TelegramCore) SearchGlobalPosts(query string, opts PaginationOpts) ([]Dialog, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	limit := opts.Limit
	if limit <= 0 {
		limit = 20
	}
	result, err := api.ChannelsSearchPosts(ctx, &tg.ChannelsSearchPostsRequest{
		Hashtag:    query,
		OffsetPeer: &tg.InputPeerEmpty{},
		Limit:      limit,
	})
	if err != nil {
		dialogs, gErr := t.SearchGlobal(query, opts)
		if gErr != nil {
			return nil, err
		}
		var filtered []Dialog
		for _, d := range dialogs {
			if d.Type == ChatTypeChannel {
				filtered = append(filtered, d)
			}
		}
		return filtered, nil
	}
	return t.convertMessagesToDialogs(result), nil
}

func (t *TelegramCore) SearchGlobalPostMessages(query string, limit int) ([]Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 20
	}
	result, err := api.ChannelsSearchPosts(ctx, &tg.ChannelsSearchPostsRequest{
		Hashtag:    query,
		OffsetPeer: &tg.InputPeerEmpty{},
		Limit:      limit,
	})
	if err != nil {
		result, err = api.MessagesSearchGlobal(ctx, &tg.MessagesSearchGlobalRequest{
			Q:          query,
			Filter:     &tg.InputMessagesFilterEmpty{},
			OffsetPeer: &tg.InputPeerEmpty{},
			Limit:      limit,
		})
		if err != nil {
			return nil, fmt.Errorf("global post search: %w", err)
		}
	}
	return t.convertMessages(result), nil
}

func (t *TelegramCore) convertMessagesToDialogs(msgs tg.MessagesMessagesClass) []Dialog {
	var dialogs []Dialog
	seen := make(map[string]bool)
	switch m := msgs.(type) {
	case *tg.MessagesMessages:
		for _, ch := range m.Chats {
			if c, ok := ch.(*tg.Channel); ok && c.Broadcast {
				id := strconv.FormatInt(-1000000000000-c.ID, 10)
				if !seen[id] {
					seen[id] = true
					dialogs = append(dialogs, Dialog{ID: id, Title: c.Title, Type: ChatTypeChannel, Platform: tgPlatform})
				}
			}
		}
	case *tg.MessagesMessagesSlice:
		for _, ch := range m.Chats {
			if c, ok := ch.(*tg.Channel); ok && c.Broadcast {
				id := strconv.FormatInt(-1000000000000-c.ID, 10)
				if !seen[id] {
					seen[id] = true
					dialogs = append(dialogs, Dialog{ID: id, Title: c.Title, Type: ChatTypeChannel, Platform: tgPlatform})
				}
			}
		}
	case *tg.MessagesChannelMessages:
		for _, ch := range m.Chats {
			if c, ok := ch.(*tg.Channel); ok && c.Broadcast {
				id := strconv.FormatInt(-1000000000000-c.ID, 10)
				if !seen[id] {
					seen[id] = true
					dialogs = append(dialogs, Dialog{ID: id, Title: c.Title, Type: ChatTypeChannel, Platform: tgPlatform})
				}
			}
		}
	}
	return dialogs
}

func (t *TelegramCore) SendTyping(chatID string) error {
	return t.SetTyping(chatID, &tg.SendMessageTypingAction{})
}

func (t *TelegramCore) CreatePoll(chatID string, question string, options []string) (*Message, error) {
	return t.SendPoll(chatID, question, options)
}

func (t *TelegramCore) CreatePollWithRevoting(chatID string, question string, answers []string, multipleChoice, anonymous, quiz, allowRevoting, hideResults bool, correctOption int, solution string, limitDuration int) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	var pollAnswers []tg.PollAnswerClass
	for i, a := range answers {
		pollAnswers = append(pollAnswers, &tg.PollAnswer{Text: tg.TextWithEntities{Text: a}, Option: []byte{byte(i)}})
	}
	poll := tg.Poll{
		ID:       time.Now().UnixNano(),
		Question: tg.TextWithEntities{Text: question},
		Answers:  pollAnswers,
	}
	if !anonymous {
		poll.SetPublicVoters(true)
	}
	if multipleChoice {
		poll.SetMultipleChoice(true)
	}
	if quiz {
		poll.SetQuiz(true)
	}
	if !allowRevoting {
		poll.SetRevotingDisabled(true)
	}
	if hideResults {
		poll.SetHideResultsUntilClose(true)
	}
	if limitDuration > 0 {
		poll.SetClosePeriod(limitDuration)
	}
	media := &tg.InputMediaPoll{Poll: poll}
	if quiz && correctOption >= 0 && correctOption < len(answers) {
		media.SetCorrectAnswers([]int{correctOption})
	}
	if quiz && solution != "" {
		media.SetSolution(solution)
	}
	result, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(), Message: "",
		Media: media,
	})
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) CreatePollEx(chatID string, question string, answers []string, multipleChoice, anonymous, quiz bool, correctOption int, solution string) (*Message, error) {
	return t.CreatePollWithRevoting(chatID, question, answers, multipleChoice, anonymous, quiz, true, false, correctOption, solution, 0)
}

func (t *TelegramCore) CreatePollWithMedia(chatID string, question string, answers []string, mediaPaths []string, multipleChoice, anonymous, quiz, allowRevoting, hideResults bool, correctOption int, solution string, limitDuration int) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	u := uploader.NewUploader(t.api)
	var pollAnswers []tg.PollAnswerClass
	for i, a := range answers {
		answer := &tg.InputPollAnswer{Text: tg.TextWithEntities{Text: a}}
		if i < len(mediaPaths) && mediaPaths[i] != "" {
			f, err := os.Open(mediaPaths[i])
			if err == nil {
				info, _ := f.Stat()
				upload, err := u.Upload(t.ctx, uploader.NewUpload(info.Name(), f, info.Size()))
				f.Close()
				if err == nil {
					ext := strings.ToLower(filepath.Ext(mediaPaths[i]))
					if ext == ".jpg" || ext == ".jpeg" || ext == ".png" || ext == ".webp" {
						answer.SetMedia(&tg.InputMediaUploadedPhoto{File: upload})
					} else {
						mtype := "application/octet-stream"
						switch ext {
						case ".mp4", ".mov":
							mtype = "video/mp4"
						case ".gif":
							mtype = "image/gif"
						case ".webm":
							mtype = "video/webm"
						}
						answer.SetMedia(&tg.InputMediaUploadedDocument{
							File:     upload,
							MimeType: mtype,
						})
					}
				}
			}
		}
		pollAnswers = append(pollAnswers, answer)
	}
	poll := tg.Poll{
		ID:       time.Now().UnixNano(),
		Question: tg.TextWithEntities{Text: question},
		Answers:  pollAnswers,
	}
	if !anonymous {
		poll.SetPublicVoters(true)
	}
	if multipleChoice {
		poll.SetMultipleChoice(true)
	}
	if quiz {
		poll.SetQuiz(true)
	}
	if !allowRevoting {
		poll.SetRevotingDisabled(true)
	}
	if hideResults {
		poll.SetHideResultsUntilClose(true)
	}
	if limitDuration > 0 {
		poll.SetClosePeriod(limitDuration)
	}
	media := &tg.InputMediaPoll{Poll: poll}
	if quiz && correctOption >= 0 && correctOption < len(answers) {
		media.SetCorrectAnswers([]int{correctOption})
	}
	if quiz && solution != "" {
		media.SetSolution(solution)
	}
	result, err := t.api.MessagesSendMedia(t.ctx, &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(), Message: "",
		Media: media,
	})
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) VotePoll(chatID string, msgID string, optionIndex int) error {
	return t.VoteInPoll(chatID, msgID, optionIndex)
}

func (t *TelegramCore) SendSticker(chatID string, stickerID string) (*Message, error) {
	return t.SendStickerWithOpts(chatID, stickerID, false, 0)
}

func (t *TelegramCore) SendStickerWithOpts(chatID string, stickerID string, silent bool, scheduleDate int) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgUserID(stickerID)
	if err != nil {
		return nil, err
	}
	accessHash := t.GetCachedFileHash(id)
	fileRef := t.getCachedFileRef(id)
	req := &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(),
		Media: &tg.InputMediaDocument{ID: &tg.InputDocument{
			ID:            id,
			AccessHash:    accessHash,
			FileReference: fileRef,
		}},
		Silent: silent,
	}
	if scheduleDate > 0 {
		req.SetScheduleDate(scheduleDate)
	}
	result, err := t.api.MessagesSendMedia(t.ctx, req)
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) SendStickerWithCaption(chatID string, stickerID string, caption string, silent bool, scheduleDate int) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgUserID(stickerID)
	if err != nil {
		return nil, err
	}
	accessHash := t.GetCachedFileHash(id)
	fileRef := t.getCachedFileRef(id)
	req := &tg.MessagesSendMediaRequest{
		Peer: inputPeer, RandomID: time.Now().UnixNano(),
		Media: &tg.InputMediaDocument{ID: &tg.InputDocument{
			ID:            id,
			AccessHash:    accessHash,
			FileReference: fileRef,
		}},
		Message: caption,
		Silent:  silent,
	}
	if scheduleDate > 0 {
		req.SetScheduleDate(scheduleDate)
	}
	result, err := t.api.MessagesSendMedia(t.ctx, req)
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

const (
	tgTestApiID    = 17349
	tgSnapApiID    = 611335
	tgDesktopApiID = 2040
)

func formatVersionDisplay(version int) string {
	s := strconv.Itoa(version/1000000) + "." + strconv.Itoa((version%1000000)/1000)
	if version%1000 != 0 {
		s += "." + strconv.Itoa(version%1000)
	}
	return s
}

func normalizeSessionApp(apiID int, appName, appVersion string) (string, string) {
	isTest := apiID == tgTestApiID
	isDesktop := apiID == tgDesktopApiID || apiID == tgSnapApiID || isTest

	name := appName
	if isDesktop {
		name = "Telegram Desktop"
		if isTest {
			name += " (GitHub)"
		}
	}

	ver := appVersion
	if isDesktop {
		if n, err := strconv.Atoi(appVersion); err == nil && strconv.Itoa(n) == appVersion {
			ver = formatVersionDisplay(n)
		}
	} else if idx := strings.IndexByte(appVersion, '('); idx >= 0 {
		ver = appVersion[idx:]
	}
	return name, ver
}

func (t *TelegramCore) GetSessions() ([]Session, error) {
	sessions, err := t.GetActiveSessions()
	if err != nil {
		return nil, err
	}
	var result []Session
	for _, s := range sessions {
		appName, appVersion := normalizeSessionApp(s.ApiID, s.AppName, s.AppVersion)
		activeTime := s.DateActive
		if activeTime == 0 {
			activeTime = s.DateCreated
		}
		result = append(result, Session{
			ID:              strconv.FormatInt(s.Hash, 10),
			Device:          s.Device,
			Platform:        s.Platform,
			System:          s.SystemName,
			AppName:         appName,
			AppVersion:      appVersion,
			IP:              s.IP,
			Location:        s.Country,
			LastActive:      time.Unix(int64(activeTime), 0),
			IsCurrent:       s.IsCurrent,
			PasswordPending: s.PasswordPending,
			ApiID:           s.ApiID,
			OfficialApp:     s.OfficialApp,
		})
	}
	return result, nil
}

func (t *TelegramCore) MuteChat(chatID string, muted bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	settings := tg.InputPeerNotifySettings{}
	if muted {
		settings.SetMuteUntil(2147483647)
	} else {
		settings.SetMuteUntil(0)
	}

	_, err = api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: settings,
	})
	return err
}

func (t *TelegramCore) MuteChatFor(chatID string, durationSeconds int32) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	settings := tg.InputPeerNotifySettings{}
	settings.SetMuteUntil(int(time.Now().Unix()) + int(durationSeconds))

	_, err = api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: settings,
	})
	return err
}

type ChatNotifySettings struct {
	Muted        bool
	MuteUntil    int32
	SoundOn      bool
	ShowPreviews bool
}

func NotifySoundOn(s tg.NotificationSoundClass) bool {
	if _, is := s.(*tg.NotificationSoundNone); is {
		return false
	}
	return true
}

func NotifyPreviewsOf(s *tg.PeerNotifySettings) bool {
	if v, ok := s.GetShowPreviews(); ok {
		return v
	}
	return true
}

func ChatNotifySettingsFromWire(s *tg.PeerNotifySettings) ChatNotifySettings {
	if s == nil {
		return ChatNotifySettings{SoundOn: true, ShowPreviews: true}
	}
	muteUntil := int32(0)
	if s.MuteUntil > 0 && s.MuteUntil < 2000000000 {
		muteUntil = int32(s.MuteUntil)
	}
	return ChatNotifySettings{
		Muted:        s.MuteUntil > 0,
		MuteUntil:    muteUntil,
		SoundOn:      NotifySoundOn(s.OtherSound),
		ShowPreviews: NotifyPreviewsOf(s),
	}
}

func NotifySettingsInput(muteUntil int32, soundOn, showPreviews *bool) tg.InputPeerNotifySettings {
	settings := tg.InputPeerNotifySettings{}
	settings.SetMuteUntil(int(muteUntil))
	if soundOn != nil {
		if *soundOn {
			settings.SetSound(&tg.NotificationSoundDefault{})
		} else {
			settings.SetSound(&tg.NotificationSoundNone{})
		}
	}
	if showPreviews != nil {
		settings.SetShowPreviews(*showPreviews)
	}
	return settings
}

func (t *TelegramCore) GetChatNotifySettings(chatID string) (*ChatNotifySettings, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.AccountGetNotifySettings(ctx, &tg.InputNotifyPeer{Peer: inputPeer})
	if err != nil {
		return nil, err
	}
	s := ChatNotifySettingsFromWire(res)
	return &s, nil
}

func (t *TelegramCore) SetChatNotifySettings(chatID string, muteUntil int32, soundOn, showPreviews *bool) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: NotifySettingsInput(muteUntil, soundOn, showPreviews),
	})
	return err
}

func (t *TelegramCore) GetCallsDisabledHere() (bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return false, err
	}
	result, err := api.AccountGetAuthorizations(ctx)
	if err != nil {
		return false, err
	}
	for _, a := range result.Authorizations {
		if a.Current {
			return a.CallRequestsDisabled, nil
		}
	}
	return false, nil
}

func (t *TelegramCore) ResetPeerNotifySettings(chatID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	settings := tg.InputPeerNotifySettings{}
	_, err = t.api.AccountUpdateNotifySettings(t.ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: settings,
	})
	return err
}

func (t *TelegramCore) ToggleCallsDisabledHere(disabled bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.AccountChangeAuthorizationSettingsRequest{
		Hash: 0,
	}
	req.SetCallRequestsDisabled(disabled)
	_, err = api.AccountChangeAuthorizationSettings(ctx, req)
	return err
}

func (t *TelegramCore) UpdateDefaultNotifySettings(peerType string, enabled bool, silent *bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	var peer tg.InputNotifyPeerClass
	switch peerType {
	case "private":
		peer = &tg.InputNotifyUsers{}
	case "group":
		peer = &tg.InputNotifyChats{}
	case "channel":
		peer = &tg.InputNotifyBroadcasts{}
	default:
		return fmt.Errorf("unknown peer type: %s", peerType)
	}

	settings := tg.InputPeerNotifySettings{}
	if !enabled {
		settings.SetMuteUntil(2147483647)
	} else {
		settings.SetMuteUntil(0)
	}
	if silent != nil {
		settings.SetSilent(*silent)
	}

	_, err = api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     peer,
		Settings: settings,
	})
	return err
}

func (t *TelegramCore) MuteDefaultNotifyForDuration(peerType string, seconds int) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	var peer tg.InputNotifyPeerClass
	switch peerType {
	case "private":
		peer = &tg.InputNotifyUsers{}
	case "group":
		peer = &tg.InputNotifyChats{}
	case "channel":
		peer = &tg.InputNotifyBroadcasts{}
	default:
		return fmt.Errorf("unknown peer type: %s", peerType)
	}

	settings := tg.InputPeerNotifySettings{}
	settings.SetMuteUntil(int(time.Now().Unix()) + seconds)

	_, err = api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer:     peer,
		Settings: settings,
	})
	return err
}

func (t *TelegramCore) GetDefaultNotifySettings(peerType string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	var peer tg.InputNotifyPeerClass
	switch peerType {
	case "private":
		peer = &tg.InputNotifyUsers{}
	case "group":
		peer = &tg.InputNotifyChats{}
	case "channel":
		peer = &tg.InputNotifyBroadcasts{}
	default:
		return nil, fmt.Errorf("unknown peer type: %s", peerType)
	}

	s, err := api.AccountGetNotifySettings(ctx, peer)
	if err != nil {
		return nil, err
	}

	enabled := s.MuteUntil == 0
	soundEnabled := !s.Silent

	result := map[string]interface{}{
		"enabled":       enabled,
		"sound_enabled": soundEnabled,
	}

	if sound, ok := s.GetOtherSound(); ok {
		switch snd := sound.(type) {
		case *tg.NotificationSoundDefault:
			result["sound_id"] = int64(-1)
			result["sound_name"] = "Default"
		case *tg.NotificationSoundNone:
			result["sound_id"] = int64(-2)
			result["sound_name"] = "No sound"
		case *tg.NotificationSoundRingtone:
			result["sound_id"] = snd.ID
		case *tg.NotificationSoundLocal:
			result["sound_name"] = snd.Title
		}
	}

	return result, nil
}

func (t *TelegramCore) GetReactionsNotifySettings() (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	settings, err := api.AccountGetReactionsNotifySettings(ctx)
	if err != nil {
		return nil, err
	}
	fromStr := func(f tg.ReactionNotificationsFromClass) string {
		if f == nil {
			return ""
		}
		switch f.(type) {
		case *tg.ReactionNotificationsFromContacts:
			return "contacts"
		default:
			return "everyone"
		}
	}
	result := map[string]interface{}{
		"reactions_enabled":  settings.MessagesNotifyFrom != nil,
		"reactions_from":     "everyone",
		"poll_votes_enabled": settings.PollVotesNotifyFrom != nil,
		"poll_votes_from":    "everyone",
		"show_sender_name":   settings.ShowPreviews,
	}
	if settings.MessagesNotifyFrom != nil {
		result["reactions_from"] = fromStr(settings.MessagesNotifyFrom)
	}
	if settings.PollVotesNotifyFrom != nil {
		result["poll_votes_from"] = fromStr(settings.PollVotesNotifyFrom)
	}
	return result, nil
}

func (t *TelegramCore) SetReactionsNotifySettings(reactionsEnabled bool, reactionsFrom string, pollVotesEnabled bool, pollVotesFrom string, showSenderName bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	fromClass := func(s string) tg.ReactionNotificationsFromClass {
		if s == "contacts" {
			return &tg.ReactionNotificationsFromContacts{}
		}
		return &tg.ReactionNotificationsFromAll{}
	}

	settings := tg.ReactionsNotifySettings{
		ShowPreviews: showSenderName,
		Sound:        &tg.NotificationSoundDefault{},
	}
	if reactionsEnabled {
		settings.SetMessagesNotifyFrom(fromClass(reactionsFrom))
	}
	if pollVotesEnabled {
		settings.SetPollVotesNotifyFrom(fromClass(pollVotesFrom))
	}

	_, err = api.AccountSetReactionsNotifySettings(ctx, settings)
	return err
}

func (t *TelegramCore) GetSavedRingtones() ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.AccountGetSavedRingtones(ctx, 0)
	if err != nil {
		return nil, err
	}
	saved, ok := result.(*tg.AccountSavedRingtones)
	if !ok {
		return []map[string]interface{}{}, nil
	}
	var tones []map[string]interface{}
	for _, doc := range saved.Ringtones {
		d, ok := doc.(*tg.Document)
		if !ok {
			continue
		}
		name := fmt.Sprintf("Ringtone %d", d.ID)
		for _, attr := range d.Attributes {
			if a, ok := attr.(*tg.DocumentAttributeFilename); ok {
				name = a.FileName
				break
			}
			if a, ok := attr.(*tg.DocumentAttributeAudio); ok && a.Title != "" {
				name = a.Title
				break
			}
		}
		tone := map[string]interface{}{
			"id":   d.ID,
			"name": name,
		}
		if path := t.cachedRingtonePath(api, ctx, d); path != "" {
			tone["file_path"] = path
		}
		tones = append(tones, tone)
	}
	return tones, nil
}

func (t *TelegramCore) cachedRingtonePath(api *tg.Client, ctx context.Context, d *tg.Document) string {
	ext := ".ogg"
	switch d.MimeType {
	case "audio/mpeg", "audio/mp3":
		ext = ".mp3"
	case "audio/ogg", "audio/opus":
		ext = ".ogg"
	case "audio/wav", "audio/x-wav":
		ext = ".wav"
	case "audio/mp4", "audio/aac", "audio/x-m4a":
		ext = ".m4a"
	}
	dir, err := utils.PrivateCacheDir("telegram-ringtones")
	if err != nil {
		return ""
	}
	path := filepath.Join(dir, fmt.Sprintf("uniclient_ringtone_%d%s", d.ID, ext))
	if fi, err := os.Stat(path); err == nil && fi.Size() > 0 {
		return path
	}
	loc := &tg.InputDocumentFileLocation{
		ID:            d.ID,
		AccessHash:    d.AccessHash,
		FileReference: d.FileReference,
	}
	data, err := t.downloadSmallFile(api, ctx, loc, 4*1024*1024)
	if err != nil || len(data) == 0 {
		return ""
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return ""
	}
	return path
}

func (t *TelegramCore) UploadRingtone(fileName, mimeType string, data []byte) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	u := uploader.NewUploader(t.api)
	upload, err := u.Upload(ctx, uploader.NewUpload(fileName, io.NopCloser(bytes.NewReader(data)), int64(len(data))))
	if err != nil {
		return nil, fmt.Errorf("upload ringtone file: %w", err)
	}

	doc, err := api.AccountUploadRingtone(ctx, &tg.AccountUploadRingtoneRequest{
		File:     upload,
		FileName: fileName,
		MimeType: mimeType,
	})
	if err != nil {
		return nil, fmt.Errorf("account.uploadRingtone: %w", err)
	}

	d, ok := doc.(*tg.Document)
	if !ok {
		return nil, fmt.Errorf("unexpected document type: %T", doc)
	}

	_, err = api.AccountSaveRingtone(ctx, &tg.AccountSaveRingtoneRequest{
		ID:     &tg.InputDocument{ID: d.ID, AccessHash: d.AccessHash, FileReference: d.FileReference},
		Unsave: false,
	})
	if err != nil {
		return nil, fmt.Errorf("account.saveRingtone: %w", err)
	}

	name := fileName
	for _, attr := range d.Attributes {
		if a, ok := attr.(*tg.DocumentAttributeFilename); ok {
			name = a.FileName
			break
		}
	}
	return map[string]interface{}{
		"id":   d.ID,
		"name": name,
	}, nil
}

func (t *TelegramCore) DeleteRingtone(documentID int64) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	tones, err := api.AccountGetSavedRingtones(ctx, 0)
	if err != nil {
		return fmt.Errorf("get saved ringtones: %w", err)
	}
	saved, ok := tones.(*tg.AccountSavedRingtones)
	if !ok {
		return fmt.Errorf("no saved ringtones")
	}

	for _, doc := range saved.Ringtones {
		d, ok := doc.(*tg.Document)
		if !ok || d.ID != documentID {
			continue
		}
		_, err := api.AccountSaveRingtone(ctx, &tg.AccountSaveRingtoneRequest{
			ID:     &tg.InputDocument{ID: d.ID, AccessHash: d.AccessHash, FileReference: d.FileReference},
			Unsave: true,
		})
		return err
	}
	return fmt.Errorf("ringtone %d not found", documentID)
}

func (t *TelegramCore) GetNotificationExceptions(peerType string) ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	req := &tg.AccountGetNotifyExceptionsRequest{}
	switch peerType {
	case "private":
		req.SetPeer(&tg.InputNotifyUsers{})
	case "group":
		req.SetPeer(&tg.InputNotifyChats{})
	case "channel":
		req.SetPeer(&tg.InputNotifyBroadcasts{})
	}

	updates, err := api.AccountGetNotifyExceptions(ctx, req)
	if err != nil {
		return nil, err
	}

	var exceptions []map[string]interface{}
	switch u := updates.(type) {
	case *tg.Updates:
		for _, update := range u.Updates {
			if ns, ok := update.(*tg.UpdateNotifySettings); ok {
				exc := map[string]interface{}{
					"muted":         ns.NotifySettings.MuteUntil > 0,
					"sound_enabled": !ns.NotifySettings.Silent,
				}
				switch p := ns.Peer.(type) {
				case *tg.NotifyPeer:
					switch peer := p.Peer.(type) {
					case *tg.PeerUser:
						exc["peer_type"] = "user"
						exc["peer_id"] = peer.UserID
					case *tg.PeerChat:
						exc["peer_type"] = "chat"
						exc["peer_id"] = peer.ChatID
					case *tg.PeerChannel:
						exc["peer_type"] = "channel"
						exc["peer_id"] = peer.ChannelID
					}
				}
				if _, hasPeerID := exc["peer_id"]; hasPeerID {
					for _, user := range u.Users {
						if usr, ok := user.(*tg.User); ok && usr.ID == exc["peer_id"] {
							name := usr.FirstName
							if usr.LastName != "" {
								name += " " + usr.LastName
							}
							exc["name"] = name
							break
						}
					}
					for _, chat := range u.Chats {
						switch c := chat.(type) {
						case *tg.Chat:
							if int64(c.ID) == exc["peer_id"] {
								exc["name"] = c.Title
							}
						case *tg.Channel:
							if int64(c.ID) == exc["peer_id"] {
								exc["name"] = c.Title
							}
						}
					}
					exceptions = append(exceptions, exc)
				}
			}
		}
	}
	if exceptions == nil {
		exceptions = []map[string]interface{}{}
	}
	return exceptions, nil
}

func (t *TelegramCore) MarkUnread(chatID string, unread bool) error {
	return t.MarkDialogUnread(chatID, unread)
}

func (t *TelegramCore) SendLocation(chatID string, lat float64, lon float64) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesSendMedia(ctx, &tg.MessagesSendMediaRequest{
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

func LiveLocationMedia(lat, lon float64, period int) tg.InputMediaClass {
	m := &tg.InputMediaGeoLive{
		GeoPoint: &tg.InputGeoPoint{Lat: lat, Long: lon},
	}
	m.SetPeriod(period)
	return m
}

func LiveStopMedia() tg.InputMediaClass {
	m := &tg.InputMediaGeoLive{}
	m.SetStopped(true)
	return m
}

func (t *TelegramCore) SendLiveLocation(chatID string, lat float64, lon float64, period int) (*Message, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	result, err := api.MessagesSendMedia(ctx, &tg.MessagesSendMediaRequest{
		Peer:     inputPeer,
		Media:    LiveLocationMedia(lat, lon, period),
		RandomID: time.Now().UnixNano(),
		Message:  "",
	})
	if err != nil {
		return nil, fmt.Errorf("send live location: %w", err)
	}

	return t.extractMessageFromUpdates(result, chatID), nil
}

func (t *TelegramCore) StopLiveLocation(chatID, msgID string) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	unlock()
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	id, err := strconv.Atoi(msgID)
	if err != nil {
		return fmt.Errorf("invalid message ID: %s", msgID)
	}

	_, err = api.MessagesEditMessage(ctx, &tg.MessagesEditMessageRequest{
		Peer:  inputPeer,
		ID:    id,
		Media: LiveStopMedia(),
	})
	if err != nil {
		return fmt.Errorf("stop live location: %w", err)
	}
	return nil
}

func (t *TelegramCore) TerminateSession(sessionID string) error {
	hash, err := strconv.ParseInt(sessionID, 10, 64)
	if err != nil {
		return fmt.Errorf("invalid session ID: %w", err)
	}
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountResetAuthorization(ctx, hash)
	return err
}

func (t *TelegramCore) ClearPaymentInfo(clearCredentials, clearShipping bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	req := &tg.PaymentsClearSavedInfoRequest{}
	if clearCredentials {
		req.SetCredentials(true)
	}
	if clearShipping {
		req.SetInfo(true)
	}
	_, err = api.PaymentsClearSavedInfo(ctx, req)
	return err
}

func (t *TelegramCore) GetPaymentForm(chatID, msgID string) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	rawResult, err := t.api.PaymentsGetPaymentForm(t.ctx, &tg.PaymentsGetPaymentFormRequest{
		Invoice: &tg.InputInvoiceMessage{
			Peer:  inputPeer,
			MsgID: id,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("get payment form: %w", err)
	}
	result, ok := rawResult.(*tg.PaymentsPaymentForm)
	if !ok {
		return nil, fmt.Errorf("unexpected payment form type: %T", rawResult)
	}
	form := map[string]interface{}{
		"form_id":  result.FormID,
		"bot_id":   result.BotID,
		"title":    result.Title,
		"currency": result.Invoice.Currency,
		"test":     result.Invoice.Test,
	}
	if result.Description != "" {
		form["description"] = result.Description
	}
	if result.NativeProvider != "" {
		form["native_provider"] = result.NativeProvider
	}
	if np, ok := result.GetNativeParams(); ok {
		var nativeParams map[string]interface{}
		if err := json.Unmarshal([]byte(np.Data), &nativeParams); err == nil {
			form["native_params"] = nativeParams
		}
	}
	if result.URL != "" {
		form["url"] = result.URL
	}
	if p, ok := result.GetPhoto(); ok {
		if photo, ok := p.(*tg.WebDocument); ok {
			form["photo_url"] = photo.URL
		}
		if photo, ok := p.(*tg.WebDocumentNoProxy); ok {
			form["photo_url"] = photo.URL
		}
	}
	prices := make([]map[string]interface{}, 0, len(result.Invoice.Prices))
	for _, p := range result.Invoice.Prices {
		prices = append(prices, map[string]interface{}{
			"label":  p.Label,
			"amount": p.Amount,
		})
	}
	form["prices"] = prices
	var total int64
	for _, p := range result.Invoice.Prices {
		total += p.Amount
	}
	form["total_amount"] = total
	if result.Invoice.ShippingAddressRequested {
		form["shipping_requested"] = true
	}
	if result.Invoice.NameRequested {
		form["name_requested"] = true
	}
	if result.Invoice.EmailRequested {
		form["email_requested"] = true
	}
	if result.Invoice.PhoneRequested {
		form["phone_requested"] = true
	}
	if result.Invoice.Flexible {
		form["flexible"] = true
	}
	tips := make([]int64, 0, len(result.Invoice.SuggestedTipAmounts))
	for _, ta := range result.Invoice.SuggestedTipAmounts {
		tips = append(tips, ta)
	}
	if len(tips) > 0 {
		form["suggested_tips"] = tips
	}
	if result.Invoice.MaxTipAmount > 0 {
		form["max_tip"] = result.Invoice.MaxTipAmount
	}
	if info, ok := result.GetSavedInfo(); ok {
		saved := map[string]interface{}{}
		if n, ok := info.GetName(); ok {
			saved["name"] = n
		}
		if ph, ok := info.GetPhone(); ok {
			saved["phone"] = ph
		}
		if em, ok := info.GetEmail(); ok {
			saved["email"] = em
		}
		if addr, ok := info.GetShippingAddress(); ok {
			saved["street1"] = addr.StreetLine1
			saved["street2"] = addr.StreetLine2
			saved["city"] = addr.City
			saved["state"] = addr.State
			saved["country"] = addr.CountryISO2
			saved["postcode"] = addr.PostCode
		}
		form["saved_info"] = saved
	}
	if result.CanSaveCredentials {
		form["can_save_credentials"] = true
	}
	if result.PasswordMissing {
		form["password_missing"] = true
	}
	if tUrl, ok := result.Invoice.GetTermsURL(); ok {
		form["terms_url"] = tUrl
	}
	return form, nil
}

func (t *TelegramCore) GetPaymentReceipt(chatID, msgID string) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	rawResult, err := t.api.PaymentsGetPaymentReceipt(t.ctx, &tg.PaymentsGetPaymentReceiptRequest{
		Peer:  inputPeer,
		MsgID: id,
	})
	if err != nil {
		return nil, fmt.Errorf("get payment receipt: %w", err)
	}
	result, ok := rawResult.(*tg.PaymentsPaymentReceipt)
	if !ok {
		return nil, fmt.Errorf("unexpected payment receipt type: %T", rawResult)
	}
	receipt := map[string]interface{}{
		"title":        result.Title,
		"currency":     result.Invoice.Currency,
		"total_amount": result.TotalAmount,
		"date":         result.Date,
		"bot_id":       result.BotID,
		"is_receipt":   true,
	}
	if result.Description != "" {
		receipt["description"] = result.Description
	}
	if p, ok := result.GetPhoto(); ok {
		if photo, ok := p.(*tg.WebDocument); ok {
			receipt["photo_url"] = photo.URL
		}
		if photo, ok := p.(*tg.WebDocumentNoProxy); ok {
			receipt["photo_url"] = photo.URL
		}
	}
	prices := make([]map[string]interface{}, 0, len(result.Invoice.Prices))
	for _, p := range result.Invoice.Prices {
		prices = append(prices, map[string]interface{}{
			"label":  p.Label,
			"amount": p.Amount,
		})
	}
	receipt["prices"] = prices
	if result.Invoice.SuggestedTipAmounts != nil {
		receipt["tip_amount"] = result.TipAmount
	}
	if info, ok := result.GetInfo(); ok {
		saved := map[string]interface{}{}
		if n, ok := info.GetName(); ok {
			saved["name"] = n
		}
		if ph, ok := info.GetPhone(); ok {
			saved["phone"] = ph
		}
		if em, ok := info.GetEmail(); ok {
			saved["email"] = em
		}
		if addr, ok := info.GetShippingAddress(); ok {
			saved["street1"] = addr.StreetLine1
			saved["street2"] = addr.StreetLine2
			saved["city"] = addr.City
			saved["state"] = addr.State
			saved["country"] = addr.CountryISO2
			saved["postcode"] = addr.PostCode
		}
		receipt["saved_info"] = saved
	}
	if so, ok := result.GetShipping(); ok {
		receipt["shipping_option"] = so.Title
	}
	return receipt, nil
}

func (t *TelegramCore) SendPaymentForm(chatID, msgID string, formData map[string]interface{}) error {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return err
	}
	formID, _ := formData["form_id"].(float64)
	credentialsData := "{}"
	if cd, ok := formData["credentials_data"].(string); ok && cd != "" {
		credentialsData = cd
	}
	saveCredentials := false
	if sc, ok := formData["save_credentials"].(bool); ok {
		saveCredentials = sc
	}
	req := &tg.PaymentsSendPaymentFormRequest{
		FormID: int64(formID),
		Invoice: &tg.InputInvoiceMessage{
			Peer:  inputPeer,
			MsgID: id,
		},
		Credentials: &tg.InputPaymentCredentials{
			Save: saveCredentials,
			Data: tg.DataJSON{Data: credentialsData},
		},
	}
	if tipAmount, ok := formData["tip_amount"].(float64); ok && tipAmount > 0 {
		req.SetTipAmount(int64(tipAmount))
	}
	if infoID, ok := formData["requested_info_id"].(string); ok && infoID != "" {
		req.SetRequestedInfoID(infoID)
	}
	if shippingID, ok := formData["shipping_option_id"].(string); ok && shippingID != "" {
		req.SetShippingOptionID(shippingID)
	}
	_, err = t.api.PaymentsSendPaymentForm(t.ctx, req)
	if err != nil {
		return fmt.Errorf("send payment form: %w", err)
	}
	return nil
}

func (t *TelegramCore) ValidatePaymentInfo(chatID, msgID string, info map[string]interface{}, save bool) (map[string]interface{}, error) {
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return nil, err
	}
	defer unlock()
	id, err := tgMsgID(msgID)
	if err != nil {
		return nil, err
	}
	reqInfo := tg.PaymentRequestedInfo{}
	if name, ok := info["name"].(string); ok && name != "" {
		reqInfo.SetName(name)
	}
	if phone, ok := info["phone"].(string); ok && phone != "" {
		reqInfo.SetPhone(phone)
	}
	if email, ok := info["email"].(string); ok && email != "" {
		reqInfo.SetEmail(email)
	}
	if street1, ok := info["street1"].(string); ok && street1 != "" {
		addr := tg.PostAddress{
			StreetLine1: street1,
		}
		if s2, ok := info["street2"].(string); ok {
			addr.StreetLine2 = s2
		}
		if c, ok := info["city"].(string); ok {
			addr.City = c
		}
		if s, ok := info["state"].(string); ok {
			addr.State = s
		}
		if co, ok := info["country"].(string); ok {
			addr.CountryISO2 = co
		}
		if pc, ok := info["postcode"].(string); ok {
			addr.PostCode = pc
		}
		reqInfo.SetShippingAddress(addr)
	}
	req := &tg.PaymentsValidateRequestedInfoRequest{
		Invoice: &tg.InputInvoiceMessage{
			Peer:  inputPeer,
			MsgID: id,
		},
		Info: reqInfo,
	}
	if save {
		req.SetSave(true)
	}
	result, err := t.api.PaymentsValidateRequestedInfo(t.ctx, req)
	if err != nil {
		return nil, fmt.Errorf("validate payment info: %w", err)
	}
	resp := map[string]interface{}{}
	if infoID, ok := result.GetID(); ok {
		resp["id"] = infoID
	}
	if options, ok := result.GetShippingOptions(); ok {
		opts := make([]map[string]interface{}, 0, len(options))
		for _, opt := range options {
			prices := make([]map[string]interface{}, 0, len(opt.Prices))
			for _, p := range opt.Prices {
				prices = append(prices, map[string]interface{}{
					"label":  p.Label,
					"amount": p.Amount,
				})
			}
			opts = append(opts, map[string]interface{}{
				"id":     opt.ID,
				"title":  opt.Title,
				"prices": prices,
			})
		}
		resp["shipping_options"] = opts
	}
	return resp, nil
}

func (t *TelegramCore) GetConnectedBots() ([]map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.AccountGetConnectedBots(ctx)
	if err != nil {
		return nil, err
	}
	var bots []map[string]interface{}
	for _, cb := range result.ConnectedBots {
		botName := ""
		for _, u := range result.Users {
			if user, ok := u.(*tg.User); ok && user.ID == cb.BotID {
				botName = user.FirstName
				if user.LastName != "" {
					botName += " " + user.LastName
				}
				break
			}
		}
		m := map[string]interface{}{
			"bot_id":           strconv.FormatInt(cb.BotID, 10),
			"bot_name":         botName,
			"can_reply":        cb.Rights.Reply,
			"exclude_selected": cb.Recipients.ExcludeSelected,
			"existing_chats":   cb.Recipients.ExistingChats,
			"new_chats":        cb.Recipients.NewChats,
			"contacts":         cb.Recipients.Contacts,
			"non_contacts":     cb.Recipients.NonContacts,
		}
		var userIDs []string
		if users, ok := cb.Recipients.GetUsers(); ok {
			for _, uid := range users {
				userIDs = append(userIDs, strconv.FormatInt(uid, 10))
			}
		}
		m["user_ids"] = userIDs
		bots = append(bots, m)
	}
	return bots, nil
}

func (t *TelegramCore) ToggleConnectedBotPaused(chatID string, paused bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	unlock()
	_, err = api.AccountToggleConnectedBotPaused(ctx, &tg.AccountToggleConnectedBotPausedRequest{
		Peer:   inputPeer,
		Paused: paused,
	})
	return err
}

func (t *TelegramCore) DisablePeerConnectedBot(chatID string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	inputPeer, unlock, err := t.withPeer(chatID)
	if err != nil {
		return err
	}
	unlock()
	_, err = api.AccountDisablePeerConnectedBot(ctx, inputPeer)
	return err
}

func (t *TelegramCore) GetSavedSublists(limit, offsetDate, offsetID int, excludePinned bool) ([]SavedSublistInfo, int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, 0, err
	}

	if limit <= 0 {
		limit = 50
	}

	req := &tg.MessagesGetSavedDialogsRequest{
		Limit:      limit,
		OffsetDate: offsetDate,
		OffsetID:   offsetID,
		OffsetPeer: &tg.InputPeerEmpty{},
	}
	if excludePinned {
		req.SetExcludePinned(true)
	}

	result, err := api.MessagesGetSavedDialogs(ctx, req)
	if err != nil {
		return nil, 0, err
	}

	var dialogs []tg.SavedDialogClass
	var messages []tg.MessageClass
	var users []tg.UserClass
	var chats []tg.ChatClass
	var totalCount int

	switch r := result.(type) {
	case *tg.MessagesSavedDialogs:
		dialogs = r.Dialogs
		messages = r.Messages
		users = r.Users
		chats = r.Chats
		totalCount = len(r.Dialogs)
	case *tg.MessagesSavedDialogsSlice:
		dialogs = r.Dialogs
		messages = r.Messages
		users = r.Users
		chats = r.Chats
		totalCount = r.Count
	case *tg.MessagesSavedDialogsNotModified:
		return nil, r.Count, nil
	default:
		return nil, 0, fmt.Errorf("unexpected saved dialogs type: %T", result)
	}

	userMap := make(map[int64]*tg.User)
	for _, u := range users {
		if user, ok := u.(*tg.User); ok {
			userMap[user.ID] = user
		}
	}
	chatMap := make(map[int64]tg.ChatClass)
	for _, c := range chats {
		switch ch := c.(type) {
		case *tg.Chat:
			chatMap[ch.ID] = ch
		case *tg.Channel:
			chatMap[ch.ID] = ch
		}
	}

	msgMap := make(map[int]string)
	msgTimeMap := make(map[int]int64)
	for _, m := range messages {
		if msg, ok := m.(*tg.Message); ok {
			text := msg.Message
			if text == "" && msg.Media != nil {
				text = "[media]"
			}
			msgMap[msg.ID] = text
			msgTimeMap[msg.ID] = int64(msg.Date) * 1000
		}
	}

	var sublists []SavedSublistInfo
	for _, d := range dialogs {
		sd, ok := d.(*tg.SavedDialog)
		if !ok {
			continue
		}

		var info SavedSublistInfo
		info.IsPinned = sd.Pinned
		info.TopMessage = sd.TopMessage
		info.LastMsgText = msgMap[sd.TopMessage]
		info.LastMsgTime = msgTimeMap[sd.TopMessage]

		switch p := sd.Peer.(type) {
		case *tg.PeerUser:
			info.PeerID = strconv.FormatInt(p.UserID, 10)
			info.Type = 1
			if p.UserID == t.selfID {
				info.IsSelf = true
				info.PeerName = "My Notes"
			} else if user, ok := userMap[p.UserID]; ok {
				info.PeerName = strings.TrimSpace(user.FirstName + " " + user.LastName)
			}
		case *tg.PeerChat:
			info.PeerID = strconv.FormatInt(p.ChatID, 10)
			info.Type = 2
			if ch, ok := chatMap[p.ChatID]; ok {
				if chat, ok := ch.(*tg.Chat); ok {
					info.PeerName = chat.Title
				}
			}
		case *tg.PeerChannel:
			info.PeerID = strconv.FormatInt(p.ChannelID, 10)
			info.Type = 3
			if ch, ok := chatMap[p.ChannelID]; ok {
				if channel, ok := ch.(*tg.Channel); ok {
					info.PeerName = channel.Title
				}
			}
		}

		if info.PeerName == "" {
			info.PeerName = info.PeerID
		}
		sublists = append(sublists, info)
	}

	return sublists, totalCount, nil
}

func (t *TelegramCore) GetPinnedSavedSublists() ([]SavedSublistInfo, int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, 0, err
	}

	result, err := api.MessagesGetPinnedSavedDialogs(ctx)
	if err != nil {
		return nil, 0, err
	}

	var dialogs []tg.SavedDialogClass
	var messages []tg.MessageClass
	var users []tg.UserClass
	var chats []tg.ChatClass
	var totalCount int

	switch r := result.(type) {
	case *tg.MessagesSavedDialogs:
		dialogs = r.Dialogs
		messages = r.Messages
		users = r.Users
		chats = r.Chats
		totalCount = len(r.Dialogs)
	case *tg.MessagesSavedDialogsSlice:
		dialogs = r.Dialogs
		messages = r.Messages
		users = r.Users
		chats = r.Chats
		totalCount = r.Count
	case *tg.MessagesSavedDialogsNotModified:
		return nil, r.Count, nil
	default:
		return nil, 0, fmt.Errorf("unexpected pinned saved dialogs type: %T", result)
	}

	userMap := make(map[int64]*tg.User)
	for _, u := range users {
		if user, ok := u.(*tg.User); ok {
			userMap[user.ID] = user
		}
	}
	chatMap := make(map[int64]tg.ChatClass)
	for _, c := range chats {
		switch ch := c.(type) {
		case *tg.Chat:
			chatMap[ch.ID] = ch
		case *tg.Channel:
			chatMap[ch.ID] = ch
		}
	}

	msgMap := make(map[int]string)
	msgTimeMap := make(map[int]int64)
	for _, m := range messages {
		if msg, ok := m.(*tg.Message); ok {
			text := msg.Message
			if text == "" && msg.Media != nil {
				text = "[media]"
			}
			msgMap[msg.ID] = text
			msgTimeMap[msg.ID] = int64(msg.Date) * 1000
		}
	}

	var sublists []SavedSublistInfo
	for _, d := range dialogs {
		sd, ok := d.(*tg.SavedDialog)
		if !ok {
			continue
		}

		var info SavedSublistInfo
		info.IsPinned = true
		info.TopMessage = sd.TopMessage
		info.LastMsgText = msgMap[sd.TopMessage]
		info.LastMsgTime = msgTimeMap[sd.TopMessage]

		switch p := sd.Peer.(type) {
		case *tg.PeerUser:
			info.PeerID = strconv.FormatInt(p.UserID, 10)
			info.Type = 1
			if p.UserID == t.selfID {
				info.IsSelf = true
				info.PeerName = "My Notes"
			} else if user, ok := userMap[p.UserID]; ok {
				info.PeerName = strings.TrimSpace(user.FirstName + " " + user.LastName)
			}
		case *tg.PeerChat:
			info.PeerID = strconv.FormatInt(p.ChatID, 10)
			info.Type = 2
			if ch, ok := chatMap[p.ChatID]; ok {
				if chat, ok := ch.(*tg.Chat); ok {
					info.PeerName = chat.Title
				}
			}
		case *tg.PeerChannel:
			info.PeerID = strconv.FormatInt(p.ChannelID, 10)
			info.Type = 3
			if ch, ok := chatMap[p.ChannelID]; ok {
				if channel, ok := ch.(*tg.Channel); ok {
					info.PeerName = channel.Title
				}
			}
		}

		if info.PeerName == "" {
			info.PeerName = info.PeerID
		}
		sublists = append(sublists, info)
	}

	return sublists, totalCount, nil
}

func (t *TelegramCore) GetSavedReactionTags(sublistPeerID string) ([]SavedReactionTagInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}

	req := &tg.MessagesGetSavedReactionTagsRequest{
		Hash: 0,
	}
	if sublistPeerID != "" {
		peer, err := t.resolvePeer(sublistPeerID)
		if err == nil {
			if inputPeer, err := t.toInputPeer(peer); err == nil {
				req.SetPeer(inputPeer)
			}
		}
	}

	result, err := api.MessagesGetSavedReactionTags(ctx, req)
	if err != nil {
		return nil, err
	}

	switch r := result.(type) {
	case *tg.MessagesSavedReactionTags:
		tags := make([]SavedReactionTagInfo, 0, len(r.Tags))
		for _, tag := range r.Tags {
			info := SavedReactionTagInfo{
				Title: tag.Title,
				Count: tag.Count,
			}
			switch reaction := tag.Reaction.(type) {
			case *tg.ReactionEmoji:
				info.Emoji = reaction.Emoticon
			case *tg.ReactionCustomEmoji:
				info.CustomID = reaction.DocumentID
			}
			tags = append(tags, info)
		}
		return tags, nil
	case *tg.MessagesSavedReactionTagsNotModified:
		return nil, nil
	default:
		return nil, fmt.Errorf("unexpected saved reaction tags type: %T", result)
	}
}

func (t *TelegramCore) RenameSavedReactionTag(emoji string, customID int64, title string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}

	req := &tg.MessagesUpdateSavedReactionTagRequest{}
	if customID != 0 {
		req.Reaction = &tg.ReactionCustomEmoji{DocumentID: customID}
	} else if emoji != "" {
		req.Reaction = &tg.ReactionEmoji{Emoticon: emoji}
	} else {
		return fmt.Errorf("either emoji or custom_id must be provided")
	}
	if title != "" {
		req.SetTitle(title)
	}

	_, err = api.MessagesUpdateSavedReactionTag(ctx, req)
	return err
}

func (t *TelegramCore) GetThemeBySlug(slug string, isDark bool) (*CloudThemeInfo, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	format := "tdesktop"
	th, err := api.AccountGetTheme(ctx, &tg.AccountGetThemeRequest{
		Format: format,
		Theme:  &tg.InputThemeSlug{Slug: slug},
	})
	if err != nil {
		return nil, err
	}
	info := &CloudThemeInfo{
		ID:         th.ID,
		AccessHash: th.AccessHash,
		Title:      th.Title,
		Slug:       th.Slug,
	}
	if doc, ok := th.GetDocument(); ok {
		info.DocumentId = doc.GetID()
	}
	if len(th.Settings) > 0 {
		s := th.Settings[0]
		if isDark && len(th.Settings) > 1 {
			s = th.Settings[1]
		}
		info.AccentColor = s.AccentColor
		switch s.BaseTheme.(type) {
		case *tg.BaseThemeNight, *tg.BaseThemeTinted:
			info.IsDark = true
		}
		if len(s.MessageColors) > 0 {
			info.SentColor = s.MessageColors[0]
		}
		info.RecvColor = info.AccentColor
	}
	return info, nil
}

func (t *TelegramCore) CheckGiftCode(slug string) (map[string]interface{}, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.PaymentsCheckGiftCode(ctx, slug)
	if err != nil {
		return nil, err
	}
	usedDate, hasUsed := result.GetUsedDate()
	info := map[string]interface{}{
		"days":         result.Days,
		"used":         hasUsed,
		"date":         result.Date,
		"via_giveaway": result.ViaGiveaway,
	}
	if hasUsed {
		info["used_date"] = usedDate
	}
	return info, nil
}

func (t *TelegramCore) ApplyGiftCode(slug string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.PaymentsApplyGiftCode(ctx, slug)
	return err
}

func (t *TelegramCore) GetPromoSuggestions() (PromoSuggestionsSnapshot, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return PromoSuggestionsSnapshot{}, err
	}
	res, err := api.HelpGetPromoData(ctx)
	if err != nil {
		return PromoSuggestionsSnapshot{}, fmt.Errorf("get promo data: %w", err)
	}
	result, ok := res.(*tg.HelpPromoData)
	if !ok {
		return PromoSuggestionsSnapshot{}, nil
	}
	snap := PromoSuggestionsSnapshot{Pending: result.GetPendingSuggestions()}
	if custom, ok := result.GetCustomPendingSuggestion(); ok {
		snap.Custom = &PromoSuggestion{
			Key:         "custom",
			Title:       plainText(custom.Title),
			Description: plainText(custom.Description),
			URL:         custom.URL,
		}
	}
	return snap, nil
}

func (t *TelegramCore) DismissSuggestion(key string) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.HelpDismissSuggestion(ctx, &tg.HelpDismissSuggestionRequest{
		Peer:       &tg.InputPeerEmpty{},
		Suggestion: key,
	})
	return err
}

func (t *TelegramCore) GetTodayBirthdayContacts() ([]BirthdayContact, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	result, err := api.ContactsGetBirthdays(ctx)
	if err != nil {
		return nil, fmt.Errorf("get birthdays: %w", err)
	}
	if result == nil {
		return nil, nil
	}
	now := time.Now()
	var out []BirthdayContact
	for _, cb := range result.Contacts {
		if cb.Birthday.Day == now.Day() && cb.Birthday.Month == int(now.Month()) {
			out = append(out, BirthdayContact{
				UserID: cb.ContactID,
				Name:   t.getCachedUserName(cb.ContactID),
			})
		}
	}
	return out, nil
}

func (t *TelegramCore) GetSelfSuggestionState() (SelfSuggestionState, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return SelfSuggestionState{}, err
	}
	var st SelfSuggestionState
	users, err := api.UsersGetUsers(ctx, []tg.InputUserClass{&tg.InputUserSelf{}})
	if err == nil {
		if len(users) > 0 {
			if user, ok := users[0].(*tg.User); ok {
				_, st.PhotoSet = user.GetPhoto()
			}
		}
	}
	full, err := api.UsersGetFullUser(ctx, &tg.InputUser{UserID: t.selfID})
	if err == nil && full != nil {
		if b, ok := full.FullUser.GetBirthday(); ok {
			st.BirthdaySet = true
			now := time.Now()
			st.BirthdayIsToday = b.Day == now.Day() && b.Month == int(now.Month())
		}
	}
	return st, nil
}

func plainText(twe tg.TextWithEntities) string {
	return twe.Text
}
