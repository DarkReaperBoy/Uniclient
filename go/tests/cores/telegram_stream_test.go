package tests

import (
	"errors"
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
)

func TestFileLocationOfDocument(t *testing.T) {
	c := &TelegramCore{}
	loc, err := c.FileLocationOf(FileRef{
		ID:       "5",
		MimeType: "video/mp4",
		Extra:    "777:Zm9v",
	})
	if err != nil {
		t.Fatalf("FileLocationOf: %v", err)
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

	loc2, err := c.FileLocationOf(FileRef{ID: "5", MimeType: "video/mp4"})
	if err != nil {
		t.Fatalf("second resolve: %v", err)
	}
	if d2, ok := loc2.(*tg.InputDocumentFileLocation); !ok || d2.AccessHash != 777 {
		t.Errorf("cached resolve = %v, want document with AccessHash 777", loc2)
	}
}

func TestFileLocationOfPhotoAndGif(t *testing.T) {
	c := &TelegramCore{}
	loc, err := c.FileLocationOf(FileRef{ID: "9", MimeType: "image/jpeg", Extra: "42:"})
	if err != nil {
		t.Fatalf("photo: %v", err)
	}
	if ph, ok := loc.(*tg.InputPhotoFileLocation); !ok {
		t.Errorf("image/jpeg resolved to %T, want *InputPhotoFileLocation", loc)
	} else if ph.ThumbSize != "y" {
		t.Errorf("ThumbSize = %q, want \"y\" (largest)", ph.ThumbSize)
	}

	loc, err = c.FileLocationOf(FileRef{ID: "11", MimeType: "image/gif", Extra: "42:"})
	if err != nil {
		t.Fatalf("gif: %v", err)
	}
	if _, ok := loc.(*tg.InputDocumentFileLocation); !ok {
		t.Errorf("image/gif resolved to %T, want *InputDocumentFileLocation", loc)
	}
}

func TestFileLocationOfRejectsEmptyID(t *testing.T) {
	c := &TelegramCore{}
	if _, err := c.FileLocationOf(FileRef{ID: "0", MimeType: "video/mp4"}); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("empty ID: err = %v, want ErrInvalidInput", err)
	}
}

func TestReadFilePartValidatesRange(t *testing.T) {
	c := &TelegramCore{}
	ref := FileRef{ID: "5", MimeType: "video/mp4"}

	if _, err := c.ReadFilePart(ref, -1, 4096); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("negative offset: err = %v, want ErrInvalidInput", err)
	}
	if _, err := c.ReadFilePart(ref, 0, 0); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("zero limit: err = %v, want ErrInvalidInput", err)
	}
	if _, err := c.ReadFilePart(ref, 100, 4096); !errors.Is(err, ErrInvalidInput) {
		t.Errorf("unaligned offset: err = %v, want ErrInvalidInput", err)
	}
	if _, err := c.ReadFilePart(ref, 512<<10, 4096); err == nil {
		t.Errorf("aligned offset on a disconnected core: got nil, want a connection error (validation passed through)")
	}
}
