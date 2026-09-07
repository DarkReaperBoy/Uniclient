// Command uniclient-cli is a headless host for the Uniclient engine.
//
// It links the bridge in-process (same code path the c-shared and wasm
// builds expose) and drives it from the command line. Use it to exercise
// the engine without a GUI frontend: account management, engine state, and
// raw bridge calls for debugging.
//
// Examples:
//
//	uniclient-cli init ~/.config/uniclient
//	uniclient-cli add telegram
//	uniclient-cli accounts
//	uniclient-cli raw __engine ListAccounts < request.bin
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"google.golang.org/protobuf/proto"

	"uniclient/bridge"
	pb "uniclient/proto"
)

const usage = `uniclient-cli — headless host for the Uniclient engine

Usage:
  uniclient-cli init [configDir] [password]  initialize/open the engine
  uniclient-cli add <platform>               add an account (telegram, github,
                                             irc, matrix, xmpp, bale, rubika,
                                             deltachat, mumble, teamspeak)
  uniclient-cli remove <accountId>           remove an account
  uniclient-cli accounts                     list accounts
  uniclient-cli status                       engine status
  uniclient-cli raw <coreId> <method>        raw bridge call; request payload
                                             (bytes) read from stdin, response
                                             payload bytes written to stdout
  uniclient-cli shutdown                     save state and stop

The engine state lives under <configDir> (vault + cache + downloads),
defaulting to $UNICLIENT_HOME or ~/.uniclient.
The vault password defaults to $UNICLIENT_PASSWORD or "uniclient-cli".`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}

	cmd := os.Args[1]
	switch cmd {
	case "help", "-h", "--help":
		fmt.Println(usage)
		return
	case "init", "add", "remove", "accounts", "status", "raw", "shutdown":
		if err := run(cmd, os.Args[2:]); err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n%s\n", cmd, usage)
		os.Exit(2)
	}
}

func defaultHome() (string, error) {
	base := os.Getenv("UNICLIENT_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("no UNICLIENT_HOME and no home dir: %w", err)
		}
		base = filepath.Join(home, ".uniclient")
	}
	return base, nil
}

func vaultPassword() string {
	if p := os.Getenv("UNICLIENT_PASSWORD"); p != "" {
		return p
	}
	return "uniclient-cli"
}

// initEngine opens (or creates) the engine through the bridge — the exact
// same call path a real host uses.
func initEngine(args []string) (dir string, err error) {
	dir, err = defaultHome()
	if len(args) > 0 {
		dir = args[0]
	}
	if err != nil {
		return dir, err
	}

	password := vaultPassword()
	if len(args) > 1 {
		password = args[1]
	}

	req := &pb.EngineInitRequest{
		ConfigDir:     dir,
		CacheDir:      filepath.Join(dir, "cache"),
		DownloadDir:   filepath.Join(dir, "downloads"),
		VaultPassword: password,
	}
	payload, err := proto.Marshal(req)
	if err != nil {
		return dir, err
	}
	res, err := bridgeCall("__engine", "Init", payload)
	if err != nil {
		return dir, err
	}
	var initResp pb.EngineInitResponse
	if err := proto.Unmarshal(res.resp.GetPayload(), &initResp); err != nil {
		return dir, fmt.Errorf("parse init response: %w", err)
	}
	if !initResp.Ok {
		return dir, fmt.Errorf("init failed: %s", initResp.Error)
	}
	return dir, nil
}

type bridgeResult struct{ resp *pb.BridgeResponse }

// bridgeCall performs one request/response cycle through the bridge.
func bridgeCall(coreID, method string, payload []byte) (*bridgeResult, error) {
	req := &pb.BridgeRequest{CoreId: coreID, Method: method, Payload: payload}
	reqData, err := proto.Marshal(req)
	if err != nil {
		return nil, err
	}
	respData := bridge.Call(reqData)
	var resp pb.BridgeResponse
	if err := proto.Unmarshal(respData, &resp); err != nil {
		return nil, fmt.Errorf("parse bridge response: %w", err)
	}
	if !resp.Ok {
		return &bridgeResult{resp: &resp}, fmt.Errorf("%s: %s", method, resp.Error)
	}
	return &bridgeResult{resp: &resp}, nil
}

func run(cmd string, args []string) error {
	switch cmd {
	case "init":
		dir, err := initEngine(args)
		if err != nil {
			return err
		}
		fmt.Printf("engine ready at %s\n", dir)
		_, err = bridgeCall("__engine", "Shutdown", nil)
		return err

	case "add":
		if len(args) < 1 {
			return fmt.Errorf("add requires a platform")
		}
		platform := strings.ToLower(args[0])
		if _, err := initEngine(nil); err != nil {
			return err
		}
		req := &pb.EngineAddAccountRequest{Platform: platform}
		payload, err := proto.Marshal(req)
		if err != nil {
			return err
		}
		res, err := bridgeCall("__engine", "AddAccount", payload)
		if err != nil {
			return err
		}
		var addResp pb.EngineAddAccountResponse
		if err := proto.Unmarshal(res.resp.GetPayload(), &addResp); err != nil {
			return err
		}
		fmt.Printf("added %s account: %s\n", platform, addResp.AccountId)
		_, _ = bridgeCall("__engine", "Shutdown", nil)
		return nil

	case "remove":
		if len(args) < 1 {
			return fmt.Errorf("remove requires an account id")
		}
		if _, err := initEngine(nil); err != nil {
			return err
		}
		req := &pb.EngineRemoveAccountRequest{AccountId: args[0]}
		payload, err := proto.Marshal(req)
		if err != nil {
			return err
		}
		if _, err := bridgeCall("__engine", "RemoveAccount", payload); err != nil {
			return err
		}
		fmt.Printf("removed %s\n", args[0])
		_, _ = bridgeCall("__engine", "Shutdown", nil)
		return nil

	case "accounts":
		if _, err := initEngine(nil); err != nil {
			return err
		}
		res, err := bridgeCall("__engine", "ListAccounts", nil)
		if err != nil {
			return err
		}
		var list pb.EngineListAccountsResponse
		if err := proto.Unmarshal(res.resp.GetPayload(), &list); err != nil {
			return err
		}
		if len(list.Accounts) == 0 {
			fmt.Println("no accounts")
		}
		for _, a := range list.Accounts {
			state := "offline"
			switch a.ConnState {
			case 1:
				state = "connecting"
			case 2:
				state = "online"
			}
			fmt.Printf("%s\t%s\t%s\n", a.Id, a.Platform, state)
		}
		_, _ = bridgeCall("__engine", "Shutdown", nil)
		return nil

	case "status":
		dir, err := initEngine(nil)
		if err != nil {
			return err
		}
		res, err := bridgeCall("__engine", "ListAccounts", nil)
		if err != nil {
			return err
		}
		var list pb.EngineListAccountsResponse
		if err := proto.Unmarshal(res.resp.GetPayload(), &list); err != nil {
			return err
		}
		fmt.Printf("engine     : running (%s)\n", dir)
		fmt.Printf("accounts   : %d\n", len(list.Accounts))
		for _, a := range list.Accounts {
			fmt.Printf("  - %s [%s]\n", a.Id, a.Platform)
		}
		fmt.Printf("as of      : %s\n", time.Now().Format(time.RFC3339))
		_, _ = bridgeCall("__engine", "Shutdown", nil)
		return nil

	case "raw":
		if len(args) < 2 {
			return fmt.Errorf("raw requires <coreId> <method>")
		}
		if _, err := initEngine(nil); err != nil {
			return err
		}
		payload, err := io.ReadAll(os.Stdin)
		if err != nil {
			return err
		}
		res, err := bridgeCall(args[0], args[1], payload)
		if err != nil {
			return err
		}
		if _, err := os.Stdout.Write(res.resp.GetPayload()); err != nil {
			return err
		}
		_, _ = bridgeCall("__engine", "Shutdown", nil)
		return nil

	case "shutdown":
		if _, err := initEngine(nil); err != nil {
			return err
		}
		_, err := bridgeCall("__engine", "Shutdown", nil)
		return err
	}
	return fmt.Errorf("unreachable")
}
