package cores

import (
	"encoding/hex"
	"fmt"

	"github.com/gotd/td/tg"
)

type SponsoredMessageInfo struct {
	RandomID       string       `json:"random_id"`
	URL            string       `json:"url"`
	Title          string       `json:"title"`
	Message        string       `json:"message"`
	ButtonText     string       `json:"button_text,omitempty"`
	SponsorInfo    string       `json:"sponsor_info,omitempty"`
	AdditionalInfo string       `json:"additional_info,omitempty"`
	ThumbB64       string       `json:"thumb_b64,omitempty"`
	MediaThumbB64  string       `json:"media_thumb_b64,omitempty"`
	MediaIsVideo   bool         `json:"media_is_video,omitempty"`
	Recommended    bool         `json:"recommended,omitempty"`
	CanReport      bool         `json:"can_report,omitempty"`
	AccentColorID  int          `json:"accent_color_id,omitempty"`
	Entities       []TextEntity `json:"entities,omitempty"`
}

type SponsoredReportOption struct {
	Text   string `json:"text"`
	Option string `json:"option"`
}

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
	default:
		return nil, 0, fmt.Errorf("unexpected sponsored result %T", res)
	}
	return list, postsBetween, nil
}

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

func (t *TelegramCore) ToggleSponsoredMessages(enabled bool) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountToggleSponsoredMessages(ctx, enabled)
	return err
}

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

func sponsoredAccentColorID(c tg.PeerColorClass) int {
	if c == nil {
		return 0
	}
	if pc, ok := c.(*tg.PeerColor); ok {
		return pc.Color
	}
	return 0
}

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

func parseSponsoredReportResult(res tg.ChannelsSponsoredMessageReportResultClass) (string, []SponsoredReportOption) {
	if res == nil {
		return "", nil
	}
	choose, ok := res.(*tg.ChannelsSponsoredMessageReportResultChooseOption)
	if !ok {
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
