package cores

// tests-first for slice 228 — the ranged-read half of row 281. The RPC
// itself needs a live DC (owner's rung), but everything the streaming
// path depends on before the wire is testable here: location resolution
// (document vs photo vs gif, Extra fallback, cache round-trip) and the
// request validation that keeps malformed ranges off the network.

import (
	"errors"
	"testing"

	"github.com/gotd/td/tg"
)

func TestFileLocationOfDocument(t *testing.T) {
	c := &TelegramCore{}
	loc, err := c.fileLocationOf(FileRef{
		ID:       "5",
		MimeType: "video/mp4",
		Extra:    "777:Zm9v", // accessHash 777, file ref "foo"
	})
	if err != nil {
		t.Fatalf("fileLocationOf: %v", err)
	}
	doc, ok := loc.(*tg.InputDocumentFileLocation)
	if !ok {
		t.Fatalf("got %T, want *InputDocumentFileLocation", loc)
	}
	if doc.ID != 5 {
		t.Errorf("ID = %d, want 5", doc.ID)
	}
	if doc.AccessHash != 777 {
		t.Errorf("AccessHash = %d, want 777 (decoded from Extra)", doc.AccessHash)
	}
	if string(doc.FileReference) != "foo" {
		t.Errorf("FileReference = %q, want %q", doc.FileReference, "foo")
	}

	// The Extra decode must have been cached: a second resolve without
	// Extra still finds the hash (this is how the engine's later reads
	// of the same file skip re-parsing).
	loc2, err := c.fileLocationOf(FileRef{ID: "5", MimeType: "video/mp4"})
	if err != nil {
		t.Fatalf("second resolve: %v", err)
	}
	if d2, ok := loc2.(*tg.InputDocumentFileLocation); !ok || d2.AccessHash != 777 {
		t.Errorf("cached resolve = %v, want document with AccessHash 777", loc2)
	}
}

func TestFileLocationOfPhotoAndGif(t *testing.T) {
	c := &TelegramCore{}
	// A photo resolves to the photo location at the largest thumb size.
	loc, err := c.fileLocationOf(FileRef{ID: "9", MimeType: "image/jpeg", Extra: "42:"})
	if err != nil {
		t.Fatalf("photo: %v", err)
	}
	if ph, ok := loc.(*tg.InputPhotoFileLocation); !ok {
		t.Errorf("image/jpeg resolved to %T, want *InputPhotoFileLocation", loc)
	} else if ph.ThumbSize != "y" {
		t.Errorf("ThumbSize = %q, want \"y\" (largest)", ph.ThumbSize)
	}

	// image/gif is a document despite the image/ prefix.
	loc, err = c.fileLocationOf(FileRef{ID: "11", MimeType: "image/gif", Extra: "42:"})
	if err != nil {
		t.Fatalf("gif: %v", err)
	}
	if _, ok := loc.(*tg.InputDocumentFileLocation); !ok {
		t.Errorf("image/gif resolved to %T, want *InputDocumentFileLocation", loc)
	}
}

func TestFileLocationOfRejectsEmptyID(t *testing.T) {
	c := &TelegramCore{}
	if _, err := c.fileLocationOf(FileRef{ID: "0", MimeType: "video/mp4"}); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("empty ID: err = %v, want ErrInvalidInput", err)
	}
}

// TestReadFilePartValidatesRange: malformed ranges fail locally, before
// withAPI (these cores are not connected here — getting the validation
// error rather than a connection error is the point).
func TestReadFilePartValidatesRange(t *testing.T) {
	c := &TelegramCore{}
	ref := FileRef{ID: "5", MimeType: "video/mp4"}

	if _, err := c.ReadFilePart(ref, -1, 4096); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("negative offset: err = %v, want ErrInvalidInput", err)
	}
	if _, err := c.ReadFilePart(ref, 0, 0); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("zero limit: err = %v, want ErrInvalidInput", err)
	}
	// 4096-alignment is the upload.getFile rule the engine relies on;
	// an unaligned request must be rejected here, not at the layer.
	if _, err := c.ReadFilePart(ref, 100, 4096); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("unaligned offset: err = %v, want ErrInvalidInput", err)
	}
	if _, err := c.ReadFilePart(ref, 512<<10, 4096); err == nil {
		t.Errorf("aligned offset on a disconnected core: got nil, want a connection error (validation passed through)")
	}
}
