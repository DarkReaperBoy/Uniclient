package cores

import "testing"

// F-81 (slice 317): extractAttachments len-guarded the photo array but
// BARE-asserted the element type — a hostile/malformed Bale server
// sending `"photo": ["not-a-map"]` hit
// photos[len(photos)-1].(map[string]interface{}) → index-safe but
// TYPE-unsafe → interface-conversion PANIC = remote client crash
// (the F-79 class, one assertion over).
//
// Behavioral RED (WORKLOG 317): pre-fix the first test dies with
// interface conversion: interface {} is string, not map[string]interface{}.

func TestExtractAttachmentsRejectsNonMapPhotoElement(t *testing.T) {
	b := &BaleCore{}
	atts := b.extractAttachments(map[string]interface{}{
		"photo": []interface{}{"hostile-element"},
	})
	if len(atts) != 0 {
		t.Fatalf("hostile photo element produced %d attachments, want 0", len(atts))
	}
}

func TestExtractAttachmentsAcceptsRealPhotoElement(t *testing.T) {
	b := &BaleCore{}
	atts := b.extractAttachments(map[string]interface{}{
		"photo": []interface{}{
			map[string]interface{}{"file_id": "small"},
			map[string]interface{}{
				"file_id": "big", "file_size": float64(1234),
				"width": float64(640), "height": float64(480),
			},
		},
	})
	if len(atts) != 1 {
		t.Fatalf("got %d attachments, want 1", len(atts))
	}
	a := atts[0]
	if a.ID != "big" || a.Size != 1234 || a.Width != 640 || a.Height != 480 {
		t.Fatalf("attachment = %+v", a)
	}
}
