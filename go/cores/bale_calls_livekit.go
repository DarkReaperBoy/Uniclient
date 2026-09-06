//go:build !js

// LiveKit-based call transport for the Bale core (native platforms only).
//
// Extracted from bale.go so the core stays buildable for js/wasm: the
// LiveKit server SDK does not compile for js/wasm (it depends on pion/webrtc
// APIs that are not available under GOOS=js). Signaling still goes through
// Bale's user API in bale.go; this file only owns the media transport.
//
// UNTESTED: meet-em.ble.ir is geo-restricted to Iran. This subsystem was
// implemented from the Python reference (bale.py) and LiveKit SDK docs but
// has never been tested against a live server.

package cores

import (
	"fmt"
	"os"
	"time"

	lksdk "github.com/livekit/server-sdk-go/v2"
	"github.com/pion/webrtc/v4"
	"github.com/pion/webrtc/v4/pkg/media"
)

// baleLKCall holds the transport-specific handles for an active LiveKit call.
type baleLKCall struct {
	room     *lksdk.Room
	audioPub *lksdk.LocalTrackPublication // our published silent/mic audio track
}

// audioPubSetMuted mutes/unmutes our published track. Defined on
// baleActiveCall so callers in bale.go are transport-agnostic.
func (c *baleActiveCall) audioPubSetMuted(muted bool) {
	if pub, ok := c.impl.(*baleLKCall); ok && pub != nil && pub.audioPub != nil {
		pub.audioPub.SetMuted(muted)
	}
}

// baleConnectLiveKit connects to the LiveKit SFU room using the credentials from CallSession.Meta.
// It publishes a silent audio track (required for the SFU to treat us as a real participant)
// and subscribes to all remote tracks. Audio from remote participants is forwarded to
// the update handler as UpdateCallState events.
func (b *BaleCore) baleConnectLiveKit(session *CallSession) error {
	lkURL := session.Meta["livekit_url"]
	lkToken := session.Meta["livekit_token"]
	if lkURL == "" || lkToken == "" {
		return fmt.Errorf("missing LiveKit credentials (url=%q token=%v)", lkURL, lkToken != "")
	}

	// done is closed when the call ends, signaling all track reader goroutines to exit
	callDone := make(chan struct{})

	// Create a silent opus audio track — the SFU needs at least one published audio track
	// to treat the connection as a real call participant (affects bandwidth allocation,
	// triggers connection_quality_changed events).
	silenceTrack, err := lksdk.NewLocalSampleTrack(webrtc.RTPCodecCapability{
		MimeType:  webrtc.MimeTypeOpus,
		ClockRate: 48000,
		Channels:  1,
	})
	if err != nil {
		return fmt.Errorf("create silent audio track: %w", err)
	}

	cb := &lksdk.RoomCallback{
		ParticipantCallback: lksdk.ParticipantCallback{
			OnTrackSubscribed: func(track *webrtc.TrackRemote, pub *lksdk.RemoteTrackPublication, rp *lksdk.RemoteParticipant) {
				fmt.Fprintf(os.Stderr, "bale: track subscribed: kind=%s from %s\n", track.Kind(), rp.Identity())
				if track.Kind() == webrtc.RTPCodecTypeAudio {
					// Read and discard audio RTP packets to keep the stream alive.
					// In a full implementation, these would be decoded and forwarded
					// to the UI for playback via the bridge's audio callback.
					go func() {
						buf := make([]byte, 1500)
						for {
							select {
							case <-callDone:
								return
							default:
							}
							_, _, err := track.Read(buf)
							if err != nil {
								return
							}
						}
					}()
				}
			},
			OnTrackUnsubscribed: func(track *webrtc.TrackRemote, pub *lksdk.RemoteTrackPublication, rp *lksdk.RemoteParticipant) {
				fmt.Fprintf(os.Stderr, "bale: track unsubscribed: kind=%s from %s\n", track.Kind(), rp.Identity())
			},
		},
		OnDisconnected: func() {
			fmt.Fprintf(os.Stderr, "bale: LiveKit disconnected\n")
			b.activeCallMu.Lock()
			b.activeCall = nil
			b.activeCallMu.Unlock()
			b.updateMu.RLock()
			for _, h := range b.updateHandlers {
				go h(Update{Type: UpdateCallState})
			}
			b.updateMu.RUnlock()
		},
		OnReconnecting: func() {
			fmt.Fprintf(os.Stderr, "bale: LiveKit reconnecting...\n")
		},
		OnReconnected: func() {
			fmt.Fprintf(os.Stderr, "bale: LiveKit reconnected\n")
		},
		OnParticipantConnected: func(p *lksdk.RemoteParticipant) {
			fmt.Fprintf(os.Stderr, "bale: participant joined: %s (sid=%s)\n", p.Identity(), p.SID())
		},
		OnParticipantDisconnected: func(p *lksdk.RemoteParticipant) {
			fmt.Fprintf(os.Stderr, "bale: participant left: %s\n", p.Identity())
		},
	}

	room, err := lksdk.ConnectToRoomWithToken(lkURL, lkToken, cb,
		lksdk.WithAutoSubscribe(true),
	)
	if err != nil {
		return fmt.Errorf("LiveKit connect to %s: %w", lkURL, err)
	}

	fmt.Fprintf(os.Stderr, "bale: connected to LiveKit room %s\n", room.Name())

	// Publish silent audio track — feed one frame of silence then rely on DTX
	// Source auto-detected as MICROPHONE for audio tracks when Source == UNKNOWN
	audioPub, err := room.LocalParticipant.PublishTrack(silenceTrack, &lksdk.TrackPublicationOptions{
		Name: "mic",
	})
	if err != nil {
		room.Disconnect()
		return fmt.Errorf("publish audio track: %w", err)
	}

	// Write one frame of silence to initialize the encoder, then DTX handles the rest
	silence := make([]byte, 960*2) // 20ms at 48kHz, 16-bit mono = 960 samples * 2 bytes
	_ = silenceTrack.WriteSample(media.Sample{
		Data:     silence,
		Duration: 20 * time.Millisecond,
	}, nil)

	fmt.Fprintf(os.Stderr, "bale: audio track published (silent, DTX)\n")

	b.activeCallMu.Lock()
	b.activeCall = &baleActiveCall{
		session: session,
		done:    callDone,
		impl:    &baleLKCall{room: room, audioPub: audioPub},
	}
	b.activeCallMu.Unlock()

	return nil
}

// baleDisconnectLiveKit disconnects from the active LiveKit room.
func (b *BaleCore) baleDisconnectLiveKit() {
	b.activeCallMu.Lock()
	call := b.activeCall
	b.activeCall = nil
	b.activeCallMu.Unlock()

	if call != nil {
		if call.done != nil {
			select {
			case <-call.done:
			default:
				close(call.done)
			}
		}
		if lk, ok := call.impl.(*baleLKCall); ok && lk != nil && lk.room != nil {
			lk.room.Disconnect()
			fmt.Fprintf(os.Stderr, "bale: LiveKit disconnected\n")
		}
	}
}
