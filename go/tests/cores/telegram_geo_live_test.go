package tests

import (
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestLiveLocationMedia(t *testing.T) {
	m := LiveLocationMedia(41.0, 29.0, 900)
	gl, ok := m.(*tg.InputMediaGeoLive)
	if !ok {
		t.Fatalf("LiveLocationMedia returned %T", m)
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
	m := LiveStopMedia()
	gl, ok := m.(*tg.InputMediaGeoLive)
	if !ok {
		t.Fatalf("LiveStopMedia returned %T", m)
	}
	if !gl.Stopped {
		t.Error("stop media is not stopped")
	}
	if gl.GeoPoint != nil {
		t.Errorf("stop media carried a geo point: %T", gl.GeoPoint)
	}
}
