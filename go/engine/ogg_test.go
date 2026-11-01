package engine

import (
	"bytes"
	"encoding/binary"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"uniclient/voice"
)

func TestOggRoundTrip(t *testing.T) {
	var buf bytes.Buffer
	pkt0 := append([]byte("OpusHead"), make([]byte, 11)...)
	pkt1 := []byte("OpusTags")
	pkt2 := bytes.Repeat([]byte{0xAB}, 300)
	serial := uint32(0x1EA7BEEF)
	buf.Write(buildOggPage([][]byte{pkt0, pkt1}, 960, serial, 0, false))
	buf.Write(buildOggPage([][]byte{pkt2}, 1920, serial, 1, true))

	rd := newOggPacketReader(bytes.NewReader(buf.Bytes()))
	var got [][]byte
	for {
		p, err := rd.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("Next: %v", err)
		}
		got = append(got, append([]byte(nil), p...))
	}
	if len(got) != 3 {
		t.Fatalf("packet count: %d, want 3", len(got))
	}
	if !bytes.Equal(got[0], pkt0) || !bytes.Equal(got[1], pkt1) {
		t.Fatalf("header packets mismatch: %x %x", got[0], got[1])
	}
	if !bytes.Equal(got[2], pkt2) {
		t.Fatalf("300-byte packet not reassembled: len=%d head=%x", len(got[2]), got[2][:4])
	}
}

func TestOggPacketSpansPages(t *testing.T) {
	big := bytes.Repeat([]byte{0x5A}, 600)
	serial := uint32(7)

	var head [oggHeaderLen]byte
	copy(head[:4], oggMagic)
	binary.LittleEndian.PutUint32(head[14:18], serial)
	binary.LittleEndian.PutUint32(head[18:22], 0)
	head[26] = 1
	page1 := make([]byte, 0, oggHeaderLen+1+255)
	page1 = append(page1, head[:]...)
	page1 = append(page1, byte(255))
	page1 = append(page1, big[:255]...)
	binary.LittleEndian.PutUint32(page1[22:26], oggCRC(page1))

	var buf bytes.Buffer
	buf.Write(page1)
	buf.Write(buildOggPage([][]byte{big[255:]}, 960, serial, 1, true))

	rd := newOggPacketReader(bytes.NewReader(buf.Bytes()))
	p, err := rd.Next()
	if err != nil {
		t.Fatalf("first packet: %v", err)
	}
	if !bytes.Equal(p, big) {
		t.Fatalf("cross-page packet mismatch: len=%d", len(p))
	}
	if _, err := rd.Next(); err != io.EOF {
		t.Fatalf("want EOF after the single packet, got %v", err)
	}
}

func TestOggCRCRejectsCorruption(t *testing.T) {
	page := buildOggPage([][]byte{[]byte("hello")}, 960, 1, 0, true)
	page[len(page)-1] ^= 0xFF
	rd := newOggPacketReader(bytes.NewReader(page))
	if _, err := rd.Next(); err == nil || err == io.EOF {
		t.Fatal("corrupted page must be rejected by CRC")
	}
}

func TestOggCRCVector(t *testing.T) {
	if got := oggCRC([]byte("123456789")); got != 0x89a1897f {
		t.Fatalf("oggCRC vector: got %08x want 89a1897f", got)
	}
	_ = binary.LittleEndian
}

func TestOggRealOpusFile(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not available")
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "tone.ogg")
	cmd := exec.Command("ffmpeg", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=2",
		"-ar", "48000", "-ac", "1", "-c:a", "libopus", "-b:a", "32k", path)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("ffmpeg encode failed: %v (%s)", err, out)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	rd := newOggPacketReader(bytes.NewReader(data))
	dec := voice.NewDecoder()
	nAudio := 0
	var totalSamples int
	for i := 0; ; i++ {
		pkt, err := rd.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("packet %d: %v (CRC/page mismatch vs real encoder)", i, err)
		}
		switch {
		case i == 0:
			if !bytes.HasPrefix(pkt, []byte("OpusHead")) {
				t.Fatalf("first packet is not OpusHead: %x", pkt[:8])
			}
		case i == 1:
			if !bytes.HasPrefix(pkt, []byte("OpusTags")) {
				t.Fatalf("second packet is not OpusTags: %x", pkt[:8])
			}
		default:
			pcm, err := dec.Decode(pkt)
			if err != nil {
				t.Fatalf("audio packet %d decode: %v", i, err)
			}
			nAudio++
			totalSamples += len(pcm)
		}
	}
	if nAudio == 0 {
		t.Fatal("no audio packets")
	}
	dur := float64(totalSamples) / float64(voice.SampleRate)
	if dur < 1.8 || dur > 2.2 {
		t.Fatalf("decoded duration %.2fs, want ~2s", dur)
	}
	t.Logf("real opus file: %d packets, %.2fs decoded, all page CRCs verified", nAudio, dur)
}
