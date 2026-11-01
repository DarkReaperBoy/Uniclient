package gui

import (
	"fmt"
	"sync"
	"time"

	"image"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"

	"uniclient/engine"
)

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

var suggestionOrder = []string{
	"BIRTHDAY_CONTACTS_TODAY",
	"BIRTHDAY_SETUP",
	"custom",
	"PREMIUM_OFFER",
	"USERPIC_SETUP",
}

func pickSuggestion(st suggestionState) *promoSuggestionInfo {
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
				continue
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

func (st *suggestionState) dismiss(key string) {
	if st.dismissed == nil {
		st.dismissed = map[string]bool{}
	}
	st.dismissed[key] = true
}

var (
	suggBarBtn   widget.Clickable
	suggCloseBtn widget.Clickable
)

type suggestionFetchState struct {
	st      *engine.SuggestionState
	fetched time.Time
}

var (
	suggStates    = map[string]*suggestionFetchState{}
	suggFetching  = map[string]bool{}
	suggDismissed = map[string]map[string]bool{}
)

var suggMu sync.Mutex

func suggStateFor(acc string) (*suggestionFetchState, bool) {
	suggMu.Lock()
	defer suggMu.Unlock()
	cur, ok := suggStates[acc]
	return cur, ok
}

func suggStateStore(acc string, st *suggestionFetchState) {
	suggMu.Lock()
	suggStates[acc] = st
	suggMu.Unlock()
}

func suggFetchingStart(acc string) bool {
	suggMu.Lock()
	defer suggMu.Unlock()
	if suggFetching[acc] {
		return false
	}
	suggFetching[acc] = true
	return true
}

func suggFetchingDone(acc string) {
	suggMu.Lock()
	delete(suggFetching, acc)
	suggMu.Unlock()
}

func suggDismissedFor(acc string) map[string]bool {
	suggMu.Lock()
	defer suggMu.Unlock()
	return suggDismissed[acc]
}

func suggDismissedStore(acc, key string) {
	suggMu.Lock()
	if suggDismissed[acc] == nil {
		suggDismissed[acc] = map[string]bool{}
	}
	suggDismissed[acc][key] = true
	suggMu.Unlock()
}

const suggStaleTTL = time.Hour

func (a *App) ensureSuggestionState(f frame) {
	if len(f.accounts) == 0 {
		return
	}
	acc := f.accounts[0]
	if cur, ok := suggStateFor(acc.ID); ok && time.Since(cur.fetched) < suggStaleTTL {
		return
	}
	if !suggFetchingStart(acc.ID) {
		return
	}
	go func() {
		defer suggFetchingDone(acc.ID)
		st, err := a.eng.GetSuggestionState(acc.ID)
		if err != nil || st == nil {
			return
		}
		suggStateStore(acc.ID, &suggestionFetchState{st: st, fetched: time.Now()})
		a.invalidate()
	}()
}

func (a *App) guiSuggestionState(f frame) suggestionState {
	if len(f.accounts) == 0 {
		return suggestionState{}
	}
	acc := f.accounts[0]
	cur, ok := suggStateFor(acc.ID)
	if !ok || cur.st == nil {
		return suggestionState{}
	}
	return suggestionState{
		Pending:          cur.st.Pending,
		Custom:           cur.st.Custom,
		BirthdayContacts: cur.st.BirthdayContacts,
		Self:             cur.st.Self,
		dismissed:        suggDismissedFor(acc.ID),
	}
}

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
		suggDismissedStore(acc.ID, key)
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

func materialButtonSurface(a *App, gtx layout.Context, btn *widget.Clickable, w layout.Widget) layout.Dimensions {
	return roundedFill(gtx, a.ui.p.Surface, unit.Dp(12), func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Min.X = gtx.Constraints.Max.X
		return btn.Layout(gtx, w)
	})
}

func suggestionGlyph(key string) *widget.Icon {
	switch key {
	case "BIRTHDAY_CONTACTS_TODAY", "BIRTHDAY_SETUP":
		return iconActionSchedule
	case "PREMIUM_OFFER":
		return iconToggleStar
	default:
		return iconActionAccount
	}
}

func (a *App) suggestionActivated(accountID string, card *promoSuggestionInfo) {
	switch card.Key {
	case "BIRTHDAY_CONTACTS_TODAY":
		if cur, ok := suggStateFor(accountID); ok && cur.st != nil && len(cur.st.BirthdayContacts) > 0 {
			uid := fmt.Sprintf("%d", cur.st.BirthdayContacts[0].UserID)
			title := cur.st.BirthdayContacts[0].Name
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
