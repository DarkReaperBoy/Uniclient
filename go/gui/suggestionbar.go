package gui

// suggestionbar.go — slice 171: the chat-list top-bar suggestion card
// (tdesktop dialogs/suggestions 1:1: a card above the dialog rows).
//
// Priority (tdesktop suggestion.cpp AllSpecs order, reduced to keys we
// can act on with REAL local surface — the rest stay hidden exactly
// like tdesktop hides unknown keys):
//
//	BIRTHDAY_CONTACTS_TODAY → open the contact's chat
//	BIRTHDAY_SETUP          → own profile editor (birthday field)
//	custom server card      → openLinkExternal(URL)
//	PREMIUM_OFFER           → Premium settings page
//	USERPIC_SETUP           → own profile editor (avatar)

import (
	"fmt"
	"time"

	"image"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

// suggestionState is the GUI-side decision input (mirrors
// engine.SuggestionState plus the local dismissal set).
type suggestionState struct {
	Pending          []string
	Custom           *promoSuggestionInfo
	BirthdayContacts []birthdayContactInfo
	Self             selfState
	dismissed        map[string]bool
}

type promoSuggestionInfo = engine.PromoSuggestionInfo
type birthdayContactInfo = engine.BirthdayContactInfo
type selfState = engine.SelfSuggestionStateInfo

// suggestionOrder is the render priority (tdesktop AllSpecs, filtered
// to actionable keys).
var suggestionOrder = []string{
	"BIRTHDAY_CONTACTS_TODAY",
	"BIRTHDAY_SETUP",
	"custom",
	"PREMIUM_OFFER",
	"USERPIC_SETUP",
}

// pickSuggestion chooses the card to render, honoring the local
// dismissals and the setup-gates. Returns nil for "render nothing".
func pickSuggestion(st suggestionState) *promoSuggestionInfo {
	// Local birthday contacts win even without the server key (the data
	// is local and definitive — tdesktop shows the card while the
	// birthday set is still being fetched).
	if !st.dismissed["BIRTHDAY_CONTACTS_TODAY"] && len(st.BirthdayContacts) > 0 {
		n := len(st.BirthdayContacts)
		title := fmt.Sprintf("%d contacts have birthdays today", n)
		if n == 1 {
			title = fmt.Sprintf("%s has a birthday today", st.BirthdayContacts[0].Name)
		}
		return &promoSuggestionInfo{
			Key:         "BIRTHDAY_CONTACTS_TODAY",
			Title:       title,
			Description: "Send them a message",
		}
	}
	for _, key := range suggestionOrder {
		if st.dismissed[key] {
			continue
		}
		switch key {
		case "BIRTHDAY_SETUP":
			if containsSuggestionKey(st.Pending, key) && !st.Self.BirthdayIsToday {
				return &promoSuggestionInfo{
					Key:         key,
					Title:       "Add your birthday",
					Description: "Let your contacts know when to celebrate you",
				}
			}
		case "custom":
			if st.Custom != nil && st.Custom.Title != "" {
				return st.Custom
			}
		case "PREMIUM_OFFER", "USERPIC_SETUP":
			if !containsSuggestionKey(st.Pending, key) {
				continue
			}
			if key == "USERPIC_SETUP" && st.Self.PhotoSet {
				continue // nothing to set up — the server key is stale
			}
			title, desc := "Upgrade to Premium", "Support bigger uploads, faster downloads and more"
			if key == "USERPIC_SETUP" {
				title, desc = "Add a profile photo", "Personalize your account with a profile photo"
			}
			return &promoSuggestionInfo{
				Key:         key,
				Title:       title,
				Description: desc,
			}
		}
	}
	return nil
}

func containsSuggestionKey(keys []string, key string) bool {
	for _, k := range keys {
		if k == key {
			return true
		}
	}
	return false
}

// dismiss hides a key locally (help.dismissSuggestion is fired by the
// engine separately).
func (st *suggestionState) dismiss(key string) {
	if st.dismissed == nil {
		st.dismissed = map[string]bool{}
	}
	st.dismissed[key] = true
}

// ── widget state ───────────────────────────────────────────────────────────

var (
	suggBarBtn   widget.Clickable // whole-bar action
	suggCloseBtn widget.Clickable // X
)

// suggestionFetchState is one account's fetched state.
type suggestionFetchState struct {
	st      *engine.SuggestionState
	fetched time.Time
}

var (
	suggStates    = map[string]*suggestionFetchState{}
	suggFetching  = map[string]bool{}
	suggDismissed = map[string]map[string]bool{} // accountID → key (GUI-local mirror)
)

// suggStaleTTL mirrors tdesktop's hourly refresh.
const suggStaleTTL = time.Hour

// ensureSuggestionState fetches the account's suggestion state when
// missing or stale (async — the bar renders next frame).
func (a *App) ensureSuggestionState(f frame) {
	if len(f.accounts) == 0 {
		return
	}
	acc := f.accounts[0] // the visible account owns the bar (tdesktop: one per session)
	cur, ok := suggStates[acc.ID]
	if ok && time.Since(cur.fetched) < suggStaleTTL {
		return
	}
	if suggFetching[acc.ID] {
		return
	}
	suggFetching[acc.ID] = true
	go func() {
		defer delete(suggFetching, acc.ID)
		st, err := a.eng.GetSuggestionState(acc.ID)
		if err != nil || st == nil {
			return
		}
		suggStates[acc.ID] = &suggestionFetchState{st: st, fetched: time.Now()}
		a.invalidate()
	}()
}

// guiSuggestionState projects the engine state + local dismissals into
// the decision input.
func (a *App) guiSuggestionState(f frame) suggestionState {
	if len(f.accounts) == 0 {
		return suggestionState{}
	}
	acc := f.accounts[0]
	cur, ok := suggStates[acc.ID]
	if !ok || cur.st == nil {
		return suggestionState{}
	}
	return suggestionState{
		Pending:          cur.st.Pending,
		Custom:           cur.st.Custom,
		BirthdayContacts: cur.st.BirthdayContacts,
		Self:             cur.st.Self,
		dismissed:        suggDismissed[acc.ID],
	}
}

// layoutSuggestionBar renders the top-bar suggestion card above the
// dialog rows (below the folder tabs). Nothing renders when no
// suggestion is active — honest empty (§1.10).
func (a *App) layoutSuggestionBar(gtx layout.Context, f frame) layout.Dimensions {
	a.ensureSuggestionState(f)
	st := a.guiSuggestionState(f)
	card := pickSuggestion(st)
	if card == nil || len(f.accounts) == 0 {
		return layout.Dimensions{}
	}
	acc := f.accounts[0]

	if suggBarBtn.Clicked(gtx) {
		a.suggestionActivated(acc.ID, card)
	}
	if suggCloseBtn.Clicked(gtx) {
		key := card.Key
		if suggDismissed[acc.ID] == nil {
			suggDismissed[acc.ID] = map[string]bool{}
		}
		suggDismissed[acc.ID][key] = true
		go func() {
			_ = a.eng.DismissSuggestion(acc.ID, key)
			a.setToast("Suggestion dismissed")
		}()
	}

	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Top: unit.Dp(6), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return materialButtonSurface(a, gtx, &suggBarBtn, func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(10), Bottom: unit.Dp(10), Left: unit.Dp(14), Right: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Inset{Right: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									return drawerIcon(gtx, suggestionGlyph(card.Key), a.ui.p.Accent)
								})
							}),
							layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
								t := a.ui.Label(unit.Sp(14), card.Title)
								return t.Layout(gtx)
							}),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								// Close (X) — nested clickable inside the bar's
								// ButtonLayout: the bar ignores taps landing here
								// because the X consumes the pointer first.
								return suggCloseBtn.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									sz := gtx.Dp(unit.Dp(22))
									gtx.Constraints.Max = image.Pt(sz, sz)
									gtx.Constraints.Min = gtx.Constraints.Max
									return drawerIcon(gtx, iconContentClear, a.ui.p.TextDim)
								})
							}),
						)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return layout.Inset{Left: unit.Dp(32)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							d := a.ui.Dim(unit.Sp(11), card.Description)
							return d.Layout(gtx)
						})
					}),
				)
			})
		})
	})
}

// materialButtonSurface wraps a clickable in the standard card surface
// (rounded, Surface bg) — the sidebar card idiom.
func materialButtonSurface(a *App, gtx layout.Context, btn *widget.Clickable, w layout.Widget) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.Surface, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Min.X = gtx.Constraints.Max.X
		return btn.Layout(gtx, w)
	})
}

// suggestionGlyph picks the leading icon for a card key.
func suggestionGlyph(key string) *widget.Icon {
	switch key {
	case "BIRTHDAY_CONTACTS_TODAY", "BIRTHDAY_SETUP":
		return iconActionSchedule // calendar glyph (no cake in the MD set)
	case "PREMIUM_OFFER":
		return iconToggleStar
	default:
		return iconActionAccount
	}
}

// suggestionActivated routes the card tap to its real action.
func (a *App) suggestionActivated(accountID string, card *promoSuggestionInfo) {
	switch card.Key {
	case "BIRTHDAY_CONTACTS_TODAY":
		if st := suggStates[accountID]; st != nil && len(st.st.BirthdayContacts) > 0 {
			uid := fmt.Sprintf("%d", st.st.BirthdayContacts[0].UserID)
			title := st.st.BirthdayContacts[0].Name
			a.openChat(chatKey{AccountID: accountID, ChatID: uid}, title)
		}
	case "BIRTHDAY_SETUP", "USERPIC_SETUP":
		a.openProfileEdit(accountID)
	case "PREMIUM_OFFER":
		a.openPremiumPage(accountID)
	default:
		if card.URL != "" {
			a.openLinkExternal(card.URL)
		}
	}
}
