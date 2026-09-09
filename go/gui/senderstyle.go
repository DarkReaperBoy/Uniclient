package gui

import (
	"image/color"

	"uniclient/engine"
)

// Sender color + admin rank (AyuGram parity slice 77, matrix row 89):
// Telegram renders group-chat sender names in a per-sender name color —
// the server-assigned color id when the core knows it (SenderColorID 0-6),
// otherwise a stable derivation from the sender id (the core returns -1
// for unknown). The admin rank (SenderRank, e.g. "admin"/"owner"/custom
// titles) is appended next to the name.

// senderPalette: Telegram's 7 dark-theme name colors.
var senderPalette = [7]color.NRGBA{
	{R: 0xE1, G: 0x70, B: 0x76, A: 0xFF}, // red
	{R: 0xFA, G: 0xA3, B: 0x37, A: 0xFF}, // orange
	{R: 0xA5, G: 0x66, B: 0xFF, A: 0xFF}, // violet
	{R: 0x63, G: 0xD6, B: 0x5B, A: 0xFF}, // green
	{R: 0x4F, G: 0xC3, B: 0xF7, A: 0xFF}, // cyan
	{R: 0x6A, G: 0xB3, B: 0xF3, A: 0xFF}, // blue
	{R: 0xF6, G: 0x94, B: 0xB8, A: 0xFF}, // pink
}

// senderColorFor resolves the bubble's sender-name color. colorID >= 0 is
// the server slot; colorID < 0 falls back to a stable hash of the sender
// id so a peer keeps one color across sessions.
func senderColorFor(colorID int, senderID string) color.NRGBA {
	if colorID >= 0 && colorID < len(senderPalette) {
		return senderPalette[colorID]
	}
	h := fnv32(senderID)
	return senderPalette[h%uint32(len(senderPalette))]
}

// fnv32: small stable string hash (FNV-1a).
func fnv32(s string) uint32 {
	var h uint32 = 2166136261
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

// senderTitle: display name with the admin rank suffix.
func senderTitle(m engine.CachedMessage) string {
	if m.SenderRank == "" {
		return m.SenderName
	}
	return m.SenderName + " (" + m.SenderRank + ")"
}
