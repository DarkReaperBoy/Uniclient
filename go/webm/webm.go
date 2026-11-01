package webm

import (
	"encoding/binary"
	"errors"
	"math"
	"sort"
)

var (
	ErrNotWebM    = errors.New("webm: not an EBML/WebM document")
	ErrNoVP9Track = errors.New("webm: no VP9 video track")
	ErrBadElement = errors.New("webm: malformed EBML element")
	ErrBadLacing  = errors.New("webm: malformed block lacing")
)

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

const defaultTimecodeScale = 1_000_000

type VideoTrack struct {
	TrackNumber     uint64
	PixelWidth      int
	PixelHeight     int
	DefaultDuration uint64
}

type Frame struct {
	TimecodeNs uint64
	Payload    []byte
	Alpha      []byte
	Keyframe   bool
}

type Document struct {
	Track         VideoTrack
	TimecodeScale uint64
	DurationNs    uint64
	Frames        []Frame
}

func Parse(data []byte) (*Document, error) {
	p := &parser{data: data}
	doc := &Document{TimecodeScale: defaultTimecodeScale}

	segStart, segEnd, sawSegment := -1, -1, false
	for p.pos < len(p.data) {
		id, ok := p.readID()
		if !ok {
			break
		}
		size, unk, ok := p.readSize()
		if !ok {
			return nil, ErrBadElement
		}
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
		}
		p.pos = end
	}
	if !sawSegment {
		return nil, ErrNotWebM
	}
	if segStart < 0 || segEnd > len(data) || segStart > segEnd {
		return nil, ErrBadElement
	}

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

type parser struct {
	data []byte
	pos  int
}

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
	v &^= uint64(1) << uint(7*n)
	all := uint64(1)<<uint(7*n) - 1
	if v == all {
		return -1, true, true
	}
	if v > uint64(len(p.data)) {
		return 0, false, false
	}
	return int64(v), false, true
}

func (p *parser) payloadRange(size int64, unknown bool) (int, int) {
	start := p.pos
	if unknown || size < 0 {
		return start, len(p.data)
	}
	end := start + int(size)
	if end > len(p.data) {
		end = len(p.data)
	}
	return start, end
}

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
			return false
		}
		if id == idDocType {
			dt := string(p.data[s:e])
			return dt == "webm" || dt == "matroska"
		}
		q.pos = e
	}
	return false
}

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
			break
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
			break
		}
		if id == idTrackEntry {
			tn, terr := p.parseTrackEntry(s, e, doc)
			if terr != nil {
				return 0, terr
			}
			if tn != 0 {
				return tn, nil
			}
		}
		q.pos = e
	}
	return 0, nil
}

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
			return 0, ErrBadElement
		}
		switch id {
		case idTrackNumber:
			v, ok := q.readUint(s, e)
			if !ok {
				return 0, ErrBadElement
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
					break
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
		return 0, nil
	}
	doc.Track = VideoTrack{
		TrackNumber:     num,
		PixelWidth:      w,
		PixelHeight:     h,
		DefaultDuration: defDur,
	}
	return num, nil
}

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
			break
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
			break
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
					break
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
			break
		}
		switch id {
		case idBlockAddID:
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

func (p *parser) parseBlock(start, end int, trackNum uint64, clusterTC int64, simple bool, doc *Document) {
	p.parseBlockWithAlpha(start, end, trackNum, clusterTC, nil, doc)
}

func (p *parser) parseBlockWithAlpha(start, end int, trackNum uint64, clusterTC int64, alpha []byte, doc *Document) {
	q := &parser{data: p.data, pos: start}
	tn, _, ok := q.readSize()
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
	case 1:
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
	case 2:
		if (end-pos)%count != 0 {
			return nil
		}
		sz := (end - pos) / count
		for i := range sizes {
			sizes[i] = sz
		}
	case 3:
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
	v &^= uint64(1) << uint(7*n)
	return v, n, true
}
