//go:build js

package wrtc

import (
	"errors"
	"net"
	"time"

	"github.com/pion/interceptor"
	pionlogging "github.com/pion/logging"
	"github.com/pion/rtcp"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
	pionmedia "github.com/pion/webrtc/v4/pkg/media"
)

// ErrUnsupported is returned by every media-plumbing entry point on js/wasm.
// Signaling (offer/answer/ICE via the browser PeerConnection) still works;
// the media tracks themselves cannot be driven from Go on the web target.
var ErrUnsupported = errors.New("wrtc: media call transport is not supported on js/wasm builds")

// PeerConnection wraps the browser-backed *webrtc.PeerConnection and adds
// stubs for the native-only media methods (AddTrack/OnTrack/GetStats/
// GetSenders) so call transports compile. Everything the js API of
// pion/webrtc provides (CreateOffer, SetLocal/RemoteDescription,
// AddICECandidate, OnICECandidate, OnConnectionStateChange, Close, ...)
// keeps working through the embedded pointer.
type PeerConnection struct {
	*webrtc.PeerConnection
}

// NewPeerConnection wraps webrtc.NewPeerConnection.
func NewPeerConnection(cfg webrtc.Configuration) (*PeerConnection, error) {
	pc, err := webrtc.NewPeerConnection(cfg)
	if err != nil {
		return nil, err
	}
	return &PeerConnection{PeerConnection: pc}, nil
}

// AddTrack is a native-only media API; media cannot be attached on js/wasm.
func (p *PeerConnection) AddTrack(_ TrackLocal) (*RTPSender, error) { return nil, ErrUnsupported }

// OnTrack is a native-only media API; it never fires on js/wasm.
func (p *PeerConnection) OnTrack(_ func(*TrackRemote, *webrtc.RTPReceiver)) {}

// GetStats is a native-only media API; returns an empty report on js/wasm.
func (p *PeerConnection) GetStats() webrtc.StatsReport { return nil }

// GetSenders is a native-only media API; returns nothing on js/wasm.
func (p *PeerConnection) GetSenders() []*RTPSender { return nil }

// GetReceivers is a native-only media API; returns nothing on js/wasm.
func (p *PeerConnection) GetReceivers() []*webrtc.RTPReceiver { return nil }

// GetTransceivers returns shimmed transceivers on js/wasm (Kind/Mid are
// native-only; the browser transceiver only exposes direction + sender/
// receiver handles).
func (p *PeerConnection) GetTransceivers() []*RTPTransceiver { return nil }

// RTPTransceiver wraps the js RTPTransceiver with stubs for native-only
// methods.
type RTPTransceiver struct{ *webrtc.RTPTransceiver }

// Kind is a native-only transceiver API; zero value on js/wasm.
func (t *RTPTransceiver) Kind() webrtc.RTPCodecType { return 0 }

// Mid is a native-only transceiver API; empty on js/wasm.
func (t *RTPTransceiver) Mid() string { return "" }

// RTPSender wraps the js RTPSender with stubs for the native-only media
// methods (Read/ReadRTCP/Track).
type RTPSender struct{ *webrtc.RTPSender }

// Track is a native-only media API; always nil on js/wasm.
func (s *RTPSender) Track() *TrackRemote { return nil }

// Read is a native-only media API; always fails on js/wasm.
func (s *RTPSender) Read([]byte) (int, interceptor.Attributes, error) {
	return 0, nil, ErrUnsupported
}

// ReadRTCP is a native-only media API; always fails on js/wasm.
func (s *RTPSender) ReadRTCP() ([]rtcp.Packet, interceptor.Attributes, error) {
	return nil, nil, ErrUnsupported
}

// GetParameters is a native-only media API; zero value on js/wasm.
func (s *RTPSender) GetParameters() webrtc.RTPSendParameters { return webrtc.RTPSendParameters{} }

// TrackLocal is the AddTrack parameter type. Both static track stubs
// implement it.
type TrackLocal interface{ trackLocal() }

// TrackLocalStaticRTP is a compile stub for the native media track.
// Its constructor fails at runtime with ErrUnsupported.
type TrackLocalStaticRTP struct{}

// TrackLocalStaticSample is a compile stub for the native media track.
// Its constructor fails at runtime with ErrUnsupported.
type TrackLocalStaticSample struct{}

func (*TrackLocalStaticRTP) trackLocal()    {}
func (*TrackLocalStaticSample) trackLocal() {}

// NewTrackLocalStaticRTP mirrors the native constructor signature.
func NewTrackLocalStaticRTP(_ webrtc.RTPCodecCapability, _, _ string, _ ...func(*TrackLocalStaticRTP)) (*TrackLocalStaticRTP, error) {
	return nil, ErrUnsupported
}

// NewTrackLocalStaticSample mirrors the native constructor signature.
func NewTrackLocalStaticSample(_ webrtc.RTPCodecCapability, _, _ string, _ ...func(*TrackLocalStaticSample)) (*TrackLocalStaticSample, error) {
	return nil, ErrUnsupported
}

// WriteRTP mirrors the native method; always fails on js/wasm.
func (t *TrackLocalStaticRTP) WriteRTP(*rtp.Packet) error { return ErrUnsupported }

// Write mirrors the native raw-RTP-write method; always fails on js/wasm.
func (t *TrackLocalStaticRTP) Write([]byte) (int, error) { return 0, ErrUnsupported }

// WriteRTCP mirrors the native method; always fails on js/wasm.
func (t *TrackLocalStaticRTP) WriteRTCP([][]byte) error { return ErrUnsupported }

// ID mirrors the native method.
func (t *TrackLocalStaticRTP) ID() string { return "" }

// StreamID mirrors the native method.
func (t *TrackLocalStaticRTP) StreamID() string { return "" }

// WriteSample mirrors the native method; always fails on js/wasm.
func (t *TrackLocalStaticSample) WriteSample(pionmedia.Sample) error { return ErrUnsupported }

// ID mirrors the native method.
func (t *TrackLocalStaticSample) ID() string { return "" }

// StreamID mirrors the native method.
func (t *TrackLocalStaticSample) StreamID() string { return "" }

// TrackRemote is a compile stub for the native receive track. Its method
// set mirrors everything the cores call on native TrackRemote values.
type TrackRemote struct{}

// ID mirrors the native method.
func (t *TrackRemote) ID() string { return "" }

// RID mirrors the native method.
func (t *TrackRemote) RID() string { return "" }

// Kind mirrors the native method.
func (t *TrackRemote) Kind() webrtc.RTPCodecType { return 0 }

// StreamID mirrors the native method.
func (t *TrackRemote) StreamID() string { return "" }

// SSRC mirrors the native method.
func (t *TrackRemote) SSRC() webrtc.SSRC { return 0 }

// Msid mirrors the native method.
func (t *TrackRemote) Msid() string { return "" }

// Codec mirrors the native method.
func (t *TrackRemote) Codec() webrtc.RTPCodecParameters { return webrtc.RTPCodecParameters{} }

// PayloadType mirrors the native method.
func (t *TrackRemote) PayloadType() webrtc.PayloadType { return 0 }

// Read mirrors the native method; always fails on js/wasm.
func (t *TrackRemote) Read([]byte) (int, interceptor.Attributes, error) {
	return 0, nil, ErrUnsupported
}

// ReadRTP mirrors the native method; always fails on js/wasm.
func (t *TrackRemote) ReadRTP() (*rtp.Packet, interceptor.Attributes, error) {
	return nil, nil, ErrUnsupported
}

// SetReadDeadline mirrors the native method; always fails on js/wasm.
func (t *TrackRemote) SetReadDeadline(time.Time) error { return ErrUnsupported }

// MediaEngine is a compile stub; codec registration is a no-op on js/wasm
// (the browser negotiates codecs itself).
type MediaEngine struct{}

// RegisterDefaultCodecs is a no-op on js/wasm.
func (m *MediaEngine) RegisterDefaultCodecs() error { return nil }

// RegisterCodec mirrors the native 2-argument form; no-op on js/wasm.
func (m *MediaEngine) RegisterCodec(webrtc.RTPCodecParameters, webrtc.RTPCodecType) error {
	return nil
}

// RegisterHeaderExtension is a no-op on js/wasm.
func (m *MediaEngine) RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability, webrtc.RTPCodecType) error {
	return nil
}

// RegisterFeedback is a no-op on js/wasm.
func (m *MediaEngine) RegisterFeedback(webrtc.RTCPFeedback, webrtc.RTPCodecType) error { return nil }

// SettingEngine is a compile stub; all Set* methods are no-ops on js/wasm
// (the browser owns ICE/SRTP configuration).
type SettingEngine struct {
	// LoggerFactory mirrors the native field; unused on js/wasm.
	LoggerFactory pionlogging.LoggerFactory
}

// SetSRTPReplayProtectionWindow is a no-op on js/wasm.
func (s *SettingEngine) SetSRTPReplayProtectionWindow(uint32) {}

// SetICECredentials is a no-op on js/wasm.
func (s *SettingEngine) SetICECredentials(string, string) {}

// SetFireOnTrackBeforeFirstRTP is a no-op on js/wasm.
func (s *SettingEngine) SetFireOnTrackBeforeFirstRTP(bool) {}

// SetIPFilter is a no-op on js/wasm.
func (s *SettingEngine) SetIPFilter(func(net.IP) bool) {}

// SetHandleUndeclaredSSRCWithoutAnswer is a no-op on js/wasm.
func (s *SettingEngine) SetHandleUndeclaredSSRCWithoutAnswer(bool) {}

// API wraps the js *webrtc.API so NewPeerConnection can return the wrtc
// wrapper type. Options are accepted and ignored.
type API struct{ *webrtc.API }

// NewAPI mirrors the native constructor; options are ignored on js/wasm.
func NewAPI(...func(*API)) *API { return &API{API: webrtc.NewAPI()} }

// WithMediaEngine mirrors the native option; ignored on js/wasm.
func WithMediaEngine(*MediaEngine) func(*API) { return func(*API) {} }

// WithInterceptorRegistry mirrors the native option; ignored on js/wasm.
func WithInterceptorRegistry(*interceptor.Registry) func(*API) { return func(*API) {} }

// WithSettingEngine mirrors the native option; ignored on js/wasm.
func WithSettingEngine(SettingEngine) func(*API) { return func(*API) {} }

// NewPeerConnection returns the wrtc wrapper around a browser PC.
func (a *API) NewPeerConnection(cfg webrtc.Configuration) (*PeerConnection, error) {
	pc, err := webrtc.NewPeerConnection(cfg)
	if err != nil {
		return nil, err
	}
	return &PeerConnection{PeerConnection: pc}, nil
}

// RegisterDefaultInterceptors is a no-op on js/wasm.
func RegisterDefaultInterceptors(*MediaEngine, *interceptor.Registry) error { return nil }

// ConfigureNack is a no-op on js/wasm.
func ConfigureNack(*MediaEngine, *interceptor.Registry) error { return nil }

// ConfigureRTCPReports is a no-op on js/wasm.
func ConfigureRTCPReports(*interceptor.Registry) error { return nil }

// ConfigureStatsInterceptor is a no-op on js/wasm.
func ConfigureStatsInterceptor(*interceptor.Registry) error { return nil }

// ConfigureTWCCSender is a no-op on js/wasm.
func ConfigureTWCCSender(*MediaEngine, *interceptor.Registry) error { return nil }

// GatheringCompletePromise mirrors the native function; on js/wasm the
// browser fires ICE gathering events, so the returned channel is closed
// immediately (gathering treated as complete).
func GatheringCompletePromise(_ *PeerConnection) (gatherComplete <-chan struct{}) {
	ch := make(chan struct{})
	close(ch)
	return ch
}
