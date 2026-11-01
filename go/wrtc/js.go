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

var ErrUnsupported = errors.New("wrtc: media call transport is not supported on js/wasm builds")

type PeerConnection struct {
	*webrtc.PeerConnection
}

func NewPeerConnection(cfg webrtc.Configuration) (*PeerConnection, error) {
	pc, err := webrtc.NewPeerConnection(cfg)
	if err != nil {
		return nil, err
	}
	return &PeerConnection{PeerConnection: pc}, nil
}

func (p *PeerConnection) AddTrack(_ TrackLocal) (*RTPSender, error) { return nil, ErrUnsupported }

func (p *PeerConnection) OnTrack(_ func(*TrackRemote, *webrtc.RTPReceiver)) {}

func (p *PeerConnection) GetStats() webrtc.StatsReport { return nil }

func (p *PeerConnection) GetSenders() []*RTPSender { return nil }

func (p *PeerConnection) GetReceivers() []*webrtc.RTPReceiver { return nil }

func (p *PeerConnection) GetTransceivers() []*RTPTransceiver { return nil }

type RTPTransceiver struct{ *webrtc.RTPTransceiver }

func (t *RTPTransceiver) Kind() webrtc.RTPCodecType { return 0 }

func (t *RTPTransceiver) Mid() string { return "" }

type RTPSender struct{ *webrtc.RTPSender }

func (s *RTPSender) Track() *TrackRemote { return nil }

func (s *RTPSender) Read([]byte) (int, interceptor.Attributes, error) {
	return 0, nil, ErrUnsupported
}

func (s *RTPSender) ReadRTCP() ([]rtcp.Packet, interceptor.Attributes, error) {
	return nil, nil, ErrUnsupported
}

func (s *RTPSender) GetParameters() webrtc.RTPSendParameters { return webrtc.RTPSendParameters{} }

type TrackLocal interface{ trackLocal() }

type TrackLocalStaticRTP struct{}

type TrackLocalStaticSample struct{}

func (*TrackLocalStaticRTP) trackLocal()    {}
func (*TrackLocalStaticSample) trackLocal() {}

func NewTrackLocalStaticRTP(_ webrtc.RTPCodecCapability, _, _ string, _ ...func(*TrackLocalStaticRTP)) (*TrackLocalStaticRTP, error) {
	return nil, ErrUnsupported
}

func NewTrackLocalStaticSample(_ webrtc.RTPCodecCapability, _, _ string, _ ...func(*TrackLocalStaticSample)) (*TrackLocalStaticSample, error) {
	return nil, ErrUnsupported
}

func (t *TrackLocalStaticRTP) WriteRTP(*rtp.Packet) error { return ErrUnsupported }

func (t *TrackLocalStaticRTP) Write([]byte) (int, error) { return 0, ErrUnsupported }

func (t *TrackLocalStaticRTP) WriteRTCP([][]byte) error { return ErrUnsupported }

func (t *TrackLocalStaticRTP) ID() string { return "" }

func (t *TrackLocalStaticRTP) StreamID() string { return "" }

func (t *TrackLocalStaticSample) WriteSample(pionmedia.Sample) error { return ErrUnsupported }

func (t *TrackLocalStaticSample) ID() string { return "" }

func (t *TrackLocalStaticSample) StreamID() string { return "" }

type TrackRemote struct{}

func (t *TrackRemote) ID() string { return "" }

func (t *TrackRemote) RID() string { return "" }

func (t *TrackRemote) Kind() webrtc.RTPCodecType { return 0 }

func (t *TrackRemote) StreamID() string { return "" }

func (t *TrackRemote) SSRC() webrtc.SSRC { return 0 }

func (t *TrackRemote) Msid() string { return "" }

func (t *TrackRemote) Codec() webrtc.RTPCodecParameters { return webrtc.RTPCodecParameters{} }

func (t *TrackRemote) PayloadType() webrtc.PayloadType { return 0 }

func (t *TrackRemote) Read([]byte) (int, interceptor.Attributes, error) {
	return 0, nil, ErrUnsupported
}

func (t *TrackRemote) ReadRTP() (*rtp.Packet, interceptor.Attributes, error) {
	return nil, nil, ErrUnsupported
}

func (t *TrackRemote) SetReadDeadline(time.Time) error { return ErrUnsupported }

type MediaEngine struct{}

func (m *MediaEngine) RegisterDefaultCodecs() error { return nil }

func (m *MediaEngine) RegisterCodec(webrtc.RTPCodecParameters, webrtc.RTPCodecType) error {
	return nil
}

func (m *MediaEngine) RegisterHeaderExtension(webrtc.RTPHeaderExtensionCapability, webrtc.RTPCodecType) error {
	return nil
}

func (m *MediaEngine) RegisterFeedback(webrtc.RTCPFeedback, webrtc.RTPCodecType) error { return nil }

type SettingEngine struct {
	LoggerFactory pionlogging.LoggerFactory
}

func (s *SettingEngine) SetSRTPReplayProtectionWindow(uint32) {}

func (s *SettingEngine) SetICECredentials(string, string) {}

func (s *SettingEngine) SetFireOnTrackBeforeFirstRTP(bool) {}

func (s *SettingEngine) SetIPFilter(func(net.IP) bool) {}

func (s *SettingEngine) SetHandleUndeclaredSSRCWithoutAnswer(bool) {}

type API struct{ *webrtc.API }

func NewAPI(...func(*API)) *API { return &API{API: webrtc.NewAPI()} }

func WithMediaEngine(*MediaEngine) func(*API) { return func(*API) {} }

func WithInterceptorRegistry(*interceptor.Registry) func(*API) { return func(*API) {} }

func WithSettingEngine(SettingEngine) func(*API) { return func(*API) {} }

func (a *API) NewPeerConnection(cfg webrtc.Configuration) (*PeerConnection, error) {
	pc, err := webrtc.NewPeerConnection(cfg)
	if err != nil {
		return nil, err
	}
	return &PeerConnection{PeerConnection: pc}, nil
}

func RegisterDefaultInterceptors(*MediaEngine, *interceptor.Registry) error { return nil }

func ConfigureNack(*MediaEngine, *interceptor.Registry) error { return nil }

func ConfigureRTCPReports(*interceptor.Registry) error { return nil }

func ConfigureStatsInterceptor(*interceptor.Registry) error { return nil }

func ConfigureTWCCSender(*MediaEngine, *interceptor.Registry) error { return nil }

func GatheringCompletePromise(_ *PeerConnection) (gatherComplete <-chan struct{}) {
	ch := make(chan struct{})
	close(ch)
	return ch
}
