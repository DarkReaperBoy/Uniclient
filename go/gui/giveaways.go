package gui

// giveaways.go — slice 212: the giveaway box (tdesktop
// create_giveaway_box, re-implemented): stars-giveaway creation funded
// from the star balance (options → winner split → end date → audience
// toggles → additional prize → send), plus prepaid-giveaway launch rows
// surfaced from the boosts status. Reached from the boosts page.

import (
	"sort"
	"strconv"
	"strings"
	"time"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/cores"
	"uniclient/engine"
)

var (
	giveawayBackBtn    widget.Clickable
	giveawaySendBtn    widget.Clickable
	giveawayOnlyNewBtn widget.Clickable
	giveawayShowWinBtn widget.Clickable
	giveawayList       widget.List
	giveawayOptCells   []widget.Clickable
	giveawayWinCells   []widget.Clickable
	giveawayDateCells  []widget.Clickable
	giveawayPrizeEd    widget.Editor
	// slice 214: country + channel pickers.
	giveawayCountriesRow widget.Clickable
	giveawayChannelsRow  widget.Clickable
	giveawayDoneBtn      widget.Clickable
	giveawaySearchEd     widget.Editor
	giveawayCountryCells []widget.Clickable
	giveawayChannelCells []widget.Clickable
)

func init() {
	giveawayList.Axis = layout.Vertical
	giveawayPrizeEd.SingleLine = true
}

// giveawayDatePreset is one offered end-date offset.
type giveawayDatePreset struct {
	Label string
	Days  int
}

// giveawayDatePresets (pure, testable): tdesktop defaults to 3 days; the
// row offers the common offsets.
func giveawayDatePresets() []giveawayDatePreset {
	return []giveawayDatePreset{
		{"in 3 days", 3},
		{"in 7 days", 7},
		{"in 14 days", 14},
		{"in 30 days", 30},
	}
}

// giveawayUntilDate (pure, testable): +days, then minutes rounded up to
// a 5-minute boundary — tdesktop's ThreeDaysAfterToday rule.
func giveawayUntilDate(days int, now time.Time) int64 {
	t := now.AddDate(0, 0, days)
	if r := t.Minute() % 5; r != 0 {
		t = t.Add(time.Duration(5-r) * time.Minute)
	}
	return t.Unix()
}

// prepaidGiveawayRow is one already-paid giveaway entry from the boosts
// status (channels.getBoostsStatus prepaid_giveaways).
type prepaidGiveawayRow struct {
	ID       int64
	Credits  int64
	Months   int
	Quantity int
	Boosts   int
	Date     int64
}

// prepaidFromBoostStatus (pure, testable) parses the boost-status map's
// prepaid entries (GetBoostsJSON shape).
func prepaidFromBoostStatus(st map[string]interface{}) []prepaidGiveawayRow {
	if st == nil {
		return nil
	}
	raw, ok := st["prepaid_giveaways"].([]interface{})
	if !ok {
		return nil
	}
	var rows []prepaidGiveawayRow
	for _, item := range raw {
		m, ok := item.(map[string]interface{})
		if !ok {
			continue
		}
		row := prepaidGiveawayRow{
			ID:       boostInt64Field(m, "id"),
			Credits:  boostInt64Field(m, "credits"),
			Months:   boostIntField(m, "months"),
			Quantity: boostIntField(m, "quantity"),
			Boosts:   boostIntField(m, "boosts"),
			Date:     boostInt64Field(m, "date"),
		}
		if row.ID != 0 {
			rows = append(rows, row)
		}
	}
	return rows
}

// boostIntField reads a numeric map field across int/int64/float64.
func boostIntField(m map[string]interface{}, key string) int {
	return int(boostInt64Field(m, key))
}

// boostInt64Field reads a numeric map field across int/int64/float64.
func boostInt64Field(m map[string]interface{}, key string) int64 {
	switch v := m[key].(type) {
	case int:
		return int64(v)
	case int64:
		return v
	case float64:
		return int64(v)
	}
	return 0
}

// prepaidRowTitle (pure, testable).
func prepaidRowTitle(r prepaidGiveawayRow) string {
	if r.Credits > 0 {
		return "Prepaid Stars giveaway · " + strconv.FormatInt(r.Credits, 10) + " Stars"
	}
	return "Prepaid Premium giveaway · " + strconv.Itoa(r.Months) + " months"
}

// prepaidRowSub (pure, testable).
func prepaidRowSub(r prepaidGiveawayRow) string {
	sub := strconv.Itoa(r.Quantity) + " winners"
	if r.Boosts > 0 {
		sub += " · " + strconv.Itoa(r.Boosts) + " boosts"
	}
	return sub
}

// giveawayDlgState is the open giveaway box (nil when closed). Prepaid
// mode: Prepaid != nil — the box collects date/audience/prize and
// launches; create mode: Prepaid == nil — full option picker.
type giveawayDlgState struct {
	accountID string
	chatID    string
	peerTitle string

	prepaid *prepaidGiveawayRow

	options     []cores.StarsGiveawayOptionInfo
	selOpt      int
	selWin      int
	balance     int64 // nanostars
	periodMax   int   // seconds, 0 = unknown → presets unfiltered
	dateIdx     int
	onlyNew     bool
	showWinners bool
	loaded      bool
	err         string
	sending     bool
	launched    bool

	// slice 214: audience pickers.
	countries     []cores.CountryInfo
	selCountries  map[string]bool
	pickCountries bool
	countryQuery  string
	selChats      map[string]bool
	pickChannels  bool
}

// giveawayOptionLabel (pure, testable): the prize row label.
func giveawayOptionLabel(o cores.StarsGiveawayOptionInfo) string {
	s := strconv.FormatInt(o.Stars, 10) + " Stars"
	if o.YearlyBoosts > 0 {
		s += " · +" + strconv.Itoa(o.YearlyBoosts) + " boosts/yr"
	}
	if o.Default {
		s += " · Default"
	}
	return s
}

// giveawayWinnerLabel (pure, testable): one winner-split chip.
func giveawayWinnerLabel(w cores.StarsGiveawayWinnerInfo) string {
	noun := "winners"
	if w.Users == 1 {
		noun = "winner"
	}
	return strconv.Itoa(w.Users) + " " + noun + " · " + strconv.FormatInt(w.PerUserStars, 10) + " Stars each"
}

// giveawayTotalStars (pure, testable): the selected option's total cost.
func giveawayTotalStars(st *giveawayDlgState) int64 {
	if st == nil || st.selOpt < 0 || st.selOpt >= len(st.options) {
		return 0
	}
	return st.options[st.selOpt].Stars
}

// giveawaySendEnabled (pure, testable): the send-bar gate — loaded,
// option chosen, balance covers the total, nothing in flight. Prepaid
// launch needs no balance (already paid).
func giveawaySendEnabled(st *giveawayDlgState) bool {
	if st == nil || st.sending || st.launched {
		return false
	}
	if st.prepaid != nil {
		return true
	}
	if !st.loaded || st.selOpt < 0 || st.selOpt >= len(st.options) {
		return false
	}
	return st.balance >= giveawayTotalStars(st)*1_000_000_000
}

// giveawayDatePresetsFor filters presets by the account's
// giveaway_period_max when known (pure, testable).
func giveawayDatePresetsFor(periodMax int) []giveawayDatePreset {
	presets := giveawayDatePresets()
	if periodMax <= 0 {
		return presets
	}
	var out []giveawayDatePreset
	for _, p := range presets {
		if p.Days*86400 <= periodMax {
			out = append(out, p)
		}
	}
	if len(out) == 0 {
		out = presets[:1]
	}
	return out
}

// openGiveawayCreator opens the creation box for a channel and kicks the
// options + balance loads.
func (a *App) openGiveawayCreator(c engine.ChatInfo) {
	st := &giveawayDlgState{
		accountID:   c.AccountID,
		chatID:      c.ChatID,
		peerTitle:   c.Title,
		dateIdx:     0,
		onlyNew:     true,
		showWinners: true,
	}
	a.mu.Lock()
	a.giveawayDlg = st
	a.mu.Unlock()
	a.invalidate()
	account, chat := c.AccountID, c.ChatID
	go func() {
		opts, oerr := a.eng.GetStarsGiveawayOptions(account)
		balance, berr := a.eng.GiftStarsBalance(account)
		max, _ := a.eng.GetGiveawayPeriodMax(account)
		countries, _ := a.eng.GetCountriesList(account, "en")
		a.mu.Lock()
		if a.giveawayDlg == nil || a.giveawayDlg.accountID != account || a.giveawayDlg.chatID != chat || a.giveawayDlg.prepaid != nil {
			a.mu.Unlock()
			return
		}
		if oerr != nil {
			a.giveawayDlg.err = oerr.Error()
		} else {
			a.giveawayDlg.options = opts
			a.giveawayDlg.selOpt = giveawayDefaultOption(opts)
			a.giveawayDlg.selWin = giveawayDefaultWinner(opts, a.giveawayDlg.selOpt)
		}
		if berr == nil {
			a.giveawayDlg.balance = balance
		}
		if len(countries) > 0 {
			a.giveawayDlg.countries = countries
		}
		if max > 0 {
			a.giveawayDlg.periodMax = max
		}
		a.giveawayDlg.loaded = true
		a.mu.Unlock()
		a.invalidate()
	}()
}

// giveawayDefaultOption (pure, testable): the server-flagged default, or
// the first non-extended row.
func giveawayDefaultOption(opts []cores.StarsGiveawayOptionInfo) int {
	for i, o := range opts {
		if o.Default {
			return i
		}
	}
	for i, o := range opts {
		if !o.Extended {
			return i
		}
	}
	return 0
}

// giveawayDefaultWinner (pure, testable): the split flagged default.
func giveawayDefaultWinner(opts []cores.StarsGiveawayOptionInfo, optIdx int) int {
	if optIdx < 0 || optIdx >= len(opts) {
		return 0
	}
	for i, w := range opts[optIdx].Winners {
		if w.Default {
			return i
		}
	}
	return 0
}

// sortedKeys (pure, testable): deterministic key ordering for map
// selections riding the wire (countries ISO codes, channel chat IDs).
func sortedKeys(m map[string]bool) []string {
	if len(m) == 0 {
		return nil
	}
	out := make([]string, 0, len(m))
	for k, ok := range m {
		if ok {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}

// countryLabel (pure, testable): the picker row label.
func countryLabel(c cores.CountryInfo) string {
	if c.Name != "" {
		return c.Name
	}
	return c.ISO2
}

// countryMatches (pure, testable): rows matching the query —
// case-insensitive substring on name or ISO code.
func countryMatches(list []cores.CountryInfo, query string) []cores.CountryInfo {
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" || list == nil {
		return list
	}
	var out []cores.CountryInfo
	for _, c := range list {
		if strings.Contains(strings.ToLower(c.Name), query) ||
			strings.Contains(strings.ToLower(c.ISO2), query) {
			out = append(out, c)
		}
	}
	return out
}

// giveawayCountryLabel (pure, testable): the Countries row label.
func giveawayCountryLabel(sel map[string]bool) string {
	if len(sel) == 0 {
		return "All countries"
	}
	noun := "countries"
	if len(sel) == 1 {
		noun = "country"
	}
	return strconv.Itoa(len(sel)) + " " + noun + " selected"
}

// giveawayChannelCandidates (pure, testable): same-account channels
// excluding the giveaway channel itself.
func giveawayChannelCandidates(chats []engine.ChatInfo, accountID, excludeChatID string) []engine.ChatInfo {
	var out []engine.ChatInfo
	for _, c := range chats {
		if c.AccountID != accountID || c.ChatID == excludeChatID {
			continue
		}
		if c.Type != engine.ChatTypeChanVal {
			continue
		}
		out = append(out, c)
	}
	return out
}

// giveawayChannelsLabel (pure, testable): the Channels row label.
func giveawayChannelsLabel(sel map[string]bool) string {
	if len(sel) == 0 {
		return "This channel only"
	}
	noun := "additional channels"
	if len(sel) == 1 {
		noun = "additional channel"
	}
	return strconv.Itoa(len(sel)) + " " + noun
}

// openPrepaidLaunch opens the box in prepaid-launch mode.
func (a *App) openPrepaidLaunch(c engine.ChatInfo, row prepaidGiveawayRow) {
	st := &giveawayDlgState{
		accountID:    c.AccountID,
		chatID:       c.ChatID,
		peerTitle:    c.Title,
		prepaid:      &row,
		dateIdx:      0,
		onlyNew:      true,
		showWinners:  true,
		loaded:       true,
		selCountries: map[string]bool{},
		selChats:     map[string]bool{},
	}
	a.mu.Lock()
	a.giveawayDlg = st
	a.mu.Unlock()
	a.invalidate()
	max, _ := a.eng.GetGiveawayPeriodMax(c.AccountID)
	a.mu.Lock()
	if a.giveawayDlg != nil && a.giveawayDlg.prepaid != nil && a.giveawayDlg.prepaid.ID == row.ID {
		if max > 0 {
			a.giveawayDlg.periodMax = max
		}
	}
	a.mu.Unlock()
	a.invalidate()
}

// closeGiveaway dismisses the box.
func (a *App) closeGiveaway() {
	a.mu.Lock()
	a.giveawayDlg = nil
	a.mu.Unlock()
	a.invalidate()
}

// sendGiveaway purchases (create mode) or launches (prepaid mode) the
// configured giveaway.
func (a *App) sendGiveaway(f frame) {
	st := f.giveawayDlg
	if st == nil {
		return
	}
	if st.launched {
		a.closeGiveaway()
		return
	}
	if st.sending {
		return
	}
	account, chat := st.accountID, st.chatID
	presets := giveawayDatePresetsFor(st.periodMax)
	if st.dateIdx < 0 || st.dateIdx >= len(presets) {
		return
	}
	p := cores.GiveawayParams{
		WinnerCount: 0,
		UntilDate:   int(giveawayUntilDate(presets[st.dateIdx].Days, time.Now())),
		OnlyNew:     st.onlyNew,
		ShowWinners: st.showWinners,
		Prize:       strings.TrimSpace(giveawayPrizeEd.Text()),
		Countries:   sortedKeys(st.selCountries),
		ExtraChats:  sortedKeys(st.selChats),
	}
	if len(p.Prize) > 128 {
		a.setToast("Additional prize is too long (max 128 characters)")
		return
	}

	if st.prepaid != nil {
		row := *st.prepaid
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.sending = true
		}
		a.mu.Unlock()
		a.invalidate()
		go func() {
			err := a.eng.LaunchPrepaidGiveaway(account, chat, row.ID, row.Credits, row.Months, p)
			a.mu.Lock()
			if a.giveawayDlg == nil || a.giveawayDlg.prepaid == nil || a.giveawayDlg.prepaid.ID != row.ID {
				a.mu.Unlock()
				return
			}
			a.giveawayDlg.sending = false
			if err != nil {
				a.giveawayDlg.err = err.Error()
				a.mu.Unlock()
				a.setToast("Giveaway launch failed: " + err.Error())
				return
			}
			a.giveawayDlg.launched = true
			a.giveawayDlg.err = ""
			a.mu.Unlock()
			a.setToast("Prepaid giveaway launched")
			a.invalidate()
		}()
		return
	}

	if st.selOpt < 0 || st.selOpt >= len(st.options) {
		return
	}
	winnerCount := 0
	if st.selWin >= 0 && st.selWin < len(st.options[st.selOpt].Winners) {
		winnerCount = st.options[st.selOpt].Winners[st.selWin].Users
	}
	if winnerCount <= 0 {
		return
	}
	p.WinnerCount = winnerCount
	opt := st.options[st.selOpt]

	a.mu.Lock()
	if a.giveawayDlg != nil {
		a.giveawayDlg.sending = true
	}
	a.mu.Unlock()
	a.invalidate()
	go func() {
		err := a.eng.CreateStarsGiveaway(account, chat, opt, p)
		a.mu.Lock()
		if a.giveawayDlg == nil || a.giveawayDlg.prepaid != nil {
			a.mu.Unlock()
			return
		}
		a.giveawayDlg.sending = false
		if err != nil {
			a.giveawayDlg.err = err.Error()
			a.mu.Unlock()
			a.setToast("Giveaway failed: " + err.Error())
			return
		}
		a.giveawayDlg.launched = true
		a.giveawayDlg.err = ""
		a.mu.Unlock()
		a.setToast("Giveaway started")
		a.invalidate()
	}()
}

// layoutGiveaway renders the box (content-pane surface).
func (a *App) layoutGiveaway(gtx layout.Context, f frame) layout.Dimensions {
	st := f.giveawayDlg
	if st == nil {
		return layout.Dimensions{}
	}
	if giveawayBackBtn.Clicked(gtx) {
		a.closeGiveaway()
	}
	if giveawaySendBtn.Clicked(gtx) {
		a.sendGiveaway(f)
	}
	if giveawayOnlyNewBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.onlyNew = !a.giveawayDlg.onlyNew
		}
		a.mu.Unlock()
		a.invalidate()
	}
	if giveawayShowWinBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.showWinners = !a.giveawayDlg.showWinners
		}
		a.mu.Unlock()
		a.invalidate()
	}
	if giveawayCountriesRow.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.pickCountries = !a.giveawayDlg.pickCountries
			a.giveawayDlg.pickChannels = false
		}
		a.mu.Unlock()
		a.invalidate()
	}
	if giveawayChannelsRow.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.pickChannels = !a.giveawayDlg.pickChannels
			a.giveawayDlg.pickCountries = false
		}
		a.mu.Unlock()
		a.invalidate()
	}
	if giveawayDoneBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.pickCountries = false
			a.giveawayDlg.pickChannels = false
		}
		a.mu.Unlock()
		a.invalidate()
	}
	for {
		ev, ok := giveawaySearchEd.Update(gtx)
		if !ok {
			break
		}
		if _, is := ev.(widget.ChangeEvent); is {
			a.mu.Lock()
			if a.giveawayDlg != nil {
				a.giveawayDlg.countryQuery = giveawaySearchEd.Text()
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}

	presets := giveawayDatePresetsFor(st.periodMax)
	if st.dateIdx >= len(presets) {
		st.dateIdx = len(presets) - 1
	}
	growClickables(&giveawayOptCells, len(st.options))
	for i := range st.options {
		if giveawayOptCells[i].Clicked(gtx) {
			a.mu.Lock()
			if a.giveawayDlg != nil && a.giveawayDlg.prepaid == nil {
				a.giveawayDlg.selOpt = i
				a.giveawayDlg.selWin = giveawayDefaultWinner(a.giveawayDlg.options, i)
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}
	var winners []cores.StarsGiveawayWinnerInfo
	if st.selOpt >= 0 && st.selOpt < len(st.options) {
		winners = st.options[st.selOpt].Winners
	}
	growClickables(&giveawayWinCells, len(winners))
	for i := range winners {
		if giveawayWinCells[i].Clicked(gtx) {
			a.mu.Lock()
			if a.giveawayDlg != nil && a.giveawayDlg.prepaid == nil {
				a.giveawayDlg.selWin = i
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}
	growClickables(&giveawayDateCells, len(presets))
	for i := range presets {
		if giveawayDateCells[i].Clicked(gtx) {
			a.mu.Lock()
			if a.giveawayDlg != nil {
				a.giveawayDlg.dateIdx = i
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}

	title := "Start a Stars giveaway"
	if st.prepaid != nil {
		title = "Launch prepaid giveaway"
	}
	sub := st.peerTitle
	if st.prepaid != nil {
		sub = prepaidRowTitle(*st.prepaid) + " \u00b7 " + prepaidRowSub(*st.prepaid)
	}

	var sections []layout.FlexChild

	// Balance + total (create mode only).
	if st.prepaid == nil {
		sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			total := giveawayTotalStars(st)
			line := "Your balance: " + formatStars(st.balance) + " Stars"
			if total > 0 {
				line += " \u00b7 Total: " + strconv.FormatInt(total, 10) + " Stars"
			}
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(12), line).Layout(gtx)
			})
		}))
	} else {
		sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(12), "Already paid \u2014 pick the end date and audience, then launch.").Layout(gtx)
			})
		}))
	}

	// Prize options (create mode).
	if st.prepaid == nil {
		sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if !st.loaded {
				return a.centerLoader(gtx)
			}
			if st.err != "" {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(13), "Giveaways unavailable: "+st.err).Layout(gtx)
					})
				})
			}
			if len(st.options) == 0 {
				return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(24), Bottom: unit.Dp(24)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return a.ui.Dim(unit.Sp(13), "No giveaway options available").Layout(gtx)
					})
				})
			}
			var rows []layout.FlexChild
			rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Prize")
					return lbl.Layout(gtx)
				})
			}))
			for i, o := range st.options {
				i, o := i, o
				rows = append(rows, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							bg := a.ui.p.Surface
							if i == st.selOpt {
								bg = a.ui.p.SurfaceHi
							}
							return roundedFill(gtx, bg, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), giveawayOptionLabel(o))
									if i == st.selOpt {
										lbl.Color = a.ui.p.Accent
									}
									return lbl.Layout(gtx)
								})
							})
						})
				}))
			}
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, rows...)
		}))

		// Winner split chips.
		sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if len(winners) == 0 {
				return layout.Dimensions{}
			}
			return layout.Inset{Top: unit.Dp(6), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := a.ui.Label(unit.Sp(13), "Winners")
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						var chips []layout.FlexChild
						for i, w := range winners {
							i, w := i, w
							chips = append(chips, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								btn := material.Button(a.ui.Theme, &giveawayWinCells[i], giveawayWinnerLabel(w))
								btn.CornerRadius = 8
								btn.TextSize = unit.Sp(12)
								if i == st.selWin {
									btn.Background = a.ui.p.Accent
								} else {
									btn.Background = a.ui.p.SurfaceHi
								}
								return btn.Layout(gtx)
							}))
							chips = append(chips, layout.Rigid(layout.Spacer{Width: unit.Dp(6)}.Layout))
						}
						return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, chips...)
					}),
				)
			})
		}))
	}

	// End-date presets.
	sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := a.ui.Label(unit.Sp(13), "Ends")
					return lbl.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					var chips []layout.FlexChild
					for i, p := range presets {
						i, p := i, p
						chips = append(chips, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := material.Button(a.ui.Theme, &giveawayDateCells[i], p.Label)
							btn.CornerRadius = 8
							btn.TextSize = unit.Sp(12)
							if i == st.dateIdx {
								btn.Background = a.ui.p.Accent
							} else {
								btn.Background = a.ui.p.SurfaceHi
							}
							return btn.Layout(gtx)
						}))
						chips = append(chips, layout.Rigid(layout.Spacer{Width: unit.Dp(6)}.Layout))
					}
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx, chips...)
				}),
			)
		})
	}))

	// Audience rows: countries + channels (slice 214 pickers).
	sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
								layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
									return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											lbl := a.ui.Label(unit.Sp(14), "Countries")
											return lbl.Layout(gtx)
										}),
										layout.Rigid(func(gtx layout.Context) layout.Dimensions {
											return a.ui.Dim(unit.Sp(12), giveawayCountryLabel(st.selCountries)).Layout(gtx)
										}),
									)
								}),
								layout.Rigid(func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Dim(unit.Sp(13), "Change")
									lbl.Color = a.ui.p.Accent
									return giveawayCountriesRow.Layout(gtx, lbl.Layout)
								}),
							)
						})
					})
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					cands := giveawayChannelCandidates(f.chats, st.accountID, st.chatID)
					if len(cands) == 0 {
						return layout.Dimensions{}
					}
					return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return roundedFill(gtx, a.ui.p.Surface, 10, func(gtx layout.Context) layout.Dimensions {
							return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
									layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
										return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
											layout.Rigid(func(gtx layout.Context) layout.Dimensions {
												lbl := a.ui.Label(unit.Sp(14), "Channels to join")
												return lbl.Layout(gtx)
											}),
											layout.Rigid(func(gtx layout.Context) layout.Dimensions {
												return a.ui.Dim(unit.Sp(12), giveawayChannelsLabel(st.selChats)).Layout(gtx)
											}),
										)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										lbl := a.ui.Dim(unit.Sp(13), "Change")
										lbl.Color = a.ui.p.Accent
										return giveawayChannelsRow.Layout(gtx, lbl.Layout)
									}),
								)
							})
						})
					})
				}),
			)
		})
	}))

	// Audience toggles + additional prize.
	sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		return layout.Inset{Top: unit.Dp(10), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							btn := material.Button(a.ui.Theme, &giveawayOnlyNewBtn, "Only new subscribers")
							btn.CornerRadius = 8
							btn.TextSize = unit.Sp(12)
							if st.onlyNew {
								btn.Background = a.ui.p.Accent
							} else {
								btn.Background = a.ui.p.SurfaceHi
							}
							return btn.Layout(gtx)
						}),
						layout.Rigid(layout.Spacer{Width: unit.Dp(6)}.Layout),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							btn := material.Button(a.ui.Theme, &giveawayShowWinBtn, "Show winners")
							btn.CornerRadius = 8
							btn.TextSize = unit.Sp(12)
							if st.showWinners {
								btn.Background = a.ui.p.Accent
							} else {
								btn.Background = a.ui.p.SurfaceHi
							}
							return btn.Layout(gtx)
						}),
					)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						ed := material.Editor(a.ui.Theme, &giveawayPrizeEd, "Additional prize (optional)")
						ed.TextSize = unit.Sp(14)
						return ed.Layout(gtx)
					})
				}),
			)
		})
	}))

	// Error line.
	sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if st.err == "" {
			return layout.Dimensions{}
		}
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return a.ui.Dim(unit.Sp(12), st.err).Layout(gtx)
		})
	}))

	// Done hint after a successful send/launch.
	sections = append(sections, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
		if !st.launched {
			return layout.Dimensions{}
		}
		return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return a.ui.Dim(unit.Sp(12), "Done \u2014 the giveaway message will appear in the channel.").Layout(gtx)
		})
	}))

	sendLabel := "Send giveaway"
	if st.prepaid != nil {
		sendLabel = "Launch giveaway"
	}
	if st.launched {
		sendLabel = "Close"
	}

	body := func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, sections...)
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(8), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Horizontal, Alignment: layout.Middle}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := a.ui.IconButton(&giveawayBackBtn, iconNavigationBack, "Back")
							btn.Color = a.ui.p.TextDim
							return btn.Layout(gtx)
						}),
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return layout.Inset{Left: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										return a.ui.H2(title).Layout(gtx)
									}),
									layout.Rigid(func(gtx layout.Context) layout.Dimensions {
										if sub == "" {
											return layout.Dimensions{}
										}
										return a.ui.Dim(unit.Sp(12), sub).Layout(gtx)
									}),
								)
							})
						}),
					)
				})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if st.pickCountries {
				return a.layoutGiveawayCountryPicker(gtx, f)
			}
			if st.pickChannels {
				return a.layoutGiveawayChannelPicker(gtx, f)
			}
			gl := material.List(a.ui.Theme, &giveawayList)
			return gl.Layout(gtx, 1, func(gtx layout.Context, _ int) layout.Dimensions {
				return body(gtx)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(a.ui.Theme, &giveawaySendBtn, sendLabel)
					if !giveawaySendEnabled(st) && !st.launched {
						btn.Background = a.ui.p.TextDim
					}
					return btn.Layout(gtx)
				})
		}),
	)
}

// layoutGiveawayCountryPicker: the audience country picker
// (tdesktop select_countries_box) — search + checkbox rows + Done.
func (a *App) layoutGiveawayCountryPicker(gtx layout.Context, f frame) layout.Dimensions {
	st := f.giveawayDlg
	if st == nil {
		return layout.Dimensions{}
	}
	rows := countryMatches(st.countries, st.countryQuery)
	growClickables(&giveawayCountryCells, len(rows))
	for i, c := range rows {
		if giveawayCountryCells[i].Clicked(gtx) {
			a.mu.Lock()
			if a.giveawayDlg != nil && a.giveawayDlg.selCountries != nil {
				if a.giveawayDlg.selCountries[c.ISO2] {
					delete(a.giveawayDlg.selCountries, c.ISO2)
				} else {
					a.giveawayDlg.selCountries[c.ISO2] = true
				}
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}
	if giveawayDoneBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.pickCountries = false
		}
		a.mu.Unlock()
		a.invalidate()
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				ed := a.ui.Editor(&giveawaySearchEd, "Search countries")
				return roundedFill(gtx, a.ui.p.SurfaceHi, 10, func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx, ed.Layout)
				})
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(12), giveawayCountryLabel(st.selCountries)+" · tap to toggle").Layout(gtx)
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if len(st.countries) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Dim(unit.Sp(13), "Country list unavailable").Layout(gtx)
				})
			}
			if len(rows) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Dim(unit.Sp(13), "No matching countries").Layout(gtx)
				})
			}
			var children []layout.FlexChild
			for i, c := range rows {
				i, c := i, c
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							bg := a.ui.p.Surface
							if st.selCountries[c.ISO2] {
								bg = a.ui.p.SurfaceHi
							}
							return roundedFill(gtx, bg, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), countryLabel(c))
									if st.selCountries[c.ISO2] {
										lbl.Color = a.ui.p.Accent
									}
									return giveawayCountryCells[i].Layout(gtx, lbl.Layout)
								})
							})
						})
				}))
			}
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(a.ui.Theme, &giveawayDoneBtn, "Done")
					btn.CornerRadius = 10
					return btn.Layout(gtx)
				})
		}),
	)
}

// layoutGiveawayChannelPicker: additional channels the winners must join
// — same-account channels excluding the giveaway channel itself.
func (a *App) layoutGiveawayChannelPicker(gtx layout.Context, f frame) layout.Dimensions {
	st := f.giveawayDlg
	if st == nil {
		return layout.Dimensions{}
	}
	rows := giveawayChannelCandidates(f.chats, st.accountID, st.chatID)
	growClickables(&giveawayChannelCells, len(rows))
	for i, c := range rows {
		if giveawayChannelCells[i].Clicked(gtx) {
			a.mu.Lock()
			if a.giveawayDlg != nil && a.giveawayDlg.selChats != nil {
				if a.giveawayDlg.selChats[c.ChatID] {
					delete(a.giveawayDlg.selChats, c.ChatID)
				} else {
					a.giveawayDlg.selChats[c.ChatID] = true
				}
			}
			a.mu.Unlock()
			a.invalidate()
		}
	}
	if giveawayDoneBtn.Clicked(gtx) {
		a.mu.Lock()
		if a.giveawayDlg != nil {
			a.giveawayDlg.pickChannels = false
		}
		a.mu.Unlock()
		a.invalidate()
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				return a.ui.Dim(unit.Sp(12), giveawayChannelsLabel(st.selChats)+" · tap to toggle").Layout(gtx)
			})
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if len(rows) == 0 {
				return centerLayout(gtx, func(gtx layout.Context) layout.Dimensions {
					return a.ui.Dim(unit.Sp(13), "No other channels in this account").Layout(gtx)
				})
			}
			var children []layout.FlexChild
			for i, c := range rows {
				i, c := i, c
				children = append(children, layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							bg := a.ui.p.Surface
							if st.selChats[c.ChatID] {
								bg = a.ui.p.SurfaceHi
							}
							return roundedFill(gtx, bg, 10, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(10)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
									lbl := a.ui.Label(unit.Sp(14), c.Title)
									if st.selChats[c.ChatID] {
										lbl.Color = a.ui.p.Accent
									}
									return giveawayChannelCells[i].Layout(gtx, lbl.Layout)
								})
							})
						})
				}))
			}
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx, children...)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions { return a.ui.Divider(gtx) }),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8), Bottom: unit.Dp(8), Left: unit.Dp(12), Right: unit.Dp(12)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(a.ui.Theme, &giveawayDoneBtn, "Done")
					btn.CornerRadius = 10
					return btn.Layout(gtx)
				})
		}),
	)
}
