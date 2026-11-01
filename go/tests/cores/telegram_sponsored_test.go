package tests

import (
	"testing"
	. "uniclient/cores"

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
	list, postsBetween := ConvertSponsoredMessages(res)
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
		Flags:        bin.Fields(1 << 0),
		PostsBetween: 20,
		Messages: []tg.SponsoredMessage{
			{RandomID: []byte{1}, URL: "https://a", Title: "A", Message: "a", ButtonText: "b"},
			{RandomID: []byte{2}, URL: "https://b", Title: "B", Message: "b", ButtonText: "b"},
		},
	}
	_, postsBetween := ConvertSponsoredMessages(res)
	if postsBetween != 20 {
		t.Errorf("postsBetween = %d, want 20", postsBetween)
	}
}

func TestConvertSponsoredMessagesEmpty(t *testing.T) {
	list, postsBetween := ConvertSponsoredMessages(nil)
	if list != nil || postsBetween != 0 {
		t.Errorf("nil input converted to %v/%d, want nil/0", list, postsBetween)
	}
}

func TestSponsoredAccentColorID(t *testing.T) {
	if got := SponsoredAccentColorID(nil); got != 0 {
		t.Errorf("nil color = %d, want 0", got)
	}
	if got := SponsoredAccentColorID(&tg.PeerColor{Color: 3}); got != 3 {
		t.Errorf("peerColor = %d, want 3", got)
	}
	if got := SponsoredAccentColorID(&tg.PeerColor{}); got != 0 {
		t.Errorf("zero color = %d, want 0", got)
	}
}

func TestSponsoredMediaInfo(t *testing.T) {
	thumb, isVideo := SponsoredMediaInfo(nil)
	if thumb != "" || isVideo {
		t.Errorf("nil media = %q/%v, want empty/false", thumb, isVideo)
	}
	thumb, isVideo = SponsoredMediaInfo(&tg.MessageMediaPhoto{Photo: strippedPhoto()})
	if thumb == "" || isVideo {
		t.Errorf("photo media = %q/%v, want thumb/false", thumb, isVideo)
	}
	thumb, isVideo = SponsoredMediaInfo(&tg.MessageMediaDocument{
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
	title, opts := ParseSponsoredReportResult(nil)
	if title != "" || len(opts) != 0 {
		t.Errorf("nil result = %q/%d, want done", title, len(opts))
	}
	title, opts = ParseSponsoredReportResult(&tg.ChannelsSponsoredMessageReportResultReported{})
	if title != "" || len(opts) != 0 {
		t.Errorf("non-choose result = %q/%d, want done", title, len(opts))
	}
	title, opts = ParseSponsoredReportResult(&tg.ChannelsSponsoredMessageReportResultChooseOption{
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
	if got := StoryReactionEmoticon(&tg.ReactionEmoji{Emoticon: "🔥"}); got != "🔥" {
		t.Errorf("emoji reaction = %q, want 🔥", got)
	}
	if got := StoryReactionEmoticon(&tg.ReactionCustomEmoji{DocumentID: 5}); got != "" {
		t.Errorf("custom emoji reaction must map to empty (not representable), got %q", got)
	}
	if got := StoryReactionEmoticon(nil); got != "" {
		t.Errorf("nil reaction = %q, want empty", got)
	}
}
