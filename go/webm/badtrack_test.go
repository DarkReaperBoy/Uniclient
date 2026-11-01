package webm

import (
	"errors"
	"testing"
)

func TestMalformedTrackNumberIsAnErrorNotAnAbsentTrack(t *testing.T) {
	badTrack := el{id: idTrackEntry, sub: []el{
		{id: idTrackNumber, data: []byte{1, 2, 3, 4, 5, 6, 7, 8, 9}},
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
