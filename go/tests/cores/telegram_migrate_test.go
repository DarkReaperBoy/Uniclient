package tests

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

type errInvoker struct {
	err  error
	seen []bin.Encoder
}

func (e *errInvoker) Invoke(_ context.Context, input bin.Encoder, _ bin.Decoder) error {
	e.seen = append(e.seen, input)
	return e.err
}

type filePartInvoker struct {
	payload []byte
	req     *tg.UploadGetFileRequest
	loc     tg.InputFileLocationClass
}

func (f *filePartInvoker) Invoke(_ context.Context, input bin.Encoder, output bin.Decoder) error {
	if req, ok := input.(*tg.UploadGetFileRequest); ok {
		f.req = req
		f.loc = req.Location
	}
	out, ok := output.(*tg.UploadFileBox)
	if !ok {
		return errors.New("filePartInvoker: unexpected output container")
	}
	out.File = &tg.UploadFile{Bytes: f.payload}
	return nil
}

func newScriptedCore(inv tg.Invoker) *TelegramCore {
	c := NewTelegramCore(TelegramConfig{})
	c.ForTestSetApi(tg.NewClient(inv))
	c.ForTestSetCtx(context.Background())
	c.ForTestSetAuthed(true)
	return c
}

func TestReadFilePartWrapsRedirectFailureWithoutSwallowing(t *testing.T) {
	mig := tgerr.New(400, "FILE_MIGRATE_2")
	inv := &errInvoker{err: mig}
	c := newScriptedCore(inv)
	ref := FileRef{ID: "5", MimeType: "video/mp4"}

	if _, err := c.ReadFilePart(ref, 0, 4096); err == nil {
		t.Fatal("want the scripted FILE_MIGRATE error back, got nil")
	} else {
		if !errors.Is(err, mig) {
			t.Fatalf("migration error must be preserved for the engine's retry classification: %v", err)
		}
		if !strings.Contains(err.Error(), "redirect") {
			t.Errorf("error lacks redirect context — indistinguishable from a plain RPC failure: %v", err)
		}
	}
	if len(inv.seen) != 1 {
		t.Fatalf("RPC count = %d, want 1", len(inv.seen))
	}
}

func TestReadFilePartReturnsBytesAndForwardsRange(t *testing.T) {
	payload := bytes.Repeat([]byte{0xAB}, 4096)
	inv := &filePartInvoker{payload: payload}
	c := newScriptedCore(inv)
	ref := FileRef{ID: "5", MimeType: "video/mp4"}

	got, err := c.ReadFilePart(ref, 8192, 4096)
	if err != nil {
		t.Fatalf("ReadFilePart: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("payload mismatch: got %d bytes, want %d", len(got), len(payload))
	}
	if inv.req == nil {
		t.Fatal("invoker never saw upload.getFile")
	}
	if inv.req.Offset != 8192 || inv.req.Limit != 4096 || !inv.req.Precise {
		t.Errorf("request = offset=%d limit=%d precise=%v, want 8192/4096/true",
			inv.req.Offset, inv.req.Limit, inv.req.Precise)
	}
	if _, ok := inv.loc.(*tg.InputDocumentFileLocation); !ok {
		t.Errorf("location = %T, want *tg.InputDocumentFileLocation for video/mp4", inv.loc)
	}
}
