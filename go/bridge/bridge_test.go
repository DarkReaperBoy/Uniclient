package bridge

import (
	"testing"

	"google.golang.org/protobuf/proto"

	pb "uniclient/proto"
)

func TestCallUnknownCore(t *testing.T) {
	req := &pb.BridgeRequest{
		CoreId: "nonexistent",
		Method: "Ping",
	}
	data, err := proto.Marshal(req)
	if err != nil {
		t.Fatal(err)
	}

	respData := Call(data)
	var resp pb.BridgeResponse
	if err := proto.Unmarshal(respData, &resp); err != nil {
		t.Fatal(err)
	}

	if resp.Ok {
		t.Error("expected error response for unknown core")
	}
	if resp.Error == "" {
		t.Error("expected error message")
	}
	t.Logf("got expected error: %s", resp.Error)
}

func TestCallInvalidRequest(t *testing.T) {
	respData := Call([]byte{0xff, 0xff})
	var resp pb.BridgeResponse
	if err := proto.Unmarshal(respData, &resp); err != nil {
		t.Fatal(err)
	}

	if resp.Ok {
		t.Error("expected error for invalid request")
	}
	t.Logf("got expected error: %s", resp.Error)
}

func TestErrorCategorization(t *testing.T) {
	tests := []struct {
		msg  string
		code string
	}{
		{"FLOOD_WAIT_300", "auth"},
		{"connection refused", "network"},
		{"context deadline exceeded", "timeout"},
		{"404 not found", "not_found"},
		{"rate limit exceeded", "rate_limited"},
		{"permission denied", "permission"},
		{"not implemented", "not_supported"},
		{"something random", "unknown"},
	}

	for _, tt := range tests {
		code := categorizeError(errString(tt.msg))
		if code != tt.code {
			t.Errorf("categorizeError(%q) = %q, want %q", tt.msg, code, tt.code)
		}
	}
}

type errString string

func (e errString) Error() string { return string(e) }
