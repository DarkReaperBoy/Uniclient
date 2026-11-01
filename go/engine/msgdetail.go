package engine

import (
	"encoding/json"
	"strconv"
)

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
