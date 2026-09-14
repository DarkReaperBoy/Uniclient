package engine

// msgdetail.go — slice 207: message-details completion (AyuGram parity
// gap 15). The media document/photo DC rides the media row (migrateV56)
// into CachedMessage.MediaDC for the "Datacenter" details row, and the
// sticker-set author derives from the cached pack ID with the
// TDesktop-x64 bit formula AyuGram's getUserIdFromPackId uses.

import (
	"encoding/json"
	"strconv"
)

// StickerPackAuthorID derives the sticker-pack owner's user ID from the
// pack ID — the TDesktop-x64 formula (AyuGram getUserIdFromPackId,
// telegram_helpers.cpp):
//
//	ownerId = id >> 32
//	if (id >> 16 & 0xff) == 0x3f → ownerId |= 0x80000000
//	if  id >> 24 & 0xff          → ownerId += 0x100000000
//
// Pure — unit-tested.
func StickerPackAuthorID(packID int64) int64 {
	ownerID := packID >> 32
	if (packID>>16)&0xff == 0x3f {
		ownerID |= 0x80000000
	}
	if (packID>>24)&0xff != 0 {
		ownerID += 0x100000000
	}
	return ownerID
}

// StickerSetID returns the message's sticker pack ID from the cached
// content (the core exports sticker_set_id on sticker documents); 0 when
// the message carries none. Pure — unit-tested.
func (m *CachedMessage) StickerSetID() int64 {
	if m == nil || len(m.ContentRaw) == 0 {
		return 0
	}
	var msg struct {
		Extra map[string]interface{} `json:"extra"`
	}
	if json.Unmarshal(m.ContentRaw, &msg) != nil || msg.Extra == nil {
		return 0
	}
	switch v := msg.Extra["sticker_set_id"].(type) {
	case string:
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	case float64:
		return int64(v)
	}
	return 0
}
