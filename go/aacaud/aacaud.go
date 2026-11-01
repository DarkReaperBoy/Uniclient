package aacaud

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	aacpcm "github.com/tphakala/go-aac/pcm"
)

var (
	ErrNoAudio     = errors.New("aacaud: no audio track")
	ErrUnsupported = errors.New("aacaud: unsupported audio")
	ErrCorrupt     = errors.New("aacaud: corrupt file")
)

type Sample struct {
	Data []byte
	DTS  int64
}

type Track struct {
	SampleRate int
	Channels   int
	ASC        []byte
	Timescale  uint32
	Priming    int
	Length     int
	Samples    []Sample
}

func (t *Track) Duration() time.Duration {
	if t.SampleRate <= 0 || t.Length <= 0 {
		return 0
	}
	return time.Duration(int64(t.Length) * int64(time.Second) / int64(t.SampleRate))
}

func ParseFile(path string) (*Track, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return Parse(f)
}

type mbox struct {
	typ  string
	body []byte
}

func children(b []byte) ([]mbox, error) {
	var out []mbox
	for off := 0; off+8 <= len(b); {
		size := int(binary.BigEndian.Uint32(b[off : off+4]))
		typ := string(b[off+4 : off+8])
		hdr := 8
		switch {
		case size == 1:
			if off+16 > len(b) {
				return nil, fmt.Errorf("%w: truncated 64-bit size for %q", ErrCorrupt, typ)
			}
			size = int(binary.BigEndian.Uint64(b[off+8 : off+16]))
			hdr = 16
		case size == 0:
			size = len(b) - off
		}
		if size < hdr || off+size > len(b) {
			return nil, fmt.Errorf("%w: box %q claims %d bytes at offset %d of %d",
				ErrCorrupt, typ, size, off, len(b))
		}
		out = append(out, mbox{typ: typ, body: b[off+hdr : off+size]})
		off += size
	}
	return out, nil
}

func Parse(r io.ReadSeeker) (*Track, error) {
	if r == nil {
		return nil, fmt.Errorf("%w: nil reader", ErrCorrupt)
	}
	end, err := r.Seek(0, io.SeekEnd)
	if err != nil {
		return nil, err
	}
	moov, movieTS, err := readMoov(r, end)
	if err != nil {
		return nil, err
	}
	roots, err := children(moov)
	if err != nil {
		return nil, err
	}
	for _, b := range roots {
		if b.typ != "trak" {
			continue
		}
		tr, err := parseTrak(r, b.body, movieTS)
		if errors.Is(err, ErrNoAudio) {
			continue
		}
		if err != nil {
			return nil, err
		}
		return tr, nil
	}
	return nil, ErrNoAudio
}

func readMoov(r io.ReadSeeker, end int64) ([]byte, uint32, error) {
	var hdr [16]byte
	for off := int64(0); off+8 <= end; {
		if _, err := r.Seek(off, io.SeekStart); err != nil {
			return nil, 0, err
		}
		if _, err := io.ReadFull(r, hdr[:8]); err != nil {
			return nil, 0, fmt.Errorf("%w: reading box header at %d: %v", ErrCorrupt, off, err)
		}
		size := int64(binary.BigEndian.Uint32(hdr[:4]))
		typ := string(hdr[4:8])
		hdrLen := int64(8)
		switch {
		case size == 1:
			if _, err := io.ReadFull(r, hdr[8:16]); err != nil {
				return nil, 0, fmt.Errorf("%w: reading 64-bit size of %q: %v", ErrCorrupt, typ, err)
			}
			size = int64(binary.BigEndian.Uint64(hdr[8:16]))
			hdrLen = 16
		case size == 0:
			size = end - off
		}
		if size < hdrLen || off+size > end {
			return nil, 0, fmt.Errorf("%w: box %q claims size %d at offset %d", ErrCorrupt, typ, size, off)
		}
		if typ == "moov" {
			body := make([]byte, size-hdrLen)
			if _, err := io.ReadFull(r, body); err != nil {
				return nil, 0, fmt.Errorf("%w: reading moov: %v", ErrCorrupt, err)
			}
			roots, err := children(body)
			if err != nil {
				return nil, 0, err
			}
			var movieTS uint32
			for _, c := range roots {
				if c.typ == "mvhd" {
					movieTS = parseMVHD(c.body)
				}
			}
			if movieTS == 0 {
				movieTS = 1000
			}
			return body, movieTS, nil
		}
		off += size
	}
	return nil, 0, fmt.Errorf("%w: no moov box (fragmented MP4 is not supported)", ErrCorrupt)
}

func parseMVHD(b []byte) uint32 {
	if len(b) < 16 {
		return 0
	}
	if b[0] == 1 {
		if len(b) < 24 {
			return 0
		}
		return binary.BigEndian.Uint32(b[20:24])
	}
	return binary.BigEndian.Uint32(b[12:16])
}

func parseTrak(r io.ReadSeeker, trakBody []byte, movieTS uint32) (*Track, error) {
	boxes, err := children(trakBody)
	if err != nil {
		return nil, err
	}
	var (
		handler   string
		timescale uint32
		edit      *editList
		stblBody  []byte
	)
	for _, b := range boxes {
		switch b.typ {
		case "edts":
			kids, err := children(b.body)
			if err != nil {
				return nil, err
			}
			for _, k := range kids {
				if k.typ == "elst" {
					if e, err := parseELST(k.body); err != nil {
						return nil, err
					} else {
						edit = e
					}
				}
			}
		case "mdia":
			kids, err := children(b.body)
			if err != nil {
				return nil, err
			}
			for _, k := range kids {
				switch k.typ {
				case "hdlr":
					if len(k.body) >= 12 {
						handler = string(k.body[8:12])
					}
				case "mdhd":
					timescale = parseMDHD(k.body)
				case "minf":
					sub, err := children(k.body)
					if err != nil {
						return nil, err
					}
					for _, s := range sub {
						if s.typ == "stbl" {
							stblBody = s.body
						}
					}
				}
			}
		}
	}
	if handler != "soun" {
		return nil, ErrNoAudio
	}
	if timescale == 0 {
		return nil, fmt.Errorf("%w: audio track has no mdhd timescale", ErrCorrupt)
	}
	if stblBody == nil {
		return nil, fmt.Errorf("%w: audio track has no stbl", ErrCorrupt)
	}

	stbl, err := children(stblBody)
	if err != nil {
		return nil, err
	}
	var (
		asc       []byte
		sttsBody  []byte
		stscBody  []byte
		stszBody  []byte
		stcoBody  []byte
		co64      bool
		mp4aRate  uint32
		mp4aChans uint16
	)
	for _, b := range stbl {
		switch b.typ {
		case "stsd":
			asc, mp4aRate, mp4aChans, err = parseSTSD(b.body)
			if err != nil {
				return nil, err
			}
		case "stts":
			sttsBody = b.body
		case "stsc":
			stscBody = b.body
		case "stsz":
			stszBody = b.body
		case "stco":
			stcoBody = b.body
		case "co64":
			stcoBody, co64 = b.body, true
		}
	}
	if asc == nil {
		return nil, fmt.Errorf("%w: audio track has no AudioSpecificConfig", ErrCorrupt)
	}
	rate, channels, err := ascInfo(asc)
	if err != nil {
		return nil, err
	}
	if mp4aRate != 0 && int(mp4aRate) != rate {
		return nil, fmt.Errorf("%w: mp4a says %d Hz, ASC says %d", ErrCorrupt, mp4aRate, rate)
	}
	if mp4aChans != 0 && int(mp4aChans) != channels {
		return nil, fmt.Errorf("%w: mp4a says %d channels, ASC says %d", ErrCorrupt, mp4aChans, channels)
	}

	deltas, err := parseSTTS(sttsBody)
	if err != nil {
		return nil, err
	}
	sizes, err := parseSTSZ(stszBody)
	if err != nil {
		return nil, err
	}
	chunks, err := parseSTCO(stcoBody, co64)
	if err != nil {
		return nil, err
	}
	perChunk, err := parseSTSC(stscBody)
	if err != nil {
		return nil, err
	}
	if len(sizes) != len(deltas) {
		return nil, fmt.Errorf("%w: stsz lists %d samples, stts %d",
			ErrCorrupt, len(sizes), len(deltas))
	}

	samples, err := readSamples(r, sizes, chunks, perChunk, deltas)
	if err != nil {
		return nil, err
	}

	tr := &Track{
		SampleRate: rate,
		Channels:   channels,
		ASC:        append([]byte(nil), asc...),
		Timescale:  timescale,
		Samples:    samples,
	}

	tr.Priming, tr.Length = editPresentation(edit, movieTS, rate, deltas)
	return tr, nil
}

type editList struct {
	mediaTime  int64
	segmentDur int64
}

func parseELST(b []byte) (*editList, error) {
	if len(b) < 8 {
		return nil, fmt.Errorf("%w: short elst", ErrCorrupt)
	}
	count := int(binary.BigEndian.Uint32(b[4:8]))
	v1 := b[0] == 1
	e := &editList{mediaTime: -1}
	p := 8
	for i := 0; i < count; i++ {
		var segDur, mediaTime int64
		if v1 {
			if p+16 > len(b) {
				return nil, fmt.Errorf("%w: truncated elst", ErrCorrupt)
			}
			segDur = int64(binary.BigEndian.Uint64(b[p : p+8]))
			mediaTime = int64(binary.BigEndian.Uint64(b[p+8 : p+16]))
			p += 16
		} else {
			if p+8 > len(b) {
				return nil, fmt.Errorf("%w: truncated elst", ErrCorrupt)
			}
			segDur = int64(binary.BigEndian.Uint32(b[p : p+4]))
			mt := binary.BigEndian.Uint32(b[p+4 : p+8])
			if mt == 0xFFFFFFFF {
				p += 8 + 2
				continue
			}
			mediaTime = int64(mt)
			p += 8
		}
		p += 2
		if e.mediaTime < 0 || mediaTime > 0 {
			e.segmentDur, e.mediaTime = segDur, mediaTime
			break
		}
	}
	if e.mediaTime < 0 {
		return nil, nil
	}
	return e, nil
}

func parseMDHD(b []byte) uint32 {
	if len(b) < 16 {
		return 0
	}
	if b[0] == 1 {
		if len(b) < 24 {
			return 0
		}
		return binary.BigEndian.Uint32(b[20:24])
	}
	return binary.BigEndian.Uint32(b[12:16])
}

func editPresentation(e *editList, movieTS uint32, rate int, deltas []int64) (priming, length int) {
	totalTicks := int64(0)
	for _, d := range deltas {
		totalTicks += d
	}
	length = int(totalTicks)
	if e == nil || e.segmentDur <= 0 || movieTS == 0 {
		return 0, length
	}
	priming = int(e.mediaTime)
	if priming < 0 {
		priming = 0
	}
	length = int(e.segmentDur * int64(rate) / int64(movieTS))
	if length <= 0 {
		length = int(totalTicks)
	}
	return priming, length
}

func parseSTSD(b []byte) (asc []byte, rate uint32, channels uint16, err error) {
	if len(b) < 16 {
		return nil, 0, 0, fmt.Errorf("%w: short stsd", ErrCorrupt)
	}
	entries, err := children(b[8:])
	if err != nil {
		return nil, 0, 0, err
	}
	for _, e := range entries {
		if e.typ != "mp4a" {
			continue
		}
		if len(e.body) < 28 {
			return nil, 0, 0, fmt.Errorf("%w: short mp4a sample entry", ErrCorrupt)
		}
		channels = binary.BigEndian.Uint16(e.body[16:18])
		rate = binary.BigEndian.Uint32(e.body[24:28]) >> 16
		kids, err := children(e.body[28:])
		if err != nil {
			return nil, 0, 0, err
		}
		for _, k := range kids {
			if k.typ == "esds" {
				if asc, err = esdsASC(k.body); err != nil {
					return nil, 0, 0, err
				}
				return asc, rate, channels, nil
			}
		}
		return nil, 0, 0, fmt.Errorf("%w: mp4a has no esds", ErrCorrupt)
	}
	return nil, 0, 0, fmt.Errorf("%w: stsd has no mp4a entry", ErrCorrupt)
}

func esdsASC(b []byte) ([]byte, error) {
	if len(b) < 5 {
		return nil, fmt.Errorf("%w: short esds", ErrCorrupt)
	}
	p := 4
	for p < len(b) {
		tag := b[p]
		p++
		l, n, err := readVarint(b[p:])
		if err != nil {
			return nil, err
		}
		p += n
		if p+l > len(b) {
			return nil, fmt.Errorf("%w: descriptor 0x%02x claims %d bytes past the box", ErrCorrupt, tag, l)
		}
		switch tag {
		case 0x05:
			return append([]byte(nil), b[p:p+l]...), nil
		case 0x03:
			if l < 3 {
				return nil, fmt.Errorf("%w: short ES_Descriptor", ErrCorrupt)
			}
			p += 3
		case 0x04:
			if l < 13 {
				return nil, fmt.Errorf("%w: short DecoderConfigDescriptor", ErrCorrupt)
			}
			p += 13
		default:
			p += l
		}
	}
	return nil, fmt.Errorf("%w: no DecoderSpecificInfo in esds", ErrCorrupt)
}

func readVarint(b []byte) (val, n int, err error) {
	for i := 0; i < len(b); i++ {
		c := b[i]
		val = (val << 7) | int(c&0x7F)
		if c&0x80 == 0 {
			return val, i + 1, nil
		}
		if i >= 3 {
			return 0, 0, fmt.Errorf("%w: overlong descriptor length", ErrCorrupt)
		}
	}
	return 0, 0, fmt.Errorf("%w: truncated descriptor length", ErrCorrupt)
}

func parseSTTS(b []byte) ([]int64, error) {
	if len(b) < 8 {
		return nil, fmt.Errorf("%w: short stts", ErrCorrupt)
	}
	count := int(binary.BigEndian.Uint32(b[4:8]))
	if 8+count*8 > len(b) {
		return nil, fmt.Errorf("%w: stts claims %d entries", ErrCorrupt, count)
	}
	var out []int64
	p := 8
	for i := 0; i < count; i++ {
		n := int(binary.BigEndian.Uint32(b[p : p+4]))
		delta := int64(binary.BigEndian.Uint32(b[p+4 : p+8]))
		p += 8
		if n < 0 || n > 1<<24 {
			return nil, fmt.Errorf("%w: implausible stts run %d", ErrCorrupt, n)
		}
		for j := 0; j < n; j++ {
			out = append(out, delta)
		}
	}
	return out, nil
}

func parseSTSZ(b []byte) ([]int, error) {
	if len(b) < 12 {
		return nil, fmt.Errorf("%w: short stsz", ErrCorrupt)
	}
	uniform := binary.BigEndian.Uint32(b[4:8])
	count := int(binary.BigEndian.Uint32(b[8:12]))
	if count < 0 || count > 1<<24 {
		return nil, fmt.Errorf("%w: implausible sample count %d", ErrCorrupt, count)
	}
	if uniform != 0 {
		return make([]int, count), nil
	}
	if 12+count*4 > len(b) {
		return nil, fmt.Errorf("%w: stsz claims %d entries", ErrCorrupt, count)
	}
	out := make([]int, count)
	for i := 0; i < count; i++ {
		out[i] = int(binary.BigEndian.Uint32(b[12+i*4 : 16+i*4]))
	}
	return out, nil
}

func parseSTCO(b []byte, wide bool) ([]int64, error) {
	if len(b) < 8 {
		return nil, fmt.Errorf("%w: short chunk offset table", ErrCorrupt)
	}
	count := int(binary.BigEndian.Uint32(b[4:8]))
	entry := 4
	if wide {
		entry = 8
	}
	if 8+count*entry > len(b) {
		return nil, fmt.Errorf("%w: offset table claims %d entries", ErrCorrupt, count)
	}
	out := make([]int64, count)
	for i := 0; i < count; i++ {
		if wide {
			out[i] = int64(binary.BigEndian.Uint64(b[8+i*8 : 16+i*8]))
		} else {
			out[i] = int64(binary.BigEndian.Uint32(b[8+i*4 : 12+i*4]))
		}
	}
	return out, nil
}

type stscEntry struct {
	firstChunk, samples int
}

func parseSTSC(b []byte) ([]stscEntry, error) {
	if len(b) < 8 {
		return nil, fmt.Errorf("%w: short stsc", ErrCorrupt)
	}
	count := int(binary.BigEndian.Uint32(b[4:8]))
	if 8+count*12 > len(b) {
		return nil, fmt.Errorf("%w: stsc claims %d entries", ErrCorrupt, count)
	}
	out := make([]stscEntry, 0, count)
	p := 8
	for i := 0; i < count; i++ {
		out = append(out, stscEntry{
			firstChunk: int(binary.BigEndian.Uint32(b[p : p+4])),
			samples:    int(binary.BigEndian.Uint32(b[p+4 : p+8])),
		})
		p += 12
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%w: empty stsc", ErrCorrupt)
	}
	return out, nil
}

func readSamples(r io.ReadSeeker, sizes []int, chunks []int64, perChunk []stscEntry, deltas []int64) ([]Sample, error) {
	if len(sizes) == 0 {
		return nil, fmt.Errorf("%w: audio track has no samples", ErrCorrupt)
	}
	out := make([]Sample, 0, len(sizes))
	var dts int64
	idx := 0
	for ci, offset := range chunks {
		want := perChunk[len(perChunk)-1].samples
		for _, e := range perChunk {
			if e.firstChunk <= ci+1 {
				want = e.samples
			}
		}
		for s := 0; s < want && idx < len(sizes); s++ {
			size := sizes[idx]
			if size <= 0 || size > 1<<22 {
				return nil, fmt.Errorf("%w: implausible access unit size %d at %d", ErrCorrupt, size, idx)
			}
			if offset < 0 {
				return nil, fmt.Errorf("%w: negative chunk offset", ErrCorrupt)
			}
			if _, err := r.Seek(offset, io.SeekStart); err != nil {
				return nil, err
			}
			data := make([]byte, size)
			if _, err := io.ReadFull(r, data); err != nil {
				return nil, fmt.Errorf("%w: reading access unit %d: %v", ErrCorrupt, idx, err)
			}
			out = append(out, Sample{Data: data, DTS: dts})
			if idx < len(deltas) {
				dts += deltas[idx]
			}
			offset += int64(size)
			idx++
		}
	}
	if idx != len(sizes) {
		return nil, fmt.Errorf("%w: chunk table covers %d of %d access units",
			ErrCorrupt, idx, len(sizes))
	}
	return out, nil
}

func Decode(t *Track) ([]byte, error) {
	if t == nil || len(t.Samples) == 0 {
		return nil, fmt.Errorf("%w: no access units", ErrCorrupt)
	}
	var framed []byte
	for _, s := range t.Samples {
		if len(s.Data) > 0xFFFF {
			return nil, fmt.Errorf("%w: access unit of %d bytes overflows go-aac's 16-bit framing",
				ErrCorrupt, len(s.Data))
		}
		var hdr [2]byte
		binary.BigEndian.PutUint16(hdr[:], uint16(len(s.Data)))
		framed = append(framed, hdr[:]...)
		framed = append(framed, s.Data...)
	}

	pcm, info, err := aacpcm.DecodeInterleaved(
		&reader{b: framed}, aacpcm.WithRawStream(t.ASC))
	if err != nil {
		return nil, mapDecodeErr(err)
	}
	if t.SampleRate > 0 && info.SampleRate != t.SampleRate {
		return nil, fmt.Errorf("%w: decoded at %d Hz, track says %d",
			ErrCorrupt, info.SampleRate, t.SampleRate)
	}

	frame := 2 * t.Channels
	if frame == 0 {
		return nil, fmt.Errorf("%w: zero channels", ErrCorrupt)
	}
	start := t.Priming * frame
	end := start + t.Length*frame
	if start < 0 || end > len(pcm) || start > end {
		return nil, fmt.Errorf("%w: decoded %d bytes but the presentation window is [%d:%d] "+
			"(priming %d, length %d)",
			ErrCorrupt, len(pcm), start, end, t.Priming, t.Length)
	}
	return pcm[start:end], nil
}

func mapDecodeErr(err error) error {
	switch {
	case errors.Is(err, aacpcm.ErrUnsupportedSBR), errors.Is(err, aacpcm.ErrUnsupported):
		return fmt.Errorf("%w: %v", ErrUnsupported, err)
	case errors.Is(err, aacpcm.ErrCorruptStream):
		return fmt.Errorf("%w: %v", ErrCorrupt, err)
	default:
		return fmt.Errorf("%w: %v", ErrCorrupt, err)
	}
}

func ascInfo(asc []byte) (rate, channels int, err error) {
	if len(asc) < 2 {
		return 0, 0, fmt.Errorf("%w: AudioSpecificConfig is %d bytes", ErrCorrupt, len(asc))
	}
	aot := int(asc[0] >> 3)
	if aot == 31 {
		if len(asc) < 3 {
			return 0, 0, fmt.Errorf("%w: truncated escaped AudioObjectType", ErrCorrupt)
		}
		aot = 32 + int(asc[0]&0x7<<3) + int(asc[1]>>5)
	}
	if aot != 2 {
		return 0, 0, fmt.Errorf("%w: AudioObjectType %d (want AAC-LC = 2; HE-AAC/SBR is out of scope)",
			ErrUnsupported, aot)
	}
	sfi := int(asc[0]&0x7)<<1 | int(asc[1]>>7)
	chanCfg := int(asc[1]>>3) & 0xF
	switch {
	case sfi == 15:
		return 0, 0, fmt.Errorf("%w: explicitly coded sample rate is out of scope", ErrUnsupported)
	case sfi >= len(aacSampleRates):
		return 0, 0, fmt.Errorf("%w: reserved sample rate index %d", ErrCorrupt, sfi)
	}
	switch chanCfg {
	case 1, 2:
	default:
		return 0, 0, fmt.Errorf("%w: channel configuration %d (want mono or stereo)",
			ErrUnsupported, chanCfg)
	}
	return aacSampleRates[sfi], chanCfg, nil
}

func checkASC(asc []byte) error {
	_, _, err := ascInfo(asc)
	return err
}

var aacSampleRates = [13]int{
	96000, 88200, 64000, 48000, 44100, 32000, 24000,
	22050, 16000, 12000, 11025, 8000, 7350,
}

type reader struct {
	b []byte
}

func (r *reader) Read(p []byte) (int, error) {
	if len(r.b) == 0 {
		return 0, io.EOF
	}
	n := copy(p, r.b)
	r.b = r.b[n:]
	return n, nil
}
