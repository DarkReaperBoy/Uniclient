package cores

// Sponsored messages (Telegram, slice 163): the channel/bot ad surface.
//
// Wire contract (core.telegram.org/api/sponsored-messages, layer as of
// gotd v0.161): channels.getSponsoredMessages(peer) →
// messages.SponsoredMessages{ posts_between?, messages[], chats[], users[] }.
// Sponsored messages must be displayed below all other posts in channels
// (after the user scrolls past the last message) or as an action bar above
// bot chats; clicks/views/reports are reported back through
// messages.clickSponsoredMessage / .viewSponsoredMessage /
// .reportSponsoredMessage (report returns a choose-option chain via
// channels.sponsoredMessageReportResult). The result must be cached for
// 5 minutes (the engine does that part).
//
// RPC hygiene: every method here follows the withAPI snapshot rule (§8) —
// the RLock is never held across an RPC.

import (
	"encoding/hex"
	"fmt"

	"github.com/gotd/td/tg"
)

// SponsoredMessageInfo is one converted sponsored message, engine-facing.
type SponsoredMessageInfo struct {
	RandomID       string `json:"random_id"`
	URL            string `json:"url"`
	Title          string `json:"title"`
	Message        string `json:"message"`
	ButtonText     string `json:"button_text,omitempty"`
	SponsorInfo    string `json:"sponsor_info,omitempty"`
	AdditionalInfo string `json:"additional_info,omitempty"`
	// ThumbB64 is the custom profile photo bubble (stripped inline thumb,
	// base64 JPEG), like a group message sender avatar.
	ThumbB64 string `json:"thumb_b64,omitempty"`
	// MediaThumbB64 / MediaIsVideo describe the optional media attachment
	// (photo or video poster); honest scope: in-app video decode is blocked,
	// so video media renders as a poster with a play badge.
	MediaThumbB64 string       `json:"media_thumb_b64,omitempty"`
	MediaIsVideo  bool         `json:"media_is_video,omitempty"`
	Recommended   bool         `json:"recommended,omitempty"`
	CanReport     bool         `json:"can_report,omitempty"`
	AccentColorID int          `json:"accent_color_id,omitempty"`
	Entities      []TextEntity `json:"entities,omitempty"`
}

// SponsoredReportOption is one step in the iterative ad-report flow.
type SponsoredReportOption struct {
	Text   string `json:"text"`
	Option string `json:"option"` // hex; "" = request the option list
}

// GetSponsoredMessages fetches the sponsored messages for a channel or bot
// chat. Returns the converted list and posts_between (0 = show one block
// after the last message; >0 = additional blocks interleaved between
// posts, spaced that many messages apart).
func (t *TelegramCore) GetSponsoredMessages(chatID string) ([]SponsoredMessageInfo, int, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, 0, err
	}
	peer, err := t.resolvePeer(chatID)
	if err != nil {
		return nil, 0, fmt.Errorf("resolve chat: %w", err)
	}
	inputPeer, err := t.toInputPeer(peer)
	if err != nil {
		return nil, 0, fmt.Errorf("input peer: %w", err)
	}
	res, err := api.MessagesGetSponsoredMessages(ctx, &tg.MessagesGetSponsoredMessagesRequest{
		Peer: inputPeer,
	})
	if err != nil {
		return nil, 0, fmt.Errorf("get sponsored messages: %w", err)
	}
	var list []SponsoredMessageInfo
	var postsBetween int
	switch v := res.(type) {
	case *tg.MessagesSponsoredMessages:
		list, postsBetween = convertSponsoredMessages(v)
	case *tg.MessagesSponsoredMessagesEmpty:
		// No ads right now — the honest empty state.
	default:
		return nil, 0, fmt.Errorf("unexpected sponsored result %T", res)
	}
	return list, postsBetween, nil
}

// ViewSponsoredMessage reports that the ad's full text became visible
// (messages.viewSponsoredMessage). Fire-and-forget at the call sites.
func (t *TelegramCore) ViewSponsoredMessage(randomID string) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	raw, err := hex.DecodeString(randomID)
	if err != nil {
		return fmt.Errorf("random id: %w", err)
	}
	_, err = api.MessagesViewSponsoredMessage(ctx, raw)
	return err
}

// ClickSponsoredMessage reports a click on the sponsored message
// (messages.clickSponsoredMessage): media=true when the click was on the
// media block, fullscreen=true when a video ad was clicked in fullscreen.
func (t *TelegramCore) ClickSponsoredMessage(randomID string, media, fullscreen bool) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	raw, err := hex.DecodeString(randomID)
	if err != nil {
		return fmt.Errorf("random id: %w", err)
	}
	req := &tg.MessagesClickSponsoredMessageRequest{RandomID: raw}
	if media {
		req.SetMedia(true)
	}
	if fullscreen {
		req.SetFullscreen(true)
	}
	_, err = api.MessagesClickSponsoredMessage(ctx, req)
	return err
}

// ReportSponsoredMessage walks one step of the iterative report flow
// (messages.reportSponsoredMessage). An empty option requests the option
// list; a chosen option submits it. The result is the next choose-option
// chain (title + options) — empty title means the report is complete.
func (t *TelegramCore) ReportSponsoredMessage(randomID, option string) (string, []SponsoredReportOption, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return "", nil, err
	}
	raw, err := hex.DecodeString(randomID)
	if err != nil {
		return "", nil, fmt.Errorf("random id: %w", err)
	}
	var opt []byte
	if option != "" {
		if opt, err = hex.DecodeString(option); err != nil {
			return "", nil, fmt.Errorf("option: %w", err)
		}
	}
	res, err := api.MessagesReportSponsoredMessage(ctx, &tg.MessagesReportSponsoredMessageRequest{
		RandomID: raw,
		Option:   opt,
	})
	if err != nil {
		return "", nil, fmt.Errorf("report sponsored message: %w", err)
	}
	title, opts := parseSponsoredReportResult(res)
	return title, opts, nil
}

// ToggleSponsoredMessages turns account-wide sponsored messages off/on
// (account.toggleSponsoredMessages — the AyuGram "disable ads" lever; it
// is a setter, not a flip, so calls are idempotent).
func (t *TelegramCore) ToggleSponsoredMessages(enabled bool) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountToggleSponsoredMessages(ctx, enabled)
	return err
}

// ── pure conversion (unit-tested) ─────────────────────────────────────────

// convertSponsoredMessages maps the wire payload to engine-facing structs.
func convertSponsoredMessages(res *tg.MessagesSponsoredMessages) ([]SponsoredMessageInfo, int) {
	if res == nil {
		return nil, 0
	}
	postsBetween, _ := res.GetPostsBetween()
	if len(res.Messages) == 0 {
		return nil, postsBetween
	}
	list := make([]SponsoredMessageInfo, 0, len(res.Messages))
	for i := range res.Messages {
		m := &res.Messages[i]
		info := SponsoredMessageInfo{
			RandomID:      hex.EncodeToString(m.RandomID),
			URL:           m.URL,
			Title:         m.Title,
			Message:       m.Message,
			ButtonText:    m.ButtonText,
			Recommended:   m.Recommended,
			CanReport:     m.CanReport,
			AccentColorID: sponsoredAccentColorID(m.Color),
			Entities:      convertTgEntities(m.Entities),
		}
		if sponsorInfo, ok := m.GetSponsorInfo(); ok {
			info.SponsorInfo = sponsorInfo
		}
		if additionalInfo, ok := m.GetAdditionalInfo(); ok {
			info.AdditionalInfo = additionalInfo
		}
		if photo, ok := m.GetPhoto(); ok && photo != nil {
			if p, ok := photo.(*tg.Photo); ok {
				info.ThumbB64 = extractStrippedThumbB64(p.Sizes)
			}
		}
		info.MediaThumbB64, info.MediaIsVideo = sponsoredMediaInfo(m.Media)
		list = append(list, info)
	}
	return list, postsBetween
}

// sponsoredAccentColorID extracts the palette id from the optional
// PeerColor accent (0 = default).
func sponsoredAccentColorID(c tg.PeerColorClass) int {
	if c == nil {
		return 0
	}
	if pc, ok := c.(*tg.PeerColor); ok {
		return pc.Color
	}
	return 0
}

// sponsoredMediaInfo extracts the media poster thumb (photo or video
// document) and whether the media is a video.
func sponsoredMediaInfo(m tg.MessageMediaClass) (thumbB64 string, isVideo bool) {
	if m == nil {
		return "", false
	}
	switch v := m.(type) {
	case *tg.MessageMediaPhoto:
		if p, ok := v.Photo.(*tg.Photo); ok {
			return extractStrippedThumbB64(p.Sizes), false
		}
	case *tg.MessageMediaDocument:
		if d, ok := v.Document.(*tg.Document); ok {
			video := false
			for _, a := range d.Attributes {
				if _, ok := a.(*tg.DocumentAttributeVideo); ok {
					video = true
					break
				}
			}
			return extractStrippedThumbB64(d.Thumbs), video
		}
	}
	return "", false
}

// parseSponsoredReportResult unpacks the report step result: a
// choose-option chain (title + options) or a terminal state ("" title).
func parseSponsoredReportResult(res tg.ChannelsSponsoredMessageReportResultClass) (string, []SponsoredReportOption) {
	if res == nil {
		return "", nil
	}
	choose, ok := res.(*tg.ChannelsSponsoredMessageReportResultChooseOption)
	if !ok {
		// Reported / AdsHidden / Internal: the flow is done.
		return "", nil
	}
	opts := make([]SponsoredReportOption, 0, len(choose.Options))
	for _, o := range choose.Options {
		opts = append(opts, SponsoredReportOption{
			Text:   o.Text,
			Option: hex.EncodeToString(o.Option),
		})
	}
	return choose.Title, opts
}
