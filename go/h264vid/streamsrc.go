package h264vid

// streamsrc.go — slice 229: the container layer that can sit on a
// fetch-on-read stream (parity row 281, "playback without full
// download").
//
// Why a second container path exists: the govid demuxer this package
// started on reads the ENTIRE file during construction — measured,
// not assumed: mp4.DecodeFile walks into mdat and pulls 100% of the
// bytes (11 926 of 11 926, zero seeks, on our round-video fixture —
// mdat sits before moov). Its index pass then reads every sample
// payload again just to record timestamps. Both habits are fatal on a
// stream whose ReadAt fetches 512 KiB per miss.
//
// So this file does what the demuxer did, in the only shape that can
// stream:
//
//   - mp4ff with DecModeLazyMdat: box headers and moov are parsed,
//     mdat is SEEKED over — parse reads ~950 bytes of an 11 926-byte
//     file (pinned by TestParseSeekReadsNoPayload);
//   - a table-driven packet pump: sample offsets come from
//     stsc/stco/stsz, timestamps from stts+ctts exactly as govid
//     computed them (same mp4ff functions, same float expression —
//     TestPacketPumpMatchesGovidDemuxer pins byte-identical packets),
//     and each payload is ReadAt only when the decoder asks.
//
// A GOP resume is metadata-only: skip touches no payload, so seeking
// to a later keyframe never fetches the samples it skips (the old
// demuxer read and discarded them).

import (
	"encoding/binary"
	"fmt"
	"io"
	"time"

	"github.com/Eyevinn/mp4ff/mp4"
	govid "github.com/liqmix/govid"
)

// fileSource is a payload source with both sequential access (mp4ff's
// lazy parse seeks through box headers) and random access (sample
// payloads). os.File, bytes.Reader and *io.SectionReader all satisfy
// it — the last is what the engine's streaming reader hands over.
type fileSource interface {
	io.ReaderAt
	io.ReadSeeker
}

// moovInfo holds everything playback needs from the moov box.
type moovInfo struct {
	ranges    []mp4.DataRange // sample s (1-based) lives in ranges[s-1]
	sps, pps  []byte          // length-prefixed parameter sets, govid's format
	stts      *mp4.SttsBox
	ctts      *mp4.CttsBox
	total     uint32
	timescale uint32
	syncSet   map[uint32]bool // empty ⇒ every sample is a sync sample (govid's rule)
}

// isSync replicates govid's rule exactly: no stss box means all
// samples are sync samples.
func (m *moovInfo) isSync(sample uint32) bool {
	if len(m.syncSet) == 0 {
		return true
	}
	return m.syncSet[sample]
}

// ptsOf is govid's timestamp expression verbatim (decode time + ctts
// offset, divided by timescale in float) — identical math on both
// sides of the refactor is what makes packet equality exact.
func (m *moovInfo) ptsOf(sample uint32) time.Duration {
	decTime, _ := m.stts.GetDecodeTime(sample)
	comp := int64(decTime)
	if m.ctts != nil {
		comp += int64(m.ctts.GetCompositionTimeOffset(sample))
	}
	return time.Duration(float64(comp) / float64(m.timescale) * float64(time.Second))
}

// ParseSeek parses an MP4 from a seekable, random-access source
// WITHOUT reading payload bytes. This is the entry point a streamed
// (not yet downloaded) video uses; Parse (the []byte path) goes
// through the very same parseSource.
func ParseSeek(r fileSource) (*Video, error) {
	if r == nil {
		return nil, ErrNotVideo
	}
	return parseSource(r)
}

// parseSource is the one container path for both byte and stream
// inputs: lazy moov parse → table index → shared timeline build.
func parseSource(r fileSource) (*Video, error) {
	f, err := mp4.DecodeFile(r, mp4.WithDecodeMode(mp4.DecModeLazyMdat))
	if err != nil {
		// Decode-stage failure: on a stream this is usually a dead read,
		// not a verdict about the bytes (slice 230 — IsPermanent classifies
		// it retryable, so one failed fetch cannot pin the clip dead).
		return nil, fmt.Errorf("%w: %w: %v", ErrNotVideo, ErrDecodeFailed, err)
	}
	if f.Moov == nil {
		return nil, fmt.Errorf("%w: no moov box", ErrNotVideo)
	}

	var trak *mp4.TrakBox
	for _, t := range f.Moov.Traks {
		if t.Mdia != nil && t.Mdia.Hdlr != nil && t.Mdia.Hdlr.HandlerType == "vide" {
			trak = t
			break
		}
	}
	if trak == nil || trak.Mdia == nil || trak.Mdia.Minf == nil || trak.Mdia.Minf.Stbl == nil {
		return nil, fmt.Errorf("%w: no video track", ErrNotVideo)
	}
	stbl := trak.Mdia.Minf.Stbl
	if stbl.Stsd == nil || stbl.Stsd.AvcX == nil {
		return nil, fmt.Errorf("%w: no avc1 track", ErrUnsupported)
	}
	avcX := stbl.Stsd.AvcX
	if avcX.AvcC == nil {
		return nil, fmt.Errorf("%w: no avcC box", ErrNotVideo)
	}
	dcr := avcX.AvcC.DecConfRec
	if len(dcr.SPSnalus) == 0 {
		return nil, fmt.Errorf("%w: no SPS in avcC", ErrNotVideo)
	}
	if len(dcr.PPSnalus) == 0 {
		return nil, fmt.Errorf("%w: no PPS in avcC", ErrNotVideo)
	}
	if stbl.Stts == nil || stbl.Stsz == nil {
		return nil, fmt.Errorf("%w: no timing/size tables", ErrNotVideo)
	}
	if trak.Mdia.Mdhd == nil || trak.Mdia.Mdhd.Timescale == 0 {
		return nil, fmt.Errorf("%w: no media timescale", ErrNotVideo)
	}

	m := &moovInfo{
		sps:       lengthPrefix(dcr.SPSnalus[0]),
		pps:       lengthPrefix(dcr.PPSnalus[0]),
		stts:      stbl.Stts,
		ctts:      stbl.Ctts,
		total:     stbl.Stsz.GetNrSamples(),
		timescale: trak.Mdia.Mdhd.Timescale,
	}
	if m.total == 0 {
		return nil, fmt.Errorf("%w: no samples", ErrNotVideo)
	}
	if stbl.Stss != nil {
		m.syncSet = make(map[uint32]bool, stbl.Stss.EntryCount())
		for _, sn := range stbl.Stss.SampleNumber {
			m.syncSet[sn] = true
		}
	}

	// Per-sample byte ranges, computed once from stsc/stco/stsz — the
	// same table walk govid's demuxer did per packet, but as metadata.
	m.ranges = make([]mp4.DataRange, m.total)
	for s := uint32(1); s <= m.total; s++ {
		rngs, err := trak.GetRangesForSampleInterval(s, s)
		if err != nil {
			return nil, fmt.Errorf("%w: sample %d range: %v", ErrNotVideo, s, err)
		}
		if len(rngs) == 0 {
			return nil, fmt.Errorf("%w: no data range for sample %d", ErrNotVideo, s)
		}
		m.ranges[s-1] = rngs[0]
	}

	v := &Video{
		Width:  int(avcX.Width),
		Height: int(avcX.Height),
		ra:     r,
		moov:   m,
	}
	if err := v.validateDims(); err != nil {
		return nil, err
	}

	// Index pass over TABLES ONLY — no payload is touched. The old
	// index walk called NextPacket per sample and therefore read the
	// whole mdat twice per parse.
	order := make([]indexSample, 0, m.total)
	for s := uint32(1); s <= m.total; s++ {
		order = append(order, indexSample{
			pts:    m.ptsOf(s),
			sync:   m.isSync(s),
			decode: s,
		})
	}

	// Container duration, govid's mdhd expression.
	container := time.Duration(float64(trak.Mdia.Mdhd.Duration) / float64(m.timescale) * float64(time.Second))
	if err := v.finishTimeline(order, container); err != nil {
		return nil, err
	}
	return v, nil
}

// packetSrc is one decode session's view of the samples: positions at
// sample n (1-based), reads payloads on demand.
type packetSrc struct {
	ra io.ReaderAt
	m  *moovInfo
	n  uint32 // next sample to deliver
}

// packetSrc starts a fresh session at sample 1.
func (v *Video) packetSrc() *packetSrc {
	return &packetSrc{ra: v.ra, m: v.moov, n: 1}
}

// skip advances past samples WITHOUT reading their payloads — pure
// metadata. Positioning at a later keyframe therefore fetches zero
// bytes (the old demuxer read and discarded each skipped payload).
func (p *packetSrc) skip(k uint32) {
	if k == 0 {
		return
	}
	end := p.n + k // n may legitimately land one past the end: next() then EOFs
	if end > p.m.total+1 {
		end = p.m.total + 1
	}
	p.n = end
}

// next delivers the next packet in decode order with govid's exact
// semantics: payload via ReadAt (fetch-on-read), timestamp as
// decode+composition over timescale, and SPS/PPS prepended to sync
// samples so a fresh codec can start mid-file.
func (p *packetSrc) next() (govid.Packet, error) {
	m := p.m
	if p.n == 0 {
		p.n = 1
	}
	if p.n > m.total {
		return govid.Packet{}, io.EOF
	}
	s := p.n
	rng := m.ranges[s-1]
	data := make([]byte, rng.Size)
	if _, err := p.ra.ReadAt(data, int64(rng.Offset)); err != nil {
		return govid.Packet{}, fmt.Errorf("read sample %d: %w", s, err)
	}

	keyframe := m.isSync(s)
	if keyframe {
		prefixed := make([]byte, len(m.sps)+len(m.pps)+len(data))
		n := copy(prefixed, m.sps)
		n += copy(prefixed[n:], m.pps)
		copy(prefixed[n:], data)
		data = prefixed
	}
	p.n++
	return govid.Packet{
		Data:      data,
		Timestamp: m.ptsOf(s),
		Keyframe:  keyframe,
	}, nil
}

// lengthPrefix wraps a raw NAL with the 4-byte big-endian length
// prefix govid's codec consumes (its demuxer did the same).
func lengthPrefix(nalu []byte) []byte {
	buf := make([]byte, 4+len(nalu))
	binary.BigEndian.PutUint32(buf, uint32(len(nalu)))
	copy(buf[4:], nalu)
	return buf
}
