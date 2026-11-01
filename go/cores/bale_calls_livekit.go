//go:build !js

package cores

import (
	"fmt"
	"os"
	"time"

	lksdk "github.com/livekit/server-sdk-go/v2"
	"github.com/pion/webrtc/v4"
	"github.com/pion/webrtc/v4/pkg/media"
)

type baleLKCall struct {
	room     *lksdk.Room
	audioPub *lksdk.LocalTrackPublication
}

func (c *baleActiveCall) audioPubSetMuted(muted bool) {
	if pub, ok := c.impl.(*baleLKCall); ok && pub != nil && pub.audioPub != nil {
		pub.audioPub.SetMuted(muted)
	}
}

func (b *BaleCore) baleConnectLiveKit(session *CallSession) error {
	lkURL := session.Meta["livekit_url"]
	lkToken := session.Meta["livekit_token"]
	if lkURL == "" || lkToken == "" {
		return fmt.Errorf("missing LiveKit credentials (url=%q token=%v)", lkURL, lkToken != "")
	}

	callDone := make(chan struct{})

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

	audioPub, err := room.LocalParticipant.PublishTrack(silenceTrack, &lksdk.TrackPublicationOptions{
		Name: "mic",
	})
	if err != nil {
		room.Disconnect()
		return fmt.Errorf("publish audio track: %w", err)
	}

	silence := make([]byte, 960*2)
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
