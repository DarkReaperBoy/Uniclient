//go:build !js

package cores

import (
	"fmt"
	"strings"

	"github.com/gotd/td/tg"
)

func ProximityDistanceLabel(meters int) string {
	if meters < 1000 {
		return fmt.Sprintf("%d m", meters)
	}
	km := float64(10*(meters/10)) / 1000.0
	s := fmt.Sprintf("%.1f", km)
	s = strings.TrimSuffix(s, ".0")
	return s + " km"
}

func ProximityReachedText(fromName, toName string, fromSelf, toSelf bool, meters int) string {
	d := ProximityDistanceLabel(meters)
	if fromName == "" {
		fromName = "a user"
	}
	if toName == "" {
		toName = "a user"
	}
	switch {
	case fromSelf:
		return "You're now within " + d + " of " + toName
	case toSelf:
		return fromName + " is now within " + d + " of you"
	default:
		return fromName + " is now within " + d + " of " + toName
	}
}

func (t *TelegramCore) proximityPeerName(peer tg.PeerClass) string {
	switch p := peer.(type) {
	case *tg.PeerUser:
		if n := t.getCachedUserName(p.UserID); n != "" {
			return n
		}
	case *tg.PeerChannel:
		if n := t.getCachedChannelName(p.ChannelID); n != "" {
			return n
		}
	case *tg.PeerChat:
		if n := t.getCachedChannelName(p.ChatID); n != "" {
			return n
		}
	}
	return ""
}
