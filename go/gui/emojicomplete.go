package gui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"uniclient/engine"
)

// Inline emoji autocomplete (AyuGram parity, the ":shortcode" composer
// behavior): while the caret sits inside a ":token" (colon at a word start,
// at least one shortcode char after it), a strip of matching emoji appears
// above the composer; tapping one replaces the whole ":token" with the emoji.
// Matches come from the same Telegram keyword table the emoji panel's search
// uses (engine GetEmojiKeywords / MessagesGetEmojiKeywords), so this works
// on every backend that provides keywords and stays hidden elsewhere (§1.10:
// no panel without real data).

// emojiAcTokenChars: the shortcode charset Telegram keyword names use.
func emojiAcTokenChar(r rune) bool {
	switch {
	case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		return true
	case r == '_' || r == '-' || r == '+':
		return true
	}
	return false
}

// emojiAutocompleteQuery scans backward from the caret (rune offset) for a
// ":token". Returns the query (token text), the rune offset where the whole
// ":token" starts (what a tap must replace), and whether a token is active.
// A colon only counts when it starts a new token (the rune before it is
// not itself a token char), so URLs ("https://…") and glued words ("a:b",
// "3:30pm") never trigger — but an emoji inserted right before a fresh
// ":token" still does (the fast-typing chain pattern).
func emojiAutocompleteQuery(text string, caret int) (query string, start int, active bool) {
	r := []rune(text)
	if caret < 0 || caret > len(r) {
		return "", 0, false
	}
	i := caret
	for i > 0 && emojiAcTokenChar(r[i-1]) {
		i--
	}
	if i == 0 || r[i-1] != ':' {
		return "", 0, false
	}
	tok := r[i:caret]
	if len(tok) == 0 || len(tok) > 24 {
		return "", 0, false
	}
	if i-1 > 0 && emojiAcTokenChar(r[i-2]) {
		return "", 0, false // colon glued to a word/time/URL — not a shortcode
	}
	return string(tok), i - 1, true
}

// emojiAutocompleteMatches ranks keyword matches for a token: keywords equal
// to the query first, then prefix matches; every keyword contributes its
// emoticons (deduped), capped. Pure — tested against the engine table shape.
func emojiAutocompleteMatches(kws []engine.EmojiKeywordEntry, q string, cap int) []string {
	q = strings.ToLower(strings.TrimSpace(q))
	if q == "" || len(kws) == 0 || cap <= 0 {
		return nil
	}
	type ranked struct {
		exact bool
		kw    engine.EmojiKeywordEntry
	}
	var exacts, prefixes []ranked
	for _, kw := range kws {
		k := strings.ToLower(kw.Keyword)
		if k == q {
			exacts = append(exacts, ranked{true, kw})
		} else if strings.HasPrefix(k, q) {
			prefixes = append(prefixes, ranked{false, kw})
		}
	}
	seen := make(map[string]struct{}, 32)
	out := make([]string, 0, 16)
	for _, group := range [][]ranked{exacts, prefixes} {
		for _, rk := range group {
			for _, e := range rk.kw.Emoticons {
				if e == "" {
					continue
				}
				if _, dup := seen[e]; dup {
					continue
				}
				seen[e] = struct{}{}
				out = append(out, e)
				if len(out) >= cap {
					return out
				}
			}
		}
	}
	return out
}

// emojiAutocompleteVisible: the strip shows only with a live token and no
// competing composer panels (emoji picker / attach menu own that space).
func emojiAutocompleteVisible(emojiOpen, attachOpen bool) bool {
	return !emojiOpen && !attachOpen
}

// ── state + panel ─────────────────────────────────────────────────────────

var emojiAcBtns []widget.Clickable

// applyEmojiAutocomplete replaces ":token" [start,caret) in the composer with
// the chosen emoji (the Editor's Insert replaces the active selection).
func (a *App) applyEmojiAutocomplete(start, caret int, emoji string) {
	composer.SetCaret(start, caret)
	composer.Insert(emoji)
	a.invalidate()
}

// layoutEmojiAutocomplete renders the suggestion strip above the composer.
// Derived per-frame from the composer state — no panel state to invalidate:
// the strip appears while a token is active and vanishes the moment it is not.
func (a *App) layoutEmojiAutocomplete(gtx layout.Context, f frame) layout.Dimensions {
	if !emojiAutocompleteVisible(f.emojiOpen, f.attachMenuOpen) {
		return layout.Dimensions{}
	}
	start, end := composer.Selection()
	if start != end {
		return layout.Dimensions{} // active text selection: don't fight it
	}
	query, _, active := emojiAutocompleteQuery(composer.Text(), end)
	if !active {
		return layout.Dimensions{}
	}
	acc := ""
	if f.selected != nil {
		acc = f.selected.AccountID
	} else if len(f.accounts) > 0 {
		acc = f.accounts[0].ID
	}
	a.ensureEmojiKeywords(acc)
	sugg := emojiAutocompleteMatches(a.emojiKeywords(), query, 32)
	if len(sugg) == 0 {
		return layout.Dimensions{}
	}

	growClickables(&emojiAcBtns, len(sugg))
	for i := range sugg {
		if emojiAcBtns[i].Clicked(gtx) {
			// Replace the whole ":token" — the caret may have moved since
			// the query was computed, so re-derive the replacement range.
			s, e := composer.Selection()
			if s != e {
				return layout.Dimensions{}
			}
			_, rs, ok := emojiAutocompleteQuery(composer.Text(), e)
			if !ok {
				return layout.Dimensions{}
			}
			a.applyEmojiAutocomplete(rs, e, sugg[i])
			return layout.Dimensions{}
		}
	}

	// Horizontal strip anchored above the composer (same chrome family as
	// the bot-commands panel), scrollable when long.
	return layout.Inset{Left: unit.Dp(12), Right: unit.Dp(12), Bottom: unit.Dp(6)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return roundedFill(gtx, a.ui.p.Surface, 12, func(gtx layout.Context) layout.Dimensions {
			return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
				list := material.List(a.ui.Theme, &emojiAcList)
				return list.Layout(gtx, len(sugg), func(gtx layout.Context, i int) layout.Dimensions {
					return material.ButtonLayout(a.ui.Theme, &emojiAcBtns[i]).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.UniformInset(unit.Dp(6)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
							lbl := a.ui.Label(unit.Sp(22), sugg[i])
							return lbl.Layout(gtx)
						})
					})
				})
			})
		})
	})
}

var emojiAcList widget.List

func init() {
	emojiAcList.Axis = layout.Horizontal
}
