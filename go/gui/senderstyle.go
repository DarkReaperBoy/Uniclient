package gui

import (
	"image/color"

	"uniclient/engine"
)

var senderPalette = [7]color.NRGBA{
	{R: 0xE1, G: 0x70, B: 0x76, A: 0xFF},
	{R: 0xFA, G: 0xA3, B: 0x37, A: 0xFF},
	{R: 0xA5, G: 0x66, B: 0xFF, A: 0xFF},
	{R: 0x63, G: 0xD6, B: 0x5B, A: 0xFF},
	{R: 0x4F, G: 0xC3, B: 0xF7, A: 0xFF},
	{R: 0x6A, G: 0xB3, B: 0xF3, A: 0xFF},
	{R: 0xF6, G: 0x94, B: 0xB8, A: 0xFF},
}

func senderColorFor(colorID int, senderID string) color.NRGBA {
	if colorID >= 0 && colorID < len(senderPalette) {
		return senderPalette[colorID]
	}
	h := fnv32(senderID)
	return senderPalette[h%uint32(len(senderPalette))]
}

func fnv32(s string) uint32 {
	var h uint32 = 2166136261
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

func senderTitle(m engine.CachedMessage) string {
	if m.SenderRank == "" {
		return m.SenderName
	}
	return m.SenderName + " (" + m.SenderRank + ")"
}
