package tests

import (
	"testing"
	. "uniclient/cores"
)

func TestExtractAttachmentsRejectsNonMapPhotoElement(t *testing.T) {
	b := &BaleCore{}
	atts := b.ExtractAttachments(map[string]interface{}{
		"photo": []interface{}{"hostile-element"},
	})
	if len(atts) != 0 {
		t.Fatalf("hostile photo element produced %d attachments, want 0", len(atts))
	}
}

func TestExtractAttachmentsAcceptsRealPhotoElement(t *testing.T) {
	b := &BaleCore{}
	atts := b.ExtractAttachments(map[string]interface{}{
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
