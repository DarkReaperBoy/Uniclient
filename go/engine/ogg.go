package engine

import (
	"encoding/binary"
	"fmt"
	"io"
)

// Minimal Ogg container demuxer (RFC 3533) — exactly the subset needed
// to pull Opus packets out of downloaded voice notes and audio files
// (Telegram stores both as Ogg/Opus). Pages are verified with the Ogg
// CRC-32 variant (poly 0x04c11db7, MSB-first, init 0, no final xor);
// packets spanning page boundaries are reassembled via the lacing table.

const (
	oggMagic       = "OggS"
	oggHeaderLen   = 27
	oggMaxPageSize = 1 << 20 // 1 MiB: voice pages are ~4 KB
)

var oggCRCTable [256]uint32

func init() {
	for i := uint32(0); i < 256; i++ {
		r := i << 24
		for j := 0; j < 8; j++ {
			if r&0x80000000 != 0 {
				r = (r << 1) ^ 0x04c11db7
			} else {
				r <<= 1
			}
		}
		oggCRCTable[i] = r
	}
}

func oggCRC(data []byte) uint32 {
	var crc uint32
	for _, b := range data {
		crc = (crc << 8) ^ oggCRCTable[byte(crc>>24)^b]
	}
	return crc
}

// oggPage is one parsed page (header fields + payload).
type oggPage struct {
	headerType byte
	granule    int64
	serial     uint32
	seq        uint32
	payload    []byte
	lacing     []byte
}

// readOggPage reads and CRC-verifies the next page from r.
func readOggPage(r io.Reader, scratch []byte) (oggPage, error) {
	var head [oggHeaderLen]byte
	if _, err := io.ReadFull(r, head[:]); err != nil {
		if err == io.ErrUnexpectedEOF {
			return oggPage{}, fmt.Errorf("ogg: truncated page header")
		}
		return oggPage{}, err // clean io.EOF at a page boundary
	}
	if string(head[:4]) != oggMagic {
		return oggPage{}, fmt.Errorf("ogg: bad magic %q", string(head[:4]))
	}
	if head[4] != 0 {
		return oggPage{}, fmt.Errorf("ogg: unsupported stream version %d", head[4])
	}
	nsegs := int(head[26])
	if nsegs == 0 {
		return oggPage{}, fmt.Errorf("ogg: zero segments")
	}
	var segTbl [255]byte
	if _, err := io.ReadFull(r, segTbl[:nsegs]); err != nil {
		return oggPage{}, fmt.Errorf("ogg: truncated segment table: %w", err)
	}
	total := 0
	for i := 0; i < nsegs; i++ {
		total += int(segTbl[i])
	}
	if total > oggMaxPageSize {
		return oggPage{}, fmt.Errorf("ogg: page too large (%d bytes)", total)
	}
	if cap(scratch) < total {
		scratch = make([]byte, total)
	}
	payload := scratch[:total]
	if _, err := io.ReadFull(r, payload); err != nil {
		return oggPage{}, fmt.Errorf("ogg: truncated payload: %w", err)
	}

	// CRC over the whole page with the checksum field zeroed.
	saved := binary.LittleEndian.Uint32(head[22:26])
	binary.LittleEndian.PutUint32(head[22:26], 0)
	var page []byte
	page = append(page, head[:]...)
	page = append(page, segTbl[:nsegs]...)
	page = append(page, payload...)
	if got := oggCRC(page); got != saved {
		return oggPage{}, fmt.Errorf("ogg: crc mismatch (stored %08x, computed %08x)", saved, got)
	}

	return oggPage{
		headerType: head[5],
		granule:    int64(binary.LittleEndian.Uint64(head[6:14])),
		serial:     binary.LittleEndian.Uint32(head[14:18]),
		seq:        binary.LittleEndian.Uint32(head[18:22]),
		payload:    payload,
		lacing:     segTbl[:nsegs],
	}, nil
}

// oggPacketReader yields complete Ogg packets in stream order.
type oggPacketReader struct {
	r       io.Reader
	scratch []byte
	ready   [][]byte // completed packets from the last read page
	pending []byte   // bytes of a packet spanning page boundaries
	err     error
}

func newOggPacketReader(r io.Reader) *oggPacketReader {
	return &oggPacketReader{r: r, scratch: make([]byte, 0, 8192)}
}

// Next returns the next complete packet; io.EOF marks the stream end.
func (o *oggPacketReader) Next() ([]byte, error) {
	for {
		if len(o.ready) > 0 {
			pkt := o.ready[0]
			o.ready = o.ready[1:]
			return pkt, nil
		}
		if o.err != nil {
			return nil, o.err
		}
		if err := o.readPage(); err != nil {
			o.err = err
		}
	}
}

func (o *oggPacketReader) readPage() error {
	pg, err := readOggPage(o.r, o.scratch)
	if err != nil {
		return err
	}
	o.scratch = pg.payload[:cap(pg.payload)]
	off := 0
	for _, v := range pg.lacing {
		o.pending = append(o.pending, pg.payload[off:off+int(v)]...)
		off += int(v)
		if v < 255 {
			// Copy: the next packet reuses pending's backing array.
			pkt := make([]byte, len(o.pending))
			copy(pkt, o.pending)
			o.ready = append(o.ready, pkt)
			o.pending = o.pending[:0]
		}
	}
	return nil
}

// buildOggPage encodes packets into one Ogg page with a valid CRC —
// used by tests and fixtures.
func buildOggPage(packets [][]byte, granule int64, serial, seq uint32, last bool) []byte {
	var lacing []byte
	var payload []byte
	for _, p := range packets {
		n := len(p)
		for n >= 255 {
			lacing = append(lacing, 255)
			n -= 255
		}
		lacing = append(lacing, byte(n))
		payload = append(payload, p...)
	}
	var head [oggHeaderLen]byte
	copy(head[:4], oggMagic)
	head[4] = 0
	if last {
		head[5] = 0x04
	}
	binary.LittleEndian.PutUint64(head[6:14], uint64(granule))
	binary.LittleEndian.PutUint32(head[14:18], serial)
	binary.LittleEndian.PutUint32(head[18:22], seq)
	head[26] = byte(len(lacing))

	page := make([]byte, 0, oggHeaderLen+len(lacing)+len(payload))
	page = append(page, head[:]...)
	page = append(page, lacing...)
	page = append(page, payload...)
	binary.LittleEndian.PutUint32(page[22:26], oggCRC(page))
	return page
}
