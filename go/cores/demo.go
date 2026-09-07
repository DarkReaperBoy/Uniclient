package cores

// Demo core: a fake platform used to evaluate the GUI with zero accounts and
// zero credentials. It fabricates a chat list with folders, message history,
// an echo bot, typing simulation and read receipts. It is registered under
// the "demo" platform in bootstrap and offered on the welcome screen.

import (
	"fmt"
	"sort"
	"strconv"
	"sync"
	"time"
)

type DemoCore struct {
	StubCore

	mu       sync.Mutex
	handler  func(Update)
	chats    []Dialog
	messages map[string][]Message // chatID -> ascending history
	ids      int
	stop     chan struct{}
}

var _ Core = (*DemoCore)(nil)

// NewDemoCore builds the fake world.
func NewDemoCore() *DemoCore {
	c := &DemoCore{
		messages: make(map[string][]Message),
		stop:     make(chan struct{}),
	}
	c.seed()
	return c
}

func (c *DemoCore) Name() string { return "demo" }

func (c *DemoCore) Capabilities() []string {
	return []string{
		CapText, CapFolders, CapTyping, CapReadReceipts, CapReactions,
		CapChannels, CapGroupCalls, CapPresence,
	}
}

func (c *DemoCore) Authenticate(AuthConfig) error {
	go func() {
		time.Sleep(300 * time.Millisecond)
		c.emit(Update{Type: UpdateConnectivity, ConnState: "connected"})
		// A burst of activity so the GUI feels alive.
		go c.activityLoop()
	}()
	return nil
}

func (c *DemoCore) Logout() error { return nil }

func (c *DemoCore) Close() error {
	select {
	case <-c.stop:
	default:
		close(c.stop)
	}
	return nil
}

func (c *DemoCore) OnUpdate(h func(Update)) {
	c.mu.Lock()
	c.handler = h
	c.mu.Unlock()
}

func (c *DemoCore) emit(u Update) {
	c.mu.Lock()
	h := c.handler
	c.mu.Unlock()
	if h != nil {
		u.Platform = "demo"
		h(u)
	}
}

// GetFolders returns Telegram-style folders so the folder tabs exercise the
// real GUI path.
func (c *DemoCore) GetFolders() ([]Folder, error) {
	return []Folder{
		{ID: "f-all", Name: "All", IsChatList: true},
		{ID: "f-people", Name: "People", Contacts: true, ExcludeArchived: true},
		{ID: "f-groups", Name: "Groups", Groups: true},
		{ID: "f-channels", Name: "Channels", Channels: true},
	}, nil
}

func (c *DemoCore) GetDialogs(opts PaginationOpts) ([]Dialog, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]Dialog, len(c.chats))
	copy(out, c.chats)
	sort.SliceStable(out, func(i, j int) bool {
		pi, pj := out[i].IsPinned, out[j].IsPinned
		if pi != pj {
			return pi
		}
		ti, tj := c.lastTime(out[i].ID), c.lastTime(out[j].ID)
		return ti.After(tj)
	})
	// "unread first" is not Telegram behaviour; keep pure time sort.
	if opts.Limit > 0 && len(out) > opts.Limit {
		out = out[:opts.Limit]
	}
	return out, nil
}

func (c *DemoCore) lastTime(chatID string) time.Time {
	msgs := c.messages[chatID]
	if len(msgs) == 0 {
		return time.Time{}
	}
	return msgs[len(msgs)-1].Timestamp
}

func (c *DemoCore) GetChatInfo(chatID string) (*Dialog, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := range c.chats {
		if c.chats[i].ID == chatID {
			d := c.chats[i]
			return &d, nil
		}
	}
	return nil, ErrNotFound
}

func (c *DemoCore) GetMessages(chatID string, opts PaginationOpts) ([]Message, error) {
	c.mu.Lock()
	msgs := append([]Message(nil), c.messages[chatID]...)
	c.mu.Unlock()
	// Newest-first, like the real cores.
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	limit := opts.Limit
	if limit <= 0 || limit > len(msgs) {
		limit = len(msgs)
	}
	return msgs[:limit], nil
}

func (c *DemoCore) SendMessage(chatID string, msg OutgoingMessage) (*Message, error) {
	m := c.store(chatID, "me", "You", msg.Text, true, MessageStatusSent)
	// Read receipt + reply from the echo bot.
	go func() {
		time.Sleep(700 * time.Millisecond)
		c.emit(Update{Type: UpdateReadState, ChatID: chatID, ReadState: &ReadState{
			MyLastRead:   m.ID,
			PeerLastRead: map[string]string{"me": m.ID},
		}})
		text := fmt.Sprintf("echo: %s", msg.Text)
		c.emit(Update{Type: UpdateTyping, ChatID: chatID, UserID: "bot", Action: "typing"})
		time.Sleep(900 * time.Millisecond)
		c.store(chatID, "bot", "Echo Bot", text, false, MessageStatusDelivered)
	}()
	return &m, nil
}

func (c *DemoCore) MarkAsRead(chatID, upToMsgID string) error { return nil }

func (c *DemoCore) GetProfile(userID string) (*User, error) {
	return &User{
		ID:          userID,
		DisplayName: "Demo User",
		Username:    "demo",
		Platform:    "demo",
	}, nil
}

// store appends a message to a chat, refreshes the dialog, emits the update.
func (c *DemoCore) store(chatID, senderID, senderName, text string, outgoing bool, status MessageStatus) Message {
	c.mu.Lock()
	c.ids++
	m := Message{
		ID:         strconv.Itoa(c.ids),
		ChatID:     chatID,
		SenderID:   senderID,
		SenderName: senderName,
		Text:       text,
		Timestamp:  time.Now(),
		Status:     status,
		IsOutgoing: outgoing,
		Platform:   "demo",
	}
	c.messages[chatID] = append(c.messages[chatID], m)
	for i := range c.chats {
		if c.chats[i].ID == chatID {
			c.chats[i].LastMessage = &m
			if !outgoing {
				if c.chats[i].UnreadCount == 0 {
					c.chats[i].UnreadCount = 1
				} else {
					c.chats[i].UnreadCount++
				}
			}
		}
	}
	c.mu.Unlock()
	if outgoing {
		c.emit(Update{Type: UpdateNewMessage, ChatID: chatID, Message: &m})
	} else {
		c.emit(Update{Type: UpdateNewMessage, ChatID: chatID, Message: &m})
	}
	return m
}

// activityLoop makes the demo world breathe: incoming messages, typing
// indicators, presence flips.
func (c *DemoCore) activityLoop() {
	bursts := [][]string{
		{"g-dev", "Linus", "Anyone tried the new Gio release? The Vulkan backend is 🔥"},
		{"dm-alice", "Alice", "Did you see the release notes? 🚀"},
		{"chan-news", "Uniclient News", "v0.4.0 is out: folders, voice tab, scrolling everywhere."},
		{"g-dev", "Grace", "Just tested it — scroll finally feels native."},
	}
	i := 0
	for {
		select {
		case <-c.stop:
			return
		case <-time.After(9 * time.Second):
		}
		if len(bursts) == 0 {
			continue
		}
		b := bursts[i%len(bursts)]
		i++
		chatID, sender, text := b[0], b[1], b[2]
		c.emit(Update{Type: UpdateTyping, ChatID: chatID, UserID: sender, Action: "typing"})
		time.Sleep(1200 * time.Millisecond)
		var senderID = "u-" + sender
		c.store(chatID, senderID, sender, text, false, MessageStatusDelivered)
	}
}

// seed builds the fake world once.
func (c *DemoCore) seed() {
	now := time.Now()
	type seed struct {
		id, title string
		chatType  ChatType
		pinned    bool
		unread    int
		members   int
		hist      [][2]string // sender, text
	}
	seeds := []seed{
		{"dm-alice", "Alice Kim", ChatTypeDM, true, 0, 0, [][2]string{
			{"Alice", "hey! how's the new client treating you?"},
			{"You", "honestly it's starting to feel like AyuGram"},
			{"Alice", "that was the goal 😄 folders and everything?"},
			{"You", "yep, folder tabs on top of the chat list"},
		}},
		{"g-dev", "Gio Developers", ChatTypeGroup, true, 3, 128, [][2]string{
			{"Elias", "The text shaper rewrite landed."},
			{"Dominik", "benchmarks look great, +30% shaping throughput"},
			{"Alice", "does that fix the emoji fallback?"},
			{"Elias", "it does — per-glyph fallback is in"},
		}},
		{"chan-news", "Uniclient News", ChatTypeChannel, false, 12, 4021, [][2]string{
			{"Uniclient News", "v0.3: the web-app era is over. Native Gio GUI only."},
			{"Uniclient News", "v0.4: folders, voice tab, demo backend, Android APK."},
		}},
		{"dm-bob", "Bob Marsh", ChatTypeDM, false, 1, 0, [][2]string{
			{"Bob", "can it do IRC yet?"},
			{"You", "yes — verified against a real server already"},
		}},
		{"g-voice", "Friday Voice Chat", ChatTypeGroup, false, 0, 9, [][2]string{
			{"Alice", "voice room opens at 8, bring headphones"},
		}},
		{"chan-go", "Go Weekly", ChatTypeChannel, false, 44, 15700, [][2]string{
			{"Go Weekly", "Issue #212: generics deep-dive + the new wasm imports"},
		}},
	}
	for _, s := range seeds {
		c.chats = append(c.chats, Dialog{
			ID:          s.id,
			Type:        s.chatType,
			Title:       s.title,
			UnreadCount: s.unread,
			IsPinned:    s.pinned,
			MemberCount: s.members,
			Platform:    "demo",
			Username:    s.id,
		})
		base := now.Add(-time.Duration(len(seeds)) * time.Hour)
		for j, h := range s.hist {
			c.ids++
			outgoing := h[0] == "You"
			m := Message{
				ID:         strconv.Itoa(c.ids),
				ChatID:     s.id,
				SenderID:   "u-" + h[0],
				SenderName: h[0],
				Text:       h[1],
				Timestamp:  base.Add(time.Duration(j) * 3 * time.Minute),
				Status:     MessageStatusRead,
				IsOutgoing: outgoing,
				Platform:   "demo",
			}
			c.messages[s.id] = append(c.messages[s.id], m)
			d := &c.chats[len(c.chats)-1]
			d.LastMessage = &m
		}
	}
}
