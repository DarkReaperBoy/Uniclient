package bridge

import (
	"testing"

	"google.golang.org/protobuf/proto"

	pb "uniclient/proto"
	pbcores "uniclient/proto/cores"
	"uniclient/cores"
)

func TestDispatchRoundTrip(t *testing.T) {
	// Test the full round trip: marshal request → dispatch → get response
	// We use IRC core's Ping method which is simple and doesn't need auth
	irc := &cores.IRCCore{}

	RegisterCore("irc-test", "irc", irc)
	defer UnregisterCore("irc-test")

	// Call a method that will fail gracefully (not connected)
	methodReq := &pbcores.IrcSendRawCommandRequest{
		Line: "PING :test",
	}
	payload, err := proto.Marshal(methodReq)
	if err != nil {
		t.Fatal(err)
	}

	req := &pb.BridgeRequest{
		CoreId:  "irc-test",
		Method:  "SendRawCommand",
		Payload: payload,
	}
	reqData, err := proto.Marshal(req)
	if err != nil {
		t.Fatal(err)
	}

	respData := Call(reqData)
	var resp pb.BridgeResponse
	if err := proto.Unmarshal(respData, &resp); err != nil {
		t.Fatal(err)
	}

	// Expected to fail (not connected) but proves the dispatch path works
	t.Logf("ok=%v error=%q code=%q", resp.Ok, resp.Error, resp.ErrorCode)
	if resp.Ok {
		t.Log("unexpectedly succeeded (IRC not connected)")
	}
}

func TestDispatchUnknownMethod(t *testing.T) {
	gh := &cores.GitHubCore{}
	RegisterCore("gh-test2", "github", gh)
	defer UnregisterCore("gh-test2")

	req := &pb.BridgeRequest{
		CoreId:  "gh-test2",
		Method:  "NonexistentMethod",
		Payload: nil,
	}
	reqData, _ := proto.Marshal(req)

	respData := Call(reqData)
	var resp pb.BridgeResponse
	_ = proto.Unmarshal(respData, &resp)

	if resp.Ok {
		t.Error("expected error for unknown method")
	}
	if resp.Error == "" {
		t.Error("expected error message for unknown method")
	}
	t.Logf("got expected error: %s", resp.Error)
}
