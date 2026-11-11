package app

import (
	"uniclient/ui/dialogs"
	"uniclient/ui/tokens"
)

const (
	MenuFooterName    = "Uniclient"
	MenuFooterVersion = "0.10.3"
)

const (
	connDisconnected = 0
	connConnecting   = 1
	connConnected    = 2
)

type MenuState struct {
	Open         bool
	Anim         bool
	From         float32
	To           float32
	Started      int
	Progress     float32
	FadeProgress float32
}

type MenuScrimPressed struct {
	Now int
}

func (MenuScrimPressed) isMsg() {}

func menuConnStatus(state int) string {
	switch state {
	case connConnected:
		return "online"
	case connConnecting:
		return "connecting"
	default:
		return "offline"
	}
}

func (m Model) MenuVisible() bool {
	return m.Menu.Progress > 0
}

func (m Model) MenuActive() bool {
	return m.Menu.Anim || m.MenuToggleRipple != (tokens.RippleState{})
}

func (m Model) MenuPressRoute(x, y int) (scrim, eat bool) {
	if !m.MenuVisible() {
		return false, false
	}
	if x < tokens.MainMenuWidth {
		return false, true
	}
	return true, false
}

func (m Model) menuContextAccountID() string {
	for _, a := range m.Accounts {
		if a.ID == m.selectedAccount {
			return a.ID
		}
	}
	if len(m.Accounts) > 0 {
		return m.Accounts[0].ID
	}
	return ""
}

func (m Model) MenuPane() dialogs.MenuView {
	v := dialogs.MenuView{
		Slide:         m.Menu.Progress,
		Fade:          m.Menu.FadeProgress,
		Width:         tokens.MainMenuWidth,
		WindowW:       m.Width,
		Height:        m.Height,
		FooterName:    MenuFooterName,
		FooterVersion: MenuFooterVersion,
	}
	ctx := m.menuContextAccountID()
	if ctx != "" {
		for _, a := range m.Accounts {
			if a.ID != ctx {
				continue
			}
			v.CoverHasAccount = true
			v.CoverName = a.DisplayName
			v.CoverStatus = menuConnStatus(a.ConnState)
			break
		}
	}
	if len(m.Accounts) > 0 {
		v.Rows = make([]dialogs.MenuAccountRow, 0, len(m.Accounts))
		for _, a := range m.Accounts {
			v.Rows = append(v.Rows, dialogs.MenuAccountRow{Name: a.DisplayName, Active: a.ID == ctx})
		}
	}
	return v
}

func (m *Model) pressMenuToggle(x, y, now int) {
	m.nowMs = now
	m.searchBlur()
	m.MenuTogglePress = true
	m.MenuToggleRipple = tokens.RippleState{
		OriginX: x - tokens.MainMenuToggleX,
		OriginY: y - tokens.MainMenuToggleY,
		Started: now,
	}
}

func (m *Model) releaseMenuToggle(x, y, now int) {
	m.nowMs = now
	if !m.MenuTogglePress {
		return
	}
	m.MenuTogglePress = false
	m.menuToggleRippleRelease(now)
	if dialogs.HeaderToggleHit(m.Columns().Dialogs, x, y) {
		m.menuSetOpen(!m.Menu.Open, now)
	}
}

func (m *Model) menuSetOpen(open bool, now int) {
	if m.Menu.Open == open {
		return
	}
	m.Menu.Open = open
	m.Menu.Anim = true
	m.Menu.From = m.Menu.Progress
	m.Menu.To = 0
	if open {
		m.Menu.To = 1
	}
	m.Menu.Started = now
	m.MenuToggleHover = false
}

func (m *Model) menuToggleRippleRelease(now int) {
	if m.MenuToggleRipple == (tokens.RippleState{}) || m.MenuToggleRipple.Fading {
		return
	}
	m.MenuToggleRipple.Fading = true
	m.MenuToggleRipple.FadeStarted = now
}

func (m *Model) menuToggleRippleTick(now int) {
	if m.MenuToggleRipple == (tokens.RippleState{}) {
		return
	}
	if m.MenuToggleRipple.Fading && now-m.MenuToggleRipple.FadeStarted >= tokens.HistoryToDownRippleHideMs {
		m.MenuToggleRipple = tokens.RippleState{}
	}
}

func (m *Model) menuTick(now int) {
	if !m.Menu.Anim {
		return
	}
	raw := float32(now-m.Menu.Started) / float32(tokens.MainMenuSlideDurationMs)
	if raw >= 1 {
		m.Menu.Progress = m.Menu.To
		m.Menu.FadeProgress = m.Menu.To
		m.Menu.Anim = false
		return
	}
	if raw < 0 {
		raw = 0
	}
	slide := tokens.EaseOutCirc(raw)
	fade := slide
	if m.Menu.To == 0 {
		fade = raw
	}
	m.Menu.Progress = m.Menu.From + (m.Menu.To-m.Menu.From)*slide
	m.Menu.FadeProgress = m.Menu.From + (m.Menu.To-m.Menu.From)*fade
}
