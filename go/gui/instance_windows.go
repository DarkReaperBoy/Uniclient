//go:build windows

package gui

// instance_windows.go — slice 202: toast click-through activation.
// Windows toasts activate through the shell, not a Go callback: the
// toast XML carries activationType="protocol" launch="uniclient://open"
// (toastxml.go), this file registers the uniclient:// scheme for the
// current user (HKCU\Software\Classes — no elevation, the tdesktop-
// faithful single-binary path; the WinRT COM activator alternative
// would need a separate in-proc DLL, banned by §1.3), and a tiny
// single-instance command channel forwards the click to the running
// app:
//
//   - ServeInstanceCommands (boot, main window): registers the scheme,
//     listens on 127.0.0.1:<ephemeral>, writes <config>/instance.lock
//     ("port cookie"), and routes a launch URI captured at start-up
//     once an account exists.
//   - HandleLaunchURI (before engine boot): a launcher process holding
//     a uniclient:// arg forwards it to the running instance (lockfile
//     → dial → "open cookie uri" line) and exits; with no live
//     instance it returns false so the app boots and routes the URI.
//   - The accept loop hops the open onto the GUI goroutine through the
//     existing pendingOpen path + ActionRaise (the same surface the
//     Linux DBus banner click uses).
//
// Pure-Go all the way: registry via x/sys, transport via net. Failures
// are log-only (toasts still render; the in-app banner remains a click
// surface — never a crash, §1.10).

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows/registry"
)

var (
	instanceMu       sync.Mutex
	instanceLn       net.Listener
	instanceLockPath string
	instanceCookie   string
	instanceApp      *App
	instanceBootURI  string
)

// HandleLaunchURI scans launcher args for a uniclient://open URI. When
// a running instance owns the command channel it forwards the open and
// returns true (the caller should exit — the toast click is served).
// Otherwise the URI is kept for post-boot routing and false returns
// (normal start-up). Called before the engine boots: forwarding must
// not pay the engine/SQLite init cost.
func HandleLaunchURI(args []string, configDir string) bool {
	uri := ""
	for _, arg := range args {
		if isLaunchURI(arg) {
			uri = arg
			break
		}
	}
	if uri == "" {
		return false
	}
	if _, _, ok := parseOpenURI(uri); !ok {
		return false
	}
	if forwardOpenURI(configDir, uri) {
		return true
	}
	instanceMu.Lock()
	instanceBootURI = uri
	instanceMu.Unlock()
	return false
}

// ServeInstanceCommands wires the running app into the click-through
// channel: scheme registration, the command listener, the lockfile, and
// any boot-time launch URI. Main window only, once, right after Start.
func (a *App) ServeInstanceCommands(configDir string) {
	instanceMu.Lock()
	instanceApp = a
	instanceMu.Unlock()

	// Per-user protocol registration (idempotent rewrite — picks up an
	// exe that moved; log-only on failure: toasts still render, the
	// click just falls back to the in-app banner).
	if exe, err := os.Executable(); err == nil {
		if err := registerProtocolHandler(exe); err != nil {
			log.Printf("gui: instance: protocol register: %v", err)
		}
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Printf("gui: instance: listen: %v", err)
		return
	}
	cookie := make([]byte, 8)
	if _, err := rand.Read(cookie); err != nil {
		ln.Close()
		log.Printf("gui: instance: cookie: %v", err)
		return
	}
	lockPath := filepath.Join(configDir, "instance.lock")
	line := fmt.Sprintf("%d %s\n", ln.Addr().(*net.TCPAddr).Port, hex.EncodeToString(cookie))
	tmp := lockPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(line), 0o600); err != nil {
		ln.Close()
		log.Printf("gui: instance: lockfile: %v", err)
		return
	}
	if err := os.Rename(tmp, lockPath); err != nil {
		ln.Close()
		log.Printf("gui: instance: lockfile: %v", err)
		return
	}
	instanceMu.Lock()
	instanceLn = ln
	instanceLockPath = lockPath
	instanceCookie = hex.EncodeToString(cookie)
	instanceMu.Unlock()
	go instanceAcceptLoop(ln)

	// A launch URI from a cold start (no running instance was alive):
	// route it once an account exists — before that the open has no
	// target (fresh login lands on the auth flow; the URI is moot).
	if uri := instanceBootURI; uri != "" {
		go routeBootURI(a, uri)
	}
}

// stopInstanceServer closes the command channel (Shutdown path; the
// taskbar/tray release order — main window owns it).
func stopInstanceServer() {
	instanceMu.Lock()
	defer instanceMu.Unlock()
	if instanceLn != nil {
		instanceLn.Close()
		instanceLn = nil
	}
	if instanceLockPath != "" {
		os.Remove(instanceLockPath)
		instanceLockPath = ""
	}
	instanceApp = nil
}

// instanceAcceptLoop serves one command line per connection.
func instanceAcceptLoop(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return // listener closed (shutdown)
		}
		go instanceServeConn(conn)
	}
}

// instanceServeConn reads "open <cookie> <uri>" and hops the open onto
// the GUI goroutine. Anything malformed is dropped silently — the
// channel is localhost-only and best-effort by design.
func instanceServeConn(conn net.Conn) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(3 * time.Second))
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil && line == "" {
		return
	}
	fields := strings.Fields(strings.TrimSpace(line))
	if len(fields) != 3 || fields[0] != "open" {
		return
	}
	instanceMu.Lock()
	cookie, app := instanceCookie, instanceApp
	instanceMu.Unlock()
	if cookie == "" || app == nil || fields[1] != cookie {
		return
	}
	acc, chat, ok := parseOpenURI(fields[2])
	if !ok {
		return
	}
	// The same hop the Linux DBus banner click takes: raise + open on
	// the GUI loop.
	notifyOpenAction(app, chatKey{AccountID: acc, ChatID: chat}, "")("")
	conn.Write([]byte("ok\n"))
}

// routeBootURI waits for a logged-in account (up to 2 minutes), then
// opens the target chat.
func routeBootURI(a *App, uri string) {
	deadline := time.Now().Add(2 * time.Minute)
	for time.Now().Before(deadline) {
		a.mu.Lock()
		n := len(a.accounts)
		a.mu.Unlock()
		if n > 0 {
			if acc, chat, ok := parseOpenURI(uri); ok {
				notifyOpenAction(a, chatKey{AccountID: acc, ChatID: chat}, "")("")
			}
			return
		}
		time.Sleep(500 * time.Millisecond)
	}
}

// forwardOpenURI sends the open command to the running instance.
// Returns false when there is no live listener (stale lockfile or cold
// start) — the caller boots normally instead.
func forwardOpenURI(configDir, uri string) bool {
	data, err := os.ReadFile(filepath.Join(configDir, "instance.lock"))
	if err != nil {
		return false
	}
	fields := strings.Fields(string(data))
	if len(fields) != 2 {
		return false
	}
	if _, err := strconv.Atoi(fields[0]); err != nil {
		return false
	}
	conn, err := net.DialTimeout("tcp", "127.0.0.1:"+fields[0], 700*time.Millisecond)
	if err != nil {
		return false
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := fmt.Fprintf(conn, "open %s %s\n", fields[1], uri); err != nil {
		return false
	}
	// Wait for the ack so the command is committed before exit.
	buf := make([]byte, 64)
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	conn.Read(buf)
	return true
}

// registerProtocolHandler maps the uniclient:// scheme to the binary
// for the current user (HKCU — no elevation): URL Protocol + the
// shell\open\command that re-launches us with the URI as the argument.
func registerProtocolHandler(exe string) error {
	const root = `Software\Classes\` + openURIScheme
	k, _, err := registry.CreateKey(registry.CURRENT_USER, root, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if err := k.SetStringValue("", "URL: Uniclient"); err != nil {
		return err
	}
	if err := k.SetStringValue("URL Protocol", ""); err != nil {
		return err
	}
	icon, _, err := registry.CreateKey(registry.CURRENT_USER, root+`\DefaultIcon`, registry.SET_VALUE)
	if err != nil {
		return err
	}
	if err := icon.SetStringValue("", exe+",0"); err != nil {
		icon.Close()
		return err
	}
	icon.Close()
	cmd, _, err := registry.CreateKey(registry.CURRENT_USER, root+`\shell\open\command`, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer cmd.Close()
	return cmd.SetStringValue("", `"`+exe+`" "%1"`)
}
