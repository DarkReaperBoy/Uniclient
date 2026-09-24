// Package webm implements a minimal pure-Go WebM/EBML reader scoped to
// single-video-track VP9 documents — the container of Telegram video
// stickers and video custom emoji. It parses the EBML element tree far
// enough to find the VP9 video track and every frame block, including:
//
//   - Cluster/Block/SimpleBlock timecodes (signed int16 block offsets,
//     TimecodeScale scaling to nanoseconds);
//   - all three lacing modes (Xiph, fixed, EBML) with ffmpeg-compatible
//     semantics (first EBML size = plain vint value, deltas as
//     value - (2^(7n-1) - 1); pinned by unit tests);
//   - the WebM VP9 alpha side stream (BlockGroup → BlockAdditions →
//     BlockMore → BlockAdditional with BlockAddID 1), returned per frame
//     as Frame.Alpha.
//
// Everything else (SeekHead, Cues, Tags, audio tracks, attachments,
// chapters) is skipped. Unknown-size Segment/Cluster elements (streamed
// files) are handled by treating the subtree as extending to the end of
// the data. The whole document must fit in memory — stickers are small.
package webm

import (
	"encoding/binary"
	"errors"
	"math"
	"sort"
)

// Errors reported by Parse.
var (
	ErrNotWebM    = errors.New("webm: not an EBML/WebM document")
	ErrNoVP9Track = errors.New("webm: no VP9 video track")
	ErrBadElement = errors.New("webm: malformed EBML element")
	ErrBadLacing  = errors.New("webm: malformed block lacing")
)

// Matroska/EBML element IDs this reader understands. Everything else is
// skipped opaquely (children never entered unless listed in walkDown).
const (
	idEBMLHeader      = 0x1A45DFA3
	idDocType         = 0x4282
	idSegment         = 0x18538067
	idVoid            = 0xEC
	idInfo            = 0x1549A966
	idTimecodeScale   = 0x2AD7B1
	idDuration        = 0x4489
	idTracks          = 0x1654AE6B
	idTrackEntry      = 0xAE
	idTrackNumber     = 0xD7
	idTrackType       = 0x83
	idCodecID         = 0x86
	idVideo           = 0xE0
	idPixelWidth      = 0xB0
	idPixelHeight     = 0xBA
	idDefaultDur      = 0x23E383
	idCluster         = 0x1F43B675
	idClusterTC       = 0xE7
	idSimpleBlock     = 0xA3
	idBlockGroup      = 0xA0
	idBlock           = 0xA1
	idBlockAdditions  = 0x75A1
	idBlockMore       = 0xA6
	idBlockAddID      = 0xEE
	idBlockAdditional = 0xA5
)

const defaultTimecodeScale = 1_000_000 // ns per timecode unit (Matroska default: 1ms)

// VideoTrack describes the single VP9 track of the document.
type VideoTrack struct {
	TrackNumber     uint64
	PixelWidth      int
	PixelHeight     int
	DefaultDuration uint64 // ns; 0 when the element is absent
}

// Frame is one video frame extracted from the container.
type Frame struct {
	TimecodeNs uint64 // absolute presentation time
	Payload    []byte // primary VP9 bitstream
	Alpha      []byte // VP9 alpha side-stream bitstream (nil when absent)
	Keyframe   bool
}

// Document is a parsed WebM file.
type Document struct {
	Track         VideoTrack
	TimecodeScale uint64 // ns per timecode unit
	DurationNs    uint64 // Info.Duration × scale; 0 when absent
	Frames        []Frame
}

// Parse reads a complete WebM document.
func Parse(data []byte) (*Document, error) {
	p := &parser{data: data}
	doc := &Document{TimecodeScale: defaultTimecodeScale}

	// Top level: EBML header, then (usually one) Segment.
	segStart, segEnd, sawSegment := -1, -1, false
	for p.pos < len(p.data) {
		id, ok := p.readID()
		if !ok {
			break // trailing garbage is tolerated
		}
		size, unk, ok := p.readSize()
		if !ok {
			return nil, ErrBadElement
		}
		// Top-level elements must be complete in the data: a Segment (or
		// header) claiming more bytes than the file has is a truncated
		// download — reject rather than render half a document.
		if !unk && p.pos+int(size) > len(p.data) {
			return nil, ErrBadElement
		}
		start, end := p.payloadRange(size, unk)
		switch id {
		case idEBMLHeader:
			if !p.checkDocType(start, end) {
				return nil, ErrNotWebM
			}
		case idSegment:
			if !sawSegment {
				segStart, segEnd, sawSegment = start, end, true
			}
		case idVoid:
			// skip
		}
		p.pos = end
	}
	if !sawSegment {
		return nil, ErrNotWebM
	}
	if segStart < 0 || segEnd > len(data) || segStart > segEnd {
		return nil, ErrBadElement
	}

	// Walk the Segment children.
	sp := &parser{data: data, pos: segStart}
	trackNum := uint64(0)
	for sp.pos < segEnd {
		id, ok := sp.readID()
		if !ok {
			break
		}
		size, unk, ok := sp.readSize()
		if !ok {
			return nil, ErrBadElement
		}
		start, end := sp.payloadRange(size, unk)
		if end > segEnd {
			end = segEnd
		}
		// readID/readSize may have run past the parent boundary: a
		// payload starting BEYOND the element end must never slice
		// [s:e] with s>e or walk q.pos backwards into a spin (B-38).
		if start > end {
			break
		}
		switch id {
		case idInfo:
			p.parseInfo(start, end, doc)
		case idTracks:
			tn, err := p.parseTracks(start, end, doc)
			if err != nil {
				return nil, err
			}
			trackNum = tn
		case idCluster:
			if trackNum == 0 {
				// Tracks must precede Clusters per spec; without a track
				// number blocks cannot be attributed. Keep scanning.
				break
			}
			p.parseCluster(start, end, trackNum, doc)
		}
		sp.pos = end
	}
	if trackNum == 0 {
		return nil, ErrNoVP9Track
	}
	sort.SliceStable(doc.Frames, func(i, j int) bool {
		return doc.Frames[i].TimecodeNs < doc.Frames[j].TimecodeNs
	})
	return doc, nil
}

// ── low-level EBML reading ────────────────────────────────────────────────

type parser struct {
	data []byte
	pos  int
}

// readID reads an EBML element ID (vint with the marker bit kept).
// IDs are 1-4 bytes; a leading zero byte is invalid (returns ok=false).
func (p *parser) readID() (id uint32, ok bool) {
	if p.pos >= len(p.data) {
		return 0, false
	}
	first := p.data[p.pos]
	if first == 0 {
		return 0, false
	}
	n := 1
	for mask := byte(0x80); first&mask == 0; mask >>= 1 {
		n++
		if n > 4 {
			return 0, false
		}
	}
	if p.pos+n > len(p.data) {
		return 0, false
	}
	var v uint32
	for i := 0; i < n; i++ {
		v = v<<8 | uint32(p.data[p.pos+i])
	}
	p.pos += n
	return v, true
}

// readSize reads an element size vint. All-value-bits-set is the unknown
// size (streaming) marker; ok=false marks invalid data.
func (p *parser) readSize() (size int64, unknown bool, ok bool) {
	if p.pos >= len(p.data) {
		return 0, false, false
	}
	first := p.data[p.pos]
	if first == 0 {
		return 0, false, false
	}
	n := 1
	for mask := byte(0x80); first&mask == 0; mask >>= 1 {
		n++
		if n > 8 {
			return 0, false, false
		}
	}
	if p.pos+n > len(p.data) {
		return 0, false, false
	}
	var v uint64
	for i := 0; i < n; i++ {
		v = v<<8 | uint64(p.data[p.pos+i])
	}
	p.pos += n
	v &^= uint64(1) << uint(7*n) // strip the length-marker bit (bit 7n)
	// All value bits set → unknown size.
	all := uint64(1)<<uint(7*n) - 1
	if v == all {
		return -1, true, true
	}
	if v > uint64(len(p.data)) {
		return 0, false, false // cannot possibly fit
	}
	return int64(v), false, true
}

// payloadRange computes [start, end) for an element payload of the given
// size; unknown sizes extend to the end of the data.
func (p *parser) payloadRange(size int64, unknown bool) (int, int) {
	start := p.pos
	if unknown || size < 0 {
		return start, len(p.data)
	}
	end := start + int(size)
	if end > len(p.data) {
		end = len(p.data) // truncated tail: parse what is there
	}
	return start, end
}

// readUint reads a big-endian unsigned integer of 1-8 bytes.
func (p *parser) readUint(start, end int) (uint64, bool) {
	n := end - start
	if n <= 0 || n > 8 {
		return 0, false
	}
	var v uint64
	for i := start; i < end; i++ {
		v = v<<8 | uint64(p.data[i])
	}
	return v, true
}

// readFloat reads a 4- or 8-byte big-endian IEEE float.
func (p *parser) readFloat(start, end int) (float64, bool) {
	n := end - start
	switch n {
	case 4:
		return float64(math.Float32frombits(binary.BigEndian.Uint32(p.data[start:]))), true
	case 8:
		return math.Float64frombits(binary.BigEndian.Uint64(p.data[start:])), true
	}
	return 0, false
}

// checkDocType verifies the EBML header declares doc type webm (matroska
// files with VP9 tracks are accepted too — same subtree shape).
func (p *parser) checkDocType(start, end int) bool {
	q := &parser{data: p.data, pos: start}
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			return false
		}
		size, unk, ok := q.readSize()
		if !ok {
			return false
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			return false // payload starts past the element — malformed, never slice [s:e] (B-38)
		}
		if id == idDocType {
			dt := string(p.data[s:e])
			return dt == "webm" || dt == "matroska"
		}
		q.pos = e
	}
	return false
}

// ── Info / Tracks ─────────────────────────────────────────────────────────

func (p *parser) parseInfo(start, end int, doc *Document) {
	q := &parser{data: p.data, pos: start}
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			return
		}
		size, unk, ok := q.readSize()
		if !ok {
			return
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			break // crossed the parent boundary (B-38) — no backward q.pos, no slices
		}
		switch id {
		case idTimecodeScale:
			if v, ok := q.readUint(s, e); ok && v > 0 {
				doc.TimecodeScale = v
			}
		case idDuration:
			if f, ok := q.readFloat(s, e); ok && f > 0 {
				doc.DurationNs = uint64(f * float64(doc.TimecodeScale))
			}
		}
		q.pos = e
	}
}

// parseTracks finds the first VP9 video track and records its metadata.
// Returns the chosen track number (0 when none found).
func (p *parser) parseTracks(start, end int, doc *Document) (uint64, error) {
	q := &parser{data: p.data, pos: start}
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			break
		}
		size, unk, ok := q.readSize()
		if !ok {
			return 0, ErrBadElement
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			break // crossed the parent boundary (B-38)
		}
		if id == idTrackEntry {
			tn, terr := p.parseTrackEntry(s, e, doc)
			if terr != nil {
				return 0, terr // malformed field: hard error, never a fabricated value (B-17)
			}
			if tn != 0 {
				return tn, nil
			}
		}
		q.pos = e
	}
	return 0, nil
}

// parseTrackEntry returns the track number when this entry is a VP9
// video track, filling doc.Track. A malformed field is a hard error —
// never a fabricated zero that the track gate would read as "absent"
// (B-17; §1.10 fail-don't-fudge).
func (p *parser) parseTrackEntry(start, end int, doc *Document) (uint64, error) {
	q := &parser{data: p.data, pos: start}
	num, trackType := uint64(0), uint64(0)
	codec := ""
	w, h, defDur := 0, 0, uint64(0)
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			break
		}
		size, unk, ok := q.readSize()
		if !ok {
			return 0, ErrBadElement
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			// readID/readSize ran past this track entry's end — malformed
			// structure, hard error (B-17 doctrine): the raw slices below
			// ([s:e]) would otherwise panic with s>e (B-39, fuzz-found).
			return 0, ErrBadElement
		}
		switch id {
		case idTrackNumber:
			v, ok := q.readUint(s, e)
			if !ok {
				return 0, ErrBadElement // e.g. a 9-byte "uint": malformed, not 0
			}
			num = v
		case idTrackType:
			v, ok := q.readUint(s, e)
			if !ok {
				return 0, ErrBadElement
			}
			trackType = v
		case idCodecID:
			codec = string(p.data[s:e])
		case idDefaultDur:
			v, ok := q.readUint(s, e)
			if !ok {
				return 0, ErrBadElement
			}
			defDur = v
		case idVideo:
			vq := &parser{data: p.data, pos: s}
			for vq.pos < e {
				vid, ok := vq.readID()
				if !ok {
					break
				}
				vsize, vunk, ok := vq.readSize()
				if !ok {
					break
				}
				vs, ve := vq.payloadRange(vsize, vunk)
				if ve > e {
					ve = e
				}
				if vs > ve {
					break // parent boundary crossed (B-38) — readUint would refuse, but vq.pos must not step back
				}
				switch vid {
				case idPixelWidth:
					if v, ok := vq.readUint(vs, ve); ok {
						w = int(v)
					}
				case idPixelHeight:
					if v, ok := vq.readUint(vs, ve); ok {
						h = int(v)
					}
				}
				vq.pos = ve
			}
		}
		q.pos = e
	}
	if trackType != 1 || codec != "V_VP9" || num == 0 {
		return 0, nil // a DIFFERENT/absent track is not an error
	}
	doc.Track = VideoTrack{
		TrackNumber:     num,
		PixelWidth:      w,
		PixelHeight:     h,
		DefaultDuration: defDur,
	}
	return num, nil
}

// ── Clusters & Blocks ─────────────────────────────────────────────────────

func (p *parser) parseCluster(start, end int, trackNum uint64, doc *Document) {
	q := &parser{data: p.data, pos: start}
	clusterTC := int64(0)
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			return
		}
		size, unk, ok := q.readSize()
		if !ok {
			return
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			break // crossed the parent boundary (B-38)
		}
		switch id {
		case idClusterTC:
			if v, ok := q.readUint(s, e); ok {
				clusterTC = int64(v)
			}
		case idSimpleBlock:
			p.parseBlock(s, e, trackNum, clusterTC, true, doc)
		case idBlockGroup:
			p.parseBlockGroup(s, e, trackNum, clusterTC, doc)
		}
		q.pos = e
	}
}

// parseBlockGroup extracts Block + the VP9 alpha side stream.
func (p *parser) parseBlockGroup(start, end int, trackNum uint64, clusterTC int64, doc *Document) {
	q := &parser{data: p.data, pos: start}
	var blockStart, blockEnd int
	var alpha []byte
	haveBlock := false
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			return
		}
		size, unk, ok := q.readSize()
		if !ok {
			return
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			break // crossed the parent boundary (B-38)
		}
		switch id {
		case idBlock:
			blockStart, blockEnd, haveBlock = s, e, true
		case idBlockAdditions:
			aq := &parser{data: p.data, pos: s}
			for aq.pos < e {
				aid, ok := aq.readID()
				if !ok {
					break
				}
				asize, aunk, ok := aq.readSize()
				if !ok {
					break
				}
				as, ae := aq.payloadRange(asize, aunk)
				if ae > e {
					ae = e
				}
				if as > ae {
					break // parent boundary crossed (B-38) — aq.pos must not step back
				}
				if aid == idBlockMore {
					alpha = p.parseBlockMore(as, ae)
				}
				aq.pos = ae
			}
		}
		q.pos = e
	}
	if !haveBlock {
		return
	}
	p.parseBlockWithAlpha(blockStart, blockEnd, trackNum, clusterTC, alpha, doc)
}

// parseBlockMore returns the BlockAdditional payload when BlockAddID is 1
// (the WebM VP9 alpha channel slot).
func (p *parser) parseBlockMore(start, end int) []byte {
	q := &parser{data: p.data, pos: start}
	addID := uint64(0)
	var additional []byte
	for q.pos < end {
		id, ok := q.readID()
		if !ok {
			break
		}
		size, unk, ok := q.readSize()
		if !ok {
			break
		}
		s, e := q.payloadRange(size, unk)
		if e > end {
			e = end
		}
		if s > e {
			break // crossed the parent boundary (B-38) — guards the raw slice below too
		}
		switch id {
		case idBlockAddID:
			// Lenient ON PURPOSE: BlockAdditions is optional alpha — a
			// malformed add-id must degrade to "no alpha" (identical to
			// absence), never to fabricated bytes (B-17 audit note: the
			// track-entry fields above do NOT get this treatment because
			// their zeros drive decisions).
			addID, _ = q.readUint(s, e)
		case idBlockAdditional:
			additional = p.data[s:e]
		}
		q.pos = e
	}
	if addID != 1 {
		return nil
	}
	return additional
}

// parseBlock decodes a SimpleBlock: [track vint][int16 tc][flags][data].
func (p *parser) parseBlock(start, end int, trackNum uint64, clusterTC int64, simple bool, doc *Document) {
	p.parseBlockWithAlpha(start, end, trackNum, clusterTC, nil, doc)
}

func (p *parser) parseBlockWithAlpha(start, end int, trackNum uint64, clusterTC int64, alpha []byte, doc *Document) {
	q := &parser{data: p.data, pos: start}
	// Track number: vint.
	tn, _, ok := q.readSize() // same shape (marker-stripped vint)
	if !ok || tn != int64(trackNum) {
		return
	}
	if q.pos+3 > end {
		return
	}
	tc := int64(int16(binary.BigEndian.Uint16(p.data[q.pos:])))
	q.pos += 2
	flags := p.data[q.pos]
	q.pos++
	scale := doc.TimecodeScale
	abs := clusterTC + tc
	if abs < 0 {
		abs = 0
	}
	tns := uint64(abs) * scale
	if alpha == nil && flags&0x06 == 0 {
		// No lacing, no alpha: payload is the rest.
		payload := p.data[q.pos:end]
		if len(payload) == 0 {
			return
		}
		doc.Frames = append(doc.Frames, Frame{
			TimecodeNs: tns,
			Payload:    payload,
			Keyframe:   flags&0x80 != 0,
		})
		return
	}
	// Laced: split into frames (alpha pairs only occur with single-frame
	// blocks in practice; the laced path assigns alpha to the first frame).
	frames := p.splitLaced(q.pos, end, flags)
	for i, f := range frames {
		if len(f) == 0 {
			continue
		}
		fr := Frame{
			TimecodeNs: tns,
			Payload:    f,
			Keyframe:   flags&0x80 != 0,
		}
		if i == 0 && len(alpha) > 0 {
			fr.Alpha = alpha
		}
		doc.Frames = append(doc.Frames, fr)
	}
}

// splitLaced splits the block payload into frames per the lacing mode in
// the flags (bits 1-2). ffmpeg-compatible semantics; see package comment.
func (p *parser) splitLaced(start, end int, flags byte) [][]byte {
	mode := (flags >> 1) & 0x3
	if mode == 0 {
		if start >= end {
			return nil
		}
		return [][]byte{p.data[start:end]}
	}
	if start >= end {
		return nil
	}
	count := int(p.data[start]) + 1
	pos := start + 1
	if count <= 0 || count > 256 {
		return nil
	}
	sizes := make([]int, count)
	switch mode {
	case 1: // Xiph
		total := 0
		for i := 0; i < count-1; i++ {
			sz := 0
			for {
				if pos >= end {
					return nil
				}
				b := int(p.data[pos])
				pos++
				sz += b
				if b != 0xFF {
					break
				}
			}
			sizes[i] = sz
			total += sz
		}
		if end-pos < total {
			return nil
		}
		sizes[count-1] = end - pos - total
	case 2: // fixed
		if (end-pos)%count != 0 {
			return nil
		}
		sz := (end - pos) / count
		for i := range sizes {
			sizes[i] = sz
		}
	case 3: // EBML
		// First size: plain vint value. Deltas: value - (2^(7n-1) - 1).
		v, n, ok := readVintValue(p.data[pos:end])
		if !ok {
			return nil
		}
		pos += n
		sizes[0] = int(v)
		total := sizes[0]
		for i := 1; i < count-1; i++ {
			v, n, ok := readVintValue(p.data[pos:end])
			if !ok {
				return nil
			}
			pos += n
			delta := int64(v) - (int64(1)<<uint(7*n-1) - 1)
			sizes[i] = sizes[i-1] + int(delta)
			if sizes[i] < 0 {
				return nil
			}
			total += sizes[i]
		}
		if end-pos < total {
			return nil
		}
		sizes[count-1] = end - pos - total
	}
	out := make([][]byte, 0, count)
	for _, sz := range sizes {
		if sz < 0 || pos+sz > end {
			return nil
		}
		out = append(out, p.data[pos:pos+sz])
		pos += sz
	}
	return out
}

// readVintValue reads a marker-stripped EBML vint from data, returning
// the value and length in bytes.
func readVintValue(data []byte) (uint64, int, bool) {
	if len(data) == 0 || data[0] == 0 {
		return 0, 0, false
	}
	n := 1
	for mask := byte(0x80); data[0]&mask == 0; mask >>= 1 {
		n++
		if n > 8 || n > len(data) {
			return 0, 0, false
		}
	}
	var v uint64
	for i := 0; i < n; i++ {
		v = v<<8 | uint64(data[i])
	}
	v &^= uint64(1) << uint(7*n) // strip the length-marker bit (bit 7n)
	return v, n, true
}
