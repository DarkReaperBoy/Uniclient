package tests

import (
	"bytes"
	"errors"
	"strings"
	"testing"
	. "uniclient/cores"

	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

func TestReadFilePartWrapsRedirectFailureWithoutSwallowing(t *testing.T) {
	s := newTGScriptedServer(t)
	s.setUploadScript(tgerr.New(400, "FILE_MIGRATE_2"), nil)
	core := s.authedCore(t)
	ref := FileRef{ID: "5", MimeType: "video/mp4"}

	if _, err := core.ReadFilePart(ref, 0, 4096); err == nil {
		t.Fatal("want the scripted FILE_MIGRATE error back, got nil")
	} else {
		var rpcErr *tgerr.Error
		if !errors.As(err, &rpcErr) || rpcErr.Type != "FILE_MIGRATE" || rpcErr.Argument != 2 {
			t.Fatalf("migration error must be preserved for the engine's retry classification: %v", err)
		}
		if !strings.Contains(err.Error(), "redirect") {
			t.Errorf("error lacks redirect context — indistinguishable from a plain RPC failure: %v", err)
		}
	}
	if n := len(s.uploadRequests()); n != 2 {
		t.Fatalf("upload.getFile RPC count = %d, want 2 (original + gotd's redirected retry on the DC sub-connection)", n)
	}
	if n := s.countOf(tg.AuthExportAuthorizationRequestTypeID); n != 1 {
		t.Fatalf("auth.exportAuthorization count = %d, want 1 (gotd's DC transfer must really run before the retry)", n)
	}
}

func TestReadFilePartReturnsBytesAndForwardsRange(t *testing.T) {
	s := newTGScriptedServer(t)
	payload := bytes.Repeat([]byte{0xAB}, 4096)
	s.setUploadScript(nil, payload)
	core := s.authedCore(t)
	ref := FileRef{ID: "5", MimeType: "video/mp4"}

	got, err := core.ReadFilePart(ref, 8192, 4096)
	if err != nil {
		t.Fatalf("ReadFilePart: %v", err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("payload mismatch: got %d bytes, want %d bytes", len(got), len(payload))
	}
	reqs := s.uploadRequests()
	if len(reqs) != 1 {
		t.Fatalf("server saw %d upload.getFile requests, want 1", len(reqs))
	}
	req := reqs[0]
	if req.Offset != 8192 || req.Limit != 4096 || !req.Precise {
		t.Errorf("request = offset=%d limit=%d precise=%v, want 8192/4096/true",
			req.Offset, req.Limit, req.Precise)
	}
	loc, ok := req.Location.(*tg.InputDocumentFileLocation)
	if !ok || loc.ID != 5 {
		t.Errorf("location = %T, want *tg.InputDocumentFileLocation id=5 for video/mp4", req.Location)
	}
}
