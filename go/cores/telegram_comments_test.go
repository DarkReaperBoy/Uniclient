package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

// Channel-post comments (slice 195): the pure conversion helpers — the
// replies-info reader (comment count) and the reply-header thread-root
// reader (reply-to-top) — pinned against constructed wire objects.

func TestRepliesInfoOf(t *testing.T) {
	// No replies info → zero.
	m := &tg.Message{}
	if c, isComments := repliesInfoOf(m); c != 0 || isComments {
		t.Errorf("no replies: %d/%v, want 0/false", c, isComments)
	}
	// Plain group replies (not comments).
	m.SetReplies(tg.MessageReplies{Replies: 7})
	if c, isComments := repliesInfoOf(m); c != 7 || isComments {
		t.Errorf("group replies: %d/%v, want 7/false", c, isComments)
	}
	// Channel-post comments: Replies + Comments flag.
	m.SetReplies(tg.MessageReplies{Replies: 12, Comments: true})
	if c, isComments := repliesInfoOf(m); c != 12 || !isComments {
		t.Errorf("comments: %d/%v, want 12/true", c, isComments)
	}
	// Comments flag with zero replies → zero (honest: nothing to show).
	m.SetReplies(tg.MessageReplies{Comments: true})
	if c, _ := repliesInfoOf(m); c != 0 {
		t.Errorf("zero-reply comments: %d, want 0", c)
	}
}

func TestThreadRootOf(t *testing.T) {
	// No reply header.
	m := &tg.Message{}
	if r := threadRootOf(m); r != "" {
		t.Errorf("no header: %q, want empty", r)
	}
	// Reply without top: the reply target itself is the thread root.
	m.SetReplyTo(&tg.MessageReplyHeader{ReplyToMsgID: 55})
	if r := threadRootOf(m); r != "55" {
		t.Errorf("reply no-top: %q, want 55", r)
	}
	// Reply with top: the top wins.
	m.SetReplyTo(&tg.MessageReplyHeader{ReplyToMsgID: 77, ReplyToTopID: 55})
	if r := threadRootOf(m); r != "55" {
		t.Errorf("reply top: %q, want 55", r)
	}
}
