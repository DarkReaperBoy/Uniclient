package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// Channel statistics (slice 184, parity row "Channel statistics
// screens"): statsGraphJSON extracts the inline JSON or the async token
// (the caller then loads it via stats.loadAsyncGraph); the broadcast
// stats mapping stays pure so the GUI gets a flat result.

func TestStatsGraphJSON(t *testing.T) {
	// Inline graph → JSON directly, no token.
	g := &tg.StatsGraph{JSON: tg.DataJSON{Data: `{"columns":[["x",1],["y",2]]}`}}
	json, token := statsGraphJSON(g)
	if json != `{"columns":[["x",1],["y",2]]}` || token != "" {
		t.Fatalf("inline graph = %q / %q", json, token)
	}
	// Async graph → token only, JSON empty.
	a := &tg.StatsGraphAsync{Token: "tok123"}
	json2, token2 := statsGraphJSON(a)
	if json2 != "" || token2 != "tok123" {
		t.Fatalf("async graph = %q / %q", json2, token2)
	}
	// Unknown constructor → nothing.
	json3, token3 := statsGraphJSON(nil)
	if json3 != "" || token3 != "" {
		t.Fatalf("nil graph = %q / %q", json3, token3)
	}
}

func TestBroadcastStatsToResult(t *testing.T) {
	st := &tg.StatsBroadcastStats{
		Period: tg.StatsDateRangeDays{MinDate: 1725148800, MaxDate: 1727654400},
		Followers: tg.StatsAbsValueAndPrev{
			Current:  4100,
			Previous: 3900,
		},
		ViewsPerPost:         tg.StatsAbsValueAndPrev{Current: 5300, Previous: 5100},
		SharesPerPost:        tg.StatsAbsValueAndPrev{Current: 120, Previous: 100},
		ReactionsPerPost:     tg.StatsAbsValueAndPrev{Current: 240, Previous: 200},
		ViewsPerStory:        tg.StatsAbsValueAndPrev{Current: 900, Previous: 800},
		SharesPerStory:       tg.StatsAbsValueAndPrev{Current: 30, Previous: 25},
		EnabledNotifications: tg.StatsPercentValue{Part: 810, Total: 4100},
		GrowthGraph: &tg.StatsGraph{
			JSON: tg.DataJSON{Data: `{"columns":[["x",1,2],["y",3,4]]}`},
		},
		FollowersGraph:    &tg.StatsGraphAsync{Token: "fg-tok"},
		MuteGraph:         &tg.StatsGraphAsync{Token: "mg-tok"},
		TopHoursGraph:     &tg.StatsGraph{JSON: tg.DataJSON{Data: `{"columns":[["x",5],["y",6]]}`}},
		InteractionsGraph: nil,
	}
	r := broadcastStatsToResult(st)
	if r == nil {
		t.Fatal("mapping returned nil")
	}
	if r.MinDate != 1725148800 || r.MaxDate != 1727654400 {
		t.Fatalf("period = %d..%d", r.MinDate, r.MaxDate)
	}
	if r.Followers.Current != 4100 || r.Followers.Previous != 3900 {
		t.Fatalf("followers = %+v", r.Followers)
	}
	if r.ViewsPerPost.Current != 5300 || r.SharesPerPost.Current != 120 || r.ReactionsPerPost.Current != 240 {
		t.Fatalf("per-post = %+v %+v %+v", r.ViewsPerPost, r.SharesPerPost, r.ReactionsPerPost)
	}
	if r.ViewsPerStory.Current != 900 || r.SharesPerStory.Current != 30 {
		t.Fatalf("per-story = %+v %+v", r.ViewsPerStory, r.SharesPerStory)
	}
	if r.NotifPercent != 810.0/4100.0*100 {
		t.Fatalf("notif percent = %v", r.NotifPercent)
	}
	if len(r.Graphs) != 4 {
		t.Fatalf("graphs = %d (inline Growth + TopHours, async tokens Followers + Mute)", len(r.Graphs))
	}
	byTitle := map[string]StatsGraphData{}
	for _, g := range r.Graphs {
		byTitle[g.Title] = g
	}
	if byTitle["Followers growth"].Token != "fg-tok" || byTitle["Followers growth"].JSON != "" {
		t.Fatalf("async followers graph = %+v", byTitle["Followers growth"])
	}
	if byTitle["Channel growth"].JSON == "" || byTitle["Channel growth"].Token != "" {
		t.Fatalf("inline growth graph = %+v", byTitle["Channel growth"])
	}
	if byTitle["Views by hour"].JSON == "" {
		t.Fatalf("top hours graph = %+v", byTitle["Views by hour"])
	}
	// nil graph (InteractionsGraph) → simply absent.
	if _, ok := byTitle["Interactions"]; ok {
		t.Fatal("nil graph must be absent")
	}
}

func TestStatsPercent(t *testing.T) {
	if got := statsPercent(tg.StatsPercentValue{Part: 810, Total: 4100}); got < 19.7 || got > 19.8 {
		t.Fatalf("percent = %v", got)
	}
	if got := statsPercent(tg.StatsPercentValue{Part: 0, Total: 0}); got != 0 {
		t.Fatalf("zero percent = %v", got)
	}
}
