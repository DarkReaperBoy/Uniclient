package cores

import "testing"

// TestJingleCodecTables pins the XEP-0266/0299 recommended codec
// tables (deadcode: unreachable even with tests — the XMPP call path
// builds its SDP elsewhere). Kept as protocol reference per the B-18
// table doctrine, with the values locked so a silent edit can't drift
// them away from the spec.
func TestJingleCodecTables(t *testing.T) {
	audio := JingleAudioCodecs()
	wantAudio := []map[string]string{
		{"id": "111", "name": "opus", "clockrate": "48000", "channels": "2"},
		{"id": "100", "name": "speex", "clockrate": "16000"},
		{"id": "0", "name": "PCMU", "clockrate": "8000"},
		{"id": "8", "name": "PCMA", "clockrate": "8000"},
	}
	if len(audio) != len(wantAudio) {
		t.Fatalf("audio table has %d entries, want %d", len(audio), len(wantAudio))
	}
	for i, want := range wantAudio {
		for k, v := range want {
			if audio[i][k] != v {
				t.Errorf("audio[%d][%s] = %q, want %q", i, k, audio[i][k], v)
			}
		}
	}

	video := JingleVideoCodecs()
	wantVideo := []map[string]string{
		{"id": "96", "name": "VP8", "clockrate": "90000"},
		{"id": "97", "name": "H264", "clockrate": "90000"},
	}
	if len(video) != len(wantVideo) {
		t.Fatalf("video table has %d entries, want %d", len(video), len(wantVideo))
	}
	for i, want := range wantVideo {
		for k, v := range want {
			if video[i][k] != v {
				t.Errorf("video[%d][%s] = %q, want %q", i, k, video[i][k], v)
			}
		}
	}
}
