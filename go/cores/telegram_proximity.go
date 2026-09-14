package cores

// telegram_proximity.go — slice 208: the messageActionGeoProximityReached
// service message (the last live-location parity piece). tdesktop renders
// it in history_item.cpp prepareProximityReached: "{from} is now within
// {distance} of {to}" with the self variants and the 10 m-precision km
// label. tdesktop exposes NO radius-setting UI (mobile-only), so rendering
// the server-pushed alert is the full desktop parity scope.

import (
	"fmt"
	"strings"

	"github.com/gotd/td/tg"
)

// proximityDistanceLabel (pure, testable): the distance label — meters
// under 1 km, kilometers above (10 m precision before the division, the
// tdesktop formula).
func proximityDistanceLabel(meters int) string {
	if meters < 1000 {
		return fmt.Sprintf("%d m", meters)
	}
	km := float64(10*(meters/10)) / 1000.0
	s := fmt.Sprintf("%.1f", km)
	s = strings.TrimSuffix(s, ".0")
	return s + " km"
}

// proximityReachedText (pure, testable): the service sentence for one
// proximity-reached event, tdesktop's three shapes (from-self, to-self,
// third-party).
func proximityReachedText(fromName, toName string, fromSelf, toSelf bool, meters int) string {
	d := proximityDistanceLabel(meters)
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

// proximityPeerName resolves a peer's display name from the core caches
// (users and channels/chats share the fallback).
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
