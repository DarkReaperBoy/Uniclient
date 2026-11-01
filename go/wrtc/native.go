//go:build !js

package wrtc

import (
	"github.com/pion/interceptor"
	"github.com/pion/webrtc/v4"
)

type (
	PeerConnection         = webrtc.PeerConnection
	API                    = webrtc.API
	MediaEngine            = webrtc.MediaEngine
	SettingEngine          = webrtc.SettingEngine
	TrackLocalStaticRTP    = webrtc.TrackLocalStaticRTP
	TrackLocalStaticSample = webrtc.TrackLocalStaticSample
	TrackRemote            = webrtc.TrackRemote
	RTPSender              = webrtc.RTPSender
)

var (
	NewPeerConnection         = webrtc.NewPeerConnection
	NewAPI                    = webrtc.NewAPI
	NewTrackLocalStaticRTP    = webrtc.NewTrackLocalStaticRTP
	NewTrackLocalStaticSample = webrtc.NewTrackLocalStaticSample
)

func WithMediaEngine(m *MediaEngine) func(a *API) { return webrtc.WithMediaEngine(m) }

func WithInterceptorRegistry(ir *interceptor.Registry) func(a *API) {
	return webrtc.WithInterceptorRegistry(ir)
}

func WithSettingEngine(s SettingEngine) func(a *API) { return webrtc.WithSettingEngine(s) }

func RegisterDefaultInterceptors(m *MediaEngine, ir *interceptor.Registry) error {
	return webrtc.RegisterDefaultInterceptors(m, ir)
}

func ConfigureNack(m *MediaEngine, ir *interceptor.Registry) error {
	return webrtc.ConfigureNack(m, ir)
}

func ConfigureRTCPReports(ir *interceptor.Registry) error {
	return webrtc.ConfigureRTCPReports(ir)
}

func ConfigureStatsInterceptor(ir *interceptor.Registry) error {
	return webrtc.ConfigureStatsInterceptor(ir)
}

func ConfigureTWCCSender(m *MediaEngine, ir *interceptor.Registry) error {
	return webrtc.ConfigureTWCCSender(m, ir)
}

func GatheringCompletePromise(pc *PeerConnection) (gatherComplete <-chan struct{}) {
	return webrtc.GatheringCompletePromise(pc)
}
