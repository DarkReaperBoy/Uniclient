//go:build !js

package wrtc

import (
	"github.com/pion/interceptor"
	"github.com/pion/webrtc/v4"
)

// On native platforms wrtc.X IS webrtc.X. Type aliases give zero-cost,
// behavior-identical dispatch; the js build (js.go) provides compile stubs
// with the same names.

type (
	// PeerConnection is webrtc.PeerConnection.
	PeerConnection = webrtc.PeerConnection
	// API is webrtc.API.
	API = webrtc.API
	// MediaEngine is webrtc.MediaEngine.
	MediaEngine = webrtc.MediaEngine
	// SettingEngine is webrtc.SettingEngine.
	SettingEngine = webrtc.SettingEngine
	// TrackLocalStaticRTP is webrtc.TrackLocalStaticRTP.
	TrackLocalStaticRTP = webrtc.TrackLocalStaticRTP
	// TrackLocalStaticSample is webrtc.TrackLocalStaticSample.
	TrackLocalStaticSample = webrtc.TrackLocalStaticSample
	// TrackRemote is webrtc.TrackRemote.
	TrackRemote = webrtc.TrackRemote
	// RTPSender is webrtc.RTPSender.
	RTPSender = webrtc.RTPSender
)

var (
	// NewPeerConnection is webrtc.NewPeerConnection.
	NewPeerConnection = webrtc.NewPeerConnection
	// NewAPI is webrtc.NewAPI.
	NewAPI = webrtc.NewAPI
	// NewTrackLocalStaticRTP is webrtc.NewTrackLocalStaticRTP.
	NewTrackLocalStaticRTP = webrtc.NewTrackLocalStaticRTP
	// NewTrackLocalStaticSample is webrtc.NewTrackLocalStaticSample.
	NewTrackLocalStaticSample = webrtc.NewTrackLocalStaticSample
)

// WithMediaEngine is webrtc.WithMediaEngine.
func WithMediaEngine(m *MediaEngine) func(a *API) { return webrtc.WithMediaEngine(m) }

// WithInterceptorRegistry is webrtc.WithInterceptorRegistry.
func WithInterceptorRegistry(ir *interceptor.Registry) func(a *API) {
	return webrtc.WithInterceptorRegistry(ir)
}

// WithSettingEngine is webrtc.WithSettingEngine.
func WithSettingEngine(s SettingEngine) func(a *API) { return webrtc.WithSettingEngine(s) }

// RegisterDefaultInterceptors is webrtc.RegisterDefaultInterceptors.
func RegisterDefaultInterceptors(m *MediaEngine, ir *interceptor.Registry) error {
	return webrtc.RegisterDefaultInterceptors(m, ir)
}

// ConfigureNack is webrtc.ConfigureNack.
func ConfigureNack(m *MediaEngine, ir *interceptor.Registry) error {
	return webrtc.ConfigureNack(m, ir)
}

// ConfigureRTCPReports is webrtc.ConfigureRTCPReports.
func ConfigureRTCPReports(ir *interceptor.Registry) error {
	return webrtc.ConfigureRTCPReports(ir)
}

// ConfigureStatsInterceptor is webrtc.ConfigureStatsInterceptor.
func ConfigureStatsInterceptor(ir *interceptor.Registry) error {
	return webrtc.ConfigureStatsInterceptor(ir)
}

// ConfigureTWCCSender is webrtc.ConfigureTWCCSender.
func ConfigureTWCCSender(m *MediaEngine, ir *interceptor.Registry) error {
	return webrtc.ConfigureTWCCSender(m, ir)
}

// GatheringCompletePromise is webrtc.GatheringCompletePromise.
func GatheringCompletePromise(pc *PeerConnection) (gatherComplete <-chan struct{}) {
	return webrtc.GatheringCompletePromise(pc)
}
