package cores

import (
	"fmt"

	"github.com/gotd/td/tg"
)

type StatsValue struct {
	Current  float64 `json:"current"`
	Previous float64 `json:"previous"`
}

type StatsGraphData struct {
	Title string `json:"title"`
	JSON  string `json:"json,omitempty"`
	Token string `json:"token,omitempty"`
}

type ChannelStats struct {
	MinDate int `json:"min_date"`
	MaxDate int `json:"max_date"`

	Followers        StatsValue `json:"followers"`
	ViewsPerPost     StatsValue `json:"views_per_post"`
	SharesPerPost    StatsValue `json:"shares_per_post"`
	ReactionsPerPost StatsValue `json:"reactions_per_post"`
	ViewsPerStory    StatsValue `json:"views_per_story"`
	SharesPerStory   StatsValue `json:"shares_per_story"`
	NotifPercent     float64    `json:"notif_percent"`

	Graphs []StatsGraphData `json:"graphs"`
}

func statsGraphJSON(g tg.StatsGraphClass) (json, token string) {
	switch v := g.(type) {
	case *tg.StatsGraph:
		return v.JSON.Data, ""
	case *tg.StatsGraphAsync:
		return "", v.Token
	}
	return "", ""
}

func statsPercent(p tg.StatsPercentValue) float64 {
	if p.Total == 0 {
		return 0
	}
	return p.Part / p.Total * 100
}

func broadcastStatsToResult(st *tg.StatsBroadcastStats) *ChannelStats {
	if st == nil {
		return nil
	}
	r := &ChannelStats{
		MinDate:          st.Period.MinDate,
		MaxDate:          st.Period.MaxDate,
		Followers:        StatsValue{Current: st.Followers.Current, Previous: st.Followers.Previous},
		ViewsPerPost:     StatsValue{Current: st.ViewsPerPost.Current, Previous: st.ViewsPerPost.Previous},
		SharesPerPost:    StatsValue{Current: st.SharesPerPost.Current, Previous: st.SharesPerPost.Previous},
		ReactionsPerPost: StatsValue{Current: st.ReactionsPerPost.Current, Previous: st.ReactionsPerPost.Previous},
		ViewsPerStory:    StatsValue{Current: st.ViewsPerStory.Current, Previous: st.ViewsPerStory.Previous},
		SharesPerStory:   StatsValue{Current: st.SharesPerStory.Current, Previous: st.SharesPerStory.Previous},
		NotifPercent:     statsPercent(st.EnabledNotifications),
	}
	add := func(title string, g tg.StatsGraphClass) {
		json, token := statsGraphJSON(g)
		if json == "" && token == "" {
			return
		}
		r.Graphs = append(r.Graphs, StatsGraphData{Title: title, JSON: json, Token: token})
	}
	add("Channel growth", st.GrowthGraph)
	add("Followers growth", st.FollowersGraph)
	add("Muted users", st.MuteGraph)
	add("Views by hour", st.TopHoursGraph)
	add("Interactions", st.InteractionsGraph)
	add("IV interactions", st.IvInteractionsGraph)
	add("Views by source", st.ViewsBySourceGraph)
	add("New followers by source", st.NewFollowersBySourceGraph)
	add("Story interactions", st.StoryInteractionsGraph)
	return r
}

func (t *TelegramCore) GetChannelStats(chatID string) (*ChannelStats, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, err
	}
	ch, ok := peer.(*tg.PeerChannel)
	if !ok {
		return nil, fmt.Errorf("statistics only work on channels")
	}
	hash, _ := t.resolveChannelAccessHash(ch.ChannelID)
	st, err := api.StatsGetBroadcastStats(ctx, &tg.StatsGetBroadcastStatsRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ChannelID, AccessHash: hash},
	})
	if err != nil {
		return nil, err
	}
	r := broadcastStatsToResult(st)
	if r == nil {
		return nil, fmt.Errorf("no stats data")
	}
	for i := range r.Graphs {
		g := &r.Graphs[i]
		if g.Token == "" {
			continue
		}
		rawGraph, err := api.StatsLoadAsyncGraph(ctx, &tg.StatsLoadAsyncGraphRequest{
			Token: g.Token,
		})
		if err != nil {
			g.Token = ""
			g.JSON = ""
			continue
		}
		if sg, ok := rawGraph.(*tg.StatsGraph); ok {
			g.JSON = sg.JSON.Data
			g.Token = ""
		} else {
			g.Token = ""
			g.JSON = ""
		}
	}
	out := r.Graphs[:0]
	for _, g := range r.Graphs {
		if g.JSON != "" {
			out = append(out, g)
		}
	}
	r.Graphs = out
	return r, nil
}
