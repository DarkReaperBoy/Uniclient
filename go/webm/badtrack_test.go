package webm

// tests-first for BUGS.md B-17 — a MALFORMED field must produce an
// error, not be silently converted into a different (fabricated) value.
//
// parseTrackEntry used to do `num, _ = q.readUint(s, e)`: a TrackNumber
// payload that isn't a legal EBML uint (1..8 bytes) became 0, which the
// track gate reads as "absent" — malformed input was indistinguishable
// from a file with no video track (§1.10: fail, don't fudge).

import (
	"errors"
	"testing"
)

func TestMalformedTrackNumberIsAnErrorNotAnAbsentTrack(t *testing.T) {
	badTrack := el{id: idTrackEntry, sub: []el{
		{id: idTrackNumber, data: []byte{1, 2, 3, 4, 5, 6, 7, 8, 9}}, // 9 bytes: not a legal EBML uint
		uintEl(idTrackUID, 1),
		uintEl(idTrackType, 1),
		strEl(idCodecID, "V_VP9"),
		el{id: idVideo, sub: []el{
			uintEl(idPixelWidth, 100),
			uintEl(idPixelHeight, 100),
		}},
	}}
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{badTrack}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0), simpleBlock(1, 0, flagKey, []byte{0x42})}},
	}}
	data := append(render(ebmlHeader()), render(segment)...)

	_, err := Parse(data)
	if !errors.Is(err, ErrBadElement) {
		t.Fatalf("malformed TrackNumber parsed as err=%v — garbage fields instead of a hard error (B-17); want ErrBadElement", err)
	}
}
