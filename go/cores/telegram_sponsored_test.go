package cores

// Sponsored messages (Telegram channels + bots, slice 163): conversion of
// the wire messages.SponsoredMessages payload into the engine-facing
// SponsoredMessageInfo list, plus the report-result parser. The RPCs
// themselves (get/view/click/report) ride the withAPI pattern and are
// covered by live verification.

import (
	"testing"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
)

func strippedPhoto() *tg.Photo {
	return &tg.Photo{
		ID: 5,
		Sizes: []tg.PhotoSizeClass{
			&tg.PhotoStrippedSize{Type: "i", Bytes: []byte{1, 0xFF, 0xD8, 0x11}},
		},
	}
}

func TestConvertSponsoredMessages(t *testing.T) {
	first := tg.SponsoredMessage{
		RandomID:    []byte{0xAA, 0xBB},
		URL:         "https://t.me/sponsor",
		Title:       "Sponsor Channel",
		Message:     "Check this out bold claim",
		ButtonText:  "View channel",
		Recommended: true,
		CanReport:   true,
		Entities: []tg.MessageEntityClass{
			&tg.MessageEntityBold{Offset: 16, Length: 4},
		},
	}
	// Flag-gated optionals go through the generated setters (they set the
	// conditional-field bits the way real wire data does).
	first.SetSponsorInfo("sponsor@example")
	first.SetPhoto(strippedPhoto())
	res := &tg.MessagesSponsoredMessages{
		Messages: []tg.SponsoredMessage{
			first,
			{
				RandomID:   []byte{0x01},
				URL:        "https://example.com/ad",
				Title:      "Plain Ad",
				Message:    "text only",
				ButtonText: "Learn more",
			},
		},
	}
	list, postsBetween := convertSponsoredMessages(res)
	if postsBetween != 0 {
		t.Errorf("postsBetween = %d, want 0", postsBetween)
	}
	if len(list) != 2 {
		t.Fatalf("converted %d, want 2", len(list))
	}
	conv := list[0]
	if conv.RandomID != "aabb" {
		t.Errorf("RandomID = %q, want aabb", conv.RandomID)
	}
	if conv.URL != "https://t.me/sponsor" || conv.Title != "Sponsor Channel" {
		t.Errorf("url/title = %q/%q", conv.URL, conv.Title)
	}
	if !conv.Recommended || !conv.CanReport {
		t.Errorf("recommended/canReport = %v/%v, want true/true", conv.Recommended, conv.CanReport)
	}
	if conv.ButtonText != "View channel" || conv.SponsorInfo != "sponsor@example" {
		t.Errorf("buttonText/sponsorInfo = %q/%q", conv.ButtonText, conv.SponsorInfo)
	}
	if len(conv.Entities) != 1 || conv.Entities[0].Type != "bold" || conv.Entities[0].Offset != 16 {
		t.Errorf("entities = %+v", conv.Entities)
	}
	if conv.ThumbB64 == "" {
		t.Error("custom photo stripped thumb not extracted")
	}
	second := list[1]
	if second.Recommended || second.CanReport {
		t.Errorf("second flags set unexpectedly")
	}
	if second.ThumbB64 != "" {
		t.Error("no photo but thumb extracted")
	}
}

func TestConvertSponsoredMessagesPostsBetween(t *testing.T) {
	res := &tg.MessagesSponsoredMessages{
		Flags:        bin.Fields(1 << 0), // posts_between bit
		PostsBetween: 20,
		Messages: []tg.SponsoredMessage{
			{RandomID: []byte{1}, URL: "https://a", Title: "A", Message: "a", ButtonText: "b"},
			{RandomID: []byte{2}, URL: "https://b", Title: "B", Message: "b", ButtonText: "b"},
		},
	}
	_, postsBetween := convertSponsoredMessages(res)
	if postsBetween != 20 {
		t.Errorf("postsBetween = %d, want 20", postsBetween)
	}
}

func TestConvertSponsoredMessagesEmpty(t *testing.T) {
	list, postsBetween := convertSponsoredMessages(nil)
	if list != nil || postsBetween != 0 {
		t.Errorf("nil input converted to %v/%d, want nil/0", list, postsBetween)
	}
}

func TestSponsoredAccentColorID(t *testing.T) {
	if got := sponsoredAccentColorID(nil); got != 0 {
		t.Errorf("nil color = %d, want 0", got)
	}
	if got := sponsoredAccentColorID(&tg.PeerColor{Color: 3}); got != 3 {
		t.Errorf("peerColor = %d, want 3", got)
	}
	if got := sponsoredAccentColorID(&tg.PeerColor{}); got != 0 {
		t.Errorf("zero color = %d, want 0", got)
	}
}

func TestSponsoredMediaInfo(t *testing.T) {
	// No media.
	thumb, isVideo := sponsoredMediaInfo(nil)
	if thumb != "" || isVideo {
		t.Errorf("nil media = %q/%v, want empty/false", thumb, isVideo)
	}
	// Photo media: stripped thumb, not video.
	thumb, isVideo = sponsoredMediaInfo(&tg.MessageMediaPhoto{Photo: strippedPhoto()})
	if thumb == "" || isVideo {
		t.Errorf("photo media = %q/%v, want thumb/false", thumb, isVideo)
	}
	// Video media: video flag set; photo-based documents without video attr stay photo.
	thumb, isVideo = sponsoredMediaInfo(&tg.MessageMediaDocument{
		Document: &tg.Document{
			MimeType: "video/mp4",
			Attributes: []tg.DocumentAttributeClass{
				&tg.DocumentAttributeVideo{},
			},
			Thumbs: []tg.PhotoSizeClass{
				&tg.PhotoStrippedSize{Type: "j", Bytes: []byte{1, 0xFF, 0xD8, 0x11}},
			},
		},
	})
	if thumb == "" || !isVideo {
		t.Errorf("video media = %q/%v, want thumb/true", thumb, isVideo)
	}
}

func TestParseReportResult(t *testing.T) {
	// nil / non-choose results report "done".
	title, opts := parseSponsoredReportResult(nil)
	if title != "" || len(opts) != 0 {
		t.Errorf("nil result = %q/%d, want done", title, len(opts))
	}
	title, opts = parseSponsoredReportResult(&tg.ChannelsSponsoredMessageReportResultReported{})
	if title != "" || len(opts) != 0 {
		t.Errorf("non-choose result = %q/%d, want done", title, len(opts))
	}
	// Choose-option chain.
	title, opts = parseSponsoredReportResult(&tg.ChannelsSponsoredMessageReportResultChooseOption{
		Title: "Report ad",
		Options: []tg.SponsoredMessageReportOption{
			{Text: "Spam", Option: []byte{0x01}},
			{Text: "Misleading", Option: []byte{0x02}},
		},
	})
	if title != "Report ad" || len(opts) != 2 {
		t.Fatalf("choose result = %q/%d", title, len(opts))
	}
	if opts[0].Text != "Spam" || opts[0].Option != "01" {
		t.Errorf("option[0] = %+v", opts[0])
	}
	if opts[1].Text != "Misleading" || opts[1].Option != "02" {
		t.Errorf("option[1] = %+v", opts[1])
	}
}

func TestStoryReactionEmoticon(t *testing.T) {
	if got := storyReactionEmoticon(&tg.ReactionEmoji{Emoticon: "🔥"}); got != "🔥" {
		t.Errorf("emoji reaction = %q, want 🔥", got)
	}
	if got := storyReactionEmoticon(&tg.ReactionCustomEmoji{DocumentID: 5}); got != "" {
		t.Errorf("custom emoji reaction must map to empty (not representable), got %q", got)
	}
	if got := storyReactionEmoticon(nil); got != "" {
		t.Errorf("nil reaction = %q, want empty", got)
	}
}
