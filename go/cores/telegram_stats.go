package cores

import (
        "fmt"

        "github.com/gotd/td/tg"
)

// Channel statistics (slice 184, parity row "Channel statistics
// screens" — tdesktop's channel Statistics page): stats.getBroadcastStats
// over the channel + stats.loadAsyncGraph for token graphs; the result
// is a flat struct the GUI renders (overview cards + line charts).

// StatsValue is one current-vs-previous counter.
type StatsValue struct {
        Current  float64 `json:"current"`
        Previous float64 `json:"previous"`
}

// StatsGraphData is one graph: inline JSON when already loaded, or the
// async token the engine resolves via stats.loadAsyncGraph.
type StatsGraphData struct {
        Title string `json:"title"`
        JSON  string `json:"json,omitempty"`
        Token string `json:"token,omitempty"`
}

// ChannelStats is the flattened stats.getBroadcastStats result.
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

// statsGraphJSON extracts the inline JSON or the async token from one
// graph constructor. Pure — unit-tested.
func statsGraphJSON(g tg.StatsGraphClass) (json, token string) {
        switch v := g.(type) {
        case *tg.StatsGraph:
                return v.JSON.Data, ""
        case *tg.StatsGraphAsync:
                return "", v.Token
        }
        return "", ""
}

// statsPercent: part/total as a percentage (0 when total is 0).
func statsPercent(p tg.StatsPercentValue) float64 {
        if p.Total == 0 {
                return 0
        }
        return p.Part / p.Total * 100
}

// broadcastStatsToResult flattens the broadcast stats (graphs in
// tdesktop's page order; nil graphs drop). Pure — unit-tested.
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

// GetChannelStats fetches the channel's broadcast statistics, resolving
// async graph tokens through stats.loadAsyncGraph so every returned
// graph carries inline JSON.
func (t *TelegramCore) GetChannelStats(chatID string) (*ChannelStats, error) {
        // withAPI rule: never hold t.mu across the RPC.
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
        // Resolve async tokens (stats.loadAsyncGraph) so the GUI only ever
        // sees inline JSON.
        for i := range r.Graphs {
                g := &r.Graphs[i]
                if g.Token == "" {
                        continue
                }
                rawGraph, err := api.StatsLoadAsyncGraph(ctx, &tg.StatsLoadAsyncGraphRequest{
                        Token: g.Token,
                })
                if err != nil {
                        g.Token = "" // unavailable graph drops (honest empty)
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
        // Drop graphs that ended up empty.
        out := r.Graphs[:0]
        for _, g := range r.Graphs {
                if g.JSON != "" {
                        out = append(out, g)
                }
        }
        r.Graphs = out
        return r, nil
}
