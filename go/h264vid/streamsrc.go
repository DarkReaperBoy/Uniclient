package h264vid

import (
	"encoding/binary"
	"fmt"
	"io"
	"time"

	"github.com/Eyevinn/mp4ff/mp4"
	govid "github.com/liqmix/govid"
)

type fileSource interface {
	io.ReaderAt
	io.ReadSeeker
}

type moovInfo struct {
	ranges    []mp4.DataRange
	sps, pps  []byte
	stts      *mp4.SttsBox
	ctts      *mp4.CttsBox
	total     uint32
	timescale uint32
	syncSet   map[uint32]bool
}

func (m *moovInfo) isSync(sample uint32) bool {
	if len(m.syncSet) == 0 {
		return true
	}
	return m.syncSet[sample]
}

func (m *moovInfo) ptsOf(sample uint32) time.Duration {
	decTime, _ := m.stts.GetDecodeTime(sample)
	comp := int64(decTime)
	if m.ctts != nil {
		comp += int64(m.ctts.GetCompositionTimeOffset(sample))
	}
	return time.Duration(float64(comp) / float64(m.timescale) * float64(time.Second))
}

func ParseSeek(r fileSource) (*Video, error) {
	if r == nil {
		return nil, ErrNotVideo
	}
	return parseSource(r)
}

func parseSource(r fileSource) (*Video, error) {
	f, err := mp4.DecodeFile(r, mp4.WithDecodeMode(mp4.DecModeLazyMdat))
	if err != nil {
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

	order := make([]indexSample, 0, m.total)
	for s := uint32(1); s <= m.total; s++ {
		order = append(order, indexSample{
			pts:    m.ptsOf(s),
			sync:   m.isSync(s),
			decode: s,
		})
	}

	container := time.Duration(float64(trak.Mdia.Mdhd.Duration) / float64(m.timescale) * float64(time.Second))
	if err := v.finishTimeline(order, container); err != nil {
		return nil, err
	}
	return v, nil
}

type packetSrc struct {
	ra io.ReaderAt
	m  *moovInfo
	n  uint32
}

func (v *Video) packetSrc() *packetSrc {
	return &packetSrc{ra: v.ra, m: v.moov, n: 1}
}

func (p *packetSrc) skip(k uint32) {
	if k == 0 {
		return
	}
	end := p.n + k
	if end > p.m.total+1 {
		end = p.m.total + 1
	}
	p.n = end
}

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

func lengthPrefix(nalu []byte) []byte {
	buf := make([]byte, 4+len(nalu))
	binary.BigEndian.PutUint32(buf, uint32(len(nalu)))
	copy(buf[4:], nalu)
	return buf
}
