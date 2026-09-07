package engine

import (
	"testing"

	"uniclient/cores"
)

// toggleReaction mirrors the optimistic own-reaction toggle used by
// ReactToMessage's post-success cache update. Lock the contract: add,
// increment, remove, drop-at-zero, and preserve unknown entries.
func TestToggleReaction(t *testing.T) {
	t.Run("add first reaction", func(t *testing.T) {
		got := toggleReaction(nil, "👍")
		if len(got) != 1 || got[0].Emoji != "👍" || got[0].Count != 1 || !got[0].ByMe {
			t.Fatalf("add first = %+v", got)
		}
	})

	t.Run("add to existing other-reaction", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "❤️", Count: 2}}
		got := toggleReaction(base, "❤️")
		if len(got) != 1 || got[0].Count != 3 || !got[0].ByMe {
			t.Fatalf("join existing = %+v", got)
		}
	})

	t.Run("remove own reaction drops at zero", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "🔥", Count: 1, ByMe: true}, {Emoji: "❤️", Count: 5}}
		got := toggleReaction(base, "🔥")
		if len(got) != 1 || got[0].Emoji != "❤️" || got[0].Count != 5 {
			t.Fatalf("drop at zero = %+v", got)
		}
	})

	t.Run("remove own keeps others count", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "🔥", Count: 4, ByMe: true}}
		got := toggleReaction(base, "🔥")
		if len(got) != 1 || got[0].Count != 3 || got[0].ByMe {
			t.Fatalf("decrement = %+v", got)
		}
	})

	t.Run("other entries untouched", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "🔥", Count: 4, ByMe: true}, {Emoji: "👏", Count: 7}}
		got := toggleReaction(base, "❤️")
		if len(got) != 3 {
			t.Fatalf("append new emoji = %+v", got)
		}
		if got[0].Emoji != "🔥" || got[1].Emoji != "👏" || got[2].Count != 1 || !got[2].ByMe {
			t.Fatalf("append new emoji details = %+v", got)
		}
	})
}
