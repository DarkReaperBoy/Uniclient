package tests

import (
	"testing"
	. "uniclient/engine"

	"uniclient/cores"
)

func TestToggleReaction(t *testing.T) {
	t.Run("add first reaction", func(t *testing.T) {
		got := ToggleReaction(nil, "👍")
		if len(got) != 1 || got[0].Emoji != "👍" || got[0].Count != 1 || !got[0].ByMe {
			t.Fatalf("add first = %+v", got)
		}
	})

	t.Run("add to existing other-reaction", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "❤️", Count: 2}}
		got := ToggleReaction(base, "❤️")
		if len(got) != 1 || got[0].Count != 3 || !got[0].ByMe {
			t.Fatalf("join existing = %+v", got)
		}
	})

	t.Run("remove own reaction drops at zero", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "🔥", Count: 1, ByMe: true}, {Emoji: "❤️", Count: 5}}
		got := ToggleReaction(base, "🔥")
		if len(got) != 1 || got[0].Emoji != "❤️" || got[0].Count != 5 {
			t.Fatalf("drop at zero = %+v", got)
		}
	})

	t.Run("remove own keeps others count", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "🔥", Count: 4, ByMe: true}}
		got := ToggleReaction(base, "🔥")
		if len(got) != 1 || got[0].Count != 3 || got[0].ByMe {
			t.Fatalf("decrement = %+v", got)
		}
	})

	t.Run("other entries untouched", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "🔥", Count: 4, ByMe: true}, {Emoji: "👏", Count: 7}}
		got := ToggleReaction(base, "❤️")
		if len(got) != 3 {
			t.Fatalf("append new emoji = %+v", got)
		}
		if got[0].Emoji != "🔥" || got[1].Emoji != "👏" || got[2].Count != 1 || !got[2].ByMe {
			t.Fatalf("append new emoji details = %+v", got)
		}
	})
}

func TestToggleReactionCustom(t *testing.T) {
	t.Run("add first custom reaction", func(t *testing.T) {
		got := ToggleReaction(nil, "custom_7")
		if len(got) != 1 || got[0].Emoji != "" || got[0].DocumentID != 7 || got[0].Count != 1 || !got[0].ByMe {
			t.Fatalf("add custom = %+v", got)
		}
	})

	t.Run("match existing custom entry by document id", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "", DocumentID: 42, Count: 2}, {Emoji: "🔥", Count: 1}}
		got := ToggleReaction(base, "custom_42")
		if len(got) != 2 || got[0].DocumentID != 42 || got[0].Count != 3 || !got[0].ByMe {
			t.Fatalf("join custom = %+v", got)
		}
		if got[1].Emoji != "🔥" || got[1].Count != 1 {
			t.Fatalf("other untouched = %+v", got)
		}
	})

	t.Run("remove own custom drops at zero", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "", DocumentID: 42, Count: 1, ByMe: true}, {Emoji: "❤️", Count: 5}}
		got := ToggleReaction(base, "custom_42")
		if len(got) != 1 || got[0].Emoji != "❤️" {
			t.Fatalf("drop custom = %+v", got)
		}
	})

	t.Run("remove own custom keeps others count", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "", DocumentID: 42, Count: 4, ByMe: true}}
		got := ToggleReaction(base, "custom_42")
		if len(got) != 1 || got[0].Count != 3 || got[0].ByMe {
			t.Fatalf("decrement custom = %+v", got)
		}
	})

	t.Run("plain emoji named like a custom key toggles as that emoji", func(t *testing.T) {
		base := []cores.Reaction{{Emoji: "custom_7", Count: 9}}
		got := ToggleReaction(base, "custom_7")
		if len(got) != 1 || got[0].Emoji != "custom_7" || got[0].Count != 10 || !got[0].ByMe || got[0].DocumentID != 0 {
			t.Fatalf("plain-emoji toggle = %+v", got)
		}
	})

	t.Run("malformed custom key falls back to emoji", func(t *testing.T) {
		got := ToggleReaction(nil, "custom_x")
		if len(got) != 1 || got[0].Emoji != "custom_x" || got[0].DocumentID != 0 {
			t.Fatalf("malformed = %+v", got)
		}
	})
}
