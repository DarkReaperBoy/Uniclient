package engine

// giveaways_test.go — slice 212 tests: the giveaway surface passthroughs
// (options fetch, balance-funded creation, prepaid launch) and their
// honest gates on plain cores.

import (
	"testing"

	"uniclient/cores"
)

type giveawayStub struct {
	cores.StubCore
	options   []cores.StarsGiveawayOptionInfo
	optCalls  int
	created   []string // chatIDs passed to CreateStarsGiveaway
	createErr error
	launched  []int64 // giveawayIDs passed to LaunchPrepaidGiveaway
	launchErr error
}

func (s *giveawayStub) GetStarsGiveawayOptions() ([]cores.StarsGiveawayOptionInfo, error) {
	s.optCalls++
	return s.options, nil
}

func (s *giveawayStub) CreateStarsGiveaway(chatID string, opt cores.StarsGiveawayOptionInfo, p cores.GiveawayParams) error {
	if s.createErr != nil {
		return s.createErr
	}
	s.created = append(s.created, chatID)
	return nil
}

func (s *giveawayStub) LaunchPrepaidGiveaway(chatID string, giveawayID int64, credits int64, months int, p cores.GiveawayParams) error {
	if s.launchErr != nil {
		return s.launchErr
	}
	s.launched = append(s.launched, giveawayID)
	return nil
}

func newGiveawayEngine(t *testing.T, core cores.Core) *Engine {
	t.Helper()
	e := newTestEngine(t)
	if _, err := e.db.Exec(
		`INSERT OR IGNORE INTO accounts (id, platform, display_name, sort_order, created_at)
                 VALUES ('tg', 'telegram', 'Test', 0, 0)`); err != nil {
		t.Fatal(err)
	}
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: core}}
	return e
}

func TestGiveawayOptionsPassthrough(t *testing.T) {
	st := &giveawayStub{options: []cores.StarsGiveawayOptionInfo{
		{Stars: 500, Winners: []cores.StarsGiveawayWinnerInfo{{Users: 10, PerUserStars: 50, Default: true}}},
	}}
	e := newGiveawayEngine(t, st)

	opts, err := e.GetStarsGiveawayOptions("tg")
	if err != nil {
		t.Fatal(err)
	}
	if len(opts) != 1 || opts[0].Stars != 500 || len(opts[0].Winners) != 1 {
		t.Fatalf("options = %+v", opts)
	}
	if st.optCalls != 1 {
		t.Fatalf("fetch calls = %d", st.optCalls)
	}

	// Plain stubs lack the surface → honest error, not a silent nil.
	e2 := newGiveawayEngine(t, &plainStub{})
	if _, err := e2.GetStarsGiveawayOptions("tg"); err == nil {
		t.Error("plain stub must not expose giveaway options")
	}
}

func TestCreateStarsGiveaway(t *testing.T) {
	st := &giveawayStub{}
	e := newGiveawayEngine(t, st)
	opt := cores.StarsGiveawayOptionInfo{Stars: 500, Winners: []cores.StarsGiveawayWinnerInfo{{Users: 10, PerUserStars: 50}}}

	if err := e.CreateStarsGiveaway("tg", "-1001234", opt, cores.GiveawayParams{WinnerCount: 10}); err != nil {
		t.Fatal(err)
	}
	if len(st.created) != 1 || st.created[0] != "-1001234" {
		t.Fatalf("created = %v", st.created)
	}

	// Unknown account → honest error.
	if err := e.CreateStarsGiveaway("ghost", "c", opt, cores.GiveawayParams{}); err == nil {
		t.Error("unknown account must error")
	}

	// Plain core → honest unsupported error.
	e2 := newGiveawayEngine(t, &plainStub{})
	if err := e2.CreateStarsGiveaway("tg", "c", opt, cores.GiveawayParams{}); err == nil {
		t.Error("plain stub must not create giveaways")
	}
}

func TestLaunchPrepaidGiveaway(t *testing.T) {
	st := &giveawayStub{}
	e := newGiveawayEngine(t, st)

	if err := e.LaunchPrepaidGiveaway("tg", "-1001234", 77, 500, 0, cores.GiveawayParams{WinnerCount: 10}); err != nil {
		t.Fatal(err)
	}
	if len(st.launched) != 1 || st.launched[0] != 77 {
		t.Fatalf("launched = %v", st.launched)
	}

	// Plain core → honest unsupported error.
	e2 := newGiveawayEngine(t, &plainStub{})
	if err := e2.LaunchPrepaidGiveaway("tg", "c", 1, 0, 3, cores.GiveawayParams{}); err == nil {
		t.Error("plain stub must not launch giveaways")
	}
}
