package bridge

import (
	"path/filepath"
	"testing"

	"google.golang.org/protobuf/proto"

	pb "uniclient/proto"
)

// callBridge mirrors the FFI host path: serialize a BridgeRequest, dispatch
// through bridge.Call (what BridgeCallWithLen / bridgeCall invoke), decode
// the BridgeResponse.
func callBridge(t *testing.T, coreID, method string, payload []byte) *pb.BridgeResponse {
	t.Helper()
	req := &pb.BridgeRequest{CoreId: coreID, Method: method, Payload: payload}
	reqData, err := proto.Marshal(req)
	if err != nil {
		t.Fatalf("marshal request %s: %v", method, err)
	}
	respData := Call(reqData)
	if len(respData) == 0 {
		t.Fatalf("bridge.Call(%s) returned empty bytes", method)
	}
	var resp pb.BridgeResponse
	if err := proto.Unmarshal(respData, &resp); err != nil {
		t.Fatalf("unmarshal response %s: %v", method, err)
	}
	return &resp
}

func initTestEngine(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cfgDir := filepath.Join(dir, "config")
	cacheDir := filepath.Join(dir, "cache")
	dlDir := filepath.Join(dir, "download")

	req := &pb.EngineInitRequest{
		ConfigDir:     cfgDir,
		CacheDir:      cacheDir,
		DownloadDir:   dlDir,
		VaultPassword: "test-password",
	}
	payload, err := proto.Marshal(req)
	if err != nil {
		t.Fatal(err)
	}
	resp := callBridge(t, "__engine", "Init", payload)
	if !resp.Ok {
		t.Fatalf("Init failed: %s", resp.Error)
	}

	t.Cleanup(func() {
		callBridge(t, "__engine", "Shutdown", nil)
	})
	return cfgDir
}

func TestBridgeInvalidRequestBytes(t *testing.T) {
	// 0xFF is never a valid protobuf field header.
	respData := Call([]byte{0xFF, 0xFF, 0xFF})
	if len(respData) == 0 {
		t.Fatal("no error response for invalid bytes")
	}
	var resp pb.BridgeResponse
	if err := proto.Unmarshal(respData, &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if resp.Ok {
		t.Fatal("invalid request bytes produced an Ok response")
	}
	if resp.Error == "" {
		t.Fatal("error message is empty")
	}
}

func TestBridgeUnknownCore(t *testing.T) {
	resp := callBridge(t, "no-such-core", "Whatever", nil)
	if resp.Ok {
		t.Fatal("unknown core_id returned Ok")
	}
	if resp.Error == "" {
		t.Fatal("error message is empty")
	}
}

func TestBridgeUnknownEngineMethod(t *testing.T) {
	initTestEngine(t)
	resp := callBridge(t, "__engine", "NoSuchMethodExists", nil)
	if resp.Ok {
		t.Fatal("unknown engine method returned Ok")
	}
}

func TestBridgeEngineNotInitialized(t *testing.T) {
	// Reset the global engine to nil to simulate a call before Init.
	saved := engineInstance
	engineInstance = nil
	t.Cleanup(func() { engineInstance = saved })

	resp := callBridge(t, "__engine", "ListAccounts", nil)
	if resp.Ok {
		t.Fatal("ListAccounts before Init returned Ok")
	}
}

func TestBridgeEngineLifecycle(t *testing.T) {
	initTestEngine(t)

	// ListAccounts starts empty.
	resp := callBridge(t, "__engine", "ListAccounts", nil)
	if !resp.Ok {
		t.Fatalf("ListAccounts: %s", resp.Error)
	}
	var list pb.EngineListAccountsResponse
	if err := proto.Unmarshal(resp.Payload, &list); err != nil {
		t.Fatalf("unmarshal ListAccounts: %v", err)
	}
	if len(list.Accounts) != 0 {
		t.Fatalf("fresh engine has %d accounts, want 0", len(list.Accounts))
	}

	// AddAccount.
	addReq := &pb.EngineAddAccountRequest{Platform: "github"}
	addPayload, err := proto.Marshal(addReq)
	if err != nil {
		t.Fatal(err)
	}
	resp = callBridge(t, "__engine", "AddAccount", addPayload)
	if !resp.Ok {
		t.Fatalf("AddAccount: %s", resp.Error)
	}
	var addResp pb.EngineAddAccountResponse
	if err := proto.Unmarshal(resp.Payload, &addResp); err != nil {
		t.Fatalf("unmarshal AddAccount: %v", err)
	}
	if addResp.AccountId == "" {
		t.Fatal("AddAccount returned an empty account id")
	}

	// ListAccounts now contains it.
	resp = callBridge(t, "__engine", "ListAccounts", nil)
	if !resp.Ok {
		t.Fatalf("ListAccounts after add: %s", resp.Error)
	}
	if err := proto.Unmarshal(resp.Payload, &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Accounts) != 1 {
		t.Fatalf("engine has %d accounts, want 1", len(list.Accounts))
	}
	if list.Accounts[0].Platform != "github" {
		t.Fatalf("platform = %q, want github", list.Accounts[0].Platform)
	}
	if list.Accounts[0].Id != addResp.AccountId {
		t.Fatalf("account id mismatch: %q vs %q", list.Accounts[0].Id, addResp.AccountId)
	}

	// RemoveAccount.
	rmReq := &pb.EngineRemoveAccountRequest{AccountId: addResp.AccountId}
	rmPayload, err := proto.Marshal(rmReq)
	if err != nil {
		t.Fatal(err)
	}
	resp = callBridge(t, "__engine", "RemoveAccount", rmPayload)
	if !resp.Ok {
		t.Fatalf("RemoveAccount: %s", resp.Error)
	}

	// Back to empty.
	resp = callBridge(t, "__engine", "ListAccounts", nil)
	if !resp.Ok {
		t.Fatalf("ListAccounts after remove: %s", resp.Error)
	}
	if err := proto.Unmarshal(resp.Payload, &list); err != nil {
		t.Fatal(err)
	}
	if len(list.Accounts) != 0 {
		t.Fatalf("engine has %d accounts after removal, want 0", len(list.Accounts))
	}
}

func TestBridgeEnginePersistsAcrossInit(t *testing.T) {
	dir := t.TempDir()
	cfgDir := filepath.Join(dir, "config")

	initPayload := func() []byte {
		req := &pb.EngineInitRequest{
			ConfigDir:     cfgDir,
			CacheDir:      filepath.Join(dir, "cache"),
			DownloadDir:   filepath.Join(dir, "download"),
			VaultPassword: "test-password",
		}
		payload, err := proto.Marshal(req)
		if err != nil {
			t.Fatal(err)
		}
		return payload
	}

	// First init + one account.
	resp := callBridge(t, "__engine", "Init", initPayload())
	if !resp.Ok {
		t.Fatalf("first Init: %s", resp.Error)
	}
	addReq := &pb.EngineAddAccountRequest{Platform: "irc"}
	addPayload, err := proto.Marshal(addReq)
	if err != nil {
		t.Fatal(err)
	}
	resp = callBridge(t, "__engine", "AddAccount", addPayload)
	if !resp.Ok {
		t.Fatalf("AddAccount: %s", resp.Error)
	}
	var addResp pb.EngineAddAccountResponse
	if err := proto.Unmarshal(resp.Payload, &addResp); err != nil {
		t.Fatal(err)
	}

	callBridge(t, "__engine", "Shutdown", nil)

	// Re-init on the same config dir: the account must survive (vault is
	// the source of truth, offline-first).
	resp = callBridge(t, "__engine", "Init", initPayload())
	if !resp.Ok {
		t.Fatalf("second Init: %s", resp.Error)
	}
	defer callBridge(t, "__engine", "Shutdown", nil)

	resp = callBridge(t, "__engine", "ListAccounts", nil)
	if !resp.Ok {
		t.Fatalf("ListAccounts: %s", resp.Error)
	}
	var list pb.EngineListAccountsResponse
	if err := proto.Unmarshal(resp.Payload, &list); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, a := range list.Accounts {
		if a.Id == addResp.AccountId && a.Platform == "irc" {
			found = true
		}
	}
	if !found {
		t.Fatalf("account %q (irc) did not survive re-init: %v", addResp.AccountId, list.Accounts)
	}
}

func TestCategorizeError(t *testing.T) {
	cases := []struct {
		msg  string
		want string
	}{
		{"FLOOD_WAIT_30", "rate_limited"},
		{"rpc: SESSION_EXPIRED", "auth"},
		{"dial tcp: connection refused", "network"},
		{"context deadline exceeded", "timeout"},
		{"message not found", "not_found"},
		{"CHAT_ADMIN_REQUIRED", "permission"},
		{"feature not supported yet", "not_supported"},
		{"something weird", "unknown"},
	}
	for _, c := range cases {
		if got := categorizeError(errorString(c.msg)); got != c.want {
			t.Errorf("categorizeError(%q) = %q, want %q", c.msg, got, c.want)
		}
	}
}

type errorString string

func (e errorString) Error() string { return string(e) }
