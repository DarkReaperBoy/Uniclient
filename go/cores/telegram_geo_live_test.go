package cores

// telegram_geo_live_test.go — slice 131 tests-first: live-location media
// builders (pure). The send path wraps InputMediaGeoLive{GeoPoint, Period};
// the stop path is messages.editMessage with InputMediaGeoLive{Stopped:true}
// (core.telegram.org/api/live-location: "In order to stop a live location,
// simply use messages.editMessage with inputMediaGeoLive and the stopped
// flag set").

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestLiveLocationMedia(t *testing.T) {
	m := liveLocationMedia(41.0, 29.0, 900)
	gl, ok := m.(*tg.InputMediaGeoLive)
	if !ok {
		t.Fatalf("liveLocationMedia returned %T", m)
	}
	gp, ok := gl.GeoPoint.(*tg.InputGeoPoint)
	if !ok || gp.Lat != 41.0 || gp.Long != 29.0 {
		t.Fatalf("geo point = %+v (%T)", gl.GeoPoint, gl.GeoPoint)
	}
	if gl.Period != 900 {
		t.Errorf("period = %d, want 900", gl.Period)
	}
	if gl.Stopped {
		t.Error("fresh share must not be pre-stopped")
	}
	if _, ok := gl.GetPeriod(); !ok {
		t.Error("period flag not set (gotd encodes flags lazily — SetPeriod required)")
	}
}

func TestLiveStopMedia(t *testing.T) {
	m := liveStopMedia()
	gl, ok := m.(*tg.InputMediaGeoLive)
	if !ok {
		t.Fatalf("liveStopMedia returned %T", m)
	}
	if !gl.Stopped {
		t.Error("stop media is not stopped")
	}
	// No geo point — the API takes stopped=true without coordinates.
	if gl.GeoPoint != nil {
		t.Errorf("stop media carried a geo point: %T", gl.GeoPoint)
	}
}
