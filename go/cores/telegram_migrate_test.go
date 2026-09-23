package cores

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/gotd/td/bin"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

// Tests-first for BUGS.md B-2 — PREMISE CORRECTION: FILE_MIGRATE is NOT
// "surfaced to the caller" in normal operation. gotd's invoker chain
// intercepts it and reruns the call on a sub-connection to the target
// DC (telegram client.go: c.invoker = chainMiddlewares(invokeDirect);
// invoke.go: FILE_MIGRATE/STATS_MIGRATE → invokeSub; sub_conns.go
// creates/reuses the DC connection). Our t.api =
// tg.NewClient(rpcGuard{next: t.client}) rides exactly that chain — and
// so do DownloadFile (downloader → same api) and the thumb path, which
// is why they cross DCs with no code of ours. What THIS repo owns is
// the surface when the redirect itself fails: the raw error must
// survive (the engine classifies read failures as retryable, F-5) and
// the message must say what happened.

// errInvoker fails every RPC with the scripted error and records the
// inputs it saw.
type errInvoker struct {
	err  error
	seen []bin.Encoder
}

func (e *errInvoker) Invoke(_ context.Context, input bin.Encoder, _ bin.Decoder) error {
	e.seen = append(e.seen, input)
	return e.err
}

// filePartInvoker answers upload.getFile with a fixed payload and
// remembers the request so tests can prove ranges are forwarded intact.
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

// newScriptedCore returns an authed TelegramCore whose every RPC lands
// in inv (the freeze-suite pattern).
func newScriptedCore(inv tg.Invoker) *TelegramCore {
	c := NewTelegramCore(TelegramConfig{})
	c.api = tg.NewClient(inv)
	c.ctx = context.Background()
	c.authed = true
	return c
}

// A FILE_MIGRATE that still reaches us means gotd's automatic DC
// redirect failed: the error must stay intact for the engine's
// retryable-read classification AND say so for whoever reads the log.
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

// The success path forwards offset/limit/precise/location exactly and
// returns the bytes untouched (regression guard for the wrap above).
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
